// Engine_Terrarium.js: a browser stand-in for Engine_Terrarium.sc, used by
// tools/norns-web. norns ignores this file.
//
// It takes the same commands the script sends to SuperCollider (note,
// voice_kind/set, color_kind/set, air_kind/set) and plays rough Web Audio
// sketches of each slot, so the browser gives a feel for the routing and the
// macros. It is not the mi-UGens: tune the real sound on a norns.
//
//   voice (FM pair through a low-pass gate | noise burst into resonators | nothing for visitors)
//     -> voiceBus -> color (fog: lowpass | pond: tuned resonators per note) -> colorOut
//     -> air (dry + delays | convolver) -> airOut -> out
//   drone (aurora: two detuned waves on root and fifth | roots: a bowed tone with
//     breath noise around it) -> into the air, like colorBus
// Each slot's vol (the levels group in PARAMS) scales its whole output, as in the engine.
(() => {
const RATIOS = [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4];
// Plaits engine -> carrier wave, a rough nod to each family (18-20: the 6-op FM banks)
const WAVE = { 12: "sine", 11: "triangle", 4: "sine", 5: "sawtooth", 22: "triangle", 6: "triangle", 16: "sawtooth",
  17: "square", 21: "triangle", 1: "square", 2: "square", 3: "triangle" };
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const hz = midi => 440 * Math.pow(2, (midi - 69) / 12);

NornsWeb.engines.Terrarium = () => {
  const st = {
    voiceKind: "plaits", voice: { plaits: { engine: 12, harm: 0.5, timbre: 0.5, decay: 0.5 }, rings: { struct: 0.4, bright: 0.5, damp: 0.6 } },
    colorKind: null, color: {}, airKind: null, air: {}, droneKind: null, drone: {},
  };
  let A = null, applyTimer = 0;

  function build(ctx, out) {
    const voiceBus = ctx.createGain(), fog = ctx.createBiquadFilter(), spaceIn = ctx.createGain(), dry = ctx.createGain();
    const colorOut = ctx.createGain(), airOut = ctx.createGain();
    fog.type = "lowpass"; colorOut.connect(spaceIn); airOut.connect(out); dry.connect(airOut);
    // clouds and fireflies: two cross-fed delays with a little wobble
    const cl = { in: ctx.createGain(), dA: ctx.createDelay(2), dB: ctx.createDelay(2), fbA: ctx.createGain(), fbB: ctx.createGain(),
      lp: ctx.createBiquadFilter(), out: ctx.createGain(), lfo: ctx.createOscillator(), lfoG: ctx.createGain(),
      pA: ctx.createStereoPanner(), pB: ctx.createStereoPanner() };
    cl.lp.type = "lowpass";
    cl.in.connect(cl.dA); cl.dA.connect(cl.lp); cl.lp.connect(cl.fbA); cl.fbA.connect(cl.dB); cl.dB.connect(cl.fbB); cl.fbB.connect(cl.dA);
    cl.dA.connect(cl.pA); cl.dB.connect(cl.pB); cl.pA.pan.value = -0.6; cl.pB.pan.value = 0.6;
    cl.pA.connect(cl.out); cl.pB.connect(cl.out); cl.out.connect(airOut);
    cl.lfo.connect(cl.lfoG); cl.lfoG.connect(cl.dA.delayTime); cl.lfoG.connect(cl.dB.delayTime); cl.lfo.start();
    // mountains: a convolver with a decaying noise impulse
    const vb = { conv: ctx.createConvolver(), out: ctx.createGain() };
    vb.conv.connect(vb.out); vb.out.connect(airOut);
    return { ctx, out, voiceBus, fog, spaceIn, dry, colorOut, airOut, cl, vb, irLen: 0, irTimer: 0 };
  }

  function rewire() {
    if (!A) return;
    const { voiceBus, fog, spaceIn, dry, colorOut, cl, vb } = A;
    voiceBus.disconnect(); fog.disconnect(); spaceIn.disconnect();
    if (st.colorKind === "fog") { voiceBus.connect(fog); fog.connect(colorOut); } else voiceBus.connect(colorOut);
    spaceIn.connect(dry);
    if (st.airKind === "mountains") spaceIn.connect(vb.conv); else spaceIn.connect(cl.in);
  }

  function makeIR(seconds) {
    const { ctx } = A, len = Math.floor(ctx.sampleRate * seconds), b = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let ch = 0; ch < 2; ch++) { const d = b.getChannelData(ch); for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.exp(-i / len * 5.5); }
    return b;
  }

  function apply() {
    if (!A) return;
    const t = A.ctx.currentTime, set = (p, v) => p.setTargetAtTime(v, t, 0.05);
    const c = st.color, a = st.air, cl = A.cl;
    set(A.colorOut.gain, c.vol ?? 1); set(A.airOut.gain, a.vol ?? 1);
    set(A.fog.frequency, 60 * Math.pow(2, (c.cf ?? 0.5) * 8.5));
    set(A.fog.Q, 0.5 + (c.reson ?? 0.2) * 12);
    const frozen = !!a.freeze;
    if (st.airKind === "clouds") {               // long smeared grains
      const d = 0.06 + (a.size ?? 0.4) * 0.5;
      set(cl.dA.delayTime, d); set(cl.dB.delayTime, d * 1.47);
      set(cl.lfo.frequency, 0.6); set(cl.lfoG.gain, 0.004); set(cl.lp.frequency, 4200);
      set(cl.out.gain, (a.drywet ?? 0.45) * (0.6 + (a.dens ?? 0.5) * 0.6));
      const fb = frozen ? 0.95 : clamp(0.2 + (a.fb ?? 0.2) * 1.2 + (a.dens ?? 0.5) * 0.2, 0, 0.9);
      set(cl.fbA.gain, fb); set(cl.fbB.gain, fb);
    } else if (st.airKind === "fireflies") {     // short shimmering grains
      const d = 0.02 + (a.size ?? 0.5) * 0.18;
      set(cl.dA.delayTime, d); set(cl.dB.delayTime, d * 1.61);
      set(cl.lfo.frequency, 3.1); set(cl.lfoG.gain, 0.0025); set(cl.lp.frequency, 7000);
      set(cl.out.gain, 0.3 + ((a.density ?? 0.7) - 0.5) * 1.0);
      const fb = frozen ? 0.95 : clamp(0.25 + (a.fb ?? 0.2) * 1.5, 0, 0.9);
      set(cl.fbA.gain, fb); set(cl.fbB.gain, fb);
    }
    set(cl.in.gain, frozen && st.airKind !== "mountains" ? 0 : 1);
    if (st.airKind === "mountains") {
      set(A.vb.out.gain, 0.15 + (a.drywet ?? 0.4) * 1.4);
      const irLen = frozen ? 9 : 0.6 + clamp(((a.time ?? 0.7) - 0.5) / 0.47, 0, 1) * 5;
      if (Math.abs(irLen - A.irLen) > 0.05) {
        clearTimeout(A.irTimer);
        A.irTimer = setTimeout(() => { A.vb.conv.buffer = makeIR(irLen); A.irLen = irLen; }, A.irLen ? 220 : 0);
      }
    }
  }
  // set commands can arrive every frame (the climate): apply at most every 50 ms
  const applySoon = () => { if (!applyTimer) applyTimer = setTimeout(() => { applyTimer = 0; apply(); }, 50); };

  let noiseBuf = null;
  const noise = ctx => {
    if (!noiseBuf) {
      noiseBuf = ctx.createBuffer(1, ctx.sampleRate / 4, ctx.sampleRate);
      const d = noiseBuf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    }
    return noiseBuf;
  };

  function env(g, t, peak, dur, attack = 0.006) {
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(peak, t + attack); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
  }

  // the pond: Rings as a comb ringing on each note (loop above the 128-sample minimum)
  // Rings, roughly: a bank of tuned resonators (high-Q bandpass filters) on a note's
  // partials. structure stretches the partials from a string toward a bell, brightness
  // keeps the upper ones, damping (Rings: higher is longer) sets how long they ring.
  // It rings at the note's pitch (a delay loop can't, above ~375 Hz, in Web Audio).
  function resonate(src, f, { struct = 0.4, bright = 0.5, damp = 0.6 }, dest, gain) {
    const { ctx } = A, out = ctx.createGain(), nodes = [];
    out.gain.value = gain;
    for (let k = 1; k <= 6; k++) {
      const ratio = Math.pow(k, 1 + struct * 0.45);          // 1, 2, 3... stretched toward inharmonic
      const fk = f * ratio;
      if (fk > ctx.sampleRate * 0.45) break;
      const bp = ctx.createBiquadFilter(), g = ctx.createGain();
      bp.type = "bandpass"; bp.frequency.value = fk;
      bp.Q.value = (40 + damp * 360) * Math.sqrt(k);          // higher partials die sooner in seconds
      g.gain.value = Math.pow(0.25 + bright * 0.7, k - 1) * Math.sqrt(bp.Q.value) * 0.18;
      src.connect(bp); bp.connect(g); g.connect(out); nodes.push(bp, g);
    }
    out.connect(dest);
    setTimeout(() => { nodes.forEach(n => n.disconnect()); out.disconnect(); }, 9000);
  }

  function note(pitch, accent) {
    if (!A || A.ctx.state !== "running" || st.voiceKind === "none") return;
    const { ctx } = A, t = ctx.currentTime, f = hz(pitch);
    const peak = (0.12 + 0.14 * accent) * (st.voice[st.voiceKind]?.vol ?? 1);
    const out = ctx.createGain(); out.gain.value = 0;
    const nodes = [];
    let dur;
    if (st.voiceKind === "rings") {
      // Rings' internal exciter: a pluck at the note (a decaying saw, so its energy lands on
      // the partials) with a touch of noise for the attack, into the resonators
      const v = st.voice.rings, saw = ctx.createOscillator(), burst = ctx.createBufferSource(), ex = ctx.createGain(), ng = ctx.createGain();
      saw.type = "sawtooth"; saw.frequency.value = f;
      ex.gain.setValueAtTime(1, t); ex.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
      burst.buffer = noise(ctx); ng.gain.setValueAtTime(0.4, t); ng.gain.exponentialRampToValueAtTime(0.001, t + 0.01);
      saw.connect(ex); burst.connect(ng); ng.connect(ex);
      resonate(ex, f, v, out, 7);
      out.gain.value = peak * 2.5;
      dur = 0.06;
      nodes.push(saw, burst);
    } else {
      const v = st.voice.plaits, eng = v.engine ?? 12, h = v.harm ?? 0.5, tb = v.timbre ?? 0.5;
      const car = ctx.createOscillator(), mod = ctx.createOscillator(), mg = ctx.createGain();
      car.frequency.value = f;
      if (eng >= 18 && eng <= 20) {
        // the 6-op banks (crystals): glassy FM with an inharmonic ratio and a quiet upper partial
        mod.frequency.value = f * (1.41 + h * 2.1);
        mg.gain.setValueAtTime(f * (0.5 + tb * 7), t); mg.gain.exponentialRampToValueAtTime(f * 0.02 + 0.01, t + 1.1);
        const p2 = ctx.createOscillator(), g2 = ctx.createGain(); p2.frequency.value = f * 2.76; env(g2, t, 0.05, 0.7);
        p2.connect(g2); g2.connect(out); nodes.push(p2);
        dur = 1.2 + (v.decay ?? 0.6) * 1.2;
      } else {
        car.type = WAVE[eng] || "sine";
        mod.frequency.value = f * RATIOS[Math.min(7, Math.floor(h * 8))];
        mg.gain.setValueAtTime(f * (0.2 + tb * 5), t); mg.gain.exponentialRampToValueAtTime(f * 0.05 + 0.01, t + 0.5);
        dur = 0.5 + (v.decay ?? 0.5) * 1.6;
      }
      // Plaits' low-pass gate: the tone closes as it decays
      const lpg = ctx.createBiquadFilter();
      lpg.type = "lowpass"; lpg.Q.value = 0.8;
      lpg.frequency.setValueAtTime(Math.min(18000, f * (2 + tb * 14)), t);
      lpg.frequency.exponentialRampToValueAtTime(f * 1.1, t + dur);
      mod.connect(mg); mg.connect(car.frequency); car.connect(lpg); lpg.connect(out);
      env(out, t, peak, dur);
      nodes.push(car, mod);
    }
    for (const n of nodes) { n.start(t); n.stop(t + dur + 0.05); }
    const pan = ctx.createStereoPanner(); pan.pan.value = (Math.random() * 2 - 1) * 0.3; // each note its place, as in the engine
    out.connect(pan); pan.connect(A.voiceBus);
    if (st.colorKind === "pond") resonate(pan, f, st.color, A.colorOut, 0.5 * (st.color.mix ?? 0.8));
    setTimeout(() => { out.disconnect(); pan.disconnect(); }, (dur + 9) * 1000);
  }

  // the drone: built when sound starts or the module changes, then only retuned
  let D = null;
  function droneStop() {
    if (!D) return;
    const t = A.ctx.currentTime, old = D;
    old.out.gain.setTargetAtTime(0, t, 0.3);
    setTimeout(() => { old.nodes.forEach(n => { try { n.stop(); } catch (e) {} }); old.out.disconnect(); }, 2000);
    D = null;
  }
  function droneBuild() {
    if (!A) return;
    droneStop();
    if (!st.droneKind || st.droneKind === "none") return;
    const { ctx } = A, d = st.drone, out = ctx.createGain(), nodes = [], tones = [];
    out.gain.value = 0;
    if (st.droneKind === "aurora") {
      // a soft pad on root and fifth: a triangle and a sine a few cents apart, a quiet
      // octave above the root for air; the filter breathes, and each voice swells on its
      // own slow cycle (the fifth a little quieter than the root)
      for (const [off, pan, rate, level] of [[0, -0.4, 0.071, 1], [7, 0.4, 0.053, 0.8]]) {
        const o = ctx.createOscillator(), o2 = ctx.createOscillator(), lp = ctx.createBiquadFilter();
        const p = ctx.createStereoPanner(), voice = ctx.createGain();
        o.type = "triangle"; o.detune.value = -4; o2.type = "sine"; o2.detune.value = 5;
        lp.type = "lowpass"; lp.Q.value = 0.5; p.pan.value = pan; voice.gain.value = level;
        o.connect(lp); o2.connect(lp); lp.connect(voice); voice.connect(p); p.connect(out);
        const oscs = [o, o2];
        if (!off) { // the octave above the root
          const o3 = ctx.createOscillator(), g3 = ctx.createGain();
          o3.type = "sine"; g3.gain.value = 0.12; o3.connect(g3); g3.connect(lp); oscs.push(o3);
        }
        const lfo = ctx.createOscillator(), lg = ctx.createGain(); lfo.frequency.value = off ? 0.063 : 0.05;
        lfo.connect(lg); lg.connect(lp.frequency);
        const swell = ctx.createOscillator(), sg = ctx.createGain(); swell.type = "triangle"; swell.frequency.value = rate;
        sg.gain.value = 0.15 * level; swell.connect(sg); sg.connect(voice.gain);
        nodes.push(...oscs, lfo, swell); tones.push({ off, oscs, lp, lg });
      }
    } else {
      // a bowed tone (a saw, softened, with a slow bow pressure wobble) and breath noise
      // around its pitch; breath crossfades from the bow to the breath
      const bowed = ctx.createOscillator(), lp = ctx.createBiquadFilter(), bowGain = ctx.createGain();
      const lfo = ctx.createOscillator(), lg = ctx.createGain();
      bowed.type = "sawtooth"; lp.type = "lowpass"; lp.Q.value = 2;
      lfo.frequency.value = 0.21; lg.gain.value = 0.15; lfo.connect(lg); lg.connect(bowGain.gain);
      bowed.connect(lp); lp.connect(bowGain); bowGain.connect(out);
      const src = ctx.createBufferSource(), bp = ctx.createBiquadFilter(), breathGain = ctx.createGain();
      const len = ctx.sampleRate * 2, b = ctx.createBuffer(1, len, ctx.sampleRate), data = b.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
      src.buffer = b; src.loop = true; bp.type = "bandpass"; bp.Q.value = 6;
      src.connect(bp); bp.connect(breathGain); breathGain.connect(out);
      nodes.push(bowed, lfo, src); tones.push({ off: 0, bowed, lp, bowGain, bp, breathGain });
    }
    for (const n of nodes) n.start();
    out.connect(A.spaceIn);
    D = { out, nodes, tones, fresh: true };
    droneApply();
  }
  function droneApply() {
    if (!D) return;
    const t = A.ctx.currentTime, d = st.drone, root = d.pitch ?? 50;
    // a new drone starts on its pitch; after that it glides when the key turns, like the engine
    const pitchTo = (param, f) => D.fresh ? param.setValueAtTime(f, t) : param.setTargetAtTime(f, t, 1.3);
    for (const tone of D.tones) {
      const f = hz(root + (tone.off ? (d.fifth ?? 7) : 0));
      if (tone.oscs) {
        tone.oscs.forEach((o, i) => pitchTo(o.frequency, i === 2 ? f * 2 : f));
        tone.lp.frequency.setTargetAtTime(f * (2 + (d.timbre ?? 0.4) * 5), t, 0.2);
        tone.lg.gain.setTargetAtTime(f * (0.3 + (d.wobble ?? 0.1) * 3), t, 0.2);   // the filter breathes
      } else {
        const bow = d.bow ?? 0.6, blow = d.blow ?? 0.2;
        pitchTo(tone.bowed.frequency, f);
        tone.lp.frequency.setTargetAtTime(f * (2 + (d.geom ?? 0.3) * 8), t, 0.2);   // depth opens it up
        tone.bowGain.gain.setTargetAtTime(0.25 + bow * 0.75, t, 0.3);
        pitchTo(tone.bp.frequency, f * 2);
        tone.breathGain.gain.setTargetAtTime(blow * 2.5, t, 0.3);
      }
    }
    const level = (st.droneKind === "aurora" ? 0.3 : 0.6) * (d.hush ?? 1) * (d.vol ?? 1);
    D.out.gain.setTargetAtTime(level, t, d.hush === 0 ? 1.2 : 0.4);
    if (d.pitch !== undefined) D.fresh = false;
  }

  return {
    // the installer looks for mi-UGens with find: answer as if they're installed
    os_capture: cmd => (/^find .*\.sc/.test(cmd) ? "/norns-web/Mi.sc" : ""),
    start(ctx, out) { A = build(ctx, out); rewire(); apply(); droneBuild(); },
    note,
    voice_kind(k) { st.voiceKind = k; },
    voice_set(k, v) { (st.voice[st.voiceKind] ??= {})[k] = v; },
    color_kind(k) { st.colorKind = k; rewire(); apply(); },
    color_set(k, v) { st.color[k] = v; applySoon(); },   // keys the sketch doesn't model are kept and ignored
    air_kind(k) { st.airKind = k; rewire(); apply(); },
    air_set(k, v) { st.air[k] = v; applySoon(); },
    drone_kind(k) { st.droneKind = k; droneBuild(); },
    drone_set(k, v) { st.drone[k] = v; droneApply(); },
  };
};
})();
