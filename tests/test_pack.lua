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

-- A pretend game: goTo puts the Hoon straight at its slot.
local function fakeCar()
  local car = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }, cars = {}, next = 100,
    paths = {}, strikes = {}, released = {}, calmed = 0 }
  function car:player() return self.me end
  function car:ground() return 0 end
  function car:take()
    if self.refuse then return nil, self.refuse end
    self.next = self.next + 1
    return self.next, 'own'
  end
  function car:place(id, px, py, pz) self.cars[id] = { x = px, y = py, z = pz, speed = 20 }; return true end
  -- Pretend the Hoon gets to its slot at once.
  function car:goTo(id, aim)
    self.paths[id] = aim
    if not self.frozen then self.cars[id].x, self.cars[id].y = aim.slotX, aim.slotY end
    return true
  end
  function car:state(id) return self.cars[id] end
  function car:calm() self.calmed = self.calmed + 1 end
  function car:release(id, source) self.released[#self.released + 1] = { id = id, source = source }; self.cars[id] = nil end
  function car:removeAll() self.removedAll = true end
  function car:road(x, y, z) if self.onRoad then return { x = x, y = y, z = z, metres = 0 } end end
  car.chases = {}
  function car:chase(id, target) self.chases[#self.chases + 1] = { id = id, target = target } end
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

-- A Hoon turns up at a far slot, in its own car, and circles the far slots before closing in.
local car = fakeCar()
local p = P.new(car, random)
local line = p:add(0)
local h = p.hoons[1]
T.eq(h.source, 'own', 'the Hoon comes in its own car')
T.eq(line, P.LINES.arrived(h.slot), 'says where it turned up')
T.eq(P.SLOTS[h.slot].far, true, 'at a far slot'); T.eq(h.state, 'CIRCLING', 'sizing you up')
T.eq(h.movesLeft, P.CIRCLES[1], 'circles a few far slots first')
local moves, last, forwards = 0, h.slot, true
for t = 0.5, 30, 0.5 do
  p:step(t)
  if h.state ~= 'CIRCLING' then break end
  if h.slot ~= last then
    moves = moves + 1
    if P.SLOTS[h.slot].ahead < 0 then forwards = false end
    last = h.slot
  end
end
T.eq(moves, P.CIRCLES[1], 'moved round the far slots like a hyena')
T.check(forwards, 'always forwards, to a front slot, never dropping back')
T.eq(P.forward('RRF'), 'RFF', 'rear to the front on the same side')
T.eq(P.forward('RFF'), 'LFF', 'front to the other front, round your nose')
T.eq(P.forward('LFF'), 'RFF', 'and back')
T.eq(h.state, 'CLOSING', 'then closes in'); T.eq(P.SLOTS[h.slot].far, nil, 'to a near slot')
-- It drives at its slot, and once there keeps pace with you, aiming a little beyond the slot.
local aim = car.paths[h.id]
local nx, ny = slotAt(h.slot)
T.eq(aim.slotX, nx, 'it drives to the slot'); T.eq(aim.slotY, ny, 'level with your front or back')
p:steer(1000)
aim = car.paths[h.id]
T.near(aim.speed, car.me.speed, 0.01, 'at the slot it keeps pace with you')
T.eq(aim.mode, 'coast', 'getting into place it never brakes')
T.eq(aim.x, nx, 'running alongside'); T.near(aim.y, ny + car.me.speed * P.LEAD_SECONDS, 0.01, 'aiming a little ahead')
car.cars[h.id].y = ny - 20
p:steer(1001)
T.near(car.paths[h.id].speed, car.me.speed + 20 * P.GAIN, 0.01, 'behind its slot it speeds up')
car.cars[h.id].y = ny - 200
p:steer(1002)
T.eq(car.paths[h.id].speed, car.me.speed + P.CATCH_UP_MPS, 'but only so much faster than you')
car.cars[h.id].y = ny + 50
p:steer(1003)
T.eq(car.paths[h.id].speed, car.me.speed - P.DROP_MPS, 'far past it, it eases off to drop back, never braking hard')
T.eq(car.paths[h.id].x, nx, 'still aiming along its slot')
car.cars[h.id].y = ny
p:steer(1003.1)
T.eq(car.paths[h.id].speed, car.me.speed - P.DROP_MPS, 'and is only steered every few frames')
-- Past its point while you drive on: it aims a little ahead of itself, never behind (its driver
-- would turn round), and eases off so the point comes back to it.
car.cars[h.id].x, car.cars[h.id].y = nx, ny + 30
p:steer(1003.5)
T.check(car.paths[h.id].y >= ny + 30 + P.MIN_LEAD - 0.01, 'aims ahead of itself, not behind')
T.eq(car.paths[h.id].speed, car.me.speed - P.DROP_MPS, 'easing off to drop back')
-- The rear far slots are closer in.
local rr, ra = P.offset('RRF')
T.eq(rr, P.REAR_FAR_SIDE, 'rear far slots 30 m out'); T.check(ra < 0, 'behind you')
T.check(math.sqrt(rr * rr + ra * ra) < 35, 'about 30 m from you')
-- You stop beside it: it circles its point instead of parking.
local mySpeed = car.me.speed
car.me.speed = 0
local sx, sy = P.at(car.me, P.offset(h.slot))
car.cars[h.id].x, car.cars[h.id].y = sx + 5, sy
p:steer(1004)
local o = car.paths[h.id]
T.eq(o.speed, P.MIN_MPS, 'you stopped: it keeps moving')
T.near(math.sqrt((o.x - sx) ^ 2 + (o.y - sy) ^ 2), P.ORBIT_METRES, 0.01, 'round its point')
T.check(o.y ~= sy, 'aiming further round, not at the point')
car.me.speed = mySpeed
p:steer(1004)

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
T.eq(math.abs(car.paths[h.id].slotX), P.WINDUP_SIDE, 'edging in to 6 m')
car.frozen = true
lines, t = runUntil(p, t + 0.5, function() return h.state == 'SWIPE' end)
local side = P.SLOTS[h.slot].side
local _, slotAhead = P.offset(h.slot)
aim = car.paths[h.id]
T.eq(aim.slotX, side * P.SWIPE_INTO, 'the swipe drives into your side'); T.eq(aim.slotY, slotAhead, 'at the corner by its slot')
T.near(aim.y, slotAhead + P.STRIKE_LEAD, 0.01, 'turning in hard'); T.eq(aim.speed, car.me.speed, 'at your speed')
T.eq(aim.mode, 'swipe', 'with no brake, turning in suddenly')
car.frozen = nil
lines, t = runUntil(p, t + 0.5, function() return h.state == 'CIRCLING' end)
T.check(has(lines, P.LINES.swiped), 'hits you and peels off'); T.eq(h.state, 'CIRCLING', 'back out to a far slot')
T.eq(P.SLOTS[h.slot].far, true, 'a far one')

-- A second Hoon: one per slot, and only one attacks at a time.
line = p:add(t)
local h2 = p.hoons[2]
T.eq(h2.source, 'own', 'so does the second')
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
T.eq(lp.slotX, 0, 'the lead is right in front'); T.eq(lp.slotY, P.HALF_LENGTH + P.BOX_AHEAD, 'a few metres ahead')
p2:steer(boxed + 0.1)
T.check(car2.paths[lead.id].speed >= car2.me.speed, 'gathering: the lead runs at your speed while the other gets alongside')
local squeezed
for t = boxed + 0.5, boxed + P.GATHER_SECONDS + 1, 0.5 do
  if p2:step(t) == P.LINES.squeeze then squeezed = t break end
end
T.check(squeezed ~= nil and squeezed - boxed < P.GATHER_SECONDS, 'once the other is alongside, they squeeze')
p2:steer(squeezed + 0.3)
T.near(car2.paths[lead.id].speed, car2.me.speed * P.BOX_SLOW, 0.01, 'and slower than you')
T.near(car2.paths[side.id].speed, car2.me.speed * P.BOX_SLOW, 1.0, 'both of them together')
boxed = squeezed
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
car2.frozen = true
car2.cars[lead.id].x, car2.cars[lead.id].y, car2.cars[side.id].x, car2.cars[side.id].y = 0, 399, 0, 399
run(p2, 100, 0.5)
T.eq(#p2.hoons, 2, 'downed Hoons wait while you are within 400 m')
car2.cars[lead.id].y, car2.cars[side.id].y = 401, 401
run(p2, 101, 0.5)
T.eq(#p2.hoons, 0, 'and are given back once you are more than 400 m away')
car2.frozen = nil

-- A team box: with four Hoons, one leads in front, one on each side and one behind, and they
-- keep the box going if one is lost.
local car5 = fakeCar()
coin = 0.1
local p5 = P.new(car5, random)
for _ = 1, 4 do p5:add(0) end
local teamLine
for t = 0.5, 20, 0.5 do
  local l = p5:step(t)
  if l == P.LINES.teamBox(4) then teamLine = t break end
end
T.check(teamLine ~= nil, 'four Hoons work together to box you in')
local roles = {}
for _, o in ipairs(p5.hoons) do roles[o.state] = (roles[o.state] or 0) + 1 end
T.eq(roles.BOXING, 1, 'one leads in front'); T.eq(roles.BOX_SIDE, 2, 'two beside you')
T.eq(roles.BOX_REAR, 1, 'one behind you')
local sides = {}
for _, o in ipairs(p5.hoons) do if o.state == 'BOX_SIDE' then sides[o.side] = true end end
T.check(sides[1] and sides[-1], 'one on each side')
local leader
for _, o in ipairs(p5.hoons) do if o.state == 'BOXING' then leader = o end end
local squeezedAt
for t = teamLine + 0.5, teamLine + P.GATHER_SECONDS + 1, 0.5 do
  if p5:step(t) == P.LINES.squeeze then squeezedAt = t break end
end
T.check(squeezedAt ~= nil, 'they squeeze together')
p5:shot(leader.id); p5:shot(leader.id); p5:shot(leader.id); p5:shot(leader.id)
T.eq(leader.state, 'DOWN', 'you shoot the lead down')
local newLead, still = nil, 0
for _, o in ipairs(p5.hoons) do
  if o.state == 'BOXING' then newLead = o end
  if o.state == 'BOX_SIDE' or o.state == 'BOX_REAR' then still = still + 1 end
end
T.check(newLead ~= nil and newLead ~= leader, 'a helper takes over the lead')
T.eq(newLead.squeeze, true, 'and keeps squeezing'); T.eq(still, 2, 'the rest stay in the box')
p5:step(squeezedAt + 1)
for _, o in ipairs(p5.hoons) do if o.lead then T.eq(o.lead, newLead, 'following the new lead') end end
local onlyOne = P.new(fakeCar(), random)
onlyOne:add(0)
for t = 0.5, 20, 0.5 do onlyOne:step(t) end
T.check(onlyOne.hoons[1].state ~= 'BOXING', 'a Hoon on its own never boxes, it swipes')

-- Stuck while you drive: down. Getting away: lost. Gone: forgotten. Full: no more.
local car3 = fakeCar()
coin = 0.9
local p3 = P.new(car3, random)
p3:add(0)
car3.frozen = true
car3.cars[p3.hoons[1].id].speed = 0
local lines3 = run(p3, 0.5, P.DOWN_SECONDS + 1)
T.check(not has(lines3, P.LINES.down), 'a Hoon that never hit you is not down for being slow')
T.eq(p3.hoons[1].stalls, 2, 'its stalls are counted'); T.check(p3.stalled ~= nil, 'and reported')
p3.hoons[1].hasHit = true
T.check(has(run(p3, 20, P.DOWN_SECONDS + 1), P.LINES.down), 'one that hit you and is stuck is down')
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
c:hoonPhase(c.pack.hoons[2].id, 'BRAKE_CHECK')
T.eq(c.pack.hoons[2].phase, 'BRAKE_CHECK', 'the driver\'s reports reach the Hoon')
T.check(c:view().pack.mode ~= nil, 'the Rig tab shows the mode')
T.eq(c:clearHoons(), true, 'clear'); T.eq(#c.pack.hoons, 0, 'all gone'); T.eq(c.feedback, P.LINES.cleared, 'and says so')
c:packProblem(101, 'no_script_ai'); c:packProblem(101, 'no_script_ai')
c:shutdown()
T.eq(car4.removedAll, true, 'the cars go with Tanker')

-- The game's side: every Hoon gets a HoonOld1 of ours, never a traffic car; its point is sent,
-- and its car is hidden for the next Hoon.
local v3 = function(px, py, pz) return { x = px, y = py, z = pz } end
local commands, removed, loads = {}, {}, 0
local hc = {
  player = function() return { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 10 } end,
  state = function() return nil end,
  calm = function() end, hunt = function() end, hide = function(_, id) commands[#commands + 1] = 'hide ' .. id end,
  load = function() loads = loads + 1; return 49 + loads, 'barstow' end, remove = function(_, id) removed[#removed + 1] = id end,
}
local pc = PC.new(hc, {
  byId = function(id) return { queueLuaCommand = function(_, cmd) commands[#commands + 1] = cmd end, id = id } end,
})
local id, source = pc:take(hc.player())
T.eq(id, 50, 'the Hoon\'s own car is loaded'); T.eq(source, 'own', 'its own, not from traffic')
id = pc:take(hc.player())
T.eq(id, 51, 'a second Hoon loads a second car')
T.eq(pc:goTo(50, { x = 4, y = 5, z = 6, speed = 22.5 }), true, 'point sent')
T.check(commands[#commands]:find('tankerDriver.target(4.00, 5.00, 6.00, 22.50, nil)', 1, true) ~= nil, 'to Tanker\'s own driver')
pc:goTo(50, { x = 4, y = 5, z = 6, speed = 22.5, mode = 'coast' })
T.check(commands[#commands]:find('22.50, "coast")', 1, true) ~= nil, 'with no brake when asked')
T.check((loadstring or load)(commands[#commands]) ~= nil, 'still valid Lua')
T.check(commands[#commands]:find('ai.setSlotTrafficTarget, 4.00, 5.00, 6.00, 22.50', 1, true) ~= nil, 'or BeamNG\'s slotTraffic AI without it')
T.check((loadstring or load)(commands[#commands]) ~= nil, 'the command is valid Lua')
T.eq(pc:goTo(50, { x = 0 / 0, y = 5, z = 6, speed = 1 }), false, 'a broken point is not sent')
T.eq(pc:goTo(7, { x = 4, y = 5, z = 6, speed = 1 }), false, 'never sent to your own car, even if it was a Hoon\'s')
T.eq(pc:release(50, 'own'), true, 'let go')
T.eq(commands[#commands], 'hide 50', 'its car is hidden')
id = pc:take({ id = 7, x = 0, y = 0, z = 0 })
T.eq(id, 50, 'the hidden car is reused, not loaded again'); T.eq(loads, 2, 'still two loads')
pc:removeAll()
T.eq(removed[#removed], 51, 'loaded cars removed when Tanker goes')

-- Road and desert modes: on a road for 5 s, the Hoons drive themselves (overtake, cut in,
-- brake-check); off road for 5 s, back to the slots.
local car6 = fakeCar()
car6.onRoad = true
local p6 = P.new(car6, random)
T.eq(p6:add(0), P.LINES.arrivedRoad, 'on the road, a Hoon comes up the road behind you')
local h6 = p6.hoons[1]
T.eq(h6.state, 'ROAD', 'in road mode'); T.eq(car6.chases[1].target, 7, 'its own driver hunts you')
T.eq(car6.cars[h6.id].y, -P.ROAD_START_METRES, 'put on the road behind you')
p6:steer(1)
T.eq(car6.paths[h6.id], nil, 'not steered to a slot')
T.eq(p6:roadPhase(h6.id, 'PASS'), true, 'its driver says what it is doing')
T.eq(p6:view()[1].doing, P.ROAD_DOING.PASS, 'and the HUD shows it')
car6.onRoad = nil
local l6 = run(p6, 1, P.MODE_SECONDS - 1)
T.eq(h6.state, 'ROAD', 'a few seconds off road changes nothing')
l6 = run(p6, 1 + P.MODE_SECONDS - 0.5, 2)
T.check(has(l6, P.LINES.desertMode), 'off road for 5 s: desert mode'); T.eq(h6.state, 'CIRCLING', 'back to the slots')
T.eq(P.SLOTS[h6.slot].far, true, 'at a far slot'); T.check(car6.paths[h6.id] ~= nil, 'driven to it')
car6.onRoad = true
l6 = run(p6, 20, P.MODE_SECONDS + 1)
T.check(has(l6, P.LINES.roadMode), 'on the road for 5 s: road mode again'); T.eq(h6.state, 'ROAD', 'driving itself')
T.eq(#car6.chases, 2, 'hunting you on the road again')
car6.onRoad = nil
local p7 = P.new(fakeCar(), random)
p7:add(0)
T.eq(p7.mode, 'desert', 'off road, a new Hoon starts in desert mode'); T.eq(p7.hoons[1].state, 'CIRCLING', 'circling')

T.done('pack')
