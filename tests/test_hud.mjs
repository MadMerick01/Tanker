import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'

const APP = '../mod/tanker/ui/modules/apps/Tanker/'
const source = readFileSync(new URL(APP + 'app.js', import.meta.url), 'utf8')
const html = readFileSync(new URL(APP + 'app.html', import.meta.url), 'utf8')
const fixed = body => 'if tanker_core then tanker_core.' + body + ' end'

// Just enough of a page for the siphon box.
function page() {
  const el = tag => ({ tag, children: [], style: {}, attrs: {}, textContent: '', parentNode: null,
    setAttribute(k, v) { this.attrs[k] = v },
    appendChild(c) { c.parentNode = this; this.children.push(c); return c },
    removeChild(c) { this.children = this.children.filter(x => x !== c); c.parentNode = null } })
  const body = el('body')
  return { body, createElement: el }
}
const text = node => node.textContent + node.children.map(text).join(' ')

function app(document) {
  const commands = [], handlers = {}, timers = new Map()
  let definition, clock = 0
  const scope = { $on: (name, fn) => { handlers[name] = fn }, $evalAsync: fn => fn() }
  vm.runInNewContext(source, {
    angular: { module(name) {
      assert.equal(name, 'beamng.apps')
      return { directive(id, factory) { assert.equal(id, 'tankerHud'); definition = factory.at(-1)() } }
    } },
    bngApi: { engineLua: command => commands.push(command) },
    setInterval: fn => { timers.set(1, fn); return 1 }, clearInterval: id => timers.delete(id), Date: { now: () => clock },
    document
  })
  definition.link(scope)
  const a = { scope, commands, handlers, relink: (s, el) => definition.link(s, el), state: data => handlers.TankerState({}, data),
    advance: ms => { clock += ms; for (const tick of timers.values()) tick() } }
  // BeamNG rebuilds the app when a menu closes: the old one is destroyed and a new one linked.
  a.remount = () => {
    handlers.$destroy()
    a.scope = { $on: (name, fn) => { handlers[name] = fn }, $evalAsync: fn => fn() }
    definition.link(a.scope)
    return a
  }
  return a
}

test('app mounts, resyncs and says when Lua is silent', () => {
  const a = app()
  assert.equal(a.commands[0], fixed('uiMounted(true)'))
  a.advance(3000)
  assert.equal(a.commands[1], fixed('uiMounted(true)'))
  a.advance(4000)
  assert.match(a.scope.data.feedback, /not responding/)
  a.handlers.$destroy()
  assert.equal(a.commands.at(-1), fixed('uiMounted(false)'))
})

test('buttons only send fixed commands when Lua allows them', () => {
  const a = app()
  const before = a.commands.length
  a.scope.send('startRun'); a.scope.send('save'); a.scope.send('goToSave'); a.scope.send('os.exit')
  assert.equal(a.commands.length, before)
  a.state({ state: 'NEW', startAllowed: true })
  a.scope.send('startRun')
  assert.equal(a.commands.at(-1), fixed('startRun()'))
  a.state({ state: 'RUNNING', saveAllowed: true })
  a.scope.send('save')
  assert.equal(a.commands.at(-1), fixed('save()'))
  a.state({ state: 'AWAY', goToSaveAllowed: true })
  a.scope.send('goToSave')
  assert.equal(a.commands.at(-1), fixed('goToSave()'))
  a.state({ state: 'RUNNING', rocksAllowed: true, rocks: { on: true } })
  a.scope.send('rocksOff')
  assert.equal(a.commands.at(-1), fixed('rocksOff()'))
  a.scope.send('rocksOn')
  assert.equal(a.commands.at(-1), fixed('rocksOn()'))
})

