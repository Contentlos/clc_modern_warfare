local Config = MW.require('shared/config.lua')
local Constants = MW.require('shared/constants.lua')
local Utils = MW.require('shared/utils.lua')
local WarState = MW.require('server/warstate.lua')

local Vehicles = {}
local registry = {}
local spawnedRegistry = {}
local destroyedCount = {}
local depotCooldowns = {}
local vehicleCooldowns = {}
local recentRequestIds = {}
local spawnLocks = {}

local function now()
  return Utils.now()
end

local function getTimeMs()
  return GetGameTimer()
end

local function cleanupRecent(src, nowMs)
  local list = recentRequestIds[src]
  if not list then return end
  for id, ts in pairs(list) do
    if (nowMs - ts) > 5000 then
      list[id] = nil
    end
  end
end

local function isDuplicateRequest(src, requestId)
  if not requestId then return false end
  local nowMs = getTimeMs()
  recentRequestIds[src] = recentRequestIds[src] or {}
  cleanupRecent(src, nowMs)
  if recentRequestIds[src][requestId] then
    return true
  end
  recentRequestIds[src][requestId] = nowMs
  return false
end

local function acquireSpawnLock(src)
  local nowMs = getTimeMs()
  local lock = spawnLocks[src]
  if lock and (nowMs - lock) < 5000 then
    return false
  end
  spawnLocks[src] = nowMs
  return true
end

local function releaseSpawnLock(src)
  spawnLocks[src] = nil
end

local function canSpawnCooldown(faction, vehicleId, depotId)
  local t = now()
  local depotCd = depotCooldowns[depotId]
  if depotCd and (t - depotCd) < (Config.Depots[depotId].cooldown or 0) then
    return false, 'Depot cooldown active'
  end

  vehicleCooldowns[faction] = vehicleCooldowns[faction] or {}
  local last = vehicleCooldowns[faction][vehicleId]
  local cd = Config.Vehicles[vehicleId].cooldown or 0
  if last and (t - last) < cd then
    return false, 'Vehicle cooldown active'
  end

  return true
end

local function setCooldowns(faction, vehicleId, depotId)
  depotCooldowns[depotId] = now()
  vehicleCooldowns[faction] = vehicleCooldowns[faction] or {}
  vehicleCooldowns[faction][vehicleId] = now()
end

local function modelOk(hash)
  if type(IsModelInCdimage) ~= 'function' or type(IsModelAVehicle) ~= 'function' then
    Utils.logDebug(Config.Debug, 'Model validation natives missing; skipping strict check')
    return true
  end
  return IsModelInCdimage(hash) and IsModelAVehicle(hash)
end

local function loadModel(hash, modelName)
  if type(RequestModel) ~= 'function' or type(HasModelLoaded) ~= 'function' then
    Utils.logDebug(Config.Debug, ('Model load natives missing for %s; skipping load step'):format(modelName))
    return true
  end

  RequestModel(hash)
  local timeoutAt = GetGameTimer() + 2000
  while not HasModelLoaded(hash) and GetGameTimer() < timeoutAt do
    Wait(25)
  end
  return HasModelLoaded(hash)
end

local function spawnAt(hash, spawn)
  local coords = vector3(spawn.x, spawn.y, spawn.z)
  local heading = spawn.h or 0.0

  local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, true)
  if not veh or veh == 0 then
    Utils.logDebug(Config.Debug, ('CreateVehicle failed at %.2f %.2f %.2f'):format(coords.x, coords.y, coords.z))
    return nil, nil, coords
  end

  Wait(0)
  if not DoesEntityExist(veh) then
    Utils.logDebug(Config.Debug, ('Entity invalid after spawn at %.2f %.2f %.2f'):format(coords.x, coords.y, coords.z))
    return nil, nil, coords
  end

  SetEntityAsMissionEntity(veh, true, true)
  local netId = NetworkGetNetworkIdFromEntity(veh)
  if netId and netId ~= 0 then
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)
  end

  SetVehicleOnGroundProperly(veh)
  SetVehicleEngineOn(veh, false, true, true)
  if type(SetModelAsNoLongerNeeded) == 'function' then
    SetModelAsNoLongerNeeded(hash)
  end

  return veh, netId, coords
end

local function getSpawnList(depot)
  if type(depot.spawns) == 'table' and depot.spawns[1] then
    return depot.spawns
  end
  return {}
end

local function shuffle(list)
  local copy = {}
  for i, v in ipairs(list) do
    copy[i] = v
  end
  for i = #copy, 2, -1 do
    local j = math.random(1, i)
    copy[i], copy[j] = copy[j], copy[i]
  end
  return copy
end

local function isOccupied(coords)
  if type(IsPositionOccupied) == 'function' then
    return IsPositionOccupied(coords.x, coords.y, coords.z, 2.5, false, true, true, false, false, 0, false)
  end
  return false
