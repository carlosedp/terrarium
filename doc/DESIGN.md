# terrarium: design notes

What terrarium is meant to be, and the decisions behind it. Written after the first design
round (October 2026), which happened in a browser prototype before any norns code existed. That
prototype was a hand-written JavaScript twin of the script; it's gone (see git history), replaced
by norns-web, which runs the real Lua in the browser.

## The idea

An all-in-one norns instrument that feels like a "modular for everyone": a few swappable
modules with great-sounding macro controls, mainly generative (Marbles-like), built on the
Mutable Instruments mi-UGens. What makes it a norns instrument is the screen: like the
scripts inspired by real-world visuals, the patch _is_ a scene.

- **The patch is a landscape.** Five parts, each one piece of the scene and one stage of the sound:
  brain (weather) → voice (ground) → color (light and water) → air (sky), with the drone (a bed
  under it all, aurora or roots) playing into the air.
- **Fixed signal path, swappable modules.** Free patching on a 128×64 screen with 3 encoders
  would be miserable, so the routing is pre-wired, like a semi-modular synth. You swap what sits
  in each slot.
- **No parameters on screen, except names on touch.** Turning a macro changes the scene; the scene
  _is_ the readout. Touching an encoder briefly names what it moved, then fades. Holding K1 shows a
  peek view for when you're lost. Everything is also in PARAMS for presets and MIDI.
- **Every note is a place.** Where an event lands across the screen sets its pitch, so a melody is
  something you can see.
- **Macros, not parameters.** Each module has two macros (E2, E3) that move several mi-UGen
  parameters along hand-picked ranges. The good sound comes from those curated ranges and a few
  deliberate couplings between parts (doc/SOUND.md).

## Modules

| Part  | Module    | mi-UGen        | In the scene                                                                       | Macros                |
| ----- | --------- | -------------- | ---------------------------------------------------------------------------------- | --------------------- |
| brain | rain      | — (clocked)    | drops fall on the norns clock and play where they land; puddles mark the phrase    | rate, change          |
| brain | lightning | — (random)     | random strikes, sometimes doubled, light up the land; scorch marks hold the phrase | rate, change          |
| voice | meadow    | Plaits         | each note blooms a flower in swaying grass; each Plaits engine grows its own kind  | harmonics, timbre     |
| voice | crystals  | Plaits 6-op FM | glass spires glint and throw sparks                                                | ratio, index          |
| voice | reeds     | Rings          | each note plucks a reed and it vibrates like a string                              | structure, brightness |
| color | pond      | Rings          | ripples spread from each note; the water mirrors the scene and ripples bend it     | structure, damping    |
| color | fog       | Ripples        | fog thickens as the filter closes; the whole scene dims (soil under the ground)    | clarity, shimmer      |
| air   | clouds    | Clouds         | clouds made of grains drift                                                        | density, size         |
| air   | fireflies | Beads          | each grain is a firefly with a trail                                               | density, glow         |
| air   | mountains | MiVerb         | ridges grow with the room; notes echo off the far ridge                            | size, echo            |
| drone | aurora    | 2x Plaits      | curtains of light across the top of the sky; they flare when a season turns        | glow, motion          |
| drone | roots     | Elements       | roots under the ground with light flowing down them                                | breath, depth         |

The glass is drawn over everything (`lib/glass.lua`): rounded jar corners and a glint, rain
condensing on it (more beads at faster rates, some run down), and frost growing in from the
corners while the air is frozen. The weather's wind (rain's change, or a wilder storm) also
pushes the clouds and fireflies, so the sky and the grass move together.

