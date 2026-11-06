-- The Tanker controller: ties the Earth position, the save, the fuel and the pistol together,
-- builds the HUD's state, and draws the wrist HUD. For now a run is: go to the start at Kulgera
-- Roadhouse, drive north, fight off the Hoons, siphon fuel from cars you find, and save on the way.
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
local pack = require('tanker/pack')
local packCar = require('tanker/packCar')
local transfer = require('tanker/transfer')
local bedTank = require('tanker/bedTank')
local workshop = require('tanker/workshop')
local parts = require('tanker/parts')
local pricing = require('tanker/pricing')
local revolver = require('tanker/revolver')
local aim = require('tanker/aim')
local tankerMob = require('tanker/tankerMob')
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
-- The fuel a new run starts with, in litres, about 200 km in the starter truck all told: a little
-- in the truck's own tank and the rest in the bed tank, to pump across. Kulgera to Pine Gap is
-- about 270 km, so you have to find fuel on the way.
local START_FUEL_LITRES, START_BED_LITRES = 15, 25
M.START_FUEL_LITRES, M.START_BED_LITRES = START_FUEL_LITRES, START_BED_LITRES
-- How often the bed tank's weight is updated while the pump runs, and its size asked for.
local BED_APPLY_SECONDS, BED_READ_SECONDS = 2, 5

local LABELS = {
  STARTING = 'STARTING UP', NO_EARTH = 'WAITING FOR BEAMNG.EARTH', NEW = 'READY TO START',
  TO_START = 'HEADING TO THE START', SPAWNING = 'FETCHING YOUR TRUCK', AWAY = 'AWAY FROM YOUR SAVE', TO_SAVE = 'HEADING TO YOUR SAVE',
  RUNNING = 'ON THE ROAD', ERROR = 'SOMETHING WENT WRONG',
}

