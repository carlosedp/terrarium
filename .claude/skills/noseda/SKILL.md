---
name: noseda
description: Write, review, refactor, debug, test and optimize monome norns scripts, mods and SuperCollider engines using current, source-verified norns idioms. Use for norns projects (Lua with init/redraw/enc/key, lib/mod.lua, Engine_*.sc, dust/code), norns, matron, maiden, crone, softcut or dust development, and running or testing components on hardware or desktop norns.
license: MIT
---

# NoSEDA: modern norns development

Paths here are relative to this skill directory. Links within `references/`
are relative to the file containing the link.

## 1. Detect the component and task

Inspect the user's project, not this skill directory. Components can coexist;
read every applicable component guide.

| Project contains / user requests | Read |
|---|---|
| A script entry point, usually `<project>.lua` | `references/components/script.md` |
| `lib/mod.lua`, a system extension or nb voice provider | `references/components/mod.md` |
| `Engine_*.sc`, a custom synthesis or processing engine | `references/components/engine.md` |

For a new project, infer the components from the requested instrument. Consider
existing engines, softcut and optional nb voices before adding a custom engine.

## 2. Apply the modern definition

Read `references/modern.md`: the target, shared rules, then the section for
each component involved. It is the authority for these guides.
“Modern” means current platform integration and explicit ownership, not copying
the style of a popular script. Preserve intentional musical behavior during
refactors and report compatibility costs before changing it.

- Use params for user-facing settings, with actions driving derived state and
  sound. Preserve stable IDs and existing PSET/PMAP compatibility.
- Save runtime data under `norns.state.data`, audio under `_path.audio`.
- Use beat-aware clocks for musical synchronization. Metro remains supported
  for seconds-based work. Keep rendering inexpensive and deliberately paced.
- Global callbacks and small scripts' global state are normal norns usage.
  Modules ordinarily return local tables. Do not shadow system bindings.
- Track owned work and external notes; distinguish core resets from component
  cleanup. Restore changes to shared implementations.
- Prefer platform facilities. Label undocumented interfaces, including
  `refresh()`, and verify them on the target version/backend.

## 3. Load only relevant detail

| Reference | Read when… |
|---|---|
| `references/modern.md` | Always: target, shared rules and relevant component definitions |
| `references/patterns/params.md` | Adding/editing parameters, groups, actions, dependencies |
| `references/patterns/state.md` | PSET hooks, sidecar data, migrations or session persistence |
| `references/patterns/timing.md` | Clocks, transport, lattice, sequins or event recording |
| `references/patterns/ui.md` | Dirty redraws, refresh, modal UI or screen/grid coordination |
| `references/patterns/midi.md` | Sending notes, handling overlap/stop, optional nb integration |
| `references/tasks/review.md` | Reviewing or refactoring, especially legacy components |
| `references/tasks/debug.md` | Running, testing or debugging on hardware/desktop norns |
| `references/tasks/optimize.md` | Measuring timing, CPU, memory, xruns or audio dropouts |
| `references/exemplars.md` | Looking for an implementation to study for a specific purpose |
| `references/tasks/beta-compat.md` | Only when asked for 3.x beta support, a failure occurs only on a beta build, or working on norns core |

## 4. Verify and finish

Target the current stable release (260102, tag `v2.9.4`) unless the user's
device or request says otherwise. Find a core checkout (`../norns`, `~/norns`,
or elsewhere) at the matching tag. Read core as reference; don't edit it as
part of component work.
Verify API behavior in `lua/core/`, `lua/lib/`, `matron/src/`, and, for engines,
`sc/core/`; cross-check [monome docs](https://monome.org/docs/norns/).
`references/modern.md` records the audited baseline and known documentation gaps.

Choose checks proportional to the change: syntax, PSET compatibility, transport
and cleanup, then target-device timing/audio/UI where relevant. State what ran
and what still needs hardware. For reviews, report each finding as **legacy
idiom → modern replacement → risk of changing it**, with source evidence.

`scripts/nrepl.py` sends Lua to matron over websocket; usage and dependencies
are in `references/tasks/debug.md` and `scripts/requirements.txt`.
