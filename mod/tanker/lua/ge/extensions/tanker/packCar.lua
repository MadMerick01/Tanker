-- The game's side of the Hoon pack (pack.lua). Every Hoon drives Rowan's HoonOld1, a rusty Barstow
-- shipped in the mod. Its car is taken out of Tanker's traffic pool (trafficPool.lua), which loaded
-- it with the rest of traffic, so it doesn't hitch; only with none left is one loaded. Once a Hoon
-- is done its car is kept hidden, so a later Hoon reuses it at once.
--
-- Moving to a slot uses Tanker's own desert driver (tankerDriver.lua, in the car), which drives at
-- a point at a speed, road or no road, for moving between slots and for attacks alike. Every game call is guarded: a missing or changed
-- one means no Hoon, never an error.
local M = {}

local function defaults()
  return {
    byId = function(id) return be and be:getObjectByID(id) end,
  }
end

-- Runs inside a Hoon's car: drive at this point at this speed with Tanker's own desert driver
-- (lua/vehicle/extensions/tankerDriver.lua). If it can't be loaded, BeamNG's slotTraffic AI
-- drives instead, which must hear again within half a second or it slows to a stop. With
-- neither, it tells Tanker (Tanker logs each problem once).
local SLOT = [[
if extensions and not extensions.tankerDriver then pcall(extensions.load, 'tankerDriver') end
if extensions and extensions.tankerDriver then
  extensions.tankerDriver.target(%.2f, %.2f, %.2f, %.2f, %s)
elseif ai and ai.setSlotTrafficTarget then
  pcall(ai.setSlotTrafficTarget, %.2f, %.2f, %.2f, %.2f)
  if obj then obj:queueGameEngineLua('if tanker_core then tanker_core.packProblem(%d, "no_tanker_driver") end') end
elseif obj then
  obj:queueGameEngineLua('if tanker_core then tanker_core.packProblem(%d, "no_driver_ai") end')
end
]]
-- The driving modes a point may ask for (see tankerDriver.control), as Lua in the command.
local MODES = { coast = '"coast"', swipe = '"swipe"' }
-- Hands the car back from Tanker's driver, before BeamNG's AI takes over or is switched off.
local LET_GO = [[if extensions and extensions.tankerDriver then extensions.tankerDriver.stop() end]]

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- hc is hoonCar: the player, the ground, and switching a car on, off, placing and hunting.
function M.new(hc, environment)
  local env = environment or defaults()
  local p = {}
  local spares, loaded = {}, {} -- our own hidden HoonOld1 cars, and every one we loaded

  -- Never the player's own vehicle: if the game puts you in a Hoon's car, it stops being a Hoon.
  local function car(id)
    local me = hc:player()
    if id == nil or (me and me.id == id) then return nil end
    local ok, c = pcall(env.byId, id)
    return ok and c or nil
  end

  function p:player() return hc:player() end
  function p:ground(x, y, z) return hc:ground(x, y, z) end
  function p:camera() return hc.camera and hc:camera() end
  function p:state(id) return hc:state(id) end
  local function letGo(id)
    local c = car(id)
    if c then pcall(function() c:queueLuaCommand(LET_GO) end) end
  end
  function p:calm(id) letGo(id); return hc:calm(id) end
  function p:place(id, x, y, z, dx, dy) return hc:put(id, x, y, z, dx, dy) end
  function p:hop(id, x, y, z, dx, dy) return (hc.hop and hc:hop(id, x, y, z, dx, dy)) or hc:put(id, x, y, z, dx, dy) end
  function p:road(x, y, z) return hc:road(x, y, z) end
  -- Road mode: the Hoon's own driver hunts targetId along the roads.
  function p:chase(id, targetId) return hc:hunt(id, targetId) end

  -- A car for a new Hoon: a hidden one of ours, else a HoonOld1 from Tanker's traffic pool, else a
  -- new one loaded (hoonCar.lua does both).
  -- Returns its id and where it came from ('own'), or nil and why.
  function p:take()
    local id = table.remove(spares)
    while id and not car(id) do id = table.remove(spares) end
    if id then return id, 'own' end
    local why, detail
    id, why, detail = hc:load()
    if not id then return nil, tostring(why) .. (detail and (': ' .. detail) or '') end
    loaded[#loaded + 1] = id
    return id, 'own'
  end

  -- aim: x, y, z to drive at and speed in metres a second.
  function p:goTo(id, aim)
    local c = car(id)
    if not (c and aim and finite(aim.x) and finite(aim.y) and finite(aim.z) and finite(aim.speed)) then return false end
    return (pcall(function() c:queueLuaCommand(string.format(SLOT, aim.x, aim.y, aim.z, aim.speed, MODES[aim.mode] or 'nil', aim.x, aim.y, aim.z, aim.speed, id, id)) end))
  end

  -- Hides the Hoon's car for the next Hoon.
  function p:release(id)
    letGo(id)
    hc:calm(id)
    if car(id) then
      hc:hide(id)
      spares[#spares + 1] = id
    end
    return true
  end

  -- Deletes the cars we loaded, when Tanker goes away.
  function p:removeAll()
    for _, id in ipairs(loaded) do hc:remove(id) end
    loaded, spares = {}, {}
  end

  return p
end

return M
