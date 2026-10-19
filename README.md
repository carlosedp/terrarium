# terrarium

A small world of Mutable Instruments for [monome norns](https://monome.org/docs/norns/).

The patch is a landscape. Five parts each draw one piece of the scene and play one part of
the sound. Swap a module and that piece of the scene changes; turn a macro and the scene moves
with the sound. The screen shows no numbers.

| Part | In the scene | Modules |
| --- | --- | --- |
| **brain** | the weather: when notes happen and which ones | rain (clocked to the norns clock), lightning (random) |
| **voice** | the ground: what plays | meadow (Plaits), crystals (Plaits 6-op FM), reeds (Rings), visitors (any [nb](https://github.com/sixolet/nb) voice) |
| **color** | light and water: what shapes it | pond (Rings), fog (Ripples) |
| **air** | the sky: where it rings out | clouds (Clouds), fireflies (Beads), mountains (MiVerb) |
| **drone** | the bed under it all, on the key's root and fifth | aurora (Plaits), roots (Elements), none |

The whole scene sits behind the terrarium's glass. Rain beads up on it, and freezing the air
frosts it over.

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

[nb](https://github.com/sixolet/nb) comes in as a git submodule (`lib/nb`). Cloning by hand,
use `git clone --recurse-submodules`.

## Controls

| Control | Does |
| --- | --- |
| E1 | choose a part (the others dim for a moment) |
| E2, E3 | that part's two macros (their names show for a moment while you turn) |
| K2 | swap the part's module |
| hold K2 + E2 | pick the module's variant: Plaits engine (meadow), DX bank (crystals), Rings model (reeds, pond), nb voice (visitors), Clouds mode |
| K3 | gesture: new phrase (brain), strike (voice, color), freeze (air), hush / rise (drone) |
| hold K1 | peek at all parts; while held, E2 picks a setting and E3 changes it |

**Climate** (a setting, off by default) lets a chaotic attractor slowly move the macros: fronts
(Lorenz), gusts (Rössler), tides (Thomas) or squalls (Chua). It moves them, the way CV moves a module's knobs: the macro you set is the center and
the climate pushes it around it. Each macro has a cv amount in PARAMS; the peek view shows
where each macro is right now and the attractor's path.

**Day** (a setting, off by default) adds the longest arc: a day and night of 20 minutes, an hour,
or following the norns' clock. Night slows the weather, darkens the voice, opens up the air and
brings the drone forward; the sky shows a sun by day and a moon and stars by night.

**Breath** (a setting, off by default) adds silence: now and then the weather calms for a phrase
or three, notes rest (the phrase keeps them) and their marks dim, then it breathes in again.

A quick tap of K1 still opens the norns menu. Settings (key, scale, range, length, seasons,
climate, drift, day, breath),
every macro, and each module's fixed options (Plaits engine, DX bank, Rings model, Clouds
mode) are also in PARAMS, so they save with PSETs and can be MIDI-mapped.

## How it's built

```
terrarium.lua            script: parts, params, controls, drawing, the brain clock
lib/Engine_Terrarium.sc  engine: 2 Plaits voices -> color slot -> air slot -> out
lib/brain.lua            phrase, pitch mapping, seasons
lib/canvas.lua           128x64 framebuffer, blitted to the screen as merged runs
lib/glass.lua            the glass over the scene: rim, condensation, frost
lib/climate.lua          chaotic attractors that modulate the macros
lib/nb/                  the nb library (git submodule), for visitors
lib/scene/*.lua          one file per module: its drawing, macros and sound mapping
lib/installer.lua        mi-UGens check and installer
doc/SOUND.md             macro -> mi-UGen parameter map (the tuning reference)
lib/Engine_Terrarium.js  Web Audio stand-in for the engine, for norns-web (norns ignores it)
tools/norns-web/         runs the script's real Lua in a browser
test/                    mocked norns runtime and a smoke test
```

The Lua side owns every macro-to-parameter mapping (each module's `sound()` function, written
from [doc/SOUND.md](doc/SOUND.md)); the engine only exposes raw parameters per slot. Tuning the
sound means editing those functions.

A module is one file under `lib/scene/` with `macros`, `draw`, `update`, and either
`wait`/`spawn`/`wind` (brain; `flash` optional) or `sound`/`on_note` (voice, color, air). Add it to `LAYERS` in `terrarium.lua`; a new
color or air module also needs a `terrarium_<id>` SynthDef in the engine.

## Development

`make` lists the common tasks: `make web` (the script in a browser), `make test`, `make deploy`
(copy to a norns over ssh; `NORNS=we@<ip>` if `norns.local` doesn't resolve).

Run the smoke test on a computer (Lua 5.3+):

```
lua test/smoke.lua
```

It loads the script against `test/mock_norns.lua`, plays every module, gesture and setting,
exercises the installer path, and prints screen calls per frame. It checks the Lua logic only:
no sound, no real screen.

To see and play the real script in a browser, run [norns-web](tools/norns-web/README.md):

```
node tools/norns-web/serve.mjs     # then open http://localhost:8800/
```

It runs this Lua as is (screen, controls, clocks, PARAMS), with rough Web Audio stand-ins for the
engine (`lib/Engine_Terrarium.js`), not the MI engines. A published copy is at
https://claude.ai/artifact/SBCpfHzewFWLQyez8d2hfZ.

## Tuning

Each module's macro → parameter mapping is a table that `tune()` changes live from the maiden
REPL, printing the result to paste back; PARAMS > levels balances the slots. See
[doc/SOUND.md](doc/SOUND.md#tuning-on-the-norns) for the syntax and a first-night checklist.

## To do on hardware

- [ ] engine loads and every slot sounds; fix anything SuperCollider complains about
- [ ] CPU with the heaviest combination (2 Plaits + Rings + Beads); pick voice count from it
- [ ] screen frame time (the smoke test averages about 730 screen calls per frame and peaks around 1,550 with fog or a lightning flash; the pond's reflection is the main extra cost)
- [ ] tune ranges and curves in each module's `sound()` by ear (doc/SOUND.md lists open questions)
- [ ] visitors with real nb voices (Emplaitress, MIDI, Just Friends); they play dry, outside color and air
- [ ] grid: phrase editing, key/scale picker

## License

GPL-3.0, see [LICENSE](LICENSE). The DSP is Émilie Gillet's
[Mutable Instruments code](https://github.com/pichenettes/eurorack), via Volker Böhm's
[mi-UGens](https://github.com/v7b1/mi-UGens).
