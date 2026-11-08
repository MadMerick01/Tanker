# Tanker — Design

The game was called Mad Merick while it was being planned; MadMerick renamed it **Tanker** on 31 Oct 2026. The GitHub repository was renamed to Tanker the same day.

Status: **playable skeleton**: the start by Lake Eyre, fuel, saving, the HUD strip and wrist HUD, the start page, siphoning, the first Hoon, the pump between the bed tank and the truck's tank, and paying for parts with fuel on the Garage tab (see the README and CHANGELOG). Not built yet: buying new vehicles with fuel, ammo loot, fleeing tankers and trailers. This doc collects what MadMerick decided in the project thread (first on 31 Oct 2026, the vision on 2 Nov) and marks what is still open. Open questions are tagged **❓ OPEN** inline and gathered in [Open questions](#open-questions) at the end.

## The pitch

**Tanker: an open-world, long-haul road warrior simulation.** *Raid tankers, fight off Hoons, keep your tanks full and push on.* Built for VR, triples and telemetry. (MadMerick, 6 Nov. MadMerick turned down "survival", "roguelike", "combat" and "challenge" as the label: sim racers are here to drive, not to play a shooter.)

It is played on BeamNG.drive, across the real Australian outback on [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth). MadMerick set out the vision on 2 Nov:

- You start in a small ute with a fluid tank in the bed holding enough fuel for about 200 km, by **Lake Eyre** in outback South Australia, a long way south-east of Alice Springs. You can move fuel between the fluid tank and the vehicle's own tank.
- You must get to Pine Gap for the realignment codes that stop the AI, then to Monaco (this may change) to enter them in the mainframe.
- On the way you meet **Hoons**, muscle cars that try to intercept you on chase mode AI, and **tankers or smaller trucks carrying fuel**, which flee.
- You siphon fuel and collect ammo from Hoons and tankers.
- **Fuel is the currency.** The HUD shows what your fuel is worth in dollars, and you can spend that on parts and new vehicles, as in Worldwide Trucking. Every litre you spend is a litre you can't drive on.
- Eventually you get a bigger truck and can take whole fuel trailers off tankers and hook them to your own truck, for massive capacity.

You defend yourself with a VR revolver.

It is a separate game from Earth Freight (Worldwide Trucking Career). It reuses Earth Freight's plumbing by copying it, the same way Earth Freight was built from Earth Enduro, and changes the game on top: Earth Freight is about choosing what to carry for pay, Tanker is about surviving the road and taking what you need.

## The story

An AI has escaped its testing sandbox and turned off everyone's water, electricity and internet (MadMerick, 2 Nov). There are no electric cars, and fuel was already short because the Strait of Hormuz is blocked. The world's population has turned on each other, fighting over the fuel that is left.

The realignment codes that can stop the AI are at Pine Gap, the little-known American base outside Alice Springs. Getting there is the first goal of the game. Then the codes have to be carried to Monaco and entered in the mainframe.

**Pine Gap is not the end** (MadMerick, 31 Oct). The game is open ended: the trip to Monaco sends you out into the open world, and reaching Pine Gap should make the player realise how huge the game is. BeamNG.Earth covers the whole planet, so the world is already there. **❓ OPEN — Q1:** how the player gets from Australia to the next continent (by sea, by air, or a jump).

Pine Gap is a real facility. Everything about it in the game is fiction.

## The route

The first goal is **Lake Eyre** (28.8807093 S, 137.6024985 E, in outback South Australia; MadMerick, 6 Nov) to Pine Gap: about 680 km in a straight line, which the game counts as about 800 km by road. Starting with about 200 km of fuel means you have to take fuel on the way. The run used to start at Kulgera Roadhouse (from 2 Nov, about 270 km out) and before that at Yorkeys Crossing, Port Augusta, about 1,230 km out; saves from there still work and carry on from where they were saved.

| Leg | From → to | Roughly | Character |
|---|---|---|---|
| 1 | Kulgera → Erldunda | 75 km | The learning leg. Few Hoons. |
| 2 | Erldunda → Stuarts Well | 110 km | First tankers. Fuel gets tight. |
| 3 | Stuarts Well → Alice Springs | 90 km | Heavy Hoon country. |
| 4 | Alice Springs → Pine Gap | 20 km | The final run to the base. |

