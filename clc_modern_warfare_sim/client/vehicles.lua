local Config = MW.require('shared/config.lua')
local UI = MW.require('client/ui.lua')

local Vehicles = {}
local registry = {}
local styledVehicles = {}
local lastEntryNetId = nil
local lastSeatWasDriver = nil
local playerFaction = nil

local xenonPalette = {
  { 255, 255, 255 },
  { 2, 21, 255 },
  { 3, 83, 255 },
  { 0, 255, 140 },
  { 94, 255, 1 },
  { 255, 255, 0 },
  { 255, 150, 0 },
  { 255, 80, 0 },
  { 255, 0, 0 },
  { 255, 0, 255 },
  { 255, 32, 160 },
  { 180, 0, 255 },
  { 120, 0, 255 }
}

local function nearestXenonIndex(r, g, b)
  local best, bestDist = 0, math.huge
  for i, color in ipairs(xenonPalette) do
    local dr = r - color[1]
    local dg = g - color[2]
    local db = b - color[3]
    local dist = (dr * dr) + (dg * dg) + (db * db)
    if dist < bestDist then
      bestDist = dist
      best = i - 1
    end
  end
  return best
end

local function resolveChannel(color, key)
  if not color then return nil end
  if type(color) == 'table' and color[key] then return color[key] end
  if type(color) == 'table' and color[1] then return color[key == 'r' and 1 or key == 'g' and 2 or 3] end
  return nil
end

local function getStyleColors(style)
  local pr = resolveChannel(style and style.primary, 'r') or 255
  local pg = resolveChannel(style and style.primary, 'g') or 255
  local pb = resolveChannel(style and style.primary, 'b') or 255
  local sr = resolveChannel(style and style.secondary, 'r') or pr
  local sg = resolveChannel(style and style.secondary, 'g') or pg
  local sb = resolveChannel(style and style.secondary, 'b') or pb
  return pr, pg, pb, sr, sg, sb
end

local function getVehicleColorState(veh)
  local pr, pg, pb = GetVehicleCustomPrimaryColour(veh)
  local sr, sg, sb = GetVehicleCustomSecondaryColour(veh)
  local xenonEnabled = IsToggleModOn(veh, 22)
  local xenonId = GetVehicleXenonLightsColor(veh)
  return {
    primary = { pr, pg, pb },
    secondary = { sr, sg, sb },
    xenonEnabled = xenonEnabled,
    xenonId = xenonId
  }
end

local function applyStyleToEntity(veh, netId, factionId, phase)
  if not veh or veh == 0 then
    print(('[MW_STYLE] skipped reason=vehicle invalid netId=%s'):format(tostring(netId)))
    return false
  end
  if not DoesEntityExist(veh) then
    print(('[MW_STYLE] skipped reason=entity missing netId=%s'):format(tostring(netId)))
    return false
  end
  local faction = Config.Factions[factionId or ''] or nil
  local style = faction and faction.Style or nil
  if not style then
    print(('[MW_STYLE] skipped reason=style config missing faction=%s netId=%s'):format(tostring(factionId), tostring(netId)))
    return false
  end

  local pr, pg, pb, sr, sg, sb = getStyleColors(style)
  local xenonId = style.xenonId
  if xenonId == nil then
    xenonId = nearestXenonIndex(pr, pg, pb)
  end

  local before = getVehicleColorState(veh)

  SetVehicleModKit(veh, 0)
  SetVehicleCustomPrimaryColour(veh, pr, pg, pb)
  SetVehicleCustomSecondaryColour(veh, sr, sg, sb)
  ToggleVehicleMod(veh, 22, true)
  SetVehicleXenonLightsColor(veh, xenonId)

  local after = getVehicleColorState(veh)
  print(('[MW_STYLE] applied primary=%s,%s,%s secondary=%s,%s,%s xenonId=%s'):format(
    tostring(pr), tostring(pg), tostring(pb),
    tostring(sr), tostring(sg), tostring(sb),
    tostring(xenonId)
  ))
  return true
end

local function toast(message)
  if not message then return end
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(message)
  EndTextCommandThefeedPostTicker(false, true)
end

function Vehicles.Register(netId, payload)
  if not netId or not payload then return end
  registry[netId] = {
    factionId = payload.factionId or payload.faction or payload.id,
    style = payload.style
  }
end

function Vehicles.SetPlayerFaction(factionId)
  playerFaction = factionId
end

function Vehicles.ApplyWhenReady(netId, style)
  Vehicles.Register(netId, style)
end

function Vehicles.StartMonitor()
  CreateThread(function()
    while true do
      Wait(200)
      local ped = PlayerPedId()
      if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        local isDriver = (GetPedInVehicleSeat(veh, -1) == ped)
        local netId = NetworkGetNetworkIdFromEntity(veh)
        if netId ~= 0 and (netId ~= lastEntryNetId or lastSeatWasDriver ~= isDriver) then
          lastEntryNetId = netId
          lastSeatWasDriver = isDriver
          if not isDriver then
            print(('[MW_STYLE] skipped reason=seat not -1 netId=%s'):format(tostring(netId)))
          else
            local netVeh = NetToVeh(netId)
            if netVeh == 0 then
              print(('[MW_STYLE] skipped reason=NetToVeh returned 0 netId=%s'):format(tostring(netId)))
            else
              local entry = registry[netId]
              local factionId = (entry and entry.factionId) or playerFaction
              print(('[MW_STYLE] enter seat=-1 netId=%s faction=%s'):format(tostring(netId), tostring(factionId)))
              if not factionId then
                print(('[MW_STYLE] skipped reason=no_faction netId=%s'):format(tostring(netId)))
              elseif not styledVehicles[netId] then
                styledVehicles[netId] = true
                local applied = applyStyleToEntity(veh, netId, factionId, 'enter')
                if applied then
                  UI.Toast('success', 'Faction paint applied')
                  toast('Faction paint applied')
                end
                CreateThread(function()
                  Wait(400)
                  if DoesEntityExist(veh) then
                    local faction = Config.Factions[factionId or '']
                    local style = faction and faction.Style or nil
                    if not style then
                      print(('[MW_STYLE] skipped reason=style config missing netId=%s'):format(tostring(netId)))
                      return
                    end
                    local after = getVehicleColorState(veh)
                    local pr, pg, pb = getStyleColors(style)
                    local override = after.primary[1] ~= pr or after.primary[2] ~= pg or after.primary[3] ~= pb
                    if override then
                      print(('[MW_STYLE] override detected netId=%s reapply'):format(tostring(netId)))
                      applyStyleToEntity(veh, netId, factionId, 'reapply')
                    end
                  end
                end)
              end
            end
          end
        end
      else
        lastEntryNetId = nil
        lastSeatWasDriver = nil
      end
    end
  end)
end

return Vehicles
