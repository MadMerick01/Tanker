-- The Hoon pack, desert mode: Hoons that come for you off road. Each Hoon moves between eight
-- slots around your truck, named as on Rowan's diagram: L or R (your left or right), F or R
-- (front or rear), then N or F (near or far). RFF is right, front, far; LRN is left, rear, near.
--
--   LFF . . . . . . . . RFF       far: 60 m out to the side, 10 m beyond your front or back
--         LFN  []  RFN            near: 10 m out to the side, level with your front or back
--         LRN  []  RRN
--   LRF . . . . . . . . RRF
--
-- A new Hoon sizes you up first, circling the far slots like a hyena, then closes in to a near
-- slot, lines up and attacks. Some attacks swipe you and drive back out to a far slot; others try
-- to box you in, one Hoon getting in front and slowing down while another sits beside you, to
-- stop you for your fuel. Only one Hoon attacks at a time; the rest hold their slots and wait.
-- This is the logic only; packCar.lua does the game's side.
local M = {}

-- One-line settings. Tune these after testing in game.
-- At most this many pack Hoons at once.
M.MAX = 4
-- The slots: near is NEAR_SIDE metres out to the side, level with your front or back; far is
-- FAR_SIDE metres out and FAR_BEYOND metres beyond your front or back. HALF_LENGTH is half your
-- truck's length, from its middle to its front or back.
M.NEAR_SIDE, M.FAR_SIDE, M.FAR_BEYOND, M.HALF_LENGTH = 10, 60, 10, 3
-- A Hoon is at a far slot within this many metres of it, at a near slot within NEAR_ARRIVE.
M.FAR_ARRIVE, M.NEAR_ARRIVE = 15, 6
-- How much faster than you a Hoon closes on its slot, in metres a second, and the shortest
-- time it is given to get there, in seconds.
M.CATCH_UP_MPS, M.MIN_LEG_SECONDS = 12, 2
-- How often a Hoon's path to its slot is worked out again, in seconds.
M.REPLAN_SECONDS = 1
-- Crossing in front of or behind you from one side to the other, a Hoon swings this many metres
-- further out ahead or behind, so it doesn't cut across your nose.
M.CROSS_METRES = 30
-- How long a Hoon waits at a far slot, then at a near slot, in seconds (picked between the two).
M.HOLD_FAR, M.HOLD_NEAR = { 2, 5 }, { 1.5, 3 }
-- How many far slots a new Hoon circles through before closing in (picked between the two). A
-- bold one (BOLD_CHANCE of them) moves in after one at most. After an attack it circles 0 to 2.
M.CIRCLES, M.BOLD_CHANCE, M.CIRCLES_AFTER = { 2, 6 }, 0.3, { 0, 2 }
-- Before it strikes, a Hoon edges in to this many metres off your side for WINDUP_SECONDS, so
-- you can see it coming.
M.WINDUP_SIDE, M.WINDUP_SECONDS = 6, 1.5
-- A swipe is BeamNG's chase AI aimed at you for up to SWIPE_SECONDS; within CONTACT_METRES it
-- has hit you, and it peels off AFTER_CONTACT_SECONDS later.
M.SWIPE_SECONDS, M.CONTACT_METRES, M.AFTER_CONTACT_SECONDS = 4, 5, 1
-- This share of attacks are a box instead of a swipe. The lead Hoon gets BOX_AHEAD metres in
-- front of you and drives at BOX_SLOW of your speed; a second Hoon, if there is one, sits
-- BOX_SIDE metres off your side. A box lasts up to BOX_SECONDS. Slower than STOPPED_MPS for
-- BOXED_SECONDS and you are boxed in; they hold you there for BOX_HOLD_SECONDS, then peel off.
M.BOX_CHANCE, M.BOX_AHEAD, M.BOX_SLOW, M.BOX_SIDE = 0.35, 8, 0.6, 4
M.BOX_SECONDS, M.STOPPED_MPS, M.BOXED_SECONDS, M.BOX_HOLD_SECONDS = 15, 2, 3, 5
-- A Hoon going slower than STUCK_MPS for DOWN_SECONDS while you drive is down. You must be going
-- at least DRIVING_MPS for that to count, since Hoons wait when you stop.
M.STUCK_MPS, M.DOWN_SECONDS, M.DRIVING_MPS = 1, 12, 3
-- Further than ESCAPE_METRES from you for ESCAPE_SECONDS, and you have lost it.
M.ESCAPE_METRES, M.ESCAPE_SECONDS = 1500, 30
-- A downed Hoon is given back once you are this far from it.
M.LEAVE_METRES = 600
-- This many hits from your revolver stop a Hoon.
M.SHOTS_TO_STOP = 4

