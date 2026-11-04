# Engine development

Apply the [modern engine definition](../modern.md#engine-definition). First
consider an existing engine, softcut, or an optional nb voice-provider mod.
Use a custom engine when the instrument needs its DSP or command contract.

## Packaging and lifecycle

Distribute a unique `Engine_<Name>` subclass, conventionally under `lib/` in
`Engine_<Name>.sc`. Class discovery uses compiled subclass names, not filenames.
New/changed SC classes require recompilation, normally SYSTEM > RESTART; Lua-only
edits need only script reload.

`CroneEngine` supplies construction and calls `alloc` inside a Routine. Finish
required asynchronous setup before it returns. Base teardown removes registered
commands/polls, invokes your `free`, then synchronizes. A forwarding `*new` and
poll registration are optional. Keep ownership explicit, including partial init.

Evidence: N `sc/core/CroneEngine.sc:15–77`, `sc/core/Crone.sc:100–129,168–180`,
`sc/norns-config.sc:12–16`; D `norns/reference/engine.md:45–51`,
`norns/engine-study-1.md:145–174`. N/D use the
[audited source baseline](../modern.md#evidence-and-scope).

## Minimal runnable engine, parameter library and host

```text
dust/code/modern_tone/
├── modern_tone.lua
└── lib/
    ├── Engine_NoSEDATone.sc
    └── noseda_tone_engine.lua
```

Install all three files, restart to compile, then select `modern_tone`. Rename
the class and SynthDef together when adopting the example for a new project.

### `lib/Engine_NoSEDATone.sc`

One persistent, initially gated-off stereo sine voice. Pitch is Hz, amplitude
is linear 0–0.5, gate is 0/1. A release envelope silences it without destroying
the persistent synth; `free` owns destruction. There are no polls to register.

```supercollider
Engine_NoSEDATone : CroneEngine {
    var synth;

    alloc {
        SynthDef(\noseda_tone_voice, {
            arg out = 0, hz = 220, amp = 0.15, gate = 0;
            var env = EnvGen.kr(Env.asr(0.01, 1, 0.05), gate);
            var signal = SinOsc.ar(hz.lag(0.02)) * amp.lag(0.02) * env;
            Out.ar(out, [signal, signal]);
        }).send(context.server);
        context.server.sync;

        synth = Synth(\noseda_tone_voice,
            [\out, context.out_b], target: context.xg);

        this.addCommand(\hz, "f", { arg msg;
            synth.set(\hz, msg[1].clip(40, 4000));
        });
        this.addCommand(\amp, "f", { arg msg;
            synth.set(\amp, msg[1].clip(0, 0.5));
        });
        this.addCommand(\gate, "i", { arg msg;
            synth.set(\gate, msg[1].clip(0, 1));
        });
    }

    free {
        if(synth.notNil) {
            synth.free;
            synth = nil;
        };
    }
}
```

### `lib/noseda_tone_engine.lua`

```lua
local Tone = {}
Tone.specs = {
  hz = controlspec.new(40, 4000, 'exp', 0, 220, 'Hz'),
  amp = controlspec.new(0, 0.5, 'lin', 0, 0.15)
}

function Tone.add_params(on_change)
  params:add_group('noseda_tone', 'tone', 2)
  params:add_control('noseda_tone_hz', 'frequency', Tone.specs.hz)
  params:set_action('noseda_tone_hz', function(value)
    engine.hz(value)
    if on_change then on_change() end
  end)
  params:add_control('noseda_tone_amp', 'amplitude', Tone.specs.amp)
  params:set_action('noseda_tone_amp', function(value)
    engine.amp(value)
    if on_change then on_change() end
  end)
end

return Tone
```

### `modern_tone.lua`

```lua
-- modern_tone: persistent sine voice
-- v1.0.0 @yourname
-- https://monome.org/docs/norns/engine-study-1/
-- Hold K3: sound; E2: frequency; E3: amplitude

engine.name = 'NoSEDATone'
local tone = include('lib/noseda_tone_engine')

function init()
  tone.add_params(function() redraw() end)
  params:bang()
end

function enc(n, d)
  if n == 2 then params:delta('noseda_tone_hz', d)
  elseif n == 3 then params:delta('noseda_tone_amp', d) end
end

function key(n, z)
  if n == 3 then engine.gate(z) end
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(8, 20)
  screen.text('hold K3 to play')
  screen.move(8, 36)
  screen.text(params:string('noseda_tone_hz'))
  screen.move(8, 52)
  screen.text(params:string('noseda_tone_amp'))
  screen.update()
end
```

The gate is transient input, not a recalled setting. The companion's optional
change notification lets the host draw this small UI after parameter changes,
including PMAP/PSET paths. The closure resolves global redraw when called, so
it respects menu suppression instead of capturing a local renderer or the init
phase's no-op. Returning from the menu also draws current values. For high-rate
automation, have the notification mark dirty and use the [UI patterns](../patterns/ui.md).
There is no Lua-owned background work; core engine release invokes SC `free`.
Don't depend on `engine.gate(0)` in Lua cleanup after engine release is requested.

Evidence: N `sc/engines/Engine_SimplePassThru.sc:16–50`,
`sc/engines/Engine_TestSine.sc`, `sc/core/CroneEngine.sc:19–77`,
`sc/core/CroneAudioContext.sc:33–46`, `lua/core/script.lua:11–24,221–238`,
`lua/core/engine.lua:44–73,89–129`, `lua/core/paramset.lua`,
`matron/src/weaver.c:1928–1991`; D `norns/engine-study-1.md:384–456`.

## Extending the contract

- `addCommand(name, format, fn)` receives the OSC address in `msg[0]`, arguments
  from `msg[1]`; `i`, `f`, `s`, and an empty format are supported. Match Lua
  argument count and units. Dynamic engine commands exist after engine loading,
  so call them from init or later, not top level.
- Use optional `addPoll(name, fn, periodic=true)` for analysis/feedback. Give
  custom polls unique names; the registry rejects duplicate names. Lua obtains
  a registered poll through `poll.set(name, callback)` and can start/stop it.
- Put per-note synths in an owned group and bound polyphony/lifetimes. A
  self-freeing envelope suits one-shots; explicit release/free suits sustained
  or persistent voices. Replacing a single synth reference does not free the
  previous voice.
- Allocate buffers/private buses against `context.server`; synchronize async
  dependencies. Free your own resources, not `context.xg` or shared context
  buses. Namespace all globally compiled classes and named SynthDefs.
- Keep specs/actions in the Lua companion and performance/UI policy in the
  host. Don't hide PSET loading or a full `params:bang()` inside a reusable
  `add_params()` function.

Evidence: N `sc/core/CroneEngine.sc:35–77`, `sc/core/CronePoll.sc:117–137`,
`lua/core/poll.lua:38–56,128–145`, `sc/engines/Engine_PolySub.sc`,
`sc/core/Crone.sc:86–123`; D `norns/reference/engine.md`,
`norns/engine-study-1.md`, `norns/engine-study-3.md`.

## Acceptance checks

Compile alongside installed engines without duplicate classes; load/reload and
switch engines; test minimum/maximum commands and rapid gate changes. Confirm
no accumulated nodes/buffers/tasks after repeated use. Measure idle and maximum
voice/effect load on the intended hardware, leaving control/UI headroom. Test
parameter save/restore through the host. Avoid unsupported blanket efficiency
claims about UGens or `.ar` versus `.kr`; measure the actual DSP.
