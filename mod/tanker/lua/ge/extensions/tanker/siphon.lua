-- Siphoning: moving fuel from another car's tank into yours, a litre a second, while you stand
-- still beside it. Each step takes a litre from their tank, waits for their car to say how much
-- really came out, then puts exactly that into yours, so fuel is never made or lost.
-- The fuel goes into your truck's tank, or into the bed tank when you choose it (MadMerick, 6 Nov).
-- The bed tank's litres are Tanker's own number, so they go in as soon as their car answers.
-- This is the logic only; the controller feeds it the clock, the distance and the answers.
local M = {}

-- One-line settings. Tune these after testing in game.
-- Litres moved each second.
M.RATE = 1
-- How close the other car must be, centre to centre, in metres.
M.REACH_METRES = 10
-- Going faster than this, in metres a second, counts as driving off.
M.STILL_MPS = 1.5
-- A car that does not answer within this many seconds has gone (despawned or out of reach).
M.WAIT_SECONDS = 4
-- Less than this in a tank counts as dry, or as full when that little room is left in yours.
M.EMPTY_LITRES = 0.05
-- How long the result stays in the box once the siphon has stopped.
M.RESULT_SECONDS = 6

local RESULTS = {
  dry = 'Their tank is dry.', full = 'Your tank is full.', bedFull = 'The bed tank is full.', moved = 'You moved away, so the siphon stopped.',
  lost = 'The other car is gone, so the siphon stopped.', stopped = 'Siphon stopped.',
}
M.RESULTS = RESULTS

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- change(litres, serial, id) adds litres to a tank (taking them when negative): the player's car
-- when id is nil. It answers later through answer(). toBed(litres) puts litres in the bed tank
-- now and returns how many went in, and the bed tank's litres and size after.
function M.new(change, toBed)
  local s = { serial = 0 }

  function s:active() return self.run ~= nil end

  -- into: 'truck' (the default) or 'bed'.
  function s:start(donorId, clock, into)
    if self.run or type(donorId) ~= 'number' then return false end
    into = (into == 'bed' and toBed) and 'bed' or 'truck'
    self.run = { donor = donorId, taken = 0, nextAt = clock, startedAt = clock, into = into }
    self.result = nil
    return true
  end

  -- Ends the siphon and keeps what was taken. Returns the line to show.
  function s:finish(reason, clock)
    local run = self.run
    if not run then return nil end
    self.run = nil
    local taken = run.taken
    if reason == 'full' and run.into == 'bed' then reason = 'bedFull' end
    local text = RESULTS[reason] or RESULTS.stopped
    if taken >= 0.5 then
      text = text .. string.format(' You took %d L%s.', math.floor(taken + 0.5), run.into == 'bed' and ' into the bed tank' or '')
    elseif reason == 'dry' and taken < M.EMPTY_LITRES then text = 'There is no fuel to siphon in that car.' end
    self.result = { reason = reason, text = text, taken = taken, at = clock, into = run.into,
      theirs = run.theirs, theirsCapacity = run.theirsCapacity }
    return text
  end

  function s:send(litres, id, stage, clock)
    self.serial = self.serial + 1
    local run = self.run
    run.pending = { serial = self.serial, stage = stage, at = clock, litres = litres }
    local ok = change(litres, self.serial, id)
    if not ok then return self:finish(stage == 'take' and 'lost' or 'stopped', clock) end
  end

  -- Called often. metres is how far the other car is (nil if it is gone), speed is how fast you
  -- are going, own is the reading ({ litres, capacity }) of the tank the fuel goes into (your
  -- truck's, or the bed tank's), or nil. Returns a result line
  -- when the siphon stops.
  function s:step(clock, metres, speed, own)
    local run = self.run
    if not run then return nil end
    if not finite(metres) or metres > M.REACH_METRES or (finite(speed) and speed > M.STILL_MPS) then
      return self:finish(metres == nil and 'lost' or 'moved', clock)
    end
    if run.pending then
      if clock - run.pending.at > M.WAIT_SECONDS then return self:finish('lost', clock) end
      return nil
    end
    if clock < run.nextAt then return nil end
    local room = own and finite(own.litres) and finite(own.capacity) and own.capacity - own.litres or nil
    if room and room < M.EMPTY_LITRES then return self:finish('full', clock) end
    run.nextAt = clock + 1
    return self:send(-math.min(M.RATE, room or M.RATE), run.donor, 'take', clock)
  end

  -- A car's answer to change(). Returns handled, and a result line if the siphon stopped.
  function s:answer(serial, before, after, capacity, clock)
    local run = self.run
    if not (run and run.pending and run.pending.serial == serial) then return false end
    if not (finite(before) and finite(after)) then return true, self:finish('stopped', clock) end
    local stage = run.pending.stage
    run.pending = nil
    if stage == 'take' then
      run.theirs, run.theirsCapacity = after, finite(capacity) and capacity or run.theirsCapacity
      local moved = before - after
      if moved < 0.001 then return true, self:finish('dry', clock) end
      if run.into == 'bed' then
        local added, bedAfter, bedCapacity = toBed(moved)
        run.taken = run.taken + math.max(0, added or 0)
        if run.theirs < M.EMPTY_LITRES then return true, self:finish('dry', clock) end
        if finite(bedAfter) and finite(bedCapacity) and bedCapacity - bedAfter < M.EMPTY_LITRES then
          return true, self:finish('full', clock)
        end
        return true
      end
      return true, self:send(moved, nil, 'give', clock)
    end
    run.taken = run.taken + math.max(0, after - before)
    if run.theirs and run.theirs < M.EMPTY_LITRES then return true, self:finish('dry', clock) end
    if finite(capacity) and capacity - after < M.EMPTY_LITRES then return true, self:finish('full', clock) end
    return true
  end

  -- What the HUD shows: the live siphon, or its result for a few seconds after it stops.
  function s:view(clock, own)
    local run = self.run
    if run then
      return { active = true, into = run.into, litres = run.taken, theirs = run.theirs, theirsCapacity = run.theirsCapacity,
        yours = own and own.litres, yoursCapacity = own and own.capacity, seconds = clock - run.startedAt }
    end
    local r = self.result
    if r and clock - r.at <= M.RESULT_SECONDS then
      return { active = false, into = r.into, litres = r.taken, theirs = r.theirs, theirsCapacity = r.theirsCapacity,
        yours = own and own.litres, yoursCapacity = own and own.capacity, result = r.text }
    end
  end

  return s
end

return M
