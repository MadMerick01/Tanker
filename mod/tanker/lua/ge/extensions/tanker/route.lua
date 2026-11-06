-- The run: where it starts and where it is going. Pure maths; no game globals.
local location = require('tanker/location')
local M = {}

-- One-line settings. Tune these after testing in game.
-- By Kati Thanda-Lake Eyre, outback South Australia: Rowan's pick for where the run starts
-- (6 Nov), about 680 km south-east of Pine Gap in a straight line. It used to be Kulgera
-- Roadhouse, just north of the SA border. config.json's start moves it.
M.START = { latitude = -28.8807093, longitude = 137.6024985 }
M.START_NAME = 'Lake Eyre'
-- Pine Gap, outside Alice Springs. Everything about it in the game is fiction.
M.GOAL = { latitude = -23.7990, longitude = 133.7370 }
M.GOAL_NAME = 'Pine Gap'
-- Roads are longer than the straight line. 1.18 puts Lake Eyre to Pine Gap at about 800 km;
-- the real drive up the Oodnadatta Track and the Stuart Highway is probably a bit longer.
M.ROAD_FACTOR = 1.18
-- A new run starts once the truck is this close to the start, after the teleport there.
M.START_RADIUS_METRES = 5000
-- Within this distance of Pine Gap the run's first goal is reached.
M.GOAL_RADIUS_METRES = 2000

-- How far is left to Pine Gap from here: the straight line and the road estimate in km, which way
-- it is (degrees and letters), and whether it has been reached. nil for an invalid position.
function M.toGoal(here)
  local metres = location.distance(here, M.GOAL)
  if not metres then return nil end
  local bearing = location.bearing(here, M.GOAL)
  return {
    km = metres / 1000, roadKm = metres * M.ROAD_FACTOR / 1000, bearing = bearing,
    letters = location.compassLetters(bearing), reached = metres <= M.GOAL_RADIUS_METRES,
  }
end

-- How much of the trip is done, from 0 to 1, by road estimate from the start to here.
function M.progress(here, start)
  local total = location.distance(start or M.START, M.GOAL)
  local left = location.distance(here, M.GOAL)
  if not total or not left or total <= 0 then return nil end
  return math.max(0, math.min(1, 1 - left / total))
end

function M.atStart(here, start)
  local metres = location.distance(here, start or M.START)
  return metres ~= nil and metres <= M.START_RADIUS_METRES
end

return M
