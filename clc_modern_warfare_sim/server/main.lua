local Config = MW.require('shared/config.lua')
local Constants = MW.require('shared/constants.lua')
local Utils = MW.require('shared/utils.lua')
local Persistence = MW.require('server/persistence.lua')
local WarState = MW.require('server/warstate.lua')
local Zones = MW.require('server/zones.lua')
local Vehicles = MW.require('server/vehicles.lua')
local Logistics = MW.require('server/logistics.lua')
local AI = MW.require('server/ai.lua')
local Players = MW.require('server/players.lua')
local Commands = MW.require('server/commands.lua')

local function validateConfig()
  local ok, errors = Config.Validate()
  if not ok then
    print('[MW] Config validation failed:')
    for _, err in ipairs(errors) do
      print((' - %s'):format(err))
    end
  end
  return ok
end

local function buildSnapshot()
  local snapshot = WarState.GetSnapshot()
  local vehicleSnapshot = Vehicles.GetSnapshot()
  snapshot.vehicles = vehicleSnapshot.vehicles
  snapshot.destroyedCount = vehicleSnapshot.destroyedCount
  return snapshot
end

local function broadcastState()
  TriggerClientEvent(Constants.Events.State, -1, {
    phase = WarState.Get().phase,
    tickets = WarState.Get().tickets,
    resources = WarState.Get().resources
  })
  TriggerClientEvent(Constants.Events.Zones, -1, WarState.Get().zones)
  TriggerClientEvent(Constants.Events.Vehicles, -1, Vehicles.GetSnapshot())
  TriggerClientEvent(Constants.Events.Resources, -1, WarState.Get().resources)
end

local function isNear(src, coords, radius)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false end
  local pos = GetEntityCoords(ped)
  local dist = Utils.distance(pos, coords)
  return dist <= radius
end

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end

  print('[MW_SIM] VERSION 2026-01-30-A | resource=' .. GetCurrentResourceName())
  if GetResourceState('clc_modern_warfare') == 'started' then
    print('[MW_SIM] WARNING: clc_modern_warfare is running alongside clc_modern_warfare_sim')
  end

  validateConfig()
  Persistence.Init()
  local snapshot = Persistence.LoadSnapshot()
  WarState.Init(snapshot)
  Vehicles.Init(snapshot)
  AI.Init()

  if not Config.War.AutoStart then
    WarState.SetPhase(Constants.WarPhases.Peace)
  end

  Players.Init()
  Commands.Init()

  broadcastState()

  CreateThread(function()
    while true do
      Wait(Config.War.ZoneTick * 1000)
      if WarState.IsActive() then
        Zones.Tick()
        broadcastState()
      end
    end
  end)

  CreateThread(function()
    while true do
      Wait((Config.AI.TickSeconds or 5) * 1000)
      if WarState.IsActive() then
        AI.Tick()
        broadcastState()
      end
    end
  end)

  CreateThread(function()
    while true do
      Wait(Config.War.ResourceTick * 1000)
      if WarState.IsActive() then
        Logistics.Tick()
        broadcastState()
      end
    end
  end)

  CreateThread(function()
    while true do
      Wait(Config.War.VehicleTick * 1000)
      Vehicles.Tick()
    end
  end)

  CreateThread(function()
    while true do
      Wait(Config.SaveInterval * 1000)
      Persistence.SaveSnapshot(buildSnapshot())
    end
  end)
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  Persistence.SaveSnapshot(buildSnapshot())
end)

AddEventHandler('playerJoining', function()
  local src = source
  Players.Register(src)
  local faction = Players.GetFaction(src)
  TriggerClientEvent(Constants.Events.PlayerInfo, src, { faction = faction })
  broadcastState()
end)

AddEventHandler('playerDropped', function()
  Players.Unregister(source)
end)

RegisterNetEvent(Constants.Events.RequestJoin, function(faction)
  local src = source
  if not Config.Factions[faction] then
    return
  end
  Players.SetFaction(src, faction)
  TriggerClientEvent(Constants.Events.PlayerInfo, src, { faction = faction })
  broadcastState()
end)

