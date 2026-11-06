local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local dir = (arg[0]:match('^(.*)[/\\]') or '.')
local D = dofile(dir .. '/../mod/tanker/lua/vehicle/extensions/tankerDriver.lua')

-- A car at the origin facing north (+y); right is +x.
local function car(speed, extra)
  local c = { x = 0, y = 0, fx = 0, fy = 1, rx = 1, ry = 0, speed = speed, yawRate = 0, wheelSpeed = speed, mu = 1, wheelBase = 2.8 }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local function frames(s, c, seconds)
  local st, th, br, pk
  for _ = 1, math.floor(seconds * 60) do s.age = 0; st, th, br, pk = D.control(s, c, 1 / 60) end
  return st, th, br, pk
end
local function aim(s, x, y, speed) s.target, s.age = { x = x, y = y, speed = speed }, 0 end

-- Straight ahead, wanting speed: wheel straight, throttle on.
local s = D.newState()
aim(s, 0, 30, 20)
local st, th, br = D.control(s, car(0), 1 / 60)
T.eq(st, 0, 'straight ahead, wheel straight'); T.check(th > 0.9, 'full throttle from a stop'); T.eq(br, 0, 'no brake')

-- A point ahead and to the right: steer right, smoothly.
s = D.newState(); aim(s, 10, 20, 15)
st = D.control(s, car(15), 1 / 60)
T.check(st > 0 and st <= D.STEER_RATE / 60 + 1e-9, 'turns right, a little at a time')
st = frames(s, car(15), 1)
T.check(st > 0.1 and st < 1, 'settles on a part turn')
s = D.newState(); aim(s, -10, 20, 15)
T.check(frames(s, car(15), 1) < -0.1, 'and left for a point on the left')

-- Too fast: brake, within the braking limit.
s = D.newState(); aim(s, 0, 40, 10)
st, th, br = D.control(s, car(25), 1 / 60)
T.eq(th, 0, 'off the throttle'); T.check(br > 0.5 and br <= 1, 'brakes hard but not past full')

-- A tight arc caps the speed it asks for: it won't take a hairpin flat out.
s = D.newState(); aim(s, 15, 10, 40)
st, th, br = D.control(s, car(25), 1 / 60)
T.check(br > 0, 'brakes for a tight turn even when asked to go fast')

-- Behind: full lock towards it, slowly.
s = D.newState(); aim(s, 5, -20, 30)
st, th, br = frames(s, car(15), 1)
T.eq(st, 1, 'full lock towards a point behind'); T.check(br > 0, 'slowing to turn round')

-- Yaw damping: turning faster than the arc needs takes some steering off.
local s1, s2 = D.newState(), D.newState()
aim(s1, 5, 30, 15); aim(s2, 5, 30, 15)
local calm = frames(s1, car(15), 1)
local spinning = frames(s2, car(15, { yawRate = 1.5 }), 1)
T.check(spinning < calm, 'less steering when already turning hard')

-- Wheelspin: ease off the throttle.
s = D.newState(); aim(s, 0, 30, 30)
local _, grip = D.control(s, car(5), 1 / 60)
s = D.newState(); aim(s, 0, 30, 30)
local _, spin = D.control(s, car(5, { wheelSpeed = 20 }), 1 / 60)
T.check(spin < grip, 'less throttle when the wheels spin')

-- No new point for a while: off the throttle and brake to a stop.
s = D.newState(); aim(s, 0, 30, 20)
s.age = D.STALE_SECONDS + 1
st, th, br = D.control(s, car(10), 1 / 60)
T.eq(th, 0, 'no throttle without fresh orders'); T.check(br > 0, 'brakes')
local pk
st, th, br, pk = D.control(s, car(0), 1 / 60)
T.eq(br, 0, 'stopped, off the brake so it does not reverse'); T.eq(pk, 1, 'holding still on the parking brake')

-- Stuck: pushing without moving, it backs off steering the other way, then tries again.
s = D.newState(); aim(s, 5, 30, 20)
frames(s, car(0), D.STUCK_SECONDS + 0.1)
T.eq(s.stuckEvent, 1, 'notices it is stuck')
st, th, br = D.control(s, car(0), 1 / 60)
T.eq(th, 0, 'reversing: no throttle'); T.check(br > 0, 'brake in the arcade gearbox drives backwards')
T.check(st < 0, 'steering the other way')
frames(s, car(0), D.BACK_SECONDS + 0.1)
st, th = D.control(s, car(0), 1 / 60)
T.check(th > 0, 'then drives forward again')
for _ = 2, D.STUCK_TRIES do frames(s, car(0), D.STUCK_SECONDS + D.BACK_SECONDS + 0.5) end
T.eq(s.tries, D.STUCK_TRIES, 'tries a few times')
st, th, br, pk = frames(s, car(0), 1)
T.eq(th, 0, 'then gives up'); T.eq(pk, 1, 'and holds still')
st, th = frames(s, car(5), 0.2)
T.check(th > 0, 'until it is moving again')

-- Stopping the car: asked for nought, it holds the brake once stopped.
s = D.newState(); aim(s, 0, 10, 0)
st, th, br, pk = D.control(s, car(0), 1 / 60)
T.eq(br, 0, 'asked to stop and stopped, not on the brake (that reverses)'); T.eq(pk, 1, 'parking brake on')

T.done('driver')
