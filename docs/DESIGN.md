# Tanker — Design

The game was called Mad Merick while it was being planned; Rowan renamed it **Tanker** on 31 Oct 2026. The GitHub repository was renamed to Tanker the same day.

Status: **playable skeleton**: the start at Kulgera, fuel, saving, the HUD strip and wrist HUD, the start page, siphoning, the first Hoon, the pump between the bed tank and the truck's tank, and paying for parts with fuel on the Garage tab (see the README and CHANGELOG). Not built yet: buying new vehicles with fuel, ammo loot, fleeing tankers and trailers. This doc collects what Rowan decided in the project thread (first on 31 Oct 2026, the vision on 2 Nov) and marks what is still open. Open questions are tagged **❓ OPEN** inline and gathered in [Open questions](#open-questions) at the end.

## The pitch

A hardcore post-apocalyptic trucking game for BeamNG.drive, played across the real Australian outback on [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth). Rowan set out the vision on 2 Nov:

- You start in a small ute with a fluid tank in the bed holding enough fuel for about 200 km, at **Kulgera Roadhouse**, south of Alice Springs in the desert. You can move fuel between the fluid tank and the vehicle's own tank.
- You must get to Pine Gap for the realignment codes that stop the AI, then to Monaco (this may change) to enter them in the mainframe.
- On the way you meet **Hoons**, muscle cars that try to intercept you on chase mode AI, and **tankers or smaller trucks carrying fuel**, which flee.
- You siphon fuel and collect ammo from Hoons and tankers.
- **Fuel is the currency.** The HUD shows what your fuel is worth in dollars, and you can spend that on parts and new vehicles, as in Worldwide Trucking. Every litre you spend is a litre you can't drive on.
- Eventually you get a bigger truck and can take whole fuel trailers off tankers and hook them to your own truck, for massive capacity.

You defend yourself with a VR revolver.

It is a separate game from Earth Freight (Worldwide Trucking Career). It reuses Earth Freight's plumbing by copying it, the same way Earth Freight was built from Earth Enduro, and changes the game on top: Earth Freight is about choosing what to carry for pay, Tanker is about surviving the road and taking what you need.

## The story

An AI has escaped its testing sandbox and turned off everyone's water, electricity and internet (Rowan, 2 Nov). There are no electric cars, and fuel was already short because the Strait of Hormuz is blocked. The world's population has turned on each other, fighting over the fuel that is left.

The realignment codes that can stop the AI are at Pine Gap, the little-known American base outside Alice Springs. Getting there is the first goal of the game. Then the codes have to be carried to Monaco and entered in the mainframe.

**Pine Gap is not the end** (Rowan, 31 Oct). The game is open ended: the trip to Monaco sends you out into the open world, and reaching Pine Gap should make the player realise how huge the game is. BeamNG.Earth covers the whole planet, so the world is already there. **❓ OPEN — Q1:** how the player gets from Australia to the next continent (by sea, by air, or a jump).

Pine Gap is a real facility. Everything about it in the game is fiction.

## The route

The first goal is **Kulgera Roadhouse** (25.8406 S, 133.2966 E, on the Stuart Highway just north of the SA border, Rowan, 2 Nov) to Pine Gap: about 270 km by road. Starting with about 200 km of fuel means you have to take fuel on the way. The run used to start at Yorkeys Crossing, Port Augusta, about 1,230 km out; saves from there still work and carry on from where they were saved.

| Leg | From → to | Roughly | Character |
|---|---|---|---|
| 1 | Kulgera → Erldunda | 75 km | The learning leg. Few Hoons. |
| 2 | Erldunda → Stuarts Well | 110 km | First tankers. Fuel gets tight. |
| 3 | Stuarts Well → Alice Springs | 90 km | Heavy Hoon country. |
| 4 | Alice Springs → Pine Gap | 20 km | The final run to the base. |

Distances are rough, from the real highway, and to be checked in game. **❓ OPEN — Q2:** whether the coordinates land on the roadhouse, and how the legs play.

### The map

There is no map to build. BeamNG.Earth streams real terrain anywhere on the planet, and Earth Freight already has an index of real towns that covers Australia. Tanker fences play to the mainland: the ocean is the edge of the world, and the route keeps the player heading north.

Two things need testing before anything else, because the whole game depends on them:

- **Streaming at speed.** How fast Earth loads terrain while driving a tanker at 100 km/h for hours.
- **AI on Earth roads.** Whether BeamNG's AI can chase and flee on Earth's streamed roads, and on dirt beside them.

## Core loop

