// Build a static copy of norns-web for a script, to publish or open anywhere:
//
//   node tools/norns-web/build.mjs [--cdn] [script dir, default .] [out dir, default tools/norns-web/dist]
//
// The out dir gets the page, the runtime, files.json (every .lua file of the
// script), the script's lib/Engine_*.js stand-ins, and vendored wasmoon; with
// --cdn the page loads the same pinned wasmoon from jsdelivr instead.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { manifest } from "./manifest.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const cdn = args.includes("--cdn");
const [dirArg, outArg] = args.filter(a => a !== "--cdn");
const scriptDir = path.resolve(dirArg || ".");
const out = path.resolve(outArg || path.join(here, "dist"));
const WASMOON_CDN = "https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/dist/";

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, "script/lib"), { recursive: true });
for (const f of ["norns-web.js", "norns.lua"]) fs.copyFileSync(path.join(here, f), path.join(out, f));
let page = fs.readFileSync(path.join(here, "index.html"), "utf8");
if (cdn) {
  page = page.replace('window.NORNS_WEB_WASMOON = "vendor/wasmoon/"', `window.NORNS_WEB_WASMOON = "${WASMOON_CDN}"`)
    .replace('<script src="vendor/wasmoon/index.js"></script>', `<script src="${WASMOON_CDN}index.js"></script>`);
} else {
  fs.mkdirSync(path.join(out, "vendor/wasmoon"), { recursive: true });
  for (const f of fs.readdirSync(path.join(here, "vendor/wasmoon"))) {
    fs.copyFileSync(path.join(here, "vendor/wasmoon", f), path.join(out, "vendor/wasmoon", f));
  }
}
fs.writeFileSync(path.join(out, "index.html"), page);
const libDir = path.join(scriptDir, "lib");
for (const f of fs.existsSync(libDir) ? fs.readdirSync(libDir) : []) {
  if (/^Engine_.*\.js$/.test(f)) fs.copyFileSync(path.join(libDir, f), path.join(out, "script/lib", f));
}
const m = manifest(scriptDir, "script/");
fs.writeFileSync(path.join(out, "files.json"), JSON.stringify(m));
console.log(`norns-web: ${m.name} (${Object.keys(m.files).length} .lua files) -> ${path.relative(process.cwd(), out) || "."}`);
