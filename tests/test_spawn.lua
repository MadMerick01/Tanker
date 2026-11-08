local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local H = require('tanker/hoons')
local M = require('tanker/tankerMob')
local R = require('tanker/route')

-- The Hoon spawn button works off road: on a road nearby if there is one, or behind you.
local car = { me = { id = 7, x = 0, y = 0, z = 5, dx = 0, dy = 1, speed = 0 }, attacks = {} }
function car:player() return self.me end
function car:load() return 99, 'barstow' end
function car:hide() end
function car:road() return nil end
function car:solid() return false end
function car:ground() return 3 end
function car:attack(id, x, y, z) self.attacks[#self.attacks + 1] = { x = x, y = y, z = z }; return true end
function car:calm() end
function car:state() return { x = 0, y = -40, z = 3, speed = 10 } end
function car:remove() end
local h = H.new(car, function(lo) return lo end)
h:load(0)
T.eq(select(2, h:send(0)), 'off_road', 'on its own, a Hoon never comes off road')
T.eq(h:send(0, true), H.LINES.coming, 'the spawn button sends it anyway')
T.eq(car.attacks[1].y, -H.SPAWN_METRES, 'behind you'); T.eq(car.attacks[1].z, 3, 'on the ground')

-- The TankerMob: spawned once behind the camera (here, with no camera, behind your truck) facing away, then moved back there on the next press.
local V = {}
local function vec(x, y, z) return { x = x, y = y, z = z } end
local spawned, queued, teleports = {}, {}, 0
local truck = { getID = function() return 55 end, queueLuaCommand = function(_, cmd) queued[#queued + 1] = cmd end,
  delete = function(self) self.deleted = true end }
local mob = M.new(car, {
  vehicles = function() return { spawnNewVehicle = function(model, opts) spawned[#spawned + 1] = { model = model, opts = opts }; return truck end } end,
  byId = function(id) return id == 55 and not truck.deleted and truck or nil end,
  vec3 = vec, quatFromDir = function() return 'rot' end,
  spawn = function() return { safeTeleport = function() teleports = teleports + 1 end } end,
})
T.eq(mob:spawn(), true, 'spawned')
T.eq(spawned[1].model, 'us_semi', 'the us_semi'); T.eq(spawned[1].opts.config, M.CONFIG, 'with MadMerick\'s TankerMob config')
T.eq(spawned[1].opts.pos.y, -M.SPAWN_METRES, 'behind you, out of sight'); T.eq(spawned[1].opts.pos.z, 3 + M.DROP_METRES, 'dropped onto the ground')
T.eq(spawned[1].opts.autoEnterVehicle, false, 'you stay in your truck')
T.check(queued[1]:find("'flee'") and queued[1]:find('setTargetObjectID, 7'), 'it runs from you')
T.eq(mob:spawn(), true, 'again'); T.eq(#spawned, 1, 'the same truck'); T.eq(teleports, 1, 'moved back behind you')
mob:remove(); T.eq(truck.deleted, true, 'removed when Tanker goes')

-- The buttons, through the controller.
local adapter = F.adapter(-31.0, 140.0)
local spawns = 0
local fakeMob = { spawn = function() spawns = spawns + 1; return true end, remove = function() end }
local c = F.controller(adapter, { tankerMob = fakeMob, vehicles = F.vehicles() })
local function run(s) for _ = 1, math.floor(s * 2) do c:tick(0.5) end end
run(1)
T.eq(c:view().tankerSpawnAllowed, false, 'not before the run'); T.eq(c:spawnTanker(), false, 'nothing spawned')
c:startRun(); adapter:put(R.START.latitude, R.START.longitude); run(1); c:vehicleSpawned(7); run(0.5)
T.eq(c:view().tankerSpawnAllowed, true, 'on the road'); T.eq(c:spawnTanker(), true, 'spawned')
T.eq(spawns, 1, 'once'); T.check(c.feedback:find('TankerMob'), 'and the HUD says so')
T.done('spawn')
