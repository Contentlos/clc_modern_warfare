local Database = MW.require('server/database.lua')
local Utils = MW.require('shared/utils.lua')

local Persistence = {}
local resourceName = GetCurrentResourceName()
local stateFile = 'data_state.json'
local playersFile = 'data_players.json'
local playersCache = nil

local function loadJson(path, fallback)
  local content = LoadResourceFile(resourceName, path)
  if not content or content == '' then
    return fallback
  end
  local ok, data = pcall(json.decode, content)
  if not ok or type(data) ~= 'table' then
    return fallback
  end
  return data
end

local function saveJson(path, data)
  SaveResourceFile(resourceName, path, json.encode(data or {}), -1)
end

function Persistence.Init()
  Database.Init()
end

function Persistence.LoadSnapshot()
  if Database.IsUsingSQL() then
    local row = Database.Single('SELECT `value` FROM `mw_war_state` WHERE `key` = ?', { 'snapshot' })
    if row and row.value then
      local ok, data = pcall(json.decode, row.value)
      if ok and type(data) == 'table' then
        return data
      end
    end
    return nil
  end

  return loadJson(stateFile, nil)
end

function Persistence.SaveSnapshot(snapshot)
  if Database.IsUsingSQL() then
    Database.Execute('REPLACE INTO `mw_war_state` (`key`, `value`) VALUES (?, ?)', {
      'snapshot', json.encode(snapshot or {})
    })
    return
  end

  saveJson(stateFile, snapshot or {})
end

function Persistence.GetPlayerFaction(identifier)
  if not identifier then return nil end

  if Database.IsUsingSQL() then
    local row = Database.Single('SELECT `faction` FROM `mw_players` WHERE `identifier` = ?', { identifier })
    return row and row.faction or nil
  end

  if not playersCache then
    playersCache = loadJson(playersFile, {})
  end

  return playersCache[identifier]
end

function Persistence.SetPlayerFaction(identifier, faction)
  if not identifier or not faction then return end

  if Database.IsUsingSQL() then
    Database.Execute('INSERT INTO `mw_players` (`identifier`, `faction`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `faction` = VALUES(`faction`)', {
      identifier, faction
    })
    return
  end

  if not playersCache then
    playersCache = loadJson(playersFile, {})
  end

  playersCache[identifier] = faction
  saveJson(playersFile, playersCache)
end

return Persistence
