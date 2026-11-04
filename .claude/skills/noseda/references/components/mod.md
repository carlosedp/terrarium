# Mod development

Apply the [modern mod definition](../modern.md#mod-definition). Mods are
process-lifetime extensions with script-lifecycle responsibilities. Utility
mods, nb voice providers and engine providers have different responsibilities;
name the intended contract before choosing hooks.

## Entry point and imports

```text
dust/code/my_mod/
├── lib/
│   ├── mod.lua
│   └── helper.lua          # optional
└── README.md
```

Core discovers `*/lib/mod.lua`; enabled modules load through `require` at
startup. Use `local mods = require 'core/mods'`. Import helpers with
`require 'my_mod/lib/helper'`, not `include('lib/helper')`, whose first search
location belongs to the active script. Capture `mods.this_name` at module load
if needed later; it is cleared when loading finishes. Return a local API table
when scripts need access via `require 'my_mod/lib/mod'`.

Evidence: N `lua/core/mods.lua:13–58`, `lua/core/startup.lua:48–62,123–126`,
`lua/core/config.lua:6–16`; D `norns/mods.md:145–167`.
N/D use the [source baseline](../modern.md#evidence-and-scope).

## Minimal runnable mod with optional menu

Save as `dust/code/modern_counter/lib/mod.lua`, enable under SYSTEM > MODS and
restart. It counts script initializations, with a menu toggle for logging.
Settings are session-only; it does not mutate an active script's controls.

```lua
-- modern_counter: example utility mod
local mods = require 'core/mods'
local mod_name = mods.this_name
local starts = 0
local logging = true

mods.hook.register('script_post_init', mod_name .. ':count', function()
  starts = starts + 1
  if logging then print(mod_name .. ': script starts = ' .. starts) end
end)

local menu = {}
function menu.init() end
function menu.deinit() end

function menu.key(n, z)
  if n == 2 and z == 1 then mods.menu.exit() end
end

function menu.enc(n, d)
  if n == 3 and d ~= 0 then
    logging = d > 0
    mods.menu.redraw()
  end
end

function menu.redraw()
  screen.clear()
  screen.level(15)
  screen.move(8, 20)
  screen.text('script starts: ' .. starts)
  screen.move(8, 36)
  screen.text('logging: ' .. (logging and 'on' or 'off'))
  screen.move(8, 52)
  screen.text('E3: logging / K2: back')
  screen.update()
end

mods.menu.register(mod_name, menu)

local Counter = {}
function Counter.get_count() return starts end
return Counter
```

The registered value is a **menu callback table**, not a function returning
parameter descriptors. No special mod `init()` method or installation guard is
required. The count survives script changes because it is a module local. This
example owns no timer/process/notes requiring teardown. Enable/disable takes
effect on restart; it is not a hot-unload interface.

Evidence: N `lua/core/mods.lua:52–58,81–88,111–140`,
`lua/core/menu.lua:191–205`, `lua/core/menu/mods.lua:18–25,78–85`;
D `norns/mods.md:104–167`.

## Hooks and actual ordering

Use `mods.hook.register(which, unique_name, fn)` and
source-supported `mods.hook.deregister(which, unique_name)` (not described in
the inspected public mod guide). Reusing a callback name replaces
that registration; names run alphabetically within a hook. Mod loading itself
does not promise alphabetical order.

| Hook | Use / ordering |
|---|---|
| `script_pre_init` | Prepare per-script interfaces after top level, before engine load/init |
| `script_post_init` | Augment a successfully initialized script |
| `script_post_cleanup` | Release per-script mod ownership, before core resets |
| `system_post_startup` | System startup work; don't assume a strict before-script barrier |
| `system_pre_shutdown` | Release/save process-lifetime work for SLEEP and RESTART |

There is no `script_pre_cleanup` hook. Script post-cleanup does not guarantee
the asynchronous SC teardown has finished, and SLEEP does not run that hook.
The 3.x beta adds an audio-routing hook; see [beta compatibility](../tasks/beta-compat.md).

Evidence: N `lua/core/hook.lua:13–41`, `lua/core/script.lua:11–24,136–140,221–238`,
`lua/core/norns.lua:185–196,253–264`, `matron/src/main.c:123–139`; D `norns/mods.md:28–38`.

## Ownership and coexistence

- Keep module state separate from state for the active script. Reinitialize
  per-script resources at the proper hook; don't capture old script callbacks
  forever in a cached module.
- Core clearing cancels clocks, frees script metros and resets callbacks,
  polls and params even when a mod started them. A service started in
  `script_post_cleanup` may immediately be reset. Don't claim reserved metros
  as a workaround; design for the lifecycle.
- Prefer supported hooks and returned APIs over global injection. `_G.foo = …`
  still goes through the script metatable for a new name and isn't a guarantee
  of process-lifetime storage.
- If wrapping a shared function, chain its existing behavior, retain ownership
  information, and restore it without overwriting someone else's newer wrapper.
  Simply assigning global redraw in post-init is unreliable: menu transitions
  restore the loader's captured redraw. Use explicit integration or carefully
  version-scoped hooks for specialized system UI work.
- Persistent mod settings need their own directory beneath `_path.data`, not
  the current script's `norns.state.data`. Document the save/load policy and
  keep it out of high-rate callbacks.
- An nb provider should implement the pinned player contract and register it
  at the appropriate per-script hook. See [output patterns](../patterns/midi.md)
  and [nb exemplars](../exemplars.md#optional-nb-interface).

Evidence: N `lua/core/script.lua:26–115,206–213`, `lua/core/menu.lua:157–175`,
`lua/core/config.lua:25–31`; D `norns/mods.md:145–167`.

## Acceptance checks

Test with no script, at least two unrelated scripts, reruns, menu entry/exit,
SLEEP/RESTART, and any cooperating mods. Check partial initialization and
repeated hooks. Document conflicts, persistence, target releases and all shared
mutations.
