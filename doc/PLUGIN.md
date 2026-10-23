# terrarium as a plugin (plan)

terrarium as a VST3 / AU instrument (and a standalone app), built with JUCE: the same jar, the
same Lua, the same Mutable Instruments code, playing in a DAW. This is the plan and where it
stands; nothing here ships yet.

## Why native, not the web page in a webview

A JUCE `WebBrowserComponent` could load norns-web as it is, but its sound would come from the
webview's Web Audio, straight to the system output: not through `processBlock`, so the DAW
couldn't record it, process it or clock it, and webviews throttle audio when hidden. The page
can be the plugin's UI; the sound has to be native.

## The pieces, and where each comes from

| Part        | Today                                                  | In the plugin                                                                       |
| ----------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| mi-UGens    | armhf for norns, wasm for the browser                  | native libraries from norns-mi-UGens (`./build.sh --lib`, `native/mi_ugens.hpp`)    |
| SynthDefs   | `Engine_Terrarium.sc`, rebuilt in `Engine_Terrarium.js` | a C++ port of `Engine_Terrarium.js`: the mi-UGens plus a dozen plain blocks          |
| Lua         | Lua 5.3 on norns; norns-web's `norns.lua` in a browser  | Lua 5.3 embedded, with `norns.lua`: terrarium's Lua runs unchanged                  |
| clock       | the norns clock                                        | the host's tempo and position (rain on the DAW's grid)                              |
| UI          | 128×64 OLED, E1–E3, K1–K3                              | norns-web's page in a `WebBrowserComponent`: frames in, encoders and keys out       |
| params      | norns PARAMS, PSETs                                    | host automation (below); the state saved with the project                           |
| visitors    | MIDI out over USB, the synth back through the input    | MIDI out to another track, that track back in through a sidechain input (below)     |

## Visitors in a DAW

On norns, visitors send each note over MIDI to a synth beside the norns, and its sound comes back
through the audio input, where water and air shape it like any voice. A DAW is made for this:

- **MIDI out:** the plugin produces MIDI (a VST3 event output, an AU MIDI output). Route it to any
  instrument track.
- **Audio in:** a stereo sidechain input bus. Send that instrument's track (or anything: a
  guitar, a loop) into it, and it's terrarium's input: let in by the weather, shaped by water
  and air.
- The MIDI device variant (hold K2 + E2) becomes "plugin MIDI out" or "none" (input only); the
  channel stays.

Hosts differ: Bitwig, Reaper and Cubase route plugin MIDI out freely; Ableton Live doesn't route
MIDI out of a VST3 instrument (a Max for Live device or an IAC/loopMIDI port works around it).
Sidechain inputs work in all of them. Check it in each before promising it.

## Automation: a drawer, like Under the hood

A VST3 declares its parameters when it loads; terrarium's change with the modules. A short list,
so a DAW's stays readable:

1. **Fixed:** the ten macros, "weather 1" .. "hum 2", meaning whatever the loaded module says and
   renamed with it; and "stop with the DAW's transport".
2. **Map slots:** eight generic "map 1…8" parameters. In the drawer, the page's Under the hood
   with a "map" button on every param, the user binds any terrarium param (a module, the key, a
   cv amount) to a slot; the DAW automates the slot, like norns' MIDI mapping.
3. **State:** the PSET dump `norns.lua` already writes, plus the slot bindings, saved in the
   project.

## Threads

Lua runs on a timer on the message thread, never on the audio thread. Engine commands go to the
audio thread through a lock-free queue; notes are stamped with the host's sample position so rain
lands on the grid, not on the UI timer's jitter. Screen frames go to the UI after each tick.

## Phases

1. **mi-UGens native libraries** (norns-mi-UGens, branch `native-libs`): one shared library per
   UGen for Linux, macOS (universal) and Windows, the same C API as wasm, a header-only C++ loader
   and a render test; CI builds and tests each platform and adds them to releases. *Done:
   norns-mi-UGens v1.2.0; the same sound on all three platforms.*
2. **Plugin skeleton:** JUCE (VST3, AU, standalone), Lua + `norns.lua` embedded, the host clock,
   the native mi-UGens loaded from the bundle, MiPlaits only: rain on meadow, on the DAW's grid.
   This proves the hard parts: Lua threading, tempo sync, the native engine. *In progress on the
   `plugin` branch ([plugin/](../plugin/README.md)): the core (Lua, engine, timing, no JUCE) and
   `terrarium-render` work, notes land within a 64-sample block of the host's 16ths at any tempo,
   start and block size; the VST3 and standalone build and pass pluginval (strictness 5).*
3. **The engine:** the rest of `Engine_Terrarium.js` in C++, every SynthDef; the sidechain input
   and MIDI out for visitors. *The engine is done on the `plugin` branch: every SynthDef of the
   .sc (voices, pond, fog, clouds, fireflies, mountains, aurora, roots, the tape), module swaps
   built off the audio thread, tested by rendering every module and 57 swaps in 30 s (clean
   under AddressSanitizer). Visitors' MIDI out and sidechain input are next.*
4. **UI and automation:** norns-web's page as the editor, the drawer with map slots, state in the
   project. *Pulled ahead of phase 3, on the `plugin` branch: the page is the face
   (norns-web's hosted mode), the ten macros and 8 map slots named after what they follow, both
   ways, the map bindings saved with the project.*

Later: notarizing the macOS build. (The engine runs at 48 kHz at any host rate, with a resampler
at the edges; the heaviest jar takes about 10% of a core.)
