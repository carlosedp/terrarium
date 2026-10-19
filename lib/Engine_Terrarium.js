// Engine_Terrarium.js: a browser stand-in for Engine_Terrarium.sc, used by
// tools/norns-web. norns ignores this file.
//
// It takes the same commands the script sends to SuperCollider (note,
// voice_kind/set, color_kind/set, air_kind/set) and plays rough Web Audio
// sketches of each slot, so the browser gives a feel for the routing and the
// macros. It is not the mi-UGens: tune the real sound on a norns.
//
//   voice (FM pair | plucked string | nothing for visitors) -> voiceBus
//     -> color (fog: lowpass | pond: a comb per note) -> colorOut
//     -> air (dry + delays | convolver) -> airOut -> out
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
    colorKind: null, color: {}, airKind: null, air: {},
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

  function env(g, t, peak, dur, attack = 0.006) {
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(peak, t + attack); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
  }

  // the pond: Rings as a comb ringing on each note (loop above the 128-sample minimum)
  function comb(src, f) {
    const { ctx } = A, c = st.color;
    const k = Math.max(1, Math.ceil(0.003 * f));
    const d = ctx.createDelay(1), fb = ctx.createGain(), out = ctx.createGain();
    const a = Math.exp(-2 * Math.PI * (1200 + (c.bright ?? 0.5) * 9000) / ctx.sampleRate);
    const lp = ctx.createIIRFilter([1 - a], [1, -a]);   // unity at DC, never above: the loop can't run away
    d.delayTime.value = k / f;
    fb.gain.value = Math.min(0.96, 0.8 + (c.damp ?? 0.6) * 0.16 + (c.struct ?? 0.4) * 0.04);
    out.gain.value = 0.4;
    src.connect(d); d.connect(lp); lp.connect(fb); fb.connect(d); lp.connect(out); out.connect(A.colorOut);
    setTimeout(() => { d.disconnect(); lp.disconnect(); fb.disconnect(); out.disconnect(); }, 7000);
  }

  function note(pitch, accent) {
    if (!A || A.ctx.state !== "running" || st.voiceKind === "none") return;
    const { ctx } = A, t = ctx.currentTime, f = hz(pitch);
    const peak = (0.12 + 0.14 * accent) * (st.voice[st.voiceKind]?.vol ?? 1);
    const out = ctx.createGain(); out.gain.value = 0;
    const nodes = [];
    let dur;
    if (st.voiceKind === "rings") {
      // a plucked string: a bright saw whose filter closes, plus a stranger partial with structure
      const v = st.voice.rings, osc = ctx.createOscillator(), lp = ctx.createBiquadFilter(), p2 = ctx.createOscillator(), g2 = ctx.createGain();
      osc.type = "sawtooth"; osc.frequency.value = f; lp.type = "lowpass"; lp.Q.value = 1.5;
      lp.frequency.setValueAtTime(f * (3 + (v.bright ?? 0.5) * 12), t); lp.frequency.exponentialRampToValueAtTime(f * 1.2, t + 0.8);
      p2.frequency.value = f * (2 + (v.struct ?? 0.4) * 1.3); env(g2, t, 0.03 + (v.struct ?? 0.4) * 0.06, 1.2, 0.002);
      osc.connect(lp); lp.connect(out); p2.connect(g2); g2.connect(out);
      dur = 0.8 + (v.damp ?? 0.6) * 2.4; env(out, t, peak, dur, 0.002);
      nodes.push(osc, p2);
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
      mod.connect(mg); mg.connect(car.frequency); car.connect(out);
      env(out, t, peak, dur);
      nodes.push(car, mod);
    }
    for (const n of nodes) { n.start(t); n.stop(t + dur + 0.05); }
    out.connect(A.voiceBus);
    if (st.colorKind === "pond") comb(out, f);
    setTimeout(() => out.disconnect(), (dur + 7) * 1000);
  }

  return {
    // the installer looks for mi-UGens with find: answer as if they're installed
    os_capture: cmd => (/^find .*\.sc/.test(cmd) ? "/norns-web/Mi.sc" : ""),
    start(ctx, out) { A = build(ctx, out); rewire(); apply(); },
    note,
    voice_kind(k) { st.voiceKind = k; },
    voice_set(k, v) { (st.voice[st.voiceKind] ??= {})[k] = v; },
    color_kind(k) { st.colorKind = k; rewire(); apply(); },
    color_set(k, v) { st.color[k] = v; applySoon(); },   // keys the sketch doesn't model are kept and ignored
    air_kind(k) { st.airKind = k; rewire(); apply(); },
    air_set(k, v) { st.air[k] = v; applySoon(); },
  };
};
})();
