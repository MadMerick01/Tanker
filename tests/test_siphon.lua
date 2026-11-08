local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local S = require('tanker/siphon')
local R = require('tanker/route')

-- The logic alone: a litre a second from their tank into yours, exactly what came out.
local asked = {}
local s = S.new(function(litres, serial, id) asked[#asked + 1] = { litres = litres, serial = serial, id = id }; return true end)
T.eq(s:start(42, 0), true, 'starts on a car')
T.eq(s:start(43, 0), false, 'one siphon at a time')
s:step(0, 3, 0, { litres = 10, capacity = 100 })
T.eq(asked[1].litres, -1, 'takes a litre'); T.eq(asked[1].id, 42, 'from their car')
s:step(0.5, 3, 0, { litres = 10, capacity = 100 })
T.eq(#asked, 1, 'waits for their answer')
T.eq(s:answer(99, 1, 0, 50, 0.5), false, 'an answer to something else is ignored')
s:answer(asked[1].serial, 20, 19, 50, 0.5)
T.eq(asked[2].litres, 1, 'puts what came out into yours'); T.eq(asked[2].id, nil, 'your car')
s:answer(asked[2].serial, 10, 11, 100, 0.5)
T.near(s:view(0.5).litres, 1, 1e-9, 'one litre taken'); T.eq(s:view(0.5).theirs, 19, 'their tank shown')
s:step(0.9, 3, 0, { litres = 11, capacity = 100 })
T.eq(#asked, 2, 'no more than a litre a second')
s:step(1.0, 3, 0, { litres = 11, capacity = 100 })
T.eq(#asked, 3, 'the next litre after a second')
-- Their last half litre: only what was there moves, then it stops dry.
s:answer(asked[3].serial, 0.4, 0, 50, 1.1)
s:answer(asked[4].serial, 11, 11.4, 100, 1.1)
T.eq(s:active(), false, 'stops when their tank is dry')
T.near(s.result.taken, 1.4, 1e-9, 'kept what was taken')
T.check(s:view(2).result:find('dry'), 'says their tank is dry')
T.eq(s:view(1.1 + S.RESULT_SECONDS + 1), nil, 'the result goes after a few seconds')

-- Your tank nearly full: takes only the room left, then stops full.
local asked2 = {}
local s2 = S.new(function(litres, serial) asked2[#asked2 + 1] = { litres = litres, serial = serial }; return true end)
s2:start(5, 0)
s2:step(0, 3, 0, { litres = 99.7, capacity = 100 })
T.near(asked2[1].litres, -0.3, 1e-9, 'takes only the room you have')
s2:answer(asked2[1].serial, 30, 29.7, 50, 0)
s2:answer(asked2[2].serial, 99.7, 100, 100, 0)
T.eq(s2:active(), false, 'stops when your tank is full'); T.check(s2.result.text:find('full'), 'and says so')

-- Driving off, the car going, a silent car and Stop all end it, keeping what was taken.
local function fresh() local x = S.new(function() return true end); x:start(5, 0); return x end
local s3 = fresh(); s3:step(0, 3, 4, nil); T.eq(s3.result.reason, 'moved', 'driving off stops it')
local s4 = fresh(); s4:step(0, 30, 0, nil); T.eq(s4.result.reason, 'moved', 'too far away stops it')
local s5 = fresh(); s5:step(0, nil, 0, nil); T.eq(s5.result.reason, 'lost', 'the car gone stops it')
local s6 = fresh(); s6:step(0, 3, 0, nil); s6:step(S.WAIT_SECONDS + 1, 3, 0, nil); T.eq(s6.result.reason, 'lost', 'no answer stops it')
local s7 = fresh(); T.check(s7:finish('stopped', 0):find('stopped'), 'Stop stops it')
local s8 = S.new(function() return true end); s8:start(5, 0)
local sent8 = {}
s8 = S.new(function(l, serial) sent8[#sent8 + 1] = serial; return true end); s8:start(5, 0); s8:step(0, 3, 0, nil)
s8:answer(sent8[1], 0, 0, 0, 0)
T.check(s8.result.text:find('no fuel'), 'a car with no fuel says so')

-- In the game: a car beside you offers Siphon fuel, and the fuel shows in your tank.
local adapter = F.adapter(-31.0, 140.0)
local near = F.nearby({ [42] = 4 })
local c, env = F.controller(adapter, { nearby = near })
local function run(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
run(1)
T.eq(c:view().siphonNear, nil, 'nothing offered before the run')
T.eq(c:startSiphon(), false, 'no siphon before the run')
c:startRun(); adapter:put(R.START.latitude, R.START.longitude); run(1)
T.eq(c.state, 'RUNNING', 'on the road')
c:fuelReading(7, 50, 300)
-- In your truck: only on foot (MadMerick, 6 Nov), and the centre window says so.
local inTruck = c:view()
T.eq(inTruck.siphonAllowed, false, 'not from inside your truck'); T.eq(inTruck.siphonNear.needsFoot, true, 'the panel says get out')
T.eq(inTruck.siphonOffer.blocked, 'in_vehicle', 'so does the centre window'); T.eq(c:startSiphon(), false, 'no siphon')
-- Out on foot, the truck parked beside you. Your own truck is never offered as the car to siphon.
near.onFoot, near.cars[7] = true, 2; run(0.5)
T.eq(c.near.id, 42, 'the other car, not your truck')
local v = c:view()
T.eq(v.onFoot, true, 'on foot')
T.eq(v.siphonAllowed, true, 'Siphon fuel offered beside a car'); T.near(v.siphonNear.metres, 4, 1e-9, 'with how far it is')
near.speed = 5; run(0.5)
T.eq(c:view().siphonAllowed, false, 'not while driving'); T.eq(c:view().siphonNear.moving, true, 'says to stop')
near.speed = 0; run(0.5)
T.eq(c:startSiphon(), true, 'siphon started')
T.eq(c:view().siphonStopAllowed, true, 'Stop offered'); T.eq(c:view().siphon.active, true, 'the box shows')
run(0.5)
local take = env.fuel.changes[1]
T.eq(take.id, 42, 'takes from the car beside you'); T.eq(take.litres, -1, 'a litre')
c:fuelChanged(42, take.serial, 80, 79, 100)
local give = env.fuel.changes[2]
T.eq(give.id, 7, 'into your parked truck, not the walker'); T.eq(give.litres, 1, 'the same litre')
c:fuelChanged(7, give.serial, 50, 51, 300)
T.eq(c:view().fuel.litres, 51, 'your tank shows it at once')
T.eq(c:view().siphon.theirs, 79, 'their tank in the box')
env.hoonDistances = function() return { 300 } end; run(0.5)
T.eq(c:view().siphon.hoons, true, 'the box warns of Hoons')
env.hoonDistances = nil
T.eq(c:stopSiphon(), true, 'Stop'); T.check(c.feedback:find('You took 1 L'), 'says what you took')
T.eq(c:view().siphon.active, false, 'the box shows the result'); T.eq(c:view().siphonStopAllowed, false, 'Stop gone')

-- The centre window: stopped beside a car it offers the siphon, and with a bed tank asks where
-- the fuel goes. The last result shows first.
T.eq(c:view().siphonOffer, nil, 'the result first')
run(S.RESULT_SECONDS + 1)
local v2 = c:view()
T.check(v2.siphonOffer ~= nil, 'the centre window offers the siphon'); T.eq(v2.siphonOffer.bed, false, 'no bed tank, no choice')
near.speed = 5; run(0.5)
T.eq(c:view().siphonOffer, nil, 'not while you move')
near.speed = 0; run(0.5)
-- Your truck too far away: it says to bring it closer.
near.cars[7] = 40; run(0.5)
T.eq(c:view().siphonAllowed, false, 'not with your truck far off'); T.eq(c:view().siphonOffer.blocked, 'truck_far', 'says so')
T.eq(c:view().saveAllowed, false, 'no saving on foot')
near.cars[7] = 2; run(0.5)
-- Getting out spawns the walker: that is not a new truck.
near.walkers[8] = true
c:vehicleSpawned(8)
T.eq(c.partsCheckDue, nil, 'the walker is not your truck')
local adapterB = F.adapter(-31.0, 140.0)
local nearB = F.nearby({ [42] = 4 })
local cB, envB = F.controller(adapterB, { nearby = nearB, bed = F.bed() })
local function runB(seconds) for _ = 1, math.floor(seconds * 2) do cB:tick(0.5) end end
runB(1); cB:startRun(); adapterB:put(R.START.latitude, R.START.longitude); runB(1)
cB:bedRead(7, 200); cB:fuelReading(7, 15, 80)
nearB.onFoot, nearB.cars[7] = true, 3; runB(0.5)
local bedSets = #envB.bed.sets
local bedBefore = cB.bedLitres
T.eq(cB:view().siphonOffer.bed, true, 'with a bed tank, a choice')
T.eq(cB:startSiphon('bed'), true, 'siphon into the bed tank')
T.check(cB.feedback:find('bed tank', 1, true), 'says where')
runB(0.5)
local takeB = envB.fuel.changes[#envB.fuel.changes]
T.eq(takeB.id, 42, 'from their car')
cB:fuelChanged(42, takeB.serial, 80, 79, 100)
T.eq(envB.fuel.changes[#envB.fuel.changes], takeB, 'nothing sent into your truck')
T.near(cB.bedLitres, bedBefore + 1, 1e-9, 'the litre is in the bed tank')
T.eq(cB:view().siphon.into, 'bed', 'the window says the bed tank'); T.eq(cB:view().siphon.yoursCapacity, 200, 'and shows it')
cB:stopSiphon()
runB(3)
T.eq(#envB.bed.sets, bedSets, 'on foot, the bed tank\'s fuel waits')
nearB.onFoot = false; runB(3)
T.eq(envB.bed.sets[#envB.bed.sets], cB.bedLitres, 'back in the truck, it is poured in')
local cN = F.controller(F.adapter(-31.0, 140.0), { nearby = F.nearby({ [42] = 4 }) })
cN.state, cN.near, cN.foot, cN.truckMetres = 'RUNNING', { id = 42, metres = 4, speed = 0 }, true, 2
T.eq(cN:startSiphon('bed'), true, 'with no bed tank'); T.eq(cN.siphon.run.into, 'truck', 'it goes into your truck')

-- The game's side: on foot is the walking mode's unicycle, and your own truck can be skipped.
local NB = require('tanker/nearby')
local function gameCar(id, model, x)
  return { getID = function() return id end, getJBeamFilename = function() return model end,
    getPosition = function() return { x = x, y = 0, z = 0 } end, getVelocity = function() return { x = 0, y = 0, z = 0 } end }
end
local walkerCar, truckCar, other = gameCar(8, 'unicycle', 0), gameCar(7, 'us_semi', 2), gameCar(42, 'barstow', 5)
local byId = { [7] = truckCar, [8] = walkerCar, [42] = other }
local playerCar = walkerCar
local nb = NB.new({ player = function() return playerCar end, all = function() return { walkerCar, truckCar, other } end,
  byId = function(i) return byId[i] end })
T.eq(nb:player().onFoot, true, 'in the unicycle you are on foot')
T.eq(nb:isWalker(8), true, 'the unicycle is the walker'); T.eq(nb:isWalker(7), false, 'your truck is not')
T.eq(nb:closest().id, 7, 'without skipping, your truck is nearest')
T.eq(nb:closest(nil, 7).id, 42, 'skipping it, the other car')
T.near(nb:closest(7).metres, 2, 1e-9, 'and how far your truck is')
playerCar = truckCar
T.eq(nb:player().onFoot, false, 'in the truck you are not on foot')
local nbWalk = NB.new({ player = function() return truckCar end, all = function() return {} end,
  walk = function() return { isWalking = function() return true end } end })
T.eq(nbWalk:player().onFoot, true, 'the game\'s walking mode says so too')

-- The command sent into a car is valid Lua, and goes to the car with that id.
local fuel = require('tanker/fuel')
local commands, ids = {}, {}
local function car(id) return { getID = function() return id end, queueLuaCommand = function(_, cmd) commands[#commands + 1] = cmd; ids[#ids + 1] = id end } end
local f = fuel.new({ player = function() return car(7) end, byId = function(id) return car(id) end })
T.eq(f:change(-1, 3, 42), true, 'asks their car'); T.eq(ids[1], 42, 'the car with that id')
T.eq(f:change(1, 4), true, 'asks your car'); T.eq(ids[2], 7, 'your car')
T.check((loadstring or load)(commands[1]) ~= nil, 'the command is valid Lua')
T.check(commands[1]:find('fuelChanged(%d, %d', 1, true) and commands[1]:find(', 42, 3, before', 1, true), 'answers with its id and serial')
T.eq(f:change(0 / 0, 5, 42), false, 'nonsense litres refused')

-- The wrist shows a blinking pip while siphoning.
local W = require('tanker/wrist')
local plain, on, off = #W.build({}), #W.build({ siphon = { active = true, blink = true } }), W.build({ siphon = { active = true, blink = false } })
T.eq(on, plain + 2, 'a pip while siphoning')
T.eq(off[5][7], W.COLOURS.empty, 'it blinks off')
T.eq(#W.build({ siphon = { active = false } }), plain, 'no pip once it stops')
-- Into the bed tank (MadMerick, 6 Nov): their litres go straight into the bed tank's own number.
local askedB, bedL = {}, 190
local sb = S.new(function(litres, serial, id) askedB[#askedB + 1] = { litres = litres, serial = serial, id = id }; return true end,
  function(litres) local before = bedL; bedL = math.min(200, bedL + litres); return bedL - before, bedL, 200 end)
T.eq(sb:start(9, 0, 'bed'), true, 'starts into the bed tank'); T.eq(sb.run.into, 'bed', 'into the bed tank')
sb:step(0, 3, 0, { litres = bedL, capacity = 200 })
T.eq(askedB[1].litres, -1, 'takes a litre'); T.eq(askedB[1].id, 9, 'from their car')
sb:answer(askedB[1].serial, 30, 29, 60, 0)
T.eq(#askedB, 1, 'nothing put into your truck'); T.eq(bedL, 191, 'the bed tank has it')
T.near(sb:view(0, { litres = bedL, capacity = 200 }).litres, 1, 1e-9, 'one litre taken')
T.eq(sb:view(0).into, 'bed', 'the window knows where it goes')
for t = 1, 20 do
  sb:step(t, 3, 0, { litres = bedL, capacity = 200 })
  local last = askedB[#askedB]
  if sb.run and sb.run.pending then sb:answer(last.serial, 29, 29 + last.litres, 60, t) end
end
T.eq(sb:active(), false, 'stops when the bed tank is full'); T.eq(bedL, 200, 'filled to the top')
T.check(sb.result.text:find('The bed tank is full', 1, true), 'and says so')
T.check(sb.result.text:find('into the bed tank', 1, true), 'and where it went')
-- Without a bed tank, the fuel goes into the truck.
local sNo = S.new(function() return true end)
sNo:start(9, 0, 'bed')
T.eq(sNo.run.into, 'truck', 'no bed tank: into your truck')

T.done('siphon')
