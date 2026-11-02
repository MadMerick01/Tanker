# Tanker

A hardcore post-apocalyptic trucking game for BeamNG.drive, set in the real Australian outback on BeamNG.Earth. An AI has switched off the world's water, power and internet, and fuel is the only thing worth anything. Start in a ute with a fuel tank in the bed at Kulgera Roadhouse, take fuel from Hoons in muscle cars and from other tankers, and make it about 270 km north to Pine Gap for the codes that can stop the AI.

See [docs/DESIGN.md](docs/DESIGN.md) for the design.

## What works so far

The first skeleton. There are no Hoons or tankers yet.

- **Start the run** teleports you to Kulgera Roadhouse on the Stuart Highway, just over the Northern Territory border, puts you in the Tanker starter truck with about 200 km of fuel and starts your one and only run.
- The **HUD strip** shows the threat light, your fuel, the revolver's rounds and the road distance left to Pine Gap. Click it to open the **Road** and **Rig** tabs.
- **Save here** saves where you are and how much fuel you have. You can't save with Hoons nearby. Next session, **Go to your save** takes you back and puts your tank back as it was.
- In VR, a **wrist HUD** on your left hand shows the same strip, drawn from flat shapes like the revolver.

## Install

You need BeamNG.drive with [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth), and for the revolver and the wrist HUD, MadMerick's [BeamNG VR Controller Poses](https://github.com/MadMerick01/BeamngVRcontrollerPoses).

1. Download [tanker.zip](../../releases/latest/download/tanker.zip) from the newest release. Every merge to main publishes a new build on the [Releases](../../releases) page, and [CHANGELOG.md](CHANGELOG.md) says what changed.
2. Put `tanker.zip` in your BeamNG `mods` folder without extracting it, replacing any older one.
3. In game, add the **Tanker** app to your UI.

There is one run and one save. To start over while testing, delete `settings/tanker/save-a.json` and `save-b.json` in your BeamNG user folder. `config.example.json` shows the settings you can put in `settings/tanker/config.json`, such as a different start.

## Tests

To build the ZIP yourself, run `python tools/package.py` (it lands in `dist/tanker.zip`).


`python tests/run.py` runs the Lua tests (with LuaJIT, or `pip install -r tests/requirements.txt` for Lupa), the HUD tests in Node.js and the packaging tests.
