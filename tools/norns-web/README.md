# norns-web

Runs a norns script's real Lua in a browser: the screen, encoders, keys, clocks, metros and
PARAMS are emulated, and engine commands go to a Web Audio stand-in for the SuperCollider
engine. How close the sound is depends on the stand-in: a sketch, or the real DSP code compiled
to WebAssembly.

It knows nothing about terrarium. Any script that sticks to `screen`, `params`, `clock`, `metro`
and engine commands should run; midi, grid, arc, softcut, crow and poll are silent stubs.

## Run it while working

```
node tools/norns-web/serve.mjs [script dir, default .] [port, default 8800]
```

Open http://localhost:8800/. The page reloads by itself when you save a script file (`.lua`,
`.js`, `.json`) or norns-web's own, and keeps your params across the reload (press Start sound
again: browsers only start audio on a click). Changes to `serve.mjs` or `manifest.mjs` need a
restart.
Keys: A/S/D for K1/K2/K3; Y/H, U/J, I/K turn E1, E2, E3 up/down. Keys can be held (S + U is K2 + E2), and the
encoders take the scroll wheel and dragging.

## The device

Two shells, under the screen: **shield** (the default: compact, K1 and E1 top right, K2 K3 E2 E3
along the bottom) or **norns**, and the screen's color: **white** or **yellow** (the amber some
shields have). They're remembered by the browser, and the URL can set them:
`?shell=norns&screen=yellow`. On a phone the page is touch-first: drag the encoders up and down,
hold keys with one finger while tapping another.

## Publish a static copy

```
node tools/norns-web/build.mjs [--cdn] [script dir] [out dir, default tools/norns-web/dist]
```

The out dir holds the page, the runtime, `files.json` (every `.lua` file of the script) and the
script's engine stand-ins, with their folders of files. Without `--cdn` it also copies the vendored wasmoon; with it, the page
loads the same pinned version from jsdelivr.

## The page's text

An optional `norns-web.json` next to the script gives the page a title, subtitle and intro, and a
footer with links, the maiden install line (with a copy button) and credits or license text:

```json
{ "title": "…", "subtitle": "…", "about": "…", "install": ";install https://github.com/…",
  "links": [{ "label": "…", "url": "…" }], "footer": "…" }
```

## The engine stand-in

When the script sets `engine.name = "X"`, the page loads `lib/Engine_X.js` from the script (norns
ignores that file). It registers a factory that returns an object with one method per engine
command, plus optional `start(ctx, out)` (called when the page's sound is switched on, with an
`AudioContext` and an output node) and `os_capture(cmd)` (answers `util.os_capture`, for scripts
that look for files on norns):

```js
NornsWeb.engines.X = () => ({
  start(ctx, out) { /* build the Web Audio graph */ },
  note(pitch, accent) { /* ... */ },
});
```

A stand-in that needs files of its own (an AudioWorklet module, WebAssembly) keeps them in a
folder next to it, `lib/Engine_X/`; `build.mjs` copies it along. The stand-in finds it from its
own URL: `document.currentScript.src.replace(/\.js$/, "/")`, read when the script loads.

Without a stand-in, engine commands are only logged (tick "engine commands" under the log).

## nb voices

Scripts that use [nb](https://github.com/sixolet/nb) get one built-in voice, "web synth" (a soft
triangle; `modulate` opens its filter), since the browser has no nb mods or MIDI devices.

## REPL

The field under the log runs Lua in the script, like the maiden REPL: an expression prints its
value (`params:get("x")`), a statement just runs. Up and down recall history.

## How it works

- `norns.lua` is the norns API in Lua: the screen draws into a 128×64 framebuffer, params keep
  their values and actions, clocks are coroutines and metros are timers, all driven by
  `norns_web.tick(t)`. The page calls it once per animation frame and draws the framebuffer when
  the script has called `screen.update()`.
- `norns-web.js` loads the VM, mounts the script's files under `/code/<name>/`, and wires the
  canvas, controls, PARAMS panel, log and engine stand-in.
- The VM is [wasmoon](https://github.com/ceifa/wasmoon) 1.16.0 (MIT), vendored in `vendor/`: Lua
  compiled to WebAssembly, about a third of native speed. A pure-JS Lua (Fengari) was ~28× slower
  than native, too slow for a 15 fps script.

## Differences from a norns

- **Lua 5.4, not 5.3.** A 5.4-only feature works here and fails on the device.
- **Screen:** no anti-aliasing, line widths or fonts; text is a 3×5 bitmap font in capitals, so
  `screen.text_extents` is only approximately right.
- **PARAMS:** PSETs live in the browser's storage (8 slots next to the panel, or `params:write(n)` /
  `params:read(n)` from the REPL), not in files; no MIDI mapping, no clock params.
- **Audio:** only what the stand-in plays.
- `norns.system_cmd` is logged, not run.
