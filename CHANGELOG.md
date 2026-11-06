# What's changed

Every change to Tanker, in plain English, newest first. Each build is a new download on the [Releases](../../releases/latest) page.

## Coming next

Changes that are finished but not in a download yet. They move into a numbered build as soon as it's published.

- **The strip at the top of the HUD now shows how far the nearest Hoon is,** for example "Hoon 85 m" in red beside the threat light, and it updates as you drive. The **Rig** tab lists every spawned Hoon with its distance under the **Spawn a Hoon** button too.
- **Fixed: spawned Hoons now drive to their spots around you instead of standing still.** Tanker now has its own desert driver for them, built from Rowan's recorded driving. It corners at up to about 0.9 g, brakes at 0.65 g and accelerates at 0.45 g, less on loose ground, and turns the wheel smoothly instead of flicking it. A Hoon speeds up when it's behind its spot, slows down when it's ahead, and runs alongside you once it's there. If it gets stuck, it backs up and tries again a few times. The same driver does the attacks too: a swipe turns in hard at the corner of your truck by the Hoon's spot, a little faster than you, so you can brake or steer away from it. If you have Rowan's smartAI mod installed, the Hoons that come by themselves on the road drive with its open-road settings. A Hoon that was slow to reach its spot also no longer counts as down: a spawned Hoon only counts as down for being stopped once it has hit you.
- A spawned Hoon that gets more than 400 m away from you is now gone straight away, instead of following you from a long way back. A downed Hoon also goes once you're 400 m from it, so siphon it before you drive off. Your save still works.

## Build 18 · 6 Nov 2026

- **Fixed: Reload on a flat screen sometimes never finished.** Pressing **Reload**, or clicking with an empty cylinder, could stay stuck on **Reloading** and never give your rounds back whenever the game briefly lost track of where your truck was. A reload now always finishes after a second and a half and fills the cylinder back up to six from your spares.
- **Unlimited ammo for now, while we test.** Reloading the flat screen revolver always fills the cylinder back to six and never uses up your spares, so the HUD shows **unlimited** spare rounds and the strip shows **+∞**. You still have to reload after every six shots. Later, when ammo is limited again, the **Reload** button will say **No spare rounds** when you run out. Your save still works.

## Build 17 · 6 Nov 2026

- **New: desert Hoons that circle you before they attack.** **Spawn a Hoon** on the **Rig** tab now brings in a Hoon at one of four far spots around your truck, 60 m out to your left or right and just ahead of or behind you. It sizes you up first, moving between those far spots like a hyena circling, then closes in to 10 m off your side and attacks. Some Hoons move in sooner than others.
- A desert Hoon edges closer for a moment before it strikes, and you're told which side it's lining up on, so you can brake or steer to meet it. Some attacks swipe you and drive back out to wait for another go. Others try to box you in: one Hoon gets in front of you and slows down while another sits beside you.
- **Press Spawn a Hoon again** while Hoons are out to add another, up to four at once. Only one attacks at a time while the others hold their spots. The **Road** tab lists each Hoon, where it is around you (for example RFF for right, front, far) and what it's doing. **Clear Hoons** on the **Rig** tab sends them all away. Your revolver stops desert Hoons the same way as other Hoons.
- The Hoons come from BeamNG's traffic when traffic is running, so they turn up without a stutter. With no traffic, the first press loads a muscle car, which can stutter for a moment. Hoons that come by themselves on the road work as before. Your save still works.

## Build 16 · 6 Nov 2026

- **Tanker now calls itself an open-world, long-haul road warrior simulation.** The start page shows it under the title with the new line "Raid tankers, fight off Hoons, keep your tanks full and push on.", and the app's description in BeamNG's app list says the same and adds that it's built for VR, triples and telemetry. Nothing else in the game changes, and your save still works.

## Build 15 · 3 Nov 2026

- **After you press Pay on the parts bill, you're back on your normal camera.** The parts menu closed itself but left you in the free camera, so you had to press Shift+C to get back. Now you return to the camera you were driving with. Your save still works.

## Build 14 · 3 Nov 2026

- **Pressing Pay on the parts bill now closes the parts menu and puts you back in your truck,** ready to drive. If you don't carry enough fuel to pay, the menu stays open so you can change your parts or undo them. Paying on the Garage tab works as before. Your save still works.

## Build 13 · 3 Nov 2026

