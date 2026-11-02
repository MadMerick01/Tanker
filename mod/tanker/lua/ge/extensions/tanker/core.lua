-- The Tanker controller: ties the Earth position, the save, the fuel and the pistol together,
-- builds the HUD's state, and draws the wrist HUD. For now a run is: go to the start at Port
-- Augusta, drive north, fight off the Hoons, siphon fuel from cars you find, and save on the way.
-- Tankers and looting come next.
local location = require('tanker/location')
local config = require('tanker/config')
local options = require('tanker/options')
local persistence = require('tanker/persistence')
local diagnostics = require('tanker/diagnostics')
local hud = require('tanker/hud')
local earthAdapter = require('tanker/earthAdapter')
local fuel = require('tanker/fuel')
local pistol = require('tanker/pistol')
local route = require('tanker/route')
local threat = require('tanker/threat')
local wrist = require('tanker/wrist')
local vehicle = require('tanker/vehicle')
local siphon = require('tanker/siphon')
local nearby = require('tanker/nearby')
local hoons = require('tanker/hoons')
local hoonCar = require('tanker/hoonCar')
local M = {}

-- One-line settings. Tune these after testing in game.
-- How often the truck's position is read, in seconds.
local SAMPLE_SECONDS = 0.5
-- A jump further than this between two readings is a teleport, not driving.
local TELEPORT_METRES = 500
-- After a teleport request, how long to wait for Earth to load the terrain and place the truck.
local TELEPORT_WAIT_SECONDS = 60
M.TELEPORT_WAIT_SECONDS = TELEPORT_WAIT_SECONDS
-- After asking for the starter truck, how long to wait for it before carrying on without it.
local SPAWN_WAIT_SECONDS = 10
M.SPAWN_WAIT_SECONDS = SPAWN_WAIT_SECONDS

local LABELS = {
  STARTING = 'STARTING UP', NO_EARTH = 'WAITING FOR BEAMNG.EARTH', NEW = 'READY TO START',
  TO_START = 'HEADING TO THE START', SPAWNING = 'FETCHING YOUR TRUCK', AWAY = 'AWAY FROM YOUR SAVE', TO_SAVE = 'HEADING TO YOUR SAVE',
  RUNNING = 'ON THE ROAD', ERROR = 'SOMETHING WENT WRONG',
}

