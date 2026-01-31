local Config = MW.require('shared/config.lua')

local Blips = {}
local created = {
  static = {},
  depots = {}
}
local spawnedBlip = nil

local function addBlip(coords, sprite, color, scale, name)
  local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
  SetBlipSprite(blip, sprite)
  SetBlipDisplay(blip, 4)
  SetBlipScale(blip, scale)
  SetBlipColour(blip, color)
  SetBlipAsShortRange(blip, true)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString(name)
  EndTextCommandSetBlipName(blip)
  return blip
end

function Blips.Init()
  for _, blip in pairs(created.static) do
    RemoveBlip(blip)
  end
  created.static = {}

  for _, faction in pairs(Config.Factions) do
    local coords = faction.hq
    local blip = addBlip(coords, 60, 3, 0.9, faction.label .. ' HQ')
    created.static[#created.static + 1] = blip
  end

  for _, zone in pairs(Config.Zones) do
    local radius = zone.radius or 200.0
    local area = AddBlipForRadius(zone.center.x, zone.center.y, zone.center.z, radius)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 100)
    created.static[#created.static + 1] = area
  end
end

function Blips.UpdateDepots(depotAccess)
  for _, blip in pairs(created.depots) do
    RemoveBlip(blip)
  end
  created.depots = {}

  for id, depot in pairs(Config.Depots) do
    local access = depotAccess and depotAccess[id]
    if access and access.allowed then
      local blip = addBlip(depot.coords, 524, 5, 0.8, depot.label)
      created.depots[#created.depots + 1] = blip
    end
  end
end

function Blips.SetSpawnedVehicle(netId, coords, label)
  if spawnedBlip then
    RemoveBlip(spawnedBlip)
    spawnedBlip = nil
  end

  if netId and NetworkDoesEntityExistWithNetworkId(netId) then
    local veh = NetToVeh(netId)
    if veh and DoesEntityExist(veh) then
      spawnedBlip = AddBlipForEntity(veh)
    end
  end

  if not spawnedBlip and coords then
    spawnedBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
  end

  if spawnedBlip then
    SetBlipSprite(spawnedBlip, 225)
    SetBlipColour(spawnedBlip, 2)
    SetBlipScale(spawnedBlip, 0.9)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Vehicle')
    EndTextCommandSetBlipName(spawnedBlip)
  end
end

function Blips.ClearSpawnedVehicle()
  if spawnedBlip then
    RemoveBlip(spawnedBlip)
    spawnedBlip = nil
  end
end

return Blips