Distances are rough, from the real highway, and to be checked in game. These legs were planned from Kulgera; the drive up from Lake Eyre to Kulgera (likely via the Oodnadatta Track and Marla) has no legs yet. **❓ OPEN — Q2:** whether the coordinates land on the roadhouse, and how the legs play.

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

**Fuel is the currency** (MadMerick, 2 Nov, replacing "no buying or selling" from 31 Oct). The HUD shows your fuel's value in dollars, and you can spend it on parts and new vehicles as in Worldwide Trucking, so every purchase is fuel you can't drive on. Fuel itself still only comes from Hoons and tankers.

## The tanker

You start in a small ute with a fluid tank in the bed (MadMerick's TankerStarter config). Progression is spending fuel on parts and upgrades, then on new vehicles, and eventually on a bigger truck that can take a whole fuel trailer off a tanker and tow it (MadMerick, 2 Nov).

The tank is three things at once:

- **Your fuel.** The truck's own tank keeps you moving.
- **Your store.** The cargo tank holds the fuel you have taken. You top up your own tank from it.
- **The target.** It is what every Hoon is after.

**The starting truck.** MadMerick will test a truck in game and upload its config. It needs a fluid tank, to be slow enough that you cannot outrun a rat rod, and sturdy enough to survive a ramming.

## Hardcore rules

Decided by MadMerick, 31 Oct: **hardcore from the start, no restarts.** You manage your own fuel and repairs. If you run dry or wreck the truck, you have to get yourself out of it with what you are carrying. MadMerick added **Start a new game** on 2 Nov: it throws away the run and its save and starts again at the start, so there is still only ever one run on the go.

**One save.** The game saves where you are, so you can stop playing and carry on later from the same spot. There is no going back to an earlier save. What the truck keeps between play sessions is in [Damage between sessions](#damage-between-sessions).

**Free tow, but you are exposed.** Stuck in a ditch or on your side, you can tow yourself out for free, the same way as in Worldwide Trucking: get out, walk to a clear spot within 50 m, and the truck is brought to you. Unlike Worldwide Trucking, the tow takes **about 30 seconds of winching** (MadMerick, 31 Oct), and there is a good chance a Hoon turns up while you wait.

### Damage between sessions

BeamNG does not save a car's bent body when the game closes, so the truck has to be rebuilt from what the save holds. Agreed by MadMerick, 31 Oct:

- **Saved:** fuel in each tank, ammo, spare parts, which parts are broken or missing, and which tyres are flat.
- **Put back on load:** broken parts stay broken, missing parts stay missing, and flat tyres stay flat.
- **Not put back:** dents. The truck comes back straight, but anything that stopped working still doesn't work.
- **No escaping a fight by quitting:** saving is only allowed with no Hoons nearby, so quitting mid-chase doesn't get you out of it.

## Hoons

The raiders are called **Hoons** (MadMerick, 31 Oct). They drive **vanilla muscle cars** (MadMerick, 2 Nov; rat rods on 31 Oct), so nobody needs extra car mods, and chase your truck using BeamNG's AI in chase mode. They spawn behind or ahead of you, close in, and ram or box you in. Early legs have few and weak ones; later legs have more, faster ones, and some work in packs.

**For now they ram and do damage.** Later Hoons lean into BeamNG's physics:

- **Exploding Hoons** that blow up when they hit you, or when you shoot them enough.
- **Fire Hoons.**
- **Spiked Hoons** that rip your tyres when they come alongside.

Each downed Hoon carries a little loot: some fuel, some ammo, sometimes a part.

The chase code is not in Earth Freight. It is the CarKov hostiles in Earth Enduro, which will be copied over and given rat rods. **❓ OPEN — Q5:** which vanilla configs count as rat rods, and which of the later Hoon types comes first.

### Desert mode: the slots (6 Nov)

MadMerick decided on 6 Nov that Hoons have **two modes, desert and roads**, each with its own AI. Desert mode is for when there are no roads around, and works with **eight slots** around the player's truck, named L or R (left or right), F or R (front or rear), then N or F (near or far): RFF is right, front, far; LRN is left, rear, near.

- **Near** slots are 10 m out to the side, level with the front or back of the truck.
- **Far** slots are 60 m out to the side and 10 m beyond the front or back.
- **Sizing up.** A new Hoon moves through the far slots like a hyena circling prey. Some move in closer sooner.
- **Attacks.** Hoons want to stop you for your fuel. Some attacks swipe you and drive back out to a far slot; others try to box you in.
- **The test button.** Spawn a Hoon on the Rig tab loads a HoonOld1 (or reuses a hidden one from an earlier Hoon) and puts it at a random free far slot. Pressing again while Hoons are out adds another, up to four, so the attacks can be tested and improved.

How it's built for now (`pack.lua`, `packCar.lua`, `tankerDriver.lua`): moving between slots uses **Tanker's own desert driver** (MadMerick, 6 Nov), a vehicle extension that runs in the Hoon's car every frame. Tanker sends it the slot's position, a little ahead, and a speed every 0.2 s: your speed, plus more the further the Hoon is behind its slot, capped at 15 m/s faster than you. It steers by pure pursuit (arc curvature times wheelbase, with yaw-rate damping and a steering rate limit), caps its speed by the arc at 0.9 g, and drives the pedals within MadMerick's logged limits from BeamngAdvancedSelfDriving (0.65 g braking, 0.45 g accelerating, scaled by the ground's grip). It holds still on the parking brake, since the brake reverses in the arcade gearbox. When it's stuck it reverses and retries, as smartAI v0.3 does. If the driver can't load, BeamNG's stock slotTraffic mode (drive at a point at a speed) takes over. Script AI was tried first and left Hoons standing still. Attacks use the same driver, so there is one brain to train (MadMerick, 6 Nov). A swipe comes after the Hoon edges in to 6 m for 1.5 s so you can see it coming. It aims 0.5 m from your middle on its side, level with your front or back, only 2 m ahead of that point, at your speed. **Road mode** (MadMerick, 6 Nov) is also Tanker's own driver: a self-contained version of what BeamNG's chase mode does, using MadMerick's trained country limits. Every 0.5 s, in the car, it asks the road map for a chase route to the player (`mapmgr.findBestRoad` and `mapData:getChasePath`, the same calls chase mode makes) and turns it into a line of road points. It plans a speed for each point: the corner there at the speed-dependent country cornering limit (0.9 g at a crawl, 0.95 g from 40 km/h), then a backward pass so it can always brake at 0.65 g for the corners ahead. It steers at a point 0.8 s of its speed along the route (6–30 m), at the slowest planned speed between here and there. It doesn't ram (MadMerick, 6 Nov). Within 50 m it overtakes 3.5 m to the player's right (Australia drives on the left) at their speed + 8 m/s. Once 10 m clear of their front it cuts into their lane, settles for 1 s, then brake-checks down to 20% of their speed for 1.5 s. It drives on for 4 s and repeats, or overtakes again if they got past. If the player stops, it parks 6 m in front to block them. Further than 80 m, it catches up along the route again. With no route, it catches up from 15 m behind them. The driver reports each phase to Tanker for the HUD. The road Hoon (the one that comes every few km) uses this now. If the driver can't load, BeamNG's chase AI is the fallback, with smartAI's `moonhawk_country` when that mod is installed. **Rear far slots and lagging (MadMerick, 6 Nov):** Hoons heading for LRF or RRF ended up 200 to 300 m back, sometimes reaching 400 m and despawning. A Hoon that overshot its point had its aim behind it, and the driver turns for a point behind it at full lock and 6 m/s. Now a Hoon never aims less than its usual lead ahead of itself (2 m in a swipe), so it keeps running parallel and the speed law drops it back. The rear far slots are now 30 m out to the side (`REAR_FAR_SIDE`) and still 10 m beyond your back, about 31 m from you. **Changing spot by accelerating (MadMerick, 6 Nov):** Hoons used to touch the brakes when changing slot, and at speed that left them well behind. Circling now only moves forwards. A rear far slot goes to the front far slot on the same side, and a front far slot crosses round the player's nose to the other front far slot. While a Hoon is getting into place (circling, closing in or peeling off), it never asks for more than 1 m/s below the player's speed (3 m/s before the second pass). The driver lifts off rather than braking when it is asked for up to 3 m/s less than it is doing. **Smarter intercepts (MadMerick, 6 Nov; settings at the top of `pack.lua`):**
- *Aiming where you'll be.* The pack keeps a smoothed reading of the player's turn rate. While they turn faster than 0.05 rad/s, each Hoon aims at its spot around the player's future pose on that arc (`pack.future`). It looks ahead by the time it needs to reach the spot, up to 2.5 s, so it cuts inside the turn. Speed still comes from where it is now.
- *The PIT.* An attack from a rear near slot is a PIT half the time, and 80% of the time while the revolver is drawn. The Hoon lines up 3 m off the back corner, level with the player's back. It then aims 1 m past the player's middle, 1.5 m ahead of their back, at the player's speed plus 2 m/s, with no brake. Contact and peeling off work as in a swipe.
- *Respecting the revolver.* The pack is told whether the flatscreen or VR revolver is drawn. While it is, Hoons getting into place weave ±4 m every 2.5 s, rear Hoons spend their circling moves at their back corner, and more attacks are PITs. A hit that doesn't stop a placing, lining-up or swiping Hoon makes it shy for 6 s. It peels off to a far slot, sits 1.5 times further out, may ease off up to 4 m/s below the player's speed (still no brake) and won't attack.

**No brakes in the desert (MadMerick, 6 Nov, second pass):** Hoons still touched the brakes and dropped back, so a Hoon getting into place, lining up or swiping now sends its driver mode `coast` (`swipe` for the swipe), and the driver never brakes in those modes. It lifts off instead, even for a tight arc. A Hoon in those states asks for at most 1 m/s below the player's speed (`DROP_MPS`), so it moves round them sideways or forwards and only eases back slowly. A sideswipe matches the player's speed exactly and turns in hard at that speed, without slowing for the arc. Boxes, robberies and road mode can still brake. **Never stopping (MadMerick, 6 Nov):** a desert Hoon always has somewhere to drive and never stops while it can drive. It doesn't need to sit exactly in its slot. Its speed never drops below 8 m/s. When the speed law would want it slower (the player has stopped or is slow, or the Hoon is past its point, as when the player chases it), a Hoon getting into place circles its point 20 m out, aiming 0.8 rad further round, and that counts as having arrived. Further off, it keeps its usual aim at 8 m/s, so it turns back. A windup or swipe only keeps its speed up. A box is the one exception, since the box parks in front of the player on purpose. A driver that is stuck rests 3 s after its 4 tries, then tries again. **Switching (MadMerick, 6 Nov):** spawned Hoons use road mode once the player has been within 30 m of a road for 5 s, and desert mode once they've been further than that for 5 s. A Hoon going to desert mode takes the nearest free far slot and circles 0 or 1 slots before closing in. The road Hoon that comes every few km is always in road mode for now. **Team boxes (MadMerick, 6 Nov):** Hoons work together to box you in from either side. A box needs at least one other free Hoon (one on its own swipes), and every free Hoon joins. The lead goes 8 m in front of you. The nearest helper takes 4 m off the side it is already on, the next takes the other side, and a third sits 8 m behind you. With two or more helpers free, 60% of attacks are a box (35% with one). First the team gathers: the lead runs in front at your speed until every helper is within 8 m of its spot, or for 8 s at most. Then they squeeze, all slowing to 60% of your speed together. Stopped for 3 s, you are boxed in, and they hold you for 5 s. The box ends 15 s after the squeeze starts if you haven't stopped. If the lead goes down or is lost, a side helper takes over the lead and the rest keep going. A helper whose lead has peeled off peels off too. Only one Hoon attacks at a time and each slot holds one Hoon. Every distance and time is a one-line setting at the top of `pack.lua` and `tankerDriver.lua`. **❓ OPEN:** the steering lock (0.6 rad is a guess), how the driver copes on BeamNG.Earth's desert terrain, training it further on MadMerick's logs, and the roads mode's own behaviour.

### Out of sight (6 Nov)

**Hoons and tankers never spawn in the player's view** (MadMerick, 6 Nov). Every new one is put in the 180 degrees behind the camera (`behind.lua`): a point counts when it is at least 5 m behind the camera's flat facing (`getCameraPosition`, `getCameraForward`, or `core_camera`). With no camera to read, the truck's facing stands in. A new pack Hoon picks only free far slots behind the camera. With none free there, it starts 60 m straight behind the camera and drives to its slot. In road mode it starts on the road 80 m behind you, or behind the camera if that is in view. The road Hoon tries the road straight behind the camera, then behind and ahead of the truck, and takes only a spot behind the camera. The tanker from the spawn button appears 60 m straight behind the camera, facing away from you.

### In the bushes (6 Nov)

BeamNG.Earth's desert has small solid bushes that wreck a car. BeamNG can't let one car ignore bushes but not the ground (both are static collision), so MadMerick chose two things instead (6 Nov):

- **Feelers.** The desert driver (`tankerDriver.lua`) casts three rays ahead every 0.1 s, straight on and 0.35 rad either side, 0.3 m above the car's middle. They look 1.2 s of its speed ahead, 8 to 30 m. A hit counts only if a ray cast down just past it finds something standing more than 0.3 m above where it was touched, so a hillside doesn't count and a bush does. The nearer the hit, the more it steers away, up to 0.8 of full lock, towards the clearer side (or the side its point is on). Something straight ahead and close holds its speed to 10 m/s, by lifting off in the desert. A swipe holds its line. Without `obj:castRayStatic` the car doesn't feel, and says so once in the log.
- **Smarter feelers (MadMerick, 6 Nov, second pass).** Five feelers now: straight on, 0.35 rad either side, and two straight on along the car's edges (1.1 m out), so a gap narrower than the car counts as blocked (both edges hit also holds the speed down). The sides are scored with their edge feeler, so a clump with a bush beside the one ahead is passed on its open side. Once it picks a side it keeps it for 1 s unless that side becomes worse by 0.3 or more. The feelers follow the ground: each aims at the same height above the ground at its far end as it starts at. One that touches the ground on the way (a crest, or a slope steeper than its aim) carries on from just past that spot at its height again, up to 3 times. Up to about 16 rays every 0.1 s per Hoon on open ground, more only when a feeler touches the ground.
- **Unsticking out of sight.** A pack Hoon slower than 1 m/s for 4 s while you drive, at least 50 m from you and behind the camera, is moved 8 m on towards where it was heading, landing behind the camera too (`pack.lua`, `UNSTICK_*`). The TankerMob does the same after 5 s, moving away from you, and is set fleeing again (`tankerMob.lua`). The move uses `setPositionNoPhysicsReset`, so its damage stays. At most 3 tries for a Hoon and 2 for the tanker before it gets going again. A Hoon that hit you and still won't move is down as before. Robbing and boxing Hoons are never moved.

## Roads are watched: drone strikes (6 Nov)

MadMerick wants Tanker played **off road** (6 Nov): it's what makes the game different, it pushes the player to build an off-road truck and navigate by compass, and the Hoons drive far better off road than among road obstacles. The story is that the rogue AI has the world's road network under surveillance. Stay on a road and it sends a drone (`drone.lua`, settings at its top):

- **On a road** means within the nearest road's half width (from the map's node radius, at least 3 m) plus 1.5 m of its middle (`map.findClosestRoad`).
- **Crossing is safe.** Nothing shows for the first 5 s. After that a banner at the top of the screen counts down to the drone.
- **30 s on a road** and it hits. The drone is heard for the last 5 s (`sounds/drone.ogg`), then the blast (`sounds/blast.ogg`): a short burst of repulsion beside the truck, 2.5 m off a random side at ground level for 0.2 s, the technique BeamNG's own Explode uses (`obj:setPlanets` with a negative mass, at about half Explode's strength and beside rather than under the car). Half the time it also bursts a tyre (`beamstate.deflateRandomTire`). No fire.
- **Still on the road,** the next drone hits 20 s later, with no second warning.
- **Off the road when it arrives,** it misses (a quieter blast). Off the road for 5 s, the AI loses you and the count starts again from 30 s. A shorter trip off the road doesn't reset it.
- It runs only while the run is on the road, and ends when the run stops or Tanker goes. **❓ OPEN:** the blast's strength and the sounds need testing in game.