function M.new(env)
  local c = {
    state = 'STARTING', diag = diagnostics.new(env.log), hud = hud.new(env.trigger),
    store = persistence.new(env.io), fuel = env.fuel, pistol = env.pistol, adapter = env.adapter, vehicles = env.vehicles,
    clock = 0, nextSample = 0, threat = 'clear', nearby = env.nearby,
  }
  c.hoons = env.hoonCar and hoons.new(env.hoonCar, env.random)
  c.siphon = siphon.new(function(litres, serial, id)
    return env.fuel.change ~= nil and env.fuel:change(litres, serial, id)
  end)

  function c:transition(state, why)
    if self.state ~= state then self.diag:event('state', state .. (why and (' ' .. why) or '')) end
    self.state = state
  end

  -- Loads the settings and the save, and decides where the player stands.
  function c:reload()
    self.profile, self.reading, self.teleport, self.feedback, self.error = nil, nil, nil, nil, nil
    if self.hoons then self.hoons:remove() end
    local settings, why = config.load(env.io)
    if not settings then
      self.error, self.feedback = why, 'Your config.json can\'t be read. Fix it or delete it, then reload.'
      return self:transition('ERROR', why)
    end
    self.config = settings
    self.options = options.load(env.io)
    local save, status = self.store:load()
    if save then
      self.profile = save
      return self:transition('AWAY', 'loaded')
    end
    if status == 'missing' then return self:transition('NEW') end
    if status == 'unreadable' then
      self.feedback = 'Your save could not be read. Starting the run again replaces it.'
      return self:transition('NEW', status)
    end
    self.error = status
    self.feedback = status == 'newer_version' and 'This save is from a newer Tanker. Update the mod to carry on.'
      or 'Your saves can\'t be reached right now. Reload the mod to try again.'
    return self:transition('ERROR', status)
  end

  function c:start()
    return self.config and self.config.start or route.START
  end

  -- Asks Earth to take the truck somewhere; the arrival is seen from the position.
  function c:sendTo(point, name, state)
    local ok, why = self.adapter:teleport(point, name)
    if not ok then
      self.feedback = why == 'teleport_refused' and 'BeamNG.Earth could not teleport you. Check its companion is connected.'
        or 'BeamNG.Earth\'s teleport is not available. Check BeamNG.Earth is running.'
      self.diag:event('teleport', tostring(why), 'W')
      return false
    end
    self.teleport = { point = location.copy(point), sentAt = self.clock }
    self.feedback = 'Teleporting. The desert takes a moment to load.'
    self:transition(state)
    return true
  end

  -- Start the run: only with no save, since the run is hardcore and there is one save.
  function c:startRun()
    if self.state ~= 'NEW' then return false end
    return self:sendTo(self:start(), route.START_NAME, 'TO_START')
  end

  function c:goToSave()
    if self.state ~= 'AWAY' or not self.profile then return false end
    return self:sendTo(self.profile.resume, 'Tanker save', 'TO_SAVE')
  end

  -- Desert rocks On / Off, from the HUD. Kept at once in options.json and applied at the next sample.
  function c:setDesertRocks(on)
    if not self.options then return false end
    self.options.desertRocks = on == true
    if not options.save(env.io, self.options) then
      self.diag:event('options_save_failed', 'desertRocks', 'W')
    end
    self:applyRocks()
    return true
  end

  function c:applyRocks()
    if not (self.options and self.adapter.rocks) then return end
    local status = self.adapter:rocks(self.options.desertRocks)
    if status ~= self.rocks then self.diag:event('rocks', tostring(status)) end
    self.rocks = status
  end

  -- Siphoning: offered while you stand still beside another car on the road.
  function c:siphonBlocked()
    if self.state ~= 'RUNNING' then return 'not_running' end
    if self.siphon:active() then return 'siphoning' end
    local near = self.near
    if not (near and near.metres <= siphon.REACH_METRES) then return 'nothing_near' end
    if near.speed > siphon.STILL_MPS then return 'moving' end
  end

  function c:startSiphon()
    if self:siphonBlocked() then return false end
    if not self.siphon:start(self.near.id, self.clock) then return false end
    self.feedback = 'Siphoning. Stay still beside their car.'
    self.diag:event('siphon', 'start ' .. tostring(self.near.id))
    return true
  end

  function c:stopSiphon()
    if not self.siphon:active() then return false end
    self.feedback = self.siphon:finish('stopped', self.clock)
    return true
  end

  -- Each half second: keeps the siphon going, or looks for a car to offer one from.
  function c:followSiphon()
    if not self.nearby then return end
    if self.state ~= 'RUNNING' then
      self.near = nil
      if self.siphon:active() then self.feedback = self.siphon:finish('stopped', self.clock) end
      return
    end
    if self.siphon:active() then
      local car, me = self.nearby:closest(self.siphon.run.donor)
      local line = self.siphon:step(self.clock, car and car.metres, me and me.speed, self.reading)
      if line then self.feedback = line; self.diag:event('siphon', line) end
      self.near = nil
      return
    end
    local car, me = self.nearby:closest()
    self.near = car and me and { id = car.id, metres = car.metres, speed = me.speed } or nil
  end

  -- A car's answer to fuel:change(). Litres put into your own tank show at once.
  function c:fuelChanged(id, serial, before, after, capacity)
    local donor = self.siphon.run and self.siphon.run.donor
    local handled, line = self.siphon:answer(serial, before, after, capacity, self.clock)
    if not handled then return end
    if id ~= donor and location.finite(after) and location.finite(capacity) and capacity > 0 then
      self.reading = { litres = after, capacity = capacity, km = self.profile and self.profile.run.drivenKm }
    end
    if line then self.feedback = line; self.diag:event('siphon', line) end
  end

  -- The Hoons: their car is loaded once the run is on the road, then they come every few km.
  function c:followHoons()
    if not self.hoons or self.state ~= 'RUNNING' then return end
    if self.hoons.state == 'NONE' then
      local problem = self.hoons:load(self.profile.run.drivenKm)
      self.diag:event('hoon', problem or ('loaded ' .. tostring(self.hoons.model)), problem and 'W' or nil)
    end
    local line = self.hoons:step(self.clock, self.profile.run.drivenKm)
    if line then self.feedback = line; self.diag:event('hoon', line) end
  end

  -- For testing: sends the Hoon now instead of waiting for the km.
  function c:sendHoon()
    if self.state ~= 'RUNNING' or not self.hoons or self.hoons.state ~= 'HIDDEN' then return false end
    local line, why = self.hoons:send(self.clock)
    self.feedback = line or (why == 'off_road' and 'Hoons only come when you are on a road.'
      or why == 'no_solid_road' and 'No solid road near you for a Hoon yet. Try further along.'
      or 'The Hoon could not be sent: ' .. tostring(why))
    return line ~= nil
  end

  function c:saveBlocked()
    if self.state ~= 'RUNNING' or not self.profile then return 'not_running' end
    if not (self.here and self.here.valid) then return 'no_position' end
    if self.threat ~= 'clear' then return 'hoons_near' end
  end

  function c:write()
    local p = self.profile
    p.resume = { latitude = self.here.latitude, longitude = self.here.longitude, heading = self.here.heading }
    if self.here.vehicle and self.here.vehicle.model then p.vehicle.model = self.here.vehicle.model end
    if self.reading then p.vehicle.fuelLitres = self.reading.litres end
    local saved, why = self.store:save(p)
    if not saved then
      self.feedback = 'Saving failed. Your last save is untouched; try again.'
      self.diag:event('save_failed', tostring(why), 'W')
      return false
    end
    self.profile = saved
    self.feedback = 'Saved here.'
    return true
  end

  function c:manualSave()
    local blocked = self:saveBlocked()
    if blocked then
      if blocked == 'hoons_near' then self.feedback = 'You can\'t save with Hoons nearby.' end
      return false
    end
    return self:write()
  end

  -- A teleport has landed once the truck is near where it was sent.
  function c:arrived(radius)
    if not (self.teleport and self.here and self.here.valid) then return false end
    local metres = location.distance(self.here, self.teleport.point)
    return metres ~= nil and metres <= radius
  end

  -- Puts the player in the starter truck, then starts or resumes the run once it has arrived.
  -- Without the game's vehicles (or if the swap fails) the run carries on in whatever they drive.
  function c:fetchTruck(kind)
    self.spawning = { kind = kind, at = self.clock }
    self:transition('SPAWNING', kind)
    local ok, why, detail = self.vehicles and self.vehicles:spawnStarter()
    if not ok then
      self.diag:event('starter_truck', tostring(why) .. (detail and (': ' .. detail) or ''), 'W')
      self:truckArrived()
    end
  end

  function c:truckArrived()
    local kind = self.spawning and self.spawning.kind
    self.spawning = nil
    local here = self.here
    self.last = here and here.valid and location.copy(here) or nil
    if kind == 'start' then
      self.profile = persistence.newProfile(self:start(), here,
        { model = vehicle.STARTER_MODEL, configuration = vehicle.STARTER_NAME })
      self:transition('RUNNING', 'started')
      if self:write() then self.feedback = 'The run has started. Head north for Pine Gap.' end
    else
      -- The tank goes back to what was saved, so quitting never refills it.
      local litres = self.profile.vehicle.fuelLitres
      if litres then self.fuel:set(litres, self.profile.generation) end
      self.feedback = 'Back where you saved.'
      self:transition('RUNNING', 'resumed')
    end
  end

  -- The game's onVehicleSpawned: the starter truck has arrived when the player's vehicle respawns.
  function c:vehicleSpawned(id)
    if self.state == 'SPAWNING' and self.vehicles and self.vehicles:isPlayer(id) then self:truckArrived() end
  end

  function c:follow()
    local here = self.here
    if self.state == 'TO_START' and self:arrived(route.START_RADIUS_METRES) then
      self.teleport = nil
      self:fetchTruck('start')
    elseif self.state == 'TO_SAVE' and self:arrived(math.max(self.config.resumeRadiusMetres, route.START_RADIUS_METRES)) then
      self.teleport = nil
      self:fetchTruck('resume')
    elseif self.state == 'SPAWNING' and self.clock - self.spawning.at > SPAWN_WAIT_SECONDS then
      self.diag:event('starter_truck', 'no spawn seen; carrying on', 'W')
      self:truckArrived()
    elseif self.state == 'AWAY' and here.valid then
      local metres = location.distance(here, self.profile.resume)
      if metres and metres <= self.config.resumeRadiusMetres then
        self.last = location.copy(here)
        self:transition('RUNNING', 'at_save')
      end
    elseif (self.state == 'TO_START' or self.state == 'TO_SAVE') and self.clock - self.teleport.sentAt > TELEPORT_WAIT_SECONDS then
      self.teleport = nil
      self.feedback = 'The teleport did not arrive. Try again.'
      self:transition(self.state == 'TO_START' and 'NEW' or 'AWAY', 'teleport_timeout')
    end
    if self.state == 'RUNNING' and here.valid and self.last then
      local step = location.distance(self.last, here) or 0
      if step <= TELEPORT_METRES then self.profile.run.drivenKm = self.profile.run.drivenKm + step / 1000 end
      self.last = location.copy(here)
    end
  end

  function c:sample()
    self.here = self.adapter:sample()
    if self.state == 'ERROR' or self.state == 'STARTING' then return end
    self:applyRocks()
    if not self.here.valid then
      self.diag:event('position', tostring(self.here.reason))
      return
    end
    self:follow()
    self:followSiphon()
    self:followHoons()
    self.fuel:read()
    local distances = env.hoonDistances and env.hoonDistances() or (self.hoons and self.hoons:distances())
    self.threat = threat.level(distances)
  end

  -- The truck's answer to fuel:read(). Litres going down while driving measure the range.
  function c:fuelReading(_, litres, capacity)
    if not (location.finite(litres) and location.finite(capacity)) or capacity <= 0 then return end
    local previous = self.reading
    self.reading = { litres = litres, capacity = capacity, km = self.profile and self.profile.run.drivenKm }
    if not (previous and self.profile and self.state == 'RUNNING' and previous.km) then return end
    local used, km = previous.litres - litres, self.profile.run.drivenKm - previous.km
    if used > 0 and km >= 0 then
      local r = self.profile.run
      r.usedLitres, r.rangeKm = (r.usedLitres or 0) + used, (r.rangeKm or 0) + km
    end
  end

  function c:fuelSet(_, _, _, after, capacity)
    if location.finite(after) and location.finite(capacity) and capacity > 0 then
      self.reading = { litres = after, capacity = capacity, km = self.profile and self.profile.run.drivenKm }
    end
  end

  function c:view()
    local here = self.here or {}
    local v = {
      state = self.state, stateLabel = LABELS[self.state], feedback = self.feedback, threat = self.threat,
      startName = route.START_NAME, goalName = route.GOAL_NAME,
      startAllowed = self.state == 'NEW', goToSaveAllowed = self.state == 'AWAY',
      saveAllowed = self:saveBlocked() == nil, saveBlockedBy = self:saveBlocked() == 'hoons_near' and 'hoons' or nil,
    }
    if here.valid then
      v.goal = route.toGoal(here)
      v.progress = route.progress(here, self:start())
    end
    if self.profile then
      v.drivenKm = self.profile.run.drivenKm
      -- For the start page's Welcome back box: where the save is and what it holds.
      local resume = self.profile.resume
      local toGoal = resume and route.toGoal(resume)
      v.save = { latitude = resume and resume.latitude, longitude = resume and resume.longitude,
        roadKm = toGoal and toGoal.roadKm, fuelLitres = self.profile.vehicle.fuelLitres,
        drivenKm = self.profile.run.drivenKm,
        metresAway = here.valid and resume and location.distance(here, resume) or nil }
    end
    v.siphonAllowed = self:siphonBlocked() == nil
    v.siphonStopAllowed = self.siphon:active()
    if self.near and self.near.metres <= siphon.REACH_METRES and self.state == 'RUNNING' then
      v.siphonNear = { metres = self.near.metres, moving = self.near.speed > siphon.STILL_MPS }
    end
    v.siphon = self.siphon:view(self.clock, self.reading)
    if self.hoons then
      v.hoonTestAllowed = self.state == 'RUNNING' and self.hoons.state == 'HIDDEN'
      v.hoon = { state = self.hoons.state, metres = self.hoons:outId() and self.hoons.metres or nil }
    end
    if v.siphon then
      v.siphon.hoons = self.threat ~= 'clear'
      v.siphon.blink = math.floor(self.clock) % 2 == 0
    end
    if self.options then
      v.rocksAllowed = true
      v.rocks = { on = self.options.desertRocks, status = self.rocks }
    end
    if self.reading then
      local r = self.profile and self.profile.run or {}
      v.fuel = { litres = self.reading.litres, capacity = self.reading.capacity,
        rangeKm = fuel.range(self.reading.litres, r.usedLitres, r.rangeKm) }
    end
    local gun = self.pistol:read()
    v.pistol = { installed = gun.installed, drawn = gun.drawn }
    if gun.loaded then v.ammo = { loaded = gun.loaded, spare = gun.spare } end
    return v
  end

  -- The wrist HUD, every frame while VR hand tracking runs. The triangles are only rebuilt when
  -- what they show changes.
  function c:drawWrist()
    if not (self.config and self.config.wrist and env.drawTri) then return end
    local pose = self.pistol:leftHand()
    if not pose then return end
    local v = self.lastView or self:view()
    local key = table.concat({ tostring(v.threat), wrist.digitsFor(v.goal and v.goal.roadKm),
      tostring(v.fuel and math.floor(v.fuel.litres)), tostring(v.fuel and v.fuel.capacity),
      tostring(v.ammo and v.ammo.loaded), tostring(v.siphon and v.siphon.active and v.siphon.blink) }, '|')
    if key ~= self.wristKey then self.wristTris, self.wristKey = wrist.build(v), key end
    wrist.place(self.wristTris, pose, env.drawTri)
  end

  function c:mount(on)
    if self.hud:mount(on, self.clock) then self:publish(true) end
  end

  function c:publish()
    self.lastView = self:view()
    self.hud:publish(self.lastView, self.clock)
  end

  function c:tick(dt)
    self.clock = self.clock + (location.finite(dt) and dt > 0 and dt or 0)
    if self.state == 'STARTING' then self:reload() end
    if self.clock >= self.nextSample then
      self.nextSample = self.clock + SAMPLE_SECONDS
      self:sample()
      self:publish()
    end
    self:drawWrist()
  end

  function c:endMission()
    self.teleport = nil
  end

  -- Tanker going away puts back the rocks it hid.
  function c:shutdown()
    if self.hoons then self.hoons:remove() end
    if self.adapter.restoreRocks then self.adapter:restoreRocks() end
  end

  return c