end

local function resolveVehicleId(vehicleId, model)
  if vehicleId and Config.Vehicles[vehicleId] then
    return vehicleId
  end
  if model then
    for id, data in pairs(Config.Vehicles) do
      if data.model == model then
        return id
      end
    end
  end
  return vehicleId
end

local function registerVehicle(entity, faction, vehicleId, modelOverride)
  local netId = NetworkGetNetworkIdFromEntity(entity)
  local resolvedId = resolveVehicleId(vehicleId, modelOverride)
  local model = modelOverride or (resolvedId and Config.Vehicles[resolvedId] and Config.Vehicles[resolvedId].model) or nil
  registry[netId] = {
    netId = netId,
    entity = entity,
    faction = faction,
    vehicleId = resolvedId,
    model = model,
    state = Constants.VehicleState.Active,
    spawnedAt = now()
  }
  return netId
end

local function markDestroyed(entry)
  if not entry then return end
  entry.state = Constants.VehicleState.Destroyed
  destroyedCount[entry.faction] = destroyedCount[entry.faction] or {}
  destroyedCount[entry.faction][entry.vehicleId] = (destroyedCount[entry.faction][entry.vehicleId] or 0) + 1
  WarState.ApplyTicketLoss(entry.faction, Config.War.TicketLossPerVehicle)
  registry[entry.netId] = nil
end

function Vehicles.Init(snapshot)
  if type(snapshot) ~= 'table' then return end
  if snapshot.destroyedCount then destroyedCount = snapshot.destroyedCount end

  if snapshot.vehicles then
    for _, info in ipairs(snapshot.vehicles) do
      if info and info.model and info.coords and info.faction then
        local hash = (type(joaat) == 'function' and joaat(info.model)) or GetHashKey(info.model)
        if modelOk(hash) and loadModel(hash, info.model) then
          local spawn = { x = info.coords.x, y = info.coords.y, z = info.coords.z, h = info.heading or 0.0 }
          local veh, netId = spawnAt(hash, spawn)
          if veh then
            local registeredNetId = registerVehicle(veh, info.faction, info.vehicleId, info.model)
            local factionConfig = Config.Factions[info.faction] or {}
            local styleConfig = factionConfig.Style or {}
            spawnedRegistry[registeredNetId or netId] = {
              faction = info.faction,
              style = {
                primary = styleConfig.primary,
                secondary = styleConfig.secondary,
                xenonId = styleConfig.xenonId
              }
            }
          end
        end
      end
    end
  end
end

function Vehicles.GetSnapshot()
  local list = {}
  for _, entry in pairs(registry) do
    if DoesEntityExist(entry.entity) then
      local coords = GetEntityCoords(entry.entity)
      list[#list + 1] = {
        model = entry.model,
        vehicleId = entry.vehicleId,
        faction = entry.faction,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        heading = GetEntityHeading(entry.entity),
        state = entry.state
      }
    end
  end

  return {
    vehicles = list,
    destroyedCount = destroyedCount
  }
end

function Vehicles.IsFactionVehicle(netId, faction)
  local entry = registry[netId]
  return entry and entry.faction == faction and entry.state == Constants.VehicleState.Active
end

function Vehicles.GetSpawnedRegistry()
  return spawnedRegistry
end

