// Engine_Terrarium: the sound of terrarium.
//
//   voices (2x MiPlaits) -> voiceBus -> color (MiRings | MiRipples) -> colorBus
//     -> air (MiClouds | MiBeads | MiVerb) -> out
//
// The Lua side owns every mapping from macros to parameters (see doc/SOUND.md);
// this engine only exposes the slots and their raw parameters:
//
//   note(pitch, accent)            play a note on the next voice (and strum Rings)
//   voice_set(key, value)          set a MiPlaits parameter on all voices
//   color_kind(name)               pond | fog
//   color_set(key, value)
//   air_kind(name)                 clouds | fireflies | mountains
//   air_set(key, value)
//
// mi-UGens classes are looked up by name at runtime instead of being written as
// class names. A norns without mi-UGens then still compiles its class library
// (a missing class would fail SuperCollider for every script), the engine just
// stays silent, and the Lua side offers to install them.

Engine_Terrarium : CroneEngine {
	var voiceGroup, colorGroup, airGroup, voiceBus, colorBus;
	var voices, nextVoice = 0;
	var colorSynth, airSynth, colorKind, airKind;
	var voiceParams, colorParams, airParams;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var s = context.server;
		var plaits = \MiPlaits.asClass, rings = \MiRings.asClass, ripples = \MiRipples.asClass;
		var clouds = \MiClouds.asClass, beads = \MiBeads.asClass, verb = \MiVerb.asClass;

		voiceParams = IdentityDictionary.new;
		colorParams = IdentityDictionary.new;
		airParams = IdentityDictionary.new;
		this.addCommands;

		if ([plaits, rings, ripples, clouds, verb].any(_.isNil)) {
			"terrarium: mi-UGens not found, the engine stays silent".warn;
		} {
			this.buildDefs(plaits, rings, ripples, clouds, beads, verb);
			s.sync;
			voiceBus = Bus.audio(s, 2);
			colorBus = Bus.audio(s, 2);
			voiceGroup = Group.new(context.xg);
			colorGroup = Group.after(voiceGroup);
			airGroup = Group.after(colorGroup);
			voices = Array.fill(2, { Synth(\terrarium_voice, [\out, voiceBus], voiceGroup) });
		};
	}

	buildDefs { |plaits, rings, ripples, clouds, beads, verb|
		// slot synths fade in and out, so swapping a module doesn't click
		var fade = { |gate| EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2) };

		SynthDef(\terrarium_voice, { |out, pitch = 60, t_trig = 0, engine = 12, harm = 0.5, timbre = 0.5,
			morph = 0.5, decay = 0.5, lpg = 0.5, level = 0.8, pan = 0, amp = 0.35|
			var sig = plaits.ar(pitch, engine, harm.lag(0.05), timbre.lag(0.05), morph.lag(0.05),
				t_trig, level, decay: decay, lpg_colour: lpg);
			Out.ar(out, Pan2.ar(sig[0], pan, amp));
		}).add;

		// color: the voice excites Rings; more structure, more resonator in the mix
		SynthDef(\terrarium_pond, { |in, out, gate = 1, pitch = 60, t_trig = 0, struct = 0.4, bright = 0.5,
			damp = 0.6, pos = 0.3, model = 0, mix = 0.8|
			var dry = In.ar(in, 2);
			var wet = rings.ar(dry.sum * 0.5, t_trig, pitch, struct.lag(0.1), bright.lag(0.1), damp.lag(0.1),
				pos, model, 2);
			Out.ar(out, ((dry * (1 - (0.5 * struct))) + (wet * mix)) * fade.(gate));
		}).add;

		SynthDef(\terrarium_fog, { |in, out, gate = 1, cf = 0.5, reson = 0.2, drive = 1|
			var dry = In.ar(in, 2);
			var wet = ripples.ar(dry, cf.lag(0.1), reson.lag(0.1), drive.lag(0.1));
			Out.ar(out, wet * fade.(gate));
		}).add;

		// air: grain position drifts on a 20 s triangle so the clouds move
		SynthDef(\terrarium_clouds, { |in, out, gate = 1, dens = 0.5, fb = 0.2, size = 0.4, tex = 0.5,
			drywet = 0.45, spread = 0.7, rvb = 0.3, freeze = 0, mode = 0, pit_jitter = 0|
			var dry = In.ar(in, 2);
			var wet = clouds.ar(dry, LFNoise1.kr(0.4) * pit_jitter, LFTri.kr(0.05).range(0.3, 0.7),
				size.lag(0.1), dens.lag(0.1), tex.lag(0.1), drywet, 1, spread, rvb, fb.lag(0.1), freeze, mode);
			Out.ar(out, wet * fade.(gate));
		}).add;

		// seed is never passed: any input there counts as patched and stops
		// density from generating grains on its own
		beads !? {
			SynthDef(\terrarium_fireflies, { |in, out, gate = 1, density = 0.7, fb = 0.2, size = 0.5,
				time_rnd = 0.2, drywet = 0.5, rvb = 0.35, shape = 0.6, pitch_rnd = 0.08, freeze = 0|
				var dry = In.ar(in, 2);
				var wet = beads.ar(dry, pitch: 0, pitch_rnd: pitch_rnd, time: 0.5, time_rnd: time_rnd,
					size: size.lag(0.1), shape: shape, density: density.lag(0.1), fb: fb.lag(0.1),
					drywet: drywet, rvb: rvb, freeze: freeze, seed_btn: 2, quality: 0, in_gain: 1);
				Out.ar(out, wet * fade.(gate));
			}).add;
		};

		SynthDef(\terrarium_mountains, { |in, out, gate = 1, time = 0.7, drywet = 0.4, damp = 0.5, hp = 0.05,
			freeze = 0, diff = 0.7|
			var dry = In.ar(in, 2);
			var wet = verb.ar(dry, time.lag(0.1), drywet.lag(0.1), damp.lag(0.1), hp, freeze, diff);
			Out.ar(out, wet * fade.(gate));
		}).add;
	}

	addCommands {
		this.addCommand(\note, "ff", { |msg| this.note(msg[1], msg[2]) });
		this.addCommand(\voice_set, "sf", { |msg| this.voiceSet(msg[1].asSymbol, msg[2]) });
		this.addCommand(\color_kind, "s", { |msg| this.setColor(msg[1].asSymbol) });
		this.addCommand(\color_set, "sf", { |msg| this.colorSet(msg[1].asSymbol, msg[2]) });
		this.addCommand(\air_kind, "s", { |msg| this.setAir(msg[1].asSymbol) });
		this.addCommand(\air_set, "sf", { |msg| this.airSet(msg[1].asSymbol, msg[2]) });
	}

	note { |pitch, accent|
		var v;
		if (voices.isNil) { ^this };
		v = voices[nextVoice];
		nextVoice = (nextVoice + 1) % voices.size;
		v.set(\pitch, pitch, \level, 0.5 + (0.5 * accent), \pan, 0.3.rand2, \t_trig, 1);
		if (colorKind == \pond) { colorSynth !? { colorSynth.set(\pitch, pitch, \t_trig, 1) } };
	}

	voiceSet { |key, value|
		voiceParams[key] = value;
		voices !? { voices.do(_.set(key, value)) };
	}

	// a new slot synth starts with every parameter sent so far, then the old one fades out
	setColor { |kind|
		var old = colorSynth;
		if (voices.isNil or: { kind == colorKind }) { ^this };
		colorKind = kind;
		colorSynth = Synth(("terrarium_" ++ kind).asSymbol,
			[\in, voiceBus, \out, colorBus] ++ colorParams.asKeyValuePairs, colorGroup);
		old !? { old.set(\gate, 0) };
	}

	colorSet { |key, value|
		colorParams[key] = value;
		colorSynth !? { colorSynth.set(key, value) };
	}

	setAir { |kind|
		var old = airSynth, name = ("terrarium_" ++ kind).asSymbol;
		if (voices.isNil or: { kind == airKind }) { ^this };
		if (SynthDescLib.global.at(name).isNil) {
			("terrarium: no synth for air '" ++ kind ++ "' (is MiBeads installed?)").warn;
			^this
		};
		airKind = kind;
		airSynth = Synth(name, [\in, colorBus, \out, context.out_b.index] ++ airParams.asKeyValuePairs, airGroup);
		old !? { old.set(\gate, 0) };
	}

	airSet { |key, value|
		airParams[key] = value;
		airSynth !? { airSynth.set(key, value) };
	}

	free {
		voices !? { voices.do(_.free) };
		colorSynth !? { colorSynth.free };
		airSynth !? { airSynth.free };
		[voiceGroup, colorGroup, airGroup].do { |g| g !? { g.free } };
		[voiceBus, colorBus].do { |b| b !? { b.free } };
	}
}
