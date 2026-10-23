# terrarium, the plugin

For playing it, see [the plugin's manual](../doc/PLUGIN-MANUAL.md). This is for building it.

terrarium as a VST3 / AU instrument and a standalone app: the same Lua, the same Mutable
Instruments code, in a DAW. The plan and where it stands are in [doc/PLUGIN.md](../doc/PLUGIN.md).
**Phases 2 and 3:** the script runs and follows the host's tempo and beat, and every part of
the jar plays: the whole engine, as `lib/Engine_Terrarium.sc` has it, visitors included.

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

`bash plugin/tests.sh build/plugin/terrarium-render` runs all of the core's checks (the beat, PARAMS,
module swaps, sample rates, the transport, visitors' MIDI): CI's `plugin-core.yml` runs it on every
push and PR that touches the plugin or the Lua (no JUCE, a couple of minutes), and `plugin.yml`
again before each release, with the full build on every platform, from `v*` tags.

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
- **48 kHz inside.** The engine and Lua's clock run at 48 kHz whatever the host's rate, as a norns
  does: Plaits and Rings change their envelopes and damping with the rate, so they'd sound
  different at 88.2 or 96 kHz. The output, and the input visitors hear, go through a 64-tap
  windowed-sinc resampler (`core/Resampler.h`; flat to 18 kHz, aliasing 71 dB down, 0.7 ms);
  at 48 kHz it's skipped.
- **The transport.** "stop with the DAW's transport" (a host parameter, off by default, also in the
  face's Look menu): on, the weather stops while the transport is stopped (the clock routines
  wait; tails ring out, the screen goes on) and comes back on the beat; off, the rain keeps
  falling on its own, as on a norns.
- **The host's beat.** With the transport playing, Lua's tempo is the host's, and when their beat
  phases drift apart (start, loop, seek, tempo change) Lua's time jumps forward to the host's.
  Only forward: a waiting clock routine would sit out a jump back.
- **The engine** (`core/Engine.cpp`) is `Engine_Terrarium.sc` in C++, SynthDef by SynthDef:
  the same graphs, the same lags, the same routing (voice into color, drone beside it, air to the
  output, the tape on it), on the native mi-UGens and a few plain SuperCollider UGens
  (`core/Ugens.h`: LFTri, LFNoise1/2, DelayC, Dust, Decay2, Butterworth filters, noise). A module
  swap builds its synth on the message thread, from a mirror of what the slots were sent, and
  hands it over with the command; the old one fades out and goes back to be freed there. The
  audio thread allocates nothing.
- **State.** The params, saved with the project as a PSET (what `params:write` stores).
- **Visitors** send their notes out over MIDI and let the plugin's input in, as on a norns
  (a synth over USB, its sound back through the input). Pick the port with hold K2 + E2 on the
  soil (or `visitors midi out` in PARAMS):
  - **1: DAW (plugin MIDI out)**: the plugin's own MIDI output, for a host that routes an
    instrument's MIDI to another track (Live: MIDI From the track, then the plugin by name;
    Reason, Bitwig, Reaper, Cubase; not Logic);
  - **2 and on: the system's MIDI outputs**, which the plugin opens itself: a hardware synth, or a
    virtual port another track listens to (loopMIDI on Windows, the IAC Driver on macOS). Works in
    any host. The list is read when the plugin loads.

  The sound comes back through the plugin's side chain, "Visitors" (an aux input: Logic,
  Reason and Live offer it as the instrument's side chain): route the synth's track, or an
  input with the hardware synth, into it. Each note opens it for a moment, and visitors' first
  macro lets some through between notes.
- **The face's settings** (the shell, the screen's color, the drawer) are kept with the project, and
  its fonts come in the bundle (a DAW may be offline). The plugin's icon is the jar
  (`doc/img/icon-touch.svg`).
- **The face** is norns-web's page, the same one the browser shows, in a WebView (WebView2 on
  Windows, WebKit on macOS and Linux), served from the bundle's `Resources/web/`. It sees it's
  hosted and runs no Lua or sound of its own: it calls the plugin (see "In a plugin" in
  `tools/norns-web/README.md`). The page never scrolls (the device zooms to fit), and the drawer is a tab at the right:
  opening it grows the window wider, so the device stays whole.
- **Host automation**, kept to a short list:
  - **10 macros**, "weather 1" to "hum 2": the two macros of whatever module lives in each part,
    renamed as it changes ("weather 1: rain rate", "soil 2: meadow timbre"). Swap the module and
    the same lane drives the new one's macro.
  - **8 map slots**, "map 1" to "map 8": the drawer's **map** button binds any of terrarium's
    PARAMS to a free one ("map 3: key"); the bindings save with the project.
  - **"stop with the DAW's transport"**.

  A slot and its param follow each other: the host's lane drives the param, and the plugin's own
  changes (the encoders, the face, the script) move the slot.

## Known gaps

- A key or encoder that plays a note (K3's gestures) is heard 0.1 s late: its command is
  stamped with Lua's time, which runs ahead.
- macOS: copying the resources into the bundle after JUCE builds it may need re-signing.
