-- Fuel. BeamNG already burns fuel as you drive (more with a heavy load); this reads the player
-- truck's tank and sets it, to put the tank back as it was saved when a session starts. Copied from
-- Earth Freight. It also adds or takes litres from any car's tank, for siphoning. The cars answer
-- through tanker_core.fuelReading, tanker_core.fuelSet and tanker_core.fuelChanged.
-- Every game call is guarded: a missing or changed one means no reading.
local M = {}

-- One-line settings. Tune these after testing in game.
M.READ_EVERY_SECONDS = 2
-- A reading older than this is not trusted for a refuel.
M.STALE_SECONDS = 10
-- Tanks within this many litres of full count as full.
M.FULL_MARGIN_LITRES = 0.5

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    byId = function(id) return be and be:getObjectByID(id) end,
  }
end

-- Runs inside the car: adds up its fuel tanks (energy storages with a volume and capacity in
-- litres, leaving out batteries, nitrous and air) into litres and capacity.
local TANKS = [[
local litres, capacity, tanks = 0, 0, {}
if energyStorage and energyStorage.getStorages then
  for _, s in pairs(energyStorage.getStorages() or {}) do
    if type(s) == 'table' and type(s.capacity) == 'number' and s.capacity > 0 and type(s.remainingVolume) == 'number'
        and s.energyType ~= 'electricEnergy' and s.energyType ~= 'n2o' and s.energyType ~= 'air' then
      litres, capacity = litres + s.remainingVolume, capacity + s.capacity
      tanks[#tanks + 1] = s
    end
  end
end
-- Sets every tank to the same share of full so the total is target, and returns the litres now
-- in them. A tank's remainingVolume only catches up on the car's next frame, so the litres set are
-- counted from the share given to each tank, not read back: reading them back right away saw no
-- change, and the bed tank pump then moved nothing into the bed tank.
local function setTanks(target)
  local ratio = capacity > 0 and target / capacity or 0
  local after = 0
  for _, s in ipairs(tanks) do
    if s.setRemainingRatio then s:setRemainingRatio(ratio) elseif s.setRemainingVolume then s:setRemainingVolume(ratio * s.capacity) end
    after = after + ratio * s.capacity
  end
  return after
end
]]
-- The outer string.format fills in the car's id; %% escapes the car's own format string.
local READ = TANKS .. [[
obj:queueGameEngineLua(string.format('if tanker_core then tanker_core.fuelReading(%%d, %%.3f, %%.3f) end', %d, litres, capacity))
]]
-- Sets every tank to the same share of full, so the total is the target, and reports before and
-- after. The outer string.format fills in the target, the car's id and the serial; %% escapes the
-- car's own format string.
local SET = TANKS .. [[
local before, target = litres, math.max(0, math.min(capacity, %.3f))
local after = setTanks(target)
obj:queueGameEngineLua(string.format('if tanker_core then tanker_core.fuelSet(%%d, %%d, %%.3f, %%.3f, %%.3f) end', %d, %d, before, after, capacity))
]]
-- Adds litres to the tanks (or takes them, when negative), never past empty or full, and reports
-- what was there before and after, so the caller knows how much really moved. The outer
-- string.format fills in the change, the car's id and the serial.
local CHANGE = TANKS .. [[
local before = litres
local after = setTanks(math.max(0, math.min(capacity, litres + %.3f)))
obj:queueGameEngineLua(string.format('if tanker_core then tanker_core.fuelChanged(%%d, %%d, %%.3f, %%.3f, %%.3f) end', %d, %d, before, after, capacity))
]]

-- How far this many litres goes, in km, at the rate measured so far (litres used over km driven).
-- nil until at least MIN_RANGE_KM has been driven with fuel going down, so a first guess is not shown.
M.MIN_RANGE_KM = 2
function M.range(litres, usedLitres, drivenKm)
  local finite = function(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
  if not finite(litres) or not finite(usedLitres) or not finite(drivenKm) then return nil end
  if litres < 0 or usedLitres <= 0 or drivenKm < M.MIN_RANGE_KM then return nil end
  return litres * drivenKm / usedLitres
end

function M.new(environment)
  local env = environment or defaults()
  local f = {}

  local function send(command, id)
    local okVehicle, vehicle
    if id ~= nil then okVehicle, vehicle = pcall(env.byId, id) else okVehicle, vehicle = pcall(env.player) end
    if not okVehicle or not vehicle then return false, 'vehicle_required' end
    local idOK, id = pcall(function() return vehicle:getID() end)
    if not idOK or type(id) ~= 'number' then return false, 'vehicle_required' end
    local ok, why = pcall(function() vehicle:queueLuaCommand(command(id)) end)
    if not ok then return false, 'fuel_failed', tostring(why) end
    return true
  end

  -- Asks the player car (or the car with this id) for its fuel. The answer comes back through
  -- fuelReading.
  function f:read(id)
    return send(function(carId) return string.format(READ, carId) end, id)
  end

  -- Sets the player car's fuel to this many litres in all. serial ties the answer, which comes
  -- back through fuelSet, to this request.
  function f:set(litres, serial)
    if type(litres) ~= 'number' or litres ~= litres or litres < 0 then return false, 'invalid_litres' end
    return send(function(id) return string.format(SET, litres, id, serial or 0) end)
  end

  -- Adds this many litres to a car's tank, or takes them when negative: the player's car, or the
  -- car with this id. serial ties the answer, which comes back through fuelChanged, to this request.
  function f:change(litres, serial, id)
    if type(litres) ~= 'number' or litres ~= litres or litres == math.huge or litres == -math.huge then
      return false, 'invalid_litres'
    end
    return send(function(carId) return string.format(CHANGE, litres, carId, serial or 0) end, id)
  end

  return f
end

return M
