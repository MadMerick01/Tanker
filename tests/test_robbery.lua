local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
require('fixtures')
local RB = require('tanker/robbery')
local P = require('tanker/pack')

-- Pretend tanks: yours, the bed tank and the Hoon's. change() answers at once by default.
local function game(truck, bedLitres, hoonLitres, hoonCapacity)
  local g = { truck = truck, bed = bedLitres, hoon = hoonLitres, hoonCap = hoonCapacity or 80, calls = {}, held = {} }
  g.hoons = { state = nil, metres = 50, speed = 10, fled = 0, unrobbed = 0, offered = 0 }
  -- One Hoon to send, unless the test brings another.
  g.hoons.left = 1
  function g.hoons:startRob()
    self.offered = self.offered + 1
    if self.none or self.left < 1 then return nil end
    self.left, self.state = self.left - 1, 'ROB'
    return 55
  end
  function g.hoons:robber() if self.state == 'ROB' then return { id = 55, metres = self.metres, speed = self.speed } end end
  function g.hoons:flee(id) self.state = 'FLEE'; self.fled = self.fled + 1; self.fledId = id end
  function g.hoons:unrob() self.state = 'CIRCLING'; self.unrobbed = self.unrobbed + 1 end
  g.change = function(litres, serial, id)
    g.calls[#g.calls + 1] = { litres = litres, serial = serial, id = id }
    local before, after
    if id == nil then before = g.truck; g.truck = math.max(0, math.min(300, g.truck + litres)); after = g.truck
    else before = g.hoon; g.hoon = math.max(0, math.min(g.hoonCap, g.hoon + litres)); after = g.hoon end
    local answer = { serial, before, after, id == nil and 300 or g.hoonCap }
    if g.hold then g.held[#g.held + 1] = answer else g.answers[#g.answers + 1] = answer end
    return true
  end
  g.answers = {}
  g.bedChange = function(litres)
    local before = g.bed
    g.bed = math.max(0, math.min(200, g.bed + litres))
    return g.bed - before
  end
  g.r = RB.new(g.change, g.bedChange, g.hoons)
  -- Runs the clock, answering each change straight away, and gives the lines said.
  function g:run(from, to, speed)
    local lines = {}
    for t = from, to, 0.5 do
      local l = self.r:step(t, speed or 0, { litres = self.truck, capacity = 300 }, self.bed and { litres = self.bed, capacity = 200 } or nil)
      if l then lines[#lines + 1] = l end
      while #self.answers > 0 do
        local a = table.remove(self.answers, 1)
        self.r:answer(a[1], a[2], a[3], a[4], t)
      end
    end
    return lines
  end
  return g
end

-- Moving: nothing happens. Stopped for STUCK_SECONDS: a Hoon is sent.
local g = game(60, 0, 5)
g:run(0, 30, 10)
T.eq(g.hoons.offered, 0, 'no robbery while you drive')
local lines = g:run(31, 31 + RB.STUCK_SECONDS - 1)
T.eq(g.hoons.offered, 0, 'not straight away when you stop')
lines = g:run(31 + RB.STUCK_SECONDS, 31 + RB.STUCK_SECONDS)
T.eq(g.hoons.offered, 1, 'after a while stopped, a Hoon comes for your fuel')
T.eq(lines[1], RB.LINES.coming, 'and you are told')
T.eq(g.r.state, 'COMING', 'it is coming')
g:run(42, 45)
T.eq(#g.calls, 0, 'nothing taken while it is still driving up')
-- It pulls up and stops beside you: it takes your fuel, down to 10 L, and puts it in its own tank.
g.hoons.metres, g.hoons.speed = 4, 0.3
lines = g:run(46, 46)
T.eq(lines[1], RB.LINES.taking, 'it starts siphoning')
lines = g:run(46.5, 90)
T.near(g.truck, RB.KEEP_LITRES, 1e-6, 'you are left with 10 L')
T.near(g.hoon, 55, 1e-6, 'every litre is in the Hoon\'s tank')
T.eq(g.hoons.fled, 1, 'then it speeds off'); T.eq(g.hoons.fledId, 55, 'the robber')
T.eq(lines[#lines], RB.LINES.took(50), 'you are told what it took')
for _, c in ipairs(g.calls) do T.check(c.litres <= 0 or c.id == 55, 'fuel only moves from you to the Hoon') end
local biggest = 0
for _, c in ipairs(g.calls) do if c.id == nil then biggest = math.max(biggest, -c.litres) end end
T.check(biggest <= RB.RATE, 'a few litres a second')
T.eq(g.r:active(), false, 'the robbery is over')
local v = g.r:view(g.r.result.at, { litres = g.truck, capacity = 300 })
T.check(v and v.text == RB.LINES.took(50), 'the centre window shows the result')
T.eq(g.r:view(g.r.result.at + RB.RESULT_SECONDS + 1), nil, 'then closes')

-- The bed tank goes first, then your truck.
g = game(30, 15, 0)
g.hoons.metres, g.hoons.speed = 4, 0
g:run(0, 60)
T.near(g.bed, 0, 1e-6, 'the bed tank is emptied'); T.near(g.truck, 10, 1e-6, 'then your tank, down to 10 L')
T.near(g.hoon, 35, 1e-6, 'all of it in the Hoon\'s tank')
local firstTruck
for i, c in ipairs(g.calls) do if c.id == nil and not firstTruck then firstTruck = i end end
local bedRounds = 0
for i, c in ipairs(g.calls) do if c.id == 55 and (not firstTruck or i < firstTruck) then bedRounds = bedRounds + 1 end end
T.check(bedRounds >= 4, 'the bed tank was taken before your truck')

-- A Hoon whose own tank fills stops there and speeds off; what did not fit goes back.
g = game(200, 0, 70, 80)
g.hoons.metres, g.hoons.speed = 4, 0
g:run(0, 60)
T.near(g.hoon, 80, 1e-6, 'its tank is full'); T.near(g.truck + g.hoon, 270, 1e-6, 'no fuel made or lost')
T.eq(g.hoons.fled, 1, 'and it speeds off')

-- 10 L or less: it pulls up, checks, and speeds off with nothing.
g = game(9, 0, 5)
g.hoons.metres, g.hoons.speed = 4, 0
lines = g:run(0, RB.STUCK_SECONDS + 1)
T.eq(lines[#lines], RB.LINES.checking, 'it checks your tank')
lines = g:run(RB.STUCK_SECONDS + 1.5, RB.STUCK_SECONDS + 1.5 + RB.CHECK_SECONDS)
T.eq(lines[#lines], RB.LINES.nothing, 'nothing worth taking')
T.eq(g.hoons.fled, 1, 'it speeds off'); T.eq(g.truck, 9, 'and leaves you what you had')
T.eq(#g.calls, 0, 'touching nothing')
-- The next Hoon comes after a gap, and checks too.
g.hoons.state, g.hoons.left = nil, 1
g:run(RB.STUCK_SECONDS + 2 + RB.CHECK_SECONDS, RB.STUCK_SECONDS + 2 + 2 * RB.CHECK_SECONDS + RB.GAP_SECONDS + 2)
T.eq(g.hoons.offered, 2, 'another Hoon checks after a gap'); T.eq(g.hoons.fled, 2, 'and speeds off')

-- Driving off: before it took anything it goes back to circling; after, it runs off with what it got.
g = game(60, 0, 0)
g:run(0, RB.STUCK_SECONDS)
lines = g:run(RB.STUCK_SECONDS + 1, RB.STUCK_SECONDS + 1, 5)
T.eq(lines[1], RB.LINES.droveOff, 'you got away'); T.eq(g.hoons.unrobbed, 1, 'it goes back to the pack')
g = game(60, 0, 0)
g.hoons.metres, g.hoons.speed = 4, 0
g:run(0, RB.STUCK_SECONDS + 3)
local got = g.hoon
T.check(got > 0, 'it took some')
lines = g:run(RB.STUCK_SECONDS + 3.5, RB.STUCK_SECONDS + 3.5, 5)
T.eq(lines[1], RB.LINES.droveOffWith(got), 'you drove off, it got some'); T.eq(g.hoons.fled, 1, 'and it runs')
T.near(g.truck + g.hoon, 60, 1e-6, 'no fuel lost')

-- Shot down mid-robbery: the robbery ends quietly, and its fuel stays in its tank for you.
g = game(60, 0, 0)
g.hoons.metres, g.hoons.speed = 4, 0
g:run(0, RB.STUCK_SECONDS + 3)
g.hoons.state = 'DOWN'
T.eq(#g:run(RB.STUCK_SECONDS + 3.5, RB.STUCK_SECONDS + 4), 0, 'the pack says it is down')
T.eq(g.r:active(), false, 'robbery over'); T.near(g.truck + g.hoon, 60, 1e-6, 'its tank holds your fuel')

-- Fuel on its way when the robbery ends goes back where it came from.
g = game(60, 0, 0)
g.hoons.metres, g.hoons.speed = 4, 0
g:run(0, RB.STUCK_SECONDS + 1)
g.hold = true
g:run(RB.STUCK_SECONDS + 1.5, RB.STUCK_SECONDS + 2)
T.eq(#g.held, 1, 'your truck has given up a few litres, not yet answered')
g.hoons.state = 'DOWN'
g:run(RB.STUCK_SECONDS + 2.5, RB.STUCK_SECONDS + 2.5)
g.hold = false
local a = table.remove(g.held, 1)
T.eq(g.r:answer(a[1], a[2], a[3], a[4], 13), true, 'the late answer is still Tanker\'s')
T.near(g.truck + g.hoon, 60, 1e-6, 'and those litres go back into your truck')
g = game(60, 20, 0)
g.hoons.metres, g.hoons.speed = 4, 0
g:run(0, RB.STUCK_SECONDS + 1)
g.hold = true
g:run(RB.STUCK_SECONDS + 1.5, RB.STUCK_SECONDS + 2)
g.r:cancel(13)
T.near(g.bed + g.hoon, 20, 1e-6, 'litres from the bed tank on their way reach the Hoon')
-- One whose tank turns out full when the late answer comes: what didn't fit goes back.
g = game(60, 20, 79, 80)
g.hoons.metres, g.hoons.speed = 4, 0
g:run(0, RB.STUCK_SECONDS + 1)
g.hold = true
g:run(RB.STUCK_SECONDS + 1.5, RB.STUCK_SECONDS + 2)
g.r:cancel(13)
g.hold = false
for _, h in ipairs(g.held) do g.r:answer(h[1], h[2], h[3], h[4], 13) end
T.near(g.bed + g.hoon, 99, 1e-6, 'no fuel made or lost'); T.near(g.hoon, 80, 1e-6, 'the Hoon\'s tank is full')

-- No Hoon free to come: nothing happens, and it asks again.
g = game(60, 0, 0)
g.hoons.none = true
g:run(0, RB.STUCK_SECONDS + 2)
T.eq(g.r:active(), false, 'no robbery without a Hoon')

-- The pack drives the robber: up beside you and stopped, then away fast, and gone at 400 m.
local function fakeCar()
  local car = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 0 }, cars = {}, next = 100, paths = {}, released = {} }
  function car:player() return self.me end
  function car:ground() return 0 end
  function car:take() self.next = self.next + 1; return self.next, 'own' end
  function car:place(id, px, py, pz) self.cars[id] = { x = px, y = py, z = pz, speed = 10 }; return true end
  function car:goTo(id, aim) self.paths[id] = aim; return true end
  function car:state(id) return self.cars[id] end
  function car:calm() end
  function car:release(id) self.released[#self.released + 1] = id; self.cars[id] = nil end
  function car:removeAll() end
  function car:road() return nil end
  function car:chase() end
  return car
end
local car = fakeCar()
local p = P.new(car, function(lo) return lo end)
p:add(0); p:add(0)
p:step(0.5)
local near = p.hoons[1].metres <= p.hoons[2].metres and p.hoons[1] or p.hoons[2]
local id = p:startRob(1)
T.eq(id, near.id, 'the nearest Hoon comes'); T.eq(near.state, 'ROB', 'to rob you')
T.eq(p:startRob(1), nil, 'one at a time')
local rb = p:robber()
T.eq(rb.id, id, 'the robber'); T.check(rb.metres ~= nil, 'and how far it is')
near.replanAt = nil
p:steer(1.5)
local aim = car.paths[id]
T.near(math.abs(aim.x), P.ROB_SIDE, 1e-6, 'it drives to just beside you'); T.near(aim.y, 0, 1e-6, 'level with you')
T.check(aim.speed > 0 and aim.speed <= P.ROB_MPS, 'not too fast')
car.cars[id].x, car.cars[id].y, car.cars[id].speed = aim.x, aim.y, 0
near.replanAt = nil
p:step(2)
T.eq(car.paths[id].speed, 0, 'there, it stops')
T.eq(near.state, 'ROB', 'and stays, though you are stopped')
p:view()
T.eq(P.DOING.ROB, 'pulling up to siphon your fuel', 'the panel says so')
T.eq(p:flee(id, 3), true, 'then speeds off')
near.replanAt = nil
p:steer(3)
T.eq(car.paths[id].speed, P.FLEE_MPS, 'flat out')
local fx = car.paths[id].x - car.cars[id].x
T.check(fx * aim.x > 0, 'away from you')
car.cars[id].x, car.cars[id].y = 0, P.ESCAPE_METRES + 50
local line = p:step(4)
T.eq(line, P.LINES.fled, 'gone at 400 m'); T.eq(p:robber(), nil, 'no robber now')
-- A robber you drive away from before it takes anything goes back to sizing you up.
id = p:startRob(5)
T.eq(p:unrob(id, 5), true, 'sent back'); T.eq(p:robber(), nil, 'back to circling')
-- In road mode the robber still pulls up beside you, not chasing along the road.
car.road = function(_, x, y, z) return { x = x, y = y, z = z, metres = 0 } end
id = p:startRob(6)
for t = 6, 6 + P.MODE_SECONDS + 1, 0.5 do p:step(t) end
T.eq(p.mode, 'road', 'road mode'); T.eq(p:robber().id, id, 'still robbing')
-- Shot down while robbing: it is down, with your fuel in its tank.
for _ = 1, P.SHOTS_TO_STOP do p:shot(id) end
T.eq(p:robber(), nil, 'no robber once it is down')

-- In the game: stopped with a Hoon about, it pulls up and siphons you through the truck's own
-- fuel calls, and the centre window says so.
local F = require('fixtures')
local R = require('tanker/route')
local adapter = F.adapter(-31.0, 140.0)
local carG = fakeCar()
local nearG = F.nearby({}, 0)
local c, env = F.controller(adapter, { packCar = carG, nearby = nearG, random = function(lo) return lo end })
local function tick(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
tick(1); c:startRun(); adapter:put(R.START.latitude, R.START.longitude); tick(1)
c:fuelReading(7, 60, 300)
T.eq(c:addHoon(), true, 'a Hoon about')
local hoonId = c.pack.hoons[1].id
tick(RB.STUCK_SECONDS + 1)
T.eq(c.pack.hoons[1].state, 'ROB', 'stopped too long: it comes to rob you')
T.check(c:view().robbery and c:view().robbery.active, 'the centre window says so')
carG.cars[hoonId].x, carG.cars[hoonId].y, carG.cars[hoonId].speed = 4, 0, 0
local before = #env.fuel.changes
tick(1)
local take = env.fuel.changes[before + 1]
T.check(take and take.id == nil and take.litres < 0, 'it takes from your truck')
c:fuelChanged(7, take.serial, 60, 60 + take.litres, 300)
T.eq(c:view().fuel.litres, 60 + take.litres, 'your tank shows it')
local give = env.fuel.changes[#env.fuel.changes]
T.eq(give.id, hoonId, 'into the Hoon\'s tank'); T.near(give.litres, -take.litres, 1e-9, 'every litre')
c:fuelChanged(hoonId, give.serial, 5, 5 + give.litres, 80)
T.eq(c:view().fuel.litres, 60 + take.litres, 'the Hoon\'s answer is not your tank')
T.near(c:view().robbery.litres, give.litres, 1e-9, 'the window counts what it took')
nearG.speed = 5; tick(0.5)
T.eq(c.pack.hoons[1].state, 'FLEE', 'you drive off: it runs with what it got')

T.done('robbery')
