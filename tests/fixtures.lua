-- Small fakes for the game: positions, a file store, and the adapter, fuel and pistol the core uses.
local F = {}
function F.position(lat, lon) return { latitude = lat or 0, longitude = lon or 0 } end

-- An in-memory file store with the same calls as the game's.
function F.io()
  local files, io = {}, { writes = 0 }
  io.files = files
  function io.exists(path) return files[path] ~= nil end
  function io.read(path) return files[path] end
  function io.mkdir() return true end
  function io.write(path, data)
    io.writes = io.writes + 1
    -- A copy, as a JSON round trip would make.
    local function copy(v) if type(v) ~= 'table' then return v end local o = {} for k, x in pairs(v) do o[k] = copy(x) end return o end
    files[path] = copy(data)
    return true
  end
  return io
end

-- An Earth that reports wherever the test puts the truck, and teleports it when asked.
function F.adapter(lat, lon)
  local a = { here = { valid = true, latitude = lat, longitude = lon, heading = 0, vehicle = { model = 'us_semi' } }, teleports = {} }
  if lat == nil then a.here = { valid = false, reason = 'earth_missing' } end
  function a:sample() return self.here end
  function a:put(lat2, lon2) self.here = { valid = true, latitude = lat2, longitude = lon2, heading = 0, vehicle = { model = 'us_semi' } } end
  -- Earth's rocks: shown unless asked to hide them (or Earth hides them itself).
  a.rocksShown, a.rockCalls = true, 0
  function a:rocks(wanted)
    self.rockCalls = self.rockCalls + 1
    if self.earthRocksOff then return wanted and 'hidden_by_earth' or 'hidden' end
    self.rocksShown = wanted == true
    return wanted and 'shown' or 'hidden'
  end
  function a:restoreRocks() self.rocksShown = true end
  function a:teleport(point, name) self.teleports[#self.teleports + 1] = { point = point, name = name }; return self.refuse == nil, self.refuse end
  return a
end

function F.fuel()
  local f = { reads = 0, sets = {} }
  function f:read() self.reads = self.reads + 1; return true end
  function f:set(litres, serial) self.sets[#self.sets + 1] = { litres = litres, serial = serial }; return true end
  f.changes = {}
  function f:change(litres, serial, id) self.changes[#self.changes + 1] = { litres = litres, serial = serial, id = id }; return true end
  return f
end

-- The bed tank: records what it was filled with and how often its size was asked for.
function F.bed()
  local b = { sets = {}, reads = 0 }
  function b:set(litres) self.sets[#self.sets + 1] = litres; return true end
  function b:read() self.reads = self.reads + 1; return true end
  return b
end

-- Cars near the player: the test says which car is how far, and how fast the player goes.
function F.nearby(cars, speed)
  local n = { cars = cars or {}, speed = speed or 0 }
  function n:closest(id)
    local best
    for carId, metres in pairs(self.cars) do
      if (id == nil or carId == id) and (not best or metres < best.metres) then best = { id = carId, metres = metres } end
    end
    return best, { id = 7, speed = self.speed }
  end
  return n
end

function F.pistol(state)
  local p = { state = state or { installed = false } }
  function p:read() return self.state end
  function p:leftHand() return self.hand end
  return p
end

-- The game's vehicles: records starter truck requests; the test says when the truck arrives.
function F.vehicles(refuse)
  local v = { spawns = 0, playerId = 7 }
  function v:spawnStarter() if refuse then return false, refuse end self.spawns = self.spawns + 1; return true end
  function v:isPlayer(id) return id == self.playerId end
  return v
end

-- A controller with fakes, and what it sent to the HUD.
function F.controller(adapter, extra)
  local core = require('tanker/core')
  local sent = {}
  local env = { io = F.io(), adapter = adapter or F.adapter(-34.19, 138.14), fuel = F.fuel(), pistol = F.pistol(),
    trigger = function(event, view) sent[#sent + 1] = { event = event, view = view } end }
  for k, v in pairs(extra or {}) do env[k] = v end
  local c = core.new(env)
  return c, env, sent
end
return F
