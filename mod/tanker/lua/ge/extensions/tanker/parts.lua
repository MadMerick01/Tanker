-- The truck's parts and damage, for paying for part changes in fuel. Copied from Earth Freight's
-- garage.lua: reads the fitted parts and their jbeam prices, the car's game Value and its damage,
-- and puts a set of parts back by respawning the truck. Base-game calls only, every one guarded:
-- a missing or changed one means no reading, never an error.
local M = {}

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    -- GE keeps each vehicle's beamstate damage in map.objects[id].damage.
    objects = function() local m = rawget(_G, 'map'); return type(m) == 'table' and m.objects or nil end,
    manager = function() return rawget(_G, 'core_vehicle_manager') or (extensions and extensions.core_vehicle_manager) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    -- jbeam/io looks up a part's jbeam data, whose information.value is the price career uses.
    jbeam = function() return require('jbeam/io') end,
  }
end

local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end
M.copy = copy

-- Flattens a partsTree into { [slot path] = part name }; an empty slot has part name ''.
local function fitted(node, out)
  if type(node) ~= 'table' then return out end
  if type(node.chosenPartName) == 'string' then out[tostring(node.path or node.id or '')] = node.chosenPartName end
  if type(node.children) == 'table' then
    for _, child in pairs(node.children) do fitted(child, out) end
  end
  return out
end
M.fitted = fitted

function M.new(environment)
  local env = environment or defaults()
  local g = {}

  local function call(name) local ok, v = pcall(env[name] or function() end); return ok and v or nil end

  local function current()
    local vehicle = call('vehicle')
    if not vehicle then return nil end
    local idOK, id = pcall(function() return vehicle:getID() end)
    if not idOK or id == nil then return nil end
    return vehicle, id
  end

  local function vehicleData(id)
    local manager = call('manager')
    if type(manager) ~= 'table' or type(manager.getVehicleData) ~= 'function' then return nil end
    local ok, data = pcall(manager.getVehicleData, id)
    return ok and type(data) == 'table' and type(data.config) == 'table' and data or nil
  end

  -- A part's price and name from its jbeam information, or nothing when unreadable.
  local function partInfo(data, partName)
    local jbeam = call('jbeam')
    if type(jbeam) ~= 'table' or type(jbeam.getPart) ~= 'function' or data.ioCtx == nil then return nil end
    local partOK, part = pcall(jbeam.getPart, data.ioCtx, partName)
    local info = partOK and type(part) == 'table' and part.information or nil
    if type(info) ~= 'table' then return nil end
    local value = tonumber(info.value)
    if value and (value ~= value or value < 0 or value == math.huge) then value = nil end
    return value, type(info.name) == 'string' and info.name or nil
  end

  -- The car config's game Value (from its info file), or nil.
  local function carValue(model, configFile)
    local key = type(configFile) == 'string' and configFile:match('([^/\\]+)%.pc$') or nil
    local vehicles = call('vehicles')
    if not (key and type(model) == 'string' and type(vehicles) == 'table' and type(vehicles.getConfig) == 'function') then return nil end
    local ok, info = pcall(vehicles.getConfig, model, key)
    local value = ok and type(info) == 'table' and tonumber(info.Value) or nil
    if value and (value ~= value or value < 0 or value == math.huge) then value = nil end
    return value
  end

  -- The truck's damage: { id, damage }, or nil.
  function g:inspect()
    local vehicle, id = current()
    if not vehicle then return nil end
    local objects = call('objects')
    local entry = type(objects) == 'table' and objects[id] or nil
    local damage = type(entry) == 'table' and tonumber(entry.damage) or nil
    if not damage or damage ~= damage or damage == math.huge or damage < 0 then return nil end
    return { id = id, damage = damage }
  end

  -- The truck's fitted parts: { id, model, config, parts = { [slot] = part }, values = { [part] =
  -- price or nil }, names = { [part] = name }, value }, or nil and a reason.
  function g:parts()
    local vehicle, id = current()
    if not vehicle then return nil, 'vehicle_required' end
    local data = vehicleData(id)
    if not data or type(data.config.partsTree) ~= 'table' then return nil, 'parts_unavailable' end
    local list = fitted(data.config.partsTree, {})
    local values, names = {}, {}
    for _, partName in pairs(list) do
      if partName ~= '' and names[partName] == nil then
        local value, name = partInfo(data, partName)
        values[partName], names[partName] = value, name or partName
      end
    end
    local model = data.config.model
    if type(model) ~= 'string' or model == '' then
      local ok, filename = pcall(function() return vehicle:getJBeamFilename() end)
      model = ok and filename or nil
    end
    local configFile = type(data.config.partConfigFilename) == 'string' and data.config.partConfigFilename or nil
    return { id = id, model = model, config = copy(data.config), parts = list, values = values, names = names,
      value = carValue(model, configFile) }
  end

  -- Respawns the truck where it stands with this config's parts, keeping its tuning and paint.
  -- Returns true once the game took it.
  function g:restore(config, model)
    local vehicle, id = current()
    if not vehicle then return false, 'vehicle_required' end
    local vehicles = call('vehicles')
    if type(vehicles) ~= 'table' or type(vehicles.replaceVehicle) ~= 'function' then return false, 'restore_unavailable' end
    local data = vehicleData(id)
    local wanted = copy(config)
    if type(wanted) ~= 'table' then return false, 'config_unavailable' end
    if data then wanted.vars, wanted.paints = copy(data.config.vars), copy(data.config.paints) end
    model = model or wanted.model
    if type(model) ~= 'string' or model == '' then return false, 'config_unavailable' end
    local ok, why = pcall(vehicles.replaceVehicle, model, { config = wanted, keepOtherVehRotation = true }, vehicle)
    if not ok then return false, 'restore_failed', tostring(why) end
    return true
  end

  return g
end

return M
