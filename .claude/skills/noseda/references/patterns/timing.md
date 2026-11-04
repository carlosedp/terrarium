# Timing, transport and sequencing

Apply the [timing definition](../modern.md#timing-sequencing-and-rendering).
Distinguish musical policy from API semantics before changing a legacy clock.
Evidence below uses [N/D](../modern.md#evidence-and-scope).

## Choose the time domain

| Mechanism | Use |
|---|---|
| `clock.sync(beats, offset)` | Musical beat-grid scheduling, following selected source |
| `clock.sleep(seconds)` | Delays inside a clock coroutine; convenient UI polling |
| `metro` | Regular seconds-based callbacks, independent of musical tempo |
| lattice | Multiple clocked divisions, swing, delay and ordering |
| sequins | Value sequence generation; no scheduler of its own |
| `pattern_time` / `reflection` | Seconds-based / clocked event recording and playback |

Metro is not deprecated. Repeated sleep periods include execution/dispatch
overhead; metro maintains a regular seconds schedule. Choose according to the
task rather than rewriting working seconds-based UI timing. Old `beatclock`
is a different library, superseded for musical synchronization by `clock`.

Evidence: N `lua/core/clock.lua:19–56`, `matron/src/metro.c:219–237`,
`matron/src/clocks/clock_scheduler.c:193–204`, `lua/lib/pattern_time.lua`,
`lua/lib/reflection.lua`; D `norns/reference/metro.md:100–110`,
`norns/reference.md` (libraries), `norns/clocks.md`.

## Units and coroutine ownership

`clock.run(fn, ...)` returns a numeric handle, immediately resuming the function
until its first yield/return. Initialize dependencies first. Sleep/sync must be
inside such a coroutine, not called directly in an ordinary key/MIDI callback.
Natural successful completion cancels its handle; retain handles for work that
can be stopped or replaced. Core cleanup cancels remaining script clocks.

| Interval | `clock.sync` (quarter-note beats) | lattice `division` (whole-note fraction) |
|---|---|---|
| Quarter note | `1` | `1/4` |
| Eighth note | `1/2` | `1/8` |
| Sixteenth note | `1/4` | `1/16` |
| Four quarter-note beats | `4` | `1` |

Evidence: N `lua/core/clock.lua:19–95`, `lua/lib/lattice.lua:89–110`;
D `norns/clocks.md:48–139`.

## Transport is a musical policy

Assign `clock.transport.start` and `.stop` to your handlers. They are optional
callbacks; calling one yourself doesn't reset the underlying clock. A stop
notification doesn't automatically stop your sequence. Core clears them on
script cleanup.

- Guard repeated starts so each doesn't create another running coroutine.
- Decide immediate versus quantized first note. Leading `clock.sync(4)` waits
  for a four-beat grid, not a detected musical bar in any meter/source.
- Decide whether stop/play continues or restarts, and whether reset affects
  only sequence position or also requests a shared clock reset.
- A leading wait delays the first step; stepping before the first wait is an
  intentional alternative. Don't add waits accidentally at pattern boundaries.
- MIDI start, Link start-stop sync, internal clock reset and crow pulses have
  different semantics. Crow pulses don't identify bar downbeats or supply this
  implementation's transport-start event. Test the selected sources explicitly.
- End pending external notes/gates on stop before discarding their records.

See the [script skeleton](../components/script.md#minimal-runnable-instrument)
for idempotent start/stop. Evidence: N `lua/core/clock.lua:85–95,129–158,198–207`,
`matron/src/clocks/clock_midi.c:31–84`, `clock_link.c:42–69`,
`clock_crow.c:37–75`, `clock_internal.c:111–123,179–184` (all under
`matron/src/clocks/`); D `norns/clocks.md:235–302`.

## Lattice and event libraries

Create a lattice, add current sprockets, then explicitly start it after actions
can safely run. The first automatic pulse happens before its first sync, so
arrange quantized startup separately if required. This factory fragment accepts
an initialized musical step function:

```lua
local lattice = require 'lattice'
local s = require 'sequins'

local function make_sequence(step)
  local values = s{60, 63, 67, 70}
  local timing = lattice:new()
  timing:new_sprocket{
    division = 1/16,
    action = function() step(values()) end
  }
  return timing -- host calls :start() after initialization
end
```

`:stop()` disables pulse processing but leaves the superclock alive; `:destroy()`
cancels it. Destroy at the end of ownership, then create a fresh instance if
needed later. `new_pattern` and `set_meter` are deprecated. Library LFOs are
control modulation, not audio oscillators; specify depth explicitly, and use
parameter actions when modulating a user-facing setting.

For event recording choose `pattern_time` when preserving seconds-based timing,
or `reflection` when beat-based recording/quantization is intended. A replacement
can change performance timing, so migrate recorded data/behavior deliberately.

Evidence: N `lua/lib/lattice.lua:18–94,133–164`, `lua/lib/sequins.lua`,
`lua/lib/lfo.lua:49–112,287–355`, `lua/lib/pattern_time.lua`,
`lua/lib/reflection.lua`; D `norns/reference/lib/lattice.md`,
`norns/reference/lib/lfo.md`, `norns/reference/lib/reflection.md`.

## Scheduler behavior and diagnosis

In the audited implementation, consecutive syncs advance from the coroutine's
stored scheduled beat. Delayed execution can therefore be late and then catch
up. There is one outstanding scheduler entry per coroutine, not a prequeued
unbounded list of ticks. Switching from sleep to sync schedules from current
beats. Verify older firmware rather than asserting all versions skip lateness.

An extra same-quantum sync after 256 stepped waits adds a 257th wait without a
step. That changes the intended rate. Callback delivery is not exactly on a
boundary: scheduler polling and matron dispatch add latency. Count steps **and**
compare against intended beat times; see [performance work](../tasks/optimize.md).

Cancellation clears the scheduler entry and Lua thread, but cannot retract an
already posted resume event in this implementation. A stale event can reach a
missing thread. Investigate invalid handles/duplicate starts/lifecycle mistakes
before attributing an error to that race; don't dismiss every resume error as
harmless.

Evidence: N `matron/src/clocks/clock_scheduler.c:37–54,99–121,158–225`,
`lua/core/clock.lua:35–38,59–79`, `matron/src/events.c:213–215`,
`tests/matron/clocks/clock_scheduler/test_clock_scheduler.cpp:223–276`.
