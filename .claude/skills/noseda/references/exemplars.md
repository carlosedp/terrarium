# Exemplars by purpose

These are reading targets, not blanket style authorities. Apply the
[evidence policy](modern.md#evidence-and-scope) first. Pins were inspected on
2026-10-15; dates below are latest default-branch commits observed, not proof
of ongoing maintenance or compatibility with the target norns release.

## House conventions

Official docs at [de746029](https://github.com/monome/docs/tree/de746029ef57244036df2a206e5b894a29b5e0f6):

| Reference | Learn from it |
|---|---|
| `norns/study-1.md` | Variables, arithmetic, keys and encoders |
| `norns/study-2.md` | Screen drawing, loops/tables; direct event redraw is supported |
| `norns/study-3.md` | Functions, params and time; cross-check older PSET action wording against source |
| `norns/study-4.md` | Grid, MIDI and clock interaction |
| `norns/study-5.md` | Polls, OSC and storage |
| `norns/study-0.md` / firstlight | A small editable musical system, clocked and asynchronous behavior |
| `norns/grid-recipes.md:34–92` | Dirty grid rendering and interaction/state recipes |
| `norns/clocks.md:27–139,235–318` | Coroutine handles, time domains, transport and UI polling |

The script [monome/firstlight@7c6990e4](https://github.com/monome/firstlight/tree/7c6990e4)
(2021-10-23) uses sequins/clock, asynchronous chimes and softcut:
`firstlight.lua:18–122`. Current documentation support, not its commit date,
establishes those APIs as current.

## Discipline, instrument design and architecture

| Audited repository / latest commit | Reference for | Evidence paths and caveats |
|---|---|---|
| [markwheeler/passersby@0869e147](https://github.com/markwheeler/passersby/tree/0869e147) · 2022-11-21 | Local state/helpers, params-driven UI, engine-control library/specs | `passersby.lua:13–62,397–449`; `lib/passersby_engine.lua:61–104`. Historical discipline exemplar; metro UI at `passersby.lua:858–867` is still a supported choice. |
| [markwheeler/loom@25a64599](https://github.com/markwheeler/loom/tree/25a64599) · 2021-01-09 | Organization, local helpers, dirty drawing, reusable engine library | `loom.lua:29–94,911–1014`. BeatClock/metro-era sequencing is not the current musical-clock default. |
| [markwheeler/molly_the_poly@76cd4dc8](https://github.com/markwheeler/molly_the_poly/tree/76cd4dc8) · 2023-02-08 | Engine specs/add_params separation, params-driven randomization | `molly_the_poly.lua:12–35`; `lib/molly_the_poly_engine.lua:74–160`. Don't copy its entire historical timing architecture. |
| [sonocircuit/mlre@ba88531b](https://github.com/sonocircuit/mlre/tree/ba88531b) · 2025-04-24 | Targeted current APIs: version requirement, local includes, PSET hooks, lattice, cancellation | `mlre.lua:14–24,2485–2500,3440–3451,3481–3512`; `lib/pattern_time_mlre.lua:215–237`. These APIs are independently supported in current core/docs. |
| [jaseknighter/flora@1a708fde](https://github.com/jaseknighter/flora/tree/1a708fde) · 2025-11-21 | Musical paradigm: L-system/turtle sequencing; nb integration | `README.md:75–98`; `lib/l_system.lua:122–186`; `lib/plant_sounds_externals.lua:246–264`; bundled nb include in `lib/includes.lua:60–62`. Latest tip is README-only, not evidence of recent code maintenance. |
| [tehn/plasma@d4e12086](https://github.com/tehn/plasma/tree/d4e12086) · 2024-09-11 | Native refresh-driven screen rendering, every second event | `plasma.lua:128–134`. `refresh()` is source-supported, undocumented; widespread maintained adoption is unverified. |
| [justmat/otis@2864176a](https://github.com/justmat/otis/tree/2864176a) · 2024-07-04 | Instrument paradigm: stereo tape looper/delay and performance gestures | `otis.lua:20–58`; `lib/tlps.lua:24–73,105–147`. Study the interaction model, not all implementation choices as style rules. |
| [tehn/mlr@1c21309b](https://github.com/tehn/mlr/tree/1c21309b) · 2022-07-05 | Instrument paradigm: grid sample cutting, recorded gestures, quantized events | `mlr.lua:85–127,194–202,605–617`. This is the norns implementation, not the original Max instrument. |
| [northern-information/arcologies@06960f3c](https://github.com/northern-information/arcologies/tree/06960f3c) · 2026-03-23 | Architecture at scale: domain entities, mixins, interaction/state coordination | Former `tyleretters/arcologies`; `README.md:23–31`; `lib/includes.lua:21–83,109–135`. Architecture reference, not a local-by-default template. |
| [21echoes/cyrene@cc99a6d5](https://github.com/21echoes/cyrene/tree/cc99a6d5) · 2023-04-24 | Injected sequencer action, separated pages/adapters, script/mod reuse | `cyrene.lua:84–98`; `lib/sequencer.lua:23–56`; `lib/mod.lua:47–88`. Historical architecture example. |

Awake is not the default style template: its combination of clocks, metros and
step-loop redraw should be assessed by purpose. It can still illustrate a
specific feature, such as representing step values as parameters. See the
explicitly pinned Awake link in D `norns/reference/parameters.md:269`.

## Feature references only

| Audited repository / latest commit | Feature to study, not overall style |
|---|---|
| [dndrks/cheat_codes_2@7134bd5b](https://github.com/dndrks/cheat_codes_2/tree/7134bd5b) · 2025-09-29 | Pads/banks, quantized triggering, capture/arp/Euclidean interaction: `lib/grid_actions.lua:1437–1515`; controller list in `README.md:9–19`. |
| [dstroud/dreamsequence@c279ac2f](https://github.com/dstroud/dreamsequence/tree/c279ac2f) · 2025-06-26 | Chord-aware sequencing, arranger, automation and multiple nb voices: `README.md:19–29`; `lib/events.lua:1–34`; `dreamsequence.lua:3522–3554`. |
| [schollz/zxcvbn@3dd01360](https://github.com/schollz/zxcvbn/tree/3dd01360) · 2024-05-06 | Text musical language/tracker, onset detection, portable projects: `lib/tli.lua`; `lib/sample.lua:148–199`; `lib/archive.lua:94–117`. |

## Optional nb interface

**Ecosystem dependency:** [sixolet/nb@400e0b38](https://github.com/sixolet/nb/tree/400e0b38)
(2024-06-15), `README.md`, `lib/nb.lua`, `lib/player.lua`.

- Upstream documents `git submodule add https://github.com/sixolet/nb.git lib/nb`.
  Ship/init that dependency deliberately; installed voice-provider mods are a
  separate requirement for those backends. Flora bundles a copy; cheat_codes_2
  declares a submodule in `.gitmodules`.
- Host calls `nb:init()`, `nb:add_param(id, name)`, `nb:add_player_params()`.
  Obtain a player via `params:lookup_param(id):get_player()`.
- Players expose `note_on`, `note_off`, `play_note`, capability descriptions and
  lifecycle callbacks `active`, `delayed_active`, `inactive`, `stop_all`.
  Base `play_note` interprets length as beats, converting to seconds at launch.
  Base optional methods can be no-ops; verify backend capabilities/cleanup.
- `nb:add_player_params()` iterates all registered players at this revision,
  despite README wording suggesting only selected players.
- Voice-provider example: [sonocircuit/nb_plyprc@eb9ea921](https://github.com/sonocircuit/nb_plyprc/tree/eb9ea921)
  (2026-03-04), `lib/mod.lua:187–205`, registers `note_players['plyprc']`
  in `script_pre_init`.

These establish concrete external interfaces and multiple integrations. They
do not establish a mandatory core output idiom or prove present maintenance.
See [note-output patterns](patterns/midi.md) for ownership and units.
