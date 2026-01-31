-- Lightweight module loader for this resource.
-- Keeps module cache private; exposes only MW.require.
local resourceName = GetCurrentResourceName()
local cache = {}

local function buildEnv()
  local env = {}
  setmetatable(env, { __index = _G })
  env.require = MW and MW.require or nil
  return env
end

local function requireModule(path)
  if type(path) ~= 'string' then
    error(('[mw.require] path must be a string, got %s'):format(type(path)))
  end

  if cache[path] then
    return cache[path]
  end

  local file = LoadResourceFile(resourceName, path)
  if not file then
    error(('[mw.require] module not found: %s'):format(path))
  end

  local env = buildEnv()
  env.require = requireModule

  local chunk, err = load(file, ('@@%s/%s'):format(resourceName, path), 't', env)
  if not chunk then
    error(('[mw.require] load error in %s: %s'):format(path, err or 'unknown'))
  end

  local result = chunk()
  if result == nil then
    error(('[mw.require] module %s did not return a table'):format(path))
  end

  cache[path] = result
  return result
end

MW = {
  require = requireModule
}
