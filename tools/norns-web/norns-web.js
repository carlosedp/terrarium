// norns-web: run a norns script's real Lua in the browser.
//
// files.json says which script to run and carries its .lua files. They're
// mounted into a Lua VM (wasmoon, Lua 5.4) under /code/<name>/, norns.lua
// provides the norns API, and this file drives it: one norns_web.tick() per
// animation frame, the screen drawn to a canvas, encoders and keys from the
// page, a PARAMS panel, and engine commands sent to a JS stand-in for the
// SuperCollider engine (script/lib/Engine_<name>.js, if the script has one).
(() => {
  "use strict";

  const W = 128,
    H = 64;
  const $ = (sel) => document.querySelector(sel);

  // ---------- log ----------
  const logEl = $("#log");
  let showEngine = false;
  function log(text, kind = "print") {
    if (kind === "engine" && !showEngine) return;
    const line = document.createElement("div");
    line.className = kind;
    line.textContent = text;
    logEl.appendChild(line);
    while (logEl.childNodes.length > 300) logEl.removeChild(logEl.firstChild);
    logEl.scrollTop = logEl.scrollHeight;
  }
  $("#show-engine").addEventListener("change", (e) => {
    showEngine = e.target.checked;
  });

  // the grip at its bottom-right corner makes the log taller or shorter (arrow keys too); remembered
  {
    const grip = $("#log-grip"),
      KEY = "norns-web:log-height";
    const setHeight = (px) => {
      const h = Math.max(
        64,
        Math.min(Math.round(px), Math.round(window.innerHeight * 0.9)),
      );
      logEl.style.height = h + "px";
      try {
        localStorage.setItem(KEY, h);
      } catch (e) {}
    };
    try {
      const h = +localStorage.getItem(KEY);
      if (h) logEl.style.height = h + "px";
    } catch (e) {}
    let startY = 0,
      startH = 0;
    grip.addEventListener("pointerdown", (e) => {
      startY = e.clientY;
      startH = logEl.getBoundingClientRect().height;
      grip.setPointerCapture(e.pointerId);
      e.preventDefault();
    });
    grip.addEventListener("pointermove", (e) => {
      if (grip.hasPointerCapture(e.pointerId))
        setHeight(startH + e.clientY - startY);
    });
    grip.addEventListener("keydown", (e) => {
      const d = { ArrowDown: 24, ArrowUp: -24 }[e.key];
      if (d) {
        setHeight(logEl.getBoundingClientRect().height + d);
        e.preventDefault();
      }
    });
  }

  // ---------- screen ----------
  const cvs = $("#oled"),
    g2d = cvs.getContext("2d"),
    img = g2d.createImageData(W, H);
  // the OLED's color: white, or the amber-yellow some norns shields have
  const TINTS = { white: [248, 245, 236], yellow: [255, 196, 40] };
  let PAL = [],
    lastFrame = null;
  function setTint(name) {
    const c = TINTS[name] || TINTS.white;
    PAL = [];
    for (let l = 0; l < 16; l++) {
      const v = l === 0 ? 0 : Math.pow(l / 15, 0.8); // roughly how the OLED's levels look
      PAL.push(c.map((x) => Math.round(v * x)));
    }
    if (lastFrame) blit(lastFrame);
  }
  function blit(frame) {
    lastFrame = frame;
    const d = img.data;
    for (let i = 0; i < W * H; i++) {
      const p = PAL[frame.charCodeAt(i) - 65] || PAL[0],
        o = i * 4;
      d[o] = p[0];
      d[o + 1] = p[1];
      d[o + 2] = p[2];
      d[o + 3] = 255;
    }
    g2d.putImageData(img, 0, 0);
  }

  // ---------- view: the shell (norns | shield) and the screen's color, remembered ----------
  const view = (() => {
    try {
      return JSON.parse(localStorage.getItem("norns-web:view")) || {};
    } catch (e) {
      return {};
    }
  })();
  const query = new URLSearchParams(location.search);
  view.shell = query.get("shell") || view.shell || "shield";
  view.screen = query.get("screen") || view.screen || "white";
  function applyView() {
    $("#device").dataset.shell = view.shell;
    $("#v-shell").value = view.shell;
    $("#v-screen").value = view.screen;
    setTint(view.screen);
    try {
      localStorage.setItem("norns-web:view", JSON.stringify(view));
    } catch (e) {}
  }
  $("#v-shell").addEventListener("change", (e) => {
    view.shell = e.target.value;
    applyView();
  });
  $("#v-screen").addEventListener("change", (e) => {
    view.screen = e.target.value;
    applyView();
  });
  applyView();

  // ---------- engine stand-ins ----------
  // A script's lib/Engine_<name>.js registers itself here; it gets every engine
  // command, and start(ctx, out) once the page's sound is switched on.
  window.NornsWeb = { engines: {} };
  let engine = null;
  const unknown = new Set();
  function loadScript(src) {
    return new Promise((resolve) => {
      const s = document.createElement("script");
      s.src = src;
      s.onload = () => resolve(true);
      s.onerror = () => resolve(false);
      document.head.appendChild(s);
    });
  }
  function engineCall(cmd, ...args) {
    log(
      `engine.${cmd}(${args.map((a) => (typeof a === "string" ? JSON.stringify(a) : +(+a).toFixed(4))).join(", ")})`,
      "engine",
    );
    if (engine && typeof engine[cmd] === "function") {
      try {
        engine[cmd](...args);
      } catch (e) {
        log(`engine stand-in: ${cmd}: ${e.message}`, "error");
      }
    } else if (!unknown.has(cmd)) {
      unknown.add(cmd);
      if (engine) log(`engine stand-in has no command '${cmd}'`, "error");
    }
  }

  // ---------- sound ----------
  let audio = null;
  const soundBtn = $("#sound");
  // the button follows the audio's actual state: a new context starts "suspended" and
  // only turns "running" a moment later, and the browser can change it by itself
  function showSound() {
    const on = !!audio && audio.ctx.state === "running";
    for (const b of [soundBtn, $("#full-sound")]) {
      b.setAttribute("aria-pressed", on ? "true" : "false");
      b.textContent = on ? "Mute" : "Start sound";
    }
  }
  soundBtn.addEventListener("click", async () => {
    if (!audio) {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const out = ctx.createGain();
      out.gain.value = 0.75;
      const comp = ctx.createDynamicsCompressor();
      comp.threshold.value = -16;
      comp.ratio.value = 4;
      out.connect(comp);
      comp.connect(ctx.destination);
      audio = { ctx, out };
      ctx.onstatechange = showSound;
      if (engine && engine.start) engine.start(ctx, out);
      await ctx.resume();
    } else if (audio.ctx.state === "running") await audio.ctx.suspend();
    else await audio.ctx.resume();
    showSound();
  });
  $("#full-sound").addEventListener("click", () => soundBtn.click());

  // ---------- full screen: just the device, filling the screen like a real one ----------
  // The browser's fullscreen where it allows it; otherwise (an iPhone) the device covers the
  // window. Laid out at a natural width (capped by the window), then scaled to fit.
  {
    const frame = $("#frame"),
      device = $("#device"),
      fullBtn = $("#full");
    let full = false;
    const fit = () => {
      if (!full) return;
      const vw = window.innerWidth,
        vh = window.innerHeight,
        pad = 16,
        bar = 48;
      device.style.transform = "";
      device.style.width =
        Math.min(device.dataset.shell === "norns" ? 720 : 540, vw - 2 * pad) +
        "px";
      const r = device.getBoundingClientRect();
      const s = Math.min(
        (vw - 2 * pad) / r.width,
        (vh - 2 * pad - bar) / r.height,
      );
      device.style.transform = `scale(${s})`;
    };
    const enter = () => {
      full = true;
      frame.classList.add("full");
      document.body.classList.add("full");
      fullBtn.setAttribute("aria-pressed", "true");
      const req = frame.requestFullscreen || frame.webkitRequestFullscreen;
      if (req)
        Promise.resolve(req.call(frame, { navigationUI: "hide" })).catch(
          () => {},
        );
      fit();
    };
    const exit = () => {
      if (!full) return;
      full = false;
      frame.classList.remove("full");
      document.body.classList.remove("full");
      fullBtn.setAttribute("aria-pressed", "false");
      device.style.transform = "";
      device.style.width = "";
      const fsEl =
        document.fullscreenElement || document.webkitFullscreenElement;
      if (fsEl)
        (document.exitFullscreen || document.webkitExitFullscreen).call(
          document,
        );
      fullBtn.focus();
    };
    fullBtn.addEventListener("click", enter);
    $("#full-exit").addEventListener("click", exit);
    // leaving the browser's fullscreen (Esc, a swipe) leaves the view too
    const onFsChange = () => {
      if (!(document.fullscreenElement || document.webkitFullscreenElement))
        exit();
    };
    document.addEventListener("fullscreenchange", onFsChange);
    document.addEventListener("webkitfullscreenchange", onFsChange);
    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && full) exit();
    });
    window.addEventListener("resize", fit);
    $("#v-shell").addEventListener("change", fit);
  }

  // ---------- the built-in nb voice ("web synth" in norns.lua) ----------
  // a soft triangle per note, its filter opened by modulate, straight to the output
  const nbNotes = new Map();
  let nbBright = 0.5;
  function nbCall(kind, note, v) {
    if (!audio || audio.ctx.state !== "running") return;
    const { ctx, out } = audio,
      t = ctx.currentTime;
    const release = (n) => {
      const s = nbNotes.get(n);
      if (!s) return;
      s.g.gain.setTargetAtTime(0, t, 0.15);
      s.o.stop(t + 1);
      nbNotes.delete(n);
    };
    if (kind === "mod") {
      nbBright = v;
      return;
    }
    if (kind === "off") {
      release(note);
      return;
    }
    release(note);
    const o = ctx.createOscillator(),
      f = ctx.createBiquadFilter(),
      g = ctx.createGain();
    o.type = "triangle";
    o.frequency.value = 440 * Math.pow(2, (note - 69) / 12);
    f.type = "lowpass";
    f.frequency.value = o.frequency.value * (1.5 + nbBright * 10);
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.18 * v, t + 0.01);
    o.connect(f);
    f.connect(g);
    g.connect(out);
    o.start(t);
    nbNotes.set(note, { o, g });
  }

  // ---------- the script's own page text (norns-web.json): title, intro, links, footer ----------
  function showAbout(a) {
    if (a.title) {
      $("#script-name").textContent = a.title;
      document.title = a.title;
    }
    if (a.subtitle) {
      const s = $("#subtitle");
      s.textContent = a.subtitle;
      s.hidden = false;
    }
    if (a.about) $(".lede").textContent = a.about;
    const link = (l) => {
      const el = document.createElement("a");
      el.href = l.url;
      el.textContent = l.label;
      el.rel = "noopener";
      return el;
    };
    if (a.links && a.links.length) $("#links").append(...a.links.map(link)); // in the footer
    if (a.install) {
      // how to get the script onto a norns, with a copy button
      $("#install-cmd").textContent = a.install;
      $("#install").hidden = false;
      $("#install-copy").addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(a.install);
          $("#install-copy").textContent = "copied";
        } catch (e) {
          $("#install-copy").textContent = "select it";
        }
        setTimeout(() => {
          $("#install-copy").textContent = "copy";
        }, 1500);
      });
    }
    if (a.footer || a.install || (a.links && a.links.length)) {
      const f = $("#about-footer");
      if (a.footer) {
        const p = document.createElement("p");
        p.textContent = a.footer;
        f.append(p);
      }
      f.hidden = false;
    }
  }

  // ---------- live reload (dev server only) ----------
  // The dev server says "reload" when a file changes: keep the params in a preset
  // slot of their own, reload, and put them back, so the jar carries on with the
  // new code. (Sound needs a click again: browsers start audio only on a gesture.)
  const RESTORE = "norns-web:live-restore";
  function liveReload() {
    if (sessionStorage.getItem(RESTORE)) {
      sessionStorage.removeItem(RESTORE);
      psetFn("load", "live");
      log("reloaded with your changes; params kept (press Start sound again)");
    }
    const events = new EventSource("__reload");
    events.onmessage = () => {
      psetFn("save", "live");
      sessionStorage.setItem(RESTORE, "1");
      location.reload();
    };
  }

  // ---------- boot ----------
  let lua = null,
    tick = null,
    encFn = null,
    keyFn = null,
    paramsJson = null,
    paramDelta = null,
    replFn = null,
    psetFn = null;
  let storagePrefix = "norns-web:";
  const store = {
    // PSETs in localStorage, per script; private windows may refuse it
    get(k) {
      try {
        return localStorage.getItem(storagePrefix + k) || "";
      } catch (e) {
        return "";
      }
    },
    set(k, v) {
      try {
        localStorage.setItem(storagePrefix + k, v);
      } catch (e) {
        log("can't save: browser storage is blocked", "error");
      }
    },
  };

  async function boot() {
    const [manifest, nornsLua] = await Promise.all([
      fetch("files.json", { cache: "no-store" }).then((r) => r.json()),
      fetch("norns.lua", { cache: "no-store" }).then((r) => r.text()),
    ]);
    const { name, main, root, files, about, dev } = manifest;
    document.title = `${name} · norns-web`;
    storagePrefix = `norns-web:${name}:`;
    $("#script-name").textContent = name;
    $(".brand").textContent = name;
    if (about) showAbout(about);

    // the engine stand-in, found from the script's engine.name before it runs
    const m = /engine\.name\s*=\s*["']([\w-]+)["']/.exec(files[main] || "");
    if (m) {
      const ok = await loadScript(`${root}lib/Engine_${m[1]}.js`);
      const make = window.NornsWeb.engines[m[1]];
      if (ok && make) {
        engine = make();
        log(`engine ${m[1]}: browser stand-in loaded`);
      } else
        log(
          `engine ${m[1]}: no stand-in (lib/Engine_${m[1]}.js), commands are only logged`,
        );
    }

    const factory = new wasmoon.LuaFactory(
      `${window.NORNS_WEB_WASMOON || "vendor/wasmoon/"}glue.wasm`,
    );
    for (const [path, src] of Object.entries(files))
      await factory.mountFile(`/code/${name}/${path}`, src);
    await factory.mountFile("/norns/norns.lua", nornsLua);
    lua = await factory.createEngine();
    lua.global.set("js_bridge", {
      engine: engineCall,
      engine_name: () => {},
      log: (s) => log(String(s)),
      error: (s) => log(String(s), "error"),
      os_capture: (cmd) =>
        (engine && engine.os_capture ? engine.os_capture(String(cmd)) : "") ||
        "",
      nb: (kind, note, v) => nbCall(String(kind), +note, +v),
      storage_get: (k) => store.get(String(k)),
      storage_set: (k, v) => store.set(String(k), String(v)),
    });
    await lua.doString('dofile("/norns/norns.lua")');
    await lua.doString(
      `norns_web.boot(${JSON.stringify(name)}, ${JSON.stringify(main)})`,
    );
    const nw = (n) => lua.global.get("norns_web")[n];
    tick = nw("tick");
    encFn = nw("enc");
    keyFn = nw("key");
    paramsJson = nw("params_json");
    paramDelta = nw("param_delta");
    replFn = nw("repl");
    psetFn = nw("pset");
    if (dev) liveReload();
    renderParams();
    setInterval(renderParams, 400);
    const t0 = performance.now();
    const frame = () => {
      try {
        const s = tick((performance.now() - t0) / 1000);
        if (typeof s === "string" && s.length >= W * H) blit(s);
      } catch (e) {
        log(String(e.message || e), "error");
      }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }
  boot().catch((e) =>
    log(`norns-web failed to start: ${e.message || e}`, "error"),
  );

  // ---------- controls: encoders and keys, like the device ----------
  const enc = (n, d) => {
    if (encFn) encFn(n, d);
    spin(n, d);
  };
  const key = (n, z) => {
    if (keyFn) keyFn(n, z);
  };
  const angles = { 1: 0, 2: 0, 3: 0 };
  function spin(n, d) {
    angles[n] += d * 12;
    const el = document.querySelector(`.enc[data-e="${n}"] i`);
    if (el) el.style.transform = `rotate(${angles[n]}deg)`;
  }
  // the wheel: a mouse notch is one step; a trackpad's stream of small deltas adds up,
  // WHEEL_PX per step, so a swipe doesn't fling the value across its range
  const WHEEL_PX = 60,
    DRAG_PX = 14;
  function wheelSteps(fn) {
    let acc = 0,
      last = 0;
    return (e) => {
      e.preventDefault();
      if (e.timeStamp - last > 300) acc = 0; // a new gesture starts fresh
      last = e.timeStamp;
      acc -= e.deltaY * (e.deltaMode === 1 ? 20 : e.deltaMode === 2 ? 400 : 1);
      if (Math.abs(acc) >= WHEEL_PX) {
        const s = Math.sign(acc);
        fn(s, e);
        acc = 0;
      } // at most one per event
    };
  }
  document.querySelectorAll(".enc").forEach((el) => {
    const n = +el.dataset.e;
    el.addEventListener(
      "wheel",
      wheelSteps((s) => enc(n, s)),
      { passive: false },
    );
    let lastY = null,
      accY = 0;
    el.addEventListener("pointerdown", (e) => {
      lastY = e.clientY;
      accY = 0;
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener("pointermove", (e) => {
      if (lastY === null) return;
      accY += lastY - e.clientY;
      lastY = e.clientY;
      while (Math.abs(accY) >= DRAG_PX) {
        const s = Math.sign(accY);
        enc(n, s);
        accY -= s * DRAG_PX;
      }
    });
    const end = () => {
      lastY = null;
    };
    el.addEventListener("pointerup", end);
    el.addEventListener("pointercancel", end);
    el.addEventListener("keydown", (e) => {
      if (e.key === "ArrowUp" || e.key === "ArrowRight") {
        e.preventDefault();
        enc(n, 1);
      }
      if (e.key === "ArrowDown" || e.key === "ArrowLeft") {
        e.preventDefault();
        enc(n, -1);
      }
    });
  });
  document.querySelectorAll(".key").forEach((el) => {
    const n = +el.dataset.k;
    const down = (e) => {
      e.preventDefault();
      el.classList.add("down");
      key(n, 1);
    };
    const up = () => {
      if (el.classList.contains("down")) {
        el.classList.remove("down");
        key(n, 0);
      }
    };
    el.addEventListener("pointerdown", down);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointerleave", up);
    el.addEventListener("pointercancel", up);
    el.addEventListener("keydown", (e) => {
      if ((e.key === " " || e.key === "Enter") && !e.repeat) down(e);
    });
    el.addEventListener("keyup", (e) => {
      if (e.key === " " || e.key === "Enter") up();
    });
  });
  // encoders: a vertical pair each, top key turns up (Y/H E1, U/J E2, I/K E3); keys: A S D
  const KEYMAP = {
    y: [1, 1],
    h: [1, -1],
    u: [2, 1],
    j: [2, -1],
    i: [3, 1],
    k: [3, -1],
  };
  const KEYS = { a: 1, s: 2, d: 3 };
  const typing = (e) =>
    e.target.closest && e.target.closest("input, select, textarea");
  window.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey || typing(e)) return;
    const k = e.key.toLowerCase();
    if (KEYMAP[k]) {
      enc(...KEYMAP[k]);
      e.preventDefault();
    } else if (KEYS[k] && !e.repeat) {
      document
        .querySelector(`.key[data-k="${KEYS[k]}"]`)
        ?.classList.add("down");
      key(KEYS[k], 1);
      e.preventDefault();
    }
  });
  window.addEventListener("keyup", (e) => {
    const k = e.key.toLowerCase();
    if (KEYS[k]) {
      document
        .querySelector(`.key[data-k="${KEYS[k]}"]`)
        ?.classList.remove("down");
      key(KEYS[k], 0);
    }
  });

  // ---------- PSET ----------
  for (const action of ["save", "load"]) {
    $(`#pset-${action}`).addEventListener("click", () => {
      if (!psetFn) return;
      psetFn(action, +$("#pset-slot").value);
      renderParams();
    });
  }

  // ---------- REPL ----------
  const replEl = $("#repl"),
    history = [];
  let back = 0;
  $("#repl-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const code = replEl.value.trim();
    if (!code || !replFn) return;
    log(`>> ${code}`, "repl");
    history.push(code);
    back = 0;
    replEl.value = "";
    try {
      replFn(code);
    } catch (err) {
      log(String(err.message || err), "error");
    }
    renderParams();
  });
  replEl.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return;
    e.preventDefault();
    back = clampInt(back + (e.key === "ArrowUp" ? 1 : -1), 0, history.length);
    replEl.value = back ? history[history.length - back] : "";
  });
  const clampInt = (v, a, b) => Math.max(a, Math.min(b, v));

  // ---------- PARAMS panel ----------
  // Rebuilt when the list of params changes; otherwise only the values update,
  // so open groups and the pointer position survive.
  const paramsEl = $("#params");
  let shape = "",
    openGroups = new Set(),
    valueEls = new Map();
  function renderParams() {
    if (!paramsJson) return;
    let list;
    try {
      list = JSON.parse(paramsJson());
    } catch (e) {
      return;
    }
    const nextShape = list
      .map((p) => `${p.i}:${p.kind}:${p.group || ""}`)
      .join("|");
    if (nextShape !== shape) {
      shape = nextShape;
      paramsEl
        .querySelectorAll("details[open]")
        .forEach((d) => openGroups.add(d.dataset.group));
      paramsEl
        .querySelectorAll("details:not([open])")
        .forEach((d) => openGroups.delete(d.dataset.group));
      paramsEl.innerHTML = "";
      valueEls = new Map();
      let groupBody = null;
      for (const p of list) {
        if (p.kind === "separator") {
          groupBody = null;
          const h = document.createElement("div");
          h.className = "sep";
          h.textContent = p.name;
          paramsEl.appendChild(h);
          continue;
        }
        if (p.kind === "group") {
          const d = document.createElement("details");
          d.dataset.group = p.name;
          d.open = openGroups.has(p.name);
          const s = document.createElement("summary");
          s.textContent = p.name;
          d.appendChild(s);
          paramsEl.appendChild(d);
          groupBody = d;
          continue;
        }
        const row = document.createElement("div");
        row.className = "param";
        const label = document.createElement("span");
        label.className = "pname";
        label.textContent = p.name;
        const minus = document.createElement("button");
        minus.type = "button";
        minus.textContent = "−";
        minus.setAttribute("aria-label", `decrease ${p.name}`);
        const val = document.createElement("span");
        val.className = "pval";
        const plus = document.createElement("button");
        plus.type = "button";
        plus.textContent = "+";
        plus.setAttribute("aria-label", `increase ${p.name}`);
        const step = (d, e) => {
          paramDelta(p.i, d * (e && e.shiftKey ? 10 : 1));
          renderParams();
        };
        minus.addEventListener("click", (e) => step(-1, e));
        plus.addEventListener("click", (e) => step(1, e));
        row.addEventListener("wheel", wheelSteps(step), { passive: false });
        if (p.kind === "text" || p.kind === "file") {
          minus.hidden = true;
          plus.hidden = true;
        }
        if (p.kind === "trigger") {
          // a trigger is a button, not a value
          const go = document.createElement("button");
          go.type = "button";
          go.className = "go";
          go.textContent = "go";
          go.addEventListener("click", () => step(1));
          row.append(label, go);
          (p.group && groupBody ? groupBody : paramsEl).appendChild(row);
          continue;
        }
        row.append(label, minus, val, plus);
        (p.group && groupBody ? groupBody : paramsEl).appendChild(row);
        valueEls.set(p.i, val);
      }
    }
    for (const p of list) {
      const el = valueEls.get(p.i);
      if (el && el.textContent !== p.str) el.textContent = p.str ?? "";
    }
  }
})();
