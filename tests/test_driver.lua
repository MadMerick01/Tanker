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
T.eq(th, 0, 'then rests'); T.eq(pk, 1, 'holding still')
local pushed = false
for _ = 1, math.floor(D.REST_SECONDS * 60) + 2 do
  s.age = 0
  local _, t = D.control(s, car(0), 1 / 60)
  if t > 0 then pushed = true; break end
end
T.check(pushed, 'and tries again within a rest, it never gives up')
T.check(s.tries < D.STUCK_TRIES, 'starting its tries afresh')

-- A little slower wanted: it lifts off rather than braking; much slower, it brakes.
s = D.newState(); aim(s, 0, 40, 18)
st, th, br = D.control(s, car(20), 1 / 60)
T.eq(th, 0, 'lifts off'); T.eq(br, 0, 'without touching the brakes')
s = D.newState(); aim(s, 0, 40, 10)
st, th, br = D.control(s, car(20), 1 / 60)
T.check(br > 0, 'a lot slower wanted, it brakes')
-- A desert Hoon getting into place (MadMerick, 6 Nov): never the brakes, however much slower it is asked.
s = D.newState(); aim(s, 0, 40, 10); s.target.mode = 'coast'
st, th, br = D.control(s, car(20), 1 / 60)
T.eq(br, 0, 'coasting: no brake'); T.eq(th, 0, 'it lifts off instead')
s = D.newState(); aim(s, 15, 10, 40); s.target.mode = 'coast'
st, th, br = D.control(s, car(25), 1 / 60)
T.eq(br, 0, 'not even for a tight turn')
-- A swipe: no brake, and it turns in hard at the speed asked.
s = D.newState(); aim(s, 6, 3, 25); s.target.mode = 'swipe'
st, th, br = D.control(s, car(25), 1 / 60)
T.eq(br, 0, 'swiping: no brake'); T.check(th > 0, 'holding your speed'); T.check(st > 0, 'turning in')

-- Stopping the car: asked for nought, it holds the brake once stopped.
s = D.newState(); aim(s, 0, 10, 0)
st, th, br, pk = D.control(s, car(0), 1 / 60)
T.eq(br, 0, 'asked to stop and stopped, not on the brake (that reverses)'); T.eq(pk, 1, 'parking brake on')

