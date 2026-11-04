# Review and refactor modernity

Read the [modern definition](../modern.md) for applicable components, then their
component guides. A review should improve platform integration without erasing
the instrument's intentional behavior. Metro, globals and direct event redraws
are not findings by themselves.

## Workflow

1. **Establish the target.** Record the update number (stable is 260102),
   hardware/backend, dependencies and enabled mods. Review against stable unless
   the user asks for beta support; then also use [beta compatibility](beta-compat.md).
2. **Map components and ownership.** Entry scripts, lib/mod.lua, SC classes,
   reusable modules, shared mutations, external notes/processes and saved data.
3. **Capture behavior.** First-note phase, swing, transport continue/restart,
   note overlap/tails, screen/grid/modal ownership, PSET/PMAP IDs/options and paths.
4. **Inspect against the checklist.** Verify actual API behavior in the target
   source/docs; use [exemplars](../exemplars.md) only for their assigned purpose.
5. **Prioritize findings.** Separate bugs/deprecated APIs, compatibility work,
   measured bottlenecks and optional architectural improvements. Mark rules not
   applicable to the component; don't invent work to fill every row.
6. **Refactor in behavior-preserving steps.** Keep migrations and timing/output
   changes explicit. Use the smallest checks that distinguish correct behavior.
7. **Report evidence and residual work.** Link each finding to code and source,
   record what was tested, and name hardware/release checks still outstanding.

## Finding format

Every finding includes these three fields, even when the idiom isn't deprecated:

```text
Location and severity:
Legacy idiom → modern replacement → risk of changing it:
Evidence: target source/docs paths; observed behavior where relevant
Verification: behavior/compatibility checks to run, and results if run
```

For example: “manually scaled metro sequencer → clock.sync or lattice → changes
first-note phase, swing and transport; preserve those policies and compare
recorded timestamps.” A modern replacement can be “retain the supported idiom,
fix its ownership” when wholesale conversion has no benefit.

## Script and shared-library checklist

| Check / legacy idiom | Modern replacement | Risk of changing it |
|---|---|---|
| Runtime saves written into code/ | `norns.state.data`; audio under `_path.audio`, with existing-save import | Lost discoverability, overwritten sessions, audio references |
| Assumed `<folder>.lua` requirement or empty mandatory callbacks | Conventional layout; implement callbacks actually needed | Menu naming/data paths can change when moving entries |
| Blanket “no globals” or private `_helper` policy | Script globals where useful, local returned library tables, protect system names | Scope/upvalue changes can break callbacks and module consumers |
| `require 'lib/foo'` assumed script-relative | Script `include('lib/foo')`; project-qualified cached require for mods | Fresh execution vs cached state; dependency paths |
| UI state duplicates a mappable setting | Params as authority; actions update sound/caches | Action ordering, side effects, current performance behavior |
| Duplicate param IDs / incorrect group counts | Stable collision-free IDs and accurate nonnested groups | Renamed IDs break PSET/PMAP; changed ranges/options reinterpret values |
| Engine commands/config only updated by encoders | Parameter actions shared by PARAMS/PMAP/PSET paths | Startup actions may fire before resources or sidecars exist |
| `params:bang()` described as save / blind default recall | Explicit initialization and recall policy | Duplicate actions, external messages, different startup sound |
| Non-param data not tied to PSET lifecycle | Versioned sidecars and coordinated write/read/delete hooks | Missing/old data, overwrite semantics, multi-file partial saves |
| BeatClock/manual tempo math for beat synchronization | `clock.sync` or current lattice sprockets | First note, swing, meter, phase, reset and recorded data |
| Metro used for genuine seconds-based UI/events | Retain supported metro, fix lifecycle if needed | Replacing with sleep can introduce drift; removing timer changes UI |
| Lattice `new_pattern` / `set_meter` | `new_sprocket` and explicit division semantics | Division units, immediate first pulse, ordering |
| Duplicate clocks on repeated play / untracked replacement | Idempotent starts, retained handles and explicit stop | Continue vs restart; pending note-offs cancelled too early |
| High-rate musical callback draws every frame | State/dirty flags and independent UI service | Visual latency, animation phase; occasional direct redraw may be fine |
| Timer calls captured local redraw during menu/modal UI | Call global redraw and honor modal ownership | Menu overwrite, stale flags, forced menu-return redraw |
| Native refresh assumed portable/documented | Label source-only, verify backend or use documented polling | No refresh events on inspected SDL; modal interference |
| External notes lost on wrap/output change | Owned note identities/deadlines and explicit release | Same-pitch overlap, note tails, shared channels/players |
| Cleanup assumed solely responsible for all core resets | Explicit owned cleanup plus accurate core-reset boundary | Double release, stale handles, partial init, SLEEP behavior |
| Engine commands sent to free resources during Lua cleanup | SC-owned `free`, external-output cleanup in Lua | Engine release already requested; asynchronous ordering |
| System implementation/action replaced unconditionally | Supported callback or composed/restored wrapper | Breaks system behavior, other scripts/mods, wrapper ordering |
| Modified vendored core library | Shipped API or small adapter when compatible | Existing fork behavior/version compatibility needs analysis |