## Tankers

Other tankers drive the highway, alone or in convoys with escorts. When they see you coming they run, using BeamNG's AI in flee mode. You stop them by shooting out their tyres or forcing them off the road.

A downed tanker is the big prize: a lot of fuel, but it takes time to siphon, and the escorts arrive while you do. A siphon moves **1 litre a second** to start (MadMerick, 31 Oct), so a few hundred litres means minutes standing still. You can drive away mid-siphon and keep what you have so far; driving off simply stops it. You can come back and siphon the same car again (MadMerick, 6 Nov), as long as a downed Hoon is still there: it goes once you are more than 400 m from it. The first siphon works on any car within 10 m, so it can be tried before tankers exist.

**The centre window (MadMerick, 6 Nov).** Siphoning happens in a window in the middle of the screen, shown only while you are stopped. **You siphon on foot** (MadMerick, 6 Nov), in BeamNG's walking mode: stopped in the truck within 10 m of a car, the window and the Road tab say you must be on foot. On foot (the player is the `unicycle`, or `gameplay_walk.isWalking`), Tanker remembers the truck you got out of. The truck must be parked within 15 m of you (`TRUCK_METRES` in `core.lua`), it is never offered as the car to siphon, and the fuel goes into it by its id. While you are on foot, its fuel is read by its id. The bed tank's weight is poured in once you are back, parts checks wait, the walker's spawn is not taken as a new truck, and saving waits. Hoons nearby don't stop a siphon (MadMerick, 6 Nov). The window turns red and warns you. Within 10 m of a car on foot, it offers the siphon. With a bed tank fitted, it asks where the fuel goes: **Into your truck** or **Into the bed tank** (without one, a single **Siphon fuel** button). While fuel flows it shows their tank and the tank being filled, with a Stop button, then the result for 6 s. Fuel into the bed tank goes straight into its own number, so it is never made or lost. Hoons are never given fuel. The wrist panel is unchanged.

