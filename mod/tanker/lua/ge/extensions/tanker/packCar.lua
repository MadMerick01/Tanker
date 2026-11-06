-- The game's side of the Hoon pack (pack.lua). A Hoon's car comes from BeamNG's own traffic when
-- traffic is running: a traffic car, the furthest from you, is taken out of traffic and moved into
-- place, which doesn't hitch. With no traffic car to take, the Hoon's own muscle car is loaded
-- (once per extra Hoon; loading a car mid-drive hitches) and kept hidden for next time.
--
-- Moving to a slot uses BeamNG's slotTraffic AI, which drives at a point at a speed, road or no
-- road. An attack uses BeamNG's chase AI aimed at you. Every game call is guarded: a missing or changed
-- one means no Hoon, never an error.
local M = {}

local function defaults()
  return {
    byId = function(id) return be and be:getObjectByID(id) end,
    traffic = function() return rawget(_G, 'gameplay_traffic') or (extensions and extensions.gameplay_traffic) end,
  }
end

-- Runs inside a Hoon's car: drive at this point at this speed, with BeamNG's slotTraffic AI.
-- It must hear again within half a second or it slows to a stop. With no such AI in the game, it
-- tells Tanker (once is enough; Tanker logs each problem once).
local SLOT = [[
if ai and ai.setSlotTrafficTarget then
  pcall(ai.setSlotTrafficTarget, %.2f, %.2f, %.2f, %.2f)
elseif obj then
  obj:queueGameEngineLua('if tanker_core then tanker_core.packProblem(%d, "no_slot_traffic_ai") end')
end
]]

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- hc is hoonCar: the player, the ground, and switching a car on, off, placing and hunting.
function M.new(hc, environment)
  local env = environment or defaults()
  local p = {}
  local fromTraffic = {} -- id -> true while a traffic car is a Hoon
  local spares, loaded = {}, {} -- our own hidden muscle cars, and every one we loaded

  local function car(id)
    local ok, c = pcall(env.byId, id)
    return ok and c or nil
  end
  local function traffic()
    local ok, t = pcall(env.traffic)
    if ok and type(t) == 'table' then return t end
  end

  function p:player() return hc:player() end
  function p:ground(x, y, z) return hc:ground(x, y, z) end
  function p:state(id) return hc:state(id) end
  function p:calm(id) return hc:calm(id) end
  function p:place(id, x, y, z, dx, dy) return hc:put(id, x, y, z, dx, dy) end
  function p:strike(id, targetId) return hc:hunt(id, targetId) end

  -- The traffic car furthest from you, taken out of traffic, or nil.
  local function takeTraffic(me)
    local t = traffic()
    if not (t and type(t.getTrafficData) == 'function' and type(t.removeTraffic) == 'function') then return nil end
    local ok, data = pcall(t.getTrafficData)
    if not ok or type(data) ~= 'table' then return nil end
    local best, bestMetres
    for id in pairs(data) do
      if type(id) == 'number' and id ~= me.id and not fromTraffic[id] then
        local s = hc:state(id)
        local metres = s and math.sqrt((s.x - me.x) ^ 2 + (s.y - me.y) ^ 2) or -1
        if s and (not bestMetres or metres > bestMetres) then best, bestMetres = id, metres end
      end
    end
    if not best or not pcall(t.removeTraffic, best) then return nil end
    fromTraffic[best] = true
    return best
  end

  -- A car for a new Hoon: from traffic, else a hidden one of ours, else a new one loaded.
  -- Returns its id and where it came from ('traffic' or 'own'), or nil and why.
  function p:take(me)
    local id = takeTraffic(me)
    if id then return id, 'traffic' end
    id = table.remove(spares)
    if id and car(id) then return id, 'own' end
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
    return (pcall(function() c:queueLuaCommand(string.format(SLOT, aim.x, aim.y, aim.z, aim.speed, id)) end))
  end

  -- Gives a traffic car back to traffic (which moves it on once you are out of sight), or hides
  -- one of ours for the next Hoon.
  function p:release(id, source)
    hc:calm(id)
    if source == 'traffic' then
      fromTraffic[id] = nil
      local t = traffic()
      if t and type(t.insertTraffic) == 'function' and pcall(t.insertTraffic, id) then return true end
      return false
    end
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
