local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local Pr = require('tanker/pricing')
local Pa = require('tanker/parts')
local R = require('tanker/route')

T.eq(Pr.litresFor(Pr.FUEL_PRICE * 3), 3, 'dollars to litres'); T.eq(Pr.worth(2), 2 * Pr.FUEL_PRICE, 'litres to dollars')
T.eq(Pr.litresFor(-5), 0, 'nothing for nothing')

-- A pretend truck: the test changes its parts as the parts menu would.
local function fakeParts()
  local p = { snap = { id = 7, model = 'pickup', config = { model = 'pickup', partsTree = {} },
    parts = { engine = 'i6', tyres = 'old' }, values = { i6 = 3000, old = 100, new = 600 }, names = { i6 = 'i6 engine', old = 'Old tyres', new = 'New tyres' } },
    damage = 0, restores = 0 }
  function p:parts() local s = Pa.copy(self.snap); return s end
  function p:inspect() return { id = 7, damage = self.damage } end
  function p:restore(config, model) self.restores = self.restores + 1; self.restoredModel = model; return true end
  return p
end

local adapter = F.adapter(-31.0, 140.0)
local parts = fakeParts()
local c, env = F.controller(adapter, { parts = parts, bed = F.bed(), vehicles = F.vehicles() })
local function run(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
run(1); c:startRun(); adapter:put(R.START.latitude, R.START.longitude); run(1)
c:vehicleSpawned(7) -- the starter truck arrives
c:bedRead(7, 800); c:fuelReading(7, 15, 80)
run(0.5)
T.eq(c.ownedParts and c.ownedParts.model, 'pickup', 'the starter truck is yours')
local v = c:view()
T.near(v.fuelWorth, (15 + 25) * Pr.FUEL_PRICE, 1e-9, 'the HUD shows what your fuel is worth')
T.eq(v.buyPartsAllowed, true, 'Buy parts offered'); T.eq(v.bill, nil, 'no bill yet')

-- New tyres in the parts menu: the truck respawns, its fuel goes back, and a bill comes up.
parts.snap.parts.tyres = 'new'
env.fuel.sets = {}
c:vehicleSpawned(7)
c:fuelReading(7, 80, 80) -- a respawned truck reads full
T.eq(c.reading.litres, 15, 'a full tank after a respawn is not believed')
run(0.5)
T.eq(env.fuel.sets[1] and env.fuel.sets[1].litres, 15, 'the fuel it had is put back')
v = c:view()
local expected = 600 - math.floor(100 * Pr.PART_TRADE_IN_SHARE + 0.5)
T.eq(v.bill.cost, expected, 'new tyres less the old ones traded in')
T.near(v.bill.litres, expected / Pr.FUEL_PRICE, 1e-9, 'billed in litres'); T.eq(v.payPartsAllowed, true, 'you carry enough')
T.eq(#v.bill.lines, 2, 'one line each')
-- Paying on the bill box takes the bed tank first, then closes the parts menu.
local states = {}
c.trigger = function(event, data) if event == 'ChangeState' then states[#states + 1] = data end end
T.eq(c:payPartsBill(), true, 'paid')
T.eq(states[1] and states[1].state, 'play', 'paying on the bill box closes the parts menu, back to the truck')
local billL = expected / Pr.FUEL_PRICE
T.near(c.bedLitres, math.max(0, 25 - billL), 1e-9, 'from the bed tank first')
T.near(c.reading.litres, 15 - math.max(0, billL - 25), 1e-9, 'then the truck')
T.eq(c:view().bill, nil, 'bill gone'); T.eq(c.ownedParts.parts.tyres, 'new', 'the new tyres are yours')
T.check(c.feedback:find('Paid'), 'says so')
-- A bill bigger than the bed tank takes the rest from the truck.
parts.snap.parts.engine = ''
parts.snap.values.v8 = 9000; parts.snap.names.v8 = 'V8'; parts.snap.parts.engine = 'v8'
c:vehicleSpawned(7); run(0.5)
T.eq(c:view().payPartsAllowed, false, 'a V8 is more fuel than you carry')
T.check(c:view().bill.short > 0, 'and says how short'); T.eq(c:payParts(), false, 'cannot pay')
T.eq(c:payPartsBill(), false, 'cannot pay on the bill box either'); T.eq(#states, 1, 'and the parts menu stays open')
-- Undo puts the paid parts back.
T.eq(c:undoParts(false), true, 'undo'); T.eq(parts.restores, 1, 'the truck respawns with the paid parts')
parts.snap.parts.engine = 'i6'
c:vehicleSpawned(7); run(0.5)
T.eq(c:view().bill, nil, 'nothing to pay')
-- Driving off without paying puts them back too.
parts.snap.parts.tyres = 'old'
c:vehicleSpawned(7); run(0.5)
T.check(c:view().bill ~= nil, 'a bill for the change')
adapter:put(R.START.latitude + 0.001, R.START.longitude); run(0.5)
T.eq(parts.restores, 2, 'driving off unpaid undoes it'); T.check(c.feedback:find('drove off'), 'and says so')
-- Damage the change mended is on the bill.
parts.snap.parts.tyres = 'new'
parts.damage = 2000; run(0.5)
parts.snap.parts.tyres = 'old'
c:vehicleSpawned(7); run(0.5)
T.check(c:view().bill.lines[#c:view().bill.lines].label:find('Repair'), 'the repair is billed')
c:undoParts(false); parts.snap.parts.tyres = 'new'; parts.damage = 0; c:vehicleSpawned(7); run(0.5)
-- Another vehicle from the vehicle selector is sent back for now.
parts.snap.model = 'semi'
c:vehicleSpawned(7); run(0.5)
T.eq(parts.restoredModel, 'pickup', 'your truck comes back'); T.check(c.feedback:find('later build'), 'and says why')
parts.snap.model = 'pickup'
-- The save keeps the parts, and going back to it brings the truck with them.
c:vehicleSpawned(7); run(0.5)
c:manualSave()
T.eq(c.profile.vehicle.config.model, 'pickup', 'the save keeps the parts')
local saved = c.profile
local c2, env2 = F.controller(F.adapter(-20, 130), { io = env.io, parts = fakeParts(), vehicles = F.vehicles() })
local spawnedWith
env2.vehicles.spawnStarter = function(self, config, model) spawnedWith = { config = config, model = model }; return true end
for _ = 1, 2 do c2:tick(0.5) end
c2:goToSave(); c2.adapter:put(saved.resume.latitude, saved.resume.longitude)
for _ = 1, 2 do c2:tick(0.5) end
T.eq(spawnedWith and spawnedWith.model, 'pickup', 'back at the save, the saved truck')
T.check(spawnedWith and type(spawnedWith.config) == 'table', 'with its parts')

-- The game side, against pretend game calls.
local tree = { chosenPartName = 'pickup', path = '/', children = { engine = { chosenPartName = 'i6', path = '/engine' } } }
local game = Pa.new({
  vehicle = function() return { getID = function() return 7 end } end,
  objects = function() return { [7] = { damage = 120 } } end,
  manager = function() return { getVehicleData = function() return { config = { model = 'pickup', partsTree = tree }, ioCtx = {} } end } end,
  jbeam = function() return { getPart = function(_, name) return { information = { value = name == 'i6' and 3000 or nil, name = name } } end } end,
  vehicles = function() return { replaceVehicle = function() end } end,
})
local snap = game:parts()
T.eq(snap.parts['/engine'], 'i6', 'reads the fitted parts'); T.eq(snap.values.i6, 3000, 'and their prices')
T.eq(game:inspect().damage, 120, 'reads the damage')
T.eq(game:restore(snap.config, 'pickup'), true, 'puts parts back')
T.eq(Pa.new({}):parts(), nil, 'no game, no parts')
T.done('workshop')