**Hoons rob you when you can't move (MadMerick, 6 Nov; `robbery.lua`).** Stood still (under 1 m/s) for 10 s with a pack Hoon up, and the nearest Hoon that isn't attacking or boxing you pulls up 4 m off your side, slowing as it gets there, and stops. Within 8 m and nearly stopped, it siphons 4 L a second: the bed tank first, then your truck's tank, always leaving you **10 L**. Every litre goes into its own tank, so a Hoon you shoot down on the way out can be siphoned back. Once you are down to 10 L or its tank is full, it speeds off at 30 m/s, away from you and the way you face, and is gone at 400 m. With 10 L or less on board it pulls up, checks for 4 s and speeds off with nothing. Driving off stops a robbery: a Hoon that got nothing goes back to circling, one that got some runs with it. After a robbery the next Hoon can come 6 s later. It works in desert and road mode, but only for the spawned pack Hoons, not the road Hoon that comes every few km. "Can't move" is read as stood still for 10 s, since Tanker can't tell a stuck truck from a parked one. Every number is a one-line setting at the top of `robbery.lua` and `pack.lua`. The centre window shows the robbery, what it took and your tanks.

## Spawning from traffic

Decided by MadMerick, 31 Oct: **Hoons and tankers come from BeamNG's own traffic.** Spawning a car mid-drive loads it and causes a frame hitch. Traffic loads its cars once, when it starts, and then only moves them: a traffic car out of sight is picked up and put back on another road ahead of you. Tanker uses the same trick.

