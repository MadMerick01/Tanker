local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('tanker/transfer')
local R = require('tanker/route')
local B = require('tanker/bedTank')

-- The logic alone: a couple of litres a second, and the bed tank changes by what really moved.
local asked, bed = {}, { litres = 10, capacity = 800 }
local t = P.new(function(litres, serial) asked[#asked + 1] = { litres = litres, serial = serial }; return true end,
  function(d) bed.litres = bed.litres + d end)
T.eq(t:start('sideways', 0), false, 'only two ways to pump')
T.eq(t:start('toTruck', 0), true, 'pump into the truck')
t:step(0, { litres = 5, capacity = 80 }, bed)
T.eq(asked[1].litres, P.RATE, 'asks the truck to take a couple of litres')
T.check(asked[1].serial >= 1000000, 'with a serial the siphon never uses')
t:step(0.5, { litres = 5, capacity = 80 }, bed)
T.eq(#asked, 1, 'waits for the answer')
T.eq(t:answer(asked[1].serial, 5, 7), true, 'the truck answers')
T.eq(bed.litres, 8, 'the bed tank gives up what went in')
-- Only what is left in the bed tank goes across, then it stops empty.
bed.litres = 1.5
t:step(1, { litres = 7, capacity = 80 }, bed)
T.eq(asked[2].litres, 1.5, 'no more than the bed tank has')
t:answer(asked[2].serial, 7, 8.5)
T.near(bed.litres, 0, 1e-9, 'bed tank empty')
T.check(t:step(2, { litres = 8.5, capacity = 80 }, bed):find('empty'), 'stops when the bed tank is empty')
T.eq(t:active(), false, 'stopped')
-- The other way: from the truck into the bed tank, stopping when the bed tank is full.
local asked2, bed2 = {}, { litres = 799, capacity = 800 }
local t2 = P.new(function(litres, serial) asked2[#asked2 + 1] = { litres = litres, serial = serial }; return true end,
  function(d) bed2.litres = bed2.litres + d end)
t2:start('toBed', 0)
t2:step(0, { litres = 50, capacity = 80 }, bed2)
T.eq(asked2[1].litres, -1, 'takes only what the bed tank has room for')
t2:answer(asked2[1].serial, 50, 49)
T.eq(bed2.litres, 800, 'into the bed tank')
local line = t2:step(1, { litres = 49, capacity = 80 }, bed2)
T.check(line:find('bed tank is full') and line:find('1 L moved'), 'stops full and says how much moved')
-- A truck that never answers stops the pump.
local t3 = P.new(function() return true end, function() end)
t3:start('toTruck', 0); t3:step(0, { litres = 5, capacity = 80 }, { litres = 10, capacity = 800 })
T.check(t3:step(P.WAIT_SECONDS + 1, nil, nil):find('did not answer'), 'a silent truck stops it')

-- The command sent into the truck is valid Lua.
local commands = {}
local car = { getID = function() return 7 end, queueLuaCommand = function(_, cmd) commands[#commands + 1] = cmd end }
local b = B.new({ player = function() return car end })
T.eq(b:set(25), true, 'fills the bed tank'); T.eq(b:read(), true, 'asks its size')
T.check((loadstring or load)(commands[1]) ~= nil, 'the fill command is valid Lua')
T.check((loadstring or load)(commands[2]) ~= nil, 'the size command is valid Lua')
T.check(commands[1]:find('25.000', 1, true) and commands[1]:find('bedRead', 1, true), 'pours 25 L and reports')
T.eq(B.new({ player = function() return nil end }):set(1), false, 'no truck, nothing sent')

-- In the game: a new run puts fuel in the bed tank, the pump moves it, and the save keeps it.
local adapter = F.adapter(-31.0, 140.0)
local c, env = F.controller(adapter, { bed = F.bed() })
local function run(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
run(1); c:startRun(); adapter:put(R.START.latitude, R.START.longitude); run(1)
local core = require('tanker/core')
T.eq(env.fuel.sets[1].litres, core.START_FUEL_LITRES, 'a little fuel in the truck')
T.eq(env.bed.sets[1], core.START_BED_LITRES, 'and the rest in the bed tank')
T.check(env.bed.reads >= 1, 'asks the truck how big its bed tank is')
T.eq(c:view().bed.fitted, nil, 'size unknown until the truck says')
c:bedRead(7, 800)
c:fuelReading(7, 15, 80)
local v = c:view()
T.eq(v.bed.fitted, true, 'bed tank fitted'); T.eq(v.bed.litres, core.START_BED_LITRES, 'with its fuel')
T.eq(v.cargo.litres, core.START_BED_LITRES, 'shown on the wrist too'); T.eq(v.pumpAllowed, true, 'pump offered')
T.eq(c:startPump('toTruck'), true, 'pump into the truck')
run(0.5)
local change = env.fuel.changes[#env.fuel.changes]
T.eq(change.id, nil, 'the truck itself'); T.eq(change.litres, 2, 'two litres')
c:fuelChanged(7, change.serial, 15, 17, 80)
T.eq(c:view().fuel.litres, 17, 'the truck tank shows it'); T.eq(c:view().bed.litres, core.START_BED_LITRES - 2, 'the bed tank gave it')
T.eq(c:view().pumpStopAllowed, true, 'Stop offered'); T.eq(c:view().pumping, 'toTruck', 'and which way')
T.eq(c:stopPump(), true, 'stopped'); T.check(c.feedback:find('2 L moved'), 'says how much')
T.eq(env.bed.sets[#env.bed.sets], core.START_BED_LITRES - 2, 'the bed tank weight updated')
c:manualSave()
T.eq(c.profile.vehicle.bedLitres, core.START_BED_LITRES - 2, 'the save keeps the bed tank')
local c2, env2 = F.controller(F.adapter(-20, 130), { io = env.io, bed = F.bed(), vehicles = F.vehicles() })
for _ = 1, 2 do c2:tick(0.5) end
c2:goToSave(); c2.adapter:put(c.profile.resume.latitude, c.profile.resume.longitude)
for _ = 1, 2 do c2:tick(0.5) end
c2:vehicleSpawned(7)
T.eq(env2.bed.sets[1], core.START_BED_LITRES - 2, 'back at the save, the bed tank is refilled as saved')
c:bedRead(7, 0)
T.eq(c:view().bed.fitted, false, 'a truck without a bed tank says so'); T.eq(c:view().pumpAllowed, false, 'and no pump')
T.done('pump')