function M.new(env)
  local c = {
    state = 'STARTING', diag = diagnostics.new(env.log), hud = hud.new(env.trigger),
    store = persistence.new(env.io), fuel = env.fuel, pistol = env.pistol, adapter = env.adapter, vehicles = env.vehicles,
    clock = 0, nextSample = 0, threat = 'clear', nearby = env.nearby, trigger = env.trigger,
    -- Leaves the free camera for the truck's own camera; without it the camera is left as it is.
    camera = env.camera,
  }
  c.hoons = env.hoonCar and hoons.new(env.hoonCar, env.random)
  -- The desert Hoons, for now only from the spawn button: they circle you and take turns attacking.
  c.pack = env.packCar and pack.new(env.packCar, env.random)
  -- The flatscreen revolver: mouse aiming when there is no VR.
  c.aim, c.gun = env.aim, revolver.new()
  c.tankerMob = env.tankerMob
  -- Parts paid for in fuel.
  c.parts = env.parts
  if c.parts then workshop.attach(c) end
  -- The bed tank: its litres are Tanker's own, its size comes from the truck.
  c.bed, c.bedLitres = env.bed, 0
  c.transfer = transfer.new(function(litres, serial)
    return env.fuel.change ~= nil and env.fuel:change(litres, serial)
  end, function(litres)
    c.bedLitres = math.max(0, c.bedLitres + litres)
    if c.bedCapacity and c.bedCapacity > 0 then c.bedLitres = math.min(c.bedLitres, c.bedCapacity) end
    c.bedDirty = true
  end)
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
    if self.pack then self.pack:clear() end
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

  -- Start a new game: drops the run you are on and heads for the start. The old save stays on
  -- disk until the new run has started and saved over it, so a failed teleport loses nothing.
  function c:newGameAllowed()
    return (self.state == 'AWAY' or self.state == 'RUNNING') and self.profile ~= nil
  end

  function c:newGame()
    if not self:newGameAllowed() then return false end
    local was, profile = self.state, self.profile
    if self.siphon:active() then self:stopSiphon() end
    if self.transfer:active() then self:stopPump() end
    if self.hoons and self.hoons:outId() then self.hoons:putAway(profile.run.drivenKm) end
    if self.pack then self.pack:clear() end
    self.profile, self.state = nil, 'NEW'
    if not self:startRun() then
      self.profile, self.state = profile, was
      return false
    end
    self.ownedParts, self.pendingParts, self.fittedParts, self.lastDamage = nil, nil, nil, nil
    self.restoreFuel, self.partsCheckDue = nil, nil
    -- The new run's km start from nought, so the first Hoon comes as early as in any new run.
    if self.hoons and self.hoons.state == 'HIDDEN' then self.hoons.nextKm = hoons.FIRST_KM end
    self.diag:event('new_game', was)
    return true
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
    if not handled then
      handled = self.transfer:answer(serial, before, after)
      if handled and location.finite(after) and location.finite(capacity) and capacity > 0 then
        self.reading = { litres = after, capacity = capacity, km = self.profile and self.profile.run.drivenKm }
      end
      return
    end
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

  -- The spawn button: sends the Hoon now instead of waiting for the km, road or no road.
  function c:sendHoon()
    if self.state ~= 'RUNNING' or not self.hoons or self.hoons.state ~= 'HIDDEN' then return false end
    local line, why = self.hoons:send(self.clock, true)
    self.feedback = line or ('The Hoon could not be sent: ' .. tostring(why))
    return line ~= nil
  end

  -- The Spawn a Hoon button: one more desert Hoon, from traffic, at a far slot. Pressing again
  -- while Hoons are out adds another, up to pack.MAX.
  function c:addHoon()
    if self.state ~= 'RUNNING' or not self.pack then return false end
    local line, why = self.pack:add(self.clock)
    if line then
      local h = self.pack.hoons[#self.pack.hoons]
      self.diag:event('pack', 'Hoon ' .. h.n .. ' from ' .. h.source .. ' at ' .. h.slot)
    else
      self.diag:event('pack', 'not added: ' .. tostring(why), 'W')
    end
    self.feedback = line or (why == 'full' and pack.LINES.full or ('The Hoon could not be sent: ' .. tostring(why)))
    return line ~= nil
  end

  function c:clearHoons()
    if not self.pack or #self.pack.hoons == 0 then return false end
    self.pack:clear()
    self.feedback = pack.LINES.cleared
    return true
  end

  function c:followPack()
    if not self.pack or self.state ~= 'RUNNING' then return end
    local line = self.pack:step(self.clock)
    if line then self.feedback = line; self.diag:event('pack', line) end
  end

  -- A Hoon's car said its AI can't do what the pack asked. Logged once.
  function c:packProblem(vehId, what)
    self.packProblems = self.packProblems or {}
    if self.packProblems[what] then return end
    self.packProblems[what] = true
    self.diag:event('pack', tostring(what) .. ' in car ' .. tostring(vehId), 'W')
  end

  -- The spawn button for the TankerMob: a fuel tanker ahead of you that drives away.
  function c:spawnTanker()
    if self.state ~= 'RUNNING' or not self.tankerMob then return false end
    local ok, why = self.tankerMob:spawn()
    self.feedback = ok and 'A TankerMob is up ahead and running from you. Stop it and siphon its tank.'
      or ('The TankerMob could not be spawned: ' .. tostring(why))
    if not ok then self.diag:event('tanker_mob', tostring(why), 'W') end
    return ok
  end

  -- The pump between the bed tank and the truck's tank.
  function c:pumpBlocked()
    if self.state ~= 'RUNNING' then return 'not_running' end
    if self.transfer:active() then return 'pumping' end
    if not (self.bedCapacity and self.bedCapacity > 0) then return 'no_bed_tank' end
    if not self.reading then return 'no_reading' end
  end

  function c:startPump(dir)
    if self:pumpBlocked() then return false end
    if not self.transfer:start(dir, self.clock) then return false end
    self.feedback = dir == 'toTruck' and 'Pumping from the bed tank into your truck.' or 'Pumping from your truck into the bed tank.'
    return true
  end

  function c:stopPump()
    if not self.transfer:active() then return false end
    self.feedback = self.transfer:finish('stopped', self.clock)
    self:applyBed(true)
    return true
  end

  -- Pours the bed tank's litres into the truck so it carries the weight; at most every few
  -- seconds while the pump runs, unless now.
  function c:applyBed(now)
    if not self.bed then return end
    if not (self.bedDirty or now) then return end
    if not now and self.bedAppliedAt and self.clock - self.bedAppliedAt < BED_APPLY_SECONDS then return end
    self.bedAppliedAt, self.bedDirty = self.clock, false
    self.bed:set(self.bedLitres)
  end

  -- Fills the bed tank with this many litres, at the start or back at a save.
  function c:fillBed(litres)
    self.bedLitres = location.finite(litres) and math.max(0, litres) or 0
    self:applyBed(true)
  end

  function c:followPump()
    if self.state ~= 'RUNNING' then
      if self.transfer:active() then self.feedback = self.transfer:finish('stopped', self.clock) end
      return
    end
    if self.bed and not (self.bedCapacity and self.bedCapacity > 0)
        and (not self.bedAskedAt or self.clock - self.bedAskedAt >= BED_READ_SECONDS) then
      self.bedAskedAt = self.clock
      self.bed:read()
    end
    local line = self.transfer:step(self.clock, self.reading, { litres = self.bedLitres, capacity = self.bedCapacity })
    if line then self.feedback = line; self:applyBed(true) else self:applyBed(false) end
  end

  -- The truck's answer: how much its bed tank holds (0 with none fitted).
  function c:bedRead(_, capacity)
    if not location.finite(capacity) or capacity < 0 then return end
    self.bedCapacity = capacity
    if capacity > 0 and self.bedLitres > capacity then self.bedLitres = capacity end
  end

  -- The flatscreen revolver is yours on the road when there is no VR session (in VR, the VR
  -- revolver mod shoots).
  function c:flatGun()
    return self.aim ~= nil and self.state == 'RUNNING' and not self.aim:vr()
  end

  function c:toggleRevolver()
    if not self:flatGun() then return false end
    self.gun:setDrawn(not self.gun.drawn)
    self.feedback = self.gun.drawn and 'Revolver drawn. Aim with the mouse and click to shoot.' or 'Revolver holstered.'
    return true
  end

  function c:reloadRevolver()
    if not self:flatGun() then return false end
    local ok, why = self.gun:reload(self.clock)
    self.feedback = ok and 'Reloading.' or why == 'full' and 'The cylinder is full.' or 'No spare rounds left.'
    return ok
  end

  -- Each frame: the crosshair while the revolver is drawn, and a shot on each click.
  function c:followAim()
    if self.gun.drawn and not self:flatGun() then self.gun:setDrawn(false) end
    if not self.gun.drawn then return end
    local shot = self.aim:aim()
    self.aim:draw(shot)
    -- A click on the HUD is not a shot.
    if self.hudHover or not self.aim:clicked() then return end
    local fired, why = self.gun:fire(self.clock)
    if not fired then
      if why == 'empty' then
        self.feedback = self.gun:reloading() and 'Click. Empty, reloading.' or 'Click. You are out of rounds.'
      end
      return
    end
    -- The hit, if any, comes back from the car a moment later (vrHit below).
    self.feedback, self.shotAt = 'Missed.', self.clock
    self.aim:shoot(shot)
  end

  -- A hit from either revolver, the VR one or the flatscreen one: they send the same events. A
  -- shot through the driver stops a Hoon at once; otherwise four hits do.
  function c:vrHit(vehId, driver)
    if not self.hoons and not self.pack then return end
    local line, wasHoon
    if self.hoons then
      if driver then line, wasHoon = self.hoons:driverShot(vehId) else line, wasHoon = self.hoons:shot(vehId) end
    end
    if not wasHoon and self.pack then
      if driver then line, wasHoon = self.pack:driverShot(vehId) else line, wasHoon = self.pack:shot(vehId) end
    end
    if line then
      self.feedback = line
      self.diag:event('hoon', driver and 'driver shot' or 'shot down')
    elseif self.shotAt and self.clock - self.shotAt < 2 then
      self.feedback = wasHoon and 'Hit the Hoon.' or 'Hit.'
    end
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
    if self.bed then p.vehicle.bedLitres = self.bedLitres end
    p.vehicle.ammo = self.gun:ammo()
    -- The parts paid for, so the truck comes back with them.
    if self.ownedParts and self.ownedParts.config then
      p.vehicle.config, p.vehicle.model = parts.copy(self.ownedParts.config), self.ownedParts.model or p.vehicle.model
    end
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
    -- Back at a save, the truck comes with the parts it was saved with.
    local saved = kind == 'resume' and self.profile and self.profile.vehicle or nil
    local ok, why, detail = self.vehicles and self.vehicles:spawnStarter(saved and saved.config, saved and saved.model)
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
      self.fuel:set(START_FUEL_LITRES, self.profile.generation)
      self.gun = revolver.new()
      self:fillBed(START_BED_LITRES)
      self:transition('RUNNING', 'started')
      if self:write() then self.feedback = 'The run has started. Head north for Pine Gap.' end
    else
      -- The tank goes back to what was saved, so quitting never refills it.
      local litres = self.profile.vehicle.fuelLitres
      if litres then self.fuel:set(litres, self.profile.generation) end
      self.gun = revolver.new(self.profile.vehicle.ammo)
      self:fillBed(self.profile.vehicle.bedLitres)
      self.feedback = 'Back where you saved.'
      self:transition('RUNNING', 'resumed')
    end
  end

  -- The game's onVehicleSpawned: the starter truck has arrived when the player's vehicle respawns.
  function c:vehicleSpawned(id)
    if not (self.vehicles and self.vehicles:isPlayer(id)) then return end
    if self.state == 'SPAWNING' then self:truckArrived()
    elseif self.state == 'RUNNING' and self.parts then self:truckRespawned() end
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
        self:fillBed(self.profile.vehicle.bedLitres)
        self.gun = revolver.new(self.profile.vehicle.ammo)
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
    self:followPack()
    self:followPump()
    if self.parts then self:followWorkshop() end
    self.fuel:read()
    local distances = env.hoonDistances and env.hoonDistances()
    if not distances then
      distances = {}
      for _, d in ipairs(self.hoons and self.hoons:distances() or {}) do distances[#distances + 1] = d end
      for _, d in ipairs(self.pack and self.pack:distances() or {}) do distances[#distances + 1] = d end
    end
    self.threat = threat.level(distances)
  end

  -- The truck's answer to fuel:read(). Litres going down while driving measure the range.
  function c:fuelReading(_, litres, capacity)
    if not (location.finite(litres) and location.finite(capacity)) or capacity <= 0 then return end
    -- A respawned truck reads full until its fuel is put back.
    if self.restoreFuel then return end
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
      newGameAllowed = self:newGameAllowed(),
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
    if self.bed and self.state == 'RUNNING' then
      v.bed = { litres = self.bedLitres, capacity = self.bedCapacity }
      if self.bedCapacity ~= nil then v.bed.fitted = self.bedCapacity > 0 end
      v.cargo = { litres = self.bedLitres, capacity = self.bedCapacity }
      v.pumpAllowed = self:pumpBlocked() == nil
      v.pumpStopAllowed = self.transfer:active()
      v.pumping = self.transfer:direction()
    end
    v.tankerSpawnAllowed = self.tankerMob ~= nil and self.state == 'RUNNING'
    if self.hoons then
      v.hoonTestAllowed = self.state == 'RUNNING' and self.hoons.state == 'HIDDEN'
      v.hoon = { state = self.hoons.state, metres = self.hoons:outId() and self.hoons.metres or nil }
    end
    if self.pack then
      v.addHoonAllowed = self.state == 'RUNNING' and #self.pack.hoons < pack.MAX
      v.clearHoonsAllowed = #self.pack.hoons > 0
      v.pack = { hoons = self.pack:view(), max = pack.MAX }
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
      -- The range counts the bed tank too: it is fuel you carry.
      local carried = self.reading.litres + (self.bed and self.bedLitres or 0)
      v.fuel = { litres = self.reading.litres, capacity = self.reading.capacity,
        rangeKm = fuel.range(carried, r.usedLitres, r.rangeKm) }
    end
    if self.parts then self:workshopView(v) end
    -- Your truck on the start page, like a character sheet.
    local card = self.vehicles and self.vehicles.describe and self.vehicles:describe()
    if card then
      local truck = {}
      for k, x in pairs(card) do truck[k] = x end
      local damage = self.lastDamage and self.lastDamage.damage
      if damage then truck.repair = pricing.repairCost(damage, self.ownedParts and self.ownedParts.value or card.value) end
      v.truck = truck
    end
    local gun = self.pistol:read()
    v.pistol = { installed = gun.installed, drawn = gun.drawn }
    if gun.loaded then v.ammo = { loaded = gun.loaded, spare = gun.spare } end
    -- Without VR, the flatscreen revolver's rounds are the ones that count.
    if self:flatGun() then
      v.ammo = self.gun:ammo()
      v.gun = { drawn = self.gun.drawn, reloading = self.gun:reloading(),
        noSpare = self.gun.spare <= 0 and self.gun.loaded < revolver.CYLINDER }
      v.revolverAllowed = true
      v.reloadAllowed = not self.gun:reloading() and self.gun.loaded < revolver.CYLINDER and self.gun.spare > 0
    end
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
    -- Every frame, before anything that can bail out: a reload always finishes on time, even
    -- while the truck's position can't be read.
    if self.gun:step(self.clock) then
      self.feedback = 'Reloaded.'
      self:publish()
    end
    if self.clock >= self.nextSample then
      self.nextSample = self.clock + SAMPLE_SECONDS
      self:sample()
      self:publish()
    end
    if self.watchCamera then self:watchCamera() end
    self:drawWrist()
  end

  function c:endMission()
    self.teleport = nil
  end

  -- Tanker going away puts back the rocks it hid.
  function c:shutdown()
    if self.hoons then self.hoons:remove() end
    if self.pack then self.pack:remove() end
    if self.tankerMob then self.tankerMob:remove() end
    if self.adapter.restoreRocks then self.adapter:restoreRocks() end
  end

  return c
end

-- --------------------------------------------------------------- the game's side ---

local active
-- The game's camera: from the free camera back to the truck's own (driver, chase, orbit...).
local function gameCamera()
  return {
    backToCar = function()
      local cmd = rawget(_G, 'commands')
      if type(cmd) ~= 'table' or type(cmd.isFreeCamera) ~= 'function' or type(cmd.setGameCamera) ~= 'function' then return false end
      if not cmd.isFreeCamera() then return false end
      cmd.setGameCamera()
      return true
    end,
  }
end
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
      vehicles = vehicle.new(), nearby = nearby.new(), hoonCar = hoonCar.new(), bed = bedTank.new(), parts = parts.new(),
      aim = aim.new(), tankerMob = tankerMob.new(hoonCar.new()), packCar = packCar.new(hoonCar.new()),
      log = rawget(_G, 'log'), drawTri = drawTri, camera = gameCamera(),
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
function M.newGame() return safely(function() return ensure():newGame() end) end
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
function M.bedRead(vehicleId, capacity) return safely(function() if active then active:bedRead(vehicleId, capacity) end end) end
function M.pumpToTruck() return safely(function() return ensure():startPump('toTruck') end) end
function M.pumpToBed() return safely(function() return ensure():startPump('toBed') end) end
function M.pumpStop() return safely(function() return ensure():stopPump() end) end
function M.payParts() return safely(function() return ensure():payParts() end) end
function M.payPartsBill() return safely(function() return ensure():payPartsBill() end) end
function M.undoParts() return safely(function() return ensure():undoParts(false) end) end
function M.toggleRevolver() return safely(function() return ensure():toggleRevolver() end) end
function M.reloadRevolver() return safely(function() return ensure():reloadRevolver() end) end
-- The crosshair and the shots, each frame (ImGui draws here).
-- The VR revolver's hit events (the flatscreen revolver sends the same ones).
function M.onVrPistolHit(vehId) return safely(function() if active then active:vrHit(vehId, false) end end) end
function M.onVrPistolDriverHit(vehId) return safely(function() if active then active:vrHit(vehId, true) end end) end
function M.hudHover(on) return safely(function() ensure().hudHover = on == true end) end
function M.onDrawDebug() return safely(function() if active and active.aim then active:followAim() end end) end
function M.spawnTanker() return safely(function() return ensure():spawnTanker() end) end
function M.sendHoon() return safely(function() return ensure():sendHoon() end) end
function M.addHoon() return safely(function() return ensure():addHoon() end) end
function M.clearHoons() return safely(function() return ensure():clearHoons() end) end
-- A desert Hoon's car could not follow its path (see packCar.lua).
function M.packProblem(vehId, what) return safely(function() if active then active:packProblem(vehId, what) end end) end
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