- **The pool.** When the game starts, traffic is set up with a pool that already holds rat rods and tankers. The one hitch happens there, behind the loading screen. Traffic runs at least 7 cars, which is plenty (MadMerick, 31 Oct): **one type of rat rod and a tanker to start**, 3 or 4 Hoon types at most later.
- **Where traffic puts its cars.** A traffic car nobody is in, once it is out of sight and far enough behind you, is reset and put back down on a road further ahead, often in a new paint. Earth Freight already works around this for the player's parked car. So a car stays a traffic car only while it is just driving around; once it becomes a Hoon or a target tanker it is taken out of traffic, the same way Earth Freight parks the player's car, and given back once it is looted and left behind.
- **An encounter.** When a Hoon attack or a tanker sighting is due, Tanker takes a pooled car that is out of sight, moves it into place, and switches its AI to chase (Hoons) or flee (tankers).
- **After the fight.** A looted wreck goes back to traffic, which resets it and moves it away once you have driven off, ready to be used again.

**First Hoon (2 Nov):** for now the Hoon has its own car instead of borrowing one from traffic. It loads once when the run is on the road, then is switched off (not drawn, not simulated) until an attack switches it back on, which does not hitch, the same trick traffic uses. This doesn't depend on traffic containing a rat rod, and leaves the player's traffic as they set it. The model is the first of `hotrod`, `burnside` and `moonhawk` the game has. Moving Hoons into the traffic pool is still open once more types exist. A Hoon only comes while the player is on a road (within 30 m), and is put on solid road 250 m behind or, failing that, ahead, since BeamNG.Earth's road further out may not have loaded (MadMerick, 2 Nov). The chase uses BeamNG's own AI for now; MadMerick is training an AI model of their own to drive Tanker's cars, which will take over later.

