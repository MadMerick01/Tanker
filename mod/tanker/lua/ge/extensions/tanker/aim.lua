-- The game's side of the flatscreen revolver: aiming with the mouse, the crosshair, the shot and
-- the hit. Adapted from Rowan's Bolides The Cut (FirstPersonShoot.lua and BulletDamage.lua): the
-- shot is a ray from the camera through the mouse, snapped to a nearby car, and a hit pushes and
-- dents the car where the round lands. Every game call is guarded: a missing or changed one means
-- no shot, never an error.
local M = {}

-- One-line settings. Tune these after testing in game.
-- How far a round reaches, in metres.
M.RANGE_METRES = 250
-- A shot that passes within this many metres of a car's centre hits it.
M.SNAP_METRES = 6
-- Hits ignore anything this close to the camera (your own truck's cab).
M.NEAR_METRES = 2
-- How hard a round hits: the push on the nearest point of the car, and the dent around it.
M.IMPACT_FORCE, M.DENT_RADIUS, M.DENT_FORCE = 6000, 1.3, 70
-- The crosshair: half its size and its thickness, in pixels, and its colour (amber, ImGui ABGR).
M.CROSSHAIR_SIZE, M.CROSSHAIR_THICKNESS, M.CROSSHAIR_COLOUR = 14, 3, 0xFF00BFFF

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function defaults()
  return {
    imgui = function() return rawget(_G, 'ui_imgui') end,
    player = function() return getPlayerVehicle(0) end,
    byId = function(id) return be and be:getObjectByID(id) end,
    -- Whether a VR session is running: then the VR revolver mod does the shooting.
    vr = function()
      local xr = rawget(_G, 'render_openxr')
      if xr and xr.isSessionRunning then
        local ok, running = pcall(xr.isSessionRunning)
        if ok and running ~= nil then return running == true end
      end
      local o = rawget(_G, 'OpenXR')
      if o and o.getEnable then
        local ok, on = pcall(o.getEnable)
        if ok then return on == true end
      end
      return false
    end,
    -- The ray from the camera through the mouse: origin and direction as vec3s.
    mouseRay = function()
      local pos = getCameraPosition and getCameraPosition()
      local ray = getCameraMouseRay and getCameraMouseRay()
      if not (pos and ray and ray.dir) then return nil end
      local dir = vec3(ray.dir)
      if dir:length() < 0.001 then return nil end
      return vec3(pos), dir:normalized()
    end,
    castRay = function(from, to) return castRay and castRay(from, to) end,
    vehicles = function()
      local out = {}
      if not (scenetree and scenetree.findClassObjects) then return out end
      for _, name in ipairs(scenetree.findClassObjects('BeamNGVehicle') or {}) do
        local car = scenetree.findObject(name)
        if car and car.getID then out[#out + 1] = car end
      end
      return out
    end,
    drawSphere = function(pos, radius)
      if debugDrawer and ColorF then debugDrawer:drawSphere(pos, radius, ColorF(1, 0.75, 0.1, 0.95)) end
    end,
  }
end

-- Runs inside the car that was hit: pushes the node nearest the impact along the shot, and dents
-- the car around it. From Bolides The Cut's BulletDamage.
local IMPACT = [[
local impact = vec3(%0.4f, %0.4f, %0.4f) - obj:getPosition()
local dir = vec3(%0.5f, %0.5f, %0.5f)
local best, bestD = nil, math.huge
for i = 0, #v.data.nodes do
  local n = v.data.nodes[i]
  if n then
    local d = (obj:getNodePosition(n.cid) - impact):squaredLength()
    if d < bestD then best, bestD = n.cid, d end
  end
end
if best then
  local mass = obj.getNodeMass and obj:getNodeMass(best) or 1
  obj:applyForceVector(best, dir * %0.1f * (mass or 1))
end
local r2, r1, push = %0.3f, %0.3f * 0.5, %0.3f * 2000
for i = 0, #v.data.nodes do
  local n = v.data.nodes[i]
  if n then
    local offset = obj:getNodePosition(n.cid) - impact
    local d = offset:length()
    if d <= r2 and d > 1e-4 then
      local share = math.max(0, math.min(1, 1 - (d - r1) / (r2 - r1)))
      local sign = math.random() < 0.3 and -1 or 1
      obj:applyForceVector(n.cid, offset:normalized() * sign * push * share)
    end
  end
end
]]

function M.new(environment)
  local env = environment or defaults()
  local a = {}

  local function call(name, ...)
    local f = env[name]
    if type(f) ~= 'function' then return nil end
    local ok, x, y = pcall(f, ...)
    if ok then return x, y end
  end

  function a:vr() return call('vr') == true end

  local function playerId()
    local car = call('player')
    if not car then return nil end
    local ok, id = pcall(function() return car:getID() end)
    return ok and id or nil
  end

  -- Where the mouse is aiming: { origin, dir, point, targetId }. point is where the ray meets
  -- something (or nil), targetId the car it hits or passes close to (never your own).
  function a:aim()
    local origin, dir = call('mouseRay')
    if not (origin and dir) then return nil end
    local start = origin + dir * M.NEAR_METRES
    local hit = call('castRay', start, origin + dir * M.RANGE_METRES)
    local point
    if type(hit) == 'table' then
      if hit.pos then point = vec3(hit.pos)
      elseif finite(hit.dist) then point = start + dir * hit.dist end
    end
    local me = playerId()
    local best, bestMiss, bestAlong
    for _, car in ipairs(call('vehicles') or {}) do
      local okId, id = pcall(function() return car:getID() end)
      local okPos, pos = pcall(function() return car:getPosition() end)
      if okId and okPos and pos and id ~= me then
        local to = vec3(pos) - origin
        local along = to:dot(dir)
        if along > M.NEAR_METRES and along <= M.RANGE_METRES and (not point or along <= (point - origin):length() + M.SNAP_METRES) then
          local miss = (to - dir * along):length()
          if miss <= M.SNAP_METRES and (not bestMiss or miss < bestMiss) then best, bestMiss, bestAlong = id, miss, along end
        end
      end
    end
    local target = best
    if target and not point then point = origin + dir * bestAlong end
    return { origin = origin, dir = dir, point = point, targetId = target }
  end

  -- Hits the car: a push and a dent where the round lands.
  function a:hit(shot)
    if not (shot and shot.targetId and shot.point) then return false end
    local car = call('byId', shot.targetId)
    if not car then return false end
    local p, d = shot.point, shot.dir
    local cmd = string.format(IMPACT, p.x, p.y, p.z, d.x, d.y, d.z, M.IMPACT_FORCE, M.DENT_RADIUS, M.DENT_RADIUS, M.DENT_FORCE)
    return (pcall(function() car:queueLuaCommand(cmd) end))
  end

  -- The crosshair at the mouse, and a dot where the shot would land. Hides the mouse pointer.
  function a:draw(shot)
    local imgui = call('imgui')
    if type(imgui) ~= 'table' then return end
    pcall(function()
      if imgui.SetMouseCursor and imgui.MouseCursor_None then imgui.SetMouseCursor(imgui.MouseCursor_None) end
      local viewport = imgui.GetMainViewport and imgui.GetMainViewport()
      local list = viewport and imgui.GetForegroundDrawList2 and imgui.GetForegroundDrawList2(viewport)
      local mouse = imgui.GetMousePos and imgui.GetMousePos()
      if not (list and mouse) then return end
      local s, t, colour = M.CROSSHAIR_SIZE, M.CROSSHAIR_THICKNESS, M.CROSSHAIR_COLOUR
      imgui.ImDrawList_AddLine(list, imgui.ImVec2(mouse.x - s, mouse.y), imgui.ImVec2(mouse.x + s, mouse.y), colour, t)
      imgui.ImDrawList_AddLine(list, imgui.ImVec2(mouse.x, mouse.y - s), imgui.ImVec2(mouse.x, mouse.y + s), colour, t)
    end)
    if shot and shot.point and shot.targetId then call('drawSphere', shot.point, 0.15) end
  end

  -- Whether the left mouse button was clicked this frame on the game (not on a game menu).
  function a:clicked()
    local imgui = call('imgui')
    if type(imgui) ~= 'table' then return false end
    local ok, clicked = pcall(function()
      local io = imgui.GetIO and imgui.GetIO()
      if io and io.WantCaptureMouse then return false end
      return imgui.IsMouseClicked and imgui.IsMouseClicked(0) == true
    end)
    return ok and clicked == true
  end

  return a
end

return M
