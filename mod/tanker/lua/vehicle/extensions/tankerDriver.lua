-- tankerDriver: Tanker's own desert driver, run inside a Hoon's car. Tanker sends it a point to
-- drive at and a speed, a few times a second (target below); every frame it works out steering,
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

-- ------------------------------------------------------------ in the car ---

local state, active, savedGearbox
local lastDir

-- Tanker's command: drive at x, y, z at speed m/s.
function M.target(x, y, z, speed)
  state = state or M.newState()
  state.target = { x = x, y = y, z = z, speed = speed }
  state.age = 0
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
  active = false
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
