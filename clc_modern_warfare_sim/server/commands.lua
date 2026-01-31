local Config = MW.require('shared/config.lua')
local Constants = MW.require('shared/constants.lua')
local WarState = MW.require('server/warstate.lua')
local Players = MW.require('server/players.lua')
local AI = MW.require('server/ai.lua')

local Commands = {}

local function isAdmin(src)
  if src == 0 then return true end
  return IsPlayerAceAllowed(src, 'war.admin') or IsPlayerAceAllowed(src, 'command.war_admin')
end

local function sendMsg(src, msg)
  if src == 0 then
    print(('[MW] %s'):format(msg))
  else
    TriggerClientEvent('chat:addMessage', src, { args = { 'WAR', msg } })
  end
end

function Commands.Init()
  RegisterCommand(Constants.Commands.JoinFaction, function(src, args)
    local faction = args[1]
    if not faction or not Config.Factions[faction] then
      sendMsg(src, 'Invalid faction id')
      return
    end
    Players.SetFaction(src, faction)
    TriggerClientEvent(Constants.Events.PlayerInfo, src, { faction = faction })
    sendMsg(src, ('Faction set to %s'):format(faction))
  end)

  RegisterCommand(Constants.Commands.WarStatus, function(src)
    local state = WarState.GetSnapshot()
    sendMsg(src, ('Phase: %s | Tickets: %s'):format(state.phase, json.encode(state.tickets)))
  end)

  RegisterCommand(Constants.Commands.WarReset, function(src)
    if not isAdmin(src) then return end
    WarState.Reset()
    sendMsg(src, 'War reset')
  end)

  RegisterCommand(Constants.Commands.WarSetZone, function(src, args)
    if not isAdmin(src) then return end
    local zoneId = args[1]
    local faction = args[2]
    if not Config.Zones[zoneId] then
      sendMsg(src, 'Invalid zone id')
      return
    end
    if faction == 'neutral' then faction = nil end
    if faction and not Config.Factions[faction] then
      sendMsg(src, 'Invalid faction id')
      return
    end
    WarState.SetZoneState(zoneId, {
      owner = faction,
      state = faction and Constants.ZoneState.Captured or Constants.ZoneState.Neutral,
      contestedBy = nil,
      progress = Config.War.CaptureTime
    })
    sendMsg(src, ('Zone %s set to %s'):format(zoneId, faction or 'neutral'))
  end)

  RegisterCommand(Constants.Commands.WarGiveRes, function(src, args)
    if not isAdmin(src) then return end
    local faction = args[1]
    local resType = args[2]
    local amount = tonumber(args[3] or '0')
    if not Config.Factions[faction] then
      sendMsg(src, 'Invalid faction id')
      return
    end
    if not Config.Resources[resType] then
      sendMsg(src, 'Invalid resource type')
      return
    end
    WarState.AddResources(faction, { [resType] = amount })
    sendMsg(src, ('Gave %d %s to %s'):format(amount, resType, faction))
  end)

  RegisterCommand(Constants.Commands.AIStatus, function(src)
    if not isAdmin(src) then return end
    local summary = AI.GetStatus()
    for zoneId, data in pairs(summary) do
      sendMsg(src, ('AI %s | total=%d | status=%s'):format(zoneId, data.total, data.status))
    end
  end)

  RegisterCommand(Constants.Commands.AIClear, function(src, args)
    if not isAdmin(src) then return end
    local zoneId = args[1]
    if not zoneId or not Config.Zones[zoneId] then
      sendMsg(src, 'Invalid zone id')
      return
    end
    AI.ClearZone(zoneId)
    sendMsg(src, ('AI cleared in %s'):format(zoneId))
  end)
end

return Commands
