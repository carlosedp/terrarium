// The files.json the page loads: the script's name, its main file, where its
// other files are served from (root), and the source of every .lua file.
import fs from "node:fs";
import path from "node:path";

const SKIP = new Set([".git", "node_modules", "tools", "dist", "test"]);

export function manifest(scriptDir, root) {
  const name = path.basename(scriptDir);
  const files = {};
  const walk = dir => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name.startsWith(".") || SKIP.has(e.name)) continue;
      const full = path.join(dir, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.name.endsWith(".lua")) files[path.relative(scriptDir, full).split(path.sep).join("/")] = fs.readFileSync(full, "utf8");
    }
  };
  walk(scriptDir);
  const main = `${name}.lua`;
  if (!files[main]) throw new Error(`no ${main} in ${scriptDir}`);
  return { name, main, root, files };
}
