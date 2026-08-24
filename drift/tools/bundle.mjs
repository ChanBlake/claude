#!/usr/bin/env node
/* DRIFT — single-file bundler.
 *
 * Produces drift-standalone.html: the whole game in one file that runs from a
 * double-click, with no server and no module loading. The project build and the
 * standalone build come from the same source, so they cannot drift apart.
 *
 * This is a concatenator, not a real bundler — it strips import/export lines and
 * joins the modules in dependency order. That works because the module graph is
 * a straight line (config -> levels -> save -> audio -> game) with no cycles and
 * no name collisions. If that ever stops being true, reach for a real bundler
 * rather than making this cleverer.
 *
 *   node tools/bundle.mjs [outfile]
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const OUT = process.argv[2] || join(ROOT, "..", "drift-standalone.html");

const ORDER = ["config.js", "themes.js", "levels.js", "save.js", "audio.js", "game.js"];

function strip(name) {
  const src = readFileSync(join(ROOT, "src", name), "utf8");
  return src
    // imports can span lines, so match the whole statement rather than filtering lines
    .replace(/^[ \t]*import\s[\s\S]*?from\s+["']\.\/[^"']+["'];?[ \t]*\n/gm, "")
    .replace(/^(\s*)export\s+(const|let|function|class|async)/gm, "$1$2")
    .trim();
}

const modules = ORDER.map((n) => `/* ── ${n} ─────────────────────────────── */\n${strip(n)}`).join("\n\n");

const html = readFileSync(join(ROOT, "index.html"), "utf8");
const css = readFileSync(join(ROOT, "src", "style.css"), "utf8");

const out = html
  .replace('<link rel="stylesheet" href="src/style.css">', `<style>\n${css}\n</style>`)
  .replace(
    '<script type="module" src="src/main.js"></script>',
    `<script>\n(() => {\n"use strict";\n\n${modules}\n\n/* ── entry ─────────────────────────────── */\nloadSave().finally(boot);\n})();\n</script>`
  );

writeFileSync(OUT, out);

const kb = (Buffer.byteLength(out) / 1024).toFixed(0);
console.log(`bundled ${ORDER.length} modules -> ${OUT}  (${kb} KB)`);
