# State and persistence

Apply the [persistence definition](../modern.md#params-first-control-and-persistence).
Separate settings (params), musical data (tables/recordings), transient runtime
state (held keys, clock handles, active notes), and system state. Don't serialize
running resources as if they could be restored from disk.

## Paths and startup policy

`norns.state.data` is a path established by core, normally
`~/dust/data/<project>/`; multi-entry projects can have an additional script
segment. Numeric PSET writes use that directory plus the script shortname.
Use `_path.audio` with a project subdirectory for generated/recorded audio.
Create any extra directories deliberately; don't hardcode `/home/we` paths.

Startup defaults and automatic recall are different policies:

| Policy | After params, actions, resources and hooks are ready |
|---|---|
| Fresh parameter defaults | `params:bang()` near end of init |
| Last-used PSET, then apply once | `params:read(nil, true)` followed by `params:bang()` |
| Documented default helper | `params:default()` reads then bangs; changed-value actions may run twice |

Ordinary `params:read(slot)` applies changed-value actions while reading, then
calls `params.action_read`. Silent reading passes the silent flag to that hook;
the hook must honor any desired silent semantics itself. Decide whether sidecar
data must exist before those actions, or whether actions require a guarded
staging/commit phase. Don't let one parameter's action depend on an unspecified
bang ordering. A read of a missing PSET logs a message and doesn't call the hook.

The menu records the last PSET slot in `pset-last.txt` on save/load; runtime
params aren't automatically persisted on exit. Code-side `data/*.pset` files
are distributable defaults copied on first creation of the runtime directory,
not a destination for user saves.

Evidence: N `lua/core/script.lua:156–202`, `lua/core/paramset.lua:498–610`,
`lua/core/menu/params.lua:103–120,274–280`, `lua/core/config.lua:25–29`;
D `norns/reference/parameters.md:267–404`, `norns/reference.md:205–222`.
Source revisions are in [modern.md](../modern.md#evidence-and-scope).

## PSET-associated tables

The hook signatures are:

```text
params.action_write(filename, name, pset_number)
params.action_read(filename, silent, pset_number)
params.action_delete(filename, name, pset_number)
```

Each is one callback slot: the host should coordinate libraries that need it.
For write/read, `pset_number` is set for numeric-slot calls, but may be nil for
explicit filenames. Delete's number is supplied by the caller; don't assume
it is always present. A sidecar derived from `filename` avoids dependence on
that optional number. Normal numeric/menu PSETs are already in script data;
validate custom paths if your UI accepts arbitrary filenames.

This fragment belongs in the host's setup, before any startup PSET read. It
shows a schema/default policy; integrate with the actual sequencer when replacing
`steps`, and stop sounding notes before replacing active musical data.

```lua
local function default_steps() return {60, 64, 67, 72} end
local steps = default_steps()

local function install_pset_hooks()
  params.action_write = function(filename)
    local err = tab.save({schema = 1, steps = steps}, filename .. '.state')
    if err then print('state write failed: ' .. err) end
  end
  params.action_read = function(filename, silent)
    local ok, saved = pcall(tab.load, filename .. '.state')
    if ok and type(saved) == 'table' and saved.schema == 1
        and type(saved.steps) == 'table' then
      steps = saved.steps -- validate note ranges/shape for your instrument
    else
      steps = default_steps() -- deterministic behavior for absent/old data
      print('state missing or unsupported; using default steps')
    end
    -- Rebind sequins/playback data here; don't start transport on a read.
    -- Honor `silent` if this hook has audible or external side effects.
  end
  params.action_delete = function(filename)
    os.remove(filename .. '.state') -- only this PSET's owned sidecar
  end
end
```

`tab.save/load` handle table data but not live functions, metatables or userdata.
They are not a serializer for a complete lattice/sequins/player instance. Check
errors and save plain data that can reconstruct those objects. `tab.load` loads
a Lua representation; this example is for the component's own saved tables.

Evidence: N `lua/core/paramset.lua:518–519,572–594`,
`lua/lib/tabutil.lua:102–215`; D `norns/reference/parameters.md:267–360`,
`norns/reference/lib/tabutil.md`.

## Compatibility and session boundaries

- Keep IDs, option meanings and units stable. If changing them, migrate old
  PSET/PMAP/data deliberately; keep fixture copies for verification.
- Version sidecar schemas. Validate loaded shape/ranges and define missing-file
  behavior instead of retaining arbitrary data from the previous session.
- A change from code-folder saves to `norns.state.data` needs a one-time import
  policy. Read existing user data before removing or overwriting anything.
- Decide whether a “session” includes audio, external device settings and pattern
  recordings. A PSET of scalars alone cannot recreate an entire sampler session.
- Avoid disk work in timing callbacks. For expensive session saves, define a
  snapshot/commit policy so playback doesn't mutate tables mid-save. Multi-file
  PSET plus sidecar writes are not automatically transactional.
- Undo/redo and cross-script session managers are application designs, not
  provided by these three hooks. Keep their roadmap items separate.

Test fresh load, modified defaults, startup recall, manual read/write/delete,
missing/corrupt/older sidecars and repeated recalls while running, on the
actual target build.
