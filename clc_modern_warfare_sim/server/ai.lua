local Config = MW.require('shared/config.lua')
local Utils = MW.require('shared/utils.lua')
local Players = MW.require('server/players.lua')
local WarState = MW.require('server/warstate.lua')

local AI = {}
local zoneState = {}
local units = {}
local pendingSpawn = {}

local function isInsideSphere(coords, zone)
  local c = zone.center
  local dx = coords.x - c.x
  local dy = coords.y - c.y
  local dz = coords.z - c.z
  return (dx * dx + dy * dy + dz * dz) <= (zone.radius * zone.radius)
end

local function isInsideZone(coords, zone)
  if zone.type == 'sphere' then
    return isInsideSphere(coords, zone)
  end
  if zone.type == 'box' then
    local c = zone.center
    local s = zone.size or { x = 1, y = 1, z = 1 }
    return math.abs(coords.x - c.x) <= (s.x * 0.5)
      and math.abs(coords.y - c.y) <= (s.y * 0.5)
      and math.abs(coords.z - c.z) <= (s.z * 0.5)
  end
  return false
end

local function distance(a, b)
  return Utils.distance(a, b)
end

local function zoneConfig(zoneId)
  return Config.Zones[zoneId]
end

local function isStrategic(zoneId)
  local zone = zoneConfig(zoneId)
  if not zone then return false end
  if zone.aiStrategic == false then return false end
  if zone.aiStrategic == true then return true end
  return Config.AI.DefaultStrategic == true
end

local function isEnabled(zoneId)
  local zone = zoneConfig(zoneId)
  if not zone then return false end
  if zone.aiEnabled == false then return false end
  return Config.AI.Enabled == true
end

local function getIntensity(zoneId)
  local zone = zoneConfig(zoneId)
  if not zone then return 1.0 end
  return zone.aiIntensity or Config.AI.DefaultIntensity or 1.0
end

local function findHost(zoneId)
  local zone = zoneConfig(zoneId)
  if not zone then return nil end
  local bestSrc, bestDist = nil, math.huge
  for _, entry in pairs(Players.GetAll()) do
    if entry.coords and entry.health and entry.health > 0 then
      local dist = distance(entry.coords, zone.center)
      if dist <= (Config.AI.HostRadius or 1200.0) and dist < bestDist then
        bestDist = dist
        bestSrc = entry.source
      end
    end
  end
  return bestSrc
end

local function hasPlayersNear(zoneId)
  local zone = zoneConfig(zoneId)
  if not zone then return false end
  local radius = (zone.radius or 0) + (Config.AI.PlayerRadius or 200.0)
  for _, entry in pairs(Players.GetAll()) do
    if entry.coords and entry.health and entry.health > 0 then
      if distance(entry.coords, zone.center) <= radius then
        return true
      end
    end
  end
  return false
end

local function countPresence(zoneId)
  local zone = zoneConfig(zoneId)
  if not zone then return {} end
  local counts = { total = 0, vehicles = 0, byFaction = {} }
  for _, entry in pairs(Players.GetAll()) do
    if entry.coords and entry.health and entry.health > 0 then
      if isInsideZone(entry.coords, zone) then
        counts.total = counts.total + 1
        counts.byFaction[entry.faction] = (counts.byFaction[entry.faction] or 0) + 1
        if entry.inVehicle then
          counts.vehicles = counts.vehicles + 1
        end
      end
    end
  end
  return counts
end

local function hasEnemyNear(zoneId, owner)
  local zone = zoneConfig(zoneId)
  if not zone or not owner then return false end
  local radius = (zone.radius or 0) + (Config.AI.PerimeterBuffer or 60.0) + (Config.AI.PlayerRadius or 200.0)
  for _, entry in pairs(Players.GetAll()) do
    if entry.coords and entry.health and entry.health > 0 and entry.faction and entry.faction ~= owner then
      if distance(entry.coords, zone.center) <= radius then
        return true
      end
    end
  end
  return false
end

