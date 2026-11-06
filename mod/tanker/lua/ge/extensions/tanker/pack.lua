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
-- to box you in as a team: one Hoon gets in front and the others close in on both sides and
-- behind, then they all slow down together to stop you for your fuel. Only one attack happens at
-- a time; Hoons not in it hold their slots and wait.
-- This is the logic only; packCar.lua does the game's side.
local M = {}

-- One-line settings. Tune these after testing in game.
-- At most this many pack Hoons at once.
M.MAX = 4
-- The slots: near is NEAR_SIDE metres out to the side, level with your front or back; far is
-- FAR_SIDE metres out and FAR_BEYOND metres beyond your front or back. HALF_LENGTH is half your
-- truck's length, from its middle to its front or back.
M.NEAR_SIDE, M.FAR_SIDE, M.FAR_BEYOND, M.HALF_LENGTH = 10, 60, 10, 3
-- The rear far slots (LRF, RRF) sit only this far out, so a Hoon behind you stays close (Rowan,
-- 6 Nov): about 30 m from you.
M.REAR_FAR_SIDE = 30
-- A Hoon is at a far slot within this many metres of it, at a near slot within NEAR_ARRIVE.
M.FAR_ARRIVE, M.NEAR_ARRIVE = 15, 6
-- Driving to a slot uses Tanker's own desert driver in the car (tankerDriver.lua), fed a new
-- point and speed every STEER_SECONDS (it brakes to a stop if it gets none for 0.6 s).
-- The speed is yours, plus GAIN metres a second for every metre the Hoon is behind its slot
-- along your heading (less if it is ahead), plus SIDE_GAIN for every metre it is out to the
-- side, but never more than CATCH_UP_MPS faster than you. The point is LEAD_SECONDS of your
-- speed beyond the slot (between MIN_LEAD and MAX_LEAD metres), so the Hoon runs alongside you
-- instead of turning in at the slot.
M.STEER_SECONDS = 0.2
M.GAIN, M.SIDE_GAIN, M.CATCH_UP_MPS = 0.6, 0.15, 15
M.LEAD_SECONDS, M.MIN_LEAD, M.MAX_LEAD = 1, 6, 25
-- Crossing in front of or behind you from one side to the other, a Hoon swings this many metres
-- further out ahead or behind, so it doesn't cut across your nose.
M.CROSS_METRES = 30
-- How long a Hoon waits at a far slot, then at a near slot, in seconds (picked between the two).
M.HOLD_FAR, M.HOLD_NEAR = { 2, 5 }, { 1.5, 3 }
-- A Hoon never stops (Rowan, 6 Nov): it always drives at MIN_MPS at least. One that would go
-- slower, because it is at its point or past it (you stopped, or you are chasing it), circles
-- the point ORBIT_METRES out instead, aiming ORBIT_STEP radians further round, like a hyena
-- pacing. Only a box parks in front of you on purpose.
M.MIN_MPS, M.ORBIT_METRES, M.ORBIT_STEP = 8, 20, 0.8
-- Changing spot is done by speeding up, not braking (Rowan, 6 Nov): circling only ever moves
-- forward (a rear slot to the front slot on its side, a front slot round your nose to the other
-- front slot), and a Hoon getting into place never asks for more than DROP_MPS below your
-- speed, so it drops back by easing off, not on the brakes. A Hoon getting into place, lining up
-- or swiping never uses its brakes at all (Rowan, 6 Nov): its driver lifts off instead, and it
-- asks for at most DROP_MPS less than your speed, so it moves round you sideways or forwards,
-- and only ever eases back slowly.
M.DROP_MPS = 1
-- How many far slots a new Hoon circles through before closing in (picked between the two). A
-- bold one (BOLD_CHANCE of them) moves in after one at most. After an attack it circles 0 to 2.
M.CIRCLES, M.BOLD_CHANCE, M.CIRCLES_AFTER = { 2, 6 }, 0.3, { 0, 2 }
-- Before it strikes, a Hoon edges in to this many metres off your side for WINDUP_SECONDS, so
-- you can see it coming.
M.WINDUP_SIDE, M.WINDUP_SECONDS = 6, 1.5
-- A swipe is Tanker's own driver aimed into the corner of your truck by its slot: SWIPE_INTO
-- metres from your middle on that side (inside your bodywork, so it hits), level with your
-- front or back, only STRIKE_LEAD metres ahead of that point so it turns in hard. It matches
-- your speed and turns in suddenly, with no brake (Rowan, 6 Nov). It lasts up to
-- SWIPE_SECONDS; within CONTACT_METRES it has hit you, and it peels off AFTER_CONTACT_SECONDS
-- later.
M.SWIPE_INTO, M.STRIKE_LEAD = 0.5, 2
M.SWIPE_SECONDS, M.CONTACT_METRES, M.AFTER_CONTACT_SECONDS = 4, 5, 1
-- This share of attacks are a box instead of a swipe. The lead Hoon gets BOX_AHEAD metres in
-- front of you and drives at BOX_SLOW of your speed; a second Hoon, if there is one, sits
-- BOX_SIDE metres off your side. A box lasts up to BOX_SECONDS. Slower than STOPPED_MPS for
-- BOXED_SECONDS and you are boxed in; they hold you there for BOX_HOLD_SECONDS, then peel off.
M.BOX_CHANCE, M.BOX_AHEAD, M.BOX_SLOW, M.BOX_SIDE = 0.35, 8, 0.6, 4
M.BOX_SECONDS, M.STOPPED_MPS, M.BOXED_SECONDS, M.BOX_HOLD_SECONDS = 15, 2, 3, 5
-- A box is teamwork (Rowan, 6 Nov): it needs at least one other Hoon, and every free Hoon joins.
-- The first takes the side it is already on, the next the other side, a third sits BOX_AHEAD
-- behind you, so with three or four Hoons you are boxed in on both sides. With two or more
-- helpers free, a box is TEAM_BOX_CHANCE of attacks. First they gather: the lead runs in front
-- at your speed while the others get alongside (within BOX_ARRIVE metres of their spot), or for
-- at most GATHER_SECONDS. Then they squeeze: all of them slow to BOX_SLOW of your speed together.
-- A Hoon that goes down or is lost is replaced: a helper takes over the lead, and the team
-- keeps the box going.
M.TEAM_BOX_CHANCE, M.BOX_ARRIVE, M.GATHER_SECONDS = 0.6, 8, 8
-- A Hoon that has hit you and then goes slower than STUCK_MPS for DOWN_SECONDS while you drive
-- is down (wrecked or stuck). You must be going at least DRIVING_MPS for that to count, since
-- Hoons wait when you stop. One that hasn't hit you yet is never down for being slow: after
-- STALL_SECONDS its path is sent again and the stall is logged, to find out why.
M.STUCK_MPS, M.DOWN_SECONDS, M.DRIVING_MPS, M.STALL_SECONDS = 1, 12, 3, 5
-- Further than ESCAPE_METRES from you for ESCAPE_SECONDS, and you have lost it: it is gone.
M.ESCAPE_METRES, M.ESCAPE_SECONDS = 400, 0
-- A downed Hoon is given back once you are this far from it, and can't be siphoned after.
M.LEAVE_METRES = 400
-- This many hits from your revolver stop a Hoon.
M.SHOTS_TO_STOP = 4