Hold K2 and turn E2 to pick the module's variant: the Plaits engine for the meadow (each grows
its own flower), the DX bank for crystals, the Rings model for reeds and the pond, the mode for clouds. A K2
tap still swaps the module (on release, so the hold can't swap it).

K3 is a gesture per part: new phrase (brain), strike (voice, color), freeze (air), hush/rise (drone).
E1 picks a part, and the others dim for a moment so it's clear which one you're steering.

## Decisions and why

- **Stars became lightning; rain became clocked.** Rain reads as steady and lightning as random,
  so each brain module looks like what it does. Raindrops were shrunk to 2-pixel specks so they
  don't read as falling bombs.
- **Clouds is Clouds, Beads got its own scene (fireflies).** Both are granular, so they needed
  distinct pictures.
- **The key never changes by itself unless you ask.** An early version picked random keys; that
  felt like interruptions. Key, scale, range and phrase length are settings (K1 + E2/E3, PARAMS,
  grid later).
- **Turing Machine phrase instead of a déjà vu toggle.** The brain keeps a register of notes and
  rests. `change` (E3) is the chance per step that a note is replaced (75%) or dropped (25%), or a
  rest filled, always within the key. At 0 the phrase loops forever, which replaced the toggle.
  The phrase is drawn as marks on the ground so you can watch it evolve.
- **Seasons (opt-in) instead of random keys.** At a phrase boundary every 8/4/2 phrases, the key
  moves to a close neighbor: a one-note swap (dorian → minor, C → G) or a pentatonic gaining or
  losing two notes. It can't stray more than 3 notes from home (the key you set) and heads back
  toward home 40% of the time. Named "Seasons" because it turns gradually and comes back around.
- **Pitch is a fixed semitone per place, snapped to the scale.** Each place maps to a semitone,
  and a note steps to the nearest scale tone only when its semitone isn't in the scale. That's
  what makes Seasons smooth: shared notes stay where they are. (Mapping by scale degree reshuffled
  every note on a key change.)
- **Rain follows the norns clock** so terrarium can play with other scripts and gear; each drop is
  spawned one step ahead so it visibly lands on its note.
- **mi-UGens are installed by the script, not bundled.** The script checks for them and offers an
  installer (from the norns-mi-UGens releases) instead of failing, and the engine never names
  mi-UGens classes directly, so a missing install can't break SuperCollider for other scripts.
- **The visual details all carry information (October 2026).** Glass, condensation, water,
  the lightning flash, frost and shared wind were tried in a lab copy of the prototype with
  toggles, then all kept. Each one shows something (rain rate, which color module, the filter,
  freeze, change), so the scene still is the readout. The flash is applied before the color
  layer so fog muffles it; applied after, it lit the fog's dither into a bright checkerboard.
  Pond rings became flat and stay in the water: the old tall ellipses covered the meadow.
- **Climate modulates like CV, around the macro (October 2026).** External mods and LFOs that
  write a param fight the encoder: turn E2 and the LFO overwrites it. Instead the macro you set
  stays the center and the climate adds to it, the way CV adds to a knob on a eurorack module.
  Everything reads macros through `sc.m()`, so sound and scene both follow; `sc.base()` is the
  setting. A chaotic attractor instead of LFOs because its outputs are linked (the parts drift
  together, like weather) and never quite repeat. Four attractors with different characters,
  named on screen for how they move (fronts, gusts, tides, squalls; not "seasons", which is
  taken), one drift setting scaled per attractor so slow/medium/fast feel alike. Off by default, like
  seasons. The params stay plain, so norns mods and MIDI still work on top.
- **One gesture for variants (October 2026).** The Plaits engine, DX bank, Rings model and Clouds
  mode used to be PARAMS-only. Hold K2 + E2 reaches all of them the same way, keeps harmonics and
  timbre on E2/E3 for every engine, and leaves K3 free for its gesture. The meadow's flora list
  grew to twelve melodic Plaits engines.
- **Crystals stays FM; Rings gets its own voice, reeds (October 2026).** Rings as a voice was
  tempting for crystals, but the 6-op FM banks are a real, distinct glassy sound. Reeds plays
  Rings with its internal exciter; most Rings models are strings, so they're drawn as reeds that
  vibrate when plucked. Appended after crystals so saved PSETs keep their voice.
- **Breath: silence as part of the music (October 2026).** Ambient lives on the space between
  sounds, but density only changed when you turned rate or change. The breath setting brings calm
  spells: at a phrase end, sometimes (gentle 20%, deep 35%) the weather calms for one to three
  phrases and notes rest with a chance up to 55% / 85%, fading in and out over seconds. Resting
  notes stay in the phrase, so it comes back intact; their marks dim meanwhile. With the climate
  on, its first output deepens the calm too, so the calm and the gusts line up.
- **A day for the longest arc (October 2026).** Seasons turn the key over phrases and the climate
  drifts the timbre over minutes, but nothing changed over an hour, which an ambient piece needs.
  The day is an offset on the macros like the climate (your settings stay the center): night
  slows, darkens, opens the air and brings the drone forward. "clock" follows the local time so
  the terrarium's night is yours. The sky shows it with a sun, a moon and stars, and a glow at
  dawn and dusk.
- **A drone as a fifth part (October 2026).** Everything else is struck (flowers, plucks, strikes),
  so between notes the piece could fall apart. A sustained bed on the root and fifth holds it
  together, follows the key and glides when a season turns. It got its own part rather than a
  setting so it has modules, macros and a variant like everything else. It plays into the air
  (shared space) but skips color: Rings fed a constant drone would ring all the time. Aurora
  draws behind the sky; roots draws after the water so the pond doesn't hide it. A third module,
  none, is for anyone who doesn't want a drone (`lib/scene/none.lua`, reusable for any part).
- **Mappings are data, tuned live (October 2026).** Tuning by ear means many small changes, and
  reloading the script for each is slow. Each module's macro -> parameter mapping is now a table
  (`map`) that `tune()` changes from maiden while it plays, printing the table to paste back. The
  same mechanism maps MI parameters no macro used to reach (Clouds reverb, Beads time). A levels
  group balances the slots.
- **A patina over everything, for glue (October 2026).** Generative ambient often sounds like one
  recording because everything shares a medium. A tape stage at the very end (wow, flutter,
  crackle, hiss, rolled-off top, gentle drive) gives terrarium that: a setting, not an air
  module, so it combines with clouds, fireflies or mountains. First called "tape", renamed
  patina to sit with seasons, climate, day and breath (and it's the wear of the jar's glass as
  much as of the sound). Five steps from off to ancient, faint by default; its saturation is
  gain-compensated so switching steps doesn't change the level. Dust on the glass shows it.
- **The drone answers the weather (October 2026).** A drone that only sat there turned into a
  drone you notice, then one that annoys. Now each note makes it give way a little (a sidechain,
  up to −6 dB) and lights it up for a moment (a strike much more than a drop), and it swells
  back in the gaps: busy weather keeps it low, calm lets it fill the jar. Complementary to the
  voice rather than under it. Computed in Lua and sent as `duck` and `lift`, so the norns does
  the same as the browser.
- **The weather moves the drone, slowly (October 2026).** Inspired by Marbles patches, where
  the slower outputs share the melody's randomness but change less: at a phrase end the drone's
  upper voice may move to the consonant interval the phrase leans on. The chance grows with the
  brain's change (20% of phrase ends at 0, 80% at 1; at first it was none at 0, and the drone
  barely moved), at most once a phrase, gliding; the root never moves, so the bed keeps the key.
  Roots, a single voice, stays on the root.
