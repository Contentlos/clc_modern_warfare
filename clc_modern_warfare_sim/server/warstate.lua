local Config = MW.require('shared/config.lua')
local Constants = MW.require('shared/constants.lua')
local Utils = MW.require('shared/utils.lua')

local WarState = {}
local state = {}

local function buildDefault()
  local zones = {}
  for id, zone in pairs(Config.Zones) do
    local owner = zone.owner
    if owner == 'neutral' then owner = nil end
    zones[id] = {
      id = id,
      owner = owner,
      state = owner and Constants.ZoneState.Captured or Constants.ZoneState.Neutral,
      progress = zone.captureTime or Config.War.CaptureTime,
      contestedBy = nil,
      lastCapture = owner and Utils.now() or nil
    }
  end

  local tickets = {}
  local resources = {}
  for id in pairs(Config.Factions) do
    tickets[id] = Config.War.TicketStart
    resources[id] = { fuel = 0, ammo = 0, parts = 0 }
  end

  return {
    phase = Constants.WarPhases.Active,
    startedAt = Utils.now(),
    tickets = tickets,
    resources = resources,
    zones = zones
  }
end

local function mergeSnapshot(snapshot)
  if type(snapshot) ~= 'table' then return end
  if snapshot.phase then state.phase = snapshot.phase end
  if snapshot.tickets then state.tickets = snapshot.tickets end
  if snapshot.resources then state.resources = snapshot.resources end
  if snapshot.zones then state.zones = snapshot.zones end
  if snapshot.startedAt then state.startedAt = snapshot.startedAt end
end

function WarState.Init(snapshot)
  state = buildDefault()
  mergeSnapshot(snapshot)
end

function WarState.Reset()
  state = buildDefault()
end

function WarState.Get()
  return state
end

function WarState.GetSnapshot()
  return Utils.deepcopy(state)
end

function WarState.SetPhase(phase)
  state.phase = phase
end

function WarState.Start()
  state.phase = Constants.WarPhases.Active
  state.startedAt = Utils.now()
end

function WarState.Pause()
  state.phase = Constants.WarPhases.Paused
end

function WarState.Resume()
  state.phase = Constants.WarPhases.Active
end

function WarState.IsActive()
  return state.phase == Constants.WarPhases.Active
end

function WarState.GetResources(faction)
  return state.resources[faction]
end

function WarState.AddResources(faction, delta)
  local res = state.resources[faction]
  if not res then return end
  res.fuel = res.fuel + (delta.fuel or 0)
  res.ammo = res.ammo + (delta.ammo or 0)
  res.parts = res.parts + (delta.parts or 0)
end

function WarState.CanAfford(faction, cost)
  local res = state.resources[faction]
  if not res then return false end
  return (res.fuel >= (cost.fuel or 0))
    and (res.ammo >= (cost.ammo or 0))
    and (res.parts >= (cost.parts or 0))
end

function WarState.Consume(faction, cost)
  if not WarState.CanAfford(faction, cost) then return false end
  local res = state.resources[faction]
  res.fuel = res.fuel - (cost.fuel or 0)
  res.ammo = res.ammo - (cost.ammo or 0)
  res.parts = res.parts - (cost.parts or 0)
  return true
end

function WarState.GetTickets(faction)
  return state.tickets[faction]
end

function WarState.ApplyTicketLoss(faction, amount)
  if not state.tickets[faction] then return end
  state.tickets[faction] = math.max(0, state.tickets[faction] - amount)
  if state.tickets[faction] == 0 then
    state.phase = Constants.WarPhases.Concluded
  end
end

function WarState.SetZoneState(zoneId, data)
  if not state.zones[zoneId] then return end
  for k, v in pairs(data) do
    state.zones[zoneId][k] = v
  end
end

function WarState.GetZones()
  return state.zones
end

return WarState
