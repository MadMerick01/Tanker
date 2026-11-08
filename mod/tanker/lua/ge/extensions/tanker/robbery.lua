-- Hoons rob you when you can't move (MadMerick, 6 Nov). Stand still for STUCK_SECONDS with a Hoon up
-- and one pulls up beside you, stops, and siphons your fuel: the bed tank first, then your
-- truck's tank, always leaving you KEEP_LITRES. Once it has taken what it can (you are down to
-- KEEP_LITRES, or its own tank is full) it speeds off, and is gone once it is 400 m away. With
-- KEEP_LITRES or less on board, it pulls up, checks for CHECK_SECONDS, and speeds off with nothing.
-- Fuel is never made or lost: what it takes goes into its own tank, so a Hoon you shoot down on
-- the way out can be siphoned back. Driving off before it has finished stops it.
-- This is the logic only. The controller feeds it the clock and the readings, and hoons does the
-- driving: hoons:startRob(clock) picks a Hoon and sends it to you (returns its id), hoons:robber()
-- says where it is ({ id, metres, speed } or nil if it is down or gone), hoons:flee(id, clock)
-- sends it away fast and hoons:unrob(id, clock) sends it back to circling you.
local M = {}

-- One-line settings. Tune these after testing in game.
-- Slower than this, in metres a second, for STUCK_SECONDS, and you can't move.
M.STUCK_MPS, M.STUCK_SECONDS = 1, 10
-- Faster than this while a Hoon is coming or siphoning, and you got away.
M.MOVING_MPS = 1.5
-- A Hoon always leaves you this many litres.
M.KEEP_LITRES = 10
-- Litres it takes each second.
M.RATE = 4
-- The Hoon siphons once it is this close, centre to centre, and nearly stopped.
M.REACH_METRES, M.STILL_MPS = 8, 1.5
-- With nothing worth taking, it looks this long before it speeds off.
M.CHECK_SECONDS = 4
-- A Hoon that hasn't reached you after this long gives up and goes back to circling.
M.COME_SECONDS = 45
-- After a robbery, the next Hoon comes no sooner than this.
M.GAP_SECONDS = 6
-- A car that does not answer within this many seconds is taken as gone.
M.WAIT_SECONDS = 4
-- Less than this counts as nothing.
M.EMPTY_LITRES = 0.05
-- How long the result stays in the centre window.
M.RESULT_SECONDS = 6

