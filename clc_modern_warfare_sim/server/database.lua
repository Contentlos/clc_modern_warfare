local Config = MW.require('shared/config.lua')
local Utils = MW.require('shared/utils.lua')

local Database = {
  usingSQL = false
}

local function await(cb)
  local p = promise.new()
  cb(function(result) p:resolve(result) end)
  return Citizen.Await(p)
end

local function hasOxMySQL()
  return GetResourceState('oxmysql') == 'started' and exports.oxmysql ~= nil
end

function Database.Init()
  if Config.UseSQL and hasOxMySQL() then
    Database.usingSQL = true
    Database.EnsureSchema()
    Utils.logDebug(Config.Debug, 'SQL persistence enabled')
  else
    if Config.UseSQL then
      print('[MW] oxmysql not started; falling back to JSON persistence')
    end
    Database.usingSQL = false
  end
end

function Database.IsUsingSQL()
  return Database.usingSQL
end

function Database.Execute(query, params)
  if not Database.usingSQL then return nil end
  return await(function(done)
    exports.oxmysql:execute(query, params or {}, done)
  end)
end

function Database.Query(query, params)
  if not Database.usingSQL then return nil end
  return await(function(done)
    exports.oxmysql:query(query, params or {}, done)
  end)
end

function Database.Single(query, params)
  if not Database.usingSQL then return nil end
  return await(function(done)
    exports.oxmysql:single(query, params or {}, done)
  end)
end

function Database.Scalar(query, params)
  if not Database.usingSQL then return nil end
  return await(function(done)
    exports.oxmysql:scalar(query, params or {}, done)
  end)
end

function Database.EnsureSchema()
  local createState = [[
    CREATE TABLE IF NOT EXISTS `mw_war_state` (
      `key` VARCHAR(64) NOT NULL,
      `value` LONGTEXT NOT NULL,
      PRIMARY KEY (`key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]]
  local createPlayers = [[
    CREATE TABLE IF NOT EXISTS `mw_players` (
      `identifier` VARCHAR(64) NOT NULL,
      `faction` VARCHAR(32) NOT NULL,
      `last_seen` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]]

  Database.Execute(createState)
  Database.Execute(createPlayers)

  local factionCol = Database.Query('SHOW COLUMNS FROM `mw_players` LIKE "faction"')
  if not factionCol or #factionCol == 0 then
    Database.Execute('ALTER TABLE `mw_players` ADD COLUMN `faction` VARCHAR(32) NOT NULL')
  end

  local lastSeenCol = Database.Query('SHOW COLUMNS FROM `mw_players` LIKE "last_seen"')
  if not lastSeenCol or #lastSeenCol == 0 then
    Database.Execute('ALTER TABLE `mw_players` ADD COLUMN `last_seen` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')
  end
end

return Database