1. **Drive north.** Burn fuel. The tanker is slow and drinks a lot.
2. **Get found, or go hunting.** Hoons in muscle cars come for your tank. Or you spot a tanker convoy and go after it.
3. **Fight.** Shoot out tyres, shoot engines, ram. A car is **down** when it stops: flat tyres, heavy damage or a dead engine.
4. **Loot.** Pull up next to a downed car and take its fuel, ammo and parts.
5. **Siphon.** Fuel takes time to move from a downed tanker into yours, and its escorts keep coming while you wait. This is where the tension comes from.
6. **Rebuild.** Swap the parts you looted onto your own truck, one at a time.
7. **Keep going north**, managing fuel and repairs the whole way.

**Fuel is the currency** (Rowan, 2 Nov, replacing "no buying or selling" from 31 Oct). The HUD shows your fuel's value in dollars, and you can spend it on parts and new vehicles as in Worldwide Trucking, so every purchase is fuel you can't drive on. Fuel itself still only comes from Hoons and tankers.

## The tanker

You start in a small ute with a fluid tank in the bed (Rowan's TankerStarter config). Progression is spending fuel on parts and upgrades, then on new vehicles, and eventually on a bigger truck that can take a whole fuel trailer off a tanker and tow it (Rowan, 2 Nov).

The tank is three things at once:

- **Your fuel.** The truck's own tank keeps you moving.
- **Your store.** The cargo tank holds the fuel you have taken. You top up your own tank from it.
- **The target.** It is what every Hoon is after.

**The starting truck.** Rowan will test a truck in game and upload its config. It needs a fluid tank, to be slow enough that you cannot outrun a rat rod, and sturdy enough to survive a ramming.

## Hardcore rules

Decided by Rowan, 31 Oct: **hardcore from the start, no restarts.** You manage your own fuel and repairs. If you run dry or wreck the truck, you have to get yourself out of it with what you are carrying. Rowan added **Start a new game** on 2 Nov: it throws away the run and its save and starts again at Kulgera, so there is still only ever one run on the go.

**One save.** The game saves where you are, so you can stop playing and carry on later from the same spot. There is no going back to an earlier save. What the truck keeps between play sessions is in [Damage between sessions](#damage-between-sessions).

**Free tow, but you are exposed.** Stuck in a ditch or on your side, you can tow yourself out for free, the same way as in Worldwide Trucking: get out, walk to a clear spot within 50 m, and the truck is brought to you. Unlike Worldwide Trucking, the tow takes **about 30 seconds of winching** (Rowan, 31 Oct), and there is a good chance a Hoon turns up while you wait.

### Damage between sessions

BeamNG does not save a car's bent body when the game closes, so the truck has to be rebuilt from what the save holds. Agreed by Rowan, 31 Oct:

- **Saved:** fuel in each tank, ammo, spare parts, which parts are broken or missing, and which tyres are flat.
- **Put back on load:** broken parts stay broken, missing parts stay missing, and flat tyres stay flat.
- **Not put back:** dents. The truck comes back straight, but anything that stopped working still doesn't work.
- **No escaping a fight by quitting:** saving is only allowed with no Hoons nearby, so quitting mid-chase doesn't get you out of it.

## Hoons

The raiders are called **Hoons** (Rowan, 31 Oct). They drive **vanilla muscle cars** (Rowan, 2 Nov; rat rods on 31 Oct), so nobody needs extra car mods, and chase your truck using BeamNG's AI in chase mode. They spawn behind or ahead of you, close in, and ram or box you in. Early legs have few and weak ones; later legs have more, faster ones, and some work in packs.

**For now they ram and do damage.** Later Hoons lean into BeamNG's physics:

- **Exploding Hoons** that blow up when they hit you, or when you shoot them enough.
- **Fire Hoons.**
- **Spiked Hoons** that rip your tyres when they come alongside.

Each downed Hoon carries a little loot: some fuel, some ammo, sometimes a part.

The chase code is not in Earth Freight. It is the CarKov hostiles in Earth Enduro, which will be copied over and given rat rods. **❓ OPEN — Q5:** which vanilla configs count as rat rods, and which of the later Hoon types comes first.

## Tankers

Other tankers drive the highway, alone or in convoys with escorts. When they see you coming they run, using BeamNG's AI in flee mode. You stop them by shooting out their tyres or forcing them off the road.

A downed tanker is the big prize: a lot of fuel, but it takes time to siphon, and the escorts arrive while you do. A siphon moves **1 litre a second** to start (Rowan, 31 Oct), so a few hundred litres means minutes standing still. You can drive away mid-siphon and keep what you have so far; driving off simply stops it. The first siphon works on any car within 10 m, so it can be tried before tankers exist.

## Spawning from traffic

Decided by Rowan, 31 Oct: **Hoons and tankers come from BeamNG's own traffic.** Spawning a car mid-drive loads it and causes a frame hitch. Traffic loads its cars once, when it starts, and then only moves them: a traffic car out of sight is picked up and put back on another road ahead of you. Tanker uses the same trick.

- **The pool.** When the game starts, traffic is set up with a pool that already holds rat rods and tankers. The one hitch happens there, behind the loading screen. Traffic runs at least 7 cars, which is plenty (Rowan, 31 Oct): **one type of rat rod and a tanker to start**, 3 or 4 Hoon types at most later.
- **Where traffic puts its cars.** A traffic car nobody is in, once it is out of sight and far enough behind you, is reset and put back down on a road further ahead, often in a new paint. Earth Freight already works around this for the player's parked car. So a car stays a traffic car only while it is just driving around; once it becomes a Hoon or a target tanker it is taken out of traffic, the same way Earth Freight parks the player's car, and given back once it is looted and left behind.
- **An encounter.** When a Hoon attack or a tanker sighting is due, Tanker takes a pooled car that is out of sight, moves it into place, and switches its AI to chase (Hoons) or flee (tankers).
- **After the fight.** A looted wreck goes back to traffic, which resets it and moves it away once you have driven off, ready to be used again.

**First Hoon (2 Nov):** for now the Hoon has its own car instead of borrowing one from traffic. It loads once when the run is on the road, then is switched off (not drawn, not simulated) until an attack switches it back on, which does not hitch, the same trick traffic uses. This doesn't depend on traffic containing a rat rod, and leaves the player's traffic as they set it. The model is the first of `hotrod`, `burnside` and `moonhawk` the game has. Moving Hoons into the traffic pool is still open once more types exist. A Hoon only comes while the player is on a road (within 30 m), and is put on solid road 250 m behind or, failing that, ahead, since BeamNG.Earth's road further out may not have loaded (Rowan, 2 Nov). The chase uses BeamNG's own AI for now; Rowan is training an AI model of their own to drive Tanker's cars, which will take over later.

Earth Freight already works with traffic on BeamNG.Earth: its traffic police chase and catch the player, and it takes the player's own car in and out of traffic. So traffic runs on Earth's roads, and the police chase is the model for the Hoons. Rowan has driven a lot with traffic on Earth and seen no problems (31 Oct).

Things to check in game:

- How many cars the pool can hold before the frame rate suffers, since every car in it is simulated.
- Whether traffic can carry a tanker trailer, or whether pooled tankers have to be rigid trucks.
- Whether changing a car's paint or parts forces a reload (and a hitch), so each kind of Hoon needs its own pooled car.

## The VR revolver

Rowan's [BeamngVRcontrollerPoses](https://github.com/MadMerick01/BeamngVRcontrollerPoses) mod. Hold the right grip to draw the revolver, pull the trigger to shoot.

What it does today:

- Each shot is a ray. The car it hits gets pushed and dented where it was hit.
- A hit near a wheel hub flattens that tyre, so shooting out a fleeing tanker's tyres already works.
- Every hit reports back to the game with which car was hit and where.
- There are no drivers to hit, so a car is stopped by its tyres, its damage or its engine.

What it needs for Tanker (two small changes in the pistol mod, so Tanker never touches its code):

1. **Ammo.** It currently fires without limit, every 0.12 s. It needs a six-round cylinder, a reload, and a way for Tanker to refuse a shot when you are out of ammo.
2. **A hit event** other mods can listen to, so Tanker hears every hit and decides when a Hoon is down.

Tanker needs the pistol installed. **VR first** (Rowan, 31 Oct). A non-VR way to shoot comes later; it should be easy, since the pistol can already fire from the camera.

## The HUD

Like Worldwide Trucking's: a slim strip that is always there, which opens into a few tabs. Fairly simple, but interesting. Rowan (31 Oct): build it **both on screen and on the left wrist in VR**, then keep whichever plays better, or both.

**The strip, always visible:**

- **Fuel:** your own tank and the cargo tank, in litres, with a range estimate ("Range 140 km").
- **Ammo:** six pips for the cylinder, and your spare rounds.
- **Pine Gap:** distance left.
- **Threat light:** off, amber when a Hoon is near, red when one is on you. It still shows when the HUD is minimised, like Worldwide Trucking's gold and red dot.

**Three tabs:**

1. **Road:** distance to the next leg end, which way anything spotted is (a tanker, a Hoon pack), and the save button, greyed out while Hoons are close.
2. **Rig:** what is broken, which tyres are flat and how fast the tank is leaking, and your spare parts, each with a Fit button. The Tow button and its 30-second countdown are here too.
3. **Loot:** only shown beside a downed car. What it carries, the siphon bar filling at 1 L a second, and a "Hoons inbound" warning.

**No radio for now** (Rowan, 31 Oct). One-line radio messages that tell the story as you drive could come later.

### On screen and on the wrist

Both read the same HUD state, which the game sends at most 4 times a second, as in Worldwide Trucking, so they always agree.

- **On screen:** a BeamNG UI app, built from Worldwide Trucking's.
- **On the wrist:** a small panel drawn on the left hand, like a watch. The pistol mod already tracks the left controller (`vrHands.getPose('left', 'grip')`), and the panel is drawn the same way as the revolver: flat-coloured triangles from the debug drawer, every frame. **No textures and no text** (Rowan, 31 Oct): textures drew too slowly and lagged when the revolver was built. So the wrist shows the strip as simple shapes:

- **Fuel:** two bars, your own tank and the cargo tank, that shrink as they empty.
- **Ammo:** six pips in a ring, like the cylinder, lit or dark.
- **Threat light:** one square, off, amber or red.
- **Distance to Pine Gap:** a number drawn as seven-segment digits, each segment a thin bar, like an old digital watch.
- **Buttons:** flat coloured shapes with a simple icon made of triangles.

Buttons such as Tow, Fit and Save are pressed with **BeamNG's own VR pointers**, the ones that open doors (Rowan, 31 Oct). The on-screen app already sits on BeamNG's VR screen, where those pointers should click it as they click any UI app. The wrist panel is drawn by us, so the game's pointers may not see it; if not, it does what they do: a ray from the right controller's aim pose, highlighted where it lands, and the trigger presses. To check in game first. **❓ OPEN — Q9:** does raising the wrist to your face show more, such as the siphon bar or a tow countdown?

## What carries over from Earth Freight

Copied, then adapted. Nothing is shared at run time.

| Earth Freight | In Tanker |
|---|---|
| `earthAdapter.lua`, `location.lua`, `odometer.lua` | As is: where you are on Earth, distance driven, teleports. |
| `places.lua` and the tiles | Cut down to Australia, used for the route and leg ends. |
| `fuel.lua` | As is: reads and sets the tank. Gains siphoning and the leak. |
| `cargo.lua` | Adapted: the cargo tank and its weight on the truck. |
| `garage.lua`, `workshop.lua` | Adapted: fitting looted parts instead of buying them. |
| `persistence.lua` | Adapted: saves hold the leg, the truck, fuel, ammo and spare parts. |
| `punctures.lua` | As is: the road still bursts tyres. |
| `hud.lua` and the UI | Adapted: fuel, ammo, leg progress and threats. |

## What gets dropped

The job board and pay, towns and their boards, used cars, the helicopter, flights, shipping, beacons and the dangerous road contracts. Money goes too, since there is no buying or selling.

## What gets built fresh

- **Hoons:** taking them from the traffic pool, chase AI (from Earth Enduro's CarKov), when a car counts as down, and loot.
- **Hardcore rules:** the single save, the timed tow, and putting broken parts back on load.
- **Tankers and convoys:** taking them from the traffic pool, flee AI, escorts.
- **Siphoning:** moving fuel over time from a downed tanker.
- **Ammo** and the hookup to the pistol's hit event.
- **Legs:** the route, the leg ends, and difficulty rising leg by leg.
- **The story:** an intro, something along the way, and the new orders at Pine Gap.

## First playable slice

The smallest version that shows whether the game is fun:

1. Start in Rowan's starter truck at the edge of the desert, on leg 1.
2. One Hoon in a rat rod chases you and rams.
3. The VR revolver can stop it, with ammo counting down.
4. Pull up to the downed car and loot its fuel and ammo.
5. One AI tanker that flees, and a siphon from it once it is stopped.

Before step 2, test BeamNG's chase and flee AI on Earth's roads, because the rest depends on it.

## Open questions

Answered on 31 Oct: the ending (open ended, with orders after Pine Gap), game over (hardcore, no restarts, free tow), the starting truck (Rowan's config), Hoon cars (vanilla rat rods that ram), siphon speed (1 L a second), VR (VR first), damage between sessions and the 30-second tow.

- **Q1:** What the orders at Pine Gap are, and how the player leaves Australia.
- **Q2:** The route and its legs.
- **Q5:** Which vanilla configs are rat rods, and which later Hoon type comes first: exploding, fire or spiked?
- **Q9:** What the wrist HUD shows when raised to your face.
