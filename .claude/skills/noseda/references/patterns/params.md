# Params-first controls

Follow the [script definition](../modern.md#params-first-control-and-persistence).
API evidence uses the [N/D source baseline](../modern.md#evidence-and-scope).

## Stable IDs, groups and menu integration

- Use stable IDs and user-facing display names. Prefix new reusable-library/mod
  IDs to avoid collisions, including separators/groups. Do not rename legacy
  IDs merely for consistency: PSETs and PMAPs refer to those IDs.
- `params:add_separator(id, name)` with one argument uses it as the ID/name.
  System names like `REVERB` and `COMPRESSOR` already identify groups. Prefer
  `params:add_separator('my_script_reverb', 'REVERB')`.
- `params:add_group(id, name, n)` contains the next `n` parameter entries,
  including separators. Count conditional additions. Groups cannot nest.
  Grouping existing controls need not change their IDs or saved values.
- Use `add_number/option/control/taper/file/text/binary/trigger` according to
  the control's meaning. Ranges, controlspec units/warp/quantum and formatters
  should match the sound and encoder behavior; a formatter receives the param
  object, not its numeric value.
- Dynamic `params:hide/show(id)` may need `_menu.rebuild_params()`. This is a
  documented narrow use of `_menu`, not permission to manipulate menu internals.

Evidence: N `lua/core/paramset.lua:111–315,454–471`,
`lua/core/params/control.lua:128–137`, `lua/core/params/number.lua:72–78`,
`lua/core/menu/params.lua:49–67,697–708`;
D `norns/reference/parameters.md:24–73,154–265`.

## Actions own settings and derived state

UI controls call `params:set`/`params:delta`; actions update the sound and any
derived caches. Don't update a cache independently from MIDI/PSET/menu paths.
Use the existing `clock_tempo` parameter rather than adding a competing tempo
or assigning a nonexistent `clock.tempo` control. Preserve its system action;
use `clock.tempo_change_handler` for supported tempo notifications when needed.

```lua
local output_enabled = false -- derived cache, not an independent setting

local function add_output_param()
  params:add_option('my_script_output', 'output', {'off', 'on'}, 1)
  params:set_action('my_script_output', function(value)
    output_enabled = value == 2
  end)
end
```

After resources and actions exist, `params:bang()` applies initial values.
Ordinary setters run actions on value changes; silent setters suppress them.
A silent PSET read therefore needs a deliberate later application step. Don't
assume a read always runs every action, or call a full bang for every tick.
Reusable `add_params()` functions should let the host decide startup/recall.

Evidence: N `lua/core/paramset.lua:357–417,527–610`,
`lua/core/params/number.lua:35–69`, `lua/core/params/control.lua:68–120`,
`lua/core/clock.lua:141–145,228–239`;
D `norns/reference/parameters.md:45–61`, `norns/reference/clock.md`.

## PMAP and persistence

Parameter control values can use the built-in mapping UI instead of a parallel
MIDI-learn implementation. Not all param types are mappable; check the type's
`allow_pmap` contract. PMAP is stored separately from PSETs, under the script's
data directory. Preserve IDs, ranges and option ordering to maintain meaning.
Changes to them require compatibility analysis, not just a syntax check.
See [state patterns](state.md) for startup PSETs, hooks and sidecar data.

Evidence: N `lua/core/pmap.lua:61–108`, `lua/core/menu/params.lua:209–255,710–758`,
`lua/core/paramset.lua:443–449`; D `norns/reference/parameters.md:267–288`.

## Dependencies

Use shipped libraries directly. For script helpers use `include`, which runs
the file and returns its result. Missing includes raise `MISSING INCLUDE`.
For an explicitly optional cross-project dependency, check for it before loading:

```lua
local helper
if util.file_exists(_path.code .. 'other_project/lib/helper.lua') then
  helper = include('other_project/lib/helper')
end
```

Only expose the optional feature when its contract is available. Missing is
different from present-but-broken: don't silently swallow arbitrary load errors.
Declare required dependencies and install instructions. `require` caches a
module; choose that lifetime intentionally, especially for mod helpers. Check
licensing before copying third-party code.

Evidence: N `lua/core/startup.lua:48–62`, `lua/core/config.lua:6–16`,
`lua/lib/util.lua` (`file_exists`); D `norns/reference.md` (libraries),
`norns/mods.md:145–167`.

## Checks

Look for `collides`, `ID collision` and `clobbering` in load output. Test setting
values from encoders, PARAMS, mapped MIDI and PSET recall. Verify group counts,
formatters, silent-read initialization and legacy presets. Scope test wrappers
and restore their originals; details are in [debugging](../tasks/debug.md).
