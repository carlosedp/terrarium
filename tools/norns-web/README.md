# norns-web

Runs a norns script's real Lua in a browser: the screen, encoders, keys, clocks, metros and
PARAMS are emulated, and engine commands go to a Web Audio stand-in for the SuperCollider
engine. How close the sound is depends on the stand-in: a sketch, or the real DSP code compiled
to WebAssembly.

It knows nothing about any one script. Any script that sticks to `screen`, `params`, `clock`,
`metro` and engine commands should run; midi, grid, arc, softcut, crow and poll are silent stubs.
It started inside [terrarium](https://github.com/carlosedp/terrarium), which is still the most
complete example (an engine stand-in on real mi-UGens, a plugin that uses this page as its face).

## Add it to a script

A script carries norns-web in its own repo, at `tools/norns-web/`, as a git subtree: no
submodules to init, and CI and a fresh clone just work. The paths below assume that folder
(`manifest.mjs` skips `tools/`, so norns-web's own files never show up as the script's).

```
git subtree add  --prefix=tools/norns-web https://github.com/carlosedp/norns-web main --squash
git subtree pull --prefix=tools/norns-web https://github.com/carlosedp/norns-web main --squash   # update
git subtree push --prefix=tools/norns-web https://github.com/carlosedp/norns-web <branch>        # send a fix back
```

Changes made in a script's copy stay generic (nothing about that script) and go back here with
`subtree push`, then out to the other scripts with `subtree pull`.

`git subtree` needs a GNU `dirname`. With uutils coreutils (Ubuntu 25.10 and later),
`dirname tools/norns-web/.` gives `tools`, and subtree then works on all of `tools/`. Put the GNU
one first on the PATH for these commands (`/usr/bin/gnudirname`, or Homebrew's `gdirname`, linked
as `dirname` in a folder of its own).

## Try it

```
node serve.mjs test/hello      # then open http://localhost:8800/
lua test/headless.lua [script dir] # boots a script on lib/norns.lua, no browser; fails on Lua errors
```

`test/hello` is the smallest script it runs (under `test/`, which the norns script menu skips, as it skips `lib/`). CI runs the headless check on Lua 5.4 and 5.3
and a static build of the example (`.github/workflows/test.yml`).

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

Two shells, under the screen: **shield** (the default: compact, K1 top left and E1 top right, K2 K3 E2 E3
along the bottom) or **norns**, the case: **aluminium** (the default) or **black**, and the screen's
color: **yellow** (the default: the amber some shields have) or **white**. They're remembered by the
browser, and the URL can set them: `?shell=norns&finish=black&screen=white`. On a phone the page is touch-first: drag the encoders up and down,
hold keys with one finger while tapping another.

## Publish a static copy

```
node tools/norns-web/build.mjs [--cdn] [script dir] [out dir, default tools/norns-web/dist]
```

The out dir holds the page, the runtime, `files.json` (every `.lua` file of the script) and the
script's engine stand-ins, with their folders of files. Without `--cdn` it also copies the vendored wasmoon; with it, the page
loads the same pinned version from jsdelivr.

## The page's text

The page puts the device up front, standing on the ground under a night sky, with Start sound, the
script's actions, How to play (also <kbd>?</kbd>), Full screen and a Look menu (shell, case and screen
color); full screen shows just the device, under its own night sky (its buttons stack down the
right side on a phone turned sideways, and a phone held upright is asked to turn). PARAMS, PSETs, the log and the
REPL are in "Under the hood", a drawer at the bottom of the window: opening it scrolls the device into
view above it, the handle on its top edge resizes it, and a badge on its bar counts errors while it's
closed (open or closed and its height are remembered).

An optional `norns-web.json` next to the script fills in the rest:

```json
{ "title": "…", "subtitle": "…", "about": "…", "more": "…",
  "icon": "doc/icon.svg", "touch_icon": "doc/icon.png",
  "actions": [{ "label": "Shuffle", "icon": "shuffle", "param": "randomize", "title": "…" }],
  "controls": [{ "keys": "E1", "does": "…" }, { "keys": "hold K1 + K3", "does": "…" }],
  "gallery_intro": "…", "gallery": [{ "img": "doc/a.png", "title": "…", "text": "…", "alt": "…" }],
  "install": ";install https://github.com/…", "links": [{ "label": "…", "url": "…" }], "footer": "…" }
```

- `title`, `subtitle`, `about`: the heading and intro over the device. `icon` is the tab's icon and
  sits beside the title; `touch_icon` is a PNG for phones' home screens (paths in the script).