Evidence: N `lua/core/script.lua`, `startup.lua`, `config.lua`, `paramset.lua`,
`clock.lua`, `midi.lua`, `grid.lua`, `menu.lua` (all under `lua/core/`),
`lua/lib/lattice.lua`, `matron/src/clocks/clock_scheduler.c`;
D `norns/reference.md`, `norns/reference/parameters.md`, `norns/clocks.md`,
`norns/reference/metro.md`, `norns/grid-recipes.md`.
Detailed contracts/citations: [modern.md](../modern.md), [params](../patterns/params.md),
[state](../patterns/state.md), [timing](../patterns/timing.md), [UI](../patterns/ui.md),
[output](../patterns/midi.md).

## Mod checklist

| Legacy idiom | Modern replacement | Risk of changing it |
|---|---|---|
| Incorrect entry path / fictitious hook name | `lib/mod.lua` and the five stable hooks | Load failure; hook timing and missing startup cases |
| Menu function returns param descriptors | Registered callback table, supported mods menu helpers | Navigation, entry/exit and input ownership |
| `include` re-executes a mod / unqualified helper paths | Project-qualified cached require, returned API | Duplicate registration, changed module lifetime |
| Global injected service assumed persistent | Module locals plus explicit per-script setup | Script state reset, old callback captures |
| Timer/poll started just before core reset | Recreate in the appropriate initialized lifecycle | Service silently stops; interactions with enabled scripts |
| Assumes one script or overwrites shared function/params | Explicit contract, namespace, composition/restoration | Inter-mod ordering, PARAMS conflicts, incompatible scripts |
| Only script cleanup handles external process | Process-lifetime shutdown ownership plus per-script release | SLEEP does not invoke post-cleanup |
| nb provider inferred from generic “MIDI-like” methods | Pinned optional player contract and tested backend lifecycle | Inactive/selection behavior, held notes and no-op panic methods |

Evidence: N `lua/core/mods.lua`, `hook.lua`, `script.lua`, `norns.lua`
(under `lua/core/`); D `norns/mods.md`; external nb sources in
[exemplars](../exemplars.md#optional-nb-interface).

## Engine checklist

| Legacy idiom | Modern replacement | Risk of changing it |
|---|---|---|
| Generic class/SynthDef names | Unique project names; conventional Engine file | Recompilation, host engine selection, duplicate installed copies |
| Constructor/polls/.add assumed universally required | Inherited constructor, optional feedback, explicit server setup | Accidental change in readiness or command/poll reports |
| Synth created before async definition/setup finishes | Server synchronization in alloc | Startup latency and error-path cleanup |
| Hz/MIDI note or amplitude units disagree | Consistent typed command/spec contract | Existing hosts/PSETs may need conversion |
| Repeated voice allocations overwrite one reference | Owned group/voice manager, bounded lifetime/polyphony | Stealing, releases, overlap and musical tails |
| Frees shared context or omits owned resources | Free only owned synths/groups/buffers/buses/tasks | Other routing/analysis breaks; reload leaks |
| Performance/UI coupled to raw engine config | Lua specs/add_params companion; host recall policy | Parameter IDs, initialization order, upstream host reuse |
| New custom note engine by default | Assess existing engine or optional nb provider packaging | Dependencies, latency, output capabilities and installation |
| CPU/UGen efficiency assumed without measurement | Hardware idle/worst-case comparison and headroom | A faster desktop or fewer played notes can hide overload |

Evidence: N `sc/core/CroneEngine.sc`, `Crone.sc`, `CroneAudioContext.sc`,
`CronePoll.sc` (under `sc/core/`), `lua/core/engine.lua`,
`matron/src/weaver.c`; D `norns/engine-study-{1,2,3}.md`.

## Verify the migration

Use [debugging](debug.md) and [performance](optimize.md) only where relevant.
Exercise fresh load/rerun/switch, repeated start/stop, menu/modal transitions,
legacy PSET/PMAP fixtures, sidecar/audio paths, note release and partial init.
For timing changes compare intended-beat lateness and actual step counts;
current sync can catch up, so counts alone aren't sufficient. Keep firmware,
mods, seed, tempo, clock source and device fixed in comparisons. Record results
and any intentional musical differences; don't call untested output equivalent.
