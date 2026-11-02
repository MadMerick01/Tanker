-- The game's side of a Hoon: its car, loaded once and then kept hidden (switched off, so it costs
-- nothing and is not drawn) until an attack. Switching a car back on is instant, where spawning
-- one mid-drive hitches the frame rate. Every game call is guarded: a missing or changed one
-- means no Hoon, never an error.
local M = {}

-- Vanilla cars tried for the Hoon, in order; the first one the game has is used.
M.MODELS = { 'hotrod', 'burnside', 'moonhawk' }
-- How high above the player the car waits while hidden, in metres.
M.HIDE_LIFT = 2000
-- A road point counts as solid when the ground under it is within this many metres of it.
M.SOLID_METRES = 3

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    byId = function(id) return be and be:getObjectByID(id) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    map = function() return rawget(_G, 'map') end,
    spawn = function() return rawget(_G, 'spawn') end,
    vec3 = function(x, y, z) return vec3(x, y, z) end,
    quatFromDir = function(dir, up) return quatFromDir(dir, up) end,
    -- The height of whatever is solid under x, y, from a few metres above z.
    ground = function(x, y, z)
      if be and be.getSurfaceHeightBelow then
        local h = be:getSurfaceHeightBelow(vec3(x, y, z + 5))
        if type(h) == 'number' and h > -1e6 then return h end
      end
      if type(castRayStatic) == 'function' then
        local d = castRayStatic(vec3(x, y, z + 5), vec3(0, 0, -1), 50)
        if type(d) == 'number' and d < 50 then return z + 5 - d end
      end
    end,
  }
end

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function xyz(p)
  if not p then return nil end
  local ok, x, y, z = pcall(function() return p.x, p.y, p.z end)
  if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
end

-- Runs inside the Hoon's car: hunt the player, flat out and not avoiding anyone, so it rams.
local HUNT = [[
if ai then
  pcall(ai.setMode, 'chase')
  pcall(ai.setTargetObjectID, %d)
  pcall(ai.setAggression, 1)
  pcall(ai.setAvoidCars, 'off')
  pcall(ai.setSpeedMode, 'off')
end
]]
local STOP = [[if ai then pcall(ai.setMode, 'disabled') end]]

