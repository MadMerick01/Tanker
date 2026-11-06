-- The Hoons: when they come, how they hunt, and when it is over. For now there is one Hoon, a
-- muscle car whose car is loaded once when the run is on the road and then kept hidden. Every few
-- km of driving near a road it is put on the road behind you and hunts you, ramming. It is over
-- when the Hoon is down (stuck or wrecked, so its tank is yours to siphon) or when you get away.
-- This is the logic only; hoonCar.lua does the game's side.
local M = {}

-- One-line settings. Tune these after testing in game.
-- The first Hoon comes this many km after the run starts or the game loads.
M.FIRST_KM = 3
-- Then one comes every this many km of driving, picked at random between the two.
M.GAP_MIN_KM, M.GAP_MAX_KM = 6, 14
-- Hoons only come while you are driving within this many metres of a road: never off road.
M.ROAD_METRES = 30
-- Where the Hoon is put: this far behind you on the road, or ahead if there is no solid road
-- behind. Close, because BeamNG.Earth's road further away may not have loaded.
M.PLACE_METRES = 250
-- The road point must be within this many metres of that spot, and the Hoon never closer than
-- MIN_START_METRES to you.
M.SNAP_METRES = 80
M.MIN_START_METRES = 150
-- You must be going at least this fast, in metres a second, for a Hoon to come.
M.DRIVING_MPS = 3
-- A Hoon going slower than this for DOWN_SECONDS is down.
M.STUCK_MPS, M.DOWN_SECONDS = 1, 12
-- Further than ESCAPE_METRES from you for ESCAPE_SECONDS, and you have got away.
M.ESCAPE_METRES, M.ESCAPE_SECONDS = 1500, 30
-- A hunt that lasts this long without catching you ends anyway.
M.HUNT_SECONDS = 300
-- A downed Hoon is put away once you are this far from it.
M.LEAVE_METRES = 600
-- A downed Hoon with fuel still in its tank waits for you to come back and siphon it again,
-- until you are this far from it. Once its tank is siphoned dry, LEAVE_METRES applies.
M.KEEP_METRES = 2000
-- If a Hoon can't be placed, try again after this many seconds.
M.RETRY_SECONDS = 10
-- The spawn button puts the Hoon this far behind you when there is no road to put it on.
M.SPAWN_METRES = 40
-- This many hits from your revolver stop a hunting Hoon.
M.SHOTS_TO_STOP = 4

local LINES = {
  coming = 'A Hoon is coming up behind you.',
  ahead = 'A Hoon is coming at you from up the road.',
  down = 'The Hoon is down. Siphon its tank before more come.',
  shotDown = 'You shot the Hoon to a stop. Siphon its tank before more come.',
  driverShot = 'You shot the Hoon\'s driver. Siphon its tank before more come.',
  escaped = 'You lost the Hoon.',
  tired = 'The Hoon gave up.',
  gone = 'The Hoon is gone.',
}
M.LINES = LINES

local function distance(a, b)
  if not (a and b) then return nil end
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

