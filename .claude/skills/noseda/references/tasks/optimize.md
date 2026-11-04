# Performance work on norns

Apply the [modern definitions](../modern.md) and measure the actual bottleneck.
Preserve musical behavior unless a change is intentional. Use
[debugging](debug.md) for reaching the device and the [review checklist](review.md)
for compatibility risks. Evidence below uses [N/D](../modern.md#evidence-and-scope).

## Establish a comparable target

Record device, update number, backend, sample rate/buffer configuration,
mods, dependencies, tempo/source, seed, pattern and revision. Keep firmware
fixed across comparisons.

Use real norns hardware for timing/audio headroom. Desktop checks correctness
and can locate relative costs, but its CPU doesn't establish Pi performance.
Measure idle, realistic playing, and an explicitly described worst case.

## Measure several signals together

- **Work duration:** use `util.time()` around a musical step or other hot path.
  Report average, tail percentiles, max and counts over budget. At B BPM and N
  ticks per quarter-note beat, interval is `60 / B / N` seconds (3.906 ms at
  120 BPM / 128 PPQN). That interval isn't exclusively available to Lua: other
  control callbacks and audio work need headroom too.
- **Count and intended-beat lateness:** current consecutive syncs preserve
  scheduled targets and can catch up after delays. Count steps and compare
  actual callback times/beats with the intended timeline. A correct final
  count can hide bunched late events. If tempo changes, use beat deltas rather
  than a fixed `seconds × BPM` expectation. Older firmware needs verification.
- **Xruns:** inspect JACK logs and, in a version-scoped diagnostic harness,
  `_norns.audio_get_xrun_count()`. This internal binding returns and resets the
  counter. Other readers, including the home stats display, can consume it.
  Keep competing readers out of a measurement or record their interference.
- **DSP load:** internal `_norns.audio_get_cpu_load()` exposes JACK CPU load,
  not just the custom engine's CPU. Observe engine/server statistics alongside
  it when identifying a culprit.
- **Memory/allocation:** `collectgarbage('count')` gives Lua allocation size,
  not complete process or SC buffer memory. Table churn can add GC work.
- **Idle baseline:** compare stopped versus playing to distinguish persistent
  effects/voices from event-rate cost.

Evidence: N `lua/lib/util.lua:14–19`,
`matron/src/clocks/clock_scheduler.c:99–121,158–204`,
`matron/src/weaver.c:2211–2218`, `matron/src/jack_client.c:24–28,54–61`,
`lua/core/menu/home.lua` (stats readers). The `_norns` metrics are source-level
diagnostics, not a public production-script dependency. Scheduler tests:
`tests/matron/clocks/clock_scheduler/test_clock_scheduler.cpp:223–260`.

## A fair before/after comparison

1. Keep target, musical material, tempo/source, note duration and test duration
   fixed. Seed generated patterns. State any deliberate behavior changes.
2. Reload the component and establish a consistent baseline. Restart processes
   only when needed to remove persistent state; use the same policy for every
   revision, and don't restart someone else's active session silently.
3. Warm up consistently; interleave/repeat comparisons when drift or noisy
   conditions matter. Record results against commit hash/build and conditions.
4. Compare note/event counts, lateness, xruns and sound together. A version that
   plays fewer notes can report lower DSP load while doing the wrong work.
5. Change one suspected cost at a time. Stop once the relevant checks support
   the improvement; broad stress reruns need a concrete unresolved concern.

## Likely costs to investigate

### Lua/control

- Repeated MIDI/OSC/engine messages that don't change musical state. In
  particular, clear note-off ownership after sending once. Inspect the actual
  transport before claiming blocking or a fixed maximum message rate.
- Tables repeatedly built in hot paths. `musicutil.generate_chord()` constructs
  a new result; cache by real inputs if measurement justifies it. Include data
  changes from rules, recording, PSETs and inherited settings in invalidation.
- Params lookups/actions in tight loops. Cache derived values through actions
  when useful; don't create a second source of truth. `params:set` may execute
  its action when changed and non-silent, potentially sending more commands.
- Redraw/disk/subprocess work on the musical event path. Use dirty rendering,
  explicit save snapshots and the appropriate time domain. Keep obligatory
  note-offs even when skipping idle/muted-track work.

Evidence: N `lua/core/midi.lua:86–111`, `lua/core/paramset.lua:357–417`,
`lua/core/params/control.lua:74–97`, `lua/lib/musicutil.lua` (`generate_chord`),
`lua/core/engine.lua:60–73`; D `norns/grid-recipes.md`, `norns/clocks.md`.

### Audio/SC

- Persistent effect chains and upfront voices have idle cost. Isolate them one
  at a time, preserving gain/routing when comparing.
- Unbounded polyphony, buffers, tasks or nodes left behind after voice stealing,
  engine switching or reload. A persistent synth can be intentional; absence of
  `doneAction: 2` is not itself a leak if ownership/free is correct.
- Large bursts caused by late catch-up events. A control scheduler overload can
  increase instantaneous audio work even with the intended total note count.
- Unsupported “UGen A is always faster” or “.ar fixes aliasing” substitutions.
  Compare the actual synthesis, release tails and resulting sound.

Evidence for ownership: N `sc/core/CroneEngine.sc:42–55`,
`sc/engines/Engine_TestSine.sc`, `sc/engines/Engine_PolyPerc.sc:18–28,57–59`.
These are measurement hypotheses, not asserted universal performance results.

## Instrumentation and reporting

Keep instrumentation scoped and restore wrappers on failure as well as success.
If shipping a profiling mode, expose its settings through params and keep its
disabled cost small. Write reports under `norns.state.data` after measurement,
not on every timing tick. Compare instrumentation overhead with an idle control.
See [debugging](debug.md#scoped-testing-and-diagnostics) for wrapper lifetime.

Offline Lua can load pure libraries for deterministic behavior and relative-cost
experiments. Stub required host primitives explicitly; `util.time()` requires
`_norns.get_time` and isn't an offline timer by itself. Report offline versus
device results separately.
