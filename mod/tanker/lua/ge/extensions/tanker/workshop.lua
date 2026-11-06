-- Paying for parts in fuel, adapted from Earth Freight's workshop. Change parts in BeamNG's own
-- parts menu and Tanker bills the change: the new parts' prices, less a trade-in for the ones taken
-- off, plus the repair of any damage the change mended. The bill is paid in litres of fuel, from
-- the bed tank first and then the truck's own tank. Undo, or driving off unpaid, puts the paid
-- parts back. attach(c) adds these methods to a controller made by core.new.
local location = require('tanker/location')
local pricing = require('tanker/pricing')
local M = {}

-- One-line settings. Tune these after testing in game.
-- Driving this far from where the parts were changed, without paying, puts the paid parts back.
M.DRIVE_OFF_METRES = 25
-- Serials for taking fuel to pay, far from the siphon's and the pump's.
M.SERIAL_BASE = 2000000
-- After paying on the parts bill box, how long until the camera is checked once more.
M.CAMERA_CHECK_SECONDS = 0.5
-- While testing (Rowan, 6 Nov): any vehicle or part change is free and becomes your truck, with no
-- bill and nothing put back. Set to false to pay for parts in fuel again.
M.FREE_CHANGES = true

local function dollars(n) return pricing.dollars(math.max(0, math.floor((n or 0) + 0.5))) end