-- car is hoonCar (or a fake), random(lo, hi) a number between them.
function M.new(car, random)
  random = random or function(lo, hi) return lo + math.random() * (hi - lo) end
  local s = { state = 'NONE' }

  function s:gap() return random(M.GAP_MIN_KM, M.GAP_MAX_KM) end

  -- Loads the Hoon's car once. Returns a problem to log, if any.
  function s:load(drivenKm)
    if self.state ~= 'NONE' then return nil end
    local id, why, detail = car:load()
    if not id then
      self.state = 'UNAVAILABLE'
      return tostring(why) .. (detail and (': ' .. detail) or '')
    end
    self.id, self.model, self.state = id, why, 'HIDDEN'
    self.nextKm = (drivenKm or 0) + M.FIRST_KM
    return nil
  end

  function s:hunting() return self.state == 'HUNTING' end

  -- Sends the Hoon now, if it can be placed. Returns the line to show, or nil and why not.
  -- anywhere (the spawn button) sends it even off road: on a road nearby if there is one, or
  -- else straight behind you on the ground.
  function s:send(clock, anywhere)
    if self.state ~= 'HIDDEN' then return nil, 'not_ready' end
    local me = car:player()
    if not me then return nil, 'no_player' end
    local near = car:road(me.x, me.y, me.z)
    if not anywhere and (not near or near.metres > M.ROAD_METRES) then return nil, 'off_road' end
    -- Behind first, then ahead: a road point near the spot, far enough away, with solid ground.
    local road, line
    for _, side in ipairs({ { -1, LINES.coming }, { 1, LINES.ahead } }) do
      local x, y = me.x + side[1] * me.dx * M.PLACE_METRES, me.y + side[1] * me.dy * M.PLACE_METRES
      local r = car:road(x, y, me.z)
      if r and r.metres <= M.SNAP_METRES and distance(r, me) >= M.MIN_START_METRES and car:solid(r.x, r.y, r.z) then
        road, line = r, side[2]
        break
      end
    end
    if not road and anywhere then
      local x, y = me.x - me.dx * M.SPAWN_METRES, me.y - me.dy * M.SPAWN_METRES
      local z = car.ground and car:ground(x, y, me.z) or me.z
      road, line = { x = x, y = y, z = z or me.z }, LINES.coming
    end
    if not road then return nil, 'no_solid_road' end
    local ok, why = car:attack(self.id, road.x, road.y, road.z, me.id)
    if not ok then return nil, why end
    self.state, self.since, self.far, self.slow, self.hits = 'HUNTING', clock, nil, nil, 0
    return line
  end

  -- Puts the Hoon away and picks when the next one comes.
  function s:putAway(drivenKm)
    car:hide(self.id)
    self.state, self.dry = 'HIDDEN', nil
    self.nextKm = (drivenKm or 0) + self:gap()
  end

  -- Called every half second while the run is on the road. Returns a line to show when something
  -- happens.
  function s:step(clock, drivenKm)
    if self.state == 'HIDDEN' then
      if (drivenKm or 0) < (self.nextKm or math.huge) then return nil end
      if self.retryAt and clock < self.retryAt then return nil end
      local me = car:player()
      if not (me and me.speed >= M.DRIVING_MPS) then return nil end
      local line = self:send(clock)
      self.retryAt = not line and clock + M.RETRY_SECONDS or nil
      return line
    end
    if self.state ~= 'HUNTING' and self.state ~= 'DOWN' then return nil end
    local me, hoon = car:player(), car:state(self.id)
    if not hoon then
      self.state = 'HIDDEN'
      self.nextKm = (drivenKm or 0) + self:gap()
      return LINES.gone
    end
    local metres = distance(me, hoon)
    self.metres = metres
    if self.state == 'DOWN' then
      if metres and metres > (self.dry and M.LEAVE_METRES or M.KEEP_METRES) then self:putAway(drivenKm) end
      return nil
    end
    if hoon.speed < M.STUCK_MPS then self.slow = self.slow or clock else self.slow = nil end
    if metres and metres > M.ESCAPE_METRES then self.far = self.far or clock else self.far = nil end
    if self.slow and clock - self.slow >= M.DOWN_SECONDS then
      self.state = 'DOWN'
      car:calm(self.id)
      return LINES.down
    end
    if self.far and clock - self.far >= M.ESCAPE_SECONDS then
      self:putAway(drivenKm)
      return LINES.escaped
    end
    if clock - self.since >= M.HUNT_SECONDS then
      self:putAway(drivenKm)
      return LINES.tired
    end
  end

  -- A round from your revolver hit car id. Returns a line when it stops the Hoon, and whether
  -- the car was the Hoon.
  function s:shot(id)
    if self.state ~= 'HUNTING' or id ~= self.id then return nil, false end
    self.hits = (self.hits or 0) + 1
    if self.hits < M.SHOTS_TO_STOP then return nil, true end
    self.state = 'DOWN'
    car:calm(self.id)
    return LINES.shotDown, true
  end

  -- A shot through the Hoon's driver: its AI is already off, so it is down at once.
  function s:driverShot(id)
    if self.state ~= 'HUNTING' or id ~= self.id then return nil, false end
    self.state = 'DOWN'
    car:calm(self.id)
    return LINES.driverShot, true
  end

  -- A siphon found car id's tank dry. Returns whether it was the downed Hoon.
  function s:siphonedDry(id)
    if self.state ~= 'DOWN' or id ~= self.id then return false end
    self.dry = true
    return true
  end

  -- Distances of the Hoons hunting you, for the threat light.
  function s:distances()
    if self.state == 'HUNTING' and self.metres then return { self.metres } end
    return nil
  end

  -- The car's id while it is out (hunting or down), so the HUD can say which car is the Hoon.
  function s:outId()
    if self.state == 'HUNTING' or self.state == 'DOWN' then return self.id end
  end

  function s:remove()
    if self.id then car:remove(self.id) end
    self.id, self.state = nil, 'NONE'
  end

  return s
end

return M
