# terrarium: design notes

What terrarium is meant to be, and the decisions behind it. Written after the first design
round (October 2026), which happened in a browser prototype ([prototype.html](prototype.html))
before any norns code existed.

## The idea

An all-in-one norns instrument that feels like a "modular for everyone": a few swappable
modules with great-sounding macro controls, mainly generative (Marbles-like), built on the
Mutable Instruments mi-UGens. What makes it a norns instrument is the screen: like the
scripts that draw falling leaves or antennas, the patch *is* a scene.

- **The patch is a landscape.** Four parts, each one piece of the scene and one stage of the sound:
  brain (weather) → voice (ground) → color (light and water) → air (sky).
- **Fixed signal path, swappable modules.** Free patching on a 128×64 screen with 3 encoders
  would be miserable, so the routing is pre-wired, like a semi-modular synth. You swap what sits
  in each slot.
- **No parameters on screen.** Turning a macro changes the scene; the scene *is* the readout.
  Holding K1 shows a peek view for when you're lost. Everything is also in PARAMS for presets and MIDI.
- **Every note is a place.** Where an event lands across the screen sets its pitch, so a melody is
  something you can see.
- **Macros, not parameters.** Each module has two macros (E2, E3) that move several mi-UGen
  parameters along hand-picked ranges. The good sound comes from those curated ranges and a few
  deliberate couplings between parts (doc/SOUND.md).

## Modules

| Part | Module | mi-UGen | In the scene | Macros |
| --- | --- | --- | --- | --- |
| brain | rain | — (clocked) | drops fall on the norns clock and play where they land; puddles mark the phrase | rate, change |
| brain | lightning | — (random) | random strikes, sometimes doubled; scorch marks hold the phrase | rate, change |
| voice | meadow | Plaits | each note blooms a flower in swaying grass | harmonics, timbre |
| voice | crystals | Plaits 6-op FM | glass spires glint and throw sparks | ratio, index |
| color | pond | Rings | ripples spread from each note | structure, damping |
| color | fog | Ripples | fog thickens as the filter closes; the whole scene dims | clarity, shimmer |
| air | clouds | Clouds | clouds made of grains drift | density, size |
| air | fireflies | Beads | each grain is a firefly with a trail | density, glow |
| air | mountains | MiVerb | ridges grow with the room; notes echo off the far ridge | size, echo |

K3 is a gesture per part: new phrase (brain), strike (voice, color), freeze (air).
E1 picks a part, and the others dim for a moment so it's clear which one you're steering.

## Decisions and why

- **Antenna became crystals.** An antenna voice looked too much like dronecaster. Crystals fit FM
  (glassy, metallic) and turned out to be a real MI engine (Plaits' 6-op banks), not a stand-in.
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
- **nb voices get their own slot later ("visitors")** rather than hiding behind crystals. nb voices
  each define their own parameters, so the scene can only promise E2 → the voice's generic
  `modulate`, E3 → note length.

## Open questions

- Default Plaits engine for the meadow (modal is safe, string machine is lush).
- Voice → Rings as audio (one instrument) or trigger-only (cleaner).
- Which DX bank and patches make the best crystals.
- CPU on norns with 2 Plaits + Rings + Beads; decides voice count.
- Screen cost: up to ~1,400 rects in a frame with fog or a lightning flash.
- Grid: phrase as a row of keys to add/remove notes, key/scale picker, seasons shown as lit notes.
