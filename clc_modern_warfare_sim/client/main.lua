local Config = MW.require('shared/config.lua')
local Constants = MW.require('shared/constants.lua')
local Utils = MW.require('shared/utils.lua')
local UI = MW.require('client/ui.lua')
local Blips = MW.require('client/blips.lua')
local VehicleStyling = MW.require('client/vehicles.lua')
local AI = MW.require('client/ai.lua')

local playerFaction = nil
local warState = {}
local zones = {}
local resources = {}
local vehicles = {}
local nearDepot = nil
local depotAccess = {}
local pendingSpawn = nil
local uiState = 'closed'
local lastUiAction = 0
local uiDebounceMs = 500

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

local function getDepotControl(depotId)
  local depot = Config.Depots[depotId]
  if not depot then return nil, nil end

  local zoneId = getZoneForCoords(depot.coords)
  if zoneId then
    local state = zones[zoneId]
    if state and state.owner then
      return state.owner, zoneId
    end
    if not state or state.owner == nil then
      local configOwner = Config.Zones[zoneId] and Config.Zones[zoneId].owner
      if configOwner and configOwner ~= 'neutral' then
        return configOwner, zoneId
      end
    end
    return nil, zoneId
  end

  return depot.faction, nil
end

local function refreshDepotAccess()
  local access = {}
  for id in pairs(Config.Depots) do
    local owner, zoneId = getDepotControl(id)
    local allowed = owner and playerFaction == owner
    access[id] = {
      owner = owner,
      zoneId = zoneId,
      allowed = allowed
    }
  end
  depotAccess = access
  Blips.UpdateDepots(depotAccess)
end

local function pushUI()
  UI.Update({
    faction = playerFaction,
    state = warState,
    zones = zones,
    resources = resources,
    vehicles = vehicles,
    depots = Config.Depots,
    factions = Config.Factions,
    nearDepot = nearDepot,
    depotAccess = depotAccess,
    vehicleDefs = Config.Vehicles
  })
end

local function requestOpen(panel, reason)
  local now = GetGameTimer()
  if uiState ~= 'closed' then
    print(('[MW_UI] ignored open due to state=%s reason=%s'):format(uiState, tostring(reason)))
    return
  end
  if (now - lastUiAction) < uiDebounceMs then
    print(('[MW_UI] ignored open due to debounce reason=%s'):format(tostring(reason)))
    return
  end
  lastUiAction = now
  uiState = panel or 'hud'
  print(('[MW_UI] open requested reason=%s panel=%s'):format(tostring(reason), tostring(uiState)))
  UI.Open(uiState)
  pushUI()
end

local function requestClose(reason)
  if uiState == 'closed' and not UI.IsOpen() then return end
  lastUiAction = GetGameTimer()
  print(('[MW_UI] close requested reason=%s'):format(tostring(reason)))
  uiState = 'closed'
  UI.Close()
end

RegisterNetEvent(Constants.Events.PlayerInfo, function(data)
  playerFaction = data and data.faction or playerFaction
  VehicleStyling.SetPlayerFaction(playerFaction)
  refreshDepotAccess()
  pushUI()
end)

RegisterNetEvent(Constants.Events.State, function(data)
  warState = data or {}
  pushUI()
end)

RegisterNetEvent(Constants.Events.Zones, function(data)
  zones = data or {}
  refreshDepotAccess()
  pushUI()
end)

RegisterNetEvent(Constants.Events.Resources, function(data)
  resources = data or {}
  pushUI()
end)

RegisterNetEvent(Constants.Events.Vehicles, function(data)
  vehicles = data or {}
  pushUI()
end)

RegisterCommand(Constants.Keybinds.Hud, function()
  if uiState ~= 'closed' then
    requestClose('hud_toggle')
    return
  end
  if not playerFaction then
    requestOpen('faction', 'hud_toggle')
  else
    requestOpen('hud', 'hud_toggle')
  end
end)
RegisterKeyMapping(Constants.Keybinds.Hud, 'Toggle War HUD', 'keyboard', 'F1')

