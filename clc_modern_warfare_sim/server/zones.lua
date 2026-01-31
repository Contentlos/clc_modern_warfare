local Config = MW.require('shared/config.lua')
local Constants = MW.require('shared/constants.lua')
local Utils = MW.require('shared/utils.lua')
local Players = MW.require('server/players.lua')
local WarState = MW.require('server/warstate.lua')
local Vehicles = MW.require('server/vehicles.lua')
local AI = MW.require('server/ai.lua')

local Zones = {}

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

local function getZoneForCoords(coords)
  for zoneId, zone in pairs(Config.Zones) do
    if isInsideZone(coords, zone) then
      return zoneId
    end
  end
  return nil
end

local function getDominant(counts)
  local dominant, dominantCount, secondCount = nil, 0, 0
  for faction, count in pairs(counts) do
    if count > dominantCount then
      secondCount = dominantCount
      dominantCount = count
      dominant = faction
    elseif count > secondCount then
      secondCount = count
    end
  end
  return dominant, dominantCount, secondCount
end

function Zones.Tick()
  local zonesConfig = Config.Zones
  local zonesState = WarState.GetZones()
  if not zonesState then return end

  Players.UpdatePositions()

  local presence = {}
  for zoneId in pairs(zonesConfig) do
    presence[zoneId] = { counts = {}, vehicles = {} }
  end

  for _, entry in pairs(Players.GetAll()) do
    if entry.faction and entry.coords and entry.health and entry.health > 0 and not Players.IsAFK(entry) then
      for zoneId, zone in pairs(zonesConfig) do
        if isInsideZone(entry.coords, zone) then
          local counts = presence[zoneId].counts
          counts[entry.faction] = (counts[entry.faction] or 0) + 1

          if Config.War.RequireVehicleForCapture and entry.vehicleNetId then
            if Vehicles.IsFactionVehicle(entry.vehicleNetId, entry.faction) then
              local vehCounts = presence[zoneId].vehicles
              vehCounts[entry.faction] = (vehCounts[entry.faction] or 0) + 1
            end
          end
        end
      end
    end
  end

  for zoneId, zone in pairs(zonesConfig) do
    local state = zonesState[zoneId]
    if state then
      local counts = presence[zoneId].counts
      local dominant, dominantCount, secondCount = getDominant(counts)
      local hasVehicle = true

      if Config.War.RequireVehicleForCapture then
        hasVehicle = dominant and (presence[zoneId].vehicles[dominant] or 0) > 0 or false
      end

      local canCapture = dominant
        and dominantCount >= Config.War.MinPlayersToCapture
        and dominantCount > secondCount
        and hasVehicle

      if canCapture then
        local captureTime = zone.captureTime or Config.War.CaptureTime
        if state.owner == dominant then
          WarState.SetZoneState(zoneId, {
            state = Constants.ZoneState.Captured,
            contestedBy = nil,
            progress = captureTime
          })
        else
          local progress = state.progress or 0
          if state.contestedBy ~= dominant then
            progress = 0
          end
          local defenders = AI.GetDefenderCount(zoneId, state.owner)
          local factor = AI.GetCaptureFactor(defenders)
          progress = progress + (Config.War.ZoneTick * factor)

          if progress >= captureTime then
            local oldOwner = state.owner
            WarState.SetZoneState(zoneId, {
              owner = dominant,
              state = Constants.ZoneState.Captured,
              contestedBy = nil,
              progress = captureTime,
              lastCapture = Utils.now()
            })
            AI.OnZoneCaptured(zoneId, dominant, oldOwner)
          else
            WarState.SetZoneState(zoneId, {
              state = Constants.ZoneState.Contested,
              contestedBy = dominant,
              progress = progress
            })
          end
        end
      else
        local decay = Config.War.CaptureDecay
        local progress = math.max(0, (state.progress or 0) - decay)
        local newState = state.owner and Constants.ZoneState.Captured or Constants.ZoneState.Neutral
        WarState.SetZoneState(zoneId, {
          state = newState,
          contestedBy = nil,
          progress = progress
        })
      end
    end
  end
end

function Zones.GetControllingFaction(coords)
  local zoneId = getZoneForCoords(coords)
  if not zoneId then return nil, nil end

  local state = WarState.GetZones()[zoneId]
  if state and state.owner then
    return state.owner, zoneId
  end

  return nil, zoneId
end

return Zones
