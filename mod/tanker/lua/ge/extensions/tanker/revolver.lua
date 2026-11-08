-- The flatscreen revolver: Tanker's own six-shooter for playing without VR (in VR, MadMerick's VR
-- revolver mod does the shooting). This is the logic only: drawn or holstered, the six-round
-- cylinder, spare rounds, the time between shots and reloading. aim.lua does the game's side.
local M = {}

-- One-line settings. Tune these after testing in game.
M.CYLINDER = 6
-- A new run starts with a full cylinder and this many spare rounds.
M.START_SPARE = 12
-- Seconds between shots, and how long a reload takes: the VR revolver's.
M.SHOT_SECONDS, M.RELOAD_SECONDS = 0.12, 1.5
M.MAX_SPARE = 999
-- While testing (MadMerick, 6 Nov): reloads never use up spare rounds. Set to false for real ammo.
M.INFINITE = true

local function count(n, most)
  return type(n) == 'number' and n == n and n >= 0 and n <= most and n == math.floor(n)
end

-- ammo is { loaded, spare } from the save, or nil for a new run's.
function M.new(ammo)
  local g = { drawn = false, lastShot = -math.huge }
  if type(ammo) == 'table' and count(ammo.loaded, M.CYLINDER) and count(ammo.spare, M.MAX_SPARE) then
    g.loaded, g.spare = ammo.loaded, ammo.spare
  else
    g.loaded, g.spare = M.CYLINDER, M.START_SPARE
  end

  function g:ammo() return { loaded = self.loaded, spare = self.spare } end

  function g:setDrawn(on)
    self.drawn = on == true
  end

  -- Starts a reload. Returns true, or false and why: 'full' or 'no_spare'.
  function g:reload(clock)
    if self.reloadAt then return true end
    if self.loaded >= M.CYLINDER then return false, 'full' end
    if self.spare <= 0 and not M.INFINITE then return false, 'no_spare' end
    self.reloadAt = clock + M.RELOAD_SECONDS
    return true
  end

  function g:reloading() return self.reloadAt ~= nil end

  -- Whether there are rounds to reload from.
  function g:hasSpare() return M.INFINITE or self.spare > 0 end

  -- Finishes a reload once its time is up. Returns true when it did.
  function g:step(clock)
    if not self.reloadAt or clock < self.reloadAt then return false end
    self.reloadAt = nil
    if M.INFINITE then
      self.loaded = M.CYLINDER
      return true
    end
    local moved = math.min(M.CYLINDER - self.loaded, self.spare)
    self.loaded, self.spare = self.loaded + moved, self.spare - moved
    return true
  end

  -- A pull of the trigger. Returns true when a round is fired, or false and why: 'holstered',
  -- 'reloading', 'cooldown' or 'empty' (which starts a reload if there are spare rounds).
  function g:fire(clock)
    if not self.drawn then return false, 'holstered' end
    if self.reloadAt then return false, 'reloading' end
    if clock - self.lastShot < M.SHOT_SECONDS then return false, 'cooldown' end
    if self.loaded <= 0 then
      self:reload(clock)
      return false, 'empty'
    end
    self.loaded, self.lastShot = self.loaded - 1, clock
    return true
  end

  -- Rounds found, from loot. Returns how many were taken.
  function g:addRounds(n)
    if type(n) ~= 'number' or n <= 0 then return 0 end
    local taken = math.min(math.floor(n), M.MAX_SPARE - self.spare)
    self.spare = self.spare + taken
    return taken
  end

  return g
end

return M
