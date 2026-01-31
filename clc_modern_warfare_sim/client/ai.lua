local Config = MW.require('shared/config.lua')
local Utils = MW.require('shared/utils.lua')

local AI = {}
local aiPeds = {}
local aiRegistry = {}
local zoneHost = {}
local relationshipGroups = {}
local lastLog = { combat = {}, patrol = {} }

local function vec3(x, y, z)
  return vector3(x, y, z)
end

local function randomOffset(radius)
  local angle = math.random() * 6.283185
  local r = math.sqrt(math.random()) * radius
  return r * math.cos(angle), r * math.sin(angle)
end

local function pickModel()
  local list = Config.AI.Models or { 's_m_y_marine_01' }
  return list[math.random(1, #list)]
end

local function getGroup(factionId)
  if relationshipGroups[factionId] then
    return relationshipGroups[factionId]
  end
  local name = ('MW_AI_%s'):format(factionId)
  local group = AddRelationshipGroup(name)
  relationshipGroups[factionId] = group
  return group
end

local function setupRelations()
  for factionId in pairs(Config.Factions) do
    getGroup(factionId)
  end
  for a in pairs(Config.Factions) do
    for b in pairs(Config.Factions) do
      if a ~= b then
        SetRelationshipBetweenGroups(5, getGroup(a), getGroup(b))
      else
        SetRelationshipBetweenGroups(1, getGroup(a), getGroup(b))
      end
    end
  end
end

local function setPedLoadout(ped, factionId)
  local weapon = (Config.AI.Weapons and Config.AI.Weapons[factionId]) or 'WEAPON_CARBINERIFLE'
  GiveWeaponToPed(ped, GetHashKey(weapon), 200, false, true)
  SetPedAccuracy(ped, Config.AI.Accuracy or 30)
  SetPedCombatAbility(ped, Config.AI.CombatAbility or 1)
  SetPedCombatRange(ped, Config.AI.CombatRange or 1)
  SetPedCombatMovement(ped, Config.AI.CombatMovement or 2)
  SetPedCombatAttributes(ped, 0, true)
  SetPedCombatAttributes(ped, 46, true)
  SetPedFleeAttributes(ped, 0, false)
  SetPedSeeingRange(ped, 120.0)
  SetPedHearingRange(ped, 120.0)
  SetPedAlertness(ped, 2)
  SetPedRelationshipGroupHash(ped, getGroup(factionId))
end

local function spawnPed(spawnZoneId, targetZoneId, factionId, role)
  local zone = Config.Zones[spawnZoneId]
  if not zone then return nil end

  local model = pickModel()
  local hash = GetHashKey(model)
  RequestModel(hash)
  local timeout = GetGameTimer() + 1500
  while not HasModelLoaded(hash) and GetGameTimer() < timeout do
    Wait(10)
  end
  if not HasModelLoaded(hash) then
    print(('[MW_AI] model load failed model=%s'):format(model))
    return nil
  end

  local radius = zone.radius or 80.0
  local spawnRadius = radius
  if role == 'perimeter' then
    spawnRadius = radius + (Config.AI.PerimeterBuffer or 60.0)
  elseif role == 'reinforce' then
    spawnRadius = radius + (Config.AI.ReinforceBuffer or 100.0)
  end

  local dx, dy = randomOffset(spawnRadius)
  local x = zone.center.x + dx
  local y = zone.center.y + dy
  local z = zone.center.z + 1.0

  local ped = CreatePed(4, hash, x, y, z, math.random(0, 360), true, true)
  if not ped or ped == 0 then return nil end

  SetEntityAsMissionEntity(ped, true, true)
  setPedLoadout(ped, factionId)
  SetPedArmour(ped, 50)
  SetPedCanRagdoll(ped, true)
  SetPedDropsWeaponsWhenDead(ped, true)
  SetModelAsNoLongerNeeded(hash)

  local netId = NetworkGetNetworkIdFromEntity(ped)
  if netId and netId ~= 0 then
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)
  end

  aiPeds[netId] = {
    entity = ped,
    zoneId = targetZoneId,
    faction = factionId,
    role = role,
    spawnedAt = GetGameTimer()
  }
  return netId, ped
end

local function issuePatrol(ped, zoneId)
  local zone = Config.Zones[zoneId]
  if not zone then return end
  local dx, dy = randomOffset((zone.radius or 80.0) * 0.6)
  TaskGoToCoordAnyMeans(ped, zone.center.x + dx, zone.center.y + dy, zone.center.z, 2.0, 0, false, 1, 0)
  local now = GetGameTimer()
  if not lastLog.patrol[zoneId] or (now - lastLog.patrol[zoneId]) > 15000 then
    lastLog.patrol[zoneId] = now
    print(('[MW_AI] movement zone=%s action=patrol'):format(zoneId))
  end
end

local function issueAttack(ped, zoneId)
  TaskCombatHatedTargetsAroundPed(ped, 200.0)
  local now = GetGameTimer()
  if not lastLog.combat[zoneId] or (now - lastLog.combat[zoneId]) > 12000 then
    lastLog.combat[zoneId] = now
    print(('[MW_AI] combat zone=%s action=engage'):format(zoneId))
  end
end

RegisterNetEvent('mw:aiSpawn', function(payload)
  local zoneId = payload and payload.zoneId
  local faction = payload and payload.faction
  local role = payload and payload.role or 'defender'
  local count = payload and payload.count or 0
  local sourceZoneId = payload and payload.sourceZoneId or zoneId
  if not zoneId or not faction or count <= 0 then return end

  zoneHost[zoneId] = true
  print(('[MW_AI] spawn zone=%s faction=%s role=%s count=%d'):format(zoneId, faction, role, count))

  local netIds = {}
  for _ = 1, count do
    local netId, ped = spawnPed(sourceZoneId, zoneId, faction, role)
    if netId then
      netIds[#netIds + 1] = netId
      aiRegistry[netId] = { zoneId = zoneId, faction = faction, role = role }
      if role == 'reinforce' and sourceZoneId ~= zoneId then
        local target = Config.Zones[zoneId]
        if target then
          TaskGoToCoordAnyMeans(ped, target.center.x, target.center.y, target.center.z, 2.5, 0, false, 1, 0)
        end
      else
        issuePatrol(ped, zoneId)
      end
    end
  end

  if #netIds > 0 then
    TriggerServerEvent('mw:aiSpawned', {
      zoneId = zoneId,
      faction = faction,
      role = role,
      netIds = netIds
    })
  end
end)

RegisterNetEvent('mw:aiRegister', function(payload)
  local netIds = payload and payload.netIds or {}
  for _, netId in ipairs(netIds) do
    aiRegistry[netId] = {
      zoneId = payload.zoneId,
      faction = payload.faction,
      role = payload.role
    }
  end
end)

RegisterNetEvent('mw:aiDespawn', function(payload)
  local list = payload and payload.netIds or {}
  local reason = payload and payload.reason or 'unknown'
  if #list > 0 then
    print(('[MW_AI] despawn count=%d reason=%s'):format(#list, reason))
  end
  for _, netId in ipairs(list) do
    local ped = NetToPed(netId)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
      SetEntityAsMissionEntity(ped, true, true)
      DeleteEntity(ped)
    end
    aiRegistry[netId] = nil
    aiPeds[netId] = nil
  end
end)

CreateThread(function()
  setupRelations()
  while true do
    Wait(1000)
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)

    for netId, info in pairs(aiPeds) do
      local ped = info.entity
      if not DoesEntityExist(ped) then
        TriggerServerEvent('mw:aiDied', { netId = netId })
        aiPeds[netId] = nil
      elseif IsEntityDead(ped) then
        TriggerServerEvent('mw:aiDied', { netId = netId })
        aiPeds[netId] = nil
      else
        if zoneHost[info.zoneId] then
          local zone = Config.Zones[info.zoneId]
          if zone and Utils.distance(playerPos, zone.center) <= ((zone.radius or 80.0) + 120.0) then
            issueAttack(ped, info.zoneId)
          else
            issuePatrol(ped, info.zoneId)
          end
        end
      end
    end
  end
end)

CreateThread(function()
  while true do
    Wait(1500)
    local playerPos = GetEntityCoords(PlayerPedId())
    for netId, info in pairs(aiRegistry) do
      local ped = NetToPed(netId)
      if ped and ped ~= 0 and DoesEntityExist(ped) then
        local dist = Utils.distance(playerPos, GetEntityCoords(ped))
        local blip = info.blip
        if dist <= (Config.AI.VisibilityDistance or 800.0) then
          if not blip then
            blip = AddBlipForEntity(ped)
            SetBlipSprite(blip, 1)
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            info.blip = blip
          end
        else
          if blip then
            RemoveBlip(blip)
            info.blip = nil
          end
        end
      else
        if info.blip then
          RemoveBlip(info.blip)
        end
        aiRegistry[netId] = nil
      end
    end
  end
end)

return AI