- **New: the TankerMob,** Rowan's fuel tanker truck. For now it comes from a spawn button: **Spawn the TankerMob** on the **Rig** tab puts it about 60 m ahead of you, and it drives off away from you. Catch it, stop it and siphon its tank. Pressing the button again puts the same truck back in front of you. It's also in BeamNG's vehicle menu under the truck.
- **Spawn a Hoon** on the **Rig** tab (it was called "Send a Hoon now (testing)") now works anywhere, road or no road. Off road, the Hoon appears on the ground about 40 m behind you. Hoons that come by themselves still only come while you're on a road.
- **Fixed: pumping now changes the bed tank.** Pumping between the bed tank and the truck moved fuel in and out of the truck's own tank, but the bed tank's litres stayed the same. The bed tank now goes down as you pump into the truck and up as you pump back. The same fault could make siphoning stop straight away with "There is no fuel to siphon in that car" while still taking a litre, and that's fixed too. Your save still works.
- The starter truck has a new picture, on the start page's **Your truck** card and in BeamNG's vehicle menu.

## Build 12 · 3 Nov 2026

- **You can now shoot on a flat screen, without VR.** On the **Road** tab, press **Draw revolver**, aim with the mouse and click to shoot. An amber crosshair follows the mouse, and a dot shows where it meets the ground. **A hit works exactly like the VR revolver's:** the round has to actually reach the car, walls stop it, it shoves and dents the car, a hit near a wheel flattens that tyre, and a shot through the driver switches the car off and brakes it. With the VR revolver mod installed you also hear its gunshot. Clicking on the HUD never fires.
- **One shot through the driver, or four hits anywhere, stops a Hoon,** with either revolver, in VR or on a flat screen. It comes to a halt so you can pull up beside it and siphon its tank.
- The revolver holds six rounds, and a new run starts with 12 spare. **Reload** refills the cylinder from your spares, which takes a second and a half, and clicking with an empty cylinder starts a reload too. The strip's six pips now show your rounds on a flat screen.
- You can bind keys for **Tanker: draw or holster the revolver** and **Tanker: reload the revolver** in BeamNG's Controls settings, under Gameplay. They don't have keys until you set them.
- In VR nothing changes: the VR revolver mod still does the shooting, and the mouse revolver stays away.
- Your save now keeps your rounds. A save from an earlier build starts with a full cylinder and 12 spare, and the rest of it still works.

## Build 11 · 3 Nov 2026

- **The start page now opens in a big window in the middle of the screen,** like a real game's title screen. The HUD strip stays hidden while it's open and comes back when you press **Back to the road**.
- **Your truck is on the start page,** like a character in a role-playing game: its picture, make and model, the fuel in its tank and bed tank, what that fuel is worth, its range, the km it has driven, its condition and what it costs new.
- **You can now start a new game.** **Start a new game** on the start page asks once more, then takes you back to Kulgera Roadhouse in a fresh starter truck with a new run's fuel. Your old save is only replaced once the new run has started, so if the teleport fails you keep your run. Your save still works.

## Build 10 · 2 Nov 2026

- **Your fuel is now your money.** The HUD strip shows what all the fuel you carry is worth, at $20 a litre, counting both the truck's tank and the bed tank.
- **A new Garage tab lets you buy parts with fuel.** Press **Buy parts** to open BeamNG's parts menu and change what you like. When the truck comes back, a bill shows each new part's price, less a trade-in for the parts you took off, plus any repair the change mended, and how many litres that comes to. **Pay** takes the fuel from the bed tank first and then the truck's own tank. You can't pay a bill bigger than the fuel you carry, and the bill says how many litres you're short.
- **Undo** on the bill puts your old parts back, and so does driving more than 25 metres away without paying.
- Changing parts no longer refills your tank: the truck keeps the fuel it had.
- Picking a different vehicle from the vehicle menu sends you back to your truck for now. Buying new vehicles with fuel comes in a later build.
- Your save now keeps the parts you paid for, and going back to it brings your truck back with them. Saves from earlier builds still work and start with the truck's standard parts.

## Build 9 · 2 Nov 2026

- **You can now pump fuel between the tank in your truck's bed and the truck's own tank.** The **Rig** tab shows the bed tank with how many litres it holds. **Bed tank → truck** pumps fuel into your truck, **Truck → bed tank** pumps it back the other way, and **Stop pumping** stops it. The pump moves 2 litres a second and stops by itself when one tank is empty or the other is full. Fuel in the bed tank weighs your truck down and sloshes, and the second bar on your VR wrist now shows it. Your range counts both tanks.
- A new run now starts with 15 litres in the truck and 25 litres in the bed tank. That's still about 200 km in all, so pump some across before you run dry.
- The bed tank's fuel is kept when you save. A save from an earlier build starts with an empty bed tank, and the rest of that save still works.

## Build 8 · 2 Nov 2026

