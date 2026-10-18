# terrarium: sound map (draft)

How each macro on the screen drives the real mi-UGens. This is the starting point for
tuning: ranges and curves are first guesses, to be adjusted by ear on the real engines.
The web prototype only uses Web Audio stand-ins.

Conventions:

- Every macro is `0..1` on the encoder. A mapping like `harm 0.05→0.95` is the parameter's
  value at macro 0 and macro 1, linear unless a curve is given.
- **Fixed** values are per-module defaults, to be exposed in the PARAMS menu (hidden from the scene).
- **Coupled** values come from *another* slot. That's where the "it just sounds good" comes from,
  so keep the list short and deliberate.
- Signal flow: `brain → voice → color → air → out`. nb voices join after the voice slot through
  the insert on the main output, the same way the fx mod works.

## Brain (no audio)

| Macro | Drives | Notes |
| --- | --- | --- |
| E2 rate | event rate: rain 0.5→6 Hz (clocked), lightning 0.3→6 Hz average (random, with occasional double strikes) | exponential |
| E3 change | chance per step that the phrase mutates: `change²` | 0 = loop forever |
| K3 | new phrase | |
| Settings | key, scale, range (1–3 octaves), length (4–16), seasons | also in PARAMS; grid later |

Each note sends `pitch` (MIDI note) and a velocity-like `accent` (0..1, from the brain: e.g.
lightning double strikes and new notes accent higher).

## Voice

### Meadow → `MiPlaits`

| Macro | Parameter | Range |
| --- | --- | --- |
| E2 harmonics | `harm` | 0.05 → 0.95 |
| E3 timbre | `timbre` | 0.1 → 0.9 |
| E3 timbre | `morph` | 0.35 → 0.65 (follows timbre, narrower) |

- **Fixed:** `engine` from a curated "flora" list in PARAMS. Suggested default: **12 modal**.
  The others: 11 string, 4 additive, 5 wavetable, 22 string machine.
  The drums, speech, chord and noise engines don't fit a melodic meadow.
- **Fixed:** `lpg_colour` 0.5. Each note fires `trigger`, with `level` set from accent.
- **Coupled:** `decay` ← brain rate: fast rain plays shorter notes (0.75 at slow rate → 0.4 at fast).
- Polyphony: Plaits is mono per instance. Run 2–3 instances round-robin so notes ring over each other.
  Check the CPU cost on norns first.

### Crystals → `MiPlaits` 6-op FM (engines 18–20)

The glassy voice can be a real MI engine. No stand-in or nb voice needed.

| Macro | Parameter | Range |
| --- | --- | --- |
| E2 ratio | `harm` (selects the 6-op patch within the bank) | 0 → 1, quantized to the bank's 32 patches |
| E3 index | `timbre` (modulation amount) | 0.15 → 0.85 |
| E3 index | `morph` (envelope stretch) | 0.3 → 0.7 |

- **Fixed:** `engine` 18, 19 or 20 (which DX bank), chosen in PARAMS. Tune by ear for the most "glass".
- Ratio scrolling through patches is coarse. If it feels jumpy, keep `harm` fixed per variety
  and map E2 to `morph` instead.

### A third voice slot for nb

nb voices (Emplaitress, Doubledecker, monami.e, MIDI, Just Friends…) are better as their own
voice option than hidden behind crystals. Proposed module name: **visitors**, drawn as something
that arrives from elsewhere (birds landing, perhaps).

- Notes go to the nb player chosen in PARAMS (`nb:add_param`).
- Each nb voice has its own parameters, so the scene can only promise:
  E2 → `player:modulate(v)` (each voice decides what that does), E3 → note length.
- Their audio still passes through color and air via the insert on the main output.

## Color

### Pond → `MiRings`

The voice's audio goes into Rings' `in` (the voice excites the resonator), and each note sets `pit`
and fires `trig`.

| Macro | Parameter | Range |
| --- | --- | --- |
| E2 structure | `struct` | 0.1 → 0.85 (above ~0.9 modal goes metallic and harsh) |
| E3 damping | `damp` (inverted: more damping, shorter ring) | 0.92 → 0.35 |

- **Fixed:** `model` 0 modal, in PARAMS as "pond kind" (1 sympathetic strings and 5 string+reverb are
  good alternates). `poly` 2. `pos` 0.3.
- **Coupled:** `bright` ← the voice's timbre macro (0.35 → 0.7), so a brighter voice rings brighter.
- **Mix:** Rings has no dry/wet. Blend `voice × (1 − 0.5·structure) + rings` so more structure means more resonator.
- **K3:** strike, which triggers Rings directly with the internal exciter for one note.