-- Robbing you when you can't move (Rowan, 6 Nov; robbery.lua decides when): the Hoon drives to
-- ROB_SIDE metres off your side at up to ROB_MPS, slowing as it gets there, and stops beside you.
-- Then it speeds off at FLEE_MPS, away from you and the way you face, and is gone at 400 m.
M.ROB_SIDE, M.ROB_MPS, M.ROB_STOP_METRES = 4, 12, 2
M.FLEE_MPS, M.FLEE_AIM_METRES = 30, 120

-- Two modes (Rowan, 6 Nov): desert, the slots above, once you have been more than ROAD_METRES
-- from the nearest road for MODE_SECONDS; and road, once you have been within ROAD_METRES of a
-- road for MODE_SECONDS. In road mode each Hoon drives itself in the car (tankerDriver.chase):
-- it catches up along the roads, overtakes you, cuts in front and brake-checks. A Hoon that
-- turns up in road mode is put on the road ROAD_START_METRES behind you.
M.ROAD_METRES, M.MODE_SECONDS, M.ROAD_START_METRES = 30, 5, 80

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
  BOX_REAR = 'boxing you in, behind you',
  ROB = 'pulling up to siphon your fuel', FLEE = 'speeding off',
  ROAD = 'on the road',
}
-- What a road-mode Hoon is doing, as its driver reports it.
M.ROAD_DOING = {
  CATCH = 'catching up on the road', PASS = 'overtaking you', CUT_IN = 'cutting in front of you',
  BRAKE_CHECK = 'brake-checking you', RECOVER = 'pulling ahead', BLOCK = 'blocking you in',
}
local LINES = {
  arrived = function(slot) return 'A Hoon has turned up out on your ' .. where(slot) .. '. It is sizing you up.' end,
  windup = function(slot) return 'A Hoon is lining up on your ' .. where(slot) .. '!' end,
  box = 'A Hoon is getting in front of you to box you in!',
  teamBox = function(n) return n .. ' Hoons are working together to box you in!' end,
  squeeze = 'The Hoons are closing the box. Get out or get stopped!',
  boxed = 'The Hoons have boxed you in.',
  swiped = 'The Hoon hit you and peeled off.',
  missed = 'The Hoon missed and peeled off.',
  down = 'A Hoon is down. Siphon its tank before the others come.',
  shotDown = 'You shot a Hoon to a stop. Siphon its tank before the others come.',
  driverShot = 'You shot a Hoon\'s driver. Siphon its tank before the others come.',
  escaped = 'A Hoon got more than 400 m away and is gone.',
  fled = 'The Hoon that robbed you is gone.',
  gone = 'A Hoon is gone.',
  full = 'That\'s as many Hoons as there can be at once.',
  cleared = 'The Hoons are gone.',
  roadMode = 'You\'re on the road: the Hoons will try to get in front of you and brake-check you.',
  desertMode = 'You\'re off road: the Hoons spread out around you.',
  arrivedRoad = 'A Hoon is coming up the road behind you.',
}
M.LINES = LINES

