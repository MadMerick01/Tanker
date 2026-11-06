local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local D = require('tanker/drone')

-- A pretend game: the player's truck, a straight road along y = 0, x from 0 to 1000, 4 m half
-- width, and what was sent to every car.
local v3 = function(x, y, z) return { x = x, y = y, z = z } end
local truck = { pos = v3(100, 0, 0), commands = {} }
function truck:getPosition() return self.pos end
function truck:getDirectionVector() return v3(1, 0, 0) end
function truck:queueLuaCommand(cmd) self.commands[#self.commands + 1] = cmd end
local all = {}
local roll = 0.9
local env = {
  player = function() return truck end,
  vec3 = v3,
  map = function() return {
    findClosestRoad = function() return 'a', 'b', 0 end,
    getMap = function() return { nodes = { a = { pos = v3(0, 0, 0), radius = 4 }, b = { pos = v3(1000, 0, 0), radius = 4 } } } end,
  } end,
  allObjects = function(cmd) all[#all + 1] = cmd end,
  random = function() return roll end,
}
local d = D.new(env)

-- On the road: in its middle, and at its edge; off it beyond.
T.eq(d:onRoad(), true, 'in the middle of the road')
truck.pos = v3(100, 5, 0)
T.eq(d:onRoad(), true, 'at its edge')
truck.pos = v3(100, 4 + D.ROAD_MARGIN + 1, 0)
T.eq(d:onRoad(), false, 'off it')
T.eq(D.new({ player = function() return truck end, map = function() return nil end, vec3 = v3 }):onRoad(), false,
  'no road map, never on a road')

-- Crossing a road is safe: nothing in the first few seconds.
local function run(from, to, road)
  local lines = {}
  for t = from, to, 0.5 do
    local l = d:step(t, road)
    if l then lines[#lines + 1] = l end
  end
  return lines
end
truck.pos = v3(100, 0, 0)
local lines = run(0, D.GRACE_SECONDS - 0.5, true)
T.eq(#lines, 0, 'nothing said while crossing'); T.eq(d:view(D.GRACE_SECONDS - 0.5).state, nil, 'and no countdown')
lines = run(D.GRACE_SECONDS, D.GRACE_SECONDS, true)
T.eq(lines[1], D.LINES.watched, 'stay on it and you are warned')
local v = d:view(D.GRACE_SECONDS)
T.eq(v.state, 'WATCHED', 'the countdown shows'); T.eq(v.seconds, D.ROAD_SECONDS - D.GRACE_SECONDS, 'with the seconds left')
lines = run(D.GRACE_SECONDS + 0.5, D.ROAD_SECONDS - D.INBOUND_SECONDS, true)
T.eq(lines[#lines], D.LINES.inbound, 'then the drone is heard coming'); T.eq(d:view(D.ROAD_SECONDS - D.INBOUND_SECONDS).state, 'INBOUND', 'inbound')
lines = run(D.ROAD_SECONDS - D.INBOUND_SECONDS + 0.5, D.ROAD_SECONDS, true)
T.eq(lines[#lines], D.LINES.hit, 'after 30 s on the road it hits you')
T.eq(d.strikes, 1, 'counted, for the blast sound')
T.check(all[1]:find('obj:setPlanets({100.000000, -2.500000, -0.500000, 5, ', 1, true) ~= nil, 'a blast beside your truck, at the ground')
T.eq(truck.commands[1], nil, 'no tyre burst this time')
d:step(D.ROAD_SECONDS + D.BLAST_SECONDS, true)
T.eq(all[#all], 'obj:setPlanets({})', 'the blast is over in a moment')
-- Still on the road: the next one comes sooner, without another warning.
lines = run(D.ROAD_SECONDS + 0.5, D.ROAD_SECONDS + D.AGAIN_SECONDS, true)
T.eq(lines[#lines], D.LINES.hit, 'stay on the road and another hits 20 s later')
T.eq(lines[1], D.LINES.inbound, 'heard coming, with no second warning')
T.eq(d.strikes, 2, 'two strikes')

-- Get off the road while it is coming: it misses.
local t0 = 100
d:clear()
roll = 0.1
run(t0, t0 + D.ROAD_SECONDS - D.INBOUND_SECONDS, true)
lines = run(t0 + D.ROAD_SECONDS - D.INBOUND_SECONDS + 0.5, t0 + D.ROAD_SECONDS, false)
T.eq(lines[#lines], D.LINES.missed, 'off the road when it arrives, it misses'); T.eq(d.misses, 1, 'counted')
T.eq(d:view(t0 + D.ROAD_SECONDS).state, nil, 'and the countdown is gone')

-- Off the road a while: the AI loses you and the count starts again.
t0 = 200
run(t0, t0 + 15, true)
lines = run(t0 + 15.5, t0 + 15.5 + D.CLEAR_SECONDS, false)
T.eq(lines[#lines], D.LINES.lost, 'off the road a while, it loses you')
T.check(d:view(t0 + 21).offRoad == nil and d:view(t0 + 21).state == nil, 'no countdown')
lines = run(t0 + 21, t0 + 21 + D.ROAD_SECONDS - D.INBOUND_SECONDS - 1, true)
T.check(not (lines[#lines] == D.LINES.inbound), 'back on a road, the full 30 s again')
-- A short trip off the road doesn't reset it.
d:clear()
t0 = 400
run(t0, t0 + 20, true)
run(t0 + 20.5, t0 + 22, false)
T.eq(d:view(t0 + 22).offRoad, true, 'the banner says it is losing you')
lines = run(t0 + 22.5, t0 + D.ROAD_SECONDS, true)
T.eq(lines[#lines], D.LINES.hit, 'two seconds off the road is not enough')
T.check(truck.commands[#truck.commands] == 'beamstate.deflateRandomTire()', 'and this blast burst a tyre')

-- In the game: only while the run is on the road, and the blast ends on time between samples.
local adapter = F.adapter(-31.0, 140.0)
local onRoad = true
local fake = { strikes = 0, misses = 0, steps = 0, cleared = 0 }
function fake:onRoad() return onRoad end
function fake:step(clock, road) self.steps = self.steps + 1; self.lastRoad = road; if self.say then local s = self.say; self.say = nil; return s end end
function fake:view() return { state = 'WATCHED', seconds = 12, strikes = 0, misses = 0 } end
function fake:clear() self.cleared = self.cleared + 1; self.since = nil end
function fake:blastOff() self.blastUntil = nil; self.off = true end
local c = F.controller(adapter, { drone = fake })
local function tick(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
tick(1)
T.eq(fake.steps, 0, 'not before the run')
c:startRun(); adapter:put(require('tanker/route').START.latitude, require('tanker/route').START.longitude); tick(1)
T.check(fake.steps > 0, 'watching on the road'); T.eq(fake.lastRoad, true, 'told you are on a road')
T.eq(c:view().drone.seconds, 12, 'the HUD gets the countdown')
fake.say = D.LINES.hit
tick(0.5)
T.eq(c.feedback, D.LINES.hit, 'and the line')
fake.blastUntil = c.clock + 0.1
c:tick(0.2)
T.eq(fake.off, true, 'the blast is ended between samples')
c:shutdown()
T.check(fake.cleared >= 1, 'cleared when Tanker goes')

T.done('drone')