RegisterCommand(Constants.Keybinds.Map, function()
  if uiState == 'map' then
    requestClose('map_toggle')
    return
  end
  requestOpen('map', 'map_toggle')
end)
RegisterKeyMapping(Constants.Keybinds.Map, 'Toggle War Map', 'keyboard', 'F3')

RegisterCommand(Constants.Keybinds.Close, function()
  requestClose('key_close')
end)
RegisterKeyMapping(Constants.Keybinds.Close, 'Close War UI', 'keyboard', 'BACKSPACE')

UI.Init({
  onClose = function()
    requestClose('nui_close')
  end,
  onSelectFaction = function(data)
    if data and data.faction then
      TriggerServerEvent(Constants.Events.RequestJoin, data.faction)
    end
    requestClose('faction_selected')
  end,
  onSpawnVehicle = function(data)
    if data and data.vehicleId and data.depotId then
      print(('[MW_SIM] client spawn request depot=%s vehicle=%s requestId=%s'):format(data.depotId, data.vehicleId, tostring(data.requestId)))
      requestClose('spawn_request')
      pendingSpawn = {
        depotId = data.depotId,
        vehicleId = data.vehicleId,
        requestId = data.requestId,
        requestedAt = GetGameTimer()
      }
      TriggerServerEvent(Constants.Events.RequestSpawn, {
        vehicleId = data.vehicleId,
        depotId = data.depotId,
        requestId = data.requestId
      })
    end
  end,
  onRequestRepair = function(data)
    if data and data.netId then
      TriggerServerEvent(Constants.Events.RequestRepair, { netId = data.netId })
    end
  end
})

RegisterNetEvent(Constants.Events.SpawnResult, function(data)
  print(('[MW] Server spawned vehicle netId=%s ok=%s reason=%s'):format(data and data.netId or 'nil', tostring(data and data.ok), data and data.reason or ''))
  if not data or not data.ok then
    local reason = data and data.reason or 'Spawn denied'
    UI.Toast('error', reason)
    pendingSpawn = nil
    return
  end

  local netId = data.netId
  local label = data.label or (pendingSpawn and Config.Vehicles[pendingSpawn.vehicleId] and Config.Vehicles[pendingSpawn.vehicleId].label) or 'Vehicle'
  UI.Toast('success', ('Vehicle spawned: %s'):format(label))

  VehicleStyling.Register(netId, { factionId = data.faction, style = data.style })
  Blips.SetSpawnedVehicle(netId, data.coords, label)

  if pendingSpawn then
    pendingSpawn.netId = netId
  end
  pendingSpawn = nil
end)

CreateThread(function()
  Wait(1000)
  Blips.Init()
  TriggerServerEvent(Constants.Events.RequestStatus)
end)

AddEventHandler('onClientResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  print('[MW_SIM] VERSION 2026-01-30-A | resource=' .. GetCurrentResourceName())
end)

CreateThread(function()
  while true do
    if UI.IsOpen() then
      if IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
        requestClose('escape')
      end
      Wait(50)
    else
      Wait(250)
    end
  end
end)

CreateThread(function()
  while true do
    Wait(250)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local found = nil

    for id, depot in pairs(Config.Depots) do
      local dist = Utils.distance(coords, depot.coords)
      if dist <= (depot.radius or 6.0) then
        found = id
        break
      end
    end

    if found ~= nearDepot then
      nearDepot = found
      pushUI()
    end

    if nearDepot and IsControlJustPressed(0, 38) then
      local access = depotAccess[nearDepot]
      if access and access.allowed then
        requestOpen('depot', 'depot_interact')
      else
        local owner = access and access.owner or 'neutral'
        UI.Toast('error', ('Depot controlled by %s'):format(tostring(owner)))
      end
    end
  end
end)
VehicleStyling.StartMonitor()