RegisterNetEvent(Constants.Events.RequestSpawn, function(data)
  local src = source
  local faction = Players.GetFaction(src)
  if not faction then
    Utils.logDebug(Config.Debug, ('Spawn denied: no faction src=%s'):format(src))
    return
  end

  local depotId = data and data.depotId
  local vehicleId = data and data.vehicleId
  local requestId = data and data.requestId
  local depot = Config.Depots[depotId]
  if not depot then return end

  local radius = depot.radius or 8.0
  if not isNear(src, depot.coords, radius) then
    Utils.logDebug(Config.Debug, ('Spawn denied: too far src=%s depot=%s'):format(src, tostring(depotId)))
    return
  end

  local controlling, zoneId = Zones.GetControllingFaction(depot.coords)
  if zoneId and not controlling then
    local reason = 'Depot in neutral zone'
    Utils.logDebug(Config.Debug, ('Spawn denied: %s depot=%s'):format(reason, depotId))
    TriggerClientEvent('mw:spawnResult', src, { ok = false, reason = reason })
    return
  end

  local accessFaction = controlling or depot.faction
  if accessFaction ~= faction then
    local reason = ('Depot controlled by %s'):format(accessFaction or 'neutral')
    Utils.logDebug(Config.Debug, ('Spawn denied: %s depot=%s'):format(reason, depotId))
    TriggerClientEvent('mw:spawnResult', src, { ok = false, reason = reason })
    return
  end

  print(('[MW_SIM] spawn request src=%s faction=%s depot=%s vehicle=%s requestId=%s'):format(src, faction, tostring(depotId), tostring(vehicleId), tostring(requestId)))
  Utils.logDebug(Config.Debug, ('Spawn request src=%s faction=%s depot=%s vehicle=%s'):format(src, faction, tostring(depotId), tostring(vehicleId)))
  local ok, result = Vehicles.RequestSpawn(src, faction, vehicleId, depotId, requestId)
  if ok then
    local factionConfig = Config.Factions[faction] or {}
    local styleConfig = factionConfig.Style or {}
    TriggerClientEvent(Constants.Events.Vehicles, -1, Vehicles.GetSnapshot())
    TriggerClientEvent(Constants.Events.PlayerInfo, src, { faction = faction })
    local spawnEntry = Vehicles.GetSpawnedRegistry()[result.netId]
    TriggerClientEvent('mw:spawnResult', src, {
      ok = true,
      netId = result.netId,
      coords = result.coords,
      vehicleId = vehicleId,
      label = Config.Vehicles[vehicleId] and Config.Vehicles[vehicleId].label or vehicleId,
      faction = faction,
      style = spawnEntry and spawnEntry.style or {
        primary = styleConfig.primary,
        secondary = styleConfig.secondary,
        xenonId = styleConfig.xenonId
      }
    })
  else
    TriggerClientEvent('chat:addMessage', src, { args = { 'WAR', result or 'Spawn denied' } })
    TriggerClientEvent('mw:spawnResult', src, { ok = false, reason = result or 'Spawn denied' })
  end
end)

RegisterNetEvent(Constants.Events.RequestRepair, function(data)
  local src = source
  local faction = Players.GetFaction(src)
  if not faction then return end

  local netId = data and data.netId
  if not netId then return end

  local canRepair = false
  for _, station in pairs(Config.RepairStations) do
    if station.faction == faction then
      if isNear(src, station.coords, station.radius or 6.0) then
        canRepair = true
        break
      end
    end
  end

  if not canRepair then return end

  local ok, result = Vehicles.RequestRepair(faction, netId)
  if ok then
    TriggerClientEvent(Constants.Events.Vehicles, -1, Vehicles.GetSnapshot())
  else
    TriggerClientEvent('chat:addMessage', src, { args = { 'WAR', result or 'Repair denied' } })
  end
end)

RegisterNetEvent(Constants.Events.RequestStatus, function()
  local src = source
  TriggerClientEvent(Constants.Events.State, src, {
    phase = WarState.Get().phase,
    tickets = WarState.Get().tickets,
    resources = WarState.Get().resources
  })
  TriggerClientEvent(Constants.Events.Zones, src, WarState.Get().zones)
  TriggerClientEvent(Constants.Events.Vehicles, src, Vehicles.GetSnapshot())
  TriggerClientEvent(Constants.Events.Resources, src, WarState.Get().resources)
end)
