local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local R = require('tanker/route')
local V = require('tanker/vehicle')
local core = require('tanker/core')

local function run(c, seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end

-- Start a new game: from the road it heads back to the start, and the new run replaces the save.
local adapter = F.adapter(-31.0, 140.0)
local vehicles = F.vehicles()
function vehicles:describe() return { model = 'pickup', name = 'D15', brand = 'Gavril', value = 32300, preview = '/x.jpg' } end
local c, env = F.controller(adapter, { vehicles = vehicles })
run(c, 1)
T.eq(c:view().newGameAllowed, false, 'nothing to start over before a run')
T.eq(c:newGame(), false, 'so no new game')
c:startRun(); adapter:put(R.START.latitude, R.START.longitude); run(c, 1)
c:vehicleSpawned(7); run(c, 0.5)
T.eq(c.state, 'RUNNING', 'on the road')
local v = c:view()
T.eq(v.truck and v.truck.name, 'D15', 'your truck is on the start page'); T.eq(v.truck.brand, 'Gavril', 'with its maker')
adapter:put(R.START.latitude + 0.002, R.START.longitude); run(c, 0.5)
c:manualSave()
local firstGeneration = c.profile.generation
T.check(c.profile.run.drivenKm > 0, 'some km driven')
T.eq(v.newGameAllowed, true, 'a new game is offered on the road')
adapter.refuse = 'teleport_refused'
T.eq(c:newGame(), false, 'a failed teleport keeps the run')
T.eq(c.state, 'RUNNING', 'still on the road'); T.check(c.profile ~= nil, 'with its save')
adapter.refuse = nil
T.eq(c:newGame(), true, 'new game')
T.eq(c.state, 'TO_START', 'heading back to the start')
T.eq(adapter.teleports[#adapter.teleports].name, R.START_NAME, 'to Kulgera')
adapter:put(R.START.latitude, R.START.longitude); run(c, 1)
c:vehicleSpawned(7); run(c, 0.5)
T.eq(c.state, 'RUNNING', 'the new run is on')
T.eq(c.profile.run.drivenKm, 0, 'from nought km')
T.check(c.profile.generation > firstGeneration, 'saved over the old run')
T.eq(env.fuel.sets[#env.fuel.sets].litres, core.START_FUEL_LITRES, 'with a new run\'s fuel')
-- From the start page while away from the save.
local c2 = F.controller(F.adapter(-20, 130), { io = env.io, vehicles = F.vehicles() })
run(c2, 1)
T.eq(c2.state, 'AWAY', 'away from the save')
T.eq(c2:view().newGameAllowed, true, 'new game offered')
T.eq(c2:newGame(), true, 'and taken'); T.eq(c2.state, 'TO_START', 'heading for the start')

-- The game side: the truck's card from the game's vehicle info.
local function game(file, config, model)
  return V.new({
    player = function() return { getID = function() return 7 end, getJBeamFilename = function() return 'pickup' end } end,
    manager = function() return { getVehicleData = function() return { config = { partConfigFilename = file } } end } end,
    vehicles = function() return {
      getConfig = function(_, key) return config and key == 'd15_longbed' and config or nil end,
      getModel = function() return model end,
    } end,
  })
end
local card = game('vehicles/pickup/d15_longbed.pc', { Name = 'D15', Brand = 'Gavril', Configuration = 'Longbed', preview = '/vehicles/pickup/d15_longbed.jpg', Value = 20000 }):describe()
T.eq(card.name, 'D15', 'name'); T.eq(card.preview, '/vehicles/pickup/d15_longbed.jpg', 'picture'); T.eq(card.value, 20000, 'value')
card = game(nil, nil, { model = { Name = 'D-Series', Brand = 'Gavril' } }):describe()
T.eq(card.name, 'D-Series', 'the model name when the config is unknown')
T.eq(card.preview, V.STARTER_PREVIEW, 'the starter truck\'s picture for a pickup with bought parts')
T.eq(V.new({ player = function() return nil end }):describe(), nil, 'no vehicle, no card')
T.done('startpage')
