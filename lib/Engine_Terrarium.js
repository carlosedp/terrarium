// Engine_Terrarium.js: Engine_Terrarium.sc for the browser, used by tools/norns-web.
// norns ignores this file.
//
// It plays the same mi-UGens as the engine: they are compiled to WebAssembly
// (norns-mi-UGens, build.sh --wasm) and run in an AudioWorklet, from
// lib/Engine_Terrarium/ (mi-ugens-node.js loads them). Each SynthDef of the
// engine is a function below that builds the same graph from Web Audio nodes
// and mi-UGen nodes; the tape is plain Web Audio, as it is plain SuperCollider
// UGens in the engine.
//
//   voice (2x MiPlaits | MiRings) -> voiceBus -> color (MiRings | MiRipples) -> colorBus
//     -> air (MiClouds | MiBeads | MiVerb) -> tape -> out
//   drone (2x MiPlaits | MiElements) -> colorBus
//
// Keep it in step with the engine: a SynthDef change goes in its function here. All but
// terrarium_voice_input: visitors play a synth over MIDI and hear it back through the
// input, which the browser can't do, so their soil is silent here.
// Control lags are .lag() on the UGen inputs (the worklet runs them like
// scsynth, per 64-sample block); lags on levels are lagTo() on gain nodes.
(() => {
const BASE = document.currentScript.src.replace(/\.js(\?.*)?$/, "/");
const UGENS = ["MiPlaits", "MiRings", "MiRipples", "MiClouds", "MiBeads", "MiVerb", "MiElements"];

NornsWeb.engines.Terrarium = () => {
  // what the engine keeps: the kind of each slot and every parameter sent so far
  const st = { voiceKind: null, voiceParams: {}, colorKind: null, colorParams: {}, airKind: null, airParams: {},
    droneKind: null, droneParams: {}, tape: {} };
  let A = null;            // { ctx, mi, voiceBus, colorBus, airIn, tape } once the UGens are loaded
  let voices = null, nextVoice = 0, colorSynth = null, airSynth = null, droneSynth = null;

  const ctl = (value, lag = 0) => ({ rate: "control", value, lag });
  // .lag(t) on a level: SC's Lag reaches 60 dB in t seconds
  const lagTo = (param, v, t) => param.setTargetAtTime(v, A.ctx.currentTime, Math.max(t, 0.001) / 6.9);
  const gain = (v = 1) => { const g = A.ctx.createGain(); g.gain.value = v; return g; };

  // A slot synth: build(p) returns { output, input?, set(k, v), stop?() }. Every synth has
  // vol (its level, lagged 0.1) and fades in (0.05 s) and out (0.3 s), as the engine's fade.
  function synth(build, params, dest, defaults) {
    const p = { ...defaults, ...params };
    const s = build(p), vol = gain(p.vol ?? 1), fade = gain(0), t = A.ctx.currentTime;
    s.output.connect(vol); vol.connect(fade); fade.connect(dest);
    fade.gain.setValueAtTime(0, t); fade.gain.linearRampToValueAtTime(1, t + 0.05);
    return {
      input: s.input,
      set(k, v) {
        p[k] = v;
        if (k === "vol") lagTo(vol.gain, v, 0.1); else s.set(k, v, p);
      },
      release() {
        const now = A.ctx.currentTime;
        fade.gain.cancelScheduledValues(now); fade.gain.setValueAtTime(fade.gain.value, now);
        fade.gain.linearRampToValueAtTime(0, now + 0.3);
        setTimeout(() => {
          s.stop?.();
          (s.units || []).forEach(u => u.free());
          s.input?.disconnect(); fade.disconnect();
        }, 400);
      },
    };
  }

  // An LFNoise1.kr: a ramp to a new random value (-1..1) freq times a second.
  function lfnoise1(freq) {
    const c = A.ctx.createConstantSource(), ctx = A.ctx;
    let next = ctx.currentTime;
    const ahead = () => { while (next < ctx.currentTime + 1) { next += 1 / freq; c.offset.linearRampToValueAtTime(Math.random() * 2 - 1, next); } };
    ahead(); c.start();
    const timer = setInterval(ahead, 400);
    return { node: c, stop() { clearInterval(timer); c.stop(); } };
  }
  // An LFTri.kr times a level, or a constant: sources for a mi-UGen's modulation input
  function tri(freq, level) {
    const o = A.ctx.createOscillator(), g = gain(level);
    o.type = "triangle"; o.frequency.value = freq; o.connect(g); o.start();
    return { node: g, osc: o, stop() { o.stop(); } };
  }
  // mi-UGen modulation input: channel k carries sources[k]
  function mods(unit, sources) {
    const m = A.ctx.createChannelMerger(sources.length);
    sources.forEach((s, k) => s.connect(m, 0, k));
    m.connect(unit, 0, 1);
    return m;
  }
  // a stereo bus into a mi-UGen's two audio inputs, untouched
  const stereoInto = (src, unit) => src.connect(unit, 0, 0);

  // ---------- the SynthDefs ----------

  const DEFS = {
    voice_plaits: { defaults: { pitch: 60, engine: 12, harm: 0.5, timbre: 0.5, morph: 0.5, decay: 0.5, lpg: 0.5,
      level: 0.8, pan: 0, amp: 0.35 }, build(p) {
      const u = A.mi.node("MiPlaits", { pitch: ctl(p.pitch), engine: ctl(p.engine), harm: ctl(p.harm, 0.05),
        timbre: ctl(p.timbre, 0.05), morph: ctl(p.morph, 0.05), trigger: ctl(0), level: ctl(p.level),
        decay: ctl(p.decay), lpg_colour: ctl(p.lpg) });
      const split = A.ctx.createChannelSplitter(2), amp = gain(p.amp), pan = A.ctx.createStereoPanner();
      pan.pan.value = p.pan;
      u.connect(split); split.connect(amp, 0); amp.connect(pan);  // Pan2.ar(sig[0], pan, amp)
      const KEYS = { pitch: "pitch", engine: "engine", harm: "harm", timbre: "timbre", morph: "morph", level: "level",
        decay: "decay", lpg: "lpg_colour" };
      return { output: pan, units: [u], set(k, v) {
        if (k === "t_trig") u.trig({ trigger: v });
        else if (k === "pan") pan.pan.setValueAtTime(v, A.ctx.currentTime);
        else if (k === "amp") amp.gain.setValueAtTime(v, A.ctx.currentTime);
        else if (KEYS[k]) u.set({ [KEYS[k]]: v });
      } };
    } },

    // a Rings voice: the internal exciter strikes the resonator on each note
    voice_rings: { defaults: { pitch: 60, struct: 0.4, bright: 0.5, damp: 0.6, pos: 0.3, model: 0, amp: 0.5 }, build(p) {
      const u = A.mi.node("MiRings", { trig: ctl(0), pit: ctl(p.pitch), struct: ctl(p.struct, 0.05),
        bright: ctl(p.bright, 0.05), damp: ctl(p.damp, 0.05), pos: ctl(p.pos), model: ctl(p.model), poly: 2,
        intern_exciter: 1 });
      const amp = gain(p.amp);
      u.connect(amp);
      const KEYS = { pitch: "pit", struct: "struct", bright: "bright", damp: "damp", pos: "pos", model: "model" };
      return { output: amp, units: [u], set(k, v) {
        if (k === "t_trig") u.trig({ trig: v });
        else if (k === "amp") amp.gain.setValueAtTime(v, A.ctx.currentTime);
        else if (KEYS[k]) u.set({ [KEYS[k]]: v });
      } };
    } },

    // color: the voice excites Rings; more structure, more resonator in the mix
    pond: { defaults: { pitch: 60, struct: 0.4, bright: 0.5, damp: 0.6, pos: 0.3, model: 0, mix: 0.8 }, build(p) {
      const input = gain(), mono = gain(), dry = gain(1 - 0.5 * p.struct), wet = gain(p.mix), out = gain();
      mono.channelCount = 1; mono.channelCountMode = "explicit";   // dry.sum * 0.5: Web Audio's downmix is (L + R) / 2
      const u = A.mi.node("MiRings", { in: { rate: "audio" }, trig: ctl(0), pit: ctl(p.pitch), struct: ctl(p.struct, 0.1),
        bright: ctl(p.bright, 0.1), damp: ctl(p.damp, 0.1), pos: ctl(p.pos), model: ctl(p.model), poly: 2 });
      input.connect(mono); mono.connect(u); u.connect(wet); wet.connect(out);
      input.connect(dry); dry.connect(out);
      const KEYS = { pitch: "pit", struct: "struct", bright: "bright", damp: "damp", pos: "pos", model: "model" };
      return { input, output: out, units: [u], set(k, v) {
        const t = A.ctx.currentTime;
        if (k === "t_trig") u.trig({ trig: v });
        else if (k === "mix") wet.gain.setValueAtTime(v, t);
        else if (KEYS[k]) u.set({ [KEYS[k]]: v });
        if (k === "struct") dry.gain.setValueAtTime(1 - 0.5 * v, t);
      } };
    } },

    // a Ripples per channel (ripples.ar on a stereo input)
    fog: { defaults: { cf: 0.5, reson: 0.2, drive: 1 }, build(p) {
      const input = gain(), split = A.ctx.createChannelSplitter(2), merge = A.ctx.createChannelMerger(2);
      input.connect(split);
      const units = [0, 1].map(ch => {
        const u = A.mi.node("MiRipples", { in: { rate: "audio" }, cf: ctl(p.cf, 0.1), reson: ctl(p.reson, 0.1),
          drive: ctl(p.drive, 0.1) });
        split.connect(u, ch); u.connect(merge, 0, ch);
        return u;
      });
      return { input, output: merge, units, set(k, v) {
        if (k === "cf" || k === "reson" || k === "drive") units.forEach(u => u.set({ [k]: v }));
      } };
    } },

    // air: grain position drifts on a 20 s triangle so the clouds move
    clouds: { defaults: { dens: 0.5, fb: 0.2, size: 0.4, tex: 0.5, drywet: 0.45, spread: 0.7, rvb: 0.3, freeze: 0,
      mode: 0, pit_jitter: 0, lofi: 0 }, build(p) {
      const input = gain();
      const u = A.mi.node("MiClouds", { pit: { rate: "control", value: 0, mod: 0 }, pos: { rate: "control", value: 0.5, mod: 1 },
        size: ctl(p.size, 0.1), dens: ctl(p.dens, 0.1), tex: ctl(p.tex, 0.1), drywet: ctl(p.drywet), in_gain: 1,
        spread: ctl(p.spread), rvb: ctl(p.rvb), fb: ctl(p.fb, 0.1), freeze: ctl(p.freeze), mode: ctl(p.mode),
        lofi: ctl(p.lofi) });
      const noise = lfnoise1(0.4), jitter = gain(p.pit_jitter), drift = tri(0.05, 0.2);  // LFTri.range(0.3, 0.7)
      noise.node.connect(jitter);
      mods(u, [jitter, drift.node]);
      stereoInto(input, u);
      const KEYS = { size: 1, dens: 1, tex: 1, drywet: 1, spread: 1, rvb: 1, fb: 1, freeze: 1, mode: 1, lofi: 1 };
      return { input, output: u, units: [u], stop() { noise.stop(); drift.stop(); }, set(k, v) {
        if (k === "pit_jitter") jitter.gain.setValueAtTime(v, A.ctx.currentTime);
        else if (KEYS[k]) u.set({ [k]: v });
      } };
    } },

    // seed is never passed: any input there counts as patched and stops density
    // from generating grains on its own
    fireflies: { defaults: { density: 0.7, fb: 0.2, size: 0.5, time_rnd: 0.2, drywet: 0.5, rvb: 0.35, shape: 0.6,
      pitch_rnd: 0.08, freeze: 0, time: 0.5, pitch: 0 }, build(p) {
      const input = gain();
      const u = A.mi.node("MiBeads", { pitch: ctl(p.pitch), pitch_rnd: ctl(p.pitch_rnd), time: ctl(p.time, 0.1),
        time_rnd: ctl(p.time_rnd), size: ctl(p.size, 0.1), shape: ctl(p.shape), density: ctl(p.density, 0.1),
        fb: ctl(p.fb, 0.1), drywet: ctl(p.drywet), rvb: ctl(p.rvb), freeze: ctl(p.freeze), seed_btn: 2, quality: 0,
        in_gain: 1 });
      stereoInto(input, u);
      const KEYS = { pitch: 1, pitch_rnd: 1, time: 1, time_rnd: 1, size: 1, shape: 1, density: 1, fb: 1, drywet: 1, rvb: 1, freeze: 1 };
      return { input, output: u, units: [u], set(k, v) { if (KEYS[k]) u.set({ [k]: v }); } };
    } },

    mountains: { defaults: { time: 0.7, drywet: 0.4, damp: 0.5, hp: 0.05, freeze: 0, diff: 0.7 }, build(p) {
      const input = gain();
      const u = A.mi.node("MiVerb", { time: ctl(p.time, 0.1), drywet: ctl(p.drywet, 0.1), damp: ctl(p.damp, 0.1),
        hp: ctl(p.hp), freeze: ctl(p.freeze), diff: ctl(p.diff) });
      stereoInto(input, u);
      const KEYS = { time: 1, drywet: 1, damp: 1, hp: 1, freeze: 1, diff: 1 };
      return { input, output: u, units: [u], set(k, v) { if (KEYS[k]) u.set({ [k]: v }); } };
    } },

    // drone: a constant (scalar) trigger and level leave Plaits unpatched, so its LPG
    // stays open. Root and fifth, each drifting on its own slow LFO; each voice swells on
    // its own slow cycle. The pitch glides (4 s), but not in the first half second.
    aurora: { defaults: { pitch: 48, fifth: 7, engine: 22, harm: 0.45, timbre: 0.4, morph: 0.5, wobble: 0.1, amp: 0.25,
      hush: 1, duck: 0, lift: 0 }, build(p) {
      const ctx = A.ctx;
      // lfo = LFTri.kr([0.05, 0.063]) * wobble + lift.lag(0.3) * 0.25, and its opposite for the top's morph
      const t0 = tri(0.05, p.wobble), t1 = tri(0.063, p.wobble), lift = ctx.createConstantSource();
      lift.offset.value = p.lift * 0.25; lift.start();
      const lfo0 = gain(), lfo1 = gain(), neg0 = gain(-1);
      t0.node.connect(lfo0); lift.connect(lfo0); t1.node.connect(lfo1); lift.connect(lfo1); lfo0.connect(neg0);
      const plaits = (pitch, timbreMod, morphMod) => {
        const u = A.mi.node("MiPlaits", { pitch: ctl(pitch), engine: ctl(p.engine), harm: ctl(p.harm, 0.2),
          timbre: { rate: "control", value: p.timbre, mod: 0 }, morph: { rate: "control", value: p.morph, mod: 1 },
          trigger: 0, level: 0 });
        mods(u, [timbreMod, morphMod]);
        return u;
      };
      const root = plaits(p.pitch, lfo0, lfo1), top = plaits(p.pitch + p.fifth, lfo1, neg0);
      setTimeout(() => { root.lag({ pitch: 4 }); top.lag({ pitch: 4 }); }, 500);
      // swell = 1 + LFTri.kr([0.071, 0.053], [0, 2]) * 0.15 (phase 2: half a cycle on)
      const out = gain(), pans = [];
      [[root, 0.071, 0.15, -0.4, 1], [top, 0.053, -0.15, 0.4, 0.8]].forEach(([u, f, depth, pos, level]) => {
        const split = ctx.createChannelSplitter(2), swell = gain(level), s = tri(f, depth * level);
        const pan = ctx.createStereoPanner();
        s.node.connect(swell.gain); pan.pan.value = pos;
        u.connect(split); split.connect(swell, 0); swell.connect(pan); pan.connect(out);
        pans.push(s);
      });
      const amp = gain(p.amp), duck = gain(1 - p.duck * 0.5), hush = gain(p.hush);
      out.connect(amp); amp.connect(duck); duck.connect(hush);
      return { output: hush, units: [root, top], stop() { [t0, t1, ...pans].forEach(s => s.stop()); lift.stop(); },
        set(k, v, q) {
          if (k === "pitch" || k === "fifth") { root.set({ pitch: q.pitch }); top.set({ pitch: q.pitch + q.fifth }); }
          else if (k === "engine" || k === "harm") { root.set({ [k]: v }); top.set({ [k]: v }); }
          else if (k === "timbre" || k === "morph") { root.set({ [k]: v }); top.set({ [k]: v }); }
          else if (k === "wobble") { t0.node.gain.setValueAtTime(v, ctx.currentTime); t1.node.gain.setValueAtTime(v, ctx.currentTime); }
          else if (k === "lift") lagTo(lift.offset, v * 0.25, 0.3);
          else if (k === "amp") amp.gain.setValueAtTime(v, ctx.currentTime);
          else if (k === "duck") lagTo(duck.gain, 1 - v * 0.5, 0.4);
          else if (k === "hush") lagTo(hush.gain, v, 3);
        } };
    } },

    // Elements with its gate held open: bowed and blown for as long as it runs
    roots: { defaults: { pitch: 48, bow: 0.6, blow: 0.2, flow: 0.5, geom: 0.3, bright: 0.4, damp: 0.7, space: 0.5,
      model: 1, contour: 0.8, strength: 0.6, amp: 0.3, hush: 1, duck: 0, lift: 0 }, build(p) {
      const ctx = A.ctx;
      const u = A.mi.node("MiElements", { gate: 1, pit: ctl(p.pitch), strength: ctl(p.strength), contour: ctl(p.contour),
        bow_level: ctl(p.bow, 0.2), blow_level: ctl(p.blow, 0.2), flow: ctl(p.flow, 0.2), geom: ctl(p.geom, 0.2),
        bright: ctl(p.bright + p.lift * 0.3, 0.3), damp: ctl(p.damp), pos: 0.2, space: ctl(p.space, 0.2),
        model: ctl(p.model) });
      setTimeout(() => u.lag({ pit: 4 }), 500);
      const amp = gain(p.amp), duck = gain(1 - p.duck * 0.5), hush = gain(p.hush);
      u.connect(amp); amp.connect(duck); duck.connect(hush);
      const KEYS = { pitch: "pit", strength: "strength", contour: "contour", bow: "bow_level", blow: "blow_level",
        flow: "flow", geom: "geom", damp: "damp", space: "space", model: "model" };
      return { output: hush, units: [u], set(k, v, q) {
        if (KEYS[k]) u.set({ [KEYS[k]]: v });
        else if (k === "bright" || k === "lift") u.set({ bright: q.bright + q.lift * 0.3 });
        else if (k === "amp") amp.gain.setValueAtTime(v, ctx.currentTime);
        else if (k === "duck") lagTo(duck.gain, 1 - v * 0.5, 0.4);
        else if (k === "hush") lagTo(hush.gain, v, 3);
      } };
    } },
  };

  const make = (kind, params, dest) => synth(DEFS[kind].build, params, dest, DEFS[kind].defaults);

  // tape: the last stage, on everything. Wow and flutter wobble a short delay, a rolled-off top
  // and a soft saturation follow, crackle pops and a hiss are mixed in; "on" crossfades it in
  // and out, as the engine's terrarium_tape does
  function tapeChain(ctx, out) {
    const input = ctx.createGain(), dryG = ctx.createGain(), wetG = ctx.createGain(), driveG = ctx.createGain();
    const delay = ctx.createDelay(0.05), lp = ctx.createBiquadFilter(), shape = ctx.createWaveShaper();
    delay.delayTime.value = 0.01; lp.type = "lowpass";
    const curve = new Float32Array(1024);
    for (let i = 0; i < 1024; i++) { const x = i / 511.5 - 1; curve[i] = Math.tanh(x * 1.5) / 1.5; } // unity for quiet signals
    shape.curve = curve;
    const wow = ctx.createOscillator(), wowG = ctx.createGain(), flut = ctx.createOscillator(), flutG = ctx.createGain();
    wow.frequency.value = 0.5; flut.frequency.value = 6.3;
    wow.connect(wowG); wowG.connect(delay.delayTime); flut.connect(flutG); flutG.connect(delay.delayTime);
    input.connect(dryG); dryG.connect(out);
    input.connect(delay); delay.connect(lp); lp.connect(driveG); driveG.connect(shape); shape.connect(wetG); wetG.connect(out);
    // crackle: a loop of sparse pops (about 3 a second); hiss: noise above 2.5 kHz
    const sr = ctx.sampleRate, len = sr * 5, cb = ctx.createBuffer(2, len, sr);
    for (let ch = 0; ch < 2; ch++) {
      const d = cb.getChannelData(ch);
      for (let p = 0; p < 15; p++) {
        const at = Math.floor(Math.random() * (len - 200)), a = 0.3 + Math.random() * 0.7;
        for (let i = 0; i < 160; i++) d[at + i] += (Math.random() * 2 - 1) * a * Math.exp(-i / 30);
      }
    }
    const crack = ctx.createBufferSource(), crackG = ctx.createGain();
    crack.buffer = cb; crack.loop = true; crack.connect(crackG); crackG.connect(out);
    const hb = ctx.createBuffer(2, sr * 2, sr);
    for (let ch = 0; ch < 2; ch++) { const d = hb.getChannelData(ch); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; }
    const hiss = ctx.createBufferSource(), hp = ctx.createBiquadFilter(), hissG = ctx.createGain();
    hiss.buffer = hb; hiss.loop = true; hp.type = "highpass"; hp.frequency.value = 2500;
    hiss.connect(hp); hp.connect(hissG); hissG.connect(out);
    for (const n of [wow, flut, crack, hiss]) n.start();
    for (const g of [wetG, crackG, hissG, wowG, flutG]) g.gain.value = 0;
    return { input, dryG, wetG, driveG, lp, wowG, flutG, crackG, hissG };
  }

  function applyTape() {
    if (!A) return;
    const T = A.tape, t = A.ctx.currentTime, p = st.tape, on = (p.on ?? 0) > 0;
    const set = (param, v) => param.setTargetAtTime(v, t, 0.3);
    const drive = p.drive ?? 0;
    set(T.dryG.gain, on ? 0 : 1);
    set(T.wetG.gain, on ? 1 / (1 + drive * 2) : 0); // the drive warms loud parts, not the level
    set(T.driveG.gain, 1 + drive * 2);
    set(T.lp.frequency, 19000 - (p.tone ?? 0) * 12000);
    set(T.wowG.gain, on ? (p.wow ?? 0) * 0.003 : 0);
    set(T.flutG.gain, on ? (p.flutter ?? 0) * 0.0003 : 0);
    set(T.crackG.gain, on ? (p.crackle ?? 0) * 0.25 : 0);
    set(T.hissG.gain, on ? (p.hiss ?? 0) * 0.012 : 0);
  }

  // ---------- slots, as in the engine ----------

  // two Plaits round robin, or one Rings (polyphonic inside); the old voices fade out
  function setVoice(kind) {
    const old = voices;
    voices = null;
    if (kind && kind !== "none" && DEFS[`voice_${kind}`]) {
      const p = (st.voiceParams[kind] ??= {});
      voices = Array.from({ length: kind === "plaits" ? 2 : 1 }, () => make(`voice_${kind}`, p, A.voiceBus));
      nextVoice = 0;
    }
    old?.forEach(v => v.release());
  }

  // a slot synth for color, air or drone: the new one starts with every parameter sent so far,
  // then the old one fades out. A kind with no SynthDef (none) leaves the slot empty.
  function slot(kind, params, old, dest, input) {
    const s = kind && DEFS[kind] ? make(kind, params, dest) : null;
    if (s?.input && input) input.connect(s.input);
    if (old) { if (old.input && input) input.disconnect(old.input); old.release(); }
    return s;
  }
  const setColor = () => { colorSynth = slot(st.colorKind, st.colorParams, colorSynth, A.colorBus, A.voiceBus); };
  const setAir = () => { airSynth = slot(st.airKind, st.airParams, airSynth, A.tape.input, A.colorBus); };
  const setDrone = () => { droneSynth = slot(st.droneKind, st.droneParams, droneSynth, A.colorBus, null); };

  async function start(ctx, out) {
    let mi;
    try {
      if (!window.MiUGens) await new Promise((resolve, reject) => {
        const s = document.createElement("script");
        s.src = `${BASE}mi-ugens-node.js`; s.onload = resolve; s.onerror = () => reject(new Error("mi-ugens-node.js not found"));
        document.head.appendChild(s);
      });
      mi = await MiUGens.load(ctx, BASE, UGENS);
    } catch (e) {
      console.error("terrarium: can't load the mi-UGens, the engine stays silent:", e);
      return;
    }
    const tape = tapeChain(ctx, out);
    A = { ctx, mi, tape, voiceBus: null, colorBus: null };
    A.voiceBus = gain(); A.colorBus = gain();
    applyTape();
    setVoice(st.voiceKind); setColor(); setDrone(); setAir();
  }

  return {
    // the installer looks for mi-UGens with find: answer as if they're installed
    os_capture: cmd => (/^find .*\.sc/.test(cmd) ? "/norns-web/Mi.sc" : ""),
    start,
    note(pitch, accent, pan = 0) {
      if (!A || !voices) return;
      const v = voices[nextVoice];
      nextVoice = (nextVoice + 1) % voices.length;
      v.set("pitch", pitch); v.set("level", 0.5 + 0.5 * accent); v.set("pan", pan); v.set("t_trig", 1);
      if (st.colorKind === "pond" && colorSynth) { colorSynth.set("pitch", pitch); colorSynth.set("t_trig", 1); }
    },
    voice_kind(k) {
      if (k === st.voiceKind) return;
      st.voiceKind = k;
      if (A) setVoice(k);
    },
    voice_set(k, v) {
      if (!st.voiceKind || st.voiceKind === "none") return;
      (st.voiceParams[st.voiceKind] ??= {})[k] = v;
      voices?.forEach(s => s.set(k, v));
    },
    color_kind(k) { if (k === st.colorKind) return; st.colorKind = k; if (A) setColor(); },
    color_set(k, v) { st.colorParams[k] = v; colorSynth?.set(k, v); },
    air_kind(k) { if (k === st.airKind) return; st.airKind = k; if (A) setAir(); },
    air_set(k, v) { st.airParams[k] = v; airSynth?.set(k, v); },
    drone_kind(k) { if (k === st.droneKind) return; st.droneKind = k; if (A) setDrone(); },
    drone_set(k, v) { st.droneParams[k] = v; droneSynth?.set(k, v); },
    tape_set(k, v) { st.tape[k] = v; applyTape(); },
  };
};
})();