function M.attach(c)
  c.paySerial = M.SERIAL_BASE

  -- All the fuel you carry: the truck's tank and the bed tank.
  function c:carriedLitres()
    return (self.reading and self.reading.litres or 0) + (self.bed and self.bedLitres or 0)
  end

  function c:adoptParts(snapshot)
    self.ownedParts, self.pendingParts = snapshot, nil
    self.diag:event('parts_owned', tostring(snapshot.model))
  end

  -- The player's truck has respawned: a part change, an undo or the game reloading it. A respawn
  -- fills the tank, so the fuel it had is put back, and the bed tank's weight goes back on.
  function c:truckRespawned()
    self.partsCheckDue = true
    if self.reading then self.restoreFuel = self.reading.litres end
  end

  function c:checkParts()
    local snapshot = self.parts:parts()
    if not snapshot then return false end
    local owned = self.ownedParts
    if not owned then
      self:adoptParts(snapshot)
      return true
    end
    if M.FREE_CHANGES then
      self.pendingParts = nil
      if snapshot.model ~= owned.model then
        self.feedback = 'Free while testing: this vehicle is now your truck.'
      elseif pricing.partsDiff(owned, snapshot) then
        self.feedback = 'Free while testing: your new parts are yours, nothing to pay.'
      end
      self:adoptParts(snapshot)
      return true
    end
    -- Another vehicle from the vehicle selector: not for sale yet, so the truck comes back.
    if snapshot.model ~= owned.model then
      self.pendingParts = nil
      self.parts:restore(owned.config, owned.model)
      self.feedback = 'Buying a new vehicle with fuel comes in a later build. Your truck is back.'
      return true
    end
    local diff = pricing.partsDiff(owned, snapshot)
    if not diff then
      if self.pendingParts then self.feedback = 'Part changes undone. Nothing to pay.' end
      self.pendingParts = nil
      return true
    end
    local previous = self.pendingParts
    local damage = previous and previous.damage or (self.lastDamage and self.lastDamage.damage) or 0
    local repair = pricing.repairCost(damage, owned.value)
    local here = self.here and self.here.valid and location.copy(self.here) or nil
    self.fittedParts = snapshot
    self.pendingParts = {
      added = diff.added, removed = diff.removed, partsCost = diff.cost, repair = repair, damage = damage,
      cost = diff.cost + repair, litres = pricing.litresFor(diff.cost + repair),
      position = previous and previous.position or here,
    }
    self.diag:event('parts_quote', string.format('%d parts, %d repair', diff.cost, repair))
    return true
  end

  function c:payPartsAllowed()
    local bill = self.pendingParts
    return self.state == 'RUNNING' and bill ~= nil and self:carriedLitres() >= bill.litres
  end

  -- Pays the bill in fuel: from the bed tank first, then the truck's own tank.
  function c:payParts()
    local bill = self.pendingParts
    if not bill then return false end
    if not self:payPartsAllowed() then
      self.feedback = string.format('Not enough fuel. The bill is %d L and you carry %d L.',
        math.ceil(bill.litres), math.floor(self:carriedLitres()))
      return false
    end
    local fromBed = math.min(self.bed and self.bedLitres or 0, bill.litres)
    local fromTruck = bill.litres - fromBed
    if fromBed > 0 then
      self.bedLitres = self.bedLitres - fromBed
      self:applyBed(true)
    end
    if fromTruck > 0.001 then
      self.paySerial = self.paySerial + 1
      self.fuel:change(-fromTruck, self.paySerial)
      self.reading.litres = math.max(0, self.reading.litres - fromTruck)
    end
    self:adoptParts(self.fittedParts)
    self.feedback = string.format('Paid %s in fuel: %d L.', dollars(bill.cost), math.ceil(bill.litres))
    return true
  end

  -- Pay on the parts bill box, which shows over the game's parts menu. Once paid, the menu closes
  -- and the player is back driving the truck. Paying on the Garage tab leaves the game as it is.
  function c:payPartsBill()
    local ok = self:payParts()
    if ok then
      if self.trigger then pcall(self.trigger, 'ChangeState', { state = 'play', params = {} }) end
      -- The parts menu uses the free camera, and closing it ourselves leaves it on: back to the
      -- truck's own camera now, and once more a moment later in case closing the menu turns it on.
      self:cameraBackToCar()
      self.cameraCheckAt = self.clock + M.CAMERA_CHECK_SECONDS
    end
    return ok
  end

  function c:cameraBackToCar()
    if self.camera and self.camera.backToCar then pcall(self.camera.backToCar) end
  end

  -- Called every tick: the second camera check after paying on the bill box.
  function c:watchCamera()
    if self.cameraCheckAt and self.clock >= self.cameraCheckAt then
      self.cameraCheckAt = nil
      self:cameraBackToCar()
    end
  end

  -- Puts the paid parts back. The truck respawns, and the next check finds nothing to pay.
  function c:undoParts(droveOff)
    if not (self.pendingParts and self.ownedParts) then return false end
    local ok, why = self.parts:restore(self.ownedParts.config, self.ownedParts.model)
    if not ok then
      self.feedback = 'Could not put the paid parts back. Try again in a moment.'
      self.diag:event('parts_undo_failed', tostring(why), 'W')
      return false
    end
    self.pendingParts = nil
    self.feedback = droveOff and 'You drove off without paying, so your old parts were put back.'
      or 'Changes undone: your old parts are back.'
    return true
  end

  -- Each half second while the run is on the road.
  function c:followWorkshop()
    if self.state ~= 'RUNNING' then return end
    if self.restoreFuel then
      local litres = self.restoreFuel
      self.restoreFuel = nil
      self.fuel:set(litres, 0)
      self.reading = self.reading and { litres = litres, capacity = self.reading.capacity, km = self.reading.km } or nil
      self:applyBed(true)
    end
    if self.partsCheckDue or not self.ownedParts then
      if self:checkParts() then self.partsCheckDue = false end
      return
    end
    local inspected = self.parts:inspect()
    if inspected then self.lastDamage = inspected end
    local bill = self.pendingParts
    if bill and self.here and self.here.valid then
      if not bill.position then bill.position = location.copy(self.here)
      else
        local moved = location.distance(bill.position, self.here)
        if moved and moved > M.DRIVE_OFF_METRES and not self:undoParts(true) then bill.position = location.copy(self.here) end
      end
    end
  end

  -- What the Garage tab and the bill box show.
  function c:workshopView(v)
    v.fuelWorth = pricing.worth(self:carriedLitres())
    v.fuelPrice = pricing.FUEL_PRICE
    v.buyPartsAllowed = self.state == 'RUNNING' and self.ownedParts ~= nil
    v.freeChanges = M.FREE_CHANGES
    local bill = self.pendingParts
    if not bill then return end
    local lines = {}
    for _, part in ipairs(bill.added) do lines[#lines + 1] = { label = '+ ' .. part.name, amount = dollars(part.price) } end
    for _, part in ipairs(bill.removed) do lines[#lines + 1] = { label = '- ' .. part.name .. ' (traded in)', amount = '-' .. dollars(part.refund) } end
    if bill.repair > 0 then lines[#lines + 1] = { label = 'Repair (damage the change mended)', amount = dollars(bill.repair) } end
    local carried = self:carriedLitres()
    v.bill = { cost = bill.cost, litres = bill.litres, lines = lines, total = dollars(bill.cost),
      litresText = string.format('%d L of fuel', math.ceil(bill.litres)),
      short = carried < bill.litres and math.ceil(bill.litres - carried) or nil }
    v.payPartsAllowed = self:payPartsAllowed()
    v.undoPartsAllowed = true
  end
end

return M
