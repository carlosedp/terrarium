# Script development

Apply the [modern script definition](../modern.md#script-definition). This guide
is for construction; use the [review checklist](../tasks/review.md) for legacy
code. A script may also ship a [mod](mod.md) or [engine](engine.md).

## Layout and lifetime

```text
dust/code/my_script/
├── my_script.lua            # conventional main entry point
├── lib/                     # optional helpers, engines
└── README.md
dust/data/my_script/         # runtime PSETs/state: norns.state.data
dust/audio/my_script/        # generated/recorded audio: under _path.audio
```

Matching entry filename and folder is recommended, not enforced. A code-side
`data/` may distribute default PSETs; it is not the runtime save destination.
Core creates `norns.state.data` before executing the script. Define global
callbacks at script scope; use locals or script globals for application state
according to complexity, without shadowing system bindings.

Core supplies no-op initialization/input/cleanup and blank redraw defaults.
Omitting cleanup does not disable platform resets, but it won't end external
notes or undo arbitrary shared mutations. Omitting redraw gives no custom
screen interface. The loader captures redraw/refresh before init and loads the
selected engine before invoking init. Don't call a captured local renderer from
a background timer: use global `redraw()` so menu suppression works.

Evidence: N `lua/core/script.lua:11–115,148–238`, `lua/core/menu.lua:13–18,157–175`;
D `norns/reference.md:94–175`, `norns/reference/parameters.md:362–404`.
N/D refer to the [pinned sources](../modern.md#evidence-and-scope).

## Minimal runnable instrument

Save this as `dust/code/modern_steps/modern_steps.lua`. It uses the shipped
PolyPerc engine, stable params, a beat-synced sequins pattern, explicit transport
ownership, and dirty screen rendering. PSET saving/recall works through PARAMS;
startup deliberately uses defaults. It needs no grid, external mod or nb library.
No arbitrary minimum firmware number is asserted; verify one before requiring it.

```lua
-- modern_steps: four-note instrument
-- v1.0.0 @yourname
-- https://monome.org/docs/norns/clocks/
-- K2: reset notes; K3: play/stop
-- E2: root note; E3: amplitude

engine.name = 'PolyPerc'
local musicutil = require 'musicutil'
local s = require 'sequins'

local notes = s{0, 3, 7, 10}
local root = 48
local running = false
local dirty = true
local sequence_clock, ui_clock

local function stop()
  running = false
  if sequence_clock then
    clock.cancel(sequence_clock)
    sequence_clock = nil
  end
  dirty = true
end

local function start()
  if sequence_clock then return end
  running = true
  sequence_clock = clock.run(function()
    while true do
      clock.sync(1/4) -- sixteenth notes; first note waits for this grid
      engine.hz(musicutil.note_num_to_freq(root + notes()))
      dirty = true
    end
  end)
  dirty = true
end

function init()
  params:add_group('modern_steps', 'modern steps', 2)
  params:add_number('modern_steps_root', 'root note', 24, 84, 48)
  params:set_action('modern_steps_root', function(value)
    root = value
    dirty = true
  end)
  params:add_control('modern_steps_amp', 'amplitude',
    controlspec.new(0, 0.5, 'lin', 0, 0.15))
  params:set_action('modern_steps_amp', function(value)
    engine.amp(value)
    dirty = true
  end)
  ui_clock = clock.run(function()
    while true do
      clock.sleep(1/15)
      if dirty then
        redraw()
        dirty = false
      end
    end
  end)
  clock.transport.start = start -- these don't reset the underlying clock
  clock.transport.stop = stop
  params:bang()
end

function enc(n, d)
  if n == 2 then params:delta('modern_steps_root', d)
  elseif n == 3 then params:delta('modern_steps_amp', d) end
end

function key(n, z)
  if z ~= 1 then return end
  if n == 2 then notes:reset(); dirty = true
  elseif n == 3 then
    if running then stop() else start() end
  end
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(8, 20)
  screen.text(running and 'playing' or 'stopped')
  screen.move(8, 36)
  screen.text('root: ' .. params:string('modern_steps_root'))
  screen.move(8, 52)
  screen.text('amp: ' .. params:string('modern_steps_amp'))
  screen.update()
end

function cleanup()
  stop()
  if ui_clock then clock.cancel(ui_clock); ui_clock = nil end
end
```

PolyPerc notes have self-freeing envelopes: stop prevents new notes but leaves
the short existing tail. A sustained MIDI/crow/nb instrument instead needs
explicit note/gate release. K2 resets only note order; play continues from it.
These are musical policies, not consequences to silently change in a refactor.

Evidence: N `sc/engines/Engine_PolyPerc.sc:18–40`, `lua/core/clock.lua:19–95`,
`lua/core/paramset.lua:218–238,306–315,411–417,604–610`,
`lua/lib/sequins.lua`, `lua/lib/musicutil.lua`, `lua/core/screen.lua`;
D `norns/clocks.md:273–318`, `norns/grid-recipes.md:49–84`.

## Helpers and extension points

A script-local helper can return a table rather than inject globals:

```lua
-- lib/note_tools.lua
local NoteTools = {}
function NoteTools.transpose(note, semitones)
  return note + semitones
end
return NoteTools
```

Load it with `local note_tools = include('lib/note_tools')`. Don't use bare
`require 'lib/note_tools'` expecting script-relative resolution. Shared modules
can use a project-qualified require when cached lifetime is intentional.
Evidence: N `lua/core/startup.lua:48–62`, `lua/core/config.lua:6–16`;
D `norns/reference.md` (local and third-party libraries).

Read the relevant patterns instead of building ad hoc subsystems:

- [Params](../patterns/params.md): actions, cached state, stable IDs and PMAP.
- [State](../patterns/state.md): startup PSET policy, sidecars and migration.
- [Timing](../patterns/timing.md): lattice, recording and transport policy.
- [UI](../patterns/ui.md): metro/clock redraws, refresh and modal input.
- [MIDI/output](../patterns/midi.md): external notes and optional nb players.

## Acceptance checks

- Load, rerun, and switch to another script without errors.
- Repeated start doesn't duplicate clocks; stop and reset do what the header says.
- Encoders, PARAMS, PMAP and PSET load update the same settings and sound.
- Open/close the menu while running; script drawing respects screen ownership.
- Runtime saves use `norns.state.data`; old PSETs survive a refactor.
- External notes end on stop/output changes/cleanup; partial init is safe.
- Measure timing/audio on the supported hardware and release, not just desktop.