-- side: -1 left, 1 right. ahead: 1 front, -1 rear.
M.SLOTS = {
  LFF = { side = -1, ahead = 1, far = true }, RFF = { side = 1, ahead = 1, far = true },
  RRF = { side = 1, ahead = -1, far = true }, LRF = { side = -1, ahead = -1, far = true },
  LFN = { side = -1, ahead = 1 }, RFN = { side = 1, ahead = 1 },
  RRN = { side = 1, ahead = -1 }, LRN = { side = -1, ahead = -1 },
}
-- The far slots in a ring, clockwise seen from above, for circling.
M.RING = { 'LFF', 'RFF', 'RRF', 'LRF' }

local WHERE = { L = 'left', R = 'right' }
local function where(slot)
  return WHERE[slot:sub(1, 1)] .. ' ' .. (slot:sub(2, 2) == 'F' and 'front' or 'rear')
end
M.DOING = {
  CIRCLING = 'sizing you up', CLOSING = 'closing in', WINDUP = 'lining up', SWIPE = 'attacking',
  PEEL = 'peeling off', BOXING = 'boxing you in, in front', BOX_SIDE = 'boxing you in, beside you', DOWN = 'down',
}
local LINES = {
  arrived = function(slot) return 'A Hoon has turned up out on your ' .. where(slot) .. '. It is sizing you up.' end,
  windup = function(slot) return 'A Hoon is lining up on your ' .. where(slot) .. '!' end,
  box = 'A Hoon is getting in front of you to box you in!',
  boxed = 'The Hoons have boxed you in.',
  swiped = 'The Hoon hit you and peeled off.',
  missed = 'The Hoon missed and peeled off.',
  down = 'A Hoon is down. Siphon its tank before the others come.',
  shotDown = 'You shot a Hoon to a stop. Siphon its tank before the others come.',
  driverShot = 'You shot a Hoon\'s driver. Siphon its tank before the others come.',
  escaped = 'You lost a Hoon.',
  gone = 'A Hoon is gone.',
  full = 'That\'s as many Hoons as there can be at once.',
  cleared = 'The Hoons are gone.',
}
M.LINES = LINES

