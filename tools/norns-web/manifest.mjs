// The files.json the page loads: the script's name, its main file, where its
// other files are served from (root), the source of every .lua file, and the
// script's optional norns-web.json (about: a title, subtitle, intro, links and
// footer for the page). skip: absolute paths to leave out, such as build.mjs's out dir when it
// sits inside the script (a Pages workflow's _site), which holds norns-web's own norns.lua.
import fs from "node:fs";
import path from "node:path";

const SKIP = new Set([".git", "node_modules", "tools", "dist", "test"]);

export function manifest(scriptDir, root, skip = []) {
  const skipped = new Set(skip.map(p => path.resolve(p)));
  const name = path.basename(scriptDir);
  const files = {};
  const walk = dir => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name.startsWith(".") || SKIP.has(e.name)) continue;
      const full = path.join(dir, e.name);
      if (skipped.has(full)) continue;
      if (e.isDirectory()) walk(full);
      else if (e.name.endsWith(".lua")) files[path.relative(scriptDir, full).split(path.sep).join("/")] = fs.readFileSync(full, "utf8");
    }
  };
  walk(scriptDir);
  const main = `${name}.lua`;
  if (!files[main]) throw new Error(`no ${main} in ${scriptDir}`);
  const aboutFile = path.join(scriptDir, "norns-web.json");
  const about = fs.existsSync(aboutFile) ? JSON.parse(fs.readFileSync(aboutFile, "utf8")) : null;
  return { name, main, root, files, about };
}
