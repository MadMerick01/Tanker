-- The game's side of a Hoon: its car, loaded once and then kept hidden (switched off, so it costs
-- nothing and is not drawn) until an attack. Switching a car back on is instant, where spawning
-- one mid-drive hitches the frame rate. Every game call is guarded: a missing or changed one
-- means no Hoon, never an error.
local M = {}
local behind = require('tanker/behind')

-- The Hoon's car: one of Rowan's Barstows, shipped in the mod under vehicles/barstow, each
-- equally likely (Rowan, 6 Nov): HoonOld1 (rusty, I6, welded diff, rollcage, offroad tyres) and
-- HoonFast2 (supercharged V8, cowl hood, rollcage). If the game has no Barstow, a plain one of
-- the other vanilla muscle cars, in order, is used instead.
M.MODELS = { 'barstow', 'moonhawk', 'burnside' }
M.HOONS = { 'hoonold1', 'hoonfast2' }
local function configPath(name) return 'vehicles/barstow/' .. name .. '.pc' end
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
    -- Where the camera is and which way it looks (tanker/behind.lua keeps spawns out of its view).
    cameraPosition = function()
      if type(getCameraPosition) == 'function' then return getCameraPosition() end
      if core_camera and core_camera.getPosition then return core_camera.getPosition() end
    end,
    cameraForward = function()
      if type(getCameraForward) == 'function' then return getCameraForward() end
      if core_camera and core_camera.getForward then return core_camera.getForward() end
    end,
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

-- Runs inside the Hoon's car: hunt the player with Tanker's own driver, which follows the roads
-- to you with Rowan's country driving limits and rams once close (tankerDriver.lua). If that
-- can't be loaded, BeamNG's chase AI does it instead, flat out and not avoiding anyone.
local HUNT = [[
if extensions and not extensions.tankerDriver then pcall(extensions.load, 'tankerDriver') end
if extensions and extensions.tankerDriver then
  extensions.tankerDriver.chase(%d)
elseif ai then
  pcall(ai.setMode, 'chase')
  pcall(ai.setTargetObjectID, %d)
  pcall(ai.setAggression, 1)
  pcall(ai.setAvoidCars, 'off')
  pcall(ai.setSpeedMode, 'off')
  -- With Rowan's smartAI mod installed, drive like a person on open roads.
  if ai.setSmartProfile then pcall(ai.setSmartProfile, 'moonhawk_country') end
end
]]
local STOP = [[
if extensions and extensions.tankerDriver then extensions.tankerDriver.stop() end
if ai then pcall(ai.setMode, 'disabled') end
]]

-- pool is Tanker's traffic pool (trafficPool.lua), or nil: a Hoon's car is taken from it first.
function M.new(environment, pool)
  local env = environment or defaults()
  local h = { pool = pool }

  -- The player's own vehicle is never a Hoon (Rowan, 6 Nov): if the game ever puts you in a Hoon's
  -- car, Tanker stops commanding it at once, and the Hoon is forgotten as if its car had gone.
  local function playerId()
    local ok, c = pcall(env.player)
    if not (ok and c) then return nil end
    local okId, id = pcall(function() return c:getID() end)
    if okId then return id end
  end
  local function car(id)
    if id == nil or id == playerId() then return nil end
    local ok, c = pcall(env.byId, id)
    return ok and c or nil
  end
  -- A Hoon's car can't be switched into from the game's vehicle switching.
  local function notForPlayer(c) pcall(function() c.playerUsable = false end) end

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

  -- A car of this model taken out of Tanker's traffic pool, the one furthest from you, or nil.
  function h:fromPool(name, me, config)
    if not (self.pool and me) then return nil end
    local ok, id = pcall(self.pool.take, self.pool, name, me.x, me.y, config)
    if ok and type(id) == 'number' and car(id) then return id end
  end

  -- The Hoon's car, switched off at once: a HoonOld1 from Tanker's traffic pool, or else one
  -- loaded high above the player. Returns its id and model.
  function h:load()
    local me = self:player()
    if not me then return nil, 'vehicle_required' end
    local name = self:model()
    if not name then return nil, 'no_hoon_model' end
    -- Which Hoon: HoonOld1 or HoonFast2, even odds. From the pool, that one if it has one left,
    -- else the other; failing both, the chosen one is loaded.
    local config
    if name == 'barstow' then
      local roll = env.random and env.random() or math.random()
      local first = roll < 0.5 and 1 or 2
      config = M.HOONS[first]
      for _, pick in ipairs({ M.HOONS[first], M.HOONS[3 - first] }) do
        local pooled = self:fromPool(name, me, pick)
        if pooled then
          self:hide(pooled)
          return pooled, name, pick
        end
      end
    else
      local pooled = self:fromPool(name, me)
      if pooled then
        self:hide(pooled)
        return pooled, name
      end
    end
    local okVehicles, vehicles = pcall(env.vehicles)
    if not okVehicles or type(vehicles) ~= 'table' or type(vehicles.spawnNewVehicle) ~= 'function' then
      return nil, 'spawn_unavailable'
    end
    local okPos, pos = pcall(env.vec3, me.x, me.y, me.z + M.HIDE_LIFT)
    local ok, c = pcall(vehicles.spawnNewVehicle, name,
      { config = config and configPath(config), pos = okPos and pos or nil, autoEnterVehicle = false })
    if not ok or not c then return nil, 'spawn_failed', tostring(c) end
    local okId, id = pcall(function() return c:getID() end)
    if not okId or type(id) ~= 'number' then return nil, 'spawn_failed' end
    self:hide(id)
    return id, name, config
  end

  -- Stops the car's AI and switches it off, above wherever the player is.
  function h:hide(id)
    local c = car(id)
    if not c then return false end
    notForPlayer(c)
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

  -- The height of the ground under x, y (looking from a few metres above z), or nil.
  -- The camera: { x, y, dx, dy } flat, or nil.
  function h:camera() return behind.camera(env) end

  function h:ground(x, y, z)
    local ok, g = pcall(env.ground, x, y, z)
    if ok and finite(g) then return g end
  end

  -- Switches car id on and puts it down at x, y, z facing along dx, dy. Returns true, or false and why.
  function h:put(id, x, y, z, dx, dy)
    local c = car(id)
    if not c then return false, 'no_car' end
    notForPlayer(c)
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
    return true
  end

  -- Moves car id a little way to x, y, z without resetting it, so its damage (shot tyres and
  -- all) stays as it was: for lifting a car past a bush out of sight. Falls back to put().
  function h:hop(id, x, y, z, dx, dy)
    local c = car(id)
    if not c then return false, 'no_car' end
    local okPos, pos = pcall(env.vec3, x, y, z + 0.5)
    if okPos and pcall(function() c:setPositionNoPhysicsReset(pos) end) then return true end
    return self:put(id, x, y, z, dx, dy)
  end

  -- Sets car id hunting targetId: BeamNG's chase mode, flat out and not avoiding anyone, so it rams.
  function h:hunt(id, targetId)
    local c = car(id)
    return c ~= nil and (pcall(function() c:queueLuaCommand(string.format(HUNT, targetId, targetId)) end))
  end

  -- Puts the Hoon on the road at x, y, z facing the player, switches it on and sets it hunting.
  function h:attack(id, x, y, z, targetId)
    local me = self:player()
    if not (car(id) and me) then return false, 'no_car' end
    local ok, why = self:put(id, x, y, z, me.x - x, me.y - y)
    if not ok then return false, why end
    self:hunt(id, targetId)
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
