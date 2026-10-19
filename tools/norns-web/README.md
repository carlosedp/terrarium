# norns-web

Runs a norns script's real Lua in a browser: the screen, encoders, keys, clocks, metros and
PARAMS are emulated, and engine commands go to a Web Audio stand-in for the SuperCollider
engine. It's for checking behavior and the scene while working on a script, not for its sound.

It knows nothing about terrarium. Any script that sticks to `screen`, `params`, `clock`, `metro`
and engine commands should run; midi, grid, arc, softcut, crow and poll are silent stubs.

## Run it while working

```
node tools/norns-web/serve.mjs [script dir, default .] [port, default 8800]
```

Open http://localhost:8800/. Files are read fresh on every load: edit a `.lua` file, reload.
Keys: A/S/D for K1/K2/K3; Y/H, U/J, I/K turn E1, E2, E3 up/down. Keys can be held (S + U is K2 + E2), and the
encoders take the scroll wheel and dragging.

## Publish a static copy

```
node tools/norns-web/build.mjs [--cdn] [script dir] [out dir, default tools/norns-web/dist]
```

The out dir holds the page, the runtime, `files.json` (every `.lua` file of the script) and the
script's engine stand-ins. Without `--cdn` it also copies the vendored wasmoon; with it, the page
loads the same pinned version from jsdelivr.

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

Without a stand-in, engine commands are only logged (tick "engine commands" under the log).

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
- **PARAMS:** no PSETs (`params:read`/`write` do nothing), no MIDI mapping, no clock params.
- **Audio:** only what the stand-in sketches.
- `norns.system_cmd` is logged, not run.
