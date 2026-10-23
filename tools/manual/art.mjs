// Pictures of terrarium for the README and wallpapers, made from the real script in norns-web:
// the night sky, the logo and the device on the ground, with nothing else of the page.
// For each scene the page loads once and plays for a while (snow needs time to settle); then
// every format and case is shot from it, resizing the window in place.
//
//   make art     (npm install in tools/manual first; needs a Chromium, as pdf.mjs)
//
// doc/art/: banner.png (the README's top), social.png (GitHub's social preview, 1280x640),
// wallpapers/<scene>-<desktop|phone>-<alu|black>.jpg (3840x2160 and 1179x2556).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const outDir = path.join(root, "doc/art");
const only = process.argv[2]; // a scene's name, to redo just that one

function findChromium() {
  if (process.env.CHROMIUM) return process.env.CHROMIUM;
  const cache = path.join(os.homedir(), ".cache/ms-playwright");
  const builds = fs.existsSync(cache) ? fs.readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort() : [];
  for (const b of builds.reverse()) {
    const exe = path.join(cache, b, "chrome-linux/chrome");
    if (fs.existsSync(exe)) return exe;
  }
  throw new Error("no Chromium found: set CHROMIUM=/path/to/chrome (or: npx playwright install chromium)");
}

// each scene: the parts and their macros (as in tools/manual/lib/shots.lua), how long to let it play
const SCENES = [
  {
    name: "meadow", secs: 25,
    set: { brain_kind: 1, voice_kind: 1, color_kind: 1, air_kind: 1, drone_kind: 1, rain_rate: 0.6, rain_change: 0.3,
      meadow_harmonics: 0.5, meadow_timbre: 0.6, pond_structure: 0.7, aurora_glow: 0.9, aurora_motion: 0.5 },
  },
  {
    name: "snow", secs: 150,
    set: { brain_kind: 3, voice_kind: 2, color_kind: 1, air_kind: 3, drone_kind: 1, snow_rate: 0.85, snow_change: 0.4,
      crystals_ratio: 0.7, crystals_index: 0.8, mountains_size: 0.6, aurora_glow: 0.6 },
  },
  {
    name: "fireflies", secs: 30,
    set: { brain_kind: 1, voice_kind: 3, color_kind: 1, air_kind: 2, drone_kind: 2, rain_rate: 0.35, rain_change: 0.4,
      reeds_structure: 0.4, reeds_brightness: 0.6, pond_structure: 0.7, pond_damping: 0.2, fireflies_density: 0.9,
      fireflies_glow: 1, roots_breath: 0.6, roots_depth: 1 },
  },
];

// width x height in CSS pixels, times scale; the layout places the title beside the device (row),
// over it (stack) or under its ground (phone, clear of a lock screen's clock)
const FORMATS = [
  { file: "banner.png", scene: "meadow", finish: "alu", w: 1280, h: 520, scale: 2, layout: "row", zoom: 0.9 },
  { file: "social.png", scene: "meadow", finish: "alu", w: 1280, h: 640, scale: 1, layout: "row", zoom: 1 },
  ...SCENES.flatMap(s => ["alu", "black"].flatMap(finish => [
    { file: `wallpapers/${s.name}-desktop-${finish}.jpg`, scene: s.name, finish, w: 1920, h: 1080, scale: 2, layout: "stack", zoom: 1.25 },
    { file: `wallpapers/${s.name}-phone-${finish}.jpg`, scene: s.name, finish, w: 393, h: 852, scale: 3, layout: "phone", zoom: 1 },
  ])),
];

const CSS = `
body.art { overflow: hidden; }
body.art .controls, body.art .hint, body.art .lede, body.art main.wrap, body.art footer,
body.art #hood, body.art .full-hint { display: none !important; }
body.art .night { height: 100vh; padding: 0; display: grid; }
body.art .night .wrap { zoom: var(--art-zoom, 1); align-content: center; gap: 44px; max-width: none; width: 100%; }
body.art.row .night .wrap { grid-template-columns: auto minmax(0, 540px); justify-content: center; align-items: center; column-gap: 88px; }
body.art.row .night header { justify-items: start; text-align: left; margin-bottom: 60px; }
body.art.phone .night .wrap { align-content: end; padding-bottom: 9vh; gap: 56px; }
body.art.phone .night header { order: 2; }
body.art.phone .subtitle { font-size: 11px; white-space: nowrap; }
`;

function freePort() {
  return new Promise((ok) => {
    const s = net.createServer().listen(0, () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}

const port = await freePort();
const server = spawn("node", [path.join(root, "tools/norns-web/serve.mjs"), root, String(port)], { stdio: "ignore" });
const browser = await chromium.launch({ executablePath: findChromium() });
try {
  await new Promise(r => setTimeout(r, 800));
  for (const scene of SCENES) {
    if (only && scene.name !== only) continue;
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    const cdp = await page.context().newCDPSession(page);
    await page.goto(`http://localhost:${port}/?shell=shield&screen=yellow`);
    await page.addStyleTag({ content: CSS });
    await page.evaluate(() => document.body.classList.add("art"));
    // the script is up when the REPL answers: until then a submit is ignored
    await page.waitForFunction(() => document.querySelector("#oled")
      .getContext("2d").getImageData(0, 0, 128, 64).data.some((v, i) => i % 4 === 0 && v > 0), null, { timeout: 30000 });
    const lua = Object.entries(scene.set).map(([k, v]) => `params:set("${k}", ${v})`).join(" ");
    await page.evaluate((code) => {
      document.querySelector("#repl").value = code;
      document.querySelector("#repl-form").requestSubmit();
    }, lua);
    console.log(`${scene.name}: playing for ${scene.secs} s`);
    await page.waitForTimeout(scene.secs * 1000);
    for (const f of FORMATS.filter(f => f.scene === scene.name)) {
      // size, scale and the shot all through CDP: Playwright's own viewport would put the scale back to 1
      await cdp.send("Emulation.setDeviceMetricsOverride", { width: f.w, height: f.h, deviceScaleFactor: f.scale, mobile: false });
      await page.evaluate(({ layout, finish, zoom }) => {
        document.body.classList.remove("row", "stack", "phone");
        document.body.classList.add(layout);
        document.body.style.setProperty("--art-zoom", zoom);
        const sel = document.querySelector("#v-finish");
        sel.value = finish;
        sel.dispatchEvent(new Event("change"));
        // the sky lays out its ground on a resize of the night: nudge it, so the ground finds the device again
        const night = document.querySelector("#night");
        night.style.height = "calc(100vh - 1px)";
        requestAnimationFrame(() => { night.style.height = ""; });
      }, f);
      await page.waitForTimeout(700);
      const file = path.join(outDir, f.file);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const jpg = file.endsWith(".jpg");
      const shot = await cdp.send("Page.captureScreenshot", jpg ? { format: "jpeg", quality: 92 } : { format: "png" });
      fs.writeFileSync(file, Buffer.from(shot.data, "base64"));
      console.log(`  ${f.file}`);
    }
    await page.close();
  }
} finally {
  await browser.close();
  server.kill();
}