- **A new terrarium on K1 + K3 (October 2026).** For exploring: every part gets a random module,
  variety and knobs (kept between 0.15 and 0.85), and the settings change too: key, scale, range,
  length, seasons, climate, drift, breath. Never visitors, which need an outside voice, or none,
  which is silence, and never the day: it's about time (clock ties it to your night), not
  texture, so a random jump would read as a glitch. The light sweeps along the ground and the new
  key shows.
- **Names on touch (October 2026).** The scene shows _how much_ a macro moved but not _what_ it
  is, and the norns has no labels by its knobs, so a first-time player was guessing (the peek view
  answered, but only if you knew to hold K1). Now E2/E3 show the macro's name and a bar (with the
  climate's tick) on their side of the bottom strip, where the encoders are; E1 shows the part,
  its module and both macro names, for as long as the other parts stay dimmed (2.5 s). No numbers,
  and it fades, so nothing rests on screen.
- **The browser runs the real Lua (October 2026).** The prototype was a JavaScript copy of the
  script, and every scene change had to be written twice; the copy drifted twice in one session.
  `tools/norns-web` runs the actual Lua in the browser instead (wasmoon, Lua compiled to
  WebAssembly, a third of native speed; a pure-JS Lua was 28× slower). It's generic, so other
  scripts can use it. The prototype's "scene details" toggles were dropped: the details stay on.
- **The browser plays the real mi-UGens (October 2026).** The browser engine was a Web Audio
  sketch (FM pairs, biquads, a convolver): fine for checking the routing, useless for judging a
  sound or tuning a map. norns-mi-UGens now builds mi-UGens as WebAssembly: the SuperCollider
  wrappers compile unchanged against a small stand-in for SC's plugin header, and run in an
  AudioWorklet the way scsynth runs them (64-sample blocks, input rates, `t_trig`, `.lag`).
  `lib/Engine_Terrarium.js` rebuilds each SynthDef from those nodes, so the browser and the norns
  run the same DSP code with the same parameters; what differs is the glue (Web Audio gains and
  panners for `Pan2`, `Out` and the fades) and the tape. The sketch is gone rather than kept as a
  fallback: one more copy of every SynthDef to keep in step. Browsers without AudioWorklet or
  wasm SIMD (Safari before 16.4) get no sound, like a norns without mi-UGens.
- **nb voices are visitors, a fourth voice module (October 2026).** nb voices each define their
  own parameters, so the scene can only promise E2 → the voice's generic `modulate`, E3 → note
  length; the voice itself is the variant (hold K2 + E2). They're drawn as creatures from outside
  the jar (ants, beetles, moths), because their sound is outside it too: nb doesn't route audio,
  so color and air can't process them. An earlier note assumed an insert on the main output
  would carry them through; nb has no such thing, so they stay dry.

## Open questions

- Default Plaits engine for the meadow (modal is safe, string machine is lush).
- Voice → Rings as audio (one instrument) or trigger-only (cleaner).
- Which DX bank and patches make the best crystals.
- CPU on norns with 2 Plaits + Rings + Beads; decides voice count.
- Screen cost: up to ~1,550 rects in a frame with fog or a lightning flash; the pond reflection
  reads ~1,150 pixels per frame.
- Grid: phrase as a row of keys to add/remove notes, key/scale picker, seasons shown as lit notes.