end

-- --------------------------------------------------------------- the game's side ---

local active
local function gameIO()
  return {
    read = function(path) return jsonReadFile(path) end,
    exists = function(path) return FS:fileExists(path) end,
    mkdir = function(path)
      if not FS:directoryExists(path) then FS:directoryCreate(path, true) end
      return FS:directoryExists(path)
    end,
    write = function(path, data) return jsonWriteFile(path, data, false) end,
  }
end
-- Draws one wrist triangle with the debug drawer, as the revolver is drawn. The corners are
-- reused vec3s, so drawing makes no garbage.
local va, vb, vc
local function drawTri(ax, ay, az, bx, by, bz, cx, cy, cz, colour)
  if not (debugDrawer and vec3 and color) then return end
  if not va then va, vb, vc = vec3(), vec3(), vec3() end
  va:set(ax, ay, az) vb:set(bx, by, bz) vc:set(cx, cy, cz)
  debugDrawer:drawTriSolid(va, vb, vc, color(colour[1], colour[2], colour[3], 255))
end
local function ensure()
  if not active then
    active = M.new({ io = gameIO(), adapter = earthAdapter.new(), fuel = fuel.new(), pistol = pistol.new(),
      vehicles = vehicle.new(), nearby = nearby.new(), hoonCar = hoonCar.new(),
      log = rawget(_G, 'log'), drawTri = drawTri,
      trigger = function(event, payload) if guihooks then guihooks.trigger(event, payload) end end })
  end
  return active
