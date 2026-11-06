local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('tanker/pack')
local PC = require('tanker/packCar')
local R = require('tanker/route')

-- The slots, from your middle: you face north (+y) at the origin, so right is +x.
local function slotAt(name)
  local r, a = P.offset(name)
  return P.at({ x = 0, y = 0, dx = 0, dy = 1, speed = 0 }, r, a, 0)
end
local x, y = slotAt('RFF')
T.eq(x, P.FAR_SIDE, 'RFF is 60 m to your right'); T.eq(y, P.HALF_LENGTH + P.FAR_BEYOND, 'and 10 m past your front')
x, y = slotAt('LRN')
T.eq(x, -P.NEAR_SIDE, 'LRN is 10 m to your left'); T.eq(y, -P.HALF_LENGTH, 'level with your back')
-- Facing east (+x), your right is south.
x, y = P.at({ x = 100, y = 0, dx = 1, dy = 0 }, 10, 0, 0)
T.eq(x, 100, 'facing east, right of you'); T.eq(y, -10, 'is south')
-- Ahead at speed: where the slot will be in two seconds.
x, y = P.at({ x = 0, y = 0, dx = 0, dy = 1, speed = 20 }, 0, 5, 2)
T.eq(y, 45, 'a slot moves with you')

-- A pretend game: goTo puts the Hoon straight at its slot; a strike puts it on you.
local function fakeCar()
  local car = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }, cars = {}, next = 100,
    paths = {}, strikes = {}, released = {}, calmed = 0, traffic = 1 }
  function car:player() return self.me end
  function car:ground() return 0 end
  function car:take()
    if self.refuse then return nil, self.refuse end
    self.next = self.next + 1
    local source = self.traffic > 0 and 'traffic' or 'own'
    self.traffic = self.traffic - 1
    return self.next, source
  end
  function car:place(id, px, py, pz) self.cars[id] = { x = px, y = py, z = pz, speed = 20 }; return true end
  function car:goTo(id, points)
    self.paths[id] = points
    local p = points[#points - 2]
    -- Where that point is now: the path runs ahead with you.
    local go = self.me.speed * p.t
    if not self.frozen then self.cars[id].x, self.cars[id].y = p.x - self.me.dx * go, p.y - self.me.dy * go end
    return true
  end
  function car:strike(id, target)
    self.strikes[#self.strikes + 1] = { id = id, target = target }
    if self.hitOnStrike then self.cars[id].x, self.cars[id].y = 2, 0 end
  end
  function car:state(id) return self.cars[id] end
  function car:calm() self.calmed = self.calmed + 1 end
  function car:release(id, source) self.released[#self.released + 1] = { id = id, source = source }; self.cars[id] = nil end
  function car:removeAll() self.removedAll = true end
  return car
end
-- Random: the low end, except coin flips (0 to 1), which the test sets.
local coin = 0.9
local function random(lo, hi) if lo == 0 and hi == 1 then return coin end return lo end
local function run(p, from, seconds)
  local lines = {}
  for t = from, from + seconds, 0.5 do
    local l = p:step(t)
    if l then lines[#lines + 1] = l end
  end
  return lines
end
local function has(lines, line)
  for _, l in ipairs(lines) do if l == line then return true end end
  return false
end

-- A Hoon turns up at a far slot, from traffic, and circles the far slots before closing in.
local car = fakeCar()
local p = P.new(car, random)
local line = p:add(0)
local h = p.hoons[1]
T.eq(h.source, 'traffic', 'the first Hoon comes from traffic')
T.eq(line, P.LINES.arrived(h.slot), 'says where it turned up')
T.eq(P.SLOTS[h.slot].far, true, 'at a far slot'); T.eq(h.state, 'CIRCLING', 'sizing you up')
T.eq(h.movesLeft, P.CIRCLES[1], 'circles a few far slots first')
local seen = { [h.slot] = true }
for t = 0.5, 30, 0.5 do
  p:step(t)
  if h.state ~= 'CIRCLING' then break end
  seen[h.slot] = true
end
local farSeen = 0
for s in pairs(seen) do if P.SLOTS[s].far then farSeen = farSeen + 1 end end
T.eq(farSeen, P.CIRCLES[1] + 1, 'moved round the far slots like a hyena')
T.eq(h.state, 'CLOSING', 'then closes in'); T.eq(P.SLOTS[h.slot].far, nil, 'to a near slot')
-- Every path ends level with the slot and keeps going at your speed.
local path = car.paths[h.id]
local nx, ny = slotAt(h.slot)
T.eq(path[#path - 2].x, nx, 'the path goes to the slot'); T.eq(path[#path - 2].y, ny + car.me.speed * path[#path - 2].t, 'where it will be by then')
T.near(path[#path].y - path[#path - 1].y, 3 * car.me.speed, 0.01, 'then keeps pace with you')

-- At the near slot it waits, lines up (edging in), then swipes with the chase AI.
local function runUntil(pp, from, state, limit)
  local lines, t = {}, from
  while t <= from + (limit or 30) do
    local l = pp:step(t)
    if l then lines[#lines + 1] = l end
    if state() then break end
    t = t + 0.5
  end
  return lines, t
end
local lines, t = runUntil(p, 30.5, function() return h.state == 'WINDUP' end)
T.eq(h.state, 'WINDUP', 'lines up'); T.check(has(lines, P.LINES.windup(h.slot)), 'and you are told')
T.eq(math.abs(car.paths[h.id][#car.paths[h.id] - 2].x), P.WINDUP_SIDE, 'edging in to 6 m')
T.eq(#car.strikes, 0, 'not striking yet')
car.hitOnStrike = true
lines, t = runUntil(p, t + 0.5, function() return h.state == 'CIRCLING' end)
T.eq(#car.strikes, 1, 'strikes with the chase AI'); T.eq(car.strikes[1].target, 7, 'at you')
T.check(has(lines, P.LINES.swiped), 'hits you and peels off'); T.eq(h.state, 'CIRCLING', 'back out to a far slot')
T.eq(P.SLOTS[h.slot].far, true, 'a far one')
car.hitOnStrike = nil

-- A second Hoon: one per slot, and only one attacks at a time.
line = p:add(t)
local h2 = p.hoons[2]
T.eq(h2.source, 'own', 'with no traffic left, the Hoon\'s own car')
T.check(h2.slot ~= h.slot, 'a different slot')
local both = 0
for tt = t + 0.5, t + 80, 0.5 do
  p:step(tt)
  if h.slot and h.slot == h2.slot then T.check(false, 'two Hoons in one slot at ' .. tt) end
  local n = 0
  for _, o in ipairs(p.hoons) do if o.state == 'WINDUP' or o.state == 'SWIPE' then n = n + 1 end end
  if n > 1 then both = both + 1 end
end
T.eq(both, 0, 'never two attacking at once')

-- Boxing: the lead gets in front and slows, the other sits beside you. Stopped, you are boxed in.
local car2 = fakeCar()
coin = 0.1 -- bold, and a box
local p2 = P.new(car2, random)
p2:add(0); p2:add(0)
local a, b = p2.hoons[1], p2.hoons[2]
T.eq(a.movesLeft, 0, 'a bold Hoon moves in at once')
local boxed
for t = 0.5, 20, 0.5 do
  local l = p2:step(t)
  if l == P.LINES.box then boxed = t break end
end
T.check(boxed ~= nil, 'a box attack starts')
local lead = a.state == 'BOXING' and a or b
local side = lead == a and b or a
T.eq(lead.state, 'BOXING', 'one Hoon leads'); T.eq(side.state, 'BOX_SIDE', 'the other sits beside you')
local lp = car2.paths[lead.id]
T.eq(lp[#lp - 2].x, 0, 'the lead is right in front'); T.near(lp[#lp - 2].y - car2.me.speed * P.BOX_SLOW * lp[#lp - 2].t, P.HALF_LENGTH + P.BOX_AHEAD, 0.01, 'a few metres ahead')
T.near(lp[#lp].y - lp[#lp - 1].y, 3 * car2.me.speed * P.BOX_SLOW, 0.01, 'and slower than you')
car2.me.speed = 0
lines = run(p2, boxed + 0.5, P.BOXED_SECONDS + 1)
T.check(has(lines, P.LINES.boxed), 'stopped, you are boxed in')
run(p2, boxed + 5, P.BOX_HOLD_SECONDS + 1)
T.check(lead.state ~= 'BOXING' and side.state ~= 'BOX_SIDE', 'then they peel off')
car2.me.speed = 20

-- Shots: four hits stop one; a downed Hoon is no threat and is given back once you leave.
local before = #p2:distances()
for _ = 1, P.SHOTS_TO_STOP - 1 do T.eq(select(2, p2:shot(lead.id)), true, 'hit a Hoon') end
T.eq(p2:shot(lead.id), P.LINES.shotDown, 'four hits stop it'); T.eq(lead.state, 'DOWN', 'down')
T.eq(#p2:distances(), before - 1, 'no longer lights the threat')
T.eq(p2:driverShot(side.id), P.LINES.driverShot, 'a shot through the driver stops one at once')
car2.me.y = 5000
run(p2, 100, 1)
T.eq(#p2.hoons, 0, 'downed Hoons are given back once you are far away')

-- Stuck while you drive: down. Getting away: lost. Gone: forgotten. Full: no more.
local car3 = fakeCar()
coin = 0.9
local p3 = P.new(car3, random)
p3:add(0)
car3.frozen = true
car3.cars[p3.hoons[1].id].speed = 0
T.check(has(run(p3, 0.5, P.DOWN_SECONDS + 1), P.LINES.down), 'a stuck Hoon is down')
p3:clear(); car3.frozen = nil
T.eq(#p3.hoons, 0, 'clear sends them all away')
p3:add(0)
car3.frozen = true
car3.cars[p3.hoons[1].id].x = 399
T.eq(p3:step(0.5), nil, 'a Hoon 399 m away stays'); T.eq(#p3.hoons, 1, 'still out')
car3.cars[p3.hoons[1].id].x = 401
T.eq(p3:step(1), P.LINES.escaped, 'more than 400 m away, it is gone at once'); T.eq(#p3.hoons, 0, 'despawned')
for _ = 1, P.MAX do p3:add(50) end
T.eq(#p3.hoons, P.MAX, 'up to the most at once')
local none, why = p3:add(50)
T.eq(none, nil, 'no more'); T.eq(why, 'full', 'says why')
car3.cars[p3.hoons[1].id] = nil
T.check(has(run(p3, 51, 0.5), P.LINES.gone), 'a car that vanished is handled')
p3:remove()
T.eq(car3.removedAll, true, 'Tanker going away removes the cars')
car3.refuse = 'no_hoon_model'
none, why = p3:add(60)
T.eq(why, 'no_hoon_model', 'no car, says why')

-- In the game: the Spawn a Hoon button adds one more each press, and Clear Hoons sends them away.
local adapter = F.adapter(-31.0, 140.0)
local car4 = fakeCar()
local c = F.controller(adapter, { packCar = car4, random = random })
local function tick(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
tick(1)
T.eq(c:addHoon(), false, 'no Hoons before the run')
c:startRun(); adapter:put(R.START.latitude, R.START.longitude); tick(1)
T.eq(c:view().addHoonAllowed, true, 'Spawn a Hoon offered on the road')
T.eq(c:view().clearHoonsAllowed, false, 'nothing to clear yet')
T.eq(c:addHoon(), true, 'one Hoon'); T.eq(c:addHoon(), true, 'press again for another')
T.eq(#c:view().pack.hoons, 2, 'the HUD lists both')
T.eq(c:view().pack.hoons[1].doing, P.DOING.CIRCLING, 'saying what each is doing')
tick(0.5)
T.check(c:view().threat ~= 'clear', 'they light the threat')
T.eq(c:view().nearestHoon, c.pack:nearest(), 'the strip shows the nearest Hoon'); T.check(c:view().nearestHoon ~= nil, 'with its distance'); T.eq(c:view().saveAllowed, false, 'no saving')
local hit = c.pack.hoons[1].id
for _ = 1, P.SHOTS_TO_STOP do c:vrHit(hit, false) end
T.eq(c.pack.hoons[1].state, 'DOWN', 'the revolver stops a desert Hoon')
T.eq(c:clearHoons(), true, 'clear'); T.eq(#c.pack.hoons, 0, 'all gone'); T.eq(c.feedback, P.LINES.cleared, 'and says so')
c:packProblem(101, 'no_script_ai'); c:packProblem(101, 'no_script_ai')
c:shutdown()
T.eq(car4.removedAll, true, 'the cars go with Tanker')

-- The game's side: a traffic car is taken, the path is sent, and it goes back to traffic.
local v3 = function(px, py, pz) return { x = px, y = py, z = pz } end
local commands, removed, inserted = {}, {}, {}
local game = {
  [7] = v3(0, 0, 0), [20] = v3(0, 100, 0), [21] = v3(0, 900, 0),
}
local hc = {
  player = function() return { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 10 } end,
  state = function(_, id) local s = game[id]; return s and { x = s.x, y = s.y, z = s.z, speed = 0 } end,
  calm = function() end, hide = function(_, id) commands[#commands + 1] = 'hide ' .. id end,
  load = function() return 50, 'barstow' end, remove = function(_, id) removed[#removed + 1] = id end,
}
local pc = PC.new(hc, {
  byId = function(id) return { queueLuaCommand = function(_, cmd) commands[#commands + 1] = cmd end, id = id } end,
  traffic = function() return {
    getTrafficData = function() return { [7] = {}, [20] = {}, [21] = {} } end,
    removeTraffic = function(id) removed[#removed + 1] = 'traffic ' .. id end,
    insertTraffic = function(id) inserted[#inserted + 1] = id end,
  } end,
})
local id, source = pc:take(hc.player())
T.eq(id, 21, 'takes the traffic car furthest from you'); T.eq(source, 'traffic', 'from traffic')
T.eq(removed[1], 'traffic 21', 'taken out of traffic')
id = pc:take(hc.player())
T.eq(id, 20, 'then the next one, never the same twice')
id, source = pc:take(hc.player())
T.eq(id, 50, 'with traffic used up, the Hoon\'s own car is loaded'); T.eq(source, 'own', 'its own')
T.eq(pc:goTo(21, { { x = 1, y = 2, z = 3, t = 0 }, { x = 4, y = 5, z = 6, t = 2.5 } }), true, 'path sent')
T.check(commands[#commands]:find('ai.startFollowing', 1, true) ~= nil, 'with the script AI')
T.check(commands[#commands]:find('{x=4.00,y=5.00,z=6.00,t=2.50}', 1, true) ~= nil, 'carrying the path')
local chunk = (loadstring or load)(commands[#commands])
T.check(chunk ~= nil, 'the command is valid Lua')
T.eq(pc:release(21, 'traffic'), true, 'given back'); T.eq(inserted[1], 21, 'to traffic')
pc:release(50, 'own')
T.eq(commands[#commands], 'hide 50', 'its own car is hidden')
id, source = pc:take({ id = 7, x = 0, y = 0, z = 0 })
T.eq(id, 21, 'traffic first again')
id = pc:take({ id = 7, x = 0, y = 0, z = 0 })
T.eq(id, 50, 'then the hidden car, reused, not loaded again')
pc:removeAll()
T.eq(removed[#removed], 50, 'loaded cars removed when Tanker goes')

T.done('pack')
