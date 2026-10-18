# terrarium

A small world of Mutable Instruments for [monome norns](https://monome.org/docs/norns/).

The patch is a landscape. Four parts each draw one piece of the scene and play one part of
the sound. Swap a module and that piece of the scene changes; turn a macro and the scene moves
with the sound. The screen shows no numbers.

| Part | In the scene | Modules |
| --- | --- | --- |
| **brain** | the weather: when notes happen and which ones | rain (clocked to the norns clock), lightning (random) |
| **voice** | the ground: what plays | meadow (Plaits), crystals (Plaits 6-op FM) |
| **color** | light and water: what shapes it | pond (Rings), fog (Ripples) |
| **air** | the sky: where it rings out | clouds (Clouds), fireflies (Beads), mountains (MiVerb) |

Every note is a place: where it lands across the screen sets its pitch in the current key
and scale. The brain keeps a Turing Machine-style phrase, and each note leaves a mark on the
ground. **Change** sets how often notes are replaced, dropped to a rest or added back.
**Seasons** can let the key drift between close neighbors and find its way home.

> **Status: v0.1, untested on hardware.** The Lua side runs headless against a mocked norns
> (see [Development](#development)); the engine and the sound mappings still need a real norns.

## Requirements

- norns (or norns shield / fates)
- [mi-UGens](https://github.com/carlosedp/norns-mi-UGens) built for norns. If they're missing,
  terrarium shows an installer instead of the scene: **K3** downloads and installs the latest
  build, **K2** installs a `mi-UGens-norns*.tar.gz` you copied into `dust/`. Restart norns after.
  Fireflies needs a build that includes MiBeads; without it, that module is hidden.

## Install

From the maiden REPL:

```
;install https://github.com/carlosedp/terrarium
```

## Controls

| Control | Does |
| --- | --- |
| E1 | choose a part (the others dim for a moment) |
| E2, E3 | that part's two macros |
| K2 | swap the part's module |
| K3 | gesture: new phrase (brain), strike (voice, color), freeze (air) |
| hold K1 | peek at all parts; while held, E2 picks a setting and E3 changes it |

A quick tap of K1 still opens the norns menu. Settings (key, scale, range, length, seasons),
every macro, and each module's fixed options (Plaits engine, DX bank, Rings model, Clouds
mode) are also in PARAMS, so they save with PSETs and can be MIDI-mapped.

## How it's built

```
terrarium.lua            script: parts, params, controls, drawing, the brain clock
lib/Engine_Terrarium.sc  engine: 2 Plaits voices -> color slot -> air slot -> out
lib/brain.lua            phrase, pitch mapping, seasons
lib/canvas.lua           128x64 framebuffer, blitted to the screen as merged runs
lib/scene/*.lua          one file per module: its drawing, macros and sound mapping
lib/installer.lua        mi-UGens check and installer
doc/SOUND.md             macro -> mi-UGen parameter map (the tuning reference)
doc/prototype.html       the browser sketch the interaction was designed in
test/                    mocked norns runtime and a smoke test
```

The Lua side owns every macro-to-parameter mapping (each module's `sound()` function, written
from [doc/SOUND.md](doc/SOUND.md)); the engine only exposes raw parameters per slot. Tuning the
sound means editing those functions.

A module is one file under `lib/scene/` with `macros`, `draw`, `update`, and either `wait`/`spawn`
(brain) or `sound`/`on_note` (voice, color, air). Add it to `LAYERS` in `terrarium.lua`; a new
color or air module also needs a `terrarium_<id>` SynthDef in the engine.

## Development

Run the smoke test on a computer (Lua 5.3+):

```
lua test/smoke.lua
```

It loads the script against `test/mock_norns.lua`, plays every module, gesture and setting,
exercises the installer path, and prints screen calls per frame. It checks the Lua logic only:
no sound, no real screen.

Open `doc/prototype.html` in a browser for the interactive sketch (Web Audio stand-ins, not
the MI engines).

## To do on hardware

- [ ] engine loads and every slot sounds; fix anything SuperCollider complains about
- [ ] CPU with the heaviest combination (2 Plaits + Rings + Beads); pick voice count from it
- [ ] screen frame time (the smoke test peaks around 1,400 rects in a frame with fog or a lightning flash)
- [ ] tune ranges and curves in each module's `sound()` by ear (doc/SOUND.md lists open questions)
- [ ] nb voices as a third voice option ("visitors")
- [ ] grid: phrase editing, key/scale picker

## License

GPL-3.0, see [LICENSE](LICENSE). The DSP is Émilie Gillet's
[Mutable Instruments code](https://github.com/pichenettes/eurorack), via Volker Böhm's
[mi-UGens](https://github.com/v7b1/mi-UGens).
