local Utils = {}

function Utils.clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

function Utils.tableSize(tbl)
  local count = 0
  for _ in pairs(tbl or {}) do count = count + 1 end
  return count
end

function Utils.deepcopy(tbl)
  if type(tbl) ~= 'table' then return tbl end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = Utils.deepcopy(v)
  end
  return copy
end

function Utils.vec3(v)
  if type(v) == 'vector3' then return v end
  if type(v) == 'table' then
    return vector3(v.x or v[1] or 0.0, v.y or v[2] or 0.0, v.z or v[3] or 0.0)
  end
  return vector3(0.0, 0.0, 0.0)
end

function Utils.distance(a, b)
  local va = Utils.vec3(a)
  local vb = Utils.vec3(b)
  local dx = va.x - vb.x
  local dy = va.y - vb.y
  local dz = va.z - vb.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Utils.now()
  return os.time()
end

function Utils.safeNumber(value, fallback)
  if type(value) ~= 'number' then return fallback end
  return value
end

function Utils.safeString(value, fallback)
  if type(value) ~= 'string' then return fallback end
  return value
end

function Utils.logDebug(enabled, msg)
  if enabled then
    print(('[MW] %s'):format(msg))
  end
end

return Utils
