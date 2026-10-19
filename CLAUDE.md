# terrarium

A norns script: a landscape scene where five parts (brain = weather, voice = ground,
color = light/water, air = sky, drone = the bed under it all) are swappable modules driving
Mutable Instruments mi-UGens. Two macros per part, no numbers on screen. See README.md for the user view and
doc/DESIGN.md for why things are the way they are.

**Status:** v0.1, never run on a norns (the user's norns hadn't arrived when it was written).
The Lua side passes a headless smoke test; `lib/Engine_Terrarium.sc` has never been compiled.

## Commands

`make` lists these too (`make test`, `make web`, `make build`, `make deploy`).

```
lua test/smoke.lua                    # headless run against test/mock_norns.lua: all modules, gestures, settings, installer
node tools/norns-web/serve.mjs        # the real script in a browser at http://localhost:8800/
node tools/norns-web/build.mjs --cdn  # static copy in tools/norns-web/dist/, to publish
```

Run the smoke test after every Lua change. It also asserts that params group counts match.

To update the published page: build with `--cdn`, then publish `tools/norns-web/dist/index.html` to
https://claude.ai/artifact/SBCpfHzewFWLQyez8d2hfZ with `norns-web.js`, `norns.lua`, `files.json` and
`script/lib/Engine_Terrarium.js` as files.

## Rules that are easy to break

- **Never write mi-UGens class names in the .sc file.** Look them up with `\MiPlaits.asClass`.
  A missing class makes sclang fail to compile, which breaks SuperCollider for *every* norns
  script, not just this one. The Lua installer handles missing mi-UGens instead.
- **Never pass `seed` to MiBeads.** Any input there counts as "patched" and stops density from
  generating grains.
- **norns runs Lua 5.3.** No `<const>`/`<close>` or other 5.4+ features (the dev machine has Lua 5.5).
- **`include()` is `dofile`, not `require`:** every call returns a fresh copy. Stateful modules
  (`lib/brain.lua`, `lib/canvas.lua`, `lib/glass.lua`, `lib/climate.lua`, `lib/daylight.lua`, `lib/breath.lua`) are included only in `terrarium.lua`; modules reach them
  through the `sc` table passed to every module function.
- **Lua owns all macro-to-parameter mappings** (each module's `map` table, evaluated by
  `sc.mapped()`, plus its `sound()` for option params and conditional couplings); the
  engine only exposes raw parameters per slot. Keep `doc/SOUND.md` in sync when tuning.
- **Draw through `lib/canvas.lua`** (framebuffer, later layers can erase/dim earlier ones), then
  `cv.blit()`; native `screen.text` overlays go after the blit.
- **K1 is hold-only.** A quick K1 tap opens the norns system menu.
- `lib/scene/none.lua` is an empty module (no macros, silent, draws nothing); enc() skips
  macros a module doesn't have.
- A module with a variant (an option param picked with hold K2 + E2) sets `variant` to that param's id.
- A module that adds its own params must set `extra_count` (params group sizes are declared up front).
- A new color, air or drone module needs a matching `terrarium_<id>` SynthDef in the engine. A voice
  module sets `voice` to the engine voice it plays (`plaits`, `rings`: `terrarium_voice_<kind>`;
  `none` when it plays elsewhere, like visitors).
- Add new modules and option entries at the end of their lists, so saved PSETs keep their choices.
- **Read macros with `sc.m(i, k)`** (the value as it plays, climate and day included), never with
  `params:get` directly; `sc.base(i, k)` is the value as set. Each macro also has a `<id>_cv` param.
- A voice module can define `play(sc, note, vel)` to play notes itself instead of the engine
  (visitors does, through nb). `lib/nb` is a git submodule (sixolet/nb); don't edit it.
- **Engine command changes go in three places:** `lib/Engine_Terrarium.sc`, the Lua that sends
  them, and `lib/Engine_Terrarium.js` (the browser stand-in), or norns-web logs them as unknown.
- `tools/norns-web` must stay generic: nothing terrarium-specific in it. The browser runs Lua 5.4,
  so it won't catch 5.4-only code that would fail on norns (5.3).
- A brain module must define `wind(sc)` (the sky drifts with it); `flash()` is optional.

## Related repo

`~/norns-mi-UGens` (github.com/carlosedp/norns-mi-UGens, not pushed yet as of 2026-10-18) builds
mi-UGens for norns: `./build.sh --pr 24` cross-compiles in a Debian Buster armhf container
(upstream v7b1/mi-UGens + PR 24 = MiBeads), `./deploy.sh` installs over ssh. Its GitHub release
asset `mi-UGens-norns.tar.gz` (fixed name, latest release) is what `lib/installer.lua` downloads;
the tarball carries `install.sh`, which moves older mi-UGens installs aside (duplicate classes
break sclang).

## Environment

WSL2 (Ubuntu) on Windows. The Windows home `C:\Users\carlosedp` is `~/home` in WSL; use that
form for Windows paths. `gh`, `podman`, `lua`/`luac` are available.

## Design references

- `doc/DESIGN.md`: decisions and their reasons (read before changing behavior)
- `doc/SOUND.md`: macro -> mi-UGen parameter map, ranges, couplings, open tuning questions
- `tools/norns-web/README.md`: running the script in a browser (generic, not terrarium-specific)
