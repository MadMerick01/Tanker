-- The starter truck: Rowan's white D15 longbed dually with the i6 4.1, a 5-speed manual, a
-- bullbar and an XL tank in the bed (vehicles/pickup/tankerstarter.pc). This swaps the player's
-- vehicle for it where it stands, the way Earth Freight gives the player its starter car. Every
-- game call is guarded: a missing or changed one means no swap, never an error.
local M = {}

M.STARTER_MODEL = 'pickup'
M.STARTER_CONFIG = 'vehicles/pickup/tankerstarter.pc'
M.STARTER_NAME = 'TankerStarter'

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
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

  return v
end

return M
