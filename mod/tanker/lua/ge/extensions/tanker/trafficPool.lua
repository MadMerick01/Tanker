-- Tanker's traffic: BeamNG's own traffic, but holding only Tanker's cars (Rowan, 6 Nov). Once the
-- run is on the road, traffic is set up with a pool of HoonOld1s and TankerMobs and nothing else,
-- which loads them all in one go, once. Any normal traffic already running is cleared first. A
-- normal traffic car that turns up later (from the game's own menu, say) is deleted on its own:
-- traffic is never set up a second time, since that loads every car again and the game stutters.
-- Traffic drives the pooled cars around and keeps the ones it doesn't need hidden, so when a Hoon
-- or a TankerMob is wanted, one is taken out of traffic and put into place, which doesn't hitch.
-- Parked cars aren't wanted either (Rowan, 6 Nov): any the game parked are deleted and parking is
-- switched off. Every game call is guarded: a missing or changed one means no pool, never an error.
local M = {}

-- One-line settings. Tune these after testing in game.
-- How many of each car the pool holds: enough Hoons for a full pack plus the road Hoon.
M.CARS = {
  { model = 'barstow', config = 'hoonold1', count = 5 },
  { model = 'us_semi', config = 'tankermob', count = 2 },
}
-- How many pooled cars traffic shows driving around at once; the rest wait hidden.
M.ACTIVE = 4
-- How often to look for normal traffic to delete, in seconds.
M.CHECK_SECONDS = 10
-- How long to wait for the pool to load before Hoons load their own car instead, in seconds.
M.WAIT_SECONDS = 20

local function defaults()
  return {
    traffic = function() return rawget(_G, 'gameplay_traffic') or (extensions and extensions.gameplay_traffic) end,
    byId = function(id) return be and be:getObjectByID(id) end,
    parking = function() return rawget(_G, 'gameplay_parking') or (extensions and extensions.gameplay_parking) end,
  }
end

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- The vehicle group traffic spawns: every car of M.CARS, as BeamNG's vehicle group lists them.
function M.group()
  local group = {}
  for _, car in ipairs(M.CARS) do
    for _ = 1, car.count do group[#group + 1] = { model = car.model, config = car.config } end
  end
  return group
end

local function ours(model)
  for _, car in ipairs(M.CARS) do if car.model == model then return true end end
  return false
end

function M.new(environment)
  local env = environment or defaults()
  -- state: NONE (not set up yet), LOADING (asked for, cars not in yet), READY, UNAVAILABLE
  local p = { state = 'NONE', nextCheck = 0 }

  local function traffic()
    local ok, t = pcall(env.traffic)
    if ok and type(t) == 'table' then return t end
  end
  local function data(t)
    if type(t.getTrafficData) ~= 'function' then return nil end
    local ok, d = pcall(t.getTrafficData)
    if ok and type(d) == 'table' then return d end
  end
  -- A car's model: from traffic's own record of it when there is one, else from the car.
  local function model(id, v)
    local key = type(v) == 'table' and type(v.model) == 'table' and v.model.key
    if type(key) == 'string' then return key end
    local ok, c = pcall(env.byId, id)
    if not (ok and c) then return nil end
    local okModel, name = pcall(function() return c:getJBeamFilename() end)
    if okModel and type(name) == 'string' then return name end
  end
  local function position(id)
    local ok, c = pcall(env.byId, id)
    if not (ok and c) then return nil end
    local okPos, x, y = pcall(function() local pos = c:getPosition(); return pos.x, pos.y end)
    if okPos and finite(x) and finite(y) then return x, y end
  end

  -- Counts the AI cars in traffic: Tanker's, and lists any others (normal traffic) by id.
  local function count(d)
    local mine, others = 0, {}
    for id, v in pairs(d) do
      if type(id) == 'number' and type(v) == 'table' and v.isAi then
        local name = model(id, v)
        if ours(name) then mine = mine + 1 else others[id] = tostring(name) end
      end
    end
    return mine, others
  end

  -- Deletes the game's parked cars and switches parking off. Returns how many went.
  local function noParking()
    local okP, parking = pcall(env.parking or function() end)
    if not (okP and type(parking) == 'table') then return 0 end
    local n = 0
    if type(parking.getParkedCarsList) == 'function' then
      local ok, list = pcall(parking.getParkedCarsList)
      if ok and type(list) == 'table' then n = #list end
    end
    if type(parking.getState) == 'function' then
      local ok, on = pcall(parking.getState)
      if ok and on and type(parking.setState) == 'function' then pcall(parking.setState, false) end
    end
    if n > 0 and type(parking.deleteVehicles) == 'function' then pcall(parking.deleteVehicles) end
    return n
  end

  local function setUp(t, clock)
    local group = M.group()
    local ok, started = pcall(t.setupTraffic, #group, 0, { vehGroup = group, activeAmount = M.ACTIVE })
    if not ok or started == false then
      p.state = 'UNAVAILABLE'
      return 'could not set up traffic: ' .. tostring(started)
    end
    p.state, p.since = 'LOADING', clock
    return nil
  end

  -- Called every sample while the run is on the road. Returns a line to log, if any.
  function p:step(clock)
    if self.state == 'UNAVAILABLE' then return nil end
    local t = traffic()
    if not (t and type(t.setupTraffic) == 'function') then
      self.state = 'UNAVAILABLE'
      return 'no traffic in this game'
    end
    local parked = noParking()
    local parkedLine = parked > 0 and ('removed ' .. parked .. ' parked cars') or nil
    if self.state == 'NONE' then
      self.nextCheck = clock + M.CHECK_SECONDS
      return setUp(t, clock) or ('loading ' .. #M.group() .. ' cars into traffic' .. (parkedLine and ('; ' .. parkedLine) or ''))
    end
    if parkedLine then return parkedLine end
    local d = data(t)
    if self.state == 'LOADING' then
      local mine = d and count(d) or 0
      if mine > 0 then self.state = 'READY'; return 'traffic holds ' .. mine .. ' of Tanker\'s cars' end
      if clock - self.since >= M.WAIT_SECONDS then self.state = 'READY'; return 'traffic did not load in time' end
      return nil
    end
    if clock < self.nextCheck or not d then return nil end
    self.nextCheck = clock + M.CHECK_SECONDS
    local _, others = count(d)
    local gone = {}
    for id, name in pairs(others) do
      if type(t.removeTraffic) == 'function' then pcall(t.removeTraffic, id, true) end
      local ok, c = pcall(env.byId, id)
      if ok and c then pcall(function() c:delete() end) end
      gone[#gone + 1] = name
    end
    if #gone > 0 then
      table.sort(gone)
      return 'deleted ' .. #gone .. ' normal traffic cars: ' .. table.concat(gone, ', ')
    end
  end

  -- Whether the pool is still loading, so a Hoon should wait for it instead of loading a car.
  function p:loading() return self.state == 'LOADING' end

  -- Takes a pooled car of this model out of traffic, the one furthest from x, y (so most likely
  -- out of sight). Returns its id, or nil.
  function p:take(name, x, y)
    local t = traffic()
    if not (t and type(t.removeTraffic) == 'function') then return nil end
    local d = data(t)
    if not d then return nil end
    local best, bestMetres
    for id, v in pairs(d) do
      if type(id) == 'number' and type(v) == 'table' and v.isAi and model(id, v) == name then
        local cx, cy = position(id)
        local metres = cx and math.sqrt((cx - (x or 0)) ^ 2 + (cy - (y or 0)) ^ 2) or 0
        if not bestMetres or metres > bestMetres then best, bestMetres = id, metres end
      end
    end
    if not best or not pcall(t.removeTraffic, best, true) then return nil end
    return best
  end

  return p
end

return M
