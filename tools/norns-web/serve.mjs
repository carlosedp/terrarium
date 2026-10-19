// norns-web dev server: serves the page and the script, reading files fresh
// on every request, so editing a .lua file and reloading the page is enough.
//
//   node tools/norns-web/serve.mjs [script dir, default .] [port, default 8800]
//
// /files.json  the script's name, main file and every .lua file under its dir
// /script/...  the script's own files (for lib/Engine_<name>.js)
// /...         this directory (page, runtime, vendored wasmoon)
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { manifest } from "./manifest.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const scriptDir = path.resolve(process.argv[2] || ".");
const port = +(process.argv[3] || 8800);
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".lua": "text/plain",
  ".json": "application/json", ".wasm": "application/wasm", ".css": "text/css" };

function send(res, file) {
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end("not found"); return; }
    res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream", "cache-control": "no-store" });
    res.end(data);
  });
}

// resolve a URL path under a base dir, refusing anything that climbs out of it
function under(base, urlPath) {
  const file = path.resolve(base, "." + decodeURIComponent(urlPath));
  return file === base || file.startsWith(base + path.sep) ? file : null;
}

http.createServer((req, res) => {
  const url = new URL(req.url, "http://x").pathname;
  if (url === "/files.json") {
    res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
    res.end(JSON.stringify(manifest(scriptDir, "script/")));
    return;
  }
  const file = url.startsWith("/script/") ? under(scriptDir, url.slice("/script".length))
    : under(here, url === "/" ? "/index.html" : url);
  if (!file) { res.writeHead(403); res.end(); return; }
  send(res, file);
}).listen(port, "127.0.0.1", () => {
  console.log(`norns-web: ${path.basename(scriptDir)} at http://localhost:${port}/`);
});
