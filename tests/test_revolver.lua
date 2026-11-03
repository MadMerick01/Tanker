local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local R = require('tanker/route')
local G = require('tanker/revolver')
local H = require('tanker/hoons')

-- The cylinder, the time between shots and reloading.
local g = G.new()
T.eq(g.loaded, 6, 'a full cylinder'); T.eq(g.spare, G.START_SPARE, 'and spare rounds')
T.eq(select(2, g:fire(0)), 'holstered', 'no shot while holstered')
g:setDrawn(true)
T.eq(g:fire(1), true, 'bang'); T.eq(g.loaded, 5, 'one round gone')
T.eq(select(2, g:fire(1.1)), 'cooldown', 'not that fast')
for i = 1, 5 do g:fire(1 + i) end
T.eq(g.loaded, 0, 'empty')
T.eq(select(2, g:fire(10)), 'empty', 'click'); T.eq(g:reloading(), true, 'an empty click starts a reload')
T.eq(select(2, g:fire(10.5)), 'reloading', 'no shot while reloading')
T.eq(g:step(11), false, 'still reloading'); T.eq(g:step(12.1), true, 'reloaded')
T.eq(g.loaded, 6, 'full again'); T.eq(g.spare, G.START_SPARE - 6, 'from the spare rounds')
T.eq(select(2, g:reload(13)), 'full', 'nothing to reload')
local dry = G.new({ loaded = 0, spare = 0 }); dry:setDrawn(true)
dry:fire(0); T.eq(dry:reloading(), false, 'no spare rounds, no reload')
T.eq(G.new({ loaded = 9, spare = -1 }).loaded, 6, 'a bad save gets a full cylinder')
T.eq(dry:addRounds(4), 4, 'loot adds rounds')

-- A pretend game: the test says where the mouse aims and records the hits.
local function fakeAim()
  local a = { vrOn = false, target = 42, clicks = 0, hits = {}, draws = 0 }
  function a:vr() return self.vrOn end
  function a:aim() return { targetId = self.target, point = { x = 0, y = 0, z = 0 }, dir = { x = 0, y = 1, z = 0 } } end
  function a:draw() self.draws = self.draws + 1 end
  function a:clicked() if self.clicks > 0 then self.clicks = self.clicks - 1; return true end return false end
  function a:hit(shot) self.hits[#self.hits + 1] = shot.targetId; return true end
  return a
end
local function fakeHoonCar()
  local car = { calmed = 0 }
  function car:load() return 42, 'barstow' end
  function car:hide() end
  function car:player() return { id = 7, x = 0, y = 0, z = 0, dx = 0, dy = 1, speed = 10 } end
  function car:road(x, y, z) return { x = x, y = y, z = z, metres = 0 } end
  function car:solid() return true end
  function car:attack() return true end
  function car:calm() self.calmed = self.calmed + 1 end
  function car:state() return { x = 0, y = 200, z = 0, speed = 20 } end
  function car:remove() end
  return car
end

local adapter = F.adapter(-31.0, 140.0)
local shooter = fakeAim()
local hoonCar = fakeHoonCar()
local c, env = F.controller(adapter, { aim = shooter, hoonCar = hoonCar, vehicles = F.vehicles() })
local function run(seconds) for _ = 1, math.floor(seconds * 2) do c:tick(0.5) end end
run(1)
T.eq(c:view().revolverAllowed, nil, 'no revolver before the run'); T.eq(c:toggleRevolver(), false, 'none to draw')
c:startRun(); adapter:put(R.START.latitude, R.START.longitude); run(1); c:vehicleSpawned(7); run(0.5)
local v = c:view()
T.eq(v.revolverAllowed, true, 'the flatscreen revolver on the road'); T.eq(v.ammo.loaded, 6, 'its rounds on the HUD')
shooter.clicks = 1; c:followAim()
T.eq(#shooter.hits, 0, 'holstered, a click is just a click'); shooter.clicks = 0
T.eq(c:toggleRevolver(), true, 'drawn'); T.eq(c:view().gun.drawn, true, 'the HUD says so')
c:followAim(); T.eq(shooter.draws, 1, 'the crosshair shows')
c.hudHover = true; shooter.clicks = 1; c:followAim()
T.eq(#shooter.hits, 0, 'a click on the HUD is not a shot'); c.hudHover = false; shooter.clicks = 0
-- Shooting the Hoon: four hits stop it.
T.eq(c:sendHoon(), true, 'a Hoon comes'); T.eq(c.hoons.state, 'HUNTING', 'hunting')
for i = 1, H.SHOTS_TO_STOP do
  shooter.clicks = 1; c.clock = c.clock + 1; c:followAim()
end
T.eq(#shooter.hits, H.SHOTS_TO_STOP, 'each shot hits'); T.eq(c.hoons.state, 'DOWN', 'the Hoon is stopped')
T.check(c.feedback:find('shot the Hoon'), 'and the HUD says so'); T.eq(hoonCar.calmed, 1, 'its engine stops')
T.eq(c.gun.loaded, 6 - H.SHOTS_TO_STOP, 'rounds used')
-- A miss.
shooter.target = nil; shooter.clicks = 1; c.clock = c.clock + 1; c:followAim()
T.eq(c.feedback, 'Missed.', 'a miss'); T.eq(c.gun.loaded, 1, 'still costs a round')
-- Reloading, and the save keeps the rounds.
T.eq(c:reloadRevolver(), true, 'reload'); run(G.RELOAD_SECONDS + 0.5)
T.eq(c.gun.loaded, 6, 'reloaded')
c.hoons:putAway(0)
c.threat = 'clear'
T.eq(c:manualSave(), true, 'saved')
T.eq(c.profile.vehicle.ammo.loaded, 6, 'the save keeps the rounds'); T.eq(c.profile.vehicle.ammo.spare, G.START_SPARE - 5, 'and the spares')
local c2 = F.controller(F.adapter(-20, 130), { io = env.io, aim = fakeAim(), vehicles = F.vehicles() })
for _ = 1, 2 do c2:tick(0.5) end
c2:goToSave(); c2.adapter:put(c.profile.resume.latitude, c.profile.resume.longitude)
for _ = 1, 4 do c2:tick(0.5) end
c2:vehicleSpawned(7)
T.eq(c2.gun.spare, G.START_SPARE - 5, 'back at the save, the same rounds')
-- In VR the VR revolver mod shoots, so the flatscreen one stays away.
shooter.vrOn = true
T.eq(c:view().revolverAllowed, nil, 'no mouse revolver in VR')
c:followAim(); T.eq(c.gun.drawn, false, 'and it is holstered')
T.done('revolver')