local function distance2d(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The slot's offset from your middle: metres to your right, metres ahead.
function M.offset(slot)
  local s = M.SLOTS[slot]
  local side = s.far and (s.ahead < 0 and M.REAR_FAR_SIDE or M.FAR_SIDE) or M.NEAR_SIDE
  local ahead = M.HALF_LENGTH + (s.far and M.FAR_BEYOND or 0)
  return s.side * side, s.ahead * ahead
end

-- Where an offset (right, ahead) from you will be in t seconds, if you keep going at speed.
function M.at(me, right, ahead, t, speed)
  local go = (speed or me.speed or 0) * (t or 0) + ahead
  return me.x + me.dx * go + me.dy * right, me.y + me.dy * go - me.dx * right
end

-- The next far slot when circling, always forwards: rear to the front on the same side, front to
-- the front on the other side (round your nose).
function M.forward(slot)
  local side, endOf = slot:sub(1, 1), slot:sub(2, 2)
  if endOf == 'R' then return side .. 'FF' end
  return (side == 'L' and 'R' or 'L') .. 'FF'
end

local function near(slot) return slot:sub(1, 2) .. 'N' end
local function far(slot) return slot:sub(1, 2) .. 'F' end

-- car is packCar (or a fake), random(lo, hi) a number between them.
function M.new(car, random)
  random = random or function(lo, hi) return lo + math.random() * (hi - lo) end
  local p = { hoons = {}, count = 0, mode = nil }
  local toRoad

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
  -- The offset a Hoon drives to now (right, ahead), the share of your speed to match there, how
  -- far ahead of the point to aim (nil: the usual lead), and any extra speed on top.
  local function target(h)
    local boxLead = h.state == 'BOXING' and h or h.lead
    local squeeze = boxLead and boxLead.squeeze and M.BOX_SLOW or 1
    if h.state == 'BOXING' then return 0, M.HALF_LENGTH + M.BOX_AHEAD, squeeze end
    if h.state == 'BOX_SIDE' then return h.side * M.BOX_SIDE, 0, squeeze end
    if h.state == 'BOX_REAR' then return 0, -(M.HALF_LENGTH + M.BOX_AHEAD), squeeze end
    local right, ahead = M.offset(h.slot)
    local side = M.SLOTS[h.slot].side
    if h.state == 'WINDUP' then right = side * M.WINDUP_SIDE end
    if h.state == 'SWIPE' then return side * M.SWIPE_INTO, ahead, 1, M.STRIKE_LEAD end
    return right, ahead, 1
  end

  -- Where the Hoon is from you: metres to your right and ahead.
  local function relative(me, st)
    local x, y = st.x - me.x, st.y - me.y
    st.ahead = x * me.dx + y * me.dy
    st.right = x * me.dy - y * me.dx
  end

  -- Tells the Hoon where to drive now and how fast: its slot, or round the front or back of you
  -- first when it is crossing to your other side.
  local function drive(h, me, st, clock)
    if h.replanAt and clock < h.replanAt then return end
    h.replanAt = clock + M.STEER_SECONDS
    relative(me, st)
    if h.state == 'ROB' then
      -- Straight to the spot beside you, slowing as it gets there, then stopped.
      local sx, sy = M.at(me, (h.side or 1) * M.ROB_SIDE, 0, 0)
      local d = distance2d(st.x, st.y, sx, sy)
      h.spotMetres = d
      local speed = d <= M.ROB_STOP_METRES and 0 or math.min(M.ROB_MPS, math.max(2, M.GAIN * d))
      car:goTo(h.id, { x = sx, y = sy, z = car:ground(sx, sy, me.z) or me.z, speed = speed, slotX = sx, slotY = sy })
      return
    end
    if h.state == 'FLEE' then
      -- Away from you, and the way you face, flat out.
      local ax, ay = st.x - me.x, st.y - me.y
      local len = math.sqrt(ax * ax + ay * ay)
      if len > 0.5 then ax, ay = ax / len, ay / len else ax, ay = 0, 0 end
      ax, ay = ax + me.dx, ay + me.dy
      len = math.sqrt(ax * ax + ay * ay)
      if len > 0.01 then ax, ay = ax / len, ay / len else ax, ay = me.dx, me.dy end
      local x, y = st.x + ax * M.FLEE_AIM_METRES, st.y + ay * M.FLEE_AIM_METRES
      car:goTo(h.id, { x = x, y = y, z = car:ground(x, y, me.z) or me.z, speed = M.FLEE_MPS, slotX = x, slotY = y })
      return
    end
    local right, ahead, slow, strikeLead = target(h)
    local mine = me.speed or 0
    local aimRight, aimAhead = right, ahead
    local hr, ha = st.right, st.ahead
    if hr * right < 0 and math.abs(hr) > M.NEAR_SIDE and math.abs(right) > M.NEAR_SIDE then
      local sign = (ahead + ha) >= 0 and 1 or -1
      aimRight, aimAhead = 0, sign * (math.max(math.abs(ahead), math.abs(ha)) + M.CROSS_METRES)
    end
    local speed = mine * slow + M.GAIN * (aimAhead - ha) + M.SIDE_GAIN * math.abs(aimRight - hr)
    -- A swipe matches your speed and turns in suddenly.
    if h.state == 'SWIPE' then speed = mine end
    local coasting = h.state == 'CIRCLING' or h.state == 'CLOSING' or h.state == 'PEEL' or h.state == 'WINDUP'
      or h.state == 'SWIPE'
    if coasting then speed = math.max(speed, mine - M.DROP_MPS) end
    speed = math.max(0, math.min(speed, mine + M.CATCH_UP_MPS))
    local lead = strikeLead or math.max(M.MIN_LEAD, math.min(M.MAX_LEAD, mine * M.LEAD_SECONDS))
    -- Never aim behind the Hoon: its driver would turn round for a point behind it, slowly, and
    -- fall far behind you. A point it has passed is aimed at a little ahead of it instead, and the
    -- speed law drops it back.
    local aimAt = math.max(aimAhead + lead, ha + (strikeLead or M.MIN_LEAD))
    local x, y = M.at(me, aimRight, aimAt, 0)
    local sx, sy = M.at(me, right, ahead, 0)
    local boxing = h.state == 'BOXING' or h.state == 'BOX_SIDE' or h.state == 'BOX_REAR'
    h.spotMetres = distance2d(st.x, st.y, sx, sy)
    local placing = h.state == 'CIRCLING' or h.state == 'CLOSING' or h.state == 'PEEL'
    h.orbiting = false
    if speed < M.MIN_MPS and not boxing then
      -- Never stop: near its point, circle it; further off, keep its aim (back to its point, or
      -- round you to your other side) at MIN_MPS. A windup or swipe only keeps its speed up.
      local ox, oy = st.x - sx, st.y - sy
      local r = math.sqrt(ox * ox + oy * oy)
      if placing and r < 2 * M.ORBIT_METRES then
        h.orbiting = true
        local angle = (r > 0.5 and math.atan2(oy, ox) or 0) + (h.dir or 1) * M.ORBIT_STEP
        x, y = sx + M.ORBIT_METRES * math.cos(angle), sy + M.ORBIT_METRES * math.sin(angle)
      end
      speed = M.MIN_MPS
    end
    local mode = h.state == 'SWIPE' and 'swipe' or (coasting and 'coast' or nil)
    car:goTo(h.id, { x = x, y = y, z = car:ground(x, y, me.z) or me.z, speed = speed, slotX = sx, slotY = sy, mode = mode })
  end

  local function arrived(h, me, st)
    local right, ahead = target(h)
    local x, y = M.at(me, right, ahead, 0)
    local reach = (h.state == 'CIRCLING' or h.state == 'PEEL') and M.FAR_ARRIVE or M.NEAR_ARRIVE
    -- Circling its point because you are slow or stopped counts as being there.
    if h.orbiting then reach = math.max(reach, M.ORBIT_METRES + 5) end
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

  -- The Hoons helping h's box.
  local function helpers(h)
    local list = {}
    for _, o in ipairs(p.hoons) do if o ~= h and o.lead == h then list[#list + 1] = o end end
    return list
  end
  -- h is out of its box (down or gone). If it led, a helper takes over the lead, front first.
  local function leaveBox(h)
    local team = helpers(h)
    h.lead = nil
    if h.state ~= 'BOXING' or #team == 0 then return end
    local next = team[1]
    for _, o in ipairs(team) do if o.state == 'BOX_SIDE' then next = o break end end
    next.state, next.lead, next.side, next.replanAt = 'BOXING', nil, nil, nil
    next.since, next.squeeze, next.squeezeSince = h.since, h.squeeze, h.squeezeSince
    next.boxedSince, next.holdTill = h.boxedSince, h.holdTill
    for _, o in ipairs(team) do if o ~= next then o.lead = next end end
  end

  -- Hides the car for next time and forgets the Hoon.
  local function release(h)
    leaveBox(h)
    car:release(h.id, h.source)
    for i, other in ipairs(p.hoons) do
      if other == h then table.remove(p.hoons, i) break end
    end
  end

  local function down(h, line)
    leaveBox(h)
    h.state, h.slot = 'DOWN', nil
    car:calm(h.id)
    return line
  end

  -- Hands a Hoon to its own driver for the road attack.
  toRoad = function(h, me)
    h.state, h.slot, h.lead, h.side, h.holdUntil, h.replanAt, h.phase = 'ROAD', nil, nil, nil, nil, nil, 'CATCH'
    car:chase(h.id, me.id)
  end

  -- Back to the desert slots: the nearest free far slot, sizing you up again briefly.
  local function toDesert(h, me, st)
    local best, bestD
    for _, slot in ipairs(freeFar(h)) do
      local r, a = M.offset(slot)
      local x, y = M.at(me, r, a, 0)
      local d = distance2d(st.x, st.y, x, y)
      if not bestD or d < bestD then best, bestD = slot, d end
    end
    h.state, h.slot, h.replanAt, h.holdUntil, h.phase = 'CIRCLING', best or M.RING[1], nil, nil, nil
    h.movesLeft = whole({ 0, 1 })
  end

  -- Whether you are on a road now: within ROAD_METRES of one.
  function p:onRoad(me)
    local r = car.road and car:road(me.x, me.y, me.z)
    return r ~= nil and r.metres <= M.ROAD_METRES
  end

  -- Follows whether you are on a road, and switches mode after MODE_SECONDS one way or the other.
  local function followMode(me, clock)
    local onRoad = p:onRoad(me)
    local want = onRoad and 'road' or 'desert'
    if not p.mode then p.mode = want end
    if want == p.mode then p.wantSince = nil return nil end
    p.wantSince = p.wantSince or clock
    if clock - p.wantSince < M.MODE_SECONDS then return nil end
    p.mode, p.wantSince = want, nil
    return want == 'road' and LINES.roadMode or LINES.desertMode
  end

  -- Brings in one more Hoon at a free far slot, in a HoonOld1 (a hidden one, or a new one loaded). Returns the
  -- line to show, or nil and why not.
  function p:add(clock)
    if #self.hoons >= M.MAX then return nil, 'full' end
    local me = car:player()
    if not me then return nil, 'no_player' end
    local free = freeFar()
    if #free == 0 then return nil, 'full' end
    local slot = free[math.min(#free, math.floor(random(1, #free + 1)))]
    self.mode = self.mode or (self:onRoad(me) and 'road' or 'desert')
    local id, source = car:take(me)
    if not id then return nil, source or 'no_car' end
    local right, ahead = M.offset(slot)
    local x, y = M.at(me, right, ahead, 0)
    if self.mode == 'road' then
      x, y = M.at(me, 0, -M.ROAD_START_METRES, 0)
      local r = car.road and car:road(x, y, me.z)
      if r and r.metres <= M.ROAD_METRES then x, y = r.x, r.y end
    end
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
    if self.mode == 'road' then
      toRoad(h, me)
      return LINES.arrivedRoad
    end
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
            local nextSlot = M.forward(h.slot)
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
        elseif (function()
          -- Every other Hoon still up and not attacking can help, nearest first.
          local free = {}
          for _, o in ipairs(p.hoons) do
            if o ~= h and (o.state == 'CIRCLING' or o.state == 'CLOSING' or o.state == 'PEEL') and o.metres then
              free[#free + 1] = o
            end
          end
          table.sort(free, function(x, y) return x.metres < y.metres end)
          if #free == 0 then return false end
          if not chance(#free >= 2 and M.TEAM_BOX_CHANCE or M.BOX_CHANCE) then return false end
          h.state, h.since, h.replanAt, h.boxedSince, h.holdTill = 'BOXING', clock, nil, nil, nil
          h.squeeze, h.squeezeSince, h.slot = false, nil, h.slot
          local firstSide
          for i, o in ipairs(free) do
            o.lead, o.replanAt, o.holdUntil = h, nil, nil
            if i == 1 then
              firstSide = o.slot and M.SLOTS[o.slot].side or 1
              o.state, o.side = 'BOX_SIDE', firstSide
            elseif i == 2 then
              o.state, o.side = 'BOX_SIDE', -firstSide
            else
              o.state, o.side = 'BOX_REAR', nil
            end
            o.slot = nil
          end
          line = #free >= 2 and LINES.teamBox(#free + 1) or LINES.box
          return true
        end)() then
          -- the box is on
        else
          h.state, h.since, h.replanAt = 'WINDUP', clock, nil
          line = LINES.windup(h.slot)
        end
      end
    elseif h.state == 'WINDUP' then
      if clock - h.since >= M.WINDUP_SECONDS then
        h.state, h.since, h.contactAt, h.replanAt = 'SWIPE', clock, nil, nil
      end
    elseif h.state == 'SWIPE' then
      if not h.contactAt and h.metres and h.metres <= M.CONTACT_METRES then h.contactAt, h.hasHit = clock, true end
      if h.contactAt and clock - h.contactAt >= M.AFTER_CONTACT_SECONDS then
        peel(h, clock); line = LINES.swiped
      elseif clock - h.since >= M.SWIPE_SECONDS then
        peel(h, clock); line = LINES.missed
      end
    elseif h.state == 'BOXING' then
      local team = helpers(h)
      if not h.squeeze then
        -- Gathering: squeeze once everyone is alongside, or after GATHER_SECONDS.
        local ready = true
        for _, o in ipairs(team) do
          if not (o.spotMetres and o.spotMetres <= M.BOX_ARRIVE) then ready = false end
        end
        if ready or clock - h.since >= M.GATHER_SECONDS then
          h.squeeze, h.squeezeSince, h.replanAt = true, clock, nil
          for _, o in ipairs(team) do o.replanAt = nil end
          line = LINES.squeeze
        end
      end
      if (me.speed or 0) < M.STOPPED_MPS then h.boxedSince = h.boxedSince or clock else h.boxedSince = nil end
      if h.boxedSince and not h.holdTill and clock - h.boxedSince >= M.BOXED_SECONDS then
        h.holdTill = clock + M.BOX_HOLD_SECONDS
        line = LINES.boxed
      end
      local over = h.holdTill and clock >= h.holdTill
      if not h.holdTill and h.squeezeSince and clock - h.squeezeSince >= M.BOX_SECONDS then over = true end
      if over then
        for _, o in ipairs(team) do peel(o, clock) end
        peel(h, clock)
      end
    elseif h.state == 'BOX_SIDE' or h.state == 'BOX_REAR' then
      -- A helper whose box is over (its lead peeled off or left) peels off too.
      if not (h.lead and h.lead.state == 'BOXING') then peel(h, clock) end
    end
    if h.state ~= 'DOWN' and h.state ~= 'ROAD' then drive(h, me, st, clock) end
    return line
  end

  -- Called every half second while the run is on the road. Returns a line to show when something
  -- happens.
  function p:step(clock)
    if #self.hoons == 0 then return nil end
    local me = car:player()
    if not me then return nil end
    local line = followMode(me, clock)
    for _, h in ipairs({ unpack(self.hoons) }) do
      local st = car:state(h.id)
      if st and h.state ~= 'DOWN' then
        if h.state == 'ROB' or h.state == 'FLEE' then
          -- robbing, or running off with your fuel: in either mode
        elseif self.mode == 'road' and h.state ~= 'ROAD' then
          for _, o in ipairs(self.hoons) do if o.lead == h then peel(o, clock) end end
          toRoad(h, me)
        elseif self.mode == 'desert' and h.state == 'ROAD' then
          relative(me, st)
          toDesert(h, me, st)
        end
      end
      if not st then
        release(h); line = LINES.gone
      else
        relative(me, st)
        h.metres = distance2d(me.x, me.y, st.x, st.y)
        h.speed = st.speed
        if h.metres <= M.CONTACT_METRES and h.state ~= 'ROB' then h.hasHit = true end
        if h.state == 'DOWN' then
          if h.metres > M.LEAVE_METRES then release(h) end
        else
          local driving = (me.speed or 0) >= M.DRIVING_MPS
          if driving and st.speed < M.STUCK_MPS then h.slow = h.slow or clock else h.slow = nil end
          if h.metres > M.ESCAPE_METRES then h.far = h.far or clock else h.far = nil end
          if h.slow and h.hasHit and clock - h.slow >= M.DOWN_SECONDS then
            line = down(h, LINES.down)
          elseif h.slow and not h.hasHit and clock - h.slow >= M.STALL_SECONDS then
            h.slow, h.replanAt, h.stalls = nil, nil, (h.stalls or 0) + 1
            p.stalled = { n = h.n, state = h.state, slot = h.slot, source = h.source, metres = h.metres, stalls = h.stalls }
            if h.state == 'ROAD' then car:chase(h.id, me.id) else line = think(h, me, st, clock) end
          elseif h.far and clock - h.far >= M.ESCAPE_SECONDS then
            local fled = h.state == 'FLEE'
            release(h); line = fled and LINES.fled or LINES.escaped
          elseif h.state ~= 'ROAD' then
            line = think(h, me, st, clock) or line
          end
        end
      end
    end
    return line
  end

  -- Called every frame: keeps each moving Hoon's point and speed fresh.
  function p:steer(clock)
    if #self.hoons == 0 then return end
    local me = car:player()
    if not me then return end
    for _, h in ipairs(self.hoons) do
      if h.state ~= 'DOWN' and h.state ~= 'ROAD' then
        local st = car:state(h.id)
        if st then drive(h, me, st, clock) end
      end
    end
  end

  -- Robbing (robbery.lua): sends the nearest Hoon that is up and not attacking or boxing you to
  -- pull up beside you. Returns its id, or nil.
  function p:startRob(clock)
    if self:robber() then return nil end
    local best
    for _, h in ipairs(self.hoons) do
      local free = h.state == 'CIRCLING' or h.state == 'CLOSING' or h.state == 'PEEL' or h.state == 'ROAD'
      if free and h.metres and (not best or h.metres < best.metres) then best = h end
    end
    if not best then return nil end
    local side = 1
    if best.slot then side = M.SLOTS[best.slot].side end
    best.state, best.slot, best.side, best.holdUntil, best.replanAt, best.phase = 'ROB', nil, side, nil, nil, nil
    best.since = clock
    return best.id
  end

  -- The Hoon robbing you: { id, metres, speed }, or nil.
  function p:robber()
    for _, h in ipairs(self.hoons) do
      if h.state == 'ROB' then return { id = h.id, metres = h.metres, speed = h.speed, n = h.n } end
    end
  end

  -- It has your fuel (or found none): it speeds off.
  function p:flee(id, clock)
    for _, h in ipairs(self.hoons) do
      if h.id == id and h.state ~= 'DOWN' then
        h.state, h.slot, h.side, h.replanAt, h.since, h.hasHit = 'FLEE', nil, nil, nil, clock, true
        return true
      end
    end
    return false
  end

  -- You drove off before it took anything: back to sizing you up.
  function p:unrob(id, clock)
    for _, h in ipairs(self.hoons) do
      if h.id == id and h.state == 'ROB' then
        local back = freeFar(h)[1] or M.RING[1]
        h.state, h.slot, h.side, h.replanAt, h.since = 'CIRCLING', back, nil, nil, clock
        h.movesLeft = whole({ 0, 1 })
        return true
      end
    end
    return false
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

  -- The distance to the nearest Hoon still up, or nil.
  function p:nearest()
    local best
    for _, h in ipairs(self.hoons) do
      if h.state ~= 'DOWN' and h.metres and (not best or h.metres < best) then best = h.metres end
    end
    return best
  end

  -- For the HUD: each Hoon, its slot and what it is doing.
  function p:view()
    local list = {}
    for _, h in ipairs(self.hoons) do
      local doing = h.state == 'ROAD' and (M.ROAD_DOING[h.phase] or M.DOING.ROAD) or M.DOING[h.state]
      list[#list + 1] = { n = h.n, slot = h.slot, doing = doing, state = h.state, metres = h.metres }
    end
    return list
  end

  -- A road-mode Hoon's driver says what it is doing now. Returns whether car id is one of ours.
  function p:roadPhase(id, phase)
    for _, h in ipairs(self.hoons) do
      if h.id == id then h.phase = phase; return true end
    end
    return false
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
