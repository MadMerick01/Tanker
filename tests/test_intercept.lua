local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
require('fixtures')
local P = require('tanker/pack')

-- A pretend game, as in test_pack: goTo puts the Hoon straight at its slot unless frozen.
local function fakeCar()
  local car = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }, cars = {}, next = 100, paths = {}, released = {} }
  function car:player() return self.me end
  function car:ground() return 0 end
  function car:take() self.next = self.next + 1; return self.next, 'own' end
  function car:place(id, px, py, pz) self.cars[id] = { x = px, y = py, z = pz, speed = 20 }; return true end
  function car:goTo(id, aim)
    self.paths[id] = aim
    if not self.frozen then self.cars[id].x, self.cars[id].y = aim.slotX, aim.slotY end
    return true
  end
  function car:state(id) return self.cars[id] end
  function car:calm() end
  function car:release(id) self.released[#self.released + 1] = id; self.cars[id] = nil end
  function car:removeAll() end
  function car:road() return nil end
  function car:chase() end
  return car
end
local coin = 0.9
local function random(lo, hi) if lo == 0 and hi == 1 then return coin end return lo end

-- 1. Where you will be: straight on, nothing changes; turning, it follows your arc.
local me = { x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }
T.eq(P.future(me, 0, 2), me, 'going straight, you are where you are')
local soon = P.future(me, 0.5, 2)
T.near(math.atan2(soon.dy, soon.dx), math.pi / 2 + 1, 1e-9, 'turning left 0.5 rad a second, 1 rad round in 2 s')
local radius = 20 / 0.5
T.near(soon.x, -radius * (1 - math.cos(1)), 1e-6, 'round the arc to your left')
T.near(soon.y, radius * math.sin(1), 1e-6, 'and ahead')

-- A Hoon aims round your turn: inside it, not at where its spot is now.
local function aimWhileTurning(turnRate)
  local car = fakeCar()
  local p = P.new(car, random)
  p:add(0)
  local h = p.hoons[1]
  h.state, h.slot = 'CLOSING', 'RFN'
  car.frozen = true
  car.cars[h.id].x, car.cars[h.id].y = 30, -40
  local heading = math.pi / 2
  for i = 0, 6 do
    local t = i * 0.25
    heading = math.pi / 2 + turnRate * t
    car.me.dx, car.me.dy = math.cos(heading), math.sin(heading)
    h.replanAt = nil
    p:steer(t)
  end
  return car.paths[h.id], p
end
local straight = aimWhileTurning(0)
local left, pl = aimWhileTurning(0.4)
T.near(pl.yaw, 0.4, 0.05, 'it reads how fast you turn')
local slotTurned = { x = left.slotX, y = left.slotY }
T.check(left.x < slotTurned.x - 5, 'turning left, it aims well left of where its spot is now: inside your turn')
T.check(math.abs(straight.x - straight.slotX) < 0.01, 'going straight, it aims at its spot as before')

-- 2. The PIT: from a rear near slot, it lines up off your back corner and drives its nose through
-- your back wheel, faster than you, with no brake.
coin = 0.1
local car = fakeCar()
local p = P.new(car, random)
p:add(0)
local h = p.hoons[1]
h.state, h.slot, h.movesLeft = 'CLOSING', 'RRN', 0
local lines, t = {}, 0.5
while h.state ~= 'WINDUP' and t < 30 do
  local l = p:step(t); if l then lines[#lines + 1] = l end
  t = t + 0.5
end
T.eq(h.state, 'WINDUP', 'lines up'); T.eq(h.pit, true, 'for your back wheel')
T.eq(lines[#lines], P.LINES.pit('RRN'), 'you are told: your right back wheel')
local _, back = P.offset('RRN')
T.near(car.paths[h.id].slotX, P.HALF_WIDTH + P.PIT_SIDE, 1e-9, 'just off your back corner')
T.near(car.paths[h.id].slotY, back, 1e-9, 'level with your back')
T.eq(p:view()[1].doing, P.DOING.PIT_WINDUP, 'the panel says so')
car.frozen = true
while h.state ~= 'SWIPE' and t < 60 do p:step(t); t = t + 0.5 end
local aim = car.paths[h.id]
T.near(aim.slotX, -P.PIT_INTO, 1e-9, 'its nose aimed past your middle')
T.near(aim.slotY, back + P.PIT_WHEEL, 1e-9, 'through your back wheel')
T.near(aim.speed, car.me.speed + P.PIT_PUSH, 1e-9, 'pushing on, faster than you'); T.eq(aim.mode, 'swipe', 'no brake')
T.eq(p:view()[1].doing, P.DOING.PIT, 'going for your back wheel')
car.cars[h.id].x, car.cars[h.id].y = 2, -3
lines = {}
for _ = 1, 6 do local l = p:step(t); if l then lines[#lines + 1] = l end; t = t + 0.5 end
T.eq(lines[#lines], P.LINES.pitted, 'it shoves your back end and peels off'); T.eq(h.pit, nil, 'the PIT is over')
-- From a front slot it still swipes.
local carF = fakeCar()
local pF = P.new(carF, random)
pF:add(0)
local hF = pF.hoons[1]
hF.state, hF.slot, hF.movesLeft = 'CLOSING', 'RFN', 0
for tt = 0.5, 30, 0.5 do pF:step(tt); if hF.state == 'WINDUP' then break end end
T.eq(hF.pit, false, 'from your front, a swipe')

-- 3. Your revolver drawn: Hoons getting into place weave, rear ones stay at your back, and a
-- Hoon you hit backs off.
coin = 0.9
car = fakeCar()
p = P.new(car, random)
p:add(0)
h = p.hoons[1]
h.state, h.slot, h.movesLeft = 'CIRCLING', 'RRF', 2
p.gunDrawn = true
local xs = {}
for i = 0, 8 do
  h.replanAt = nil
  p:steer(i * 0.3)
  xs[#xs + 1] = car.paths[h.id].slotX
end
local lo, hi = math.huge, -math.huge
for _, x in ipairs(xs) do lo, hi = math.min(lo, x), math.max(hi, x) end
T.check(hi - lo > P.WEAVE_METRES, 'weaving side to side while your gun is out')
for tt = 3, 30, 0.5 do p:step(tt); if h.state ~= 'CIRCLING' then break end end
T.eq(h.slot:sub(2, 2), 'R', 'it stayed at your back corner'); T.check(h.state ~= 'CIRCLING' or h.movesLeft == 0, 'used up its moves there')
-- Hit, but not stopped: it backs off.
h.state, h.slot, h.holdUntil = 'CLOSING', 'RRN', nil
local said, ours = p:shot(h.id)
T.eq(ours, true, 'one of the pack'); T.eq(said, P.LINES.shy, 'you are told it backs off')
T.eq(h.state, 'PEEL', 'it peels off'); T.eq(P.SLOTS[h.slot].far, true, 'to a far slot')
T.eq(p:view()[1].doing, P.DOING.SHY, 'the panel says why')
T.eq(select(1, p:shot(h.id)), nil, 'told once')
h.replanAt = nil
p:steer(p.clock + 0.1)
local nominal = P.offset(h.slot)
T.check(math.abs(car.paths[h.id].slotX) > math.abs(nominal) * 1.2, 'keeping further out')
-- While shy it doesn't attack.
local shyTill = h.shyUntil
for tt = p.clock + 0.5, shyTill - 0.5, 0.5 do
  p:step(tt)
  T.check(h.state ~= 'WINDUP' and h.state ~= 'SWIPE' and h.state ~= 'BOXING', 'no attack while backing off')
end
-- Four hits still stop it.
p:shot(h.id); p:shot(h.id)
T.eq(h.state, 'DOWN', 'four hits stop it')

T.done('intercept')
