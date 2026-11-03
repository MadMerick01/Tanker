-- Two alternating JSON save slots; the newest readable one is loaded. Loading never writes files.
-- Copied from Earth Freight: the slots, validation and vehicle config copy are the same. The schema
-- holds one hardcore run: where it started, where the truck was saved, the truck and its fuel, and
-- how far it has come. There is one run and no going back to an earlier save.
local location = require('tanker/location')
local M = { DIRECTORY = '/settings/tanker/', SCHEMA = 1 }
local MAX_INTEGER = 9007199254740991

local function integer(n, minimum)
  return location.finite(n) and n >= minimum and n <= MAX_INTEGER and n == math.floor(n)
end
local function optionalString(s)
  return s == nil or (type(s) == 'string' and #s > 0 and #s <= 512 and not s:find('%c'))
end
local function amount(n)
  return n == nil or (location.finite(n) and n >= 0 and n <= MAX_INTEGER)
end

-- Copies a saved vehicle config (the game's own config table: model, partsTree, vars, paints),
-- keeping only plain JSON data and refusing anything oversized. Returns nil when unusable.
local MAX_CONFIG_DEPTH, MAX_CONFIG_VALUES = 64, 50000
local function plainConfig(config)
  local count = 0
  local function copy(value, depth)
    count = count + 1
    if count > MAX_CONFIG_VALUES or depth > MAX_CONFIG_DEPTH then return nil, false end
    local kind = type(value)
    if kind == 'string' then return value, #value <= 4096 end
    if kind == 'boolean' then return value, true end
    if kind == 'number' then return value, location.finite(value) end
    if kind ~= 'table' then return nil, false end
    local out = {}
    for k, v in pairs(value) do
      if type(k) ~= 'string' and not (type(k) == 'number' and integer(k, 1)) then return nil, false end
      local item, ok = copy(v, depth + 1)
      if not ok then return nil, false end
      out[k] = item
    end
    return out, true
  end
  if type(config) ~= 'table' or type(config.model) ~= 'string' or config.model == '' then return nil end
  local out, ok = copy(config, 1)
  return ok and out or nil
end
M.plainConfig = plainConfig

-- A saved position, with the altitude and heading when present. Returns a clean copy, or nil and why.
local function pose(r)
  if not location.valid(r) then return nil, 'invalid_coordinates' end
  local out = location.copy(r)
  if r.altitude ~= nil then
    if not location.finite(r.altitude) or r.altitude < -20000 or r.altitude > 1000000 then return nil, 'invalid_altitude' end
    out.altitude = r.altitude
  end
  if r.heading ~= nil then
    if not location.finite(r.heading) or r.heading < 0 or r.heading >= 360 then return nil, 'invalid_heading' end
    out.heading = r.heading
  end
  return out
end

-- How far the run has come: km driven, and the litres burnt over the km measured for the range.
local function run(r)
  if type(r) ~= 'table' or not amount(r.drivenKm) or r.drivenKm == nil then return nil end
  if not amount(r.usedLitres) or not amount(r.rangeKm) then return nil end
  return { drivenKm = r.drivenKm, usedLitres = r.usedLitres, rangeKm = r.rangeKm }
end

function M.validate(s)
  if type(s) ~= 'table' then return nil, 'invalid_document' end
  if s.schemaVersion ~= M.SCHEMA then return nil, 'unsupported_schema' end
  if s.profileId ~= 'default' or not integer(s.generation, 1) then return nil, 'invalid_identity' end
  if not location.valid(s.start) then return nil, 'invalid_coordinates' end
  local resume, poseWhy = pose(s.resume)
  if not resume then return nil, poseWhy end
  local r = run(s.run)
  if not r then return nil, 'invalid_run' end
  if type(s.vehicle) ~= 'table' or not optionalString(s.vehicle.model)
      or not optionalString(s.vehicle.configuration) or not amount(s.vehicle.fuelLitres)
      or not amount(s.vehicle.bedLitres) then return nil, 'invalid_vehicle' end
  -- The flatscreen revolver's rounds, when saved.
  local ammo = nil
  if s.vehicle.ammo ~= nil then
    local a = s.vehicle.ammo
    if type(a) ~= 'table' or not integer(a.loaded, 0) or a.loaded > 6 or not integer(a.spare, 0) or a.spare > 999 then
      return nil, 'invalid_vehicle'
    end
    ammo = { loaded = a.loaded, spare = a.spare }
  end
  local vehicleConfig = nil
  if s.vehicle.config ~= nil then
    vehicleConfig = plainConfig(s.vehicle.config)
    if not vehicleConfig then return nil, 'invalid_vehicle' end
  end
  return {
    schemaVersion = M.SCHEMA, profileId = 'default', generation = s.generation,
    start = location.copy(s.start), resume = resume, run = r,
    vehicle = { model = s.vehicle.model, configuration = s.vehicle.configuration, config = vehicleConfig,
      fuelLitres = s.vehicle.fuelLitres, bedLitres = s.vehicle.bedLitres, ammo = ammo },
  }
end

function M.newProfile(start, here, vehicle)
  return {
    schemaVersion = M.SCHEMA, profileId = 'default', generation = 0,
    start = location.copy(start), resume = location.copy(here), run = { drivenKm = 0 },
    vehicle = { model = vehicle and vehicle.model, configuration = vehicle and vehicle.configuration },
  }
end

function M.new(io)
  local store = { generation = 0, slot = nil, blocked = true }
  local paths = { a = M.DIRECTORY .. 'save-a.json', b = M.DIRECTORY .. 'save-b.json' }

  -- Returns the newest readable save, or nil and why: 'missing' (no save files), 'unreadable'
  -- (files exist but none can be read; saving replaces them), 'newer_version' or 'storage_unavailable'.
  function store:load()
    self.generation, self.slot, self.blocked = 0, nil, true
    local valid, unreadable = {}, false
    for _, slot in ipairs({ 'a', 'b' }) do
      local ok, present = pcall(io.exists, paths[slot])
      if not ok or type(present) ~= 'boolean' then return nil, 'storage_unavailable' end
      if present then
        local readOK, data = pcall(io.read, paths[slot])
        -- A save from a newer Tanker is never overwritten, even if the other slot is readable.
        if readOK and type(data) == 'table' and data.schemaVersion ~= nil and data.schemaVersion ~= M.SCHEMA then
          return nil, 'newer_version'
        end
        local save = readOK and M.validate(data) or nil
        if save then valid[#valid + 1] = { slot = slot, data = save } else unreadable = true end
      end
    end
    self.blocked = false
    if #valid == 0 then return nil, unreadable and 'unreadable' or 'missing' end
    table.sort(valid, function(a, b)
      if a.data.generation ~= b.data.generation then return a.data.generation > b.data.generation end
      return a.slot < b.slot
    end)
    local best = valid[1]
    self.generation, self.slot = best.data.generation, best.slot
    return best.data, 'loaded'
  end

  -- Writes the slot not holding the newest save, so a failed write never touches it. A failure
  -- changes nothing here, so Save can simply be tried again.
  function store:save(candidate)
    if self.blocked then return nil, 'storage_locked' end
    if self.generation >= MAX_INTEGER then return nil, 'generation_limit' end
    -- Build a new value: never change the caller's profile.
    local prepared = {
      schemaVersion = candidate.schemaVersion, profileId = candidate.profileId,
      generation = self.generation + 1, start = candidate.start, resume = candidate.resume,
      run = candidate.run, vehicle = candidate.vehicle,
    }
    local clean, why = M.validate(prepared)
    if not clean then return nil, why end
    local dirOK, made = pcall(io.mkdir, M.DIRECTORY)
    if not dirOK or made == false then return nil, 'directory_failed' end
    local slot = self.slot == 'a' and 'b' or 'a'
    local ok, result = pcall(io.write, paths[slot], clean)
    if not ok or result == false then return nil, 'write_failed' end
    -- The file must read back as a valid save of this generation.
    local readOK, readback = pcall(io.read, paths[slot])
    local checked = readOK and M.validate(readback) or nil
    if not checked or checked.generation ~= clean.generation then return nil, 'verification_failed' end
    self.slot, self.generation = slot, clean.generation
    return clean, 'saved'
  end
  return store
end

return M