-- Road mode: the cornering limit, the speed plan and following the route.
T.eq(D.latG(0), 0.9, 'cornering limit at a crawl'); T.eq(D.latG(100 / 3.6), 0.95, 'and at speed')
T.near(D.curvature({ x = 0, y = 0 }, { x = 10, y = 10 }, { x = 20, y = 0 }), 0.1, 1e-6, 'curvature of a 10 m circle')
T.eq(D.curvature({ x = 0, y = 0 }, { x = 0, y = 10 }, { x = 0, y = 20 }), 0, 'a straight has none')
-- A straight 200 m, then a tight 20 m radius right-hander.
local road = {}
for i = 0, 20 do road[#road + 1] = { x = 0, y = i * 10 } end
for a = 1, 9 do
  local th = a * math.pi / 18
  road[#road + 1] = { x = 20 - 20 * math.cos(th), y = 200 + 20 * math.sin(th) }
end
local speeds = D.speedPlan(road, 1)
local corner = speeds[#road - 4]
T.near(corner, math.sqrt(0.9 * 9.81 * 20), 1.5, 'the corner at about 0.9 g')
T.check(speeds[1] > corner + 10, 'faster on the straight')
T.check(speeds[19] < speeds[5], 'braking for the corner before it')
local d19 = 200 - 180
T.check(speeds[19] <= math.sqrt(speeds[21] ^ 2 + 2 * D.BRAKE_G * 9.81 * d19) + 1e-6, 'no later than it can brake at 0.65 g')
T.eq(D.speedPlan({ { x = 0, y = 0 }, { x = 0, y = 50 } }, 1, 12)[2], 12, 'the end speed is kept')
local px, py, i = D.along(road, 3, 50, 25)
T.near(px, 0, 1e-6, 'along the route from beside it'); T.near(py, 75, 1e-6, '25 m on'); T.eq(i, 9, 'and which point is next')

-- Catching up along the route, slowing for the corner ahead.
local chaser = car(25)
local aim1 = D.routeAim(chaser, road, speeds)
T.eq(aim1.x, 0, 'follows the road'); T.near(aim1.y, 25 * D.LOOK_SECONDS, 1e-6, 'looking ahead with its speed')
local late = car(25, { y = 185 })
T.check(D.routeAim(late, road, speeds).speed < 25, 'slows for the corner coming up')

-- The road attack: you drive north at 20 m/s from the origin. No ramming: it overtakes on the
-- right, cuts in front, brake-checks, and does it again.
local you = { x = 0, y = 0, vx = 0, vy = 20 }
local rs = {}
local far, phase = D.roadAttack(rs, car(25, { y = -300 }), road, speeds, you, 0.1)
T.eq(phase, 'CATCH', 'far behind, it catches up'); T.eq(far.x, 0, 'along the road')
local a2
a2, phase = D.roadAttack(rs, car(25, { y = -40 }), road, speeds, you, 0.1)
T.eq(phase, 'PASS', 'close behind, it overtakes'); T.eq(a2.x, D.PASS_SIDE, 'in the lane to your right')
T.eq(a2.speed, 20 + D.PASS_MPS, 'faster than you'); T.check(a2.y > -40, 'heading up past you')
a2, phase = D.roadAttack(rs, car(28, { x = 3.5, y = 0 }), road, speeds, you, 0.1)
T.eq(phase, 'PASS', 'still alongside, still passing')
a2, phase = D.roadAttack(rs, car(28, { x = 3.5, y = D.CUT_AHEAD + 1 }), road, speeds, you, 0.1)
T.eq(phase, 'CUT_IN', 'clear of your front, it cuts in'); T.eq(a2.x, 0, 'into your lane')
local inFront = car(20, { y = D.CUT_AHEAD })
for _ = 1, 9 do a2, phase = D.roadAttack(rs, inFront, road, speeds, you, 0.1) end
T.eq(phase, 'CUT_IN', 'settles in front first')
for _ = 1, 3 do a2, phase = D.roadAttack(rs, inFront, road, speeds, you, 0.1) end
T.eq(phase, 'BRAKE_CHECK', 'then brake-checks'); T.near(a2.speed, 20 * D.BRAKE_SHARE, 1e-6, 'hard')
for _ = 1, 16 do a2, phase = D.roadAttack(rs, inFront, road, speeds, you, 0.1) end
T.eq(phase, 'RECOVER', 'then drives on'); T.check(a2.speed > 15, 'back up to speed')
for _ = 1, 41 do a2, phase = D.roadAttack(rs, inFront, road, speeds, you, 0.1) end
T.eq(phase, 'CUT_IN', 'and lines up to do it again')
a2, phase = D.roadAttack(rs, car(20, { y = -5 }), road, speeds, you, 0.1)
T.eq(phase, 'PASS', 'if you get past, it overtakes again')
-- You stop: it parks in front of you.
a2, phase = D.roadAttack(rs, car(5, { y = 12 }), road, speeds, { x = 0, y = 0, vx = 0, vy = 0, fx = 0, fy = 1 }, 0.1)
T.eq(phase, 'BLOCK', 'you stop, it blocks you'); T.eq(a2.speed, 0, 'parked in front')
-- No route: it still catches up, from behind you.
local nr = {}
a2, phase = D.roadAttack(nr, car(20, { y = -300 }), nil, nil, you, 0.1)
T.eq(phase, 'CATCH', 'catching up with no route'); T.eq(a2.y, -D.FOLLOW_BEHIND, 'aiming behind you'); T.eq(a2.speed, 20 + D.CATCH_MPS, 'fast')

-- In a pretend car: Tanker's commands drive it with the game's inputs.
local sent, gearbox, aiMode, ge = {}, nil, nil, {}
local function v3(x, y, z) return { x = x, y = y, z = z or 0, length = function(v) return math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2) end } end
local carPos, carVel = v3(0, 0, 0), v3(0, 10, 0)
_G.vec3 = v3
_G.input = { event = function(name, value) sent[name] = value end }
_G.electrics = { values = { gearboxMode = 'realistic', wheelspeed = 10 } }
_G.controller = { mainController = { setGearboxMode = function(m) gearbox = m end } }
_G.ai = { setMode = function(m) aiMode = m end }
_G.obj = {
  getPositionXYZ = function() return carPos.x, carPos.y, 0 end, getPosition = function() return carPos end,
  getDirectionVectorXYZ = function() return 0, 1, 0 end, getDirectionVector = function() return v3(0, 1, 0) end,
  getSmoothRefVelocityXYZ = function() return carVel.x, carVel.y, 0 end, getVelocity = function() return carVel end,
  getStaticFrictionCoef = function() return 1 end, getInitialLength = function() return 4.6 end, getID = function() return 50 end,
  queueGameEngineLua = function(_, cmd) ge[#ge + 1] = cmd end,
}
local roadNodes = { a = v3(0, -10), b = v3(0, 40), c = v3(0, 90) }
_G.mapmgr = {
  requestMap = function() end,
  findBestRoad = function(pos) if pos.y > 60 then return 'b', 'c', 1 end return 'a', 'b', 1 end,
  getObjects = function() return { [7] = { pos = v3(0, 120), vel = v3(0, 15), dirVec = v3(0, 1) } } end,
  mapData = { positions = roadNodes, getChasePath = function() return { 'a', 'b', 'c' } end },
}
D.target(10, 50, 0, 20)
T.eq(aiMode, 'disabled', 'BeamNG\'s AI is switched off while it drives'); T.eq(gearbox, 'arcade', 'arcade gearbox')
D.updateGFX(1 / 60)
T.check(sent.throttle and sent.throttle > 0, 'throttle sent'); T.check(sent.steering > 0, 'steering towards the point')
D.chase(7)
for _ = 1, 30 do D.updateGFX(1 / 60) end
T.check(math.abs(sent.steering) < 0.05, 'chasing up a straight road, wheel straight')
T.check(sent.throttle > 0, 'and on the throttle')
T.check(ge[#ge]:find('hoonPhase(50, "CATCH")', 1, true) ~= nil, 'and tells Tanker what it is doing')
D.stop()
T.eq(gearbox, 'realistic', 'the gearbox is put back'); T.eq(sent.throttle, 0, 'pedals off'); T.eq(D.active(), false, 'let go')
D.updateGFX(1 / 60)
T.eq(sent.throttle, 0, 'and it no longer drives')

T.done('driver')
