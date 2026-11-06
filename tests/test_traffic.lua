local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local TP = require('tanker/trafficPool')
local HC = require('tanker/hoonCar')
local TM = require('tanker/tankerMob')

-- Pretend game: cars by id with a model and position, and BeamNG's traffic table.
local v3 = function(x, y, z) return { x = x, y = y, z = z } end
local cars, trafficTable, setups, removed = {}, {}, {}, {}
local function gameCar(id, model, pos)
  local g = { id = id, model = model, pos = pos, active = 1, commands = {} }
  function g:getID() return self.id end
  function g:getJBeamFilename() return self.model end
  function g:getPosition() return self.pos end
  function g:getDirectionVector() return v3(0, 1, 0) end
  function g:getVelocity() return v3(0, 0, 0) end
  function g:setActive(on) self.active = on end
  function g:setPositionRotation(x, y, z) self.pos = v3(x, y, z) end
  function g:queueLuaCommand(cmd) self.commands[#self.commands + 1] = cmd end
  function g:delete() cars[self.id] = nil end
  cars[id] = g
  return g
end
local nextId = 200
local game = {
  setupTraffic = function(amount, police, opts)
    setups[#setups + 1] = { amount = amount, police = police, opts = opts }
    -- BeamNG clears the traffic it has, then loads the group over the next frames.
    for id in pairs(trafficTable) do if trafficTable[id].isAi then cars[id] = nil; trafficTable[id] = nil end end
    return true
  end,
  getTrafficData = function() return trafficTable end,
  removeTraffic = function(id) removed[#removed + 1] = id; trafficTable[id] = nil end,
}
local function loadGroup(group)
  for i, entry in ipairs(group) do
    nextId = nextId + 1
    gameCar(nextId, entry.model, v3(0, i * 100, 0))
    trafficTable[nextId] = { isAi = true }
  end
end
local env = { traffic = function() return game end, byId = function(id) return cars[id] end }

-- Normal traffic is running when the run starts.
local player = gameCar(7, 'pickup', v3(0, 0, 10))
trafficTable[7] = { isAi = false }
gameCar(50, 'covet', v3(0, 30, 0)); trafficTable[50] = { isAi = true }

local group = TP.group()
T.eq(#group, 7, 'the pool holds 5 HoonOld1s and 2 TankerMobs')
T.eq(group[1].model, 'barstow', 'a Barstow'); T.eq(group[1].config, 'hoonold1', 'Hoons are HoonOld1')
T.eq(group[#group].model, 'us_semi', 'a semi'); T.eq(group[#group].config, 'tankermob', 'tankers are TankerMobs')

local pool = TP.new(env)
local line = pool:step(0)
T.eq(#setups, 1, 'traffic is set up once the run is on the road')
T.eq(setups[1].amount, 7, 'with every pooled car'); T.eq(setups[1].police, 0, 'and no police')
T.eq(setups[1].opts.vehGroup[1].config, 'hoonold1', 'from Tanker\'s own group only')
T.eq(setups[1].opts.activeAmount, TP.ACTIVE, 'only a few shown at once, the rest hidden')
T.eq(cars[50], nil, 'normal traffic is cleared'); T.check(cars[7] ~= nil, 'never the player')
T.check(line ~= nil, 'and logged')
T.eq(pool:loading(), true, 'loading')
T.eq(pool:step(1), nil, 'nothing to say while it loads')
loadGroup(setups[1].opts.vehGroup)
pool:step(2)
T.eq(pool.state, 'READY', 'ready once Tanker\'s cars are in traffic')
T.eq(pool:loading(), false, 'done loading')

-- No normal traffic: nothing is set up again.
pool:step(2 + TP.CHECK_SECONDS)
T.eq(#setups, 1, 'Tanker\'s own traffic is left alone')

-- A Hoon's car comes out of the pool, the HoonOld1 furthest from you.
local hc = HC.new({ player = function() return player end, byId = function(id) return cars[id] end, vec3 = v3,
  vehicles = function() return {
    getModel = function(name) return name == 'barstow' and { model = 'barstow' } or {} end,
    spawnNewVehicle = function() error('should come from the pool') end,
  } end }, pool)
local id, model = hc:load()
T.eq(model, 'barstow', 'a Barstow')
T.eq(id, 205, 'the HoonOld1 furthest from you, taken from the pool')
T.eq(removed[1], 205, 'out of traffic'); T.eq(trafficTable[205], nil, 'gone from traffic')
T.eq(cars[205].active, 0, 'and switched off until it is sent')
for _ = 1, 4 do T.check(hc:load() ~= nil, 'every Hoon') end
local spawned = 0
local hc2 = HC.new({ player = function() return player end, byId = function(i) return cars[i] end, vec3 = v3,
  vehicles = function() return {
    getModel = function(name) return name == 'barstow' and { model = 'barstow' } or {} end,
    spawnNewVehicle = function(m, opts) spawned = spawned + 1; return gameCar(300 + spawned, m, opts.pos) end,
  } end }, pool)
id = hc2:load()
T.eq(id, 301, 'with the pool out of HoonOld1s, one is loaded instead'); T.eq(spawned, 1, 'once')

-- The TankerMob comes out of the pool too.
local mob = TM.new(hc2, { byId = function(i) return cars[i] end, vec3 = v3, quatFromDir = function() return {} end,
  spawn = function() return nil end,
  vehicles = function() return { spawnNewVehicle = function() error('should come from the pool') end } end })
T.eq(mob:spawn(), true, 'a TankerMob is put ahead of you')
T.eq(cars[mob.id].model, 'us_semi', 'a TankerMob from the pool')
T.eq(trafficTable[mob.id], nil, 'taken out of traffic'); T.eq(cars[mob.id].active, 1, 'and switched on')

-- Normal traffic switched on later (from the game's menu) is replaced by Tanker's again.
gameCar(60, 'covet', v3(0, 50, 0)); trafficTable[60] = { isAi = true }
pool:step(3)
T.eq(#setups, 1, 'not straight away')
line = pool:step(2 + 2 * TP.CHECK_SECONDS)
T.eq(#setups, 2, 'within a check, traffic is set up again'); T.eq(cars[60], nil, 'the normal car is gone')
T.check(line:find('replacing 1', 1, true) ~= nil, 'and logged')

-- No traffic in the game: no pool, no error, Hoons load their own.
local none = TP.new({ traffic = function() return nil end, byId = function() return nil end })
T.check(none:step(0) ~= nil, 'says so once')
T.eq(none:step(1), nil, 'then stays quiet'); T.eq(none:loading(), false, 'and never holds a Hoon up')
T.eq(none:take('barstow', 0, 0), nil, 'nothing to take')

-- Traffic that never loads holds Hoons up only so long.
local slow = TP.new({ traffic = function() return { setupTraffic = function() return true end, getTrafficData = function() return {} end } end,
  byId = function() return nil end })
slow:step(0)
T.eq(slow:loading(), true, 'waiting')
slow:step(TP.WAIT_SECONDS)
T.eq(slow:loading(), false, 'after the wait, Hoons load their own car')

T.done('traffic')