### Fog → `MiRipples`

| Macro | Parameter | Range |
| --- | --- | --- |
| E2 clarity | `cf` | 0.12 → 0.92, exponential feel (most of the action in the lower half) |
| E3 shimmer | `reson` | 0.05 → 0.85 (keep below self-oscillation) |
| E3 shimmer | `drive` | 1.0 → 1.6 |

- Scene brightness on screen follows `cf` (already in the prototype).
- **K3:** strike.

## Air

### Clouds → `MiClouds`

| Macro | Parameter | Range |
| --- | --- | --- |
| E2 density | `dens` | 0.35 → 0.9 |
| E2 density | `fb` | 0.05 → 0.4 |
| E3 size | `size` | 0.1 → 0.85 |
| E3 size | `tex` | 0.3 → 0.7 |

- **Fixed:** `mode` 0 granular (PARAMS "cloud kind": stretch, looping delay, spectral).
  `drywet` 0.45, `spread` 0.7, `rvb` 0.3, `pos` drifts slowly (a 20 s LFO, 0.3 ↔ 0.7) so the clouds move.
- **Coupled:** `pit` jitter ← brain change (±0 → ±0.3 semitones of drift), so windy weather wobbles the grains.
- **K3:** `freeze`.

### Fireflies → `MiBeads`

| Macro | Parameter | Range |
| --- | --- | --- |
| E2 density | `density` | 0.56 → 0.95 (the random-grain zone; 0.48–0.52 makes no grains) |
| E2 density | `fb` | 0.05 → 0.35 |
| E3 glow | `size` | 0.2 → 0.85 |
| E3 glow | `time_rnd` | 0.1 → 0.5 (grains wander as trails grow) |

- **Fixed:** `quality` 0 hi-fi (no resampling at 48 kHz, the cheapest setting on norns),
  `drywet` 0.5, `rvb` 0.35, `shape` 0.6, `pitch_rnd` 0.08, `seed_btn` 2. Never pass `seed`.
- **K3:** `freeze`.
- Memory: about 1 MB of real-time memory per instance. One is enough.

### Mountains → `MiVerb`

| Macro | Parameter | Range |
| --- | --- | --- |
| E2 size | `time` | 0.5 → 0.97 |
| E3 echo | `drywet` | 0.12 → 0.65 |

- **Fixed:** `diff` 0.7, `hp` 0.05.
- **Coupled:** `damp` ← fog clarity (foggy → darker tail: 0.75 → 0.35). Without fog: 0.5.
- **K3:** `freeze`.

## Climate (modulation)

An optional chaotic attractor (setting **climate**: off, lorenz, rossler, thomas, chua) moves
the macros the way CV moves a eurorack module's knobs: the macro as set is the center, and the
attractor adds `cv × 0.5 × output`, clamped to `0..1`. Each macro has its own `cv` amount in
PARAMS (`-1..1`, an attenuverter). The **drift** setting sets the speed: about 40, 15 or 5 seconds
per loop of the attractor (slow, medium, fast), whichever attractor is picked.

The three outputs are linked, so each part takes a different one and they move together:

| Part | E2 macro ← | default cv | E3 macro ← | default cv |
| --- | --- | --- | --- | --- |
| brain | z | 0 (rate stays put) | x | 0.3 |
| voice | x | 0.4 | y | 0.3 |
| color | y | 0.35 | z | 0.25 |
| air | z | 0.35 | x | 0.3 |

Character: **lorenz** swings between two moods at irregular times; **rossler** circles smoothly
and its z output idles then gusts (heard on brain rate/air density); **thomas** is slow, with x,
y and z the same motion phase shifted; **chua** flips between two lobes, more abruptly.

Outputs are centered on each attractor's median and scaled by its 5th/95th percentiles
(measured over a long run; the table is in `lib/climate.lua`). Played values are rounded to
1/200 so slow drift doesn't send the engine a stream of tiny changes.

## CPU budget (to measure on norns)

Rough heaviness of each module, lightest first: MiVerb < Ripples < Plaits < Clouds ≈ Beads < Rings.
Worst case is 2–3 Plaits + Rings + Beads. Measure that first and pick the Plaits polyphony from it.

## Open questions for tuning

- Climate defaults: which macros should move out of the box, and how far. Brain rate is left at
  0 so rain doesn't jump between clock divisions.

1. Default Plaits engine for the meadow. Modal (12) is the safe pick, string machine (22) the lush one.
2. Should the voice → Rings feed be audio (voice excites Rings) or trigger-only (Rings uses its
   internal exciter)? Audio is more "one instrument", trigger is cleaner.
3. Which DX bank and patches make the best crystals.
