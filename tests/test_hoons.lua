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
car.me.y = car.hoon.y + H.LEAVE_METRES - 1
h:step(31, 14)
T.eq(h.state, 'DOWN', 'waits while you are within 400 m, so you can come back and siphon again')
car.me.y = car.hoon.y + H.LEAVE_METRES + 1
h:step(31.5, 14)
T.eq(h.state, 'HIDDEN', 'put away once you are more than 400 m away'); T.eq(car.hidden, 1, 'hidden')
T.eq(h.nextKm, 14 + H.GAP_MIN_KM, 'the next comes a few km on')

-- Getting away: far from you for long enough.
T.eq(h:step(40, 20), H.LINES.coming, 'the next Hoon')
car.hoon.speed = 30; car.hoon.y = car.me.y - 2000
T.eq(steps(h, 41, H.ESCAPE_SECONDS, 20), H.LINES.escaped, 'outrun it and it gives up')
T.eq(h.state, 'HIDDEN', 'back in hiding')

-- No solid road behind: it never comes into view from ahead (MadMerick, 6 Nov: only behind the camera).
car.holeBehind = true
h:putAway(20)
local before = #car.attacks
T.eq(h:step(60, 40), nil, 'no solid road behind, and ahead is in view: no Hoon yet')
T.eq(#car.attacks, before, 'nothing put down in front of you')
-- Looking back over your shoulder, ahead of the truck is behind the camera: it comes from there.
function car:camera() return { x = self.me.x, y = self.me.y, dx = 0, dy = -1 } end
T.eq(h:step(60 + H.RETRY_SECONDS + 1, 40), H.LINES.ahead, 'comes from ahead, out of sight, when you look back')
T.eq(car.attacks[#car.attacks].y, car.me.y + H.PLACE_METRES, 'put on the road ahead')
-- Looking off to your right, it comes from straight behind the camera: off to your left.
car.holeBehind = nil
h:putAway(20)
function car:camera() return { x = self.me.x, y = self.me.y, dx = 1, dy = 0 } end
h:step(80, 40)
T.eq(car.attacks[#car.attacks].x, car.me.x - H.PLACE_METRES, 'behind the camera, wherever it looks')
car.camera = nil
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
T.eq(h:step(200, 40), H.LINES.gone, 'a car that vanished is handled'); T.eq(h.state, 'NONE', 'and a fresh car is loaded for the next')
T.eq(h.id, nil, 'the old car is forgotten')
T.eq(h:load(40), nil, 'loads again'); T.eq(h.state, 'HIDDEN', 'and waits')
T.check(h.nextKm >= 40 + H.FIRST_KM, 'not straight away')
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
local near = F.nearby({ [99] = 4 })
local c, env = F.controller(adapter, { hoonCar = car3, random = function(lo) return lo end, nearby = near })
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
-- Down beside you: siphon it, drive off (within 400 m), come back and siphon again, until its tank is dry.
car3.hoon.speed = 0
run(H.DOWN_SECONDS + 1)
T.eq(c.hoons.state, 'DOWN', 'the Hoon is down')
car3.me.speed = 0
-- In the truck, the siphon waits for you to get out.
near.speed = 0; run(0.5)
T.eq(c:view().siphonAllowed, false, 'not from inside the truck'); T.eq(c:view().siphonNear.needsFoot, true, 'you must be on foot')
-- Out on foot, your truck parked 3 m away.
near.onFoot, near.cars[7] = true, 3; run(0.5)
local function siphonOnce(before, after)
  T.eq(c:startSiphon(), true, 'siphon started on the Hoon')
  run(0.5)
  local take = env.fuel.changes[#env.fuel.changes]
  T.eq(take.id, 99, 'from the Hoon')
  c:fuelChanged(99, take.serial, before, after, 60)
  if after > 0 then
    local give = env.fuel.changes[#env.fuel.changes]
    c:fuelChanged(7, give.serial, 10, 10 + before - after, 300)
  end
end
siphonOnce(5, 4)
near.onFoot, near.cars[7] = false, nil
near.cars[99] = 300; near.speed = 20; car3.me.y = 300; run(1)
T.eq(c.siphon:active(), false, 'driving off stops the siphon')
T.eq(c.hoons.state, 'DOWN', 'the Hoon is still there 300 m away')
near.cars[99] = 4; near.speed = 0; car3.me.y = 0; run(1)
near.onFoot, near.cars[7] = true, 3; run(0.5)
T.eq(c:view().siphonAllowed, true, 'back beside it, Siphon fuel is offered again')
siphonOnce(4, 4)
T.eq(c.siphon.result.reason, 'dry', 'until its tank is dry')
car3.me.y = H.LEAVE_METRES + 1; near.cars[99] = nil; run(0.5)
T.eq(c.hoons.state, 'HIDDEN', 'more than 400 m away, the Hoon is gone')
T.eq(c:view().siphonNear, nil, 'and can no longer be siphoned')
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
T.eq(spawned[1].opts.config, nil, 'a plain one, since HoonOld1 is a Barstow')
T.eq(spawned[1].opts.autoEnterVehicle, false, 'without moving you into it')
T.eq(cars[50].active, 0, 'and switched off at once')
local barstowGame = HC.new({
  player = function() return player end, byId = function(i) return cars[i] end, vec3 = v3,
  random = function() return 0.2 end,
  vehicles = function() return {
    getModel = function(name) return name == 'barstow' and { model = 'barstow' } or {} end,
    spawnNewVehicle = function(m, opts) spawned[#spawned + 1] = { model = m, opts = opts }; return gameCar(51, opts.pos) end,
  } end,
})
local _, barstow = barstowGame:load()
T.eq(barstow, 'barstow', 'with a Barstow in the game, the Hoon is a Barstow')
T.eq(spawned[#spawned].opts.config, 'vehicles/barstow/hoonold1.pc', 'in MadMerick\'s HoonOld1 config on a low roll')
local fastGame = HC.new({
  player = function() return player end, byId = function(i) return cars[i] end, vec3 = v3,
  random = function() return 0.7 end,
  vehicles = function() return {
    getModel = function(name) return name == 'barstow' and { model = 'barstow' } or {} end,
    spawnNewVehicle = function(m, opts) spawned[#spawned + 1] = { model = m, opts = opts }; return gameCar(52, opts.pos) end,
  } end,
})
fastGame:load()
T.eq(spawned[#spawned].opts.config, 'vehicles/barstow/hoonfast2.pc', 'and HoonFast2 on a high roll')
-- Your own vehicle is never a Hoon: if the game put you in a Hoon's car, Tanker leaves it alone.
T.eq(game:hide(7), false, 'never hides your car'); T.eq(cars[7].active, 1, 'it stays on')
local okPut, whyPut = game:put(7, 0, 0, 0, 0, 1)
T.eq(okPut, false, 'never places your car'); T.eq(whyPut, 'no_car', 'as if it were gone')
T.eq(game:state(7), nil, 'and the Hoon counts its car as gone')
T.eq(game:hunt(7, 7), false, 'never sets your car hunting')
T.eq(#cars[7].commands, 0, 'no command reaches your car')
T.eq(cars[50].playerUsable, false, 'a Hoon car cannot be switched into')
local road = game:road(3, -390, 5)
T.near(road.y, -390, 1e-9, 'the nearest point on the road'); T.near(road.metres, 3, 1e-9, 'and how far')
T.eq(game:solid(0, -390, 5), false, 'no ground, not solid'); T.eq(game:solid(0, -400, 5), true, 'ground under the road is solid')
T.eq(game:attack(50, road.x, road.y, road.z, 7), true, 'attacks')
T.eq(cars[50].active, 1, 'switched on'); T.near(cars[50].pos.y, -390, 1e-9, 'put on the road')
T.check(cars[50].commands[#cars[50].commands]:find("tankerDriver.chase(7)", 1, true), 'hunting you with Tanker\'s own road driver')
T.check(cars[50].commands[#cars[50].commands]:find("setTargetObjectID, 7", 1, true), 'or BeamNG\'s chase AI without it')
T.check((loadstring or load)(cars[50].commands[#cars[50].commands]) ~= nil, 'the AI command is valid Lua')
T.eq(game:state(50).speed, 0, 'reads the Hoon')
game:hide(50)
T.eq(cars[50].active, 0, 'hidden again'); T.eq(cars[50].pos.z, 10 + HC.HIDE_LIFT, 'up out of the way')
game:remove(50)
T.eq(game:state(50), nil, 'removed')
local bare = HC.new({})
T.eq(bare:load(), nil, 'no game, no Hoon'); T.eq(bare:road(0, 0, 0), nil, 'and no road'); T.eq(bare:attack(1, 0, 0, 0, 7), false, 'and no attack')
T.done('hoons')
