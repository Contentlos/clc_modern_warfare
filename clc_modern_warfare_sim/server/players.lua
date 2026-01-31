local Persistence = MW.require('server/persistence.lua')
local Utils = MW.require('shared/utils.lua')
local Config = MW.require('shared/config.lua')

local Players = {}
local tracked = {}

local function getIdentifier(src)
  local id = GetPlayerIdentifierByType(src, 'license')
  if id then return id end
  id = GetPlayerIdentifierByType(src, 'steam')
  if id then return id end
  return GetPlayerIdentifier(src, 0)
end

function Players.Init()
  for _, src in ipairs(GetPlayers()) do
    Players.Register(tonumber(src))
  end
end

function Players.Register(src)
  local identifier = getIdentifier(src)
  if not identifier then return end

  tracked[src] = {
    source = src,
    identifier = identifier,
    faction = Persistence.GetPlayerFaction(identifier),
    coords = nil,
    lastPos = nil,
    lastMovedAt = Utils.now(),
    lastSeen = Utils.now()
  }
end

function Players.Unregister(src)
  tracked[src] = nil
end

function Players.SetFaction(src, faction)
  local entry = tracked[src]
  if not entry then return end
  entry.faction = faction
  Persistence.SetPlayerFaction(entry.identifier, faction)
end

function Players.GetFaction(src)
  local entry = tracked[src]
  return entry and entry.faction or nil
end

function Players.GetIdentifier(src)
  local entry = tracked[src]
  return entry and entry.identifier or nil
end

function Players.GetAll()
  return tracked
end

function Players.UpdatePositions()
  local now = Utils.now()
  for src, entry in pairs(tracked) do
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
      local coords = GetEntityCoords(ped)
      entry.coords = coords
      entry.lastSeen = now

      if not entry.lastPos then
        entry.lastPos = coords
        entry.lastMovedAt = now
      else
        local dist = Utils.distance(entry.lastPos, coords)
        if dist >= Config.War.AFKMoveThreshold then
          entry.lastPos = coords
          entry.lastMovedAt = now
        end
      end

      entry.health = GetEntityHealth(ped)
      entry.inVehicle = IsPedInAnyVehicle(ped, false)
      if entry.inVehicle then
        local veh = GetVehiclePedIsIn(ped, false)
        entry.vehicle = veh
        entry.vehicleNetId = veh and NetworkGetNetworkIdFromEntity(veh) or nil
      else
        entry.vehicle = nil
        entry.vehicleNetId = nil
      end
    end
  end
end

function Players.IsAFK(entry)
  if not entry or not entry.lastMovedAt then return true end
  return (Utils.now() - entry.lastMovedAt) >= Config.War.AFKSeconds
end

return Players
