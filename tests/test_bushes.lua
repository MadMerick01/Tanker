local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local dir = (arg[0]:match('^(.*)[/\\]') or '.')
require('fixtures')
local P = require('tanker/pack')
local B = require('tanker/behind')
local TM = require('tanker/tankerMob')

-- Hoons and the TankerMob in the bushes (MadMerick, 6 Nov).

-- 1. The Hoon driver steers round solid bushes.
local D = dofile(dir .. '/../mod/tanker/lua/vehicle/extensions/tankerDriver.lua')
T.eq(select(1, D.avoid(nil, 0)), 0, 'nothing felt, no nudge')
T.eq(select(1, D.avoid({ look = 20 }, 0)), 0, 'all clear, no nudge')
local nudge, slow = D.avoid({ look = 20, left = 5 }, 0)
T.check(nudge > 0, 'a bush ahead on the left: steer right'); T.eq(slow, false, 'no need to slow')
nudge = D.avoid({ look = 20, right = 5 }, 0)
T.check(nudge < 0, 'on the right: steer left')
nudge, slow = D.avoid({ look = 20, centre = 4 }, -3)
T.check(nudge < 0, 'dead ahead: round the side its point is on'); T.eq(slow, true, 'and close: ease off')
T.check(math.abs(D.avoid({ look = 20, left = 3 }, 0)) > math.abs(D.avoid({ look = 20, left = 15 }, 0)), 'nearer, harder')

local function car(speed)
  return { x = 0, y = 0, fx = 0, fy = 1, rx = 1, ry = 0, speed = speed, yawRate = 0, wheelSpeed = speed, mu = 1, wheelBase = 2.8 }
end
local function frames(s, c, seconds)
  local st, th, br
  for _ = 1, math.floor(seconds * 60) do s.age = 0; st, th, br = D.control(s, c, 1 / 60) end
  return st, th, br
end
local s = D.newState()
s.target = { x = 0, y = 40, speed = 20, mode = 'coast' }
local straight = frames(s, car(15), 0.5)
s = D.newState()
s.target = { x = 0, y = 40, speed = 20, mode = 'coast' }
s.feel = { look = 18, centre = 6, left = 7 }
local round, th, br = frames(s, car(15), 0.5)
T.check(math.abs(straight) < 0.01 and round > 0.3, 'a bush in the way: it steers round it')
T.eq(br, 0, 'without braking in the desert'); T.eq(th, 0, 'lifting off to get round')
s = D.newState()
s.target = { x = 0, y = 40, speed = 20, mode = 'swipe' }
s.feel = { look = 18, centre = 6, left = 7 }
T.check(math.abs(frames(s, car(15), 0.5)) < 0.01, 'a swipe holds its line')

-- In a pretend car: the feelers find a bush, but not a hillside.
local sent, ge = {}, {}
local function v3(x, y, z) return { x = x, y = y, z = z or 0 } end
_G.vec3 = v3
_G.input = { event = function(name, value) sent[name] = value end }
_G.electrics = { values = { gearboxMode = 'arcade', wheelspeed = 15 } }
_G.controller = { mainController = { setGearboxMode = function() end } }
_G.ai = { setMode = function() end }
-- A bush 1.5 m tall, 2 m across, 12 m ahead and a little left.
local bush = { x = -0.5, y = 12, r = 1, top = 1.5 }
local hill = false
local function rayStatic(_, o, d, len)
  if d.z < -0.5 then -- looking down
    local dx, dy = o.x - bush.x, o.y - bush.y
    if dx * dx + dy * dy <= bush.r * bush.r then return o.z - bush.top end
    return o.z - (hill and (o.z - 3 + 0.1) or 0)
  end
  if hill then return math.min(len, 10) end
  -- along the ray, the first point inside the bush
  for t = 0, len, 0.05 do
    local x, y = o.x + d.x * t, o.y + d.y * t
    if (x - bush.x) ^ 2 + (y - bush.y) ^ 2 <= bush.r * bush.r and o.z < bush.top then return t end
  end
  return len