test('siphon buttons and the siphon box', () => {
  const doc = page()
  const a = app(doc)
  a.scope.send('siphonStart')
  assert.ok(!a.commands.includes(fixed('siphonStart()')), 'no siphon unless offered')
  a.state({ state: 'RUNNING', siphonAllowed: true, siphonNear: { metres: 4 } })
  a.scope.send('siphonStart')
  assert.equal(a.commands.at(-1), fixed('siphonStart()'))
  assert.equal(doc.body.children.length, 0, 'no window without an offer')
  // Stopped beside a car: the centre window offers the siphon, with no choice without a bed tank.
  a.state({ state: 'RUNNING', siphonAllowed: true, siphonOffer: { metres: 4, bed: false, yours: 40, yoursCapacity: 300 } })
  const offer = doc.body.children[0]
  assert.match(text(offer), /SIPHON/); assert.match(text(offer), /A car 4 m away/)
  assert.ok(!/bed tank/i.test(text(offer)), 'no bed tank, no choice')
  assert.match(offer.style.cssText, /translate\(-50%,-50%\)/, 'in the middle of the screen')
  offer.children.find(c => c.textContent === 'Siphon fuel').onclick()
  assert.equal(a.commands.at(-1), fixed('siphonToTruck()'))
  // With a bed tank: choose where the fuel goes.
  a.state({ state: 'RUNNING', siphonAllowed: true, siphonOffer: { metres: 4, bed: true, yours: 40, yoursCapacity: 300, bedLitres: 20, bedCapacity: 200 } })
  const choose = doc.body.children[0]
  assert.match(text(choose), /Where should the fuel go/); assert.match(text(choose), /20 of 200 L/)
  choose.children.find(c => c.textContent === 'Into the bed tank').onclick()
  assert.equal(a.commands.at(-1), fixed('siphonToBed()'))
  choose.children.find(c => c.textContent === 'Into your truck').onclick()
  assert.equal(a.commands.at(-1), fixed('siphonToTruck()'))
  choose.onmouseenter()
  assert.equal(a.commands.at(-1), fixed('hudHover(true)'), 'a click in the window is not a shot')
  choose.onmouseleave()
  a.state({ state: 'RUNNING', siphonAllowed: false, siphonOffer: { metres: 4, bed: true } })
  assert.equal(doc.body.children.length, 0, 'no offer unless Lua allows it')
  // In the truck: the window says you must be on foot, with nothing to press.
  a.state({ state: 'RUNNING', siphonAllowed: false, siphonOffer: { metres: 4, bed: true, blocked: 'in_vehicle' } })
  const foot = doc.body.children[0]
  assert.match(text(foot), /You must be on foot to siphon/)
  assert.ok(!foot.children.some(c => c.tagName === 'button' || c.tag === 'button'), 'no buttons')
  a.state({ state: 'RUNNING', siphonAllowed: false, siphonOffer: { metres: 4, blocked: 'truck_far', truckMetres: 15 } })
  assert.match(text(doc.body.children[0]), /Park your truck within 15 m/)
  a.state({ state: 'RUNNING' })
  const live = { active: true, litres: 12, theirs: 68, theirsCapacity: 80, yours: 112, yoursCapacity: 300 }
  a.state({ state: 'RUNNING', siphonStopAllowed: true, siphon: live })
  assert.equal(doc.body.children.length, 1, 'the box shows')
  const box = doc.body.children[0]
  assert.match(text(box), /SIPHONING/); assert.match(text(box), /12 L taken/); assert.match(text(box), /68 of 80 L/)
  assert.match(box.style.cssText, /#e0823c/, 'orange border')
  a.state({ state: 'RUNNING', siphonStopAllowed: true, siphon: live })
  assert.equal(doc.body.children[0], box, 'not redrawn when nothing changed')
  a.state({ state: 'RUNNING', siphonStopAllowed: true, siphon: { ...live, hoons: true } })
  const red = doc.body.children[0]
  assert.match(red.style.cssText, /#eb5757/, 'red border with Hoons near'); assert.match(text(red), /Hoons nearby/)
  const stop = red.children.find(c => c.textContent === 'Stop')
  stop.onclick()
  assert.equal(a.commands.at(-1), fixed('siphonStop()'))
  a.state({ state: 'RUNNING', siphon: { active: false, litres: 12, result: 'Siphon stopped. You took 12 L.' } })
  assert.match(text(doc.body.children[0]), /You took 12 L/)
  assert.ok(!doc.body.children[0].children.some(c => c.textContent === 'Stop'), 'no Stop once done')
  a.state({ state: 'RUNNING' })
  assert.equal(doc.body.children.length, 0, 'the box goes')
  a.state({ state: 'RUNNING', siphonStopAllowed: true, siphon: { ...live, into: 'bed', yoursCapacity: 200 } })
  assert.match(text(doc.body.children[0]), /SIPHONING INTO THE BED TANK/); assert.match(text(doc.body.children[0]), /Bed tank/)
  a.state({ state: 'RUNNING', siphon: live })
  a.handlers.$destroy()
  assert.equal(doc.body.children.length, 0, 'the box goes with the app')
})

test('a Hoon robbing you takes over the centre window', () => {
  const doc = page()
  const a = app(doc)
  const rob = { active: true, state: 'TAKING', text: 'A Hoon is siphoning your fuel! Drive off or shoot it.', litres: 8,
    yours: 52, yoursCapacity: 300, bed: 0, bedCapacity: 200, keep: 10 }
  a.state({ state: 'RUNNING', siphonAllowed: true, siphonOffer: { metres: 4 }, robbery: rob })
  const box = doc.body.children[0]
  assert.equal(doc.body.children.length, 1)
  assert.match(text(box), /HOON ROBBERY/); assert.match(text(box), /8 L stolen/); assert.match(text(box), /leaves you 10 L/)
  assert.match(box.style.cssText, /#eb5757/, 'red')
  a.state({ state: 'RUNNING', robbery: { active: false, text: 'The Hoon took 40 L and sped off.', litres: 40, yours: 10, yoursCapacity: 300, keep: 10 } })
  assert.match(text(doc.body.children[0]), /ROBBERY OVER/); assert.match(text(doc.body.children[0]), /siphon your fuel back/)
  a.state({ state: 'RUNNING' })
  assert.equal(doc.body.children.length, 0, 'then it goes')
})

test('the start page opens once by itself, and its buttons close it', () => {
  const a = app()
  assert.equal(a.scope.start, false)
  a.state({ state: 'NEW', startAllowed: true })
  assert.equal(a.scope.start, true, 'opens for a new run'); assert.equal(a.scope.open, true, 'with the panel open')
  a.scope.startCommand('startRun')
  assert.equal(a.commands.at(-1), fixed('startRun()')); assert.equal(a.scope.start, false, 'closes on Start the run')
  a.state({ state: 'AWAY', goToSaveAllowed: true })
  assert.equal(a.scope.start, false, 'only opens by itself once')
  a.scope.openStart()
  a.remount()
  assert.equal(a.scope.start, true, 'kept open across rebuilds')
  a.scope.closeStart()
  assert.equal(a.scope.start, false)
  assert.equal(a.scope.coordinates({ latitude: -32.47125, longitude: 137.7837 }), '32.47125 S, 137.78370 E')
  assert.equal(a.scope.coordinates(null), '')
  assert.equal(a.scope.km(12345), '12')
})

test('pump buttons only work when Lua allows them', () => {
  const a = app()
  a.scope.send('pumpToTruck')
  assert.ok(!a.commands.includes(fixed('pumpToTruck()')))
  a.state({ state: 'RUNNING', pumpAllowed: true, bed: { litres: 25, capacity: 800, fitted: true } })
  a.scope.send('pumpToTruck'); assert.equal(a.commands.at(-1), fixed('pumpToTruck()'))
  a.scope.send('pumpToBed'); assert.equal(a.commands.at(-1), fixed('pumpToBed()'))
  a.state({ state: 'RUNNING', pumpStopAllowed: true, pumping: 'toTruck' })
  a.scope.send('pumpStop'); assert.equal(a.commands.at(-1), fixed('pumpStop()'))
})

test('strip helpers show fuel, ammo and the threat light', () => {
  const a = app()
  assert.equal(a.scope.whole(1453.6), '1,454')
  assert.equal(a.scope.whole(null), '–')
  assert.equal(a.scope.fuelShare({ litres: 100, capacity: 400 }), 25)
  assert.equal(a.scope.fuelColour({ litres: 100, capacity: 400 }), '#f2c94c')
  assert.equal(a.scope.fuelColour({ litres: 20, capacity: 400 }), '#eb5757')
  assert.equal(a.scope.fuelShare(undefined), 0)
  assert.deepEqual(Array.from(a.scope.pips({ loaded: 2 })), [true, true, false, false, false, false])
  assert.deepEqual(Array.from(a.scope.pips(undefined)), [false, false, false, false, false, false])
  assert.equal(a.scope.threatColour('red'), '#eb5757')
  assert.equal(a.scope.threatColour('clear'), '#3c403c')
})

test('ignores malformed state and keeps the tab across rebuilds', () => {
  const a = app()
  a.state(null); a.state({ state: 7 })
  assert.equal(a.scope.data.state, 'STARTING')
  a.scope.setTab('rig')
  a.scope.toggle()
  a.remount()
  assert.equal(a.scope.tab, 'rig')
  assert.equal(a.scope.open, false)
})

test('template uses only the helpers the app defines', () => {
  for (const name of ['toggle', 'send', 'whole', 'fuelShare', 'fuelColour', 'pips', 'threatColour', 'setTab',
    'openStart', 'closeStart', 'startCommand', 'coordinates', 'km', 'newGame', 'cancelNewGame', 'hover']) {
    assert.ok(html.includes(name + '('), name)
  }
  assert.ok(!/bngApi|engineLua/.test(html), 'no direct Lua from the template')
})

test('start a new game asks twice, and the start page is a centre window', () => {
  const doc = page()
  const startPage = { tag: 'div', children: [], parentNode: null }
  const a = app(doc)
  a.handlers.$destroy()
  a.scope = { $on: (name, fn) => { a.handlers[name] = fn }, $evalAsync: fn => fn() }
  // Linked again with the template's element, whose start page moves onto the page body.
  const element = [{ querySelector: sel => sel === '.tk-start' ? startPage : null }]
  const definitionLink = a.relink
  assert.equal(typeof definitionLink, 'function')
  definitionLink(a.scope, element)
  assert.equal(startPage.parentNode, doc.body, 'the start page sits over the whole screen')
  a.state({ state: 'RUNNING', newGameAllowed: false })
  a.scope.newGame(); assert.equal(a.scope.askNewGame, false, 'not offered, nothing happens')
  a.state({ state: 'RUNNING', newGameAllowed: true })
  a.scope.openStart()
  a.scope.newGame()
  assert.equal(a.scope.askNewGame, true, 'asks first'); assert.ok(!a.commands.includes(fixed('newGame()')))
  a.scope.cancelNewGame(); assert.equal(a.scope.askNewGame, false, 'keep this one')
  a.scope.newGame(); a.scope.newGame()
  assert.equal(a.commands.at(-1), fixed('newGame()'), 'then starts over'); assert.equal(a.scope.start, false, 'and closes the page')
  a.handlers.$destroy()
  assert.equal(startPage.parentNode, null, 'the page goes with the app')
})

test('revolver buttons only work on a flat screen on the road, and HUD clicks are not shots', () => {
  const a = app()
  a.scope.send('toggleRevolver'); assert.ok(!a.commands.includes(fixed('toggleRevolver()')))
  a.state({ state: 'RUNNING', revolverAllowed: true, reloadAllowed: false, ammo: { loaded: 6, spare: 12 } })
  a.scope.send('toggleRevolver'); assert.equal(a.commands.at(-1), fixed('toggleRevolver()'))
  a.scope.send('reloadRevolver'); assert.equal(a.commands.at(-1), fixed('toggleRevolver()'), 'nothing to reload')
  a.scope.hover(true); assert.equal(a.commands.at(-1), fixed('hudHover(true)'))
  a.handlers.$destroy(); assert.ok(a.commands.includes(fixed('hudHover(false)')), 'the hover ends with the app')
})

test('the TankerMob spawn button only works when Lua allows it', () => {
  const a = app()
  a.scope.send('spawnTanker'); assert.ok(!a.commands.includes(fixed('spawnTanker()')))
  a.state({ state: 'RUNNING', tankerSpawnAllowed: true })
  a.scope.send('spawnTanker'); assert.equal(a.commands.at(-1), fixed('spawnTanker()'))
})

test('Spawn a Hoon and Clear Hoons only work when Lua allows them', () => {
  const a = app()
  a.scope.send('addHoon'); a.scope.send('clearHoons')
  assert.ok(!a.commands.includes(fixed('addHoon()'))); assert.ok(!a.commands.includes(fixed('clearHoons()')))
  a.state({ state: 'RUNNING', addHoonAllowed: true, clearHoonsAllowed: true, pack: { hoons: [], max: 4 } })
  a.scope.send('addHoon'); assert.equal(a.commands.at(-1), fixed('addHoon()'))
  a.scope.send('clearHoons'); assert.equal(a.commands.at(-1), fixed('clearHoons()'))
})
