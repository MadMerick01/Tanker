local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
require('fixtures')
local B = require('tanker/behind')
local P = require('tanker/pack')
local TM = require('tanker/tankerMob')

-- Out of sight (Rowan, 6 Nov): Hoons and tankers only appear in the 180 degrees behind the camera.
local look = { x = 0, y = 0, dx = 0, dy = 1 }
T.eq(B.isBehind(look, 0, -40), true, 'straight behind the camera')
T.eq(B.isBehind(look, 100, -B.MARGIN_METRES), true, 'off to the side, just behind it')
T.eq(B.isBehind(look, 100, 0), false, 'level with it is the edge of the view: not behind')
T.eq(B.isBehind(look, 0, 40), false, 'in front')
local bx, by = B.point(look, 60)
T.eq(bx, 0, 'behind, not to the side'); T.eq(by, -60, '60 m straight behind')
T.eq(B.isBehind(nil, 0, 40), true, 'no view, no limit')

-- Reading the game's camera: flat and normalised; looking straight down or nothing there, no camera.
local cam = B.camera({ cameraPosition = function() return { x = 5, y = 6, z = 7 } end,
  cameraForward = function() return { x = 3, y = 4, z = -10 } end })
T.eq(cam.x, 5, 'where the camera is'); T.near(cam.dx, 0.6, 1e-9, 'facing, flat'); T.near(cam.dy, 0.8, 1e-9, 'and forward')
T.eq(B.camera({ cameraPosition = function() return { x = 0, y = 0, z = 0 } end,
  cameraForward = function() return { x = 0, y = 0, z = -1 } end }), nil, 'looking straight down')
T.eq(B.camera({ cameraPosition = function() error('no camera') end, cameraForward = function() return { x = 1, y = 0 } end }), nil, 'no camera')
T.eq(B.camera({}), nil, 'nothing to read')
-- The view: the camera if there is one, else the truck.
local me = { x = 1, y = 2, dx = 0, dy = 1 }
T.eq(B.view({}, me).dy, 1, 'no camera: the truck\'s facing')
T.eq(B.view({ camera = function() return { x = 0, y = 0, dx = 1, dy = 0 } end }, me).dx, 1, 'the camera')

-- A new pack Hoon: only at a far slot behind the camera.
local function fakeCar(camera)
  local car = { me = { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 20 }, cars = {}, next = 100 }
  function car:player() return self.me end
  function car:ground() return 0 end
  function car:take() self.next = self.next + 1; return self.next, 'own' end
  function car:place(id, x, y, z) self.cars[id] = { x = x, y = y, z = z, speed = 20 }; return true end
  function car:goTo() return true end
  function car:state(id) return self.cars[id] end
  function car:calm() end
  function car:release(id) self.cars[id] = nil end
  function car:removeAll() end
  function car:road() return nil end
  function car:chase() end
  car.camera = camera
  return car
end
local function rolls(n) return function(lo, hi) if lo == 0 and hi == 1 then return 0.5 end return lo + (hi - lo) * n end end
for _, n in ipairs({ 0, 0.3, 0.6, 0.99 }) do
  local car = fakeCar()
  local p = P.new(car, rolls(n))
  p:add(0)
  local h = p.hoons[1]
  T.eq(P.SLOTS[h.slot].ahead, -1, 'camera behind the truck facing forward: a rear far slot (' .. h.slot .. ')')
  T.check(car.cars[h.id].y < -B.MARGIN_METRES, 'put down behind you')
end
-- Looking out of the right window: only the left slots are behind the camera.
for _, n in ipairs({ 0, 0.5, 0.99 }) do
  local car = fakeCar(function() return { x = 0, y = 0, dx = 1, dy = 0 } end)
  local p = P.new(car, rolls(n))
  p:add(0)
  local h = p.hoons[1]
  T.eq(P.SLOTS[h.slot].side, -1, 'looking right, a slot on your left (' .. h.slot .. ')')
  T.check(car.cars[h.id].x < 0, 'put down on your left')
end
-- Every slot behind the camera taken: straight behind the camera, then it drives to its slot.
local car = fakeCar()
local p = P.new(car, rolls(0))
p:add(0); p:add(0)
p:add(0)
local third = p.hoons[3]
T.eq(P.SLOTS[third.slot].ahead, 1, 'a front slot is all that is left')
T.eq(car.cars[third.id].x, 0, 'straight behind'); T.eq(car.cars[third.id].y, -P.HIDDEN_METRES, 'but it starts behind the camera')

-- The TankerMob, looking back over your shoulder: behind the camera is ahead of the truck.
local spawned = {}
local truck = { getID = function() return 55 end, queueLuaCommand = function() end, setActive = function() end }
local tcar = fakeCar(function() return { x = 0, y = -5, dx = 0, dy = -1 } end)
local mob = TM.new(tcar, {
  vehicles = function() return { spawnNewVehicle = function(model, opts) spawned[#spawned + 1] = opts; return truck end } end,
  byId = function(id) return id == 55 and truck or nil end,
  vec3 = function(x, y, z) return { x = x, y = y, z = z } end, quatFromDir = function(d) return d end,
  spawn = function() return nil end,
})
T.eq(mob:spawn(), true, 'spawned')
T.eq(spawned[1].pos.y, -5 + TM.SPAWN_METRES, 'behind the camera: ahead of your truck')
T.eq(spawned[1].rot.y, 1, 'facing away from you')

T.done('out of sight')