**The Hoon car (6 Nov):** every Hoon, the road Hoon and the ones from Spawn a Hoon, drives **HoonOld1**, MadMerick's config: a rusty Barstow with the I6, a welded diff, a rollcage, a cut hood, a tube front bumper and offroad tyres on steel wheels. It ships in the mod under `vehicles/barstow`, so it needs no other mods. If the game has no Barstow, a plain Moonhawk or Burnside is used.

**Never the player's car (6 Nov):** MadMerick's car went unstable while shooting at Hoons, and the game put them in a Hoon's car. After Start a new game, the new truck (the same vehicle id, replaced) was still being driven, because Tanker kept sending the Hoon's orders to that id. Now `hoonCar` and `packCar` refuse any command to the player's vehicle id, so a Hoon in the player's car counts as gone and is forgotten. The road Hoon loads a fresh car. Hoon cars are set `playerUsable = false` when hidden or placed, so the game's vehicle switching skips them. Start a new game also sends the player's vehicle `tankerDriver.stop()` and `ai.setMode('disabled')`. **A second Hoon (6 Nov):** **HoonFast2** is MadMerick's second config, a dark Barstow with the 353 V8 and a stage 1 supercharger, a cowl hood, a rollcage, rally front tyres and offroad rears. Every Hoon is HoonOld1 or HoonFast2 with even odds (MadMerick, 6 Nov). The pool holds 3 of each. A Hoon takes the kind it rolled, or the other kind when the pool has none left, and loads the rolled kind only when the pool has no Barstows at all. The config comes from the car's `partConfig` file name. **Tanker's own traffic (6 Nov):** normal BeamNG traffic should not run in Tanker (MadMerick, 6 Nov). The traffic pool is there to preload Tanker's Hoons and tankers. Once the run is on the road, `trafficPool.lua` calls `gameplay_traffic.setupTraffic` with a vehicle group of only Tanker's cars: 5 HoonOld1s (a full pack of 4 plus the road Hoon) and 2 TankerMobs (now 3 HoonOld1s and 3 HoonFast2s, see above), with 4 shown at once and the rest hidden by traffic's own pooling. `setupTraffic` clears whatever traffic was running first. Every 10 s Tanker looks for AI traffic that isn't a Barstow or a semi (the player switching traffic on from the radial menu, say) and deletes those cars one by one. The model comes from traffic's own record of the car (`model.key`). Traffic is never set up a second time: in MadMerick's first test (6 Nov) the game stuttered every 15 s or so, which fits a second setup reloading all 7 cars on each check. A Hoon's car, or the TankerMob, is the pooled car of that model furthest from the player, taken out of traffic with `removeTraffic`. Hoons that are done are kept hidden for the next one, not given back. The road Hoon waits up to 20 s for traffic to load, and only loads its own car when the pool has none left or traffic doesn't load. No parked cars either (MadMerick, 6 Nov): each sample, any cars `gameplay_parking` parked are deleted and parking is switched off. **❓ OPEN:** whether 5 + 2 cars, 4 of them shown, suits the frame rate on BeamNG.Earth, and whether traffic repainting a respawned HoonOld1 spoils its rusty look.

