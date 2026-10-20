// mi-UGens in the browser: runs the WebAssembly builds of mi-UGens (one .wasm
// per UGen, from build.sh --wasm) inside an AudioWorklet.
//
// This one file is both the AudioWorklet module (it registers the "mi-ugen"
// processor when loaded with audioWorklet.addModule) and a plain ES module
// (MiUnit and UGENS, for tests in node). The main-thread side, which loads the
// wasm and makes nodes, is mi-ugens-node.js.
//
// The unit runs as scsynth would run it: 64-sample blocks, inputs at scalar,
// control or audio rate (the wrappers check which), control inputs held for a
// block, triggers high for one block, and Lag on control inputs like .lag().

// Inputs in UGen order, with the defaults of the sclang classes (sc/Classes).
// "audio" names the trailing audio inputs of UGens that take an input array.
export const UGENS = {
  MiPlaits: { outputs: 2, inputs: [["pitch", 60], ["engine", 0], ["harm", 0.1], ["timbre", 0.5], ["morph", 0.5],
    ["trigger", 0], ["level", 0], ["fm_mod", 0], ["timb_mod", 0], ["morph_mod", 0], ["decay", 0.5], ["lpg_colour", 0.5]] },
  MiRings: { outputs: 2, inputs: [["in", 0], ["trig", 0], ["pit", 60], ["struct", 0.25], ["bright", 0.5], ["damp", 0.7],
    ["pos", 0.25], ["model", 0], ["poly", 1], ["intern_exciter", 0], ["easteregg", 0], ["bypass", 0]] },
  MiRipples: { outputs: 1, inputs: [["in", 0], ["cf", 0.3], ["reson", 0.2], ["drive", 1]] },
  MiClouds: { outputs: 2, audio: 2, inputs: [["pit", 0], ["pos", 0.5], ["size", 0.25], ["dens", 0.4], ["tex", 0.5],
    ["drywet", 0.5], ["in_gain", 1], ["spread", 0.5], ["rvb", 0], ["fb", 0], ["freeze", 0], ["mode", 0], ["lofi", 0],
    ["trig", 0]] },
  MiBeads: { outputs: 2, audio: 2, inputs: [["pitch", 0], ["pitch_rnd", 0], ["time", 0.5], ["time_rnd", 0], ["size", 0.5],
    ["size_rnd", 0], ["shape", 0.5], ["shape_rnd", 0], ["density", 0.7], ["fb", 0], ["drywet", 0.5], ["rvb", 0],
    ["freeze", 0], ["seed", 0], ["seed_btn", 2], ["quality", 0], ["in_gain", 1], ["synth", 0]] },
  // MiVerb processes its audio inputs in place: scsynth gives its outputs the
  // inputs' wire buffers, so the outputs alias them here too
  MiVerb: { outputs: 2, audio: 2, alias: true, inputs: [["time", 0.7], ["drywet", 0.5], ["damp", 0.5], ["hp", 0.05],
    ["freeze", 0], ["diff", 0.625]] },
  MiElements: { outputs: 2, inputs: [["blow_in", 0], ["strike_in", 0], ["gate", 0], ["pit", 48], ["strength", 0.5],
    ["contour", 0.2], ["bow_level", 0], ["blow_level", 0], ["strike_level", 0], ["flow", 0.5], ["mallet", 0.5],
    ["bow_timb", 0.5], ["blow_timb", 0.5], ["strike_timb", 0.5], ["geom", 0.25], ["bright", 0.5], ["damp", 0.7],
    ["pos", 0.2], ["space", 0.3], ["model", 0], ["easteregg", 0]] },
};

export const BLOCK = 64;
const RATE = { scalar: 0, control: 1, audio: 2 };
const LOG001 = Math.log(0.001);

// One unit in its own wasm instance.
//
// spec: { [input name]: number | { value, rate, lag, mod } }
//   rate  "scalar" (the default for a plain number), "control" or "audio".
//         A scalar input is a constant to the UGen: some treat "patched"
//         inputs differently (MiPlaits' trigger and level, MiRings' trig and
//         pit, MiBeads' seed), so only make an input control rate if the
//         SynthDef feeds it a control or signal.
//   lag   seconds, as .lag(t) on a control
//   mod   index of a channel of the modulation input added to the value
//         (read once a block, like a .kr signal)
//   audio inputs are filled from the audio input, in order: an audio-rate
//   named input, then the trailing input array (spec.audio channels)
export class MiUnit {
  constructor(name, module, sampleRate, spec = {}, log = msg => console.log(`${name}: ${msg}`)) {
    const def = UGENS[name];
    if (!def) throw new Error(`unknown UGen ${name}`);
    this.def = def;
    this.ctrlRate = sampleRate / BLOCK;
    if (!(module instanceof WebAssembly.Module)) module = new WebAssembly.Module(module);  // bytes
    let mem = null;
    const instance = new WebAssembly.Instance(module, { env: {
      mi_log: ptr => {
        const b = new Uint8Array(mem.buffer); let s = "";
        for (let i = ptr; b[i]; i++) s += String.fromCharCode(b[i]);
        log(s.trim());
      },
      emscripten_notify_memory_growth: () => {},
    } });
    const x = this.x = instance.exports;
    mem = x.memory;
    x._initialize?.();

    const nAudio = def.audio ? (spec.audio ?? def.audio) : 0;
    const nIn = this.nIn = def.inputs.length + nAudio;
    this.u = x.mi_new(sampleRate, BLOCK, nIn, def.outputs);
    this.inputs = {};  // name -> { index, rate, value, target, coef, mod, trig }
    this.audioIns = [];  // input indices fed from the audio input, in order
    def.inputs.forEach(([nm, dflt], index) => {
      let s = spec[nm];
      if (typeof s === "number") s = { value: s };
      s = s || {};
      const rate = RATE[s.rate || "scalar"];
      const value = s.value ?? dflt;
      const inp = { index, rate, value, target: value, coef: 0, mod: s.mod ?? -1, trig: false };
      this.inputs[nm] = inp;
      this.setLag(nm, s.lag || 0);
      x.mi_set_rate(this.u, index, rate);
      if (rate === RATE.audio) this.audioIns.push(index);
    });
    for (let i = 0; i < nAudio; i++) {
      const index = def.inputs.length + i;
      x.mi_set_rate(this.u, index, RATE.audio);
      this.audioIns.push(index);
      if (def.alias && i < def.outputs) x.mi_alias(this.u, i, index);
    }
    // Scalar inputs are read by the Ctor, so they must be in place before it.
    this.views();
    for (const inp of Object.values(this.inputs)) this.inBuf[inp.index][0] = inp.value;
    x.mi_init(this.u);
    this.views();  // the Ctor allocates, and memory may have grown
  }

