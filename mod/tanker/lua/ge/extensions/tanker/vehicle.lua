-- The starter truck: Rowan's white D15 longbed dually with the i6 4.1, a 5-speed manual, a
-- bullbar and an XL tank in the bed (vehicles/pickup/tankerstarter.pc). This swaps the player's
-- vehicle for it where it stands, the way Earth Freight gives the player its starter car. Every
-- game call is guarded: a missing or changed one means no swap, never an error.
local M = {}

M.STARTER_MODEL = 'pickup'
M.STARTER_CONFIG = 'vehicles/pickup/tankerstarter.pc'
M.STARTER_NAME = 'TankerStarter'
-- The starter truck's picture, for the start page when the game can't name one.
M.STARTER_PREVIEW = '/vehicles/pickup/tankerstarter.jpg'

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    manager = function() return rawget(_G, 'core_vehicle_manager') or (extensions and extensions.core_vehicle_manager) end,
  }
end

function M.new(environment)
  local env = environment or defaults()
  local v = {}

  -- Asks the game to put the starter truck where the player's vehicle is: Rowan's config, or a
  -- saved config (the parts paid for) of the saved model. Returns true once the game took the
  -- request; the new truck arrives a moment later (the game's onVehicleSpawned).
  function v:spawnStarter(config, model)
    local okPlayer, player = pcall(env.player)
    if not okPlayer or not player then return false, 'vehicle_required' end
    local okVehicles, vehicles = pcall(env.vehicles)
    if not okVehicles or type(vehicles) ~= 'table' or type(vehicles.replaceVehicle) ~= 'function' then
      return false, 'spawn_unavailable'
    end
    local useSaved = type(config) == 'table' and type(model) == 'string' and model ~= ''
    local ok, why = pcall(vehicles.replaceVehicle, useSaved and model or M.STARTER_MODEL,
      { config = useSaved and config or M.STARTER_CONFIG, keepOtherVehRotation = true }, player)
    if not ok then return false, 'spawn_failed', tostring(why) end
    return true
  end

  -- Whether this vehicle id is the player's, so a spawn of some other car (traffic) is ignored.
  function v:isPlayer(id)
    local okPlayer, player = pcall(env.player)
    if not okPlayer or not player then return false end
    local okId, playerId = pcall(function() return player:getID() end)
    return okId and playerId == id
  end

  local function text(x) return type(x) == 'string' and x ~= '' and x or nil end
  local function number(x)
    x = tonumber(x)
    return x and x == x and x > -math.huge and x < math.huge and x or nil
  end
  local cache = {}

  -- The player's vehicle for the start page, like a character sheet: its model, name, picture and
  -- the game's figures for it. Read from the game's vehicle info and kept per vehicle and config.
  function v:describe()
    local okPlayer, player = pcall(env.player)
    if not okPlayer or not player then return nil end
    local okId, id = pcall(function() return player:getID() end)
    local okModel, model = pcall(function() return player:getJBeamFilename() end)
    if not (okId and okModel and text(model)) then return nil end
    local key
    local okManager, manager = pcall(env.manager or function() end)
    if okManager and type(manager) == 'table' and type(manager.getVehicleData) == 'function' then
      local okData, data = pcall(manager.getVehicleData, id)
      local file = okData and type(data) == 'table' and type(data.config) == 'table' and data.config.partConfigFilename
      key = type(file) == 'string' and file:match('([^/\\]+)%.pc$') or nil
    end
    local cacheKey = tostring(id) .. '|' .. model .. '|' .. tostring(key)
    if cache[cacheKey] then return cache[cacheKey] end
    local info, base = {}, {}
    local okVehicles, vehicles = pcall(env.vehicles)
    if okVehicles and type(vehicles) == 'table' then
      if key and type(vehicles.getConfig) == 'function' then
        local ok, found = pcall(vehicles.getConfig, model, key)
        if ok and type(found) == 'table' then info = found end
      end
      if type(vehicles.getModel) == 'function' then
        local ok, found = pcall(vehicles.getModel, model)
        if ok and type(found) == 'table' and type(found.model) == 'table' then base = found.model end
      end
    end
    local starter = model == M.STARTER_MODEL and (key == nil or key == 'tankerstarter')
    local card = {
      model = model,
      brand = text(info.Brand) or text(base.Brand),
      name = text(info.Name) or text(base.Name) or model,
      configuration = text(info.Configuration) or (starter and 'Tanker starter') or nil,
      preview = text(info.preview) or (starter and M.STARTER_PREVIEW) or text(base.preview),
      power = number(info.Power), weight = number(info.Weight), value = number(info.Value),
      drivetrain = text(info.Drivetrain), transmission = text(info.Transmission),
    }
    cache = { [cacheKey] = card }
    return card
  end

  return v
end

return M
