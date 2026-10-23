// norns-web: run a norns script's real Lua in the browser.
//
// files.json says which script to run and carries its .lua files. They're
// mounted into a Lua VM (wasmoon, Lua 5.4) under /code/<name>/, norns.lua
// provides the norns API, and this file drives it: one norns_web.tick() per
// animation frame, the screen drawn to a canvas, encoders and keys from the
// page, a PARAMS panel, and engine commands sent to a JS stand-in for the
// SuperCollider engine (script/lib/Engine_<name>.js, if the script has one).
// The workbench (PARAMS, log, REPL) sits folded "under the hood"; up front are
// the device, Start sound, the script's actions and how to play it.
(() => {
  "use strict";

  const W = 128,
    H = 64;
  const $ = (sel) => document.querySelector(sel);

  // ---------- hosted: the face of a plugin that runs the script itself ----------
  // Inside JUCE's WebBrowserComponent (window.__JUCE__), the plugin has its own Lua and its
  // own sound: the page starts neither, and becomes the plugin's face. Encoders, keys,
  // PARAMS, presets and the REPL call the plugin's native functions (enc, key, params,
  // param_delta, repl, pset); the screen and the log arrive as its "frame" and "log" events.
  // A plugin that also registers param_map and param_maps offers its host-automation slots,
  // and PARAMS gets a "map" button per param; set_extra_height (or _width) lets the drawer
  // grow the plugin's window instead of covering the device. JUCE's wire protocol: an "__juce__invoke" event
  // { name, params, resultId }, answered by "__juce__complete" { promiseId, result }.
  const juceBackend = window.__JUCE__ && window.__JUCE__.backend;
  const hosted = !!(juceBackend && typeof juceBackend.emitEvent === "function");
  const hostFunctions = (window.__JUCE__ && window.__JUCE__.initialisationData &&
    window.__JUCE__.initialisationData.__juce__functions) || [];
  const calls = new Map();
  let nextCall = 0;
  if (hosted)
    juceBackend.addEventListener("__juce__complete", (p) => {
      const resolve = p && calls.get(p.promiseId);
      if (resolve) {
        calls.delete(p.promiseId);
        resolve(p.result);
      }
    });
  const native = (name, ...params) =>
    new Promise((resolve) => {
      const resultId = nextCall++;
      calls.set(resultId, resolve);
      juceBackend.emitEvent("__juce__invoke", { name, params, resultId });
    });
  const canMap = hosted && hostFunctions.includes("param_map") && hostFunctions.includes("param_maps");
  const canGrow = hosted && hostFunctions.includes("set_extra_height");
  // with set_extra_width, the drawer opens at the right instead, and the window grows wider
  const side = hosted && hostFunctions.includes("set_extra_width");
  if (side) document.body.classList.add("side-drawer");

  // The page's own settings (the look, the drawer): in the browser's storage, or, hosted by a
  // plugin that passes them in (initialisationData "prefs") and takes them back (prefs_set),
  // with the plugin, so they're saved in the project. Options the plugin offers
  // (initialisationData "options": [{ id, label, value }], set_option(id, on)) go in Look.
  const initData = (hosted && window.__JUCE__.initialisationData) || {};
  const first = (v) => (Array.isArray(v) ? v[0] : v);
  const hostPrefs = hosted && hostFunctions.includes("prefs_set") ? first(initData.prefs) || {} : null;
  const prefs = {
    get(k) {
      if (hostPrefs) return k in hostPrefs ? String(hostPrefs[k]) : null;
      try {
        return localStorage.getItem(k);
      } catch (e) {
        return null;
      }
    },
    set(k, v) {
      if (hostPrefs) {
        hostPrefs[k] = String(v);
        native("prefs_set", k, String(v));
        return;
      }
      try {
        localStorage.setItem(k, v);
      } catch (e) {}
    },
  };


  // ---------- under the hood: a drawer at the bottom of the window, closed until asked for ----------
  // Open, it shares the window with the device (opening it scrolls the device into view above it);
  // its height is dragged from the handle on its top edge. Open or closed and the height are remembered.
  // In a plugin that offers set_extra_width (side), it's a drawer at the right, as wide as dragged.
  const hood = $("#hood"),
    badge = $("#hood-badge"),
    HOOD = "norns-web:hood",
    HOOD_H = side ? "norns-web:hood-width" : "norns-web:hood-height";
  const setDrawer = (px, save) => {
    const most = side ? 900 : window.innerHeight * 0.85;
    const h = Math.max(side ? 300 : 160, Math.min(Math.round(px), Math.round(most)));
    document.documentElement.style.setProperty(side ? "--drawer-w" : "--drawer-h", h + "px");
    if (save)
      try {
        prefs.set(HOOD_H, h);
      } catch (e) {}
  };
  try {
    const h = +prefs.get(HOOD_H);
    if (h) setDrawer(h);
    hood.open = prefs.get(HOOD) === "open";
  } catch (e) {}
  // the page keeps room for the drawer at its bottom, so nothing hides behind it
  // A hosting plugin that offers set_extra_height grows its window by the open drawer's
  // height instead (a plugin window can grow, a browser tab can't), so the device stays whole.
  let extraAsked = 0;
  new ResizeObserver(() => {
    const summary = hood.querySelector("summary");
    if (side) {
      document.documentElement.style.setProperty("--hood-space-x", hood.offsetWidth + "px");
      const extra = hood.open ? hood.offsetWidth - summary.offsetWidth : 0;
      if (extra !== extraAsked) native("set_extra_width", (extraAsked = extra));
      return;
    }
    document.documentElement.style.setProperty("--hood-space", hood.offsetHeight + "px");
    if (canGrow) {
      const extra = hood.open ? hood.offsetHeight - summary.offsetHeight : 0;
      if (extra !== extraAsked) native("set_extra_height", (extraAsked = extra));
    }
  }).observe(hood);
  let restoring = hood.open;
  hood.addEventListener("toggle", () => {
    if (hood.open) {
      badge.hidden = true;
      badge.dataset.n = "0";
      logEl.scrollTop = logEl.scrollHeight;
      if (!restoring && !canGrow && !side)
        requestAnimationFrame(() => {
          // the device's bottom just above the drawer, or its top at the window's if it doesn't fit
          const r = $("#device").getBoundingClientRect(),
            free = window.innerHeight - hood.offsetHeight;
          let dy = r.bottom - free + 12;
          if (r.top - dy < 8) dy = r.top - 8;
          if (dy > 0 || r.top < 0) window.scrollBy({ top: dy, behavior: "smooth" });
        });
    }
    restoring = false;
    try {
      prefs.set(HOOD, hood.open ? "open" : "closed");
    } catch (e) {}
  });
  {
    // dragged from its top edge (up opens it further), or at the side from its left edge
    const grip = $("#hood-grip");
    if (side) grip.setAttribute("aria-orientation", "vertical");
    let startY = 0,
      startH = 0;
    const pos = (e) => (side ? e.clientX : e.clientY);
    const height = () => {
      const r = $("#hood .bench").getBoundingClientRect();
      return side ? r.width : r.height;
    };
    grip.addEventListener("pointerdown", (e) => {
      startY = pos(e);
      startH = height();
      grip.setPointerCapture(e.pointerId);
      e.preventDefault();
    });
    grip.addEventListener("pointermove", (e) => {
      if (grip.hasPointerCapture(e.pointerId)) setDrawer(startH - (pos(e) - startY), true);
    });
    grip.addEventListener("keydown", (e) => {
      const d = side ? { ArrowLeft: 24, ArrowRight: -24 }[e.key] : { ArrowUp: 24, ArrowDown: -24 }[e.key];
      if (d) {
        setDrawer(height() + d, true);
        e.preventDefault();
      }
    });
  }

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
    if (kind === "error" && !hood.open) {
      // the log is folded away: its cover counts what it missed
      const n = (+badge.dataset.n || 0) + 1;
      badge.dataset.n = n;
      badge.textContent = n === 1 ? "1 error" : `${n} errors`;
      badge.hidden = false;
    }
  }
  $("#show-engine").addEventListener("change", (e) => {
    showEngine = e.target.checked;
  });


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

  // ---------- view: the shell (norns | shield), the case's finish and the screen's color, remembered ----------
  const view = (() => {
    try {
      return JSON.parse(prefs.get("norns-web:view")) || {};
    } catch (e) {
      return {};
    }
  })();
  const query = new URLSearchParams(location.search);
  view.shell = query.get("shell") || view.shell || "shield";
  view.finish = query.get("finish") || view.finish || "alu";
  view.screen = query.get("screen") || view.screen || "yellow"; // the amber of a shield's OLED, by default
  function applyView() {
    $("#device").dataset.shell = view.shell;
    $("#device").dataset.finish = view.finish;
    $("#v-shell").value = view.shell;
    $("#v-finish").value = view.finish;
    $("#v-screen").value = view.screen;
    setTint(view.screen);
    try {
      prefs.set("norns-web:view", JSON.stringify(view));
    } catch (e) {}
  }
  $("#v-shell").addEventListener("change", (e) => {
    view.shell = e.target.value;
    applyView();
  });
  $("#v-finish").addEventListener("change", (e) => {
    view.finish = e.target.value;
    applyView();
  });
  $("#v-screen").addEventListener("change", (e) => {
    view.screen = e.target.value;
    applyView();
  });
  applyView();
  // a hosting plugin's options, as checkboxes in Look
  for (const o of (hosted && hostFunctions.includes("set_option") && first(initData.options)) || []) {
    const label = document.createElement("label");
    label.className = "option";
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = !!o.value;
    box.addEventListener("change", () => native("set_option", o.id, box.checked));
    label.append(box, " " + o.label);
    document.querySelector(".menu .pop").append(label);
  }
  // the Look menu closes when you click elsewhere
  document.addEventListener("click", (e) => {
    document.querySelectorAll("details.menu[open]").forEach((d) => {
      if (!d.contains(e.target)) d.open = false;
    });
  });

  // ---------- the night sky behind the device: chunky pixel stars and the ground it stands on ----------
  // Two of them: the page's, behind the device and the buttons, and full screen's, filling the
  // frame. relayoutSky() puts the ground back under the device after it moves or scales.
  const PX = 4; // one sky pixel, in CSS pixels
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  // seeded (Park-Miller), so the sky is the same on every visit
  const rand = (seed) => () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  function makeSky(box, sky) {
    const sg = sky.getContext("2d");
    let stars = [],
      ground = 0,
      cols = 0,
      rows = 0;
    const draw = (t) => {
      sg.clearRect(0, 0, cols, rows);
      for (const s of stars) {
        const a = s.tw && !still.matches ? s.l * (0.55 + 0.45 * Math.sin((t / 1000) * s.tw + s.ph)) : s.l;
        sg.fillStyle = `rgba(201, 208, 202, ${a.toFixed(2)})`;
        sg.fillRect(s.x, s.y, 1, 1);
      }
      if (ground <= 0 || ground >= rows) return;
      // a line of ground with grass along it and dashes of earth below, like the r/norns banner
      const rnd = rand(3);
      sg.fillStyle = "#8a938c";
      sg.fillRect(0, ground, cols, 1);
      sg.fillStyle = "#525a54";
      for (let x = 1; x < cols; x += 2 + Math.floor(rnd() * 4)) {
        const tall = rnd() < 0.3;
        sg.fillRect(x, ground - (tall ? 2 : 1), 1, tall ? 2 : 1);
      }
      sg.fillStyle = "#2a302c";
      for (let y = ground + 3; y < Math.min(rows, ground + 10); y += 3) // a few rows, clear of the buttons
        for (let x = Math.floor(rnd() * 20) - 10; x < cols; x += 24 + Math.floor(rnd() * 30))
          sg.fillRect(x, y, 10 + Math.floor(rnd() * 14), 1);
    };
    const layout = () => {
      const r = box.getBoundingClientRect(),
        d = $("#device").getBoundingClientRect();
      if (!r.width || !r.height) return;
      cols = Math.ceil(r.width / PX);
      rows = Math.ceil(r.height / PX);
      sky.width = cols;
      sky.height = rows;
      ground = Math.round((d.bottom - r.top) / PX); // the device stands on it
      const rnd = rand(7);
      stars = [];
      for (let i = 0; i < (cols * ground) / 260; i++)
        stars.push({
          x: Math.floor(rnd() * cols),
          y: Math.floor(rnd() * (ground - 4)),
          l: 0.2 + rnd() * 0.6,
          tw: rnd() < 0.25 ? 0.4 + rnd() * 1.2 : 0, // a quarter of them twinkle
          ph: rnd() * 6.28,
        });
      draw(performance.now());
    };
    new ResizeObserver(layout).observe(box);
    return { layout, draw };
  }
  const pageSky = makeSky($("#night"), $("#sky")),
    fullSky = makeSky($("#frame"), $("#full-sky"));
  const relayoutSky = () => (document.body.classList.contains("full") ? fullSky : pageSky).layout();
  {
    let last = 0;
    const loop = (t) => {
      if (t - last > 120 && !still.matches) {
        (document.body.classList.contains("full") ? fullSky : pageSky).draw(t);
        last = t;
      }
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }

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
      b.querySelector(".lbl").textContent = on ? "Mute" : "Start sound";
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
      bar = frame.querySelector(".full-bar"),
      fullBtn = $("#full");
    let full = false;
    // The bar sits in the top right corner. Where the device, centered, leaves it room
    // beside it (a wide window), it takes none. Otherwise it goes above the device, or
    // stacks down the right side (a phone on its side), whichever leaves the device bigger.
    const fit = () => {
      if (!full) return;
      const vw = window.innerWidth,
        vh = window.innerHeight,
        pad = 16,
        gap = 8;
      if (vw > vh) hideHint();
      device.style.transform = "";
      frame.style.padding = "";
      bar.classList.remove("side");
      device.style.width =
        Math.min(device.dataset.shell === "norns" ? 720 : 540, vw - 2 * pad) +
        "px";
      const r = device.getBoundingClientRect();
      const scale = (w, h) => Math.min(w / r.width, h / r.height);
      let s = scale(vw - 2 * pad, vh - 2 * pad);
      let b = bar.getBoundingClientRect();
      if ((vw + r.width * s) / 2 > b.left - gap) {
        const top = b.bottom + gap,
          sTop = scale(vw - 2 * pad, vh - top - pad);
        bar.classList.add("side");
        b = bar.getBoundingClientRect();
        const right = b.left - gap,
          sSide = scale(right - pad, vh - 2 * pad);
        if (b.bottom <= vh - pad && sSide >= sTop) {
          s = sSide;
          if ((vw + r.width * s) / 2 > right)
            frame.style.padding = `0 ${vw - right}px 0 ${pad}px`;
        } else {
          bar.classList.remove("side");
          s = sTop;
          frame.style.paddingTop = top - pad + "px";
        }
      }
      device.style.transform = `scale(${s})`;
      relayoutSky();
    };
    // a phone held upright gets a nudge to turn it: the norns is wider than tall
    const hint = $("#full-hint");
    let hintTimer;
    const hideHint = () => {
      clearTimeout(hintTimer);
      hint.hidden = true;
    };
    hint.addEventListener("click", hideHint);
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
      if (matchMedia("(pointer: coarse)").matches && innerHeight > innerWidth) {
        hint.hidden = false;
        hintTimer = setTimeout(hideHint, 6000);
      }
    };
    const exit = () => {
      if (!full) return;
      full = false;
      frame.classList.remove("full");
      document.body.classList.remove("full");
      fullBtn.setAttribute("aria-pressed", "false");
      device.style.transform = "";
      device.style.width = "";
      frame.style.padding = "";
      bar.classList.remove("side");
      hideHint();
      relayoutSky();
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
      if (e.key === "Escape" && full && !$("#help").open) exit(); // Esc in the help only closes it
    });
    window.addEventListener("resize", fit);
    $("#v-shell").addEventListener("change", () => (full ? fit() : relayoutSky()));
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
  // icon and touch_icon are paths in the script (root: where its files are served)
  function showAbout(a, root) {
    if (a.title) {
      $("#script-name").textContent = a.title;
      document.title = a.title;
    }
    const headLink = (rel, href, type) => {
      const l = document.createElement("link");
      l.rel = rel;
      l.href = root + href;
      if (type) l.type = type;
      document.head.append(l);
    };
    if (a.icon) {
      // the tab's icon, and the same mark beside the title
      headLink("icon", a.icon, /\.svg$/i.test(a.icon) ? "image/svg+xml" : null);
      const img = document.createElement("img");
      img.className = "mark";
      img.src = root + a.icon;
      img.alt = "";
      $("#script-name").prepend(img);
    }
    if (a.touch_icon) headLink("apple-touch-icon", a.touch_icon);
    if (a.subtitle) {
      const s = $("#subtitle");
      s.textContent = a.subtitle;
      s.hidden = false;
    }
    if (a.about) $(".lede").textContent = a.about;
    if (a.more) {
      $("#more").textContent = a.more;
      $("#more").hidden = false;
    }
    if (a.actions) showActions(a.actions);
    if (a.gallery && a.gallery.length) showGallery(a.gallery, a.gallery_intro, root);
    if (a.downloads) showDownloads(a.downloads);
    if (a.controls) showHelp(a.controls);
    const link = (l) => {
      const el = document.createElement("a");
      el.className = "btn";
      el.href = l.url;
      el.textContent = l.label;
      el.rel = "noopener";
      el.target = "_blank";
      return el;
    };
    if (a.links && a.links.length) $("#links").append(...a.links.map(link));
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
    if (a.more || a.install || (a.links && a.links.length)) $("#about").hidden = false;
    if (a.footer) {
      const p = document.createElement("p");
      p.textContent = a.footer;
      $("#about-footer").append(p);
      $("#about-footer").hidden = false;
    }
  }

  // the script's actions (norns-web.json "actions"): buttons beside Start sound that step a
  // param, like pressing a trigger in PARAMS ("randomize"); icon-only in the full screen corner
  const ICONS = {
    shuffle:
      '<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M1 4h3l6 8h4M1 12h3l6-8h4M12 2l2 2-2 2M12 10l2 2-2 2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></svg>',
  };
  function showActions(actions) {
    for (const act of actions) {
      for (const full of [false, true]) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "btn";
        b.title = act.title || act.label;
        b.innerHTML = ICONS[act.icon] || "";
        if (full && ICONS[act.icon]) {
          b.classList.add("icon");
          b.setAttribute("aria-label", act.label);
        } else b.append(act.label);
        b.addEventListener("click", () => {
          if (!paramDelta) return;
          try {
            paramDelta(act.param, act.delta || 1);
          } catch (e) {
            log(`${act.label}: ${e.message || e}`, "error");
          }
          renderParams();
        });
        $(full ? "#full-actions" : "#actions").append(b);
      }
    }
  }

  // downloads (norns-web.json "downloads": { title, intro, items: [{ title, text, url, label }],
  // links }): the script elsewhere (a plugin, an app), a card per package, near the end
  function showDownloads(d) {
    if (d.title) $("#downloads-title").textContent = d.title;
    if (d.intro) {
      $("#downloads-lede").textContent = d.intro;
      $("#downloads-lede").hidden = false;
    }
    for (const it of d.items || []) {
      const li = document.createElement("li");
      const b = document.createElement("b");
      b.textContent = it.title || "";
      const p = document.createElement("p");
      p.textContent = it.text || "";
      const a = document.createElement("a");
      a.className = "btn";
      a.href = it.url;
      a.textContent = it.label || "Download";
      li.append(b, p, a);
      $("#downloads").append(li);
    }
    if (d.links && d.links.length) {
      for (const l of d.links) {
        const a = document.createElement("a");
        a.className = "btn";
        a.href = l.url;
        a.textContent = l.label;
        a.rel = "noopener";
        a.target = "_blank";
        $("#downloads-links").append(a);
      }
      $("#downloads-links").hidden = false;
    }
    $("#downloads-section").hidden = false;
  }

  // what's in the script (norns-web.json "gallery"): pictures, each with a name and a line
  function showGallery(items, intro, root) {
    for (const it of items) {
      const li = document.createElement("li");
      const img = document.createElement("img");
      img.src = root + it.img;
      img.alt = it.alt || "";
      img.loading = "lazy";
      const b = document.createElement("b");
      b.textContent = it.title || "";
      const p = document.createElement("p");
      p.textContent = it.text || "";
      li.append(img, b, p);
      $("#gallery").append(li);
    }
    if (intro) {
      $("#gallery-lede").textContent = intro;
      $("#gallery-lede").hidden = false;
    }
    $("#gallery-section").hidden = false;
  }

  // how to play: the script's controls (norns-web.json "controls": [{ keys, does }]), then the
  // keyboard and touch; on the page and in the help dialog (? or a How to play button)
  const GENERIC_CONTROLS = [
    { keys: "E1 E2 E3", does: "the three knobs (encoders): turn them to change things" },
    { keys: "K1 K2 K3", does: "the three keys: press them, or hold one while you turn a knob" },
  ];
  function helpContent(controls) {
    const wrap = document.createElement("div");
    wrap.className = "howto";
    const moves = document.createElement("ul");
    moves.className = "moves";
    for (const c of controls) {
      const li = document.createElement("li");
      const chip = document.createElement("span");
      chip.className = "chip";
      chip.textContent = c.keys;
      const does = document.createElement("span");
      does.textContent = c.does;
      li.append(chip, does);
      moves.append(li);
    }
    const aside = document.createElement("div");
    aside.className = "aside";
    aside.innerHTML = `
      <div><h3>On a computer</h3>
        <dl class="keymap">
          <dt><kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd></dt><dd>K1, K2, K3 (hold them like the real keys)</dd>
          <dt><kbd>Y</kbd> <kbd>H</kbd></dt><dd>turn E1 up, down</dd>
          <dt><kbd>U</kbd> <kbd>J</kbd></dt><dd>turn E2 up, down</dd>
          <dt><kbd>I</kbd> <kbd>K</kbd></dt><dd>turn E3 up, down</dd>
          <dt><kbd>?</kbd></dt><dd>this help</dd>
        </dl>
        <p>Hold <kbd>S</kbd> and tap <kbd>U</kbd> for "hold K2 + turn E2". The knobs also follow the scroll
          wheel and dragging up and down.</p></div>
      <div><h3>On a phone</h3>
        <p>Drag a knob up and down to turn it. Hold a key with one finger while you turn a knob with
          another. Full screen makes the norns as big as it gets.</p></div>`;
    wrap.append(moves, aside);
    return wrap;
  }
  function showHelp(controls) {
    $("#howto").replaceChildren(helpContent(controls));
    $("#help-body").replaceChildren(helpContent(controls));
  }
  showHelp(GENERIC_CONTROLS);
  const helpDlg = $("#help");
  const openHelp = () => {
    if (!helpDlg.open) helpDlg.showModal();
  };
  document.querySelectorAll("[data-help]").forEach((b) => b.addEventListener("click", openHelp));
  helpDlg.addEventListener("click", (e) => {
    if (e.target === helpDlg) helpDlg.close(); // a click on the backdrop
  });

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


  // A plugin's window doesn't scroll: the device and its buttons zoom down to fit its height
  // (keys and encoders included, as in full screen), never up.
  function fitHosted() {
    const root = document.documentElement, night = $("#night");
    root.style.setProperty("--fit", 1);
    const over = night.scrollHeight - window.innerHeight;
    if (over > 0) {
      const zoomed = $("#frame").offsetHeight + $(".controls").offsetHeight;
      root.style.setProperty("--fit", Math.max(0.3, (zoomed - over) / zoomed).toFixed(3));
    }
  }

  function bootHosted() {
    document.body.classList.add("hosted");
    fitHosted();
    window.addEventListener("resize", fitHosted);
    $("#v-shell").addEventListener("change", () => requestAnimationFrame(fitHosted));
    encFn = (n, d) => native("enc", n, d);
    keyFn = (n, z) => native("key", n, z);
    paramsJson = () => native("params");
    paramDelta = (i, d) => native("param_delta", i, d);
    replFn = (code) => native("repl", code);
    psetFn = (action, n) => native("pset", action, String(n));
    juceBackend.addEventListener("frame", (s) => {
      if (typeof s === "string" && s.length >= W * H) blit(s);
    });
    juceBackend.addEventListener("log", (e) => log(String((e && e.text) || ""), (e && e.kind) || "print"));
    renderParams();
    setInterval(renderParams, 400);
  }

  async function boot() {
    const [manifest, nornsLua] = await Promise.all([
      fetch("files.json", { cache: "no-store" }).then((r) => r.json()),
      hosted ? "" : fetch("lib/norns.lua", { cache: "no-store" }).then((r) => r.text()),
    ]);
    const { name, main, root, files, about, dev } = manifest;
    document.title = `${name} · norns-web`;
    storagePrefix = `norns-web:${name}:`;
    $("#script-name").textContent = name;
    $(".brand").textContent = name;
    if (about) showAbout(about, root);
    if (hosted) return bootHosted();

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
    const el = document.querySelector(`.enc[data-e="${n}"] .knurl`);
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
  // keys pressed on the keyboard, so only those get released: a letter typed into the REPL
  // has its keyup too, and a K2 release swaps the module in some scripts
  const held = new Set();
  const release = (k) => {
    if (!held.delete(k)) return;
    document
      .querySelector(`.key[data-k="${KEYS[k]}"]`)
      ?.classList.remove("down");
    key(KEYS[k], 0);
  };
  window.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey || typing(e)) return;
    if (e.key === "?") {
      helpDlg.open ? helpDlg.close() : openHelp();
      e.preventDefault();
      return;
    }
    if (helpDlg.open) return; // the keys read the help, not play the norns
    const k = e.key.toLowerCase();
    if (KEYMAP[k]) {
      enc(...KEYMAP[k]);
      e.preventDefault();
    } else if (KEYS[k] && !e.repeat) {
      held.add(k);
      document
        .querySelector(`.key[data-k="${KEYS[k]}"]`)
        ?.classList.add("down");
      key(KEYS[k], 1);
      e.preventDefault();
    }
  });
  window.addEventListener("keyup", (e) => release(e.key.toLowerCase()));
  // leaving the window (or clicking into the REPL) while holding a key lets it go
  window.addEventListener("blur", () => held.forEach(release));
  document.addEventListener("focusin", (e) => {
    if (typing(e)) held.forEach(release);
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
  // Hosted, the list comes from the plugin (a promise); a "map" button per param binds it to
  // one of the plugin's host-automation slots, or frees it.
  const paramsEl = $("#params");
  let shape = "",
    openGroups = new Set(),
    valueEls = new Map(),
    mapEls = new Map(),
    rendering = false;
  async function renderParams() {
    if (!paramsJson || rendering) return;
    rendering = true;
    try {
      await renderParamsNow();
    } finally {
      rendering = false;
    }
  }
  async function renderParamsNow() {
    let list, maps = {};
    try {
      list = JSON.parse(await paramsJson());
      if (canMap) maps = (await native("param_maps")) || {};
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
      mapEls = new Map();
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
        if (canMap && p.kind !== "text" && p.kind !== "file") {
          const map = document.createElement("button");
          map.type = "button";
          map.className = "map";
          map.addEventListener("click", async () => {
            await native("param_map", p.i);
            renderParams();
          });
          row.classList.add("mappable");
          row.append(map);
          mapEls.set(p.i, map);
        }
        (p.group && groupBody ? groupBody : paramsEl).appendChild(row);
        valueEls.set(p.i, val);
      }
    }
    for (const p of list) {
      const el = valueEls.get(p.i);
      if (el && el.textContent !== p.str) el.textContent = p.str ?? "";
      const m = mapEls.get(p.i);
      if (m) {
        const slot = maps[p.i] || 0;
        const text = slot ? `map ${slot}` : "map";
        if (m.textContent !== text) {
          m.textContent = text;
          m.classList.toggle("on", !!slot);
          m.title = slot
            ? `${p.name} follows the host's automation slot "map ${slot}"; click to free it`
            : `Bind ${p.name} to a host automation slot`;
        }
      }
    }
  }
})();
