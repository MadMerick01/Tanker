-- Moving fuel between the bed tank and the truck's own tank, through the truck's pump. The bed
-- tank's litres are Tanker's own number; the truck's tank is the game's. Each step asks the truck
-- to add (or give up) a few litres, waits for it to say how much really moved, and only then
-- changes the bed tank by exactly that, so no fuel is made or lost.
-- This is the logic only; the controller feeds it the clock, the readings and the answers.
local M = {}

-- One-line settings. Tune these after testing in game.
-- Litres pumped each second.
M.RATE = 2
-- Less than this to move counts as empty (or full).
M.EMPTY_LITRES = 0.05
-- A truck that does not answer within this many seconds stops the pump.
M.WAIT_SECONDS = 4

local RESULTS = {
  toTruck = { empty = 'The bed tank is empty.', full = 'Your truck\'s tank is full.' },
  toBed = { empty = 'Your truck\'s tank is empty.', full = 'The bed tank is full.' },
  stopped = 'Pump stopped.', lost = 'The pump stopped: the truck did not answer.',
}
M.RESULTS = RESULTS

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- change(litres, serial) adds litres to the truck's tank (takes them when negative); the truck
-- answers through answer(). onMoved(litres) changes the bed tank by litres (negative takes).
function M.new(change, onMoved)
  -- Serials start high so they never match the siphon's, whose answers come back the same way.
  local t = { serial = 1000000 }

  function t:active() return self.run ~= nil end
  function t:direction() return self.run and self.run.dir end

  function t:start(dir, clock)
    if self.run or (dir ~= 'toTruck' and dir ~= 'toBed') then return false end
    self.run = { dir = dir, moved = 0, nextAt = clock }
    return true
  end

  function t:finish(reason, clock)
    local run = self.run
    if not run then return nil end
    self.run = nil
    local text = RESULTS[run.dir][reason] or RESULTS[reason] or RESULTS.stopped
    if run.moved >= 0.5 then
      text = text .. string.format(' %d L moved %s.', math.floor(run.moved + 0.5), run.dir == 'toTruck' and 'into your truck' or 'into the bed tank')
    end
    return text
  end

  -- truck is the truck's tank reading ({ litres, capacity }), bed the bed tank's.
  function t:step(clock, truck, bed)
    local run = self.run
    if not run then return nil end
    if run.pending then
      if clock - run.pending.at > M.WAIT_SECONDS then return self:finish('lost', clock) end
      return nil
    end
    if clock < run.nextAt then return nil end
    if not (truck and finite(truck.litres) and finite(truck.capacity) and bed and finite(bed.litres) and finite(bed.capacity)) then
      return nil
    end
    local amount
    if run.dir == 'toTruck' then
      if bed.litres < M.EMPTY_LITRES then return self:finish('empty', clock) end
      local room = truck.capacity - truck.litres
      if room < M.EMPTY_LITRES then return self:finish('full', clock) end
      amount = math.min(M.RATE, bed.litres, room)
    else
      if truck.litres < M.EMPTY_LITRES then return self:finish('empty', clock) end
      local room = bed.capacity - bed.litres
      if room < M.EMPTY_LITRES then return self:finish('full', clock) end
      amount = -math.min(M.RATE, truck.litres, room)
    end
    run.nextAt = clock + 1
    self.serial = self.serial + 1
    run.pending = { serial = self.serial, at = clock }
    if not change(amount, self.serial) then return self:finish('lost', clock) end
  end

  -- The truck's answer. Returns handled.
  function t:answer(serial, before, after)
    local run = self.run
    if not (run and run.pending and run.pending.serial == serial) then return false end
    run.pending = nil
    if not (finite(before) and finite(after)) then return true end
    local moved = after - before -- into the truck
    onMoved(-moved)
    run.moved = run.moved + math.abs(moved)
    return true
  end

  return t
end

return M