end
local function traced(e)
  return type(debug) == 'table' and type(debug.traceback) == 'function' and debug.traceback(tostring(e), 2) or tostring(e)
end
local function safely(f)
  local ok, result = xpcall(f, traced)
  if not ok then
    if active then
      active.error, active.feedback = 'internal_error', 'Anything since your last save is lost when you reload.'
      active:transition('ERROR', 'internal_error')
      active.diag:event('internal_error', tostring(result), 'E')
    elseif log then log('E', 'tanker', tostring(result)) end
    return false
  end
  return result
end

function M.onVehicleSpawned(vehicleId) return safely(function() if active then active:vehicleSpawned(vehicleId) end end) end
function M.onExtensionLoaded()
  return safely(function() ensure().diag:event('extension_loaded', 'Tanker') end)
end
function M.onPreRender(dtReal) return safely(function() ensure():tick(dtReal) end) end
function M.startRun() return safely(function() return ensure():startRun() end) end
function M.goToSave() return safely(function() return ensure():goToSave() end) end
function M.save() return safely(function() return ensure():manualSave() end) end
function M.rocksOn() return safely(function() return ensure():setDesertRocks(true) end) end
function M.rocksOff() return safely(function() return ensure():setDesertRocks(false) end) end
-- The truck's answers to fuel.lua's commands.
function M.fuelReading(vehicleId, litres, capacity)
  return safely(function() if active then active:fuelReading(vehicleId, litres, capacity) end end)
end
function M.fuelSet(vehicleId, serial, before, after, capacity)
  return safely(function() if active then active:fuelSet(vehicleId, serial, before, after, capacity) end end)
end
function M.fuelChanged(vehicleId, serial, before, after, capacity)
  return safely(function() if active then active:fuelChanged(vehicleId, serial, before, after, capacity) end end)
end
function M.siphonStart() return safely(function() return ensure():startSiphon() end) end
function M.siphonStop() return safely(function() return ensure():stopSiphon() end) end
function M.sendHoon() return safely(function() return ensure():sendHoon() end) end
function M.uiMounted(on) return safely(function() ensure():mount(on == true) end) end
function M.getState() return safely(function() return ensure():view() end) end
function M.reload() return safely(function() ensure():reload() end) end
function M.onClientStartMission() return M.reload() end
function M.onClientEndMission() return safely(function() if active then active:endMission() end end) end
function M.onExtensionUnloaded() -- no implicit save on shutdown
  if active then safely(function() active:shutdown() end) end
  active = nil
end

return M