- `actions`: buttons beside Start sound, each stepping a param by `delta` (default 1), like
  pressing a trigger in PARAMS. `icon` is optional (`shuffle`); in full screen they're icon-only
  when they have one.
- `controls`: what each control does, for How to play and its dialog (without it, a generic note
  about knobs and keys). The keyboard and touch help is added after it.
- `gallery`: pictures of what's in the script, each with a name and a line; `build.mjs` copies them.
- `downloads`: the script elsewhere (a plugin, an app), a section near the end: `{ title, intro,
  items: [{ title, text, url, label }], links: [{ label, url }] }`, a card and a button per
  package. Hidden in a plugin's face.
- `more`, `install`, `links`: the About section (the install line has a copy button); `footer`:
  credits or license text.

## In a plugin (hosted)

A plugin that runs the script itself (its own Lua, its own sound) can use this page as its face,
in JUCE's `WebBrowserComponent`. The page notices `window.__JUCE__` and starts neither Lua nor
Web Audio: the encoders, keys, PARAMS, presets, the REPL and the page's actions call the plugin's
native functions, and the screen and the log arrive as its events. The web page's own parts
(Start sound, the gallery, how to play, about) are hidden; the device, its controls and the
drawer stay.

| page → plugin (native functions)      | does                                                        |
| ------------------------------------- | ----------------------------------------------------------- |
| `enc(n, d)`, `key(n, z)`              | the encoders and keys                                       |
| `params()`                            | PARAMS as `norns_web.params_json()` gives it (a JSON string) |
| `param_delta(index or id, d)`         | a step of one param                                         |
| `repl(code)`, `pset(action, slot)`    | the REPL; save / load a PSET                                |
| `param_map(index)`, `param_maps()`    | optional: bind a param to one of the plugin's host-automation slots (or free it), and `{ index: slot }`; with both, PARAMS gets a **map** button per param |
| `set_extra_height(px)`                | optional: the drawer opened (or closed, 0): the plugin grows its window taller by it, so the device stays in view |
| `set_extra_width(px)`                 | optional, instead: the drawer opens at the right (a tab along the edge, PARAMS above the log) and the plugin grows its window wider by it |
| `prefs_set(key, value)`               | optional: the page's own settings (the look, the drawer) go to the plugin, to keep with the project; it passes them back in as `initialisationData` `prefs` (an object) |
| `set_option(id, on)`                  | optional: the plugin's options, passed in as `initialisationData` `options` (`[{ id, label, value }]`), become checkboxes in Look |

Hosted, the page never scrolls: the device and its buttons zoom down to fit the window's height.

`fonts/` has the page's three fonts (OFL), for a host that may be offline: swap the Google Fonts
links for `fonts/fonts.css` (terrarium's plugin does it when it stages the page).

A host can give the script MIDI out: `js_bridge.midi_ports()` returns the port names
`midi.vports` shows (up to 16), and a device from `midi.connect(port)` sends its `note_on`,
`note_off`, `cc`, `pitchbend`, `program_change` and `send` through `js_bridge.midi_send(port,
bytes...)`. Without them every port is "none" and sending is silent (as in the browser).

`lib/norns.lua` also has `norns_web.set_running(on)`, for a host with a transport: stopped, the
clock routines wait (the metros, and so the screen, go on); started again, a routine waiting on
`clock.sync` lands on its next beat.

| plugin → page (events) | carries                                                        |
| ---------------------- | -------------------------------------------------------------- |
| `frame`                | the screen: 128×64 letters, `"A"` (off) to `"P"` (full), as `norns_web.tick()` returns it |
| `log`                  | `{ text, kind }`, kind `"print"` or `"error"`                  |

The plugin serves the page's files itself (`index.html`, `norns-web.js`, and a `files.json`
with no Lua files and the script's `norns-web.json` as `about`). terrarium's plugin
(`plugin/juce/` in its repo) is an example.

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

- `lib/norns.lua` is the norns API in Lua (in `lib/` because norns lists every other `.lua`
  file in a script's folder as a script of its own): the screen draws into a 128×64
  framebuffer, params keep their values and actions, clocks are coroutines and metros are timers, all driven by
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

## License

norns-web is free software under the GNU GPL v3.0 (see [LICENSE](LICENSE)). © 2026 Voltage
Foundry Modular. [wasmoon](https://github.com/ceifa/wasmoon) (MIT) is vendored in `vendor/`, and
the fonts in `fonts/` are under the SIL Open Font License (their `OFL-*.txt`).
