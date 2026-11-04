# MIDI and note-output ownership

Apply the [output definition](../modern.md#output-and-teardown). A script may
use direct engines, MIDI, crow or optional nb players. Pick the interface for
the instrument; nb isn't a core prerequisite. Evidence uses the
[pinned N/D sources](../modern.md#evidence-and-scope).

## MIDI ports and parsing

`midi.connect(index)` returns a virtual-port table, not a newly opened private
device. Its `.event` callback receives bytes; `midi.to_msg(data)` parses them,
including note-on velocity zero as note-off. Use `:note_on(note, velocity, ch)`
and `:note_off(note, velocity, ch)` for output. MIDI values use 0–127 velocity;
don't confuse this with a normalized nb velocity. Core clears event handlers
on script clearing but does not end notes already sounding on external hardware.

Use built-in PMAP for ordinary CC-to-param controls. `midi.add/remove` are
assignable script callbacks; replacing MIDI implementations or another owner's
callback needs composition/restoration. Don't assume vport 1 is the same physical
device across setups; inspect `.name` and test hotplug/output changes.

Evidence: N `lua/core/midi.lua:17–39,74–111,190–209,271–292,439–475`;
D `norns/reference/midi.md`, `norns/reference/parameters.md:267–288`.

## Note-off bookkeeping

Keep an owned sounding-note record, send its note-offs once, then clear it.
Use a monotonic sequence tick/deadline rather than comparing wrapped pattern
positions when notes may cross the loop boundary. This fragment assumes each
track's notes have an explicit retrigger policy and independent output ownership:

```lua
local sounding = {}

local function end_note(track)
  local current = sounding[track]
  if not current then return end
  for _, note in ipairs(current.notes) do
    current.port:note_off(note, 0, current.channel)
  end
  sounding[track] = nil
end

local function start_note(track, port, notes, velocity, channel, end_tick)
  end_note(track)
  local owned_notes = {}
  for i, note in ipairs(notes) do
    owned_notes[i] = note -- don't retain a mutable chord table
    port:note_on(note, velocity, channel)
  end
  sounding[track] = {
    port = port, notes = owned_notes, channel = channel, end_tick = end_tick
  }
end

local function release_due(tick)
  for track, current in pairs(sounding) do
    if tick >= current.end_tick then end_note(track) end
  end
end
```

On stop/cleanup end every owned note before discarding records. On output or
channel change release notes on their **original** port/channel. If multiple
tracks share the same `(port, channel, note)`, define whether retriggers overlap,
steal or reference-count; one track's note-off can end another's note. MIDI
doesn't identify independent same-pitch voices. Don't change that policy silently.

Avoid sending a note-off every subsequent tick or overwriting an active record
before ending its notes. Saturation can delay control work; measure the actual
port/backend rather than assuming every MIDI call blocks. An all-notes-off CC
can be a supplemental panic operation, not a replacement for normal ownership.

This is an application bookkeeping recommendation using N
`lua/core/midi.lua:101–119`; compare [timing](timing.md) and
[performance measurement](../tasks/optimize.md).

## Optional nb integration

Pin/declare the external [sixolet/nb](../exemplars.md#optional-nb-interface)
dependency and required voice mods. For the audited submodule layout
`lib/nb/lib/nb.lua`, the setup is:

```lua
local nb = include('lib/nb/lib/nb')

local function add_voice_params()
  nb:init()
  nb:add_param('my_script_voice', 'voice')
  nb:add_player_params()
end

local function play_note(note, velocity, length_beats)
  local player = params:lookup_param('my_script_voice'):get_player()
  player:play_note(note, velocity, length_beats)
end
```

The host calls setup during init, before its final bang/recall policy. At the
audited revision, nb adds parameter definitions for all registered players.
`play_note`'s base implementation converts beats to seconds once, then schedules
note-off with sleep; a tempo change during the note doesn't retroactively change
that duration. Velocity is normalized in the audited MIDI adapter. Check the
selected backend's actual capabilities and any overrides.

Selection uses `active`, `delayed_active` and `inactive` callbacks/refcounts.
`nb:stop_all()` is intended for PSET loading, but base `stop_all` is a no-op;
don't assume every backend provides a panic. For held notes and cleanup, retain
the original player identity and explicitly verify release/selection behavior.
Coordinate this with the host's single PSET hook slots rather than replacing
another library's hooks. Voice changes while sounding are a lifecycle change.

Ecosystem evidence: `sixolet/nb@400e0b38` `README.md`,
`lib/nb.lua:110–174,192–218`, `lib/player.lua:84–148`; registration example
`sonocircuit/nb_plyprc@eb9ea921` `lib/mod.lua:187–205`.
These are external contracts, not norns core APIs.

## Verifying notes without hardware

In a scoped harness, replace vport send methods while preserving originals:

```lua
local port = midi.vports[1]
local original_on, original_off = port.note_on, port.note_off
local events = {}
port.note_on = function(_, note, velocity, channel)
  events[#events + 1] = {'on', note, velocity, channel}
end
port.note_off = function(_, note, velocity, channel)
  events[#events + 1] = {'off', note, velocity, channel}
end
-- Exercise the step/stop/output-change paths inside protected test execution.
-- Restore on success AND failure:
port.note_on, port.note_off = original_on, original_off
```

These methods are fields on each vport, not inherited class methods: assigning
nil deletes them. Check notes/chords, overlap, wrap, stop, output changes and
partial cleanup; then test actual device timing separately. For generated chords,
`musicutil.generate_chord` allocates a table and nil chord type selects Major;
memoize measured hot paths by actual inputs, preserving the UI's chord mapping.

Evidence: N `lua/core/midi.lua:17–39`, `lua/lib/musicutil.lua`
(`generate_chord`); D `norns/reference/lib/musicutil.md`.
