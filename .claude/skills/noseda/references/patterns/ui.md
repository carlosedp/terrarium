# UI ownership and redraws

Apply the [rendering definition](../modern.md#timing-sequencing-and-rendering).
Use PARAMS/PSET/PMAP and shipped widgets/modal helpers before building another
settings or file-browser subsystem. Evidence uses [N/D](../modern.md#evidence-and-scope).

## Dirty rendering

For frequent changes, separate musical state updates from rendering. Set screen
and grid dirty flags in actions/events; poll at a chosen UI cadence, commonly
15–30 fps. Lower rates can suit static UIs; 60 fps may suit animation if measured.
For occasional changes a direct redraw from an input callback is supported.

The script's `redraw` function should draw a complete frame and call
`screen.update()`. Core also invokes it when returning to play mode. Don't put
a dirty guard solely inside redraw: forced redraw after a menu must work even
when musical state hasn't changed. Gate the periodic caller instead.

```lua
local screen_dirty = true
local grid_dirty = true
local ui_clock
local g = grid.connect()

local function draw_grid()
  g:all(0)
  g:led(1, 1, 15) -- replace with rendering from the musical state
  g:refresh()
end

local function start_ui()
  ui_clock = clock.run(function()
    while true do
      clock.sleep(1/30)
      if screen_dirty then redraw(); screen_dirty = false end
      if grid_dirty then draw_grid(); grid_dirty = false end
    end
  end)
end
```

This fragment's host sets the flags when state changes, calls `start_ui()` once
after setup and cancels `ui_clock` when ending ownership. Use global `redraw()`
in the loop so core's menu suppression works; a local renderer would bypass it.
Grid refresh is its own device operation, separate from the screen callback.
Handle grid add/reconnect by marking its state dirty again.

A regular `metro.init(callback, 1/30, -1)` plus `:start()` is also supported;
retain the returned timer and stop/free it when no longer owned. Metro is not
legacy merely because an older instrument uses it for UI refresh.

Evidence: N `lua/core/menu.lua:157–175`, `lua/core/screen.lua:29–38`,
`lua/core/grid.lua:105–161`, `lua/core/metro.lua:20–71,94–113`;
D `norns/grid-recipes.md:11–16,49–84`, `norns/clocks.md:305–318`,
`norns/reference/metro.md:100–110`, `norns/study-2.md:163–182`.

## Optional native `refresh()` — undocumented

Hardware display events invoke global `refresh()` nominally at ~60 Hz. Define
it at script scope before init; the loader captures it just like redraw. It is
not `screen.update()` and it does not automatically call redraw for you.

```lua
local frame = 0
local screen_dirty = true

function refresh()
  frame = frame + 1
  if frame % 2 == 0 and screen_dirty then
    redraw() -- nominal ~30 fps opportunities on the inspected hardware backend
    screen_dirty = false
  end
end
```

This is an alternative to the screen polling clock, not an additional timer to
stack onto it. Keep `redraw()` unconditional for forced menu-return draws.
The inspected SDL backend doesn't produce these events. Public docs don't
explain this callback, and dispatch isn't a guaranteed exact frame rate. Test
the target firmware/backend and modal UI; don't advertise portable support.

Evidence: N `matron/src/weaver.c:2872–2875`,
`matron/src/hardware/screen/ssd1322.c:106–125`,
`matron/src/hardware/screen/sdl.c:69–79`, `lua/core/script.lua:206–213`,
`lua/core/menu.lua:157–175`; ecosystem `tehn/plasma/plasma.lua:128–134` at
the [audited revision](../exemplars.md).

## Widgets and modal helpers

- `local ui = require 'ui'` supplies pages, tabs, lists, sliders, dials and other
  widgets. Widget `:redraw()` calls belong inside the host frame; the host still
  calls `screen.update()` and handles navigation/state.
- `textentry.enter(callback, default, heading, check)` returns text through its
  callback, with **nil on cancel**.
- `fileselect.enter(folder, callback, filter)` returns the selected absolute
  path, with **`"cancel"` on cancel**. `_path.audio` is the normal audio root.
- These helpers take input/drawing ownership. Gate custom direct drawing while
  a modal is active, and mark dirty after its callback. Don't build a generic
  takeover by rewriting all `_menu` wiring.
- In the inspected textentry play-mode path, redraw is suppressed but refresh
  is not similarly disabled. If using native refresh, maintain an explicit
  modal-active flag around your helper calls so it cannot paint over the dialog.
  Library-specific behavior must be checked rather than inferred.

On a beta device refresh kept firing during both textentry and fileselect, an
explicit modal flag protected both dialogs, and menu returns sometimes delivered queued
bursts, so counting every second event doesn't guarantee evenly spaced 30 fps
([beta observations](../tasks/beta-compat.md#hardware-observations-on-a-beta-device)).
Stable hardware measurement is still open.

Evidence: N `lua/lib/ui.lua`, `lua/lib/textentry.lua:41–87`,
`lua/lib/fileselect.lua:16–81`; D `norns/reference/lib/ui/`,
`norns/reference/lib/textentry.md`, `norns/reference/lib/fileselect.md`.

## Review and test

Avoid drawing expensive frames in high-rate clock/poll callbacks; ordinary Lua
callbacks are control events, not a script-facing audio DSP callback. Measure
state-to-display latency, menu return, hotplug, modal cancel/accept and CPU at
the chosen rate. Screen layouts, pagination, accessibility and custom visual
language remain instrument design, not a single mandatory framework.

Evidence: N `matron/src/events.c:179–347`; D `norns/study-5.md:327–335`,
`norns/engine-study-3.md:1226–1254` (a 60 fps dirty example).
