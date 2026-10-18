# terrarium

A norns script: a landscape scene where four parts (brain = weather, voice = ground,
color = light/water, air = sky) are swappable modules driving Mutable Instruments
mi-UGens. Two macros per part, no numbers on screen. See README.md for the user view and
doc/DESIGN.md for why things are the way they are.

**Status:** v0.1, never run on a norns (the user's norns hadn't arrived when it was written).
The Lua side passes a headless smoke test; `lib/Engine_Terrarium.sc` has never been compiled.

## Commands

```
lua test/smoke.lua    # headless run against test/mock_norns.lua: all modules, gestures, settings, installer
```

Run it after every Lua change. It also asserts that params group counts match.

## Rules that are easy to break

- **Never write mi-UGens class names in the .sc file.** Look them up with `\MiPlaits.asClass`.
  A missing class makes sclang fail to compile, which breaks SuperCollider for *every* norns
  script, not just this one. The Lua installer handles missing mi-UGens instead.
- **Never pass `seed` to MiBeads.** Any input there counts as "patched" and stops density from
  generating grains.
- **norns runs Lua 5.3.** No `<const>`/`<close>` or other 5.4+ features (the dev machine has Lua 5.5).
- **`include()` is `dofile`, not `require`:** every call returns a fresh copy. Stateful modules
  (`lib/brain.lua`, `lib/canvas.lua`) are included only in `terrarium.lua`; modules reach them
  through the `sc` table passed to every module function.
- **Lua owns all macro-to-parameter mappings** (each module's `sound()` in `lib/scene/`); the
  engine only exposes raw parameters per slot. Keep `doc/SOUND.md` in sync when tuning.
- **Draw through `lib/canvas.lua`** (framebuffer, later layers can erase/dim earlier ones), then
  `cv.blit()`; native `screen.text` overlays go after the blit.
- **K1 is hold-only.** A quick K1 tap opens the norns system menu.
- A module that adds its own params must set `extra_count` (params group sizes are declared up front).
- A new color or air module needs a matching `terrarium_<id>` SynthDef in the engine.

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
- `doc/prototype.html`: the browser sketch (also published at https://claude.ai/artifact/SBCpfHzewFWLQyez8d2hfZ)
