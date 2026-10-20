# terrarium: sound map (draft)

How each macro on the screen drives the real mi-UGens. This is the starting point for
tuning: ranges and curves are first guesses, to be adjusted by ear on the real engines.
In the browser (norns-web), `lib/Engine_Terrarium.js` plays the same mi-UGens, built as
WebAssembly, in the same graphs; only the tape is an approximation (it's plain SuperCollider
UGens in the engine). Levels and timbres heard there are worth tuning from, then confirming on
the norns.

Conventions:

- Every macro is `0..1` on the encoder. A mapping like `harm 0.05→0.95` is the parameter's
  value at macro 0 and macro 1, linear unless a curve is given.
- **Fixed** values are per-module defaults.
- **Coupled** values come from _another_ slot. That's where the "it just sounds good" comes from,
  so keep the list short and deliberate.
- Signal flow: `brain → voice → color → air → out`. Visitors (nb voices) play outside it, dry.
- Parts go by their code names here (brain, voice, color, air, drone), as in param ids and
  `tune()`. On screen they're weather, soil, water, air and hum.

## Tuning on the norns

Each module's mapping is a table in its file (`map`), and the tables below are its source.
An entry is a number (fixed), `{ k, a, b [, curve] }` (this part's macro k from a to b, along
`macro ^ curve` if given) or `{ "part", k, a, b [, curve] }` (another part's macro: a coupling).
Option params, freeze and conditional couplings stay in each module's `sound()`.

`tune()` in the maiden REPL changes a map while the script runs and prints it to paste back:

```
tune()                                          -- list the modules
tune("clouds")                                  -- print clouds' map
tune("clouds", "rvb", 2, 0.1, 0.6)              -- E3 (size) also opens the reverb
tune("clouds", "rvb", 0.4)                      -- or fix it
tune("meadow", "decay", "brain", 1, 0.75, 0.4)  -- follow the brain's rate
tune("clouds", "rvb", nil)                      -- drop it (the synth's default applies)
```

Any control of the module's synth can be mapped, including ones no macro drives yet: Clouds
`lofi`, `spread`, `rvb`; Beads `time`, `pitch`, `shape`, `rvb`; MiVerb `hp`, `diff`; Rings `pos`.
A key the synth doesn't have does nothing. norns-web has the same REPL under its log.

**Levels:** PARAMS > levels has soil, water, air and hum levels in dB, sent to each slot's synth as
`vol` (it scales the slot's whole output). Balance on the device, then move the good values into
the code.

**First night with the norns,** in order:

1. The engine compiles (it never has). Fix whatever SuperCollider complains about.
2. Every slot sounds: each voice, color and air module, each variant.
3. Levels: a balanced default with the default modules, then the loudest and quietest pairings.
   The drone should sit about 6 dB under the notes (the browser plays the same UGens and
   gains, so check there first). Elements' output level is a guess (`amp` 0.3); check roots
   against aurora.
4. CPU with the heaviest pairing: reeds + pond (two Rings) + fireflies.
5. Tune each module's map by ear with `tune()`; paste the results back and update this file.

## Brain (no audio)

| Macro     | Drives                                                                                                                                                                                                                              | Notes                                         |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| E2 rate   | event rate: rain from a drop every 4 beats to 4 per beat, a drop a beat in the middle (clocked; 0.5→8 Hz at 120 BPM), lightning 0.3→6 Hz average (random, with occasional double strikes), snow a flake every 8 beats to one a beat | stepped (rain, snow), exponential (lightning) |
| E3 change | chance per step that the phrase mutates: `change²`; snow: also how far a flake drifts off the beat (it lands 1 → 1 + 1.5 × change × random steps after it leaves)                                                                   | 0 = loop forever                              |
| K3        | new phrase                                                                                                                                                                                                                          |                                               |
| Settings  | key, scale, range (1–3 octaves), length (4–16), seasons                                                                                                                                                                             | also in PARAMS; grid later                    |

Each note sends `pitch` (MIDI note), a velocity-like `accent` (0..1) and `pan`:

- **accent** = base × swell × hand × tilt × snow, clamped to 0..1 (`play()` in `terrarium.lua`):
  - base: 1 for a new note, 0.75 for one the phrase repeats (0.35 for a meltwater drip)
  - swell: per phrase, a random walk around 0.9 (±0.08 a phrase, pulled back 20%, kept in
    0.72..1), so some phrases come forward and some recede
  - hand: ±8% per note, and ×1.1 on the phrase's first step
  - tilt: 1 up to A3 (57), down to 0.7 at C6 (84), so the top of the range never pierces
  - snow: `1 − 0.35 × cover`
- **pan** = `(x / 127 × 2 − 1) × 0.6`: a note is heard from where it lands, left to right (it was
  a random ±0.3). The Plaits voices pan; the Rings voice is stereo by itself; visitors play
  through nb, which pans them its own way.

The engine maps accent to Plaits' `level` (`0.5 + 0.5 × accent`), which opens the LPG.

### Snow cover

Snow (`lib/scene/snow.lua`) keeps `sc.cover`, 0..1, the snow on the ground. Each landing flake
adds `0.018 × beats^0.6 × (1 − cover)`, where beats is the time between flakes (1 to 8), so
sparse flakes settle more each and a light snow still builds up. It thaws by `exp(−dt / 90 s)`,
times `4 ^ light` with the day on (×4 at noon, ÷4 at midnight). Under other weather it thaws over
~20 s (`exp(−dt / 20 s)`). Measured in the headless test at 120 BPM with no day, after four
minutes: 0.52 at the slowest rate, 0.64 at the default, 0.70 at the fastest (half of that within
the first 30 to 60 s). Higher at night, lower by day.

The cover muffles the voice. Each key in the voice module's `muffle` table is multiplied by
`1 − amount × cover` (cover rounded to 1/100, results to 1/200), and every note's velocity by
`1 − 0.35 × cover`:

| Voice    | `muffle` at full cover                |
| -------- | ------------------------------------- |
| meadow   | `timbre` 0.5, `decay` 0.45, `lpg` 0.7 |
| crystals | `timbre` 0.5, `decay` 0.45, `lpg` 0.7 |
| reeds    | `bright` 0.55, `damp` 0.4             |
| visitors | none (velocity only)                  |

When the cover shrinks (checked every 4 s), every 0.04 that melted becomes a drip: a note from
the phrase at velocity 0.35, skipped in a deep calm (breath). Over a 20-minute day that's about
twenty drips, most of them between dawn and noon.

### Cold

`sc.cold` follows the cover, slower (`cold += (cover − cold) × dt / 40 s`), so the cold builds
and lifts over a minute or two after the snow does. It never freezes anything: the air's freeze
(K3) stays the player's. The cold:

- stills the air: each key in the air module's `chill` table is multiplied by `1 − amount × cold`
  (same rounding as the muffle):

  | Air       | `chill` at full cold                |
  | --------- | ----------------------------------- |
  | clouds    | `pit_jitter` 0.7                    |
  | fireflies | `time_rnd` 0.6, `pitch_rnd` 0.6     |
  | mountains | none                                |

- slows the sky: clouds drift and flicker, and fireflies fly, at `1 − 0.5 × cold` speed
- rimes the glass's corners: the frost goes to `0.5 × cold` (the freeze takes it to 1)

## Voice

### Meadow → `MiPlaits`

| Macro        | Parameter | Range                                  |
| ------------ | --------- | -------------------------------------- |
| E2 harmonics | `harm`    | 0.05 → 0.95                            |
| E3 timbre    | `timbre`  | 0.1 → 0.9                              |
| E3 timbre    | `morph`   | 0.35 → 0.65 (follows timbre, narrower) |

- **Variant (hold K2 + E2):** `engine` from the "flora" list of melodic Plaits engines, each drawn
  as its own flower. Default **12 modal**. Numbers are MiPlaits' (0–15 classic, 16–23 newer):

  | Flora          | Engine | Flower     |
  | -------------- | ------ | ---------- |
  | modal          | 12     | bell       |
  | string         | 11     | seed spike |
  | additive       | 4      | petals     |
  | wavetable      | 5      | tulip      |
  | string machine | 22     | umbel      |
  | chords         | 6      | umbel      |
  | va filter      | 16     | tulip      |
  | phase dist     | 17     | star       |
  | wave terrain   | 21     | dandelion  |
  | waveshaper     | 1      | star       |
  | fm             | 2      | star       |
  | grain          | 3      | dandelion  |

  New entries go at the end so saved PSETs keep their flora. Left out: speech, swarm, noise,
  particle, the drums and chiptune; the 6-op banks (18–20) belong to crystals.

- **Fixed:** `lpg_colour` 0.5. Each note fires `trigger`, with `level` set from accent.
- **Coupled:** `decay` ← brain rate: fast rain plays shorter notes (0.75 at slow rate → 0.4 at fast).
- Polyphony: Plaits is mono per instance. Run 2–3 instances round-robin so notes ring over each other.
  Check the CPU cost on norns first.

### Crystals → `MiPlaits` 6-op FM (engines 18–20)

The glassy voice can be a real MI engine. No stand-in or nb voice needed.

| Macro    | Parameter                                       | Range                                     |
| -------- | ----------------------------------------------- | ----------------------------------------- |
| E2 ratio | `harm` (selects the 6-op patch within the bank) | 0 → 1, quantized to the bank's 32 patches |
| E3 index | `timbre` (modulation amount)                    | 0.15 → 0.85                               |
| E3 index | `morph` (envelope stretch)                      | 0.3 → 0.7                                 |

- **Fixed:** `engine` 18, 19 or 20 (which DX bank), chosen in PARAMS. Tune by ear for the most "glass".
- Ratio scrolling through patches is coarse. If it feels jumpy, keep `harm` fixed per variety
  and map E2 to `morph` instead.

### Reeds → `MiRings` as a voice (internal exciter)

Each note strikes Rings' internal exciter (`intern_exciter` 1, `poly` 2 so notes ring over each
other); no Plaits behind it. Most Rings models are strings, drawn as reeds that vibrate.

| Macro         | Parameter | Range      |
| ------------- | --------- | ---------- |
| E2 structure  | `struct`  | 0.15 → 0.9 |
| E3 brightness | `bright`  | 0.2 → 0.85 |

- **Variant (hold K2 + E2):** `model`, the same six as the pond.
- **Fixed:** `pos` 0.3.
- **Coupled:** `damp` ← brain rate: fast rain rings shorter (0.75 at slow rate → 0.45 at fast).
- **CPU:** reeds with the pond runs two Rings. Measure it; if it's too heavy, the pond could
  switch to its own exciter when reeds is the voice, or that pairing could be blocked.

### Visitors → any nb voice

nb voices (Emplaitress, Doubledecker, monami.e, MIDI, Just Friends…) play as **visitors**,
drawn as creatures that come in from outside: ants, beetles or moths, fixed per voice.

| Macro       | Parameter                                              | Range                            |
| ----------- | ------------------------------------------------------ | -------------------------------- |
| E2 modulate | `player:modulate(v)` (each voice decides what it does) | 0 → 1, sent only when it changes |
| E3 length   | note length                                            | 0.1 → 2 beats (exponential)      |

- **Variant (hold K2 + E2):** the nb voice (`visitors_voice`, from `nb:add_param`). "none" is silent.
- Each voice's own parameters are in PARAMS under "visitor voices" (`nb:add_player_params`).
- **Dry:** nb doesn't route audio. Each voice sounds wherever its mod, engine or device sends it,
  so color and air don't process visitors. The engine's voice slot is empty (`voice_kind none`).

## Color

### Pond → `MiRings`

The voice's audio goes into Rings' `in` (the voice excites the resonator), and each note sets `pit`
and fires `trig`.

| Macro        | Parameter                                     | Range                                                 |
| ------------ | --------------------------------------------- | ----------------------------------------------------- |
| E2 structure | `struct`                                      | 0.1 → 0.85 (above ~0.9 modal goes metallic and harsh) |
| E3 damping   | `damp` (inverted: more damping, shorter ring) | 0.92 → 0.35                                           |

- **Fixed:** `model` 0 modal, in PARAMS as "pond kind" (1 sympathetic strings and 5 string+reverb are
  good alternates). `poly` 2. `pos` 0.3.
- **Coupled:** `bright` ← the voice's timbre macro (0.35 → 0.7), so a brighter voice rings brighter.
- **Mix:** Rings has no dry/wet. Blend `voice × (1 − 0.5·structure) + rings` so more structure means more resonator.
- **K3:** strike, which triggers Rings directly with the internal exciter for one note.

### Fog → `MiRipples`

| Macro      | Parameter | Range                                                                |
| ---------- | --------- | -------------------------------------------------------------------- |
| E2 clarity | `cf`      | 0.12 → 0.92, exponential feel (most of the action in the lower half) |
| E3 shimmer | `reson`   | 0.05 → 0.85 (keep below self-oscillation)                            |
| E3 shimmer | `drive`   | 1.0 → 1.6                                                            |

- Scene brightness on screen follows `cf`.
- **K3:** strike.

## Air

### Clouds → `MiClouds`

| Macro      | Parameter | Range      |
| ---------- | --------- | ---------- |
| E2 density | `dens`    | 0.35 → 0.9 |
| E2 density | `fb`      | 0.05 → 0.4 |
| E3 size    | `size`    | 0.1 → 0.85 |
| E3 size    | `tex`     | 0.3 → 0.7  |

- **Variant (hold K2 + E2):** `mode`: granular (default), pitch shifter, looping delay, spectral.
  `drywet` 0.45, `spread` 0.7, `rvb` 0.3, `pos` drifts slowly (a 20 s LFO, 0.3 ↔ 0.7) so the clouds move.
- **Coupled:** `pit` jitter ← brain change (±0 → ±0.3 semitones of drift), so windy weather wobbles the grains.
- **K3:** `freeze`.

### Fireflies → `MiBeads`

| Macro      | Parameter  | Range                                                          |
| ---------- | ---------- | -------------------------------------------------------------- |
| E2 density | `density`  | 0.56 → 0.95 (the random-grain zone; 0.48–0.52 makes no grains) |
| E2 density | `fb`       | 0.05 → 0.35                                                    |
| E3 glow    | `size`     | 0.2 → 0.85                                                     |
| E3 glow    | `time_rnd` | 0.1 → 0.5 (grains wander as trails grow)                       |

- **Fixed:** `quality` 0 hi-fi (no resampling at 48 kHz, the cheapest setting on norns),
  `drywet` 0.5, `rvb` 0.35, `shape` 0.6, `pitch_rnd` 0.08, `seed_btn` 2. Never pass `seed`.
- **K3:** `freeze`.
- Memory: about 1 MB of real-time memory per instance. One is enough.

### Mountains → `MiVerb`

| Macro   | Parameter | Range       |
| ------- | --------- | ----------- |
| E2 size | `time`    | 0.5 → 0.97  |
| E3 echo | `drywet`  | 0.12 → 0.65 |

- **Fixed:** `diff` 0.7, `hp` 0.05.
- **Coupled:** `damp` ← fog clarity (foggy → darker tail: 0.75 → 0.35). Without fog: 0.5.
- **K3:** `freeze`.

## Climate (modulation)

An optional chaotic attractor (setting **climate**: off, fronts, gusts, tides, squalls) moves
the macros the way CV moves a eurorack module's knobs: the macro as set is the center, and the
attractor adds `cv × 0.5 × output`, clamped to `0..1`. Each macro has its own `cv` amount in
PARAMS (`-1..1`, an attenuverter). The **drift** setting sets the speed: about 40, 15 or 5 seconds
per loop of the attractor (slow, medium, fast), whichever attractor is picked.

The three outputs are linked, so each part takes a different one and they move together:

| Part  | E2 macro ← | default cv         | E3 macro ← | default cv |
| ----- | ---------- | ------------------ | ---------- | ---------- |
| brain | z          | 0 (rate stays put) | x          | 0.3        |
| voice | x          | 0.4                | y          | 0.3        |
| color | y          | 0.35               | z          | 0.25       |
| air   | z          | 0.35               | x          | 0.3        |

On screen they are named for how they move:

| Name        | Attractor | Moves like                                                                                                  |
| ----------- | --------- | ----------------------------------------------------------------------------------------------------------- |
| **fronts**  | Lorenz    | settles into one mood, then switches to another at unpredictable times (Lorenz found it simulating weather) |
| **gusts**   | Rössler   | circles smoothly; its z output idles, then spikes                                                           |
| **tides**   | Thomas    | slow and rolling; x, y and z are one motion offset in time                                                  |
| **squalls** | Chua      | flips abruptly between two lobes                                                                            |

Outputs are centered on each attractor's median and scaled by its 5th/95th percentiles
(measured over a long run; the table is in `lib/climate.lua`). Played values are rounded to
1/200 so slow drift doesn't send the engine a stream of tiny changes.

## Day

The **day** setting (off, 20 min, 1 hour, clock) adds to every macro, like the climate, by
`depth × light`, where light is +1 at noon and -1 at midnight (dawn at 6:00 for "clock"):

| Part  | E2 macro | E3 macro | Meaning                             |
| ----- | -------- | -------- | ----------------------------------- |
| brain | +0.12    | 0        | rain faster by day, slower at night |
| voice | 0        | +0.12    | brighter by day                     |
| color | +0.1     | 0        | clearer by day                      |
| air   | -0.12    | -0.1     | denser, bigger, longer at night     |
| drone | -0.12    | 0        | comes forward at night              |

The depths are in `lib/daylight.lua` (`DEPTH`).

## Erosion

The **erosion** setting (off, faint, worn, deep, ancient; faint by default) runs `terrarium_tape`
last, on the whole engine output (ReplaceOut on the main bus), so voice, color, air and drone
share it. Plain SuperCollider UGens, no mi-UGens. Off frees the synth (it fades back to dry over
a second).

| Amount    | What it does                                                                          | faint | worn | deep | ancient |
| --------- | ------------------------------------------------------------------------------------- | ----- | ---- | ---- | ------- |
| `wow`     | slow wandering pitch drift: a 10 ms delay moved ±3 ms × wow by LFNoise2 (~0.5–0.9 Hz) | 0.3   | 0.5  | 0.7  | 1       |
| `flutter` | fast fine wobble: ±0.3 ms × flutter at ~6.3 Hz                                        | 0.25  | 0.4  | 0.55 | 0.8     |
| `crackle` | dust pops: Dust at 8–10 × crackle per second, short noise bursts                      | 0.25  | 0.4  | 0.6  | 0.9     |
| `hiss`    | pink noise above 2.5 kHz, 0.012 × hiss                                                | 0.15  | 0.25 | 0.35 | 0.5     |
| `tone`    | lowpass from 19 kHz down to 7 kHz × tone                                              | 0.25  | 0.38 | 0.5  | 0.7     |
| `drive`   | tanh saturation, gain-compensated (unity for quiet signals)                           | 0.15  | 0.25 | 0.35 | 0.5     |

The amounts are the `EROSION` table in `terrarium.lua`. Visitors (nb) play outside the engine, so
the erosion doesn't reach them.

## Drone

A sustained bed on the key's root (C3 + root) and fifth, gliding (4 s) when the key or a season
turns. (It started an octave lower, at C2: that sat below small speakers and nearly vanished.) It plays into the air slot's input, so it shares the sky's space but skips color.
K3 hushes it and lets it rise (`hush`, glided over ~3 s). The **none** module turns it off for
good: the engine frees the drone synth, so it costs no CPU. Its level is PARAMS > levels > hum level.

### Aurora → 2x `MiPlaits` (root and fifth, no trigger)

With a constant (scalar) trigger and level, MiPlaits counts them as unpatched: its LPG stays
open and it sounds continuously. Each voice drifts on its own slow LFO (0.05 / 0.063 Hz) and
swells ±15% on another (0.071 / 0.053 Hz); the fifth sits a little under the root (0.8). The
pitch glides 4 s on key changes, but not in the first half second: the synth starts before its
pitch arrives and must land on the key, not slide into it (roots does the same).

- **Coupled:** `fifth` (the upper voice's interval) ← the weather, like Marbles' slower outputs:
  at each phrase end, with a chance that grows with change, it moves to the consonant interval
  (3, 4, 5, 7, 8 or 9 semitones, in the key) that the phrase's notes use most; the fifth wins
  ties and is the fallback, also when a season leaves the chosen interval out of key.
  `Brain.drone_follow` in `lib/brain.lua`. The chance is `0.2 + change × 0.6` per phrase end.
- **Coupled:** `duck` and `lift` ← the weather's notes (aurora and roots). Each note adds
  `0.3 × velocity` to an activity envelope (decays over ~1.8 s) and `0.25 × velocity` to a lift
  envelope (0.7 for a lightning strike; decays over ~3 s). The drone's level is multiplied by
  `1 − 0.5 × duck` (it gives way to the notes, up to −6 dB, and swells back in the gaps), and
  lift brightens it (aurora: timbre +0.25 × lift; roots: brightness +0.3 × lift).

| Macro     | Parameter                                | Range       |
| --------- | ---------------------------------------- | ----------- |
| E2 glow   | `harm`                                   | 0.3 → 0.6   |
| E2 glow   | `timbre`                                 | 0.15 → 0.75 |
| E3 motion | `morph`                                  | 0.35 → 0.65 |
| E3 motion | `wobble` (LFO depth on timbre and morph) | 0.02 → 0.3  |

- **Variant (hold K2 + E2):** `engine`: string machine 22 (default), chords 6, wavetable 5,
  additive 4, va filter 16, wave terrain 21, phase dist 17.
- **Fixed:** `amp` 0.25.

### Roots → `MiElements` (gate held open)

| Macro     | Parameter           | Range      |
| --------- | ------------------- | ---------- |
| E2 breath | `bow` (bow level)   | 0.8 → 0.15 |
| E2 breath | `blow` (blow level) | 0.1 → 0.75 |
| E2 breath | `flow`              | 0.3 → 0.7  |
| E3 depth  | `geom`              | 0.15 → 0.6 |
| E3 depth  | `space`             | 0.3 → 0.85 |

- **Variant (hold K2 + E2):** `model`: modal, string (default), strings.
- **Fixed:** `bright` 0.4, `damp` 0.7, `contour` 0.8 (sustaining), `strength` 0.6, `amp` 0.3.
- Needs MiElements, part of the mi-UGens set terrarium installs (it requires the whole set).

## CPU budget (to measure on norns)

Rough heaviness of each module, lightest first: MiVerb < Ripples < Plaits < Clouds ≈ Beads < Rings.
Worst case is 2–3 Plaits + Rings + Beads, plus the drone: 2 more Plaits (aurora) or Elements
(roots, as heavy as Rings). Measure that first and pick the Plaits polyphony from it.

## Open questions for tuning

- Climate defaults: which macros should move out of the box, and how far. Brain rate is left at
  0 so rain doesn't jump between clock divisions.
- Snow: how fast the cover builds and thaws, and how deep the muffle goes; a hush you notice
  after a few minutes, not a filter closing. Whether the cold should also lengthen the
  mountains' tail (stillness won over a bigger reverb for now: real snow deadens sound). The drips might want a quieter velocity or fewer
  of them.

1. Default Plaits engine for the meadow. Modal (12) is the safe pick, string machine (22) the lush one.
2. Should the voice → Rings feed be audio (voice excites Rings) or trigger-only (Rings uses its
   internal exciter)? Audio is more "one instrument", trigger is cleaner.
3. Which DX bank and patches make the best crystals.
