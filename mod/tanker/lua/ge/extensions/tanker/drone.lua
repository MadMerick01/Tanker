-- Drone strikes on roads (MadMerick, 6 Nov): the rogue AI watches the world's road network. Stay on a
-- road for ROAD_SECONDS and it sends a drone: you hear it coming for INBOUND_SECONDS, then it
-- hits you, with an explosion beside your truck that damages it. Still on the road, the next one
-- comes AGAIN_SECONDS later. Off the road when it arrives, it misses. Off the road for
-- CLEAR_SECONDS, it loses you and the count starts again. This keeps the game off road: the Hoons
-- are at their best there, and you navigate by compass and build an off-road truck.
-- Crossing a road is safe: the count only shows after GRACE_SECONDS on it.
-- The logic and the game's side are both here; every game call is guarded, so a missing one means
-- no strike, never an error.
local M = {}

-- One-line settings. Tune these after testing in game.
-- On a road this long, in seconds, and the drone hits.
M.ROAD_SECONDS = 30
-- You hear the drone coming for this long before it hits.
M.INBOUND_SECONDS = 5
-- Still on the road after a strike, the next drone hits this many seconds later.
M.AGAIN_SECONDS = 20
-- Off the road for this long and the AI loses you.
M.CLEAR_SECONDS = 5
-- The countdown shows once you have been on a road this long.
M.GRACE_SECONDS = 5
-- On a road: within the road's half width plus ROAD_MARGIN metres of its middle, and at least
-- MIN_HALF_WIDTH (a road with no width recorded).
M.ROAD_MARGIN, M.MIN_HALF_WIDTH = 1.5, 3
-- The blast: a push away from a point BLAST_SIDE metres off one side of your truck, at the ground,
-- for BLAST_SECONDS, as BeamNG's own Explode does (a short burst of repulsion). BLAST_MASS sets
-- how hard (BeamNG's Explode uses about -3e13 under the car; this is about half, and beside it).
M.BLAST_SIDE, M.BLAST_SECONDS, M.BLAST_RADIUS, M.BLAST_MASS = 2.5, 0.2, 5, -1.5e13
-- The chance the blast also bursts a tyre.
M.TYRE_CHANCE = 0.5

local LINES = {
  watched = 'You\'re on a road. The rogue AI watches the roads: get off it or it sends a drone.',
  inbound = 'Drone inbound! Get off the road!',
  hit = 'A drone hit you. Stay off the roads.',
  missed = 'You got off the road in time. The drone missed you.',
  lost = 'Off the road, the AI has lost you.',
}
M.LINES = LINES

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    map = function() return rawget(_G, 'map') end,
    vec3 = function(x, y, z) return vec3(x, y, z) end,
    allObjects = function(cmd) if be and be.queueAllObjectLua then be:queueAllObjectLua(cmd) end end,
    random = math.random,
  }
end

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