local function sumUnits(zoneId, faction)
  local count = 0
  for _, unit in pairs(units) do
    if unit.zoneId == zoneId and unit.faction == faction then
      count = count + 1
    end
  end
  return count
end

local function sumZoneUnits(zoneId)
  local count = 0
  for _, unit in pairs(units) do
    if unit.zoneId == zoneId then
      count = count + 1
    end
  end
  return count
end

local function desiredDefenders(zoneId, playerCount, vehicleCount)
  local intensity = getIntensity(zoneId)
  local base = (Config.AI.BaseDefenders or 2) * intensity
  local scaled = base + (playerCount * (Config.AI.PerPlayer or 1)) + (vehicleCount * (Config.AI.PerVehicle or 1))
  local minD = (Config.AI.MinDefenders or 2) * intensity
  local maxD = (Config.AI.MaxDefenders or 12) * intensity
  return math.max(minD, math.min(maxD, math.floor(scaled)))
end

local function setZoneStatus(zoneId, status)
  WarState.SetZoneState(zoneId, { aiStatus = status })
  zoneState[zoneId] = zoneState[zoneId] or {}
  zoneState[zoneId].status = status
end

local function requestSpawn(zoneId, faction, role, count)
  if count <= 0 then return end
  local host = findHost(zoneId)
  if not host then return end

  pendingSpawn[zoneId] = pendingSpawn[zoneId] or {}
  if pendingSpawn[zoneId][role] then
    return
  end

  pendingSpawn[zoneId][role] = GetGameTimer()

  local payload = {
    zoneId = zoneId,
    faction = faction,
    role = role,
    count = count
  }

  if role == 'reinforce' then
    local supportZone = nil
    local bestDist = math.huge
    for id, z in pairs(WarState.GetZones()) do
      if id ~= zoneId and z.owner == faction then
        local dist = distance(zoneConfig(zoneId).center, zoneConfig(id).center)
        if dist < bestDist then
          bestDist = dist
          supportZone = id
        end
      end
    end
    if supportZone then
      payload.sourceZoneId = supportZone
    end
  end

  TriggerClientEvent('mw:aiSpawn', host, payload)
  print(('[MW_AI] spawn requested zone=%s faction=%s role=%s count=%d host=%s'):format(zoneId, faction, role, count, host))
end

local function clearZone(zoneId, reason)
  for netId, unit in pairs(units) do
    if unit.zoneId == zoneId then
      TriggerClientEvent('mw:aiDespawn', -1, { netIds = { netId }, reason = reason or 'clear' })
      units[netId] = nil
    end
  end
  print(('[MW_AI] zone cleared zone=%s reason=%s'):format(zoneId, reason or 'clear'))
end

function AI.Init()
  zoneState = {}
  units = {}
  pendingSpawn = {}
end

function AI.GetDefenderCount(zoneId, faction)
  if not zoneId or not faction then return 0 end
  return sumUnits(zoneId, faction)
end

function AI.GetCaptureFactor(defenderCount)
  if not defenderCount or defenderCount <= 0 then return 1.0 end
  local blockThreshold = Config.AI.DefenderBlockCount or 8
  local maxBlock = Config.AI.MaxCaptureBlock or 0.85
  local block = math.min(defenderCount / blockThreshold, 1.0) * maxBlock
  return math.max(0.05, 1.0 - block)
end

function AI.GetStatus()
  local summary = {}
  for zoneId in pairs(Config.Zones) do
    summary[zoneId] = {
      total = sumZoneUnits(zoneId),
      status = (zoneState[zoneId] and zoneState[zoneId].status) or 'idle'
    }
  end
  return summary
end

function AI.ClearZone(zoneId)
  clearZone(zoneId, 'admin')
end

function AI.OnZoneCaptured(zoneId, newOwner, oldOwner)
  if oldOwner then
    clearZone(zoneId, 'capture')
  end
  setZoneStatus(zoneId, 'reinforcements incoming')
  if newOwner then
    requestSpawn(zoneId, newOwner, 'reinforce', math.max(2, Config.AI.MinDefenders or 2))
  end
end

