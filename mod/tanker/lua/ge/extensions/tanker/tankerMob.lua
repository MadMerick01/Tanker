-- The TankerMob: Rowan's fuel tanker truck (vehicles/us_semi/tankermob.pc). For now it comes from
-- the spawn button on the Rig tab: it appears behind the camera, out of sight, road or no road, and drives off away
-- from you (tankers flee). Stop it and siphon its tank. One at a time: pressing the button again
-- puts the same truck back behind the camera. Every game call is guarded: a missing or changed one
-- means no tanker, never an error.
local M = {}
local behind = require('tanker/behind')

-- One-line settings. Tune these after testing in game.
M.MODEL = 'us_semi'
M.CONFIG = 'vehicles/us_semi/tankermob.pc'
-- How far behind the camera it appears, in metres.
M.SPAWN_METRES = 60
-- How high above the ground it is put down, so it drops onto its wheels.
M.DROP_METRES = 0.5

-- Runs inside the tanker: drive away from the player.
local FLEE = [[
if ai then
  pcall(ai.setMode, 'flee')
  pcall(ai.setTargetObjectID, %d)
  pcall(ai.setAggression, 0.6)
end
]]

local function defaults()
  return {
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    byId = function(id) return be and be:getObjectByID(id) end,
    vec3 = function(x, y, z) return vec3(x, y, z) end,
    quatFromDir = function(dir, up) return quatFromDir(dir, up) end,
    spawn = function() return rawget(_G, 'spawn') end,
  }
end

-- car is hoonCar (for the player's position and the ground height).
function M.new(car, environment)
  local env = environment or defaults()
  local t = {}

  local function existing()
    if not t.id then return nil end
    local ok, c = pcall(env.byId, t.id)
    if ok and c then return c end
    t.id = nil
  end

  -- Puts the TankerMob behind the camera facing away from you, and sets it fleeing. Returns true, or false and why.
  function t:spawn()
    local me = car:player()
    if not me then return false, 'vehicle_required' end
    -- Out of sight (Rowan, 6 Nov): straight behind the camera, facing away from you.
    local view = behind.view(car, me)
    local x, y = behind.point(view, M.SPAWN_METRES)
    local fx, fy = x - me.x, y - me.y
    local flen = math.sqrt(fx * fx + fy * fy)
    if flen > 1e-6 then fx, fy = fx / flen, fy / flen else fx, fy = -me.dx, -me.dy end
    local z = (car.ground and car:ground(x, y, me.z) or me.z) + M.DROP_METRES
    local okPos, pos = pcall(env.vec3, x, y, z)
    local okDir, dir = pcall(env.vec3, fx, fy, 0)
    local okUp, up = pcall(env.vec3, 0, 0, 1)
    local okRot, rot = false, nil
    if okDir and okUp then okRot, rot = pcall(env.quatFromDir, dir, up) end
    if not okPos then return false, 'place_failed' end
    local c = existing()
    -- Tanker's traffic pool holds TankerMobs: take one out of traffic before loading a new one.
    if not c and car.fromPool then
      local pooled = car:fromPool(M.MODEL, me)
      if pooled then
        local okCar, made = pcall(env.byId, pooled)
        if okCar and made then
          t.id, c = pooled, made
          pcall(function() c:setActive(1) end)
        end
      end
    end
    if c then
      local placed = false
      local okSpawn, spawn = pcall(env.spawn)
      if okRot and okSpawn and type(spawn) == 'table' and type(spawn.safeTeleport) == 'function' then
        placed = pcall(spawn.safeTeleport, c, pos, rot)
      end
      if not placed then placed = pcall(function() c:setPositionRotation(x, y, z, 0, 0, 0, 1) end) end
      if not placed then return false, 'place_failed' end
    else
      local okVehicles, vehicles = pcall(env.vehicles)
      if not okVehicles or type(vehicles) ~= 'table' or type(vehicles.spawnNewVehicle) ~= 'function' then
        return false, 'spawn_unavailable'
      end
      local ok, made = pcall(vehicles.spawnNewVehicle, M.MODEL,
        { config = M.CONFIG, pos = pos, rot = okRot and rot or nil, autoEnterVehicle = false })
      if not ok or not made then return false, 'spawn_failed' end
      local okId, id = pcall(function() return made:getID() end)
      if not okId or type(id) ~= 'number' then return false, 'spawn_failed' end
      t.id, c = id, made
    end
    pcall(function() c:queueLuaCommand(string.format(FLEE, me.id)) end)
    return true
  end

  -- Removes the TankerMob for good, when Tanker goes away.
  function t:remove()
    local c = existing()
    if c then pcall(function() c:delete() end) end
    t.id = nil
  end

  return t
end

return M
