// mi-UGens in the browser, main-thread side: loads the AudioWorklet module and
// the .wasm files, and makes AudioWorkletNodes that each run one UGen. A plain
// script (no module): it defines window.MiUGens.
//
//   const mi = await MiUGens.load(ctx, "path/to/mi-ugens/", ["MiPlaits", "MiClouds"]);
//   const plaits = mi.node("MiPlaits", { engine: 12, harm: { rate: "control", value: 0.5, lag: 0.05 },
//                                         trigger: { rate: "control" } });
//   plaits.connect(ctx.destination);         // output: one channel per UGen output
//   plaits.set({ harm: 0.3 }); plaits.trig({ trigger: 1 });
//
//   audio inputs: connect to input 0, one channel per audio input of the UGen
//   (named audio-rate inputs first, then the input array: `audio`, default 2)
//   modulation: connect to input 1, channel k is added to inputs with mod: k
//
// The spec format is described with MiUnit in mi-ugens.js.
(() => {
  const OUTPUTS = { MiRipples: 1 };  // the rest have two

  async function load(ctx, base, names) {
    await ctx.audioWorklet.addModule(`${base}mi-ugens.js`);
    const modules = {};
    await Promise.all(names.map(async n => {
      const bytes = await (await fetch(`${base}${n}.wasm`)).arrayBuffer();
      modules[n] = { bytes, module: await WebAssembly.compile(bytes) };
    }));
    let cloneModules = true;  // posting a compiled module to the worklet; bytes if the browser can't

    function node(name, spec = {}) {
      const m = modules[name];
      if (!m) throw new Error(`MiUGens: ${name} was not loaded`);
      // each input has as many channels as what's connected to it, never mixed
      const make = module => new AudioWorkletNode(ctx, "mi-ugen", {
        numberOfInputs: 2, numberOfOutputs: 1, outputChannelCount: [OUTPUTS[name] || 2],
        channelCountMode: "max", channelInterpretation: "discrete",
        processorOptions: { ugen: name, module, spec },
      });
      let n;
      if (cloneModules) {
        try { n = make(m.module); } catch (e) { cloneModules = false; }
      }
      if (!n) n = make(m.bytes);
      n.port.onmessage = ({ data }) => {
        if (data.log) console.log(`${name}: ${data.log}`);
        if (data.error) console.error(`${name}: ${data.error}`);
      };
      n.set = values => n.port.postMessage({ set: values });
      n.trig = values => n.port.postMessage({ trig: values });
      n.lag = values => n.port.postMessage({ lag: values });
      n.free = () => { n.port.postMessage({ free: true }); n.disconnect(); };
      return n;
    }
    return { node, modules };
  }

  window.MiUGens = { load };
})();
