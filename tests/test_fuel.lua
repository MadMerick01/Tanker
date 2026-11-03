local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local Fu = require('tanker/fuel')

-- Runs the car-side fuel code against a pretend tank that, like BeamNG's, only updates its
-- remainingVolume on the car's next frame.
local function car(litres, capacity)
  local tank = { capacity = capacity, remainingVolume = litres, energyType = 'gasoline' }
  function tank:setRemainingRatio(r) self.pending = r * self.capacity end
  local sent
  local veh = { getID = function() return 7 end, queueLuaCommand = function(_, cmd) sent = cmd end }
  local f = Fu.new({ player = function() return veh end, byId = function() return veh end })
  local function run()
    local reported
    local env = setmetatable({
      energyStorage = { getStorages = function() return { tank } end },
      obj = { queueGameEngineLua = function(_, s) reported = s end },
    }, { __index = _G })
    local chunk = assert(loadstring(sent))
    setfenv(chunk, env)
    chunk()
    tank.remainingVolume = tank.pending or tank.remainingVolume -- the next frame
    return reported
  end
  return f, run, tank
end

local f, run, tank = car(15, 80)
f:change(2, 1000001)
local line = run()
local before, after = line:match('fuelChanged%(7, 1000001, ([%d%.]+), ([%d%.]+)')
T.eq(tonumber(before), 15, 'before'); T.eq(tonumber(after), 17, 'after counts the 2 L pumped in, not the stale reading')
T.eq(tank.remainingVolume, 17, 'the tank really has them')
f:change(-20, 1000002)
before, after = run():match('fuelChanged%(7, 1000002, ([%d%.]+), ([%d%.]+)')
T.eq(tonumber(after), 0, 'never below empty')
f:set(40, 3)
T.check(run():find('fuelSet%(7, 3, [%d%.]+, 40%.000'), 'a set reports what it set')
T.done('fuel')