Earth Freight already works with traffic on BeamNG.Earth: its traffic police chase and catch the player, and it takes the player's own car in and out of traffic. So traffic runs on Earth's roads, and the police chase is the model for the Hoons. MadMerick has driven a lot with traffic on Earth and seen no problems (31 Oct).

Things to check in game:

- How many cars the pool can hold before the frame rate suffers, since every car in it is simulated.
- Whether traffic can carry a tanker trailer, or whether pooled tankers have to be rigid trucks.
- Whether changing a car's paint or parts forces a reload (and a hitch), so each kind of Hoon needs its own pooled car.

## The VR revolver

MadMerick's [BeamngVRcontrollerPoses](https://github.com/MadMerick01/BeamngVRcontrollerPoses) mod. Hold the right grip to draw the revolver, pull the trigger to shoot.

What it does today:

- Each shot is a ray. The car it hits gets pushed and dented where it was hit.
- A hit near a wheel hub flattens that tyre, so shooting out a fleeing tanker's tyres already works.
- Every hit reports back to the game with which car was hit and where.
- There are no drivers to hit, so a car is stopped by its tyres, its damage or its engine.

What it needs for Tanker (two small changes in the pistol mod, so Tanker never touches its code):

1. **Ammo.** It currently fires without limit, every 0.12 s. It needs a six-round cylinder, a reload, and a way for Tanker to refuse a shot when you are out of ammo.
2. **A hit event** other mods can listen to, so Tanker hears every hit and decides when a Hoon is down.

