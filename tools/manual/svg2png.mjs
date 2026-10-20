// Renders an SVG to a PNG of a given size, in the same Chromium as the PDF (make logo):
//
//   node tools/manual/svg2png.mjs <in.svg> <out.png> <size>
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { chromium } from "playwright-core";

const [src, dest, size] = process.argv.slice(2);
const px = Number(size);
const exe = process.env.CHROMIUM || (() => {
  const cache = path.join(os.homedir(), ".cache/ms-playwright");
  const builds = fs.existsSync(cache) ? fs.readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort() : [];
  for (const b of builds.reverse()) {
    const e = path.join(cache, b, "chrome-linux/chrome");
    if (fs.existsSync(e)) return e;
  }
  throw new Error("no Chromium found: set CHROMIUM=/path/to/chrome (or: npx playwright install chromium)");
})();
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: px, height: px } });
const data = "data:image/svg+xml;base64," + fs.readFileSync(src).toString("base64");
await page.setContent(`<body style="margin:0"><img src="${data}" style="display:block;width:${px}px;height:${px}px;image-rendering:pixelated"></body>`);
await page.screenshot({ path: dest, omitBackground: true });
await browser.close();
console.log(`${dest} (${px}x${px})`);
