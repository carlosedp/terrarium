# Debugging and testing on norns

Use the [modern definitions](../modern.md) to decide expected behavior, and the
[review checklist](review.md) for migration risks. Desktop is useful for
functional checks; hardware establishes audio timing, device behavior and feel.
N/D citations use the [audited baseline](../modern.md#evidence-and-scope).

## Discover the actual target

Ask for missing connection details and check what exists before deploying:

```bash
command -v norns-desktop
pgrep -af 'ws-wrapper.*5555'
getent hosts norns.local
ssh -o ConnectTimeout=10 -o BatchMode=yes we@<ip> 'cat ~/version.txt; systemctl list-units --no-pager "norns*"'
```

Record the update number, hardware or desktop fork/backend, mods, component
revision and dependencies. Stable is 260102; if the device runs a 3.x beta and
the failure doesn't reproduce on stable, see [beta compatibility](beta-compat.md).
Don't prescribe a firmware change as a generic debugging step.

Use an IP if hostname resolution is the problem; distinguish resolution, SSH,
REPL and maiden failures. Stable services include `norns-jack`, `norns-crone`,
`norns-sclang` and `norns-matron`; forks and the beta differ.
Check `systemctl list-units "norns*"` rather than assuming names.

Evidence: N `lua/core/norns.lua:247–251` (`_norns.reset` service restarts).

## Matron REPL over websocket

The standard services expose Lua on 5555 and sclang on 5556 through ws-wrapper.
The client uses the `bus.sp.nanomsg.org` subprotocol, sending newline-terminated
Lua and receiving stdout. `scripts/nrepl.py` (relative to the skill directory)
needs the dependency in `scripts/requirements.txt` (`websocket-client`).

```bash
python3 <skill-dir>/scripts/nrepl.py --host <ip> --wait 25 'norns.script.load("code/<script>/<script>.lua")'
python3 <skill-dir>/scripts/nrepl.py --host <ip> 'print(params:get("clock_tempo"))'
python3 <skill-dir>/scripts/nrepl.py --host localhost "dofile('/abs/path/test.lua')"
```

Engine loading is asynchronous; wait for init completion rather than issuing
dependent tests immediately. For long tests, run a scoped clock coroutine in
matron and write its report under `norns.state.data`; fetch it after completion.
A disconnected client doesn't inherently cancel a started coroutine.

Evidence: N `maiden-repl/README.md:13–25`, `ws-wrapper/src/main.c:19–21,40–73`,
`lua/core/script.lua:221–238`, `lua/core/engine.lua:89–109`.

## Deployment and logs

Inspect the installed directory and local modifications before replacing code.
Use a new test directory/worktree or an explicitly agreed update location; keep
the user's scripts and saved data. Record exactly which revision is deployed.
Mods install at `dust/code/<mod>/lib/mod.lua`, then enable in SYSTEM > MODS and
restart. Changed SC classes need recompilation/restart; Lua-only changes can
normally be reloaded through `norns.script.load`.

```bash
journalctl -u norns-matron -n 100 --no-pager
journalctl -u norns-crone -n 100 --no-pager
journalctl -u norns-sclang -n 100 --no-pager
journalctl -u norns-jack --since '10 min ago' --no-pager
```

Check the first relevant compile/load error, not only the last symptom. Duplicate
SC classes can prevent sclang startup before any script init hook runs. Save logs
with target/build/test conditions. For remote failures use bounded retries and
resumable result files; don't mistake interrupted transport for a code result.

Evidence: N `sc/norns-config.sc:12–16`, `lua/core/startup.lua:76–100`,
`lua/core/mods.lua:13–58`, `lua/core/menu/mods.lua:78–85`;
D `norns/engine-study-1.md:172–174`, `norns/mods.md:24–55`.

### Building core on the device

A norns has about 900 MB of RAM and no swap. A running norns (matron, crone,
softcut buffers, scsynth) uses about half of it, and one `cc1plus` on a large
core file (`weaver`, crone) can take several hundred MB. Parallel builds next to
running services exhaust memory; the device then stops answering SSH (TCP
still connects, no banner, mDNS goes away) and stays that way until it is
rebooted.

- Stop the norns services that you are allowed to stop before building, check
  `MemAvailable` in `/proc/meminfo`, and build with one job (`./waf build -j1`).
- Start the build detached (`nohup … < /dev/null > build.log 2>&1 &`) and poll
  the log with short, bounded SSH calls, so a slow device doesn't hang the session.
- Build a branch in its own directory, not in the user's checkout, which may
  carry uncommitted work. Before installing, compare its upstream base with the
  device's (`git merge-base`): a branch on an older base rolls back core fixes.
- To try a build without installing it, run it with a separate `HOME` whose
  `norns` links to the build and whose `dust` links to `~/dust`; matron loads
  Lua from `$HOME/norns/lua`. Run it under the service's limits, so the audio
  threads get the same realtime priority. Back up `dust/data/system.state`
  first: a new build can write keys that the old build fails to read.

### JACK connections fail while the service runs

Inspect `/dev/shm`, `jack_lsp` and the logind configuration. With logind
`RemoveIPC` enabled and no user linger, the last SSH logout can remove JACK
shared memory (observed on a beta device; see
[beta compatibility](beta-compat.md#hardware-observations-on-a-beta-device)).
Restart the audio services coherently only if necessary and authorized; don't
restart JACK on every deployment or change system configuration without
identifying the condition.

## Desktop checks

A local `norns-desktop` launcher may manage maiden, sclang and an SDL norns
backend. Inspect that launcher's paths, ports, key mappings and restart behavior:
they are installation-specific, not a universal norns API. A known local setup
logs to `~/norns.log`, `~/sclang.log`, `~/maiden.log` and maps Alt+1/2/3 to keys,
Alt+q/w, a/s, z/x to encoders; verify before relying on those bindings.

Use a test dust tree when possible and include the engine in the SC class path
before compilation. Avoid starting a second instance on occupied ports or
restarting an active user session. Note enabled mods and MIDI vport names here
too. The inspected upstream SDL backend doesn't generate native refresh events;
a refresh-only script needs hardware or an appropriate backend test.

Evidence: N `matron/src/hardware/screen/sdl.c:69–79`,
`matron/src/hardware/screen/ssd1322.c:106–125`, `sc/norns-config.sc`.
Launcher behavior above is a local environment observation, not monome docs.

## Scoped testing and diagnostics

Prefer direct unit boundaries where available: call a step with deterministic
state, capture output, inspect its result. Plain Lua 5.3 can load suitable pure
libraries with `<norns>/lua/lib/?.lua` on `package.path`; stub host primitives
explicitly. Syntax-check with `luac5.3 -p file.lua`. The build uses Lua 5.3
(`N third-party/wscript`). These don't test matron bindings or audio.

When external instrumentation is necessary:

- A global callback's lexical upvalues can be inspected with Lua's
  `debug.getupvalue` and temporarily replaced with `debug.setupvalue`. This is
  diagnostic instrumentation, not production module architecture.
- Save originals and restore wrappers on success and failure. Vport methods
  are per-port fields: assigning nil deletes them. Params methods are inherited;
  preserve any existing instance override rather than assuming there is none.
- The global `engine` is a read-only proxy except its name; ordinary assignment
  cannot wrap its commands. Instrument the caller or capture output elsewhere.
- New script globals are reset on script load. Mutated system tables and cached
  modules are not isolated by that reset; a stored wrapper there can retain a
  dead script instance. Don't repeat the blanket claim that globals survive.

Evidence: N `lua/core/startup.lua:25,31`, `lua/core/script.lua:26–47`,
`lua/core/paramset.lua:85–103`, `lua/core/midi.lua:17–39`,
`lua/lib/tabutil.lua:218–251`. Lua debug-library usage is generic Lua, not a
norns-specific convention. See [MIDI captures](../patterns/midi.md) and
[performance metrics](optimize.md).

## Screen capture and input routing

`screen.export_screenshot('shot')` writes `norns.state.data .. 'shot.png'`.
Inspect that path and call after a completed draw/update. Capture the norns
frame rather than the whole desktop. Remove only test files you created.

```bash
python3 <skill-dir>/scripts/nrepl.py --host <ip> 'print(norns.state.data); screen.export_screenshot("shot")'
scp we@<ip>:dust/data/<script>/shot.png /tmp/
```

Calling `key()`/`enc()` directly tests script handlers. To diagnose actual
dispatch, note that play-mode wiring captures input handlers by value, while
menu transitions restore stored redraw/refresh callbacks. In a version-scoped
REPL harness, `_menu.key(3, 1)` and `norns.encoders.callback(2, 1)` reach the
currently routed handlers. These are **internal diagnostic entry points**,
not production script integration. Test press and release, and know whether
the menu is active. Prefer the shipped fileselect/textentry modal APIs over
manually replacing all input/screen internals.

Evidence: N `lua/core/screen.lua:397–399`, `lua/core/menu.lua:128–175`,
`lua/lib/fileselect.lua:38–81`, `lua/lib/textentry.lua:54–87`.

## Report checks honestly

### Clock errors and leftover clocks

`clock.resume` can call `coroutine.resume(nil)` (N `lua/core/clock.lua:59–62`)
when a clock is cancelled after its resume event is already queued; see
[timing](../patterns/timing.md#scheduler-behavior-and-diagnosis). Capture thread
IDs and queued/cancel ordering when investigating it. Ownership assertions can
pass before the queued error is dispatched.

After `Script.clear`, `clock.add_params` recreates core clocks (crow output,
MIDI output and external-tempo monitoring). Distinguish them from
script-owned clocks rather than asserting `clock.threads` is empty.

`_norns.restart` clears the script before saving state, while `norns.shutdown`
saves the active script before cleanup, and startup resumes only a cleanly
saved, nonempty script. So RESTART then SLEEP comes back to no script. Evidence:
N `lua/core/norns.lua:185–196,253–264`, `lua/core/state.lua:60–100`,
`lua/core/clock.lua:211`. Fetch volatile journals before power cycling.

### Reporting boundaries

State syntax/offline, host-instrumented, desktop-runtime and physical-device
checks separately, with the exact update number and core revision.
After a refactor, check PSET/PMAP fixtures, first-note/transport behavior, notes
on stop/output change, menu/modal redraw and repeated load/cleanup. Hardware
CPU/audio/refresh validation remains necessary when those behaviors matter.