local LINES = {
  coming = 'You\'re not moving. A Hoon is pulling up to siphon your fuel!',
  taking = 'A Hoon is siphoning your fuel! Drive off or shoot it.',
  checking = 'A Hoon is checking your tank.',
  nothing = 'There\'s nothing worth taking. The Hoon speeds off.',
  took = function(litres) return string.format('The Hoon took %d L and sped off.', math.floor(litres + 0.5)) end,
  tookLittle = 'The Hoon sped off.',
  droveOff = 'You drove off before the Hoon could siphon you.',
  droveOffWith = function(litres) return string.format('You drove off. The Hoon got %d L and is speeding away.', math.floor(litres + 0.5)) end,
  gaveUp = 'The Hoon couldn\'t get to you.',
}
M.LINES = LINES

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- change(litres, serial, id) adds litres to a tank (takes them when negative): yours when id is
-- nil. Its answer comes back through answer(). bed(litres) changes the bed tank by litres now
-- (negative takes) and returns how much it really changed by.
function M.new(change, bed, hoons)
  -- Serials start high so they never match the siphon's or the pump's.
  local r = { serial = 2000000, state = 'IDLE', orphans = {} }

  function r:active() return self.state ~= 'IDLE' end
  function r:robberId() return self.run and self.run.id end

  local function send(litres, id, stage, clock, from)
    r.serial = r.serial + 1
    r.run.pending = { serial = r.serial, stage = stage, at = clock, litres = litres, from = from }
    return change(litres, r.serial, id)
  end

  -- Puts back fuel that did not reach the Hoon: into the bed tank, or into your truck.
  local function giveBack(litres, from)
    if litres < 0.001 then return end
    if from == 'bed' then bed(litres) else change(litres, 0, nil) end
  end

  -- A robbery that ends with fuel on its way: when the car answers, litres that came out of your
  -- truck go back into it, and litres that did not fit in the Hoon's tank go back where they
  -- came from.
  local function dropPending(run)
    local pending = run and run.pending
    if not pending then return end
    r.orphans[pending.serial] = pending
    run.pending = nil
  end

  local function finish(clock, line, flee)
    local run = r.run
    dropPending(run)
    if run then
      if flee then hoons:flee(run.id, clock) else hoons:unrob(run.id, clock) end
    end
    r.run, r.state, r.nextAt = nil, 'IDLE', clock + M.GAP_SECONDS
    r.result = { text = line, at = clock, taken = run and run.taken or 0 }
    return line
  end

  -- How much can be taken now: from the bed tank first, then your truck down to KEEP_LITRES.
  local function available(truck, bedTank)
    local fromBed = bedTank and finite(bedTank.litres) and bedTank.litres or 0
    local fromTruck = truck and finite(truck.litres) and math.max(0, truck.litres - M.KEEP_LITRES) or 0
    return fromBed, fromTruck
  end

  -- Called often while the run is on the road. speed is how fast you are going, truck your tank's
  -- reading ({ litres, capacity }) or nil, bedTank the bed tank's or nil. Returns a line to show.
  function r:step(clock, speed, truck, bedTank)
    speed = finite(speed) and speed or 0
    if self.state == 'IDLE' then
      if speed >= M.STUCK_MPS then self.stillSince = nil return nil end
      self.stillSince = self.stillSince or clock
      if clock - self.stillSince < M.STUCK_SECONDS or (self.nextAt and clock < self.nextAt) or not truck then return nil end
      local id = hoons:startRob(clock)
      if not id then return nil end
      self.run, self.state = { id = id, taken = 0, since = clock }, 'COMING'
      return LINES.coming
    end
    local run = self.run
    local h = hoons:robber()
    if not h or h.id ~= run.id then
      -- Down or gone: whatever it took stays in its tank.
      dropPending(run)
      self.run, self.state, self.nextAt = nil, 'IDLE', clock + M.GAP_SECONDS
      return nil
    end
    if speed > M.MOVING_MPS then
      self.stillSince = nil
      if run.taken >= 0.5 then return finish(clock, LINES.droveOffWith(run.taken), true) end
      return finish(clock, LINES.droveOff, false)
    end
    if self.state == 'COMING' then
      if h.metres and h.metres <= M.REACH_METRES and (h.speed or 0) <= M.STILL_MPS then
        local fromBed, fromTruck = available(truck, bedTank)
        if fromBed + fromTruck < M.EMPTY_LITRES then
          self.state, run.checkUntil = 'CHECKING', clock + M.CHECK_SECONDS
          return LINES.checking
        end
        self.state, run.nextAt = 'TAKING', clock
        return LINES.taking
      end
      if clock - run.since >= M.COME_SECONDS then return finish(clock, LINES.gaveUp, false) end
      return nil
    end
    if self.state == 'CHECKING' then
      if clock >= run.checkUntil then return finish(clock, LINES.nothing, true) end
      return nil
    end
    -- TAKING
    if run.pending then
      if clock - run.pending.at > M.WAIT_SECONDS then
        return finish(clock, run.taken >= 0.5 and LINES.took(run.taken) or LINES.tookLittle, true)
      end
      return nil
    end
    if run.full then return finish(clock, LINES.took(run.taken), true) end
    if clock < run.nextAt then return nil end
    run.nextAt = clock + 1
    local fromBed, fromTruck = available(truck, bedTank)
    if fromBed >= M.EMPTY_LITRES then
      local took = bed(-math.min(M.RATE, fromBed))
      local litres = math.max(0, -(took or 0))
      if litres < 0.001 then return nil end
      if not send(litres, run.id, 'give', clock, 'bed') then
        giveBack(litres, 'bed'); run.pending = nil
        return finish(clock, run.taken >= 0.5 and LINES.took(run.taken) or LINES.tookLittle, true)
      end
      return nil
    end
    if fromTruck >= M.EMPTY_LITRES then
      if not send(-math.min(M.RATE, fromTruck), nil, 'take', clock, 'truck') then
        run.pending = nil
        return finish(clock, run.taken >= 0.5 and LINES.took(run.taken) or LINES.tookLittle, true)
      end
      return nil
    end
    return finish(clock, run.taken >= 0.5 and LINES.took(run.taken) or LINES.nothing, true)
  end

  -- A car's answer to change(). Returns whether it was for the robbery.
  function r:answer(serial, before, after, capacity, clock)
    local orphan = self.orphans[serial]
    if orphan then
      self.orphans[serial] = nil
      if finite(before) and finite(after) then
        if orphan.stage == 'take' then giveBack(before - after, 'truck')
        else giveBack(orphan.litres - math.max(0, after - before), orphan.from) end
      end
      return true
    end
    local run = self.run
    if not (run and run.pending and run.pending.serial == serial) then return false end
    local pending = run.pending
    run.pending = nil
    if not (finite(before) and finite(after)) then
      run.full = true
      return true
    end
    if pending.stage == 'take' then
      local moved = before - after
      if moved < 0.001 then run.full = true return true end
      if not send(moved, run.id, 'give', clock, 'truck') then giveBack(moved, 'truck'); run.pending = nil; run.full = true end
      return true
    end
    -- give: the Hoon's tank took what it had room for; the rest goes back where it came from.
    local got = math.max(0, after - before)
    run.taken = run.taken + got
    giveBack(pending.litres - got, pending.from)
    if pending.litres - got > 0.01 or (finite(capacity) and capacity - after < M.EMPTY_LITRES) then run.full = true end
    return true
  end

  -- Ends a robbery at once (a new run, or the run stopping): the Hoon goes back to the pack.
  function r:cancel(clock)
    if self.run then finish(clock, nil, false) end
    self.result, self.stillSince = nil, nil
  end

  -- What the centre window shows, or nil.
  function r:view(clock, truck, bedTank)
    local run = self.run
    if run then
      local texts = { COMING = 'A Hoon is pulling up beside you.', CHECKING = LINES.checking, TAKING = LINES.taking }
      return { active = true, state = self.state, text = texts[self.state], litres = run.taken,
        yours = truck and truck.litres, yoursCapacity = truck and truck.capacity,
        bed = bedTank and bedTank.litres, bedCapacity = bedTank and bedTank.capacity, keep = M.KEEP_LITRES }
    end
    local res = self.result
    if res and res.text and clock - res.at <= M.RESULT_SECONDS then
      return { active = false, text = res.text, litres = res.taken,
        yours = truck and truck.litres, yoursCapacity = truck and truck.capacity,
        bed = bedTank and bedTank.litres, bedCapacity = bedTank and bedTank.capacity, keep = M.KEEP_LITRES }
    end
  end

  return r
end

return M