function M.new(environment)
  local env = environment or defaults()
  local random = env.random or math.random
  -- state: CLEAR (not on a road), WATCHED (counting), INBOUND (you can hear it)
  local d = { state = 'CLEAR', strikes = 0, misses = 0 }

  local function car()
    local ok, c = pcall(env.player)
    if ok and c then return c end
  end

  -- Whether the player's car is on a road now, and where it is.
  function d:onRoad()
    local c = car()
    if not c then return false end
    local okPos, pos = pcall(function() return c:getPosition() end)
    if not (okPos and pos and finite(pos.x) and finite(pos.y) and finite(pos.z)) then return false end
    local okMap, map = pcall(env.map)
    if not (okMap and type(map) == 'table' and type(map.findClosestRoad) == 'function' and type(map.getMap) == 'function') then
      return false
    end
    local okV, v = pcall(env.vec3, pos.x, pos.y, pos.z)
    if not okV then return false end
    local ok, a, b = pcall(map.findClosestRoad, v)
    if not ok or not a then return false end
    local okNodes, nodes = pcall(function() return map.getMap().nodes end)
    local na, nb = okNodes and type(nodes) == 'table' and nodes[a], okNodes and type(nodes) == 'table' and b and nodes[b]
    if not (na and na.pos) then return false end
    nb = (nb and nb.pos) and nb or na
    local ax, ay, bx, by = na.pos.x, na.pos.y, nb.pos.x, nb.pos.y
    local sx, sy = bx - ax, by - ay
    local len2 = sx * sx + sy * sy
    local t = len2 > 1e-9 and math.max(0, math.min(1, ((pos.x - ax) * sx + (pos.y - ay) * sy) / len2)) or 0
    local px, py = ax + sx * t, ay + sy * t
    local metres = math.sqrt((pos.x - px) ^ 2 + (pos.y - py) ^ 2)
    local ra, rb = tonumber(na.radius) or 0, tonumber(nb.radius) or 0
    local half = math.max(M.MIN_HALF_WIDTH, ra + (rb - ra) * t)
    return metres <= half + M.ROAD_MARGIN
  end

  -- The blast beside the player's truck: on, then off BLAST_SECONDS later (blastOff).
  function d:blast(clock)
    local c = car()
    if not c then return false end
    local ok = pcall(function()
      local pos, dir = c:getPosition(), c:getDirectionVector()
      local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
      local rx, ry = 1, 0
      if len > 1e-6 then rx, ry = dir.y / len, -dir.x / len end
      local side = random() < 0.5 and -1 or 1
      local x, y, z = pos.x + rx * side * M.BLAST_SIDE, pos.y + ry * side * M.BLAST_SIDE, pos.z - 0.5
      env.allObjects(string.format('obj:setPlanets({%f, %f, %f, %d, %f})', x, y, z, M.BLAST_RADIUS, M.BLAST_MASS))
      if random() < M.TYRE_CHANCE then c:queueLuaCommand('beamstate.deflateRandomTire()') end
    end)
    if ok then self.blastUntil = clock + M.BLAST_SECONDS end
    return ok
  end
  function d:blastOff()
    self.blastUntil = nil
    pcall(env.allObjects, 'obj:setPlanets({})')
  end

  -- Called every half second while the run is on the road (and every frame, for the blast to end
  -- on time). road: whether you are on a road now. Returns a line to show, if any.
  function d:step(clock, road)
    if self.blastUntil and clock >= self.blastUntil then self:blastOff() end
    if road then
      self.offSince = nil
      self.since = self.since or clock
    elseif self.since then
      self.offSince = self.offSince or clock
      if clock - self.offSince >= M.CLEAR_SECONDS then
        local was = self.state
        self.since, self.offSince, self.state, self.warned = nil, nil, 'CLEAR', nil
        if was ~= 'CLEAR' and self.shown then self.shown = nil; return LINES.lost end
        return nil
      end
    end
    if not self.since then return nil end
    local on = clock - self.since
    if on >= M.ROAD_SECONDS then
      -- It arrives: a hit if you are on the road, a miss if you got off it.
      self.since, self.state, self.warned = clock - (M.ROAD_SECONDS - M.AGAIN_SECONDS), 'WATCHED', true
      if road then
        self.strikes = self.strikes + 1
        self:blast(clock)
        return LINES.hit
      end
      self.misses = self.misses + 1
      self.since, self.offSince, self.state = nil, nil, 'CLEAR'
      return LINES.missed
    end
    if on >= M.ROAD_SECONDS - M.INBOUND_SECONDS then
      if self.state ~= 'INBOUND' then self.state = 'INBOUND'; self.shown = true; return LINES.inbound end
      return nil
    end
    self.state = 'WATCHED'
    if on >= M.GRACE_SECONDS and not self.warned then
      self.warned, self.shown = true, true
      return LINES.watched
    end
  end

  -- Ends the watch (a new run, the run stopping, Tanker going away).
  function d:clear()
    if self.blastUntil then self:blastOff() end
    self.since, self.offSince, self.state, self.warned, self.shown = nil, nil, 'CLEAR', nil, nil
  end

  -- What the HUD shows: the countdown once it matters, and counters the HUD plays sounds on.
  function d:view(clock)
    local v = { strikes = self.strikes, misses = self.misses }
    if self.since and clock - self.since >= M.GRACE_SECONDS then
      v.state = self.state
      v.seconds = math.max(0, M.ROAD_SECONDS - (clock - self.since))
      v.offRoad = self.offSince ~= nil
    end
    return v
  end

  return d
end

return M