- **The run now starts at Kulgera Roadhouse,** on the Stuart Highway just over the Northern Territory border, instead of Port Augusta. Pine Gap is now about 270 km up the road.
- **A new run starts with about 200 km of fuel** (40 litres), so you'll have to take fuel from others to reach Pine Gap.
- **The start page tells the new story.** An AI has escaped its testing sandbox and switched off the world's water, power and internet, fuel was already short with the Strait of Hormuz blocked, and the codes to stop it are at Pine Gap and then go to Monaco.
- **Hoons now drive a vanilla muscle car,** the Gavril Barstow, or the Bruckell Moonhawk if the Barstow isn't there, instead of a hot rod.
- A save from the old start still works and carries on from where you saved it. Only a new run starts at Kulgera.

## Build 7 · 2 Nov 2026

- **The first Hoon is here.** About 3 km into the run, and then every 6 to 14 km you drive, a Hoon in a vanilla hot rod appears on the road about 250 m behind you, or ahead of you if the road behind isn't solid yet, and hunts you, ramming your truck. The threat light turns amber when it's within 600 m and red when it's on you, and the **Road** tab tells you how far away it is. You can't save while it's close. It's over when the Hoon is down: stuck or wrecked for 12 seconds, after which you can stop beside it and siphon its tank. It's also over when you get away, staying more than 1.5 km ahead for 30 seconds, or when it has chased you for 5 minutes. Hoons only come while you're driving on a road, never when you're off road, so heading out into the dirt is one way to lose them. To try it straight away, use **Send a Hoon now (testing)** on the **Rig** tab. The Hoon's car loads once, as you set off, so it doesn't stutter the game when it appears. Your normal traffic is left as it is. Your save still works.

## Build 6 · 2 Nov 2026

- **Tanker now has a start page.** It opens by itself when you load the game, and the **Start page** button at the top of the panel brings it back at any time. It tells the story of the 2027 fuel wars, lists the rules (one run, one save, no restarts, no shops) and has the **Start the run** button for a new run. With a saved run, a **Welcome back** box shows how far your save is from Pine Gap, the fuel you saved, the km you've driven and where the save is, with **Go to your save**. It also warns you if the VR revolver mod isn't installed. Your save still works.

## Build 5 · 1 Nov 2026

- **You can now siphon fuel from other cars.** Stop within about 10 m of any car, parked, crashed or in traffic, and the **Road** tab shows a **Siphon fuel** button with how far away the car is. Press it and fuel moves from their tank into yours at 1 litre a second. A bold **Siphoning** box near the top of the screen shows the litres taken so far, their tank emptying and yours filling. Its border turns red and it says "Hoons nearby!" when Hoons are close. It stops by itself when their tank is dry, your tank is full or you drive off, and you keep everything you took. Press **Stop** in the box, or **Stop siphoning** on the Road tab, to stop it yourself. In VR, a small pip on your wrist blinks green while fuel flows. Your save still works.

## Build 4 · 1 Nov 2026

- **The run now starts at Yorkeys Crossing, outside Port Augusta,** where the Stuart Highway heads north into the desert, instead of Port Wakefield. Pine Gap is about 1,230 km away by road. A save from the old start still works and carries on from where you saved it.
- **You now start in the Tanker starter truck.** When you reach the start, your vehicle is swapped for a white D15 longbed dually pickup with the 4.1 litre six, a 5-speed manual, a bullbar and a big fuel tank in the bed. The **Road** tab says "Fetching your truck" for a moment while it arrives. **Go to your save** puts you back in the same truck with the fuel you saved. Your save still works.

## Build 2 · 31 Oct 2026

- **Desert rocks can now be switched off.** The **Road** tab has a **Desert rocks** On / Off switch. Off clears BeamNG.Earth's scattered rocks, so the open desert becomes a fast, clear surface for chases, a bit like a salt-lake speed run. Rocks are on by default, Tanker remembers your choice, and they come back as soon as you switch them on or turn Tanker off. If you have already turned rocks off in BeamNG.Earth's own settings, they stay off. Your save still works.

## Build 1 · 31 Oct 2026

- **The first playable skeleton of Tanker.** Press **Start the run** to be teleported to Port Wakefield, at the edge of the desert north of Adelaide, and head north for Pine Gap. There is one run and one save, with no restarts.
- **The HUD strip** shows the threat light, the fuel in your tank, six ammo pips for the revolver and the road distance left to Pine Gap. Click it to open the **Road** and **Rig** tabs. The ammo pips stay dark until the revolver gets ammo in a later update.
- **Save here** keeps where you are and how much fuel you have. You can't save with Hoons nearby. Next time you play, **Go to your save** takes you back and puts your tank back as it was.
- **In VR, a wrist HUD** on your left hand shows the same strip, drawn from simple shapes like the revolver so it doesn't lag.
- **The game is now called Tanker** (it was Mad Merick while it was being planned). The app in your UI list, the download and the settings folder all use the new name.
- **Every update is now a download.** Each new version appears on the Releases page as `tanker.zip`. Copy it into your BeamNG `mods` folder without extracting it, replacing the old one.

