# Developing terrarium

How the script is put together, how to test it without a norns, how to tune it, and what is
still to do. For playing it, see the [manual](MANUAL.md); for why things are the
way they are, [DESIGN.md](DESIGN.md).

## How it's built

```
terrarium.lua            script: parts, params, controls, drawing, the brain clock
lib/Engine_Terrarium.sc  engine: 2 Plaits voices -> color slot -> air slot -> out
lib/brain.lua            phrase, pitch mapping, seasons
lib/canvas.lua           128x64 framebuffer, blitted to the screen as merged runs
lib/glass.lua            the glass over the scene: rim, condensation, frost
lib/climate.lua          chaotic attractors that modulate the macros
lib/scene/*.lua          one file per module: its drawing, macros and sound mapping
lib/installer.lua        mi-UGens check and installer
doc/SOUND.md             macro -> mi-UGen parameter map (the tuning reference)
lib/Engine_Terrarium.js  the engine for norns-web: the same graphs, in Web Audio (norns ignores it)
lib/Engine_Terrarium/    the mi-UGens it plays, built as WebAssembly (`make mi-wasm`)
plugin/                  the VST3 / AU plugin (see plugin/README.md)
tools/norns-web/         runs the script's real Lua in a browser
test/                    mocked norns runtime, a smoke test and a soak test
```

The Lua side owns every macro-to-parameter mapping (each module's `sound()` function, written
from [SOUND.md](SOUND.md)); the engine only exposes raw parameters per slot. Tuning the
sound means editing those functions.

On screen the parts are weather, soil, water, air and hum; in the code (param ids, `tune()`,
module files) they keep their working names: brain, voice, color, air and drone.

A module is one file under `lib/scene/` with `macros`, `draw`, `update`, and either
`wait`/`spawn`/`wind` (brain; `flash` optional) or `sound`/`on_note` (voice, color, air). Add it
to `LAYERS` in `terrarium.lua`; a new color or air module also needs a `terrarium_<id>` SynthDef
in the engine (and in `lib/Engine_Terrarium.js` and `plugin/core/Engine.cpp`).

## Testing

`make` lists the common tasks: `make web` (the script in a browser), `make test`, `make deploy`
(copy to a norns over ssh; `NORNS=we@<ip>` if `norns.local` doesn't resolve).

Run the smoke test on a computer (Lua 5.3+):

```
lua test/smoke.lua
```

It loads the script against `test/mock_norns.lua`, plays every module, gesture and setting,
exercises the installer path, and prints screen calls per frame. It checks the Lua logic only:
no sound, no real screen.

`lua test/soak.lua [hours]` (`make soak`) runs the jar for hours of jar time (8 by default, about
1.5 minutes each) with climate, a day, seasons and breath on and a new terrarium every 20
minutes, and fails on what only shows up over hours: growing memory or lists, values out of range
or NaN, silence, a hum stuck hushed.

## In a browser

To see and play the real script in a browser, run [norns-web](../tools/norns-web/README.md) (its
own repo, [carlosedp/norns-web](https://github.com/carlosedp/norns-web), kept here as a git
subtree; `make norns-web-pull` updates it):

```
node tools/norns-web/serve.mjs     # then open http://localhost:8800/
```

It runs this Lua as is (screen, controls, clocks, PARAMS). The engine is `lib/Engine_Terrarium.js`:
each SynthDef rebuilt in Web Audio around the same mi-UGens, compiled to WebAssembly by
[norns-mi-UGens](https://github.com/carlosedp/norns-mi-UGens) (`./build.sh --wasm`) and kept in
`lib/Engine_Terrarium/` (`make mi-wasm` rebuilds them). Every push to main publishes it to
<https://terrarium.glassgarden.cc/> (`.github/workflows/pages.yml`).

## Tuning

Each module's macro → parameter mapping is a table that `tune()` changes live from the maiden
REPL, printing the result to paste back; PARAMS > levels balances the slots. See
[SOUND.md](SOUND.md#tuning-on-the-norns) for the syntax and a first-night checklist.

## To do

- [x] engine loads and plays on a norns
- [ ] CPU with the heaviest combination (2 Plaits + Rings + Beads); pick voice count from it
- [ ] screen frame time (the smoke test averages about 730 screen calls per frame and peaks around 1,550 with fog or a lightning flash; the pond's reflection is the main extra cost)
- [ ] tune ranges and curves in each module's `sound()` by ear (SOUND.md lists open questions)
- [ ] visitors with a real synth: MIDI out, its audio back into the input (and the monitor level turned down)
- [ ] grid: phrase editing, key/scale picker

## Wallpapers and pictures

`make art` renders the README banner, the social preview and the wallpapers in `doc/art/` from
the running script; `make manual-images` the manual's pictures.