function Vehicles.RequestSpawn(src, faction, vehicleId, depotId, requestId)
  if isDuplicateRequest(src, requestId) then
    print(('[MW_SIM] ignored duplicate requestId src=%s requestId=%s'):format(src, tostring(requestId)))
    return false, 'Duplicate request'
  end

  if not acquireSpawnLock(src) then
    print(('[MW_SIM] spawn lock active src=%s'):format(src))
    return false, 'Spawn already in progress'
  end

  local function fail(reason)
    releaseSpawnLock(src)
    return false, reason
  end

  local depot = Config.Depots[depotId]
  local vehicle = Config.Vehicles[vehicleId]
  if not depot or not vehicle then
    Utils.logDebug(Config.Debug, ('Spawn denied: invalid depot/vehicle depot=%s vehicle=%s'):format(tostring(depotId), tostring(vehicleId)))
    return fail('Invalid depot or vehicle')
  end
  if depot.faction ~= faction then
    Utils.logDebug(Config.Debug, ('Spawn denied: faction mismatch faction=%s depot=%s'):format(faction, depotId))
    return fail('Depot not owned by faction')
  end
  if WarState.GetTickets(faction) <= 0 then
    Utils.logDebug(Config.Debug, ('Spawn denied: no tickets faction=%s'):format(faction))
    return fail('No tickets remaining')
  end

  local canSpawn, reason = canSpawnCooldown(faction, vehicleId, depotId)
  if not canSpawn then
    Utils.logDebug(Config.Debug, ('Spawn denied: cooldown %s'):format(reason or 'unknown'))
    return fail(reason)
  end

  if not WarState.CanAfford(faction, vehicle.cost or {}) then
    Utils.logDebug(Config.Debug, ('Spawn denied: insufficient resources faction=%s vehicle=%s'):format(faction, vehicleId))
    return fail('Insufficient resources')
  end

  local hash = (type(joaat) == 'function' and joaat(vehicle.model)) or GetHashKey(vehicle.model)
  print(('[MW][SPAWN] model=%s hash=%s'):format(vehicle.model, tostring(hash)))
  Utils.logDebug(Config.Debug, ('Model check: %s'):format(vehicle.model))

  local valid = modelOk(hash)
  Utils.logDebug(Config.Debug, ('Model validity %s => %s'):format(vehicle.model, tostring(valid)))
  if not valid then
    Utils.logDebug(Config.Debug, ('Spawn denied: invalid model %s'):format(vehicle.model))
    return fail('Invalid vehicle model')
  end

  local loaded = loadModel(hash, vehicle.model)
  Utils.logDebug(Config.Debug, ('Model load %s => %s'):format(vehicle.model, tostring(loaded)))
  if not loaded then
    Utils.logDebug(Config.Debug, ('Spawn denied: model load timeout %s'):format(vehicle.model))
    return fail('Model load timeout')
  end

  local spawns = getSpawnList(depot)
  if #spawns == 0 then
    Utils.logDebug(Config.Debug, ('Spawn denied: no spawn points for depot %s'):format(depotId))
    return fail('No spawn points configured')
  end

  print(('[MW][SPAWN] creating model=%s depot=%s'):format(vehicle.model, depotId))
  Utils.logDebug(Config.Debug, ('Spawning vehicle model=%s at depot=%s'):format(vehicle.model, depotId))

  local veh, netId, coords = nil, nil, nil
  for index, spawn in ipairs(shuffle(spawns)) do
    local coord = vector3(spawn.x, spawn.y, spawn.z)
    if isOccupied(coord) then
      Utils.logDebug(Config.Debug, ('Spawn point %d occupied for depot %s'):format(index, depotId))
    else
      Utils.logDebug(Config.Debug, ('Spawn attempt %d at %.2f %.2f %.2f'):format(index, spawn.x, spawn.y, spawn.z))
      veh, netId, coords = spawnAt(hash, spawn)
      if veh and DoesEntityExist(veh) then
        Utils.logDebug(Config.Debug, ('Spawn attempt %d success netId=%s'):format(index, tostring(netId)))
        break
      else
        Utils.logDebug(Config.Debug, ('Spawn attempt %d failed'):format(index))
      end
    end
  end

  if not veh or not DoesEntityExist(veh) then
    Utils.logDebug(Config.Debug, 'Spawn failed: no valid spawn point succeeded')
    return fail('Spawn failed')
  end

  WarState.Consume(faction, vehicle.cost or {})

  setCooldowns(faction, vehicleId, depotId)
  netId = registerVehicle(veh, faction, vehicleId)
  local factionConfig = Config.Factions[faction] or {}
  local styleConfig = factionConfig.Style or {}
  spawnedRegistry[netId] = {
    faction = faction,
    style = {
      primary = styleConfig.primary,
      secondary = styleConfig.secondary,
      xenonId = styleConfig.xenonId
    }
  }
  print(('[MW][SPAWN] created netId=%s faction=%s vehicle=%s'):format(netId, faction, vehicleId))
  Utils.logDebug(Config.Debug, ('Spawn success netId=%s faction=%s vehicle=%s'):format(netId, faction, vehicleId))
  releaseSpawnLock(src)
  return true, { netId = netId, coords = { x = coords.x, y = coords.y, z = coords.z } }
end

function Vehicles.RequestRepair(faction, netId)
  local entry = registry[netId]
  if not entry or entry.faction ~= faction then
    return false, 'Invalid vehicle'
  end

  if not WarState.Consume(faction, { parts = 5, fuel = 2 }) then
    return false, 'Insufficient resources'
  end

  if entry.entity and DoesEntityExist(entry.entity) then
    SetVehicleEngineHealth(entry.entity, 1000.0)
    SetVehicleBodyHealth(entry.entity, 1000.0)
    SetVehicleFixed(entry.entity)
    entry.state = Constants.VehicleState.Active
    return true, netId
  end

  return false, 'Vehicle missing'
end

function Vehicles.Tick()
  for _, entry in pairs(registry) do
    if not entry.entity or not DoesEntityExist(entry.entity) then
      markDestroyed(entry)
      if entry and entry.netId then
        spawnedRegistry[entry.netId] = nil
      end
    else
      local engineHealth = GetVehicleEngineHealth(entry.entity)
      if engineHealth <= 0 then
        markDestroyed(entry)
        if entry and entry.netId then
          spawnedRegistry[entry.netId] = nil
        end
      end
    end
  end
end

return Vehicles
