# terrarium, the plugin

terrarium as a VST3 / AU instrument and a standalone app: the same Lua, the same Mutable
Instruments code, in a DAW. The plan and where it stands are in [doc/PLUGIN.md](../doc/PLUGIN.md).
**Phase 2:** the script runs and follows the host's tempo and beat; only Plaits plays (meadow,
crystals), the other parts are silent for now.

## What's here

```
core/        terrarium in-process, no JUCE: the script's Lua (LuaHost), the engine
             (Engine: the SynthDefs, on the native mi-UGens), and the time between them (Terrarium)
render/      terrarium-render: the core offline, to a WAV and the last screen; tests it anywhere
juce/        the plugin (PluginProcessor, PluginEditor), the resources each bundle carries
             (stage.cmake), and terrarium_host_test, which loads the built plugin like a DAW
```

The script isn't copied or ported: each bundle carries `terrarium.lua` and `lib/` as they are,
norns-web's `norns.lua` as the norns API, Lua 5.3 (what norns runs), and the native mi-UGens from
[norns-mi-UGens](https://github.com/carlosedp/norns-mi-UGens/blob/main/native/README.md)' release.

## Build

```
cmake -S plugin -B build/plugin -DCMAKE_BUILD_TYPE=Release
cmake --build build/plugin --config Release
```

CMake ≥ 3.22 and a C++17 compiler. It downloads JUCE 8.0.4, Lua 5.3.6 and the mi-UGens (pinned
by hash); `-DMI_UGENS_DIR=<mi-UGens-native/>` uses a local build of them instead. On Linux, JUCE
needs `libasound2-dev libfreetype-dev libfontconfig1-dev libx11-dev libxrandr-dev
libxinerama-dev libxcursor-dev libxext-dev libgl1-mesa-dev`. `-DTERRARIUM_PLUGIN=OFF` builds only
the core and `terrarium-render`, without JUCE.

The plugins land in `build/plugin/juce/terrarium_plugin_artefacts/Release/` (`VST3/`, `AU/` on
macOS, `Standalone/`); copy the `.vst3` (or `.component`) to your plugin folder. The CI workflow
(`.github/workflows/plugin.yml`) builds all three platforms and keeps them as artifacts.

## Test

```
build/plugin/terrarium-render --script . --seconds 20 --bpm 93 --start 3.37 --out jar.wav
build/plugin/juce/terrarium_host_test_artefacts/Release/terrarium_host_test \
    build/plugin/juce/terrarium_plugin_artefacts/Release/VST3/terrarium.vst3
```

`terrarium-render` boots the script, plays it as a host would (offline), and writes a WAV and the
last screen (`.pgm`). It reports how far each note is from the host's 16ths: within a 64-sample
block, as scsynth schedules. `--lua 'params:set("voice_kind", 2)'` runs code in the script first,
like maiden's REPL; `--stopped` lets Lua's clock run free; the rest of its options are at the top
of `render/main.cpp`.

`terrarium_host_test` loads the built plugin as a DAW does, plays it in real time with the
transport running, saves and restores its state, and checks it made sound. CI also runs
[pluginval](https://github.com/Tracktion/pluginval) on it at strictness 5.

## How it fits together

- **Threads.** The audio thread owns time. A 60 Hz timer on the message thread ticks Lua's
  clocks up to the audio's time plus 0.1 s. Each engine command is stamped with the exact Lua
  time it was made (norns.lua runs a clock routine at its own wake time) and waits in a
  lock-free queue until the audio gets there, so notes land on their 64-sample block however
  the message thread is doing. Lua never runs on the audio thread, except when the host renders
  offline (a bounce), where nothing else would keep up.
- **The host's beat.** With the transport playing, Lua's tempo is the host's, and when their beat
  phases drift apart (start, loop, seek, tempo change) Lua's time jumps forward to the host's.
  Only forward: a waiting clock routine would sit out a jump back.
- **State.** The params, saved with the project as a PSET (what `params:write` stores).
- **The editor**, for now: the screen and the encoders and keys (drag or scroll the encoders,
  hold the keys; A S D and Y/H, U/J, I/K on the keyboard, as in norns-web). Phase 4 puts
  norns-web's page here, with a drawer to map params to the host's automation.

## Known gaps (phase 2)

- Only `voice_plaits` plays: Rings, the color, air and drone slots and the tape are next.
- A key or encoder that plays a note (K3's gestures) is heard 0.1 s late: its command is
  stamped with Lua's time, which runs ahead.
- Swapping a module creates its synths on the audio thread (they allocate).
- No host automation, MIDI out or sidechain yet (visitors), see doc/PLUGIN.md.
- macOS: copying the resources into the bundle after JUCE builds it may need re-signing.