end
_G.obj = {
  getPositionXYZ = function() return 0, 0, 0 end, getDirectionVectorXYZ = function() return 0, 1, 0 end,
  getSmoothRefVelocityXYZ = function() return 0, 15, 0 end, getStaticFrictionCoef = function() return 1 end,
  getInitialLength = function() return 4.6 end, getID = function() return 50 end,
  queueGameEngineLua = function(_, cmd) ge[#ge + 1] = cmd end,
  castRayStatic = rayStatic,
}
D.target(0, 40, 0, 20, 'coast')
for _ = 1, 30 do D.updateGFX(1 / 60) end
T.check(sent.steering > 0.1, 'it feels the bush on its left and steers right')
hill = true
D.stop(); D.target(0, 40, 0, 20, 'coast')
for _ = 1, 30 do D.updateGFX(1 / 60) end
T.check(math.abs(sent.steering) < 0.01, 'a hillside ahead is not a bush: straight on')
-- No ray to cast: it drives as before, and says so once.
_G.obj.castRayStatic = function() error('no rays') end
local D2 = dofile(dir .. '/../mod/tanker/lua/vehicle/extensions/tankerDriver.lua')
D2.target(0, 40, 0, 20, 'coast')
for _ = 1, 30 do D2.updateGFX(1 / 60) end
local told = 0
for _, cmd in ipairs(ge) do if cmd:find('no_feelers', 1, true) then told = told + 1 end end
T.eq(told, 1, 'no feelers: told once'); T.check(math.abs(sent.steering) < 0.01, 'and it still drives')
D2.stop()

-- A pretend desert: ground heights and round bushes, and a ray that marches through them.
local world = { ground = function() return 0 end, bushes = {} }
local function groundAt(x, y) return world.ground(x, y) end
local function solidAt(x, y, z)
  if z <= groundAt(x, y) then return true end
  for _, b in ipairs(world.bushes) do
    if (x - b.x) ^ 2 + (y - b.y) ^ 2 <= b.r * b.r and z <= groundAt(b.x, b.y) + b.top then return true end
  end
  return false
end
_G.obj = { castRayStatic = function(_, o, d, len)
  for t = 0, len, 0.02 do
    if solidAt(o.x + d.x * t, o.y + d.y * t, o.z + d.z * t) then return t end
  end
  return len
end }
local function sense() return D.feel(0, 0, 0.5, 0, 1, 12.5) end -- 15 m look, feelers at 0.8 m
local function bush(x, y, r) return { x = x, y = y, r = r or 0.6, top = 1.5 } end

-- A gap narrower than the car: the middle feeler sees through it, the edges don't.
world.bushes = { bush(-1.4, 5, 0.5), bush(1.4, 5, 0.5) }
local f = sense()
T.eq(f.centre, nil, 'the middle feeler threads the gap')
T.check(f.edgeLeft and f.edgeRight, 'but both edges touch a bush: too narrow for the car')
nudge, slow = D.avoid(f, 0)
T.check(nudge ~= 0, 'so it steers off'); T.eq(slow, true, 'and eases off')
-- A clump: a bush ahead and another beside it on the right. It goes round the left.
world.bushes = { bush(0, 12), bush(1.5, 12), bush(4.4, 12) }
f = sense()
T.check(f.centre and f.edgeRight and f.right, 'feels the clump ahead and to the right')
nudge = D.avoid(f, 0.5)
T.check(nudge < 0, 'and goes round its open side, even with its point a little right')
-- Up a hill: the feelers follow the ground and see a bush up the slope.
world.ground = function(_, y) return y > 5 and 0.3 * (y - 5) or 0 end
world.bushes = {}
f = sense()
T.check(not f.centre and not f.left and not f.right and not f.edgeLeft and not f.edgeRight, 'a bare hillside is not a bush')
world.bushes = { bush(0, 12) }
f = sense()
T.check(f.centre and f.centre > 9, 'a bush up the hill is felt, about where it is (' .. tostring(f.centre) .. ' m)')
-- Over a crest: the feelers dip over it and see the bush below.
world.ground = function(_, y) return y > 5 and -0.3 * (y - 5) or 0 end
world.bushes = {}
f = sense()
T.check(not f.centre and not f.edgeLeft, 'nothing over a bare crest')
world.bushes = { bush(0, 12) }
f = sense()
T.check(f.centre and f.centre > 9, 'a bush below the crest is felt (' .. tostring(f.centre) .. ' m)')
-- A sharp rise straight after flat ground (the start of a steep hill).
world.ground = function(_, y) return y > 6 and 0.7 * (y - 6) or 0 end
world.bushes = {}
f = sense()
T.check(not f.centre, 'the foot of a steep hill is not a bush')
world.ground = function() return 0 end
world.bushes = {}

-- It keeps to the side it chose for a moment, so it doesn't weave between clumps.
local look = { look = 20, left = 10, right = 11 }
local _, _, d1 = D.avoid(look, 0)
T.eq(d1, 1, 'left a little more blocked: right')
local _, _, d2 = D.avoid({ look = 20, left = 11, right = 10 }, 0, 1)
T.eq(d2, 1, 'a moment later the right is a little worse: it keeps right')
local _, _, d3 = D.avoid({ look = 20, left = 15, right = 3 }, 0, 1)
T.eq(d3, -1, 'the right is much worse: it changes its mind')
s = D.newState()
s.target = { x = 0, y = 40, speed = 20, mode = 'coast' }
s.feel = { look = 18, left = 8, right = 9 }
frames(s, car(15), 0.2)
T.eq(s.keep, 1, 'the driver remembers its side')
s.feel = { look = 18, left = 9, right = 8 }
local held = frames(s, car(15), 0.3)
T.check(held > 0, 'and still steers that way when the other side looks a touch better')
s.feel = nil
frames(s, car(15), D.COMMIT_SECONDS + 0.2)
s.feel = { look = 18, left = 9, right = 8 }
frames(s, car(15), 0.05)
T.eq(s.keep, -1, 'once it has been clear a while, it chooses again')
_G.obj = nil

-- 2. A Hoon caught on a bush out of sight is lifted past it.
local function fakeCar(camera)
  local c = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }, cars = {}, next = 100, hops = {} }
  function c:player() return self.me end
  function c:ground() return 0 end
  function c:take() self.next = self.next + 1; return self.next, 'own' end
  function c:place(id, x, y, z) self.cars[id] = { x = x, y = y, z = z, speed = 20 }; return true end
  function c:hop(id, x, y, z, dx, dy) self.hops[#self.hops + 1] = { id = id, x = x, y = y, dx = dx, dy = dy }; self.cars[id].x, self.cars[id].y = x, y; return true end
  function c:goTo() return true end
  function c:state(id) return self.cars[id] end
  function c:calm() end
  function c:release(id) self.cars[id] = nil end
  function c:removeAll() end
  function c:road() return nil end
  function c:chase() end
  c.camera = camera
  return c
end
local function random(lo, hi) if lo == 0 and hi == 1 then return 0.9 end return lo end
local c = fakeCar()
local p = P.new(c, random)
p:add(0)
local h = p.hoons[1]
h.state, h.movesLeft = 'CIRCLING', 5
local st = c.cars[h.id]
st.x, st.y, st.speed = 20, -80, 0
h.aimX, h.aimY = 20, -40
p.steer = function() end
local t = 0.5
while #c.hops == 0 and t < P.UNSTICK_SECONDS + 1 do h.aimX, h.aimY = 20, -40; p:step(t); t = t + 0.5 end
T.eq(#c.hops, 1, 'stuck behind you for a few seconds: lifted on')
T.near(c.hops[1].y, -80 + P.UNSTICK_HOP, 1e-9, 'a few metres on, towards where it was heading')
T.near(c.hops[1].dy, 1, 1e-9, 'facing that way')
T.check(t - 0.5 >= P.UNSTICK_SECONDS, 'only after a few seconds')
-- Not while you can see it.
c = fakeCar(function() return { x = 0, y = 0, dx = 0, dy = -1 } end)
p = P.new(c, random)
p:add(0)
h = p.hoons[1]
h.state = 'CIRCLING'
st = c.cars[h.id]
st.x, st.y, st.speed = 20, -80, 0
for tt = 0.5, 10, 0.5 do h.aimX, h.aimY = 20, -40; p:step(tt) end
T.eq(#c.hops, 0, 'you are looking at it: it stays caught')
-- Not when it is close to you.
c = fakeCar()
p = P.new(c, random)
p:add(0)
h = p.hoons[1]
h.state = 'CIRCLING'
st = c.cars[h.id]
st.x, st.y, st.speed = 10, -20, 0
for tt = 0.5, 10, 0.5 do h.aimX, h.aimY = 10, 0; p:step(tt) end
T.eq(#c.hops, 0, 'close to you: it stays caught')
-- At most a few tries in a row.
c = fakeCar()
p = P.new(c, random)
p:add(0)
h = p.hoons[1]
h.state, h.hasHit = 'CIRCLING', true
st = c.cars[h.id]
st.x, st.y, st.speed = 20, -200, 0
for tt = 0.5, 11.5, 0.5 do h.aimX, h.aimY = 20, -400; st.speed = 0; p:step(tt) end
T.check(#c.hops >= 1 and #c.hops <= P.UNSTICK_TRIES, 'tried at most ' .. P.UNSTICK_TRIES .. ' times')
p:step(12.5); p:step(13)
T.eq(h.state, 'DOWN', 'a Hoon that hit you and still won\'t move is down, as before')

-- 3. The TankerMob caught on a bush out of sight.
local made = { getID = function() return 55 end, queueLuaCommand = function(self, cmd) self.last = cmd end, setActive = function() end }
local tc = fakeCar()
tc.cars[55] = { x = 0, y = -120, z = 0, speed = 0 }
local mob = TM.new(tc, {
  vehicles = function() return { spawnNewVehicle = function() return made end } end,
  byId = function(id) return id == 55 and made or nil end,
  vec3 = function(x, y, z) return { x = x, y = y, z = z } end, quatFromDir = function(d) return d end,
  spawn = function() return nil end,
})
T.eq(mob:step(0), false, 'no tanker out, nothing to do')
mob:spawn()
tc.cars[55] = { x = 0, y = -120, z = 0, speed = 0 }
local hopped
for tt = 0, TM.UNSTICK_SECONDS + 1, 0.5 do hopped = mob:step(tt) or hopped end
T.eq(hopped, true, 'stuck behind you: lifted on')
T.near(tc.hops[1].y, -120 - TM.UNSTICK_HOP, 1e-9, 'on, away from you')
T.check(made.last:find("'flee'", 1, true) ~= nil, 'and set running again')
for tt = 7, 40, 0.5 do mob:step(tt) end
T.eq(#tc.hops, TM.UNSTICK_TRIES, 'a few tries at most')
tc.cars[55].speed = 10; mob:step(41)
tc.cars[55].speed = 0
for tt = 41.5, 48, 0.5 do mob:step(tt) end
T.eq(#tc.hops, TM.UNSTICK_TRIES + 1, 'once it got going, it can be lifted again')
tc.camera = function() return { x = 0, y = 0, dx = 0, dy = -1 } end
local before = #tc.hops
tc.cars[55].speed = 10; mob:step(49); tc.cars[55].speed = 0
for tt = 49.5, 60, 0.5 do mob:step(tt) end
T.eq(#tc.hops, before, 'not while you are looking at it')

T.done('bushes')
