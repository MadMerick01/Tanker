-- tankerDriver: Tanker's own Hoon driver, run inside a Hoon's car. Off road, Tanker sends it a
-- point to drive at and a speed, a few times a second (target below). On the roads it chases a
-- car by itself (chase below, and road mode further down); every frame it works out steering,
-- throttle and brake itself and drives the car with them, the way BeamNG's AI does. It takes over
-- from BeamNG's AI while it drives (the AI is switched off) and hands back on stop().
--
-- Its limits come from Rowan's logged driving (BeamngAdvancedSelfDriving, smartAI's
-- moonhawk_country profile): about 0.9 g cornering, 0.65 g braking and 0.45 g accelerating, all
-- capped by the grip of the ground under the car.
--
-- Steering is pure pursuit: the arc from the car to the point gives a curvature, and the wheelbase
-- turns that into a wheel angle, with yaw-rate damping so it doesn't weave. Speed is the asked-for
-- speed, capped by what the arc allows at the cornering limit. If the car pushes for a while
-- without moving it backs off and tries again, as smartAI does.
--
-- The maths (M.control) uses no game calls, so it can be tested outside the game.
local M = {}

-- One-line settings. Tune these after testing in game.
local G = 9.81
-- Cornering, braking and accelerating limits, in g (Rowan's country driving).
M.LAT_G, M.BRAKE_G, M.ACCEL_G = 0.9, 0.65, 0.45
-- The front wheels' full lock, in radians, used to turn a wheel angle into a steering input.
M.STEER_LOCK = 0.6
-- How fast the steering input may move, per second (a person turns the wheel, they don't flick it).
M.STEER_RATE = 2.5
-- Yaw-rate damping: steering taken off per radian a second of turning more than the arc needs.
M.YAW_DAMP = 0.15
-- The speed controller: how quickly it closes a speed gap (seconds), and pedal gains per m/s².
M.SPEED_TAU = 0.8
-- Wheel speed above the car's speed by more than this share (plus 2 m/s) is wheelspin: ease off.
M.SPIN_SHARE = 0.25
-- Pushing for STUCK_SECONDS at under 1 m/s, it reverses (steering the other way) for
-- BACK_SECONDS; after STUCK_TRIES of those it gives up until it is moving again.
M.STUCK_SECONDS, M.BACK_SECONDS, M.STUCK_TRIES = 2.5, 2.5, 4
-- With no new point for this long, it brakes to a stop.
M.STALE_SECONDS = 0.6
-- A point behind the car is turned towards at this speed at most, in m/s.
M.TURN_MPS = 6

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- The driver's memory between frames.
function M.newState()
  return { steer = 0, pushing = 0, backing = 0, tries = 0, age = math.huge }
end

-- One frame. s is the state, car what the car senses now:
--   x, y (centre), fx, fy (facing, unit), rx, ry (right, unit), speed (m/s, forward positive),
--   yawRate (rad/s, right turn positive), wheelSpeed (m/s), mu (ground grip), wheelBase (m)
-- s.target is { x, y, speed }. Returns steering (-1 left .. 1 right), throttle, brake and
-- parking brake (0 .. 1). In BeamNG's arcade gearbox the brake held at a standstill drives
-- backwards, so holding still uses the parking brake instead.
function M.control(s, car, dt)
  s.age = s.age + dt
  local t = s.target
  if not t or s.age > M.STALE_SECONDS then
    s.steer = s.steer + clamp(-s.steer, -M.STEER_RATE * dt, M.STEER_RATE * dt)
    if car.speed > 0.5 then return s.steer, 0, 0.5, 0 end
    return s.steer, 0, 0, 1
  end
  local mu = clamp(car.mu or 1, 0.2, 1.5)
  local dx, dy = t.x - car.x, t.y - car.y
  local side = dx * car.rx + dy * car.ry
  local ahead = dx * car.fx + dy * car.fy
  local dist2 = math.max(1, side * side + ahead * ahead)

  -- Pure pursuit: the curvature of the arc through the point, then a wheel angle for it.
  local curvature = 2 * side / dist2
  local want = math.atan(car.wheelBase * curvature) / M.STEER_LOCK
  local speedCap = math.huge
  if ahead < 0 then
    -- Behind: full lock towards it, slowly.
    want = side >= 0 and 1 or -1
    speedCap = M.TURN_MPS
  else
    speedCap = math.sqrt(M.LAT_G * math.min(1, mu) * G / math.max(math.abs(curvature), 1e-4))
  end
  -- Turning faster than the arc needs: take some steering off.
  local yawWanted = car.speed * curvature
  want = want - M.YAW_DAMP * ((car.yawRate or 0) - yawWanted)

  -- Stuck: pushing without moving; reverse for a bit, steering the other way.
  local reverse = false
  if s.backing > 0 then
    s.backing = s.backing - dt
    reverse = true
    want = -want
  elseif s.tries < M.STUCK_TRIES and s.lastThrottle and s.lastThrottle > 0.3 and math.abs(car.speed) < 1 then
    s.pushing = s.pushing + dt
    if s.pushing >= M.STUCK_SECONDS then
      s.pushing, s.backing, s.tries = 0, M.BACK_SECONDS, s.tries + 1
      s.stuckEvent = s.tries
    end
  else
    s.pushing = 0
    if math.abs(car.speed) > 3 then s.tries = 0 end
  end

  want = clamp(want, -1, 1)
  s.steer = s.steer + clamp(want - s.steer, -M.STEER_RATE * dt, M.STEER_RATE * dt)

  if reverse then
    -- In BeamNG's arcade gearbox, brake when stopped drives backwards.
    s.lastThrottle = 0
    return s.steer, 0, 0.4 + 0.15 * s.tries, 0
  end
  if s.tries >= M.STUCK_TRIES and math.abs(car.speed) < 1 then
    s.lastThrottle = 0
    return s.steer, 0, 0, 1
  end

  local speed = math.max(0, math.min(t.speed or 0, speedCap))
  local accel = clamp((speed - car.speed) / M.SPEED_TAU, -M.BRAKE_G * mu * G, M.ACCEL_G * mu * G)
  local throttle, brake = 0, 0
  if speed < 0.5 and car.speed < 0.5 then
    s.lastThrottle = 0
    return s.steer, 0, 0, 1
  elseif accel >= 0 then
    throttle = clamp(accel / (M.ACCEL_G * G), 0, 1)
    -- A little throttle to hold speed against drag and the slope.
    if speed > 1 then throttle = math.max(throttle, 0.15) end
    if car.wheelSpeed and car.wheelSpeed > car.speed * (1 + M.SPIN_SHARE) + 2 then throttle = throttle * 0.5 end
  else
    brake = clamp(-accel / (M.BRAKE_G * G), 0, 1)
  end
  s.lastThrottle = throttle
  return s.steer, throttle, brake, 0
end

-- ------------------------------------------------------------ road mode ---
-- Chasing you on the roads, like BeamNG's chase mode: a route along the road map to you, driven
-- with a speed plan from Rowan's country limits, then a ram once it is close. The road maths is
-- here; the route itself comes from the game's road map (in the car, below).

-- Rowan's country cornering limit by speed (smartAI moonhawk_country): {km/h, g}.
M.LAT_TABLE = { { 0, 0.9 }, { 40, 0.95 }, { 200, 0.95 } }
-- How far along the route it aims: LOOK_SECONDS of its speed, between LOOK_MIN and LOOK_MAX m.
M.LOOK_SECONDS, M.LOOK_MIN, M.LOOK_MAX = 0.8, 6, 30
-- Within RAM_METRES of you, with you ahead of it, it leaves the route and drives at you, at your
-- speed plus RAM_MPS (BeamNG's chase hits at 10 m/s over the target's speed).
M.RAM_METRES, M.RAM_MPS = 30, 8
-- How often the route is worked out again, in seconds.
M.ROUTE_SECONDS = 0.5
-- The speed to plan for at the end of the route, where you are: your speed plus a little.
M.END_EXTRA_MPS = 5

-- The cornering limit at this speed, in g.
function M.latG(speed)
  local kmh, t = speed * 3.6, M.LAT_TABLE
  if kmh <= t[1][1] then return t[1][2] end
  for i = 2, #t do
    if kmh <= t[i][1] then
      local a, b = t[i - 1], t[i]
      return a[2] + (b[2] - a[2]) * (kmh - a[1]) / (b[1] - a[1])
    end
  end
  return t[#t][2]
end

-- The curvature (1 / radius) of the circle through three points on the ground.
function M.curvature(a, b, c)
  local abx, aby, bcx, bcy = b.x - a.x, b.y - a.y, c.x - b.x, c.y - b.y
  local cax, cay = a.x - c.x, a.y - c.y
  local d = math.sqrt((abx * abx + aby * aby) * (bcx * bcx + bcy * bcy) * (cax * cax + cay * cay))
  if d < 1e-9 then return 0 end
  return math.abs(2 * (abx * bcy - aby * bcx) / d)
end

-- The fastest it can take each point of a route: the corner there at the speed-dependent
-- cornering limit, and no faster than it can brake from to make the corners after it. endSpeed
-- is the speed at the last point. mu is the ground's grip.
function M.speedPlan(points, mu, endSpeed)
  local n, speeds = #points, {}
  mu = math.min(1, mu or 1)
  for i = 1, n do
    local k = (i > 1 and i < n) and M.curvature(points[i - 1], points[i], points[i + 1]) or 0
    local v = 80
    if k > 1e-5 then
      -- The limit depends on speed, so settle it: speed from the limit, the limit from the speed.
      local lat = M.LAT_TABLE[1][2]
      for _ = 1, 4 do
        v = math.sqrt(lat * mu * G / k)
        lat = M.latG(v)
      end
      v = math.min(80, math.sqrt(lat * mu * G / k))
    end
    speeds[i] = v
  end
  if n > 0 and endSpeed then speeds[n] = math.min(speeds[n], endSpeed) end
  for i = n - 1, 1, -1 do
    local a, b = points[i], points[i + 1]
    local d = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    speeds[i] = math.min(speeds[i], math.sqrt(speeds[i + 1] ^ 2 + 2 * M.BRAKE_G * mu * G * d))
  end
  return speeds
end

-- The point dist metres along the route from where x, y is nearest it, and the index of the
-- route point just past it.
function M.along(points, x, y, dist)
  local n = #points
  if n == 0 then return nil end
  if n == 1 then return points[1].x, points[1].y, 1 end
  local best, bestD2, bestT = 1, math.huge, 0
  for i = 1, n - 1 do
    local a, b = points[i], points[i + 1]
    local sx, sy = b.x - a.x, b.y - a.y
    local len2 = sx * sx + sy * sy
    local t = len2 > 1e-9 and clamp(((x - a.x) * sx + (y - a.y) * sy) / len2, 0, 1) or 0
    local px, py = a.x + sx * t, a.y + sy * t
    local d2 = (px - x) ^ 2 + (py - y) ^ 2
    if d2 < bestD2 then best, bestD2, bestT = i, d2, t end
  end
  local i, t, left = best, bestT, dist
  while i < n do
    local a, b = points[i], points[i + 1]
    local seg = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    local rest = seg * (1 - t)
    if rest >= left and seg > 1e-9 then
      local u = t + left / seg
      return a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, i + 1
    end
    left, i, t = left - rest, i + 1, 0
  end
  return points[n].x, points[n].y, n
end

-- Where to drive and how fast, chasing a target (x, y, vx, vy) along a route (or straight at it
-- with no route). Returns a target for M.control: { x, y, speed }.
function M.chaseAim(car, route, speeds, them)
  local dx, dy = them.x - car.x, them.y - car.y
  local metres = math.sqrt(dx * dx + dy * dy)
  local theirSpeed = math.sqrt((them.vx or 0) ^ 2 + (them.vy or 0) ^ 2)
  local ahead = dx * car.fx + dy * car.fy
  if not route or #route < 2 or (metres <= M.RAM_METRES and ahead > 0) then
    -- Straight at them, where they will be in half a second.
    return { x = them.x + (them.vx or 0) * 0.5, y = them.y + (them.vy or 0) * 0.5, speed = theirSpeed + M.RAM_MPS }
  end
  local look = clamp(math.max(car.speed, 0) * M.LOOK_SECONDS, M.LOOK_MIN, M.LOOK_MAX)
  local x, y, i = M.along(route, car.x, car.y, look)
  local _, _, here = M.along(route, car.x, car.y, 0)
  local speed = math.huge
  for j = math.max(1, here - 1), i do speed = math.min(speed, speeds[j] or speed) end
  return { x = x, y = y, speed = speed }
end

-- ------------------------------------------------------------ in the car ---

local state, active, savedGearbox
local lastDir

local chasing -- the id of the car being chased on the roads, or nil
local route, routeSpeeds, routeAt

local function takeOver()
  state = state or M.newState()
  if not active then
    active = true
    state.tries, state.pushing, state.backing = 0, 0, 0
    if ai and ai.setMode then pcall(ai.setMode, 'disabled') end
    if controller and controller.mainController and controller.mainController.setGearboxMode then
      savedGearbox = electrics and electrics.values and electrics.values.gearboxMode
      pcall(controller.mainController.setGearboxMode, 'arcade')
    end
  end
end

-- Tanker's command: drive at x, y, z at speed m/s.
function M.target(x, y, z, speed)
  takeOver()
  chasing = nil
  state.target = { x = x, y = y, z = z, speed = speed }
  state.age = 0
end

-- Tanker's command: chase car id on the roads, and ram it.
function M.chase(id)
  takeOver()
  chasing, route, routeAt = id, nil, nil
  if mapmgr and mapmgr.requestMap then pcall(mapmgr.requestMap) end
end

local function drive(steer, throttle, brake, parking)
  if not input or not input.event then return end
  input.event('steering', steer, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('throttle', throttle, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('brake', brake, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('parkingbrake', parking or 0, 'FILTER_AI', nil, nil, nil, 'ai')
end

-- Hands the car back: pedals off, wheel straight, gearbox as it was.
function M.stop()
  if not active then return end
  active, chasing, route = false, nil, nil
  if state then state.target = nil end
  drive(0, 0, 0, 0)
  if savedGearbox and controller and controller.mainController and controller.mainController.setGearboxMode then
    pcall(controller.mainController.setGearboxMode, savedGearbox)
  end
  savedGearbox = nil
end

function M.active() return active == true end

local function wheelBase()
  if state.wheelBase then return state.wheelBase end
  local length = obj.getInitialLength and obj:getInitialLength() or 4.5
  state.wheelBase = clamp(length * 0.6, 2, 6)
  return state.wheelBase
end

function M.updateGFX(dt)
  if not active or not state or not obj or dt <= 0 then return end
  local px, py
  if obj.getPositionXYZ then px, py = obj:getPositionXYZ() else local p = obj:getPosition(); px, py = p.x, p.y end
  local fx, fy
  if obj.getDirectionVectorXYZ then fx, fy = obj:getDirectionVectorXYZ() else local d = obj:getDirectionVector(); fx, fy = d.x, d.y end
  local len = math.sqrt(fx * fx + fy * fy)
  if len < 1e-6 then return end
  fx, fy = fx / len, fy / len
  local vx, vy
  if obj.getSmoothRefVelocityXYZ then vx, vy = obj:getSmoothRefVelocityXYZ() else local v = obj:getVelocity(); vx, vy = v.x, v.y end
  local yawRate = 0
  if lastDir then
    -- Positive turning right: the facing moved towards the right vector.
    local cross = lastDir[1] * fy - lastDir[2] * fx
    yawRate = -math.asin(clamp(cross, -1, 1)) / dt
  end
  lastDir = { fx, fy }
  local car = {
    x = px, y = py, fx = fx, fy = fy, rx = fy, ry = -fx,
    speed = vx * fx + vy * fy, yawRate = yawRate,
    wheelSpeed = electrics and electrics.values and electrics.values.wheelspeed,
    mu = obj.getStaticFrictionCoef and obj:getStaticFrictionCoef() * 0.95 or 1,
    wheelBase = wheelBase(),
  }
  if chasing then
    local them = mapmgr and mapmgr.getObjects and mapmgr.getObjects()[chasing]
    if them and them.pos then
      local tvx, tvy = them.vel and them.vel.x or 0, them.vel and them.vel.y or 0
      local t = { x = them.pos.x, y = them.pos.y, vx = tvx, vy = tvy }
      routeAt = (routeAt or 0) - dt
      if routeAt <= 0 then
        routeAt = M.ROUTE_SECONDS
        route = nil
        local ok, points = pcall(function()
          local data = mapmgr.mapData
          if not (data and mapmgr.findBestRoad and data.getChasePath) then return nil end
          local me = vec3(px, py, 0)
          local wp1, wp2 = mapmgr.findBestRoad(obj:getPosition(), obj:getDirectionVector())
          local pl1, pl2 = mapmgr.findBestRoad(them.pos, them.vel and them.vel:length() > 1 and them.vel or them.dirVec)
          if not (wp1 and wp2 and pl1 and pl2) then return nil end
          local path = data:getChasePath(wp1, wp2, pl1, pl2, obj:getPosition(), obj:getVelocity(), them.pos, them.vel, 1)
          if not path then return nil end
          local list = { { x = me.x, y = me.y } }
          for _, node in ipairs(path) do
            local p = data.positions[node]
            -- Road points just behind the car are skipped, so it doesn't aim back at them.
            local behind = p and #list == 1 and ((p.x - px) * fx + (p.y - py) * fy) < 0
            if p and not behind then list[#list + 1] = { x = p.x, y = p.y } end
          end
          list[#list + 1] = { x = t.x, y = t.y }
          return list
        end)
        if ok and points and #points >= 2 then
          route = points
          routeSpeeds = M.speedPlan(route, car.mu, math.sqrt(tvx * tvx + tvy * tvy) + M.END_EXTRA_MPS)
        end
      end
      state.target, state.age = M.chaseAim(car, route, routeSpeeds, t), 0
    end
  end
  local steer, throttle, brake, parking = M.control(state, car, dt)
  drive(steer, throttle, brake, parking)
  if state.stuckEvent then
    local tries = state.stuckEvent
    state.stuckEvent = nil
    obj:queueGameEngineLua(string.format('if tanker_core then tanker_core.packProblem(%d, "stuck_try_%d") end', obj:getID(), tries))
  end
end

function M.onReset()
  if state then state.tries, state.pushing, state.backing = 0, 0, 0 end
  lastDir = nil
end

return M