Tanker needs the pistol installed. **VR first** (MadMerick, 31 Oct). **Flatscreen** (MadMerick, 3 Nov): without VR, Tanker has its own revolver that aims with the mouse (from MadMerick's Bolides The Cut, `FirstPersonShoot.lua`). Its shot is the VR revolver's own (MadMerick: "the same as our existing VR one"): `vrPistol.shoot` when the VR mod is installed, or Tanker's copy of `vrPistolHit.lua` (`tankerHit.lua`) when it is not, so tyres and driver shots work the same. It has six rounds, a reload and spare rounds kept in the save. Tanker listens to `onVrPistolHit` and `onVrPistolDriverHit` from both guns: a driver shot, or four hits, stops a Hoon.

## The HUD

Like Worldwide Trucking's: a slim strip that is always there, which opens into a few tabs. Fairly simple, but interesting. MadMerick (31 Oct): build it **both on screen and on the left wrist in VR**, then keep whichever plays better, or both.

**The strip, always visible:**

- **Fuel:** your own tank and the cargo tank, in litres, with a range estimate ("Range 140 km").
- **Ammo:** six pips for the cylinder, and your spare rounds.
- **Pine Gap:** distance left.
- **Threat light:** off, amber when a Hoon is near, red when one is on you. It still shows when the HUD is minimised, like Worldwide Trucking's gold and red dot.

**Three tabs:**

1. **Road:** distance to the next leg end, which way anything spotted is (a tanker, a Hoon pack), and the save button, greyed out while Hoons are close.
2. **Rig:** what is broken, which tyres are flat and how fast the tank is leaking, and your spare parts, each with a Fit button. The Tow button and its 30-second countdown are here too.
3. **Loot:** only shown beside a downed car. What it carries, the siphon bar filling at 1 L a second, and a "Hoons inbound" warning.

**No radio for now** (MadMerick, 31 Oct). One-line radio messages that tell the story as you drive could come later.

### On screen and on the wrist

Both read the same HUD state, which the game sends at most 4 times a second, as in Worldwide Trucking, so they always agree.

- **On screen:** a BeamNG UI app, built from Worldwide Trucking's.
- **On the wrist:** a small panel drawn on the left hand, like a watch. The pistol mod already tracks the left controller (`vrHands.getPose('left', 'grip')`), and the panel is drawn the same way as the revolver: flat-coloured triangles from the debug drawer, every frame. **No textures and no text** (MadMerick, 31 Oct): textures drew too slowly and lagged when the revolver was built. So the wrist shows the strip as simple shapes:

- **Fuel:** two bars, your own tank and the cargo tank, that shrink as they empty.
- **Ammo:** six pips in a ring, like the cylinder, lit or dark.
- **Threat light:** one square, off, amber or red.
- **Distance to Pine Gap:** a number drawn as seven-segment digits, each segment a thin bar, like an old digital watch.
- **Buttons:** flat coloured shapes with a simple icon made of triangles.

Buttons such as Tow, Fit and Save are pressed with **BeamNG's own VR pointers**, the ones that open doors (MadMerick, 31 Oct). The on-screen app already sits on BeamNG's VR screen, where those pointers should click it as they click any UI app. The wrist panel is drawn by us, so the game's pointers may not see it; if not, it does what they do: a ray from the right controller's aim pose, highlighted where it lands, and the trigger presses. To check in game first. **❓ OPEN — Q9:** does raising the wrist to your face show more, such as the siphon bar or a tow countdown?

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

1. Start in MadMerick's starter truck at the edge of the desert, on leg 1.
2. One Hoon in a rat rod chases you and rams.
3. The VR revolver can stop it, with ammo counting down.
4. Pull up to the downed car and loot its fuel and ammo.
5. One AI tanker that flees, and a siphon from it once it is stopped.

Before step 2, test BeamNG's chase and flee AI on Earth's roads, because the rest depends on it.

## Open questions

Answered on 31 Oct: the ending (open ended, with orders after Pine Gap), game over (hardcore, no restarts, free tow), the starting truck (MadMerick's config), Hoon cars (vanilla rat rods that ram), siphon speed (1 L a second), VR (VR first), damage between sessions and the 30-second tow.

- **Q1:** What the orders at Pine Gap are, and how the player leaves Australia.
- **Q2:** The route and its legs.
- **Q5:** Which vanilla configs are rat rods, and which later Hoon type comes first: exploding, fire or spiked?
- **Q9:** What the wrist HUD shows when raised to your face.