local function distance2d(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The slot's offset from your middle: metres to your right, metres ahead.
function M.offset(slot)
  local s = M.SLOTS[slot]
  local side = s.far and M.FAR_SIDE or M.NEAR_SIDE
  local ahead = M.HALF_LENGTH + (s.far and M.FAR_BEYOND or 0)
  return s.side * side, s.ahead * ahead
end

-- Where an offset (right, ahead) from you will be in t seconds, if you keep going at speed.
function M.at(me, right, ahead, t, speed)
  local go = (speed or me.speed or 0) * (t or 0) + ahead
  return me.x + me.dx * go + me.dy * right, me.y + me.dy * go - me.dx * right
end

local function near(slot) return slot:sub(1, 2) .. 'N' end
local function far(slot) return slot:sub(1, 2) .. 'F' end

-- car is packCar (or a fake), random(lo, hi) a number between them.
function M.new(car, random)
  random = random or function(lo, hi) return lo + math.random() * (hi - lo) end
  local p = { hoons = {}, count = 0 }

  local function pick(range) return random(range[1], range[2]) end
  local function whole(range) return math.min(range[2], math.floor(random(range[1], range[2] + 1))) end
  local function chance(share) return random(0, 1) < share end

  -- Whether a slot is taken by another Hoon that is still up.
  local function taken(slot, except)
    for _, h in ipairs(p.hoons) do
      if h ~= except and h.state ~= 'DOWN' and h.slot == slot then return true end
    end
    return false
  end
  local function strikers()
    local n = 0
    for _, h in ipairs(p.hoons) do
      if h.state == 'WINDUP' or h.state == 'SWIPE' or h.state == 'BOXING' then n = n + 1 end
    end
    return n
  end
  local function ringIndex(slot)
    for i, s in ipairs(M.RING) do if s == slot then return i end end
  end
  local function freeFar(except)
    local free = {}
    for _, s in ipairs(M.RING) do if not taken(s, except) then free[#free + 1] = s end end
    return free
  end

  -- The offset a Hoon drives to now, and the speed factor and crossing point on the way.
  local function target(h)
    if h.state == 'BOXING' then return 0, M.HALF_LENGTH + M.BOX_AHEAD, M.BOX_SLOW end
    if h.state == 'BOX_SIDE' then return h.side * M.BOX_SIDE, 0, M.BOX_SLOW end
    local right, ahead = M.offset(h.slot)
    if h.state == 'WINDUP' then right = M.SLOTS[h.slot].side * M.WINDUP_SIDE end
    return right, ahead, 1
  end

  -- Sends the Hoon its path: from where it is, maybe round the front or back, to its slot, then
  -- on beside you at your speed, so it keeps pace once there.
  local function drive(h, me, st, clock)
    if h.replanAt and clock < h.replanAt then return end
    h.replanAt = clock + M.REPLAN_SECONDS
    local right, ahead, slow = target(h)
    local speed = (me.speed or 0) * slow
    local tx, ty = M.at(me, right, ahead, 0, speed)
    local leg = math.max(M.MIN_LEG_SECONDS, distance2d(st.x, st.y, tx, ty) / M.CATCH_UP_MPS)
    local points = { { x = st.x, y = st.y, z = st.z, t = 0 } }
    local function add(r, a, t)
      local x, y = M.at(me, r, a, t, speed)
      points[#points + 1] = { x = x, y = y, z = car:ground(x, y, me.z) or me.z, t = t }
    end
    -- Crossing to the other side: swing out further ahead or behind, halfway there.
    local hr, ha = st.right or 0, st.ahead or 0
    if hr * right < 0 and math.abs(hr) > M.NEAR_SIDE and math.abs(right) > M.NEAR_SIDE then
      local sign = (ahead + ha) >= 0 and 1 or -1
      add(0, sign * (math.max(math.abs(ahead), math.abs(ha)) + M.CROSS_METRES), leg / 2)
    end
    add(right, ahead, leg)
    add(right, ahead, leg + 3)
    add(right, ahead, leg + 6)
    car:goTo(h.id, points)
  end

  -- Where the Hoon is from you: metres to your right and ahead.
  local function relative(me, st)
    local x, y = st.x - me.x, st.y - me.y
    st.ahead = x * me.dx + y * me.dy
    st.right = x * me.dy - y * me.dx
  end

  local function arrived(h, me, st)
    local right, ahead = target(h)
    local x, y = M.at(me, right, ahead, 0)
    local reach = (h.state == 'CIRCLING' or h.state == 'PEEL') and M.FAR_ARRIVE or M.NEAR_ARRIVE
    return distance2d(st.x, st.y, x, y) <= reach
  end

  local function peel(h, clock)
    local back = h.slot and far(h.slot)
    if not back or taken(back, h) then
      local free = freeFar(h)
      back = free[1] or back or M.RING[1]
    end
    h.state, h.slot, h.holdUntil, h.replanAt, h.side, h.lead = 'PEEL', back, nil, nil, nil, nil
    h.movesLeft = whole(M.CIRCLES_AFTER)
    h.since = clock
  end

  -- Gives the car back (to traffic, or hidden for next time) and forgets the Hoon.
  local function release(h)
    car:release(h.id, h.source)
    for i, other in ipairs(p.hoons) do
      if other == h then table.remove(p.hoons, i) break end
    end
    for _, other in ipairs(p.hoons) do
      if other.lead == h then peel(other, 0) end
    end
  end

  local function down(h, line)
    h.state, h.slot = 'DOWN', nil
    car:calm(h.id)
    for _, other in ipairs(p.hoons) do
      if other.lead == h then peel(other, 0) end
    end
    return line
  end

  -- Brings in one more Hoon at a free far slot, from traffic or the Hoon's own car. Returns the
  -- line to show, or nil and why not.
  function p:add(clock)
    if #self.hoons >= M.MAX then return nil, 'full' end
    local me = car:player()
    if not me then return nil, 'no_player' end
    local free = freeFar()
    if #free == 0 then return nil, 'full' end
    local slot = free[math.min(#free, math.floor(random(1, #free + 1)))]
    local id, source = car:take(me)
    if not id then return nil, source or 'no_car' end
    local right, ahead = M.offset(slot)
    local x, y = M.at(me, right, ahead, 0)
    local z = car:ground(x, y, me.z) or me.z
    local ok, why = car:place(id, x, y, z, me.dx, me.dy)
    if not ok then
      car:release(id, source)
      return nil, why
    end
    self.count = self.count + 1
    local h = { n = self.count, id = id, source = source, state = 'CIRCLING', slot = slot, since = clock,
      hits = 0, dir = chance(0.5) and 1 or -1 }
    h.movesLeft = chance(M.BOLD_CHANCE) and whole({ 0, 1 }) or whole(M.CIRCLES)
    self.hoons[#self.hoons + 1] = h
    return LINES.arrived(slot)
  end

  -- One Hoon's next move.
  local function think(h, me, st, clock)
    local line
    if h.state == 'CIRCLING' or h.state == 'PEEL' then
      if h.state == 'PEEL' and arrived(h, me, st) then h.state = 'CIRCLING' end
      if h.state == 'CIRCLING' then
        if not h.holdUntil and arrived(h, me, st) then h.holdUntil = clock + pick(M.HOLD_FAR) end
        if h.holdUntil and clock >= h.holdUntil then
          h.holdUntil = nil
          if h.movesLeft > 0 then
            local i = ringIndex(h.slot) or 1
            local nextSlot = M.RING[(i - 1 + h.dir) % 4 + 1]
            if taken(nextSlot, h) then
              h.dir = -h.dir
              nextSlot = M.RING[(i - 1 + h.dir) % 4 + 1]
            end
            if not taken(nextSlot, h) then h.slot, h.replanAt = nextSlot, nil end
            h.movesLeft = h.movesLeft - 1
          elseif not taken(near(h.slot), h) then
            h.state, h.slot, h.replanAt, h.since = 'CLOSING', near(h.slot), nil, clock
          else
            h.holdUntil = clock + 1
          end
        end
      end
    elseif h.state == 'CLOSING' then
      if not h.holdUntil and arrived(h, me, st) then h.holdUntil = clock + pick(M.HOLD_NEAR) end
      if h.holdUntil and clock >= h.holdUntil then
        h.holdUntil = nil
        if strikers() > 0 then
          h.holdUntil = clock + 1
        elseif chance(M.BOX_CHANCE) then
          h.state, h.since, h.replanAt, h.boxedSince, h.holdTill = 'BOXING', clock, nil, nil, nil
          -- The nearest other Hoon still up and not attacking sits beside you.
          local helper, best
          for _, o in ipairs(p.hoons) do
            if o ~= h and (o.state == 'CIRCLING' or o.state == 'CLOSING' or o.state == 'PEEL') and o.metres then
              if not best or o.metres < best then helper, best = o, o.metres end
            end
          end
          if helper then
            helper.state, helper.lead, helper.replanAt, helper.holdUntil = 'BOX_SIDE', h, nil, nil
            helper.side = helper.slot and M.SLOTS[helper.slot].side or 1
            helper.slot = nil
          end
          line = LINES.box
        else
          h.state, h.since, h.replanAt = 'WINDUP', clock, nil
          line = LINES.windup(h.slot)
        end
      end
    elseif h.state == 'WINDUP' then
      if clock - h.since >= M.WINDUP_SECONDS then
        h.state, h.since, h.contactAt = 'SWIPE', clock, nil
        car:strike(h.id, me.id)
      end
    elseif h.state == 'SWIPE' then
      if not h.contactAt and h.metres and h.metres <= M.CONTACT_METRES then h.contactAt = clock end
      if h.contactAt and clock - h.contactAt >= M.AFTER_CONTACT_SECONDS then
        peel(h, clock); line = LINES.swiped
      elseif clock - h.since >= M.SWIPE_SECONDS then
        peel(h, clock); line = LINES.missed
      end
    elseif h.state == 'BOXING' then
      if (me.speed or 0) < M.STOPPED_MPS then h.boxedSince = h.boxedSince or clock else h.boxedSince = nil end
      if h.boxedSince and not h.holdTill and clock - h.boxedSince >= M.BOXED_SECONDS then
        h.holdTill = clock + M.BOX_HOLD_SECONDS
        line = LINES.boxed
      end
      if (h.holdTill and clock >= h.holdTill) or (not h.holdTill and clock - h.since >= M.BOX_SECONDS) then
        for _, o in ipairs(p.hoons) do if o.lead == h then peel(o, clock) end end
        peel(h, clock)
      end
    end
    if h.state ~= 'SWIPE' and h.state ~= 'DOWN' then drive(h, me, st, clock) end
    return line
  end

  -- Called every half second while the run is on the road. Returns a line to show when something
  -- happens.
  function p:step(clock)
    if #self.hoons == 0 then return nil end
    local me = car:player()
    if not me then return nil end
    local line
    for _, h in ipairs({ unpack(self.hoons) }) do
      local st = car:state(h.id)
      if not st then
        release(h); line = LINES.gone
      else
        relative(me, st)
        h.metres = distance2d(me.x, me.y, st.x, st.y)
        if h.state == 'DOWN' then
          if h.metres > M.LEAVE_METRES then release(h) end
        else
          local driving = (me.speed or 0) >= M.DRIVING_MPS
          if driving and st.speed < M.STUCK_MPS then h.slow = h.slow or clock else h.slow = nil end
          if h.metres > M.ESCAPE_METRES then h.far = h.far or clock else h.far = nil end
          if h.slow and clock - h.slow >= M.DOWN_SECONDS then
            line = down(h, LINES.down)
          elseif h.far and clock - h.far >= M.ESCAPE_SECONDS then
            release(h); line = LINES.escaped
          else
            line = think(h, me, st, clock) or line
          end
        end
      end
    end
    return line
  end

  local function find(id)
    for _, h in ipairs(p.hoons) do if h.id == id and h.state ~= 'DOWN' then return h end end
  end

  -- A round from your revolver hit car id. Returns a line when it stops a Hoon, and whether the
  -- car was one of the pack.
  function p:shot(id)
    local h = find(id)
    if not h then return nil, false end
    h.hits = h.hits + 1
    if h.hits < M.SHOTS_TO_STOP then return nil, true end
    return down(h, LINES.shotDown), true
  end

  function p:driverShot(id)
    local h = find(id)
    if not h then return nil, false end
    return down(h, LINES.driverShot), true
  end

  -- Distances of the Hoons still up, for the threat light.
  function p:distances()
    local d = {}
    for _, h in ipairs(self.hoons) do
      if h.state ~= 'DOWN' and h.metres then d[#d + 1] = h.metres end
    end
    return #d > 0 and d or nil
  end

  -- For the HUD: each Hoon, its slot and what it is doing.
  function p:view()
    local list = {}
    for _, h in ipairs(self.hoons) do
      list[#list + 1] = { n = h.n, slot = h.slot, doing = M.DOING[h.state], state = h.state, metres = h.metres }
    end
    return list
  end

  -- Sends every Hoon away: the clear button, a new run, or Tanker going away.
  function p:clear()
    for _, h in ipairs({ unpack(self.hoons) }) do release(h) end
  end

  function p:remove()
    self:clear()
    car:removeAll()
  end

  return p
end

return M
