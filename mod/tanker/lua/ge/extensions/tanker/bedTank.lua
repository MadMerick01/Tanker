-- The fluid tank in the truck's bed. BeamNG has no fill level for a cargo tank: the fuel in it is
-- Tanker's own number, kept in the save, and this pours that much into the tank's fluid containers
-- so the truck carries its weight and it sloshes. Copied from Earth Freight's cargo.lua. The truck
-- answers with the tank's capacity through tanker_core.bedRead (0 when no tank is fitted).
local M = {}

-- One-line settings. Fuel weighs about this many kg a litre.
M.DENSITY = 0.75

local function defaults()
  return { player = function() return getPlayerVehicle(0) end }
end

-- Runs inside the car. Finds the car's fluid containers: the cargoStorage entries of its jbeam
-- whose cargo types include fluid. Each one's nodes and beams (same cargoGroup and partPath) carry
-- expressions in $volume and $density, so the part's author decides how the fluid weighs and
-- sloshes; legacy containers only list weightNodes, which share the fluid's weight.
local CONTAINERS = [[
local okParser, parser = pcall(require, 'jbeam/expressionParser')
-- Without the parser the expressions cannot be worked out, and only legacy containers fill.
okParser = okParser and type(parser) == 'table' and type(parser.compileSafe) == 'function'
local function isFluid(c)
  for _, t in pairs(type(c.cargoTypes) == 'table' and c.cargoTypes or {}) do
    if type(t) == 'string' and t:lower():find('fluid', 1, true) then return true end
  end
  return tanks[c.partOrigin] == true
end
local function member(e, c)
  return e.cargoGroup ~= nil and tostring(e.cargoGroup) == tostring(c.groupId) and tostring(e.partPath or '') == tostring(c.partPath or '')
end
local containers, capacity = {}, 0
local storage = v and v.data and type(v.data.cargoStorage) == 'table' and v.data.cargoStorage or {}
for _, c in pairs(storage) do
  if type(c) == 'table' and c.groupId ~= nil and isFluid(c) then
    local entry = { size = math.max(0, tonumber(c.capacity) or 0), nodes = {}, beams = {}, legacy = {} }
    for _, n in pairs(okParser and type(v.data.nodes) == 'table' and v.data.nodes or {}) do
      if type(n) == 'table' and n.cid and type(n.nodeWeightFunction) == 'string' and member(n, c) then entry.nodes[#entry.nodes + 1] = n end
    end
    for _, b in pairs(okParser and type(v.data.beams) == 'table' and v.data.beams or {}) do
      if type(b) == 'table' and b.cid and member(b, c) then entry.beams[#entry.beams + 1] = b end
    end
    local weightNodes = c['weightNodes:'] or c.weightNodes
    if #entry.nodes == 0 and type(weightNodes) == 'table' then
      for _, ref in pairs(weightNodes) do
        for _, n in pairs(type(v.data.nodes) == 'table' and v.data.nodes or {}) do
          if type(n) == 'table' and n.cid and (n.cid == ref or (n.name ~= nil and n.name == ref)) then entry.legacy[#entry.legacy + 1] = n break end
        end
      end
    end
    if entry.size > 0 and (#entry.nodes + #entry.beams + #entry.legacy) > 0 then
      containers[#containers + 1] = entry
      capacity = capacity + entry.size
    end
  end
end
local function report()
  if id then obj:queueGameEngineLua(string.format('if tanker_core then tanker_core.bedRead(%d, %.3f) end', id, capacity)) end
end
]]

-- Runs inside the car after CONTAINERS: fills every container to the same share of full so the
-- total is the litres asked for, then reports the capacity.
local LOAD = [[
local litres, density = %s, %s
if not (v and v.data and type(v.data.nodes) == 'table' and obj and obj.setNodeMass) then report() return end
local compiled = {}
local function value(expr, volume)
  if type(expr) ~= 'string' or not okParser then return nil end
  local f = compiled[expr]
  if f == nil then
    local ok, fun, vars = pcall(parser.compileSafe, '$' .. expr)
    f = (ok and type(fun) == 'function' and type(vars) == 'table') and { fun = fun, vars = vars } or false
    compiled[expr] = f
  end
  if not f then return nil end
  f.vars['$volume'], f.vars['$density'], f.vars['$load'] = volume, density, volume * density
  local ok, result = pcall(f.fun)
  if ok and type(result) == 'number' and result == result then return result end
  return nil
end
local function call(name, ...)
  if type(obj[name]) == 'function' then pcall(obj[name], obj, ...) end
end
local function fill(c, volume)
  for _, n in ipairs(c.nodes) do
    local mass = value(n.nodeWeightFunction, volume)
    if mass then obj:setNodeMass(n.cid, mass) end
  end
  for _, n in ipairs(c.legacy) do
    if type(n.nodeWeight) == 'number' then obj:setNodeMass(n.cid, n.nodeWeight + volume * density / #c.legacy) end
  end
  for _, b in ipairs(c.beams) do
    if b.beamSpringFunction or b.beamDampFunction then
      call('setBeamSpringDamp', b.cid, value(b.beamSpringFunction, volume) or b.beamSpring or -1, value(b.beamDampFunction, volume) or b.beamDamp or -1, -1, -1)
    end
    if b.beamLimitSpringFunction or b.beamLimitDampFunction then
      call('setBoundedBeamSpringDampLimits', b.cid, value(b.beamLimitSpringFunction, volume) or b.beamLimitSpring or -1, value(b.beamLimitDampFunction, volume) or b.beamLimitDamp or -1, -1)
    end
    local strength, deform = value(b.beamStrengthFunction, volume), value(b.beamDeformFunction, volume)
    if strength then call('setBeamStrength', b.cid, strength) end
    if deform then call('setBeamDeform', b.cid, deform) end
    local short, long = value(b.beamShortBoundFunction, volume), value(b.beamLongBoundFunction, volume)
    if short then call('setBoundedBeamShortBound', b.cid, short) end
    if long then call('setBoundedBeamLongBound', b.cid, long) end
    local precompression = value(b.beamPrecompressionFunction, volume)
    if precompression then call('setPrecompressionRatio', b.cid, precompression) end
  end
end
local share = capacity > 0 and math.max(0, math.min(1, litres / capacity)) or 0
for _, c in ipairs(containers) do fill(c, c.size * share) end
report()
]]

local function number(x)
  return string.format('%.3f', (type(x) == 'number' and x == x and x > 0 and x < math.huge) and x or 0)
end

function M.new(environment)
  local env = environment or defaults()
  local b = {}

  local function send(build)
    local okVehicle, vehicle = pcall(env.player)
    if not okVehicle or not vehicle then return false, 'vehicle_required' end
    local idOK, id = pcall(function() return vehicle:getID() end)
    local ok, why = pcall(function() vehicle:queueLuaCommand(build(idOK and type(id) == 'number' and tostring(id) or 'nil')) end)
    if not ok then return false, 'bed_failed', tostring(why) end
    return true
  end

  -- Pours this many litres into the bed tank (0 empties it). The car reports its capacity.
  function b:set(litres)
    return send(function(id)
      return 'local id, tanks = ' .. id .. ', {}\n' .. CONTAINERS .. string.format(LOAD, number(litres), number(M.DENSITY))
    end)
  end

  -- Asks the car how many litres its bed tank holds.
  function b:read()
    return send(function(id) return 'local id, tanks = ' .. id .. ', {}\n' .. CONTAINERS .. 'report()\n' end)
  end

  return b
end

return M
