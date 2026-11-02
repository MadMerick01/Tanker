local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local H = require('tanker/hoons')
local R = require('tanker/route')

-- A pretend Hoon car: the test moves the player and the Hoon about.
local function fakeCar()
  local car = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }, hoon = nil, roads = true,
    hidden = 0, attacks = {}, calmed = 0, removed = 0, loads = 0 }
  function car:player() return self.me end
  function car:load() self.loads = self.loads + 1; if self.refuse then return nil, self.refuse end return 99, 'hotrod' end
  function car:road(x, y, z)
    if not self.roads then return nil end
    return { x = x, y = y, z = z, metres = self.offRoad or 0 }
  end
  function car:solid(x, y) return not (self.holeBehind and y < self.me.y) end
  function car:attack(id, x, y, z, target)
    self.attacks[#self.attacks + 1] = { id = id, x = x, y = y, target = target }
    self.hoon = { x = x, y = y, z = z, speed = 0 }
    return true
  end
  function car:hide() self.hidden = self.hidden + 1; self.hoon = nil end
  function car:calm() self.calmed = self.calmed + 1 end
  function car:state() return self.hoon end
  function car:remove() self.removed = self.removed + 1 end
  return car
end
local function steps(h, from, seconds, km)
  local line
  for t = from, from + seconds, 0.5 do line = h:step(t, km) or line end
  return line
end

local car = fakeCar()
local h = H.new(car, function(lo) return lo end)
T.eq(h:load(10), nil, 'loads the car'); T.eq(h.state, 'HIDDEN', 'and hides it')
T.eq(h:load(10), nil, 'only once'); T.eq(car.loads, 1, 'one car')
T.eq(h:step(0, 12), nil, 'no Hoon before the first km')
T.eq(h:step(0, 13), H.LINES.coming, 'a Hoon comes after the first km')
T.eq(car.attacks[1].y, -H.PLACE_METRES, 'put on the road 250 m behind you'); T.eq(car.attacks[1].target, 7, 'hunting you')
T.eq(h:hunting(), true, 'hunting')
car.hoon.speed = 25; car.hoon.y = -100
h:step(1, 13)
T.eq(h:distances()[1], 100, 'its distance lights the threat')
-- Stuck for long enough: it is down, calmed, and stays as a wreck until you leave.
car.hoon.speed = 0
T.eq(steps(h, 2, H.DOWN_SECONDS, 13), H.LINES.down, 'a stuck Hoon is down')
T.eq(car.calmed, 1, 'its AI stopped'); T.eq(h:distances(), nil, 'a wreck is no threat'); T.eq(h:outId(), 99, 'still out')
h:step(30, 13)
T.eq(h.state, 'DOWN', 'waits while you are near')
car.me.y = 1000
h:step(31, 14)
T.eq(h.state, 'HIDDEN', 'put away once you leave'); T.eq(car.hidden, 1, 'hidden')
T.eq(h.nextKm, 14 + H.GAP_MIN_KM, 'the next comes a few km on')

-- Getting away: far from you for long enough.
T.eq(h:step(40, 20), H.LINES.coming, 'the next Hoon')
car.hoon.speed = 30; car.hoon.y = car.me.y - 2000
T.eq(steps(h, 41, H.ESCAPE_SECONDS, 20), H.LINES.escaped, 'outrun it and it gives up')
T.eq(h.state, 'HIDDEN', 'back in hiding')

-- No solid road behind: it comes from ahead instead.
car.holeBehind = true
h:putAway(20)
T.eq(h:step(60, 40), H.LINES.ahead, 'comes from ahead when the road behind is not solid')
T.eq(car.attacks[#car.attacks].y, car.me.y + H.PLACE_METRES, 'put on the road ahead')
car.holeBehind = nil
h:putAway(20)

-- No Hoon while stopped, off road, or with no road behind; it tries again later.
car.me.speed = 0
T.eq(h:step(100, 40), nil, 'not while you are stopped')
car.me.speed = 20; car.offRoad = H.ROAD_METRES + 50
T.eq(h:step(101, 40), nil, 'not far off road'); T.eq(h.state, 'HIDDEN', 'still hiding')
car.offRoad = nil
T.eq(h:step(105, 40), nil, 'waits before trying again')
T.eq(h:step(101 + H.RETRY_SECONDS + 1, 40), H.LINES.coming, 'tries again')
car.hoon = nil
T.eq(h:step(200, 40), H.LINES.gone, 'a car that vanished is handled'); T.eq(h.state, 'HIDDEN', 'and waits for the next')
h:remove()
T.eq(car.removed, 1, 'removed when Tanker goes'); T.eq(h.state, 'NONE', 'ready to load again')

-- A car the game won't give means no Hoons, not an error.
local car2 = fakeCar(); car2.refuse = 'no_hoon_model'
local h2 = H.new(car2)
T.eq(h2:load(0), 'no_hoon_model', 'says why'); T.eq(h2.state, 'UNAVAILABLE', 'no Hoons')
T.eq(h2:step(0, 100), nil, 'and nothing happens')

-- In the game: the Hoon is loaded on the road, lights the threat and blocks saving.
local adapter = F.adapter(-31.0, 140.0)
local car3 = fakeCar()
local c, env = F.controller(adapter, { hoonCar = car3, random = function(lo) return lo end })
local function run(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
run(1)
T.eq(car3.loads, 0, 'no Hoon before the run')
T.eq(c:sendHoon(), false, 'none to send before the run')
c:startRun(); adapter:put(R.START.latitude, R.START.longitude); run(1)
T.eq(car3.loads, 1, 'the Hoon is loaded once on the road')
T.eq(c:view().hoonTestAllowed, true, 'Send a Hoon offered for testing')
T.eq(c:sendHoon(), true, 'sent'); T.eq(c.feedback, H.LINES.coming, 'and says so')
car3.hoon.y, car3.hoon.speed = -80, 20
run(0.5)
T.eq(c:view().threat, 'red', 'a Hoon on you shows red'); T.eq(c:view().saveAllowed, false, 'no saving')
T.eq(c:view().hoon.state, 'HUNTING', 'the Road tab says so'); T.eq(c:view().hoon.metres, 80, 'with how far')
c:shutdown()
T.eq(car3.removed, 1, 'the Hoon car goes with Tanker')

-- The game's side, against pretend game calls: loads, hides, finds the road and attacks.
local HC = require('tanker/hoonCar')
local v3 = function(x, y, z) return { x = x, y = y, z = z } end
local cars, spawned = {}, {}
local function gameCar(id, pos)
  local g = { id = id, pos = pos, active = 1, commands = {} }
  function g:getID() return self.id end
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
local player = gameCar(7, v3(0, 0, 10))
local game = HC.new({
  player = function() return player end, byId = function(id) return cars[id] end, vec3 = v3,
  quatFromDir = function() return { 0, 0, 0, 1 } end, spawn = function() return nil end,
  ground = function(x, y, z) if y < -395 then return z + 1 end end,
  vehicles = function() return {
    getModel = function(name) return name == 'burnside' and { model = 'burnside' } or {} end,
    spawnNewVehicle = function(model, opts) spawned[#spawned + 1] = { model = model, opts = opts }; return gameCar(50, opts.pos) end,
  } end,
  map = function() return {
    findClosestRoad = function() return 'a', 'b', 3 end,
    getMap = function() return { nodes = { a = { pos = v3(0, -400, 5) }, b = { pos = v3(0, -380, 5) } } } end,
  } end,
})
local id, model = game:load()
T.eq(id, 50, 'the Hoon car is loaded'); T.eq(model, 'burnside', 'the first model the game has')
T.eq(spawned[1].opts.autoEnterVehicle, false, 'without moving you into it')
T.eq(cars[50].active, 0, 'and switched off at once')
local road = game:road(3, -390, 5)
T.near(road.y, -390, 1e-9, 'the nearest point on the road'); T.near(road.metres, 3, 1e-9, 'and how far')
T.eq(game:solid(0, -390, 5), false, 'no ground, not solid'); T.eq(game:solid(0, -400, 5), true, 'ground under the road is solid')
T.eq(game:attack(50, road.x, road.y, road.z, 7), true, 'attacks')
T.eq(cars[50].active, 1, 'switched on'); T.near(cars[50].pos.y, -390, 1e-9, 'put on the road')
T.check(cars[50].commands[#cars[50].commands]:find("setTargetObjectID, 7", 1, true), 'hunting you')
T.check((loadstring or load)(cars[50].commands[#cars[50].commands]) ~= nil, 'the AI command is valid Lua')
T.eq(game:state(50).speed, 0, 'reads the Hoon')
game:hide(50)
T.eq(cars[50].active, 0, 'hidden again'); T.eq(cars[50].pos.z, 10 + HC.HIDE_LIFT, 'up out of the way')
game:remove(50)
T.eq(game:state(50), nil, 'removed')
local bare = HC.new({})
T.eq(bare:load(), nil, 'no game, no Hoon'); T.eq(bare:road(0, 0, 0), nil, 'and no road'); T.eq(bare:attack(1, 0, 0, 0, 7), false, 'and no attack')
T.done('hoons')