function AI.Tick()
  if not Config.AI.Enabled then return end
  if not WarState.IsActive() then return end

  for zoneId, roles in pairs(pendingSpawn) do
    for role, ts in pairs(roles) do
      if (GetGameTimer() - ts) > 8000 then
        roles[role] = nil
      end
    end
  end

  Players.UpdatePositions()
  local zones = WarState.GetZones()

  for zoneId, state in pairs(zones) do
    local zone = zoneConfig(zoneId)
    if zone and isEnabled(zoneId) and isStrategic(zoneId) then
      local owner = state.owner
      local presence = countPresence(zoneId)
      local attacked = hasEnemyNear(zoneId, owner)

      local desired = owner and desiredDefenders(zoneId, presence.total, presence.vehicles) or 0
      local current = owner and sumUnits(zoneId, owner) or 0

      local status = 'idle'
      if owner and sumZoneUnits(zoneId) > 0 then
        status = 'zone defended'
      end
      if owner and attacked then
        status = 'enemy forces active'
        if (Config.AI.ReinforceRatio or 0) > 0 then
          status = 'reinforcements incoming'
        end
      end
      setZoneStatus(zoneId, status)

      if owner and attacked then
        local needed = math.max(0, desired - current)
        if needed > 0 then
          requestSpawn(zoneId, owner, 'defender', needed)
        end
        requestSpawn(zoneId, owner, 'perimeter', math.floor(desired * (Config.AI.PerimeterRatio or 0.35)))
      end

      if owner and attacked and (Config.AI.ReinforceRatio or 0) > 0 then
        requestSpawn(zoneId, owner, 'reinforce', math.floor(desired * (Config.AI.ReinforceRatio or 0.25)))
      end

      if owner and not attacked and current > desired then
        local now = Utils.now()
        zoneState[zoneId] = zoneState[zoneId] or {}
        zoneState[zoneId].lastStable = zoneState[zoneId].lastStable or now
        if (now - zoneState[zoneId].lastStable) > (Config.AI.DespawnNoActivity or 180) then
          local removeCount = math.min(Config.AI.DespawnStep or 2, current - desired)
          if removeCount > 0 then
            local removed = 0
            for netId, unit in pairs(units) do
              if unit.zoneId == zoneId and unit.faction == owner and removed < removeCount then
                TriggerClientEvent('mw:aiDespawn', -1, { netIds = { netId }, reason = 'stabilized' })
                units[netId] = nil
                removed = removed + 1
              end
            end
            if removed > 0 then
              print(('[MW_AI] despawn zone=%s removed=%d reason=stabilized'):format(zoneId, removed))
            end
          end
        end
      end
    end
  end
end

RegisterNetEvent('mw:aiSpawned', function(data)
  local src = source
  local zoneId = data and data.zoneId
  local faction = data and data.faction
  local role = data and data.role
  local netIds = data and data.netIds or {}
  if not zoneId or not faction or #netIds == 0 then return end

  pendingSpawn[zoneId] = pendingSpawn[zoneId] or {}
  pendingSpawn[zoneId][role or 'defender'] = nil

  for _, netId in ipairs(netIds) do
    units[netId] = {
      netId = netId,
      zoneId = zoneId,
      faction = faction,
      role = role or 'defender',
      owner = src,
      spawnedAt = Utils.now()
    }
  end

  TriggerClientEvent('mw:aiRegister', -1, {
    zoneId = zoneId,
    faction = faction,
    role = role or 'defender',
    netIds = netIds
  })
end)

RegisterNetEvent('mw:aiDied', function(data)
  local netId = data and data.netId
  if not netId then return end
  local unit = units[netId]
  if not unit then return end
  units[netId] = nil
  TriggerClientEvent('mw:aiDespawn', -1, { netIds = { netId }, reason = 'dead' })
  print(('[MW_AI] unit dead netId=%s zone=%s faction=%s'):format(netId, unit.zoneId, unit.faction))
end)

RegisterNetEvent('mw:aiClearZone', function(data)
  local zoneId = data and data.zoneId
  if not zoneId then return end
  clearZone(zoneId, 'admin')
end)

return AI
