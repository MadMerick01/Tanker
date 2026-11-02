/* global angular, bngApi */
angular.module('beamng.apps').directive('tankerHud', [function () {
  // What the player was looking at. BeamNG rebuilds the app each time a menu closes, so this is
  // kept out here and the new app carries on where the old one was.
  var kept = { tab: 'road', open: true, start: false, startShown: false }
  // The commands the HUD may send, each only while Lua says it is allowed.
  var COMMANDS = { startRun: 'startAllowed', goToSave: 'goToSaveAllowed', save: 'saveAllowed', rocksOn: 'rocksAllowed', rocksOff: 'rocksAllowed',
    siphonStart: 'siphonAllowed', siphonStop: 'siphonStopAllowed', sendHoon: 'hoonTestAllowed' }
  var whole = function (n) {
    return typeof n === 'number' && isFinite(n) ? Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',') : '–'
  }
  // The siphon box: bold, near the top of the screen like Earth Freight's parts bill, and put on
  // the page itself so it sits over everything. It is redrawn from each state while fuel flows,
  // shows the result for a few seconds after, then goes. Red when Hoons are near.
  var box = null
  var boxKey = null
  var closeBox = function () {
    if (box && box.parentNode) box.parentNode.removeChild(box)
    box = boxKey = null
  }
  var line = function (parent, text, css) {
    var div = document.createElement('div')
    div.textContent = text
    div.style.cssText = css
    parent.appendChild(div)
    return div
  }
  var tankLine = function (parent, label, litres, capacity, colour) {
    var row = document.createElement('div')
    row.style.cssText = 'display:flex;align-items:center;gap:8px;margin-top:4px;'
    line(row, label, 'width:84px;color:#c8bfb2;')
    var bar = document.createElement('div')
    bar.style.cssText = 'flex:1;height:10px;border-radius:5px;background:#3c403c;overflow:hidden;'
    var share = capacity > 0 && typeof litres === 'number' ? Math.max(0, Math.min(100, litres / capacity * 100)) : 0
    line(bar, '', 'height:100%;width:' + share + '%;background:' + colour + ';')
    row.appendChild(bar)
    line(row, typeof litres === 'number' ? whole(litres) + (capacity > 0 ? ' of ' + whole(capacity) : '') + ' L' : '–',
      'min-width:90px;text-align:right;font-weight:bold;')
    parent.appendChild(row)
  }
  var showBox = function (s, stop) {
    if (!s) return closeBox()
    if (typeof document === 'undefined' || !document.body) return
    // Only redrawn when what it shows changes, so a press on Stop is not lost to a redraw.
    var key = [s.active, whole(s.litres), whole(s.theirs), whole(s.yours), s.hoons, s.result].join('|')
    if (box && key === boxKey) return
    var edge = s.hoons ? '#eb5757' : '#e0823c'
    var next = document.createElement('div')
    next.setAttribute('role', 'status')
    next.style.cssText = 'position:fixed;top:12%;left:50%;transform:translateX(-50%);z-index:2147483647;' +
      'width:420px;max-width:80vw;padding:14px 18px;background:rgba(20,16,12,.96);color:#f1ece4;' +
      'border:3px solid ' + edge + ';border-radius:10px;box-shadow:0 0 24px rgba(0,0,0,.7);' +
      'font:15px/1.4 sans-serif;pointer-events:auto;'
    if (s.active) {
      var button = document.createElement('button')
      button.type = 'button'
      button.textContent = 'Stop'
      button.style.cssText = 'float:right;margin-left:10px;padding:6px 14px;background:' + edge + ';color:#1a140f;' +
        'font-weight:bold;border:none;border-radius:4px;cursor:pointer;'
      button.onclick = stop
      next.appendChild(button)
    }
    line(next, s.active ? 'SIPHONING' : 'SIPHON DONE', 'font-weight:bold;letter-spacing:2px;font-size:13px;color:' + edge + ';')
    line(next, whole(s.litres) + ' L taken', 'font-weight:bold;font-size:22px;margin-top:2px;')
    tankLine(next, 'Their tank', s.theirs, s.theirsCapacity, '#c48448')
    tankLine(next, 'Your tank', s.yours, s.yoursCapacity, '#6fcf97')
    if (s.hoons) line(next, 'Hoons nearby!', 'font-weight:bold;color:#eb5757;margin-top:6px;')
    line(next, s.active ? 'Stay still beside their car. Driving off stops it, and you keep what you took.' : String(s.result || ''),
      'margin-top:6px;color:#c8bfb2;font-size:13px;')
    closeBox()
    document.body.appendChild(next)
    box = next
    boxKey = key
  }
  return {
    templateUrl: '/ui/modules/apps/Tanker/app.html',
    replace: true,
    link: function (scope) {
      'use strict'
      var disposed = false
      var lastMessage = Date.now()
      var waiting = { state: 'STARTING', stateLabel: 'WAITING FOR TANKER', threat: 'clear' }
      scope.data = waiting
      var core = function (body) {
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) bngApi.engineLua('if tanker_core then tanker_core.' + body + ' end')
      }
      var mount = function (on) { core('uiMounted(' + (on ? 'true' : 'false') + ')') }

      scope.tabs = [{ id: 'road', label: 'Road' }, { id: 'rig', label: 'Rig' }]
      scope.tab = kept.tab
      scope.open = kept.open
      scope.setTab = function (id) { scope.tab = kept.tab = id }
      scope.toggle = function () { scope.open = kept.open = !scope.open }
      // The start page: opens by itself once each time the game loads with a run to start or a
      // save to go back to, and from the Start page button.
      scope.start = kept.start
      scope.openStart = function () { scope.start = kept.start = true; scope.open = kept.open = true }
      scope.closeStart = function () { scope.start = kept.start = false }
      scope.startCommand = function (name) { scope.send(name); scope.closeStart() }
      scope.km = function (metres) { return typeof metres === 'number' && isFinite(metres) ? whole(metres / 1000) : '–' }
      scope.coordinates = function (s) {
        if (!s || typeof s.latitude !== 'number' || typeof s.longitude !== 'number') return ''
        return Math.abs(s.latitude).toFixed(5) + (s.latitude < 0 ? ' S, ' : ' N, ') + Math.abs(s.longitude).toFixed(5) + (s.longitude < 0 ? ' W' : ' E')
      }
      scope.send = function (name) {
        var allowed = COMMANDS[name]
        if (allowed && scope.data[allowed] === true) core(name + '()')
      }

      // Whole numbers with thousands commas, or a dash when unknown.
      scope.whole = whole
      // The own tank's share as a percentage, for the bar, and its colour.
      scope.fuelShare = function (f) {
        if (!f || !(f.capacity > 0)) return 0
        return Math.max(0, Math.min(100, f.litres / f.capacity * 100))
      }
      scope.fuelColour = function (f) {
        var s = scope.fuelShare(f)
        return s <= 10 ? '#eb5757' : s <= 25 ? '#f2c94c' : '#6fcf97'
      }
      // Six pips for the cylinder: true for each round loaded.
      scope.pips = function (ammo) {
        var loaded = ammo && typeof ammo.loaded === 'number' ? ammo.loaded : 0
        return [1, 2, 3, 4, 5, 6].map(function (i) { return i <= loaded })
      }
      scope.threatColour = function (t) { return t === 'red' ? '#eb5757' : t === 'amber' ? '#f2994a' : '#3c403c' }

      scope.$on('TankerState', function (event, data) {
        if (disposed || !data || typeof data.state !== 'string') return
        lastMessage = Date.now()
        scope.$evalAsync(function () {
          if (disposed) return
          scope.data = data
          if (!kept.startShown && (data.state === 'NEW' || data.state === 'AWAY')) {
            kept.startShown = true
            scope.openStart()
          }
        })
        showBox(data.siphon, function () { scope.send('siphonStop') })
      })
      mount(true)
      var heartbeat = setInterval(function () {
        if (disposed) return
        mount(true)
        if (Date.now() - lastMessage > 6000) {
          scope.$evalAsync(function () {
            if (disposed) return
            scope.data = { state: 'STARTING', stateLabel: 'WAITING FOR TANKER', threat: 'clear',
              feedback: 'Tanker is not responding. Check that the mod is enabled, then reload it.' }
          })
        }
      }, 3000)
      scope.$on('$destroy', function () {
        disposed = true
        clearInterval(heartbeat)
        closeBox()
        mount(false)
      })
    }
  }
}])
