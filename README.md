# <img src="https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/img/icon.png" alt="" width="40" height="40" align="top"> terrarium

![terrarium on a norns shield, standing on the ground under a night sky: rain falls on a meadow and a pond on its screen](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/cover.png)

🌱 A small world of modular instruments for [monome norns](https://monome.org/docs/norns/).

**[Read the manual](https://github.com/carlosedp/terrarium/blob/main/doc/MANUAL.md)** for how to play it (also as a [PDF](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/terrarium-manual.pdf)),
or **[try it in your browser](https://terrarium.glassgarden.cc/)**, phones included: the real
script, playing the real Mutable Instruments code. It also comes as a **VST3 / AU plugin** for your
DAW, on its tempo and automation: see [the plugin's manual](https://github.com/carlosedp/terrarium/blob/main/doc/PLUGIN-MANUAL.md) (and
[plugin/](https://github.com/carlosedp/terrarium/blob/main/plugin/README.md) for building it).

The patch is a landscape. Five parts each draw one piece of the scene and play one part of
the sound. Swap a module and that piece of the scene changes; turn a macro and the scene moves
with the sound. The screen shows no numbers.

| Part        | In the scene                                            | Modules                                                                                           |
| ----------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **weather** | when notes happen and which ones                        | rain (clocked to the norns clock), lightning (random), snow (drifting, and it settles)            |
| **soil**    | what grows from the ground: what plays                  | meadow (Plaits), crystals (Plaits 6-op FM), reeds (Rings), visitors (MIDI out, the audio in back) |
| **water**   | the pond and the fog: what shapes it                    | pond (Rings), fog (Ripples)                                                                       |
| **air**     | the sky: where it rings out                             | clouds (Clouds), fireflies (Beads), mountains (MiVerb)                                            |
| **hum**     | always there, under it all, on the key's root and fifth | aurora (Plaits), roots (Elements), none                                                           |

The whole scene sits behind the terrarium's glass. Rain beads up on it, and freezing the air
frosts it over.

Every note is a place: where it lands across the screen sets its pitch in the current key
and scale. The weather keeps a Turing Machine-style phrase, and each note leaves a mark on the
ground. **Change** sets how often notes are replaced, dropped to a rest or added back.
**Seasons** (slow by default) let the key drift between close neighbors and find its way home,
at dawn and dusk when the day is on, a note at a time.

## Requirements

- norns (or norns shield / fates)
- [mi-UGens](https://github.com/carlosedp/norns-mi-UGens) built for norns. If they're missing,
  terrarium shows an installer instead of the scene: **K3** downloads and installs the latest
  build, **K2** installs a `mi-UGens-norns*.tar.gz` you copied into `dust/`. Restart norns after.
  Fireflies needs a build that includes MiBeads; without it, that module is hidden.

## Install

From the maiden REPL:

```
;install https://github.com/carlosedp/terrarium
```

## Controls

| Control      | Does                                                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| E1           | choose a part (the others dim for a moment)                                                                                           |
| E2, E3       | that part's two macros (their names show for a moment while you turn)                                                                 |
| K2           | swap the part's module                                                                                                                |
| hold K2 + E2 | pick the module's variant: Plaits engine (meadow), DX bank (crystals), Rings model (reeds, pond), MIDI device (visitors), Clouds mode |
| K3           | gesture: new phrase (weather), strike (soil, water), freeze (air), hush / rise (hum)                                                  |
| hold K1      | peek at all parts; while held, E2 picks a setting and E3 changes it                                                                   |
| hold K1 + K3 | a new terrarium: random modules, varieties, knobs and settings, all but the day (also PARAMS > randomize the jar)                     |

**Climate** (a setting, off by default) lets a chaotic attractor slowly move the macros: fronts
(Lorenz), gusts (Rössler), tides (Thomas) or squalls (Chua). It moves them, the way CV moves a module's knobs: the macro you set is the center and
the climate pushes it around it. Each macro has a cv amount in PARAMS; the peek view shows
where each macro is right now and the attractor's path.

**Day** (a setting, off by default) adds the longest arc: a day and night of 20 minutes, an hour,
or following the norns' clock. Night slows the weather, darkens the soil, opens up the air and
brings the hum forward; the sky shows a sun by day and a moon and stars by night.

**Erosion** (a setting: off, faint, worn, deep, ancient; faint by default) gives the whole sound
the wear of an old recording: wow, flutter, crackle, hiss, a rolled-off top, a little warmth. It
glues the notes, the hum and the sky together; dust settles on the glass as it wears.

**Snow** (a weather module) falls slower and looser than rain and settles on the ground. The
snow cover muffles the soil, more the longer it snows; with the day on, the sun thaws it (the
meltwater drips a few soft notes) and the night lets it build up again.

**Breath** (a setting, gentle by default) adds silence: now and then the weather calms for a phrase
or three, notes rest (the phrase keeps them) and their marks dim, then it breathes in again.

**Presets:** the jar you leave (for another script, or SLEEP) comes back the next time you open
terrarium; PARAMS > reset the jar brings back the plain one. To keep more than one, norns saves
presets for you: in the norns menu, PARAMS > PSET > save / load. A preset holds everything,
including modules, variants, settings, levels, and whether the air is frozen or the hum hushed.

A quick tap of K1 still opens the norns menu. Settings (key, scale, range, length, seasons,
climate, drift, day, breath, erosion),
every macro, and each module's fixed options (Plaits engine, DX bank, Rings model, Clouds
mode) are also in PARAMS, so they save with PSETs and can be MIDI-mapped.

## Development

How it's built, testing without a norns, running it in a browser, tuning and what's left to do on
hardware: see [doc/DEVELOPMENT.md](https://github.com/carlosedp/terrarium/blob/main/doc/DEVELOPMENT.md).

## Wallpapers

The device under the night sky, for a desktop (3840 × 2160) or a phone (1179 × 2556), in the
aluminium case or the black one.

| Scene                                                                                                                                                                                                                               | Desktop                                                                                                                                                                                                                                   | Phone                                                                                                                                                                                                                                 |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| <img src="https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/meadow-desktop-alu.jpg" alt="Rain on a meadow and a pond, clouds, an aurora" width="320"><br>Rain on a meadow and a pond, clouds, an aurora | [aluminium](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/meadow-desktop-alu.jpg) · [black](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/meadow-desktop-black.jpg)       | [aluminium](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/meadow-phone-alu.jpg) · [black](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/meadow-phone-black.jpg)       |
| <img src="https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/snow-desktop-alu.jpg" alt="Snow settling on crystals, mountains behind" width="320"><br>Snow settling on crystals, mountains behind         | [aluminium](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/snow-desktop-alu.jpg) · [black](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/snow-desktop-black.jpg)           | [aluminium](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/snow-phone-alu.jpg) · [black](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/snow-phone-black.jpg)           |
| <img src="https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/fireflies-desktop-alu.jpg" alt="Reeds over a pond, fireflies in the dark" width="320"><br>Reeds over a pond, fireflies in the dark          | [aluminium](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/fireflies-desktop-alu.jpg) · [black](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/fireflies-desktop-black.jpg) | [aluminium](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/fireflies-phone-alu.jpg) · [black](https://raw.githubusercontent.com/carlosedp/terrarium/main/doc/art/wallpapers/fireflies-phone-black.jpg) |

## License and copyright

terrarium is made by [glassgarden](https://glassgarden.cc). © 2026 glassgarden.

- **The code** is free software under the GNU GPL v3.0 (see [LICENSE](https://github.com/carlosedp/terrarium/blob/main/LICENSE)): you can use,
  study, share and change it under its terms.
- **The terrarium name, the manual and its images** are © 2026 glassgarden, all rights
  reserved.
- **Built on others' work:** the sound is Émilie Gillet's
  [Mutable Instruments code](https://github.com/pichenettes/eurorack), via Volker Böhm's
  [mi-UGens](https://github.com/v7b1/mi-UGens) (GPL-3.0), installed separately on the norns. The
  browser version carries WebAssembly builds of seven of them in `lib/Engine_Terrarium/`, built
  from [norns-mi-UGens](https://github.com/carlosedp/norns-mi-UGens) (`BUILDINFO` there records
  the source).
  [wasmoon](https://github.com/ceifa/wasmoon) (MIT) is vendored in `tools/norns-web`. The plugin's
  downloads carry [THIRD-PARTY-NOTICES.txt](https://github.com/carlosedp/terrarium/blob/main/THIRD-PARTY-NOTICES.txt), with the licences of all it
  includes.
- Mutable Instruments, monome, norns and all other product names are trademarks of their
  respective owners, used only to identify what terrarium works with. No affiliation with or
  endorsement by them is implied.
