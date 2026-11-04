# 3.x beta compatibility

Read this only when the user asks to make a component work on the 3.x beta,
reports a failure that happens only on a beta build, or is working on norns
core itself. Ordinary script, mod and engine work targets the stable release;
see [target](../modern.md#target).

## Baseline

**B**: [monome/norns at 6302a0d4dcb85ab3b701a4d7268863092b693caf](https://github.com/monome/norns/tree/6302a0d4dcb85ab3b701a4d7268863092b693caf)
(2026-10-11, after `v3.0.2`). The 3.x line ports matron to C++ (`.cc`) and adds
a `norns/` process with a sidecar. Releases listed in B `releases.txt` and tags:

| Update | Tag | Notes |
|---|---|---|
| 260526 | v3.0.0 | First 3.x beta |
| 260616 | v3.0.1 | Sidecar present; Lua `os.execute`/`io.popen` are still stock |
| 260819 | v3.0.2 | `lua_shell` replaces `os.execute`/`io.popen` through the sidecar |

Read the device's `~/version.txt` and confirm against the core checkout; a beta
device can also carry local core modifications.

## Differences from stable that affect components

### Subprocesses (`io.popen`, `os.execute`)

**User report (2026-10-15):** `io.popen` does not work on the latest beta. The
exact failing calls and fixed build are not established.

**Source (B):** `matron/src/lua_shell.cc:1–5,231–261,286–301` replaces both
functions with sidecar calls. `io.popen` rejects write mode
(`tests/matron/lua_shell/test_lua_shell.cpp:381–388`) and returns the finished
command's buffered output rather than a live process. Reads don't stream, and a
command that never exits never returns. Core helpers moved to
`_norns.execute` (`lua/lib/util.lua:27,69,78`).

To make a script beta-compatible:

- Prefer core helpers (`util.os_capture`, `util.scandir`, `util.make_dir`,
  `norns.system_glob`) over direct `io.popen`, so the version-appropriate
  implementation is used.
- Replace popen write mode and streaming reads (`for l in p:lines()` on a
  long-running process) with finite commands, files, or OSC/MIDI.
- Guard long-running helpers such as `tail -f`, servers or players; on the beta
  they block matron until they exit, if they ever do.
- Keep the stable behavior unchanged. Test the exact call on the target beta
  build. An offline stock-Lua test doesn't exercise the substitution.

### System commands

`norns.system_cmd(cmd, callback)` no longer queues in Lua; it calls
`_norns.system_cmd(cmd, callback or print)` (B `lua/core/norns.lua:226`).
Shutdown, reset and update use `_norns.system_action`. Don't depend on the
stable queue internals (`_norns.system_cmd_capture`).

### Audio routing and the extra mod hook

B adds routing functions (`audio.port_connect`, `port_disconnect`,
`port_connections`, `routing_default`, `routing_is_altered`;
`lua/core/audio.lua:433–494`). `Script.clear` restores default routing when it
was altered (`lua/core/script.lua:92`), and the sixth mod hook
`audio_post_restore_default_routing` runs afterwards
(`lua/core/hook.lua:39`, `lua/core/audio.lua:491`). Stable has none of these;
a component that uses them must guard the call or require the beta.

### Other changes

- A global `json` module is embedded and reset per script
  (`lua/core/startup.lua:35`, `lua/core/script.lua:38`). Don't shadow it; a
  script that ships its own `json` still works but shouldn't rely on the global
  on stable.
- `_norns.vu` passes engine/monitor/softcut/tape levels in addition to I/O.
- Grid devices expose `rows`/`cols` from the device (`lua/core/grid.lua`).
- Services: `norns-main` replaces stable's `norns-matron` and `norns-crone`;
  use `journalctl -u norns-main`. B image config also sets logind `RemoveIPC=no`
  (`image/config/etc/systemd/logind.conf.d/10-norns-removeipc.conf`).

## Hardware observations on a beta device

The repository's acceptance run (repository `acceptance/2026-10-15-pi3-260616-beta/REPORT.md`)
used a Pi 3 B+ shield (PCB 200323) at update 260616 (v3.0.1) with modified core
`4cbb17f`. It is beta evidence, not a stable baseline:

- All three skeletons ran verbatim; sound, controls, menus, PSETs and the mod
  behaved as the guides describe.
- Native `refresh()` averaged 59.70 Hz in play mode, was suppressed in the main
  menu, and continued during textentry and fileselect. Some menu returns
  delivered queued bursts.
- The queued-clock resume race in [timing](../patterns/timing.md#scheduler-behavior-and-diagnosis)
  reproduced 10/10 times. The same Lua and scheduler code is in stable, but it
  hasn't been reproduced there yet.
- With logind `RemoveIPC` enabled and no user linger, the last SSH logout could
  remove JACK shared memory, leaving clients running but blocking new
  connections. Check `/dev/shm`, `jack_lsp` and logind configuration if JACK
  connections fail while the service runs. Stable images may lack the B fix.
- Building core on a 903 MB shield at 260616 with `./waf build -j3` while
  `norns-main` ran hung the device until reboot (2026-11-01). With
  `norns-main` stopped, `-j1` built fine (see
  [building core on the device](debug.md#building-core-on-the-device)). A
  branch build can be tried without installing it as a transient unit with
  `norns-main`'s limits:
  `sudo systemd-run --unit=<name> --uid=we --gid=we -p LimitRTPRIO=95 -p LimitMEMLOCK=infinity --setenv=HOME=<test home> <build>/ws-wrapper/ws-wrapper 'ws://*:5555' <build>/norns/norns`.

## Reporting

State the exact build (update number and core revision), what ran on it, and
which stable behavior was preserved. Keep beta-only changes behind a version
check (`norns.version.update`) or document the beta requirement.
