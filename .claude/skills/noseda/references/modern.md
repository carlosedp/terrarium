# Modern norns components

## Contents

- [Target](#target)
- [What modern means](#what-modern-means)
- [Shared rules](#shared-rules)
- [Script definition](#script-definition)
- [Mod definition](#mod-definition)
- [Engine definition](#engine-definition)
- [Evidence and scope](#evidence-and-scope)
- [Disagreements and open checks](#disagreements-and-open-checks)

## Target

Write and review components for the **current stable release**: update
**260102**, tag `v2.9.4`. The rules below are verified against that source.
If the user's device runs something else, read `~/version.txt` (or
`norns.version.update` in the REPL) and check the matching tag in a core
checkout before relying on version-sensitive behavior.

The 3.x beta line (260526, 260616, 260819) changes the shell, process and
audio-routing layers. Use [beta compatibility](tasks/beta-compat.md) only when
the user asks for beta support, a failure happens only on a beta build, or the
work is on norns core. Don't move a component to beta-only APIs, or recommend
a beta upgrade, as part of modernizing it.

Declare `norns.version.required = YYMMDD` only for an API need with a verified
minimum release; don't derive the number from a checkout date.

## What modern means

A modern component uses current norns interfaces, integrates with the platform
(PARAMS, PSET, PMAP, menus, clock sources), owns its resources explicitly, and
states its musical and persistence policies. Age, popularity, locals
everywhere, and replacing every metro are not tests of modernity. When
reviewing an older instrument, preserve intentional behavior and report the
cost of each change.

## Shared rules

### Scope and dependencies

New script globals go through `_G`'s metatable into a state table that
`Script.clear()` replaces. That isolates new globals between scripts. It does
not isolate overwrites of existing system globals, mutations of shared library
tables, or cached modules, and it is not a security sandbox.

- Script callbacks are global. Small scripts may keep state in globals; prefer
  locals and explicit dependencies as complexity grows. Reusable `lib/`
  modules ordinarily return local tables. There is no norns rule to prefix
  private helpers with `_` or to avoid all globals.
- Don't shadow system bindings with project state, including misleading local
  aliases: `util`, `tab`, `params`, `clock`, `metro`, `screen`, `grid`, `midi`,
  `arc`, `crow`, `softcut`, `engine`, `audio`, `poll`, `norns`, `include`,
  `_menu`, `_norns`, `_path`.
- Load shipped libraries with `require`: `'musicutil'`, `'lattice'`,
  `'sequins'`, `'lfo'`, `'pattern_time'`, `'reflection'`, `'ui'`,
  `'textentry'`, `'fileselect'`. `params`, `clock`, `screen` and `controlspec`
  already exist.
- Script helpers: `local helper = include('lib/helper')`, which runs the file
  each time. Mod helpers: project-qualified `require 'mymod/lib/helper'`,
  cached and independent of the active script.

Evidence: N `lua/core/script.lua:26–47`, `lua/core/startup.lua:3–32,48–62`,
`lua/core/config.lua:6–16`, `lua/lib/`; D `norns/reference.md` (libraries),
`norns/mods.md:145–167`.

### Platform facilities and shared ownership

Prefer PARAMS, PSETs, PMAP, the shipped UI helpers and libraries when they fit,
and use the shipped core implementation rather than a vendored modified copy.
Avoid production dependencies on `_menu`/`_norns` internals. A leading
underscore doesn't decide documentation status: `_path` and
`_menu.rebuild_params()` are documented.

Scripts may assign extension callbacks such as `midi.add`, `grid.add` and
`clock.transport.*`; core resets them. Wrapping a shared implementation or
replacing a system param action is different: preserve existing behavior and
restore the change when its owner ends. Mods compose with scripts and other
mods; they don't claim every callback slot.

Evidence: N `lua/core/midi.lua:74–84,197–209`,
`lua/core/grid.lua:73–85,143–161`, `lua/core/clock.lua:85–95,129–145,228–238`;
D `norns/reference/parameters.md:24–73,267–288`, `norns/reference.md:205–222`.

## Script definition

### Layout, header and startup

- Layout: `dust/code/<name>/<name>.lua`, helpers under `lib/`, a README with
  controls and dependencies. The matching name is a convention; a project can
  have several entry scripts.
- The contiguous opening comment block is the menu preview. Include name, short
  description, version/author, a discussion/docs URL and controls.
- Set `engine.name` at top level. Core loads the engine and registers its
  commands before calling `init()`.
- `init`, `key`, `enc`, `redraw`, `cleanup` and `refresh` have defaults, so
  omit what you don't need. Define callbacks at script scope: the loader
  captures `redraw`/`refresh` before `init()` runs.
- The `norns.version.required` check runs after top-level execution; keep
  version-dependent calls in `init()` or guard them.

Evidence: N `lua/core/script.lua:49–60,88–89,148–264`,
`lua/core/engine.lua:89–109`, `lua/core/menu.lua:13–18,157–175`;
D `norns/reference.md:94–175`.

### Params-first control and persistence

Params are the source of truth for user-facing settings that should be
editable, mappable or recalled. Use stable collision-free IDs, suitable types,
controlspec/taper ranges, units/formatters, separators and sized groups
(groups don't nest). Namespace new reusable IDs. During refactors keep
existing IDs and option meanings, or migrate saved data. Encoders/keys set
params; param actions drive sound and derived state.

- After resources, params and actions exist, apply values with `params:bang()`,
  normally near the end of `init()`. It runs actions; it doesn't save. It
  skips trigger params and inactive trigger-behavior binaries.
- Choose a startup PSET policy: `params:read(slot, true)` plus one bang, or
  `params:default()` (read then bang), accounting for sidecar action ordering.
  A non-silent `params:read()` already runs changed-value actions.
- Keep steps, recordings and transient input state in tables. Persist
  PSET-associated extra data with `params.action_write/read/delete` and
  versioned sidecars, with defaults and migrations for absent or older data.
- `norns.state.data` is a **directory path** (normally `dust/data/<name>/`) for
  PSETs and runtime data. Recorded/generated audio goes under `_path.audio`.
- Bundled default `.pset` files may ship in code-side `data/`; core copies them
  when it first creates the data directory. Never write user saves into the
  code tree.

Evidence: N `lua/core/paramset.lua:111–315,357–425,498–610`,
`lua/core/params/control.lua:68–120`, `lua/core/script.lua:177–202`,
`lua/core/config.lua:25–29`, `lua/core/state.lua:107–170`;
D `norns/reference/parameters.md:154–404`.

### Timing, sequencing and rendering

- `clock.sync(beats)` for beat-grid work; `clock.sleep(seconds)` for delays in
  a coroutine. `clock.sync(1)` is a quarter note; `clock.sync(1/4)` a
  sixteenth. `clock.run` runs immediately until the first yield.
- Keep handles for work that can be stopped or replaced. Prevent duplicate
  transport starts, and decide continue/restart/quantization explicitly.
- Lattice is useful for coordinated divisions, swing and ordering; use
  `new_sprocket`, not deprecated `new_pattern`. Sequins produces values, not
  timing. A plain clock loop is still modern.
- `pattern_time` records seconds-based events; `reflection` records clocked
  events.
- **Metro is supported**, including UI timers and seconds-based work. Don't
  convert it mechanically to clock or confuse it with legacy BeatClock.
- For frequent changes, set dirty flags and redraw at a chosen cadence
  (15–30 fps is a sensible default). Direct redraw from an occasional input
  event is fine. Keep rendering out of high-rate musical callbacks; MIDI, poll,
  softcut and clock callbacks all run on matron's single event loop.
- **Undocumented:** global `refresh()` is called from hardware display events,
  nominally every 16.67 ms (~60 Hz). It is separate from `redraw()` and
  `screen.update()`. The SDL desktop backend produces no such events, so don't
  make it the portable default.

Evidence: N `lua/core/clock.lua:19–95`, `lua/lib/lattice.lua:18–163`,
`lua/lib/sequins.lua`, `lua/lib/pattern_time.lua`, `lua/lib/reflection.lua`,
`matron/src/events.c:179–347`, `matron/src/weaver.c:2872–2875`,
`matron/src/hardware/screen/ssd1322.c:106–125`,
`matron/src/hardware/screen/sdl.c:69–79`;
D `norns/clocks.md`, `norns/grid-recipes.md:49–84`,
`norns/reference/metro.md:100–110`, `norns/study-2.md:163–182`.

### Output and teardown

Choose engine/softcut, MIDI, crow or optional nb voices for the musical task.
nb is an external dependency, not a core output path; declare it and its
backends. Track external notes and end sounding notes/gates on stop, output
change and cleanup.

When a script is cleared, core requests engine release, runs Lua `cleanup()`,
calls mod post-cleanup hooks, then resets script globals, devices, script
metros, clocks, polls, softcut, params and other platform state.

- Stop owned work explicitly when useful, and clean up what core can't:
  external notes/processes, files, shared-table changes. Make cleanup safe
  after partial init.
- Don't send engine commands from Lua cleanup; release was already requested.
  SC resources belong in the engine's `free`.
- SLEEP runs Lua cleanup without the full `Script.clear()` sequence, another
  reason to own resources explicitly.

Evidence: N `lua/core/script.lua:11–115`, `lua/core/norns.lua:185–196`,
`lua/core/midi.lua:101–111`, `lua/core/crow/public.lua`,
`sc/core/CroneEngine.sc:42–55`; ecosystem sources in [exemplars](exemplars.md).

## Mod definition

A mod is `dust/code/<project>/lib/mod.lua`, loaded with `require` at startup
when enabled. Enabling or disabling takes effect on restart. Module locals and
returned APIs persist across script changes; script globals and facilities
reset separately. Import helpers with project-qualified paths.

Register uniquely named callbacks with `mods.hook.register(which, name, fn)`
from `require 'core/mods'`; `mods.hook.deregister` removes one (in source, not
the public guide). Callbacks run in alphabetical name order within a hook; that
says nothing about mod load order. Stable has five hooks:

| Hook | When it runs |
|---|---|
| `script_pre_init` | After script top level, before engine load and `init` |
| `script_post_init` | After a successful script `init` |
| `script_post_cleanup` | After Lua cleanup, before the remaining resets; engine teardown may still be in progress |
| `system_post_startup` | After startup, device scan and pending events; not a guaranteed pre-script barrier |
| `system_pre_shutdown` | At the start of SLEEP and RESTART |

The beta adds a sixth routing hook; see [beta compatibility](tasks/beta-compat.md).

- Optional settings pages: `mods.menu.register(name, menu_table)` with `init`,
  `deinit`, `key`, `enc`, `redraw`, plus `mods.menu.redraw/exit`. It is a
  callback table, not a parameter schema. Capture `mods.this_name` while
  loading; the loader clears it afterward.
- Common kinds are utility/system mods, nb voice providers and engine
  providers. Declare any script contract; otherwise work with any script and
  coexist with other mods.
- Restore shared changes. Script resets cancel clocks and clear callbacks and
  params even while module locals survive, so a service started in
  `script_post_cleanup` is reset immediately after.

Evidence: N `lua/core/mods.lua:13–69,81–88,111–140`,
`lua/core/hook.lua:13–41`, `lua/core/script.lua:11–115,136–140,221–238`,
`lua/core/norns.lua:185–196,253–264`, `lua/core/menu.lua:191–205`,
`matron/src/main.c:123–139`; D `norns/mods.md:24–55,104–167`.

## Engine definition

- A unique `Engine_<Name>` class extending `CroneEngine`, conventionally in
  `lib/Engine_<Name>.sc`. Crone discovers compiled subclasses by class name, not
  filename. Changed classes need recompilation (SYSTEM > RESTART).
- Allocate in `alloc`, free owned resources in `free`; the inherited
  constructor is enough. `alloc` runs in a Routine: use `context.server.sync`
  when later work depends on server operations such as sending a SynthDef.
  `.send(context.server)` and `.add` both appear in supported examples.
- Commands: `addCommand(name, format, fn)` with formats such as `i`, `f`, `s`,
  or `""`. The handler gets the raw OSC message: address at `msg[0]`, first
  argument at `msg[1]`. Document units, ranges and voice behavior.
- `addPoll(name, fn, periodic=true)` is optional. Base teardown removes
  commands and polls before calling `free`.
- Use `context.server`, `context.xg` or owned child groups, and send stereo
  output to `context.out_b`. Free owned synths, groups, buffers, buses, tasks
  and responders; never free the shared context's groups or buses.
- Namespace classes, SynthDefs and poll names. Persistent synths that are
  freed explicitly are fine; per-note synths need a bounded lifetime, often a
  self-freeing envelope. Bound polyphony and test worst-case load on hardware,
  leaving headroom for the host script. There is no universal CPU percentage.
- For reusable controls, ship `lib/<name>_engine.lua` returning specs and an
  `add_params()` whose actions call engine commands; the host decides when to
  load PSETs and bang. If interchangeable note playback is the goal, consider an
  nb voice-provider mod instead.

Evidence: N `sc/core/Crone.sc:86–129,168–180`,
`sc/core/CroneEngine.sc:15–77`, `sc/core/CroneAudioContext.sc:33–46`,
`sc/core/CronePoll.sc:117–137`, `sc/norns-config.sc:12–16`,
`sc/engines/Engine_SimplePassThru.sc:16–50`, `sc/engines/Engine_TestSine.sc`,
`lua/core/engine.lua:44–73,89–129`, `matron/src/weaver.c:1928–1991`;
D `norns/reference/engine.md:45–51`, `norns/engine-study-1.md:384–456,510–520`,
`norns/reference/poll.md:104–122`.

## Evidence and scope

Pinned sources, audited 2026-10-19:

- **N**: [monome/norns `v2.9.4`, 04c0f2f8](https://github.com/monome/norns/tree/04c0f2f8aaed275bd38081a1a63242785a3799b5)
  (2026-01-02), the source of stable update 260102.
- **D**: [monome/docs at de746029](https://github.com/monome/docs/tree/de746029ef57244036df2a206e5b894a29b5e0f6)
  (2026-10-01).

`N lua/core/script.lua:11–115` means those lines at the pinned tag;
`D norns/…` is a path in the docs tree. Beta citations use the separate **B**
pin in [beta compatibility](tasks/beta-compat.md). Lua-level APIs barely
differ between N and B; the shell, process and routing layers differ.

Evidence labels used in the guides:

- **Contract**: implementation behavior verified in source.
- **Convention**: documented platform usage, not enforced.
- **Recommendation**: this skill's preference, with exceptions.
- **Undocumented**: implemented but not in the public docs.
- **Ecosystem**: an external dependency, not a core API.

Call a pattern modern only when current core or docs support it, or when at
least two maintained scripts demonstrate it, with paths and evidence of
maintenance (a last-commit date alone isn't enough).
[Exemplars](exemplars.md) have narrow assigned purposes, not blanket style
endorsement. Where docs and source disagree, follow source and say so.

## Disagreements and open checks

- D `norns/study-3.md:857` says PSET reading doesn't run actions; N
  `lua/core/paramset.lua:527–574` does unless silent (setters may skip
  unchanged values). Follow source and the current parameter reference.
- Lattice docs say `enabled` defaults to true; source initializes false, so
  start it explicitly. LFO docs give depth default 1; N `lua/lib/lfo.lua:69–75`
  initializes 0, so set depth.
- Consecutive syncs advance from the stored scheduled beat, so late callbacks
  can catch up: N `matron/src/clocks/clock_scheduler.c:158–183`, tested in
  `tests/matron/clocks/clock_scheduler/test_clock_scheduler.cpp:223–260`.
  Older firmware may differ.
- `refresh()` is in source and used by plasma but undocumented; its behavior
  on other backends needs checking.
- No hardware run on an unmodified stable image exists yet. The recorded
  Pi 3 run used a modified 3.x beta and is summarized in
  [beta compatibility](tasks/beta-compat.md#hardware-observations-on-a-beta-device).
