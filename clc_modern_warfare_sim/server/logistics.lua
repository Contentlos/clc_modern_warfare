local Config = MW.require('shared/config.lua')
local WarState = MW.require('server/warstate.lua')

local Logistics = {}

function Logistics.Tick()
  if not WarState.IsActive() then return end

  local zones = WarState.GetZones()
  for zoneId, state in pairs(zones) do
    if state.owner then
      local yield = Config.Zones[zoneId].resourceYield
      if yield then
        WarState.AddResources(state.owner, yield)
      end
    end
  end
end

return Logistics