  views() {
    const x = this.x, buf = x.memory.buffer;
    if (this.buffer === buf) return;
    this.buffer = buf;
    this.inBuf = [];
    for (let i = 0; i < this.nIn; i++) this.inBuf.push(new Float32Array(buf, x.mi_in(this.u, i), BLOCK));
    this.outBuf = [];
    for (let i = 0; i < this.def.outputs; i++) this.outBuf.push(new Float32Array(buf, x.mi_out(this.u, i), BLOCK));
  }

  set(name, value) {
    const inp = this.inputs[name];
    if (!inp) return;
    inp.target = value;
    if (inp.coef === 0 || inp.rate === RATE.scalar) inp.value = value;
  }

  // a t_trig control: the value for one block, then 0
  trig(name, value = 1) {
    const inp = this.inputs[name];
    if (!inp) return;
    inp.value = inp.target = value;
    inp.trig = true;
  }

  setLag(name, seconds) {
    const inp = this.inputs[name];
    if (inp) inp.coef = seconds > 0 ? Math.exp(LOG001 / (seconds * this.ctrlRate)) : 0;
  }

  // Runs one block. audio: arrays of BLOCK samples for the audio inputs (or
  // null); mods: the modulation channels (or null); out: arrays to fill.
  process(audio, mods, out) {
    this.views();
    for (const inp of Object.values(this.inputs)) {
      if (inp.rate === RATE.audio) continue;
      if (inp.coef) inp.value = inp.target + inp.coef * (inp.value - inp.target);
      let v = inp.value;
      if (inp.mod >= 0 && mods && mods[inp.mod]) v += mods[inp.mod][0];
      this.inBuf[inp.index][0] = v;
      if (inp.trig) { inp.trig = false; inp.value = inp.target = 0; }
    }
    this.audioIns.forEach((index, k) => {
      const src = audio && audio[k];
      if (src) this.inBuf[index].set(src); else this.inBuf[index].fill(0);
    });
    this.x.mi_next(this.u, BLOCK);
    for (let i = 0; i < out.length && i < this.outBuf.length; i++) out[i].set(this.outBuf[i]);
  }

  free() {
    if (this.u) this.x.mi_free(this.u);
    this.u = 0;
  }
}

// AudioWorklet side. processorOptions: { ugen, module (or its bytes), spec }. Input 0 carries
// the audio inputs (one channel each), input 1 the modulation channels; output
// 0 has one channel per UGen output. Messages on the port:
//   { set: { name: value, ... } }   { trig: { name: value, ... } }
//   { lag: { name: seconds, ... } }   { free: true }
if (typeof registerProcessor === "function") {
  registerProcessor("mi-ugen", class extends AudioWorkletProcessor {
    constructor(options) {
      super();
      const o = options.processorOptions;
      try {
        this.unit = new MiUnit(o.ugen, o.module, sampleRate, o.spec, msg => this.port.postMessage({ log: msg }));
      } catch (e) {
        this.port.postMessage({ error: String(e) });
      }
      this.port.onmessage = ({ data }) => {
        const u = this.unit;
        if (!u) return;
        if (data.set) for (const k in data.set) u.set(k, data.set[k]);
        if (data.trig) for (const k in data.trig) u.trig(k, data.trig[k]);
        if (data.lag) for (const k in data.lag) u.setLag(k, data.lag[k]);
        if (data.free) { u.free(); this.unit = null; }
      };
      this.out = null;
    }

    process(inputs, outputs) {
      const u = this.unit;
      if (!u) return false;
      const out = outputs[0], n = out[0].length;
      const audio = inputs[0], mods = inputs[1];
      if (!this.out) this.out = out.map(() => new Float32Array(BLOCK));
      for (let off = 0; off < n; off += BLOCK) {
        const a = audio && audio.length ? audio.map(ch => ch.subarray(off, off + BLOCK)) : null;
        const m = mods && mods.length ? mods.map(ch => ch.subarray(off, off + BLOCK)) : null;
        u.process(a, m, this.out);
        for (let c = 0; c < out.length; c++) out[c].set(this.out[c], off);
      }
      return true;
    }
  });
}