function M.new(environment)
  local env = environment or defaults()
  local h = {}

  local function car(id)
    local ok, c = pcall(env.byId, id)
    return ok and c or nil
  end

  -- The player's car: position, facing (x, y on the ground) and speed.
  function h:player()
    local ok, c = pcall(env.player)
    if not ok or not c then return nil end
    local okId, id = pcall(function() return c:getID() end)
    local okPos, pos = pcall(function() return c:getPosition() end)
    local okDir, dir = pcall(function() return c:getDirectionVector() end)
    local okVel, vel = pcall(function() return c:getVelocity() end)
    local x, y, z = xyz(okPos and pos)
    if not (okId and type(id) == 'number' and x) then return nil end
    local dx, dy = 0, 1
    local fx, fy = xyz(okDir and dir)
    if fx then
      local len = math.sqrt(fx * fx + fy * fy)
      if len > 1e-6 then dx, dy = fx / len, fy / len end
    end
    local vx, vy, vz = xyz(okVel and vel)
    return { id = id, x = x, y = y, z = z, dx = dx, dy = dy,
      speed = vx and math.sqrt(vx * vx + vy * vy + vz * vz) or 0 }
  end

  -- The first of M.MODELS the game has, or nil.
  function h:model()
    local ok, vehicles = pcall(env.vehicles)
    if not ok or type(vehicles) ~= 'table' then return nil end
    if type(vehicles.getModel) ~= 'function' then return M.MODELS[1] end
    for _, name in ipairs(M.MODELS) do
      local okModel, found = pcall(vehicles.getModel, name)
      if okModel and type(found) == 'table' and next(found) ~= nil then return name end
    end
  end

  -- Loads the Hoon's car high above the player and switches it off at once. Returns its id.
  function h:load()
    local me = self:player()
    if not me then return nil, 'vehicle_required' end
    local name = self:model()
    if not name then return nil, 'no_hoon_model' end
    local okVehicles, vehicles = pcall(env.vehicles)
    if not okVehicles or type(vehicles) ~= 'table' or type(vehicles.spawnNewVehicle) ~= 'function' then
      return nil, 'spawn_unavailable'
    end
    local okPos, pos = pcall(env.vec3, me.x, me.y, me.z + M.HIDE_LIFT)
    local ok, c = pcall(vehicles.spawnNewVehicle, name, { pos = okPos and pos or nil, autoEnterVehicle = false })
    if not ok or not c then return nil, 'spawn_failed', tostring(c) end
    local okId, id = pcall(function() return c:getID() end)
    if not okId or type(id) ~= 'number' then return nil, 'spawn_failed' end
    self:hide(id)
    return id, name
  end

  -- Stops the car's AI and switches it off, above wherever the player is.
  function h:hide(id)
    local c = car(id)
    if not c then return false end
    pcall(function() c:queueLuaCommand(STOP) end)
    local me = self:player()
    if me then pcall(function() c:setPositionRotation(me.x, me.y, me.z + M.HIDE_LIFT, 0, 0, 0, 1) end) end
    return (pcall(function() c:setActive(0) end))
  end

  -- The nearest road to x, y, z: the closest point on it and how far that is.
  function h:road(x, y, z)
    local okMap, map = pcall(env.map)
    if not okMap or type(map) ~= 'table' or type(map.findClosestRoad) ~= 'function' or type(map.getMap) ~= 'function' then
      return nil
    end
    local okPos, pos = pcall(env.vec3, x, y, z)
    if not okPos then return nil end
    local ok, a, b = pcall(map.findClosestRoad, pos)
    if not ok or not a then return nil end
    local okNodes, nodes = pcall(function() return map.getMap().nodes end)
    if not okNodes or type(nodes) ~= 'table' then return nil end
    local ax, ay, az = xyz(nodes[a] and nodes[a].pos)
    local bx, by, bz = xyz(b and nodes[b] and nodes[b].pos)
    if not ax then return nil end
    if not bx then bx, by, bz = ax, ay, az end
    -- The closest point on the stretch of road between the two nodes.
    local sx, sy, sz = bx - ax, by - ay, bz - az
    local len2 = sx * sx + sy * sy + sz * sz
    local t = len2 > 1e-9 and math.max(0, math.min(1, ((x - ax) * sx + (y - ay) * sy + (z - az) * sz) / len2)) or 0
    local px, py, pz = ax + sx * t, ay + sy * t, az + sz * t
    return { x = px, y = py, z = pz, metres = math.sqrt((px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2) }
  end

  -- Whether there is solid ground at x, y, z: BeamNG.Earth streams its terrain in, so a road far
  -- from the player may not be there yet. The ground must be within SOLID_METRES of the road.
  function h:solid(x, y, z)
    local okBe, ground = pcall(env.ground, x, y, z)
    if not okBe or not finite(ground) then return false end
    return math.abs(ground - z) <= M.SOLID_METRES
  end

  -- Puts the Hoon on the road at x, y, z facing the player, switches it on and sets it hunting.
  function h:attack(id, x, y, z, targetId)
    local c = car(id)
    local me = self:player()
    if not (c and me) then return false, 'no_car' end
    local dx, dy = me.x - x, me.y - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then dx, dy, len = 0, 1, 1 end
    local okActive = pcall(function() c:setActive(1) end)
    if not okActive then return false, 'activate_failed' end
    local placed = false
    local okPos, pos = pcall(env.vec3, x, y, z + 0.5)
    local okDir, dir = pcall(env.vec3, dx / len, dy / len, 0)
    local okUp, up = pcall(env.vec3, 0, 0, 1)
    local okRot, rot = false, nil
    if okDir and okUp then okRot, rot = pcall(env.quatFromDir, dir, up) end
    local okSpawn, spawn = pcall(env.spawn)
    if okPos and okRot and okSpawn and type(spawn) == 'table' and type(spawn.safeTeleport) == 'function' then
      placed = pcall(spawn.safeTeleport, c, pos, rot)
    end
    if not placed then
      placed = pcall(function() c:setPositionRotation(x, y, z + 0.5, 0, 0, 0, 1) end)
    end
    if not placed then return false, 'place_failed' end
    pcall(function() c:queueLuaCommand(string.format(HUNT, targetId)) end)
    return true
  end

  -- Calms a downed Hoon so a wreck does not keep revving.
  function h:calm(id)
    local c = car(id)
    return c ~= nil and (pcall(function() c:queueLuaCommand(STOP) end))
  end

  -- Where the Hoon is and how fast it goes, or nil if the car is gone.
  function h:state(id)
    local c = car(id)
    if not c then return nil end
    local okPos, pos = pcall(function() return c:getPosition() end)
    local x, y, z = xyz(okPos and pos)
    if not x then return nil end
    local okVel, vel = pcall(function() return c:getVelocity() end)
    local vx, vy, vz = xyz(okVel and vel)
    return { x = x, y = y, z = z, speed = vx and math.sqrt(vx * vx + vy * vy + vz * vz) or 0 }
  end

  -- Removes the car for good, when Tanker goes away.
  function h:remove(id)
    local c = car(id)
    return c ~= nil and (pcall(function() c:delete() end))
  end

  return h
end

return M
