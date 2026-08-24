#!/usr/bin/env node
/* DRIFT — local dev server.
 *
 * The project is ES modules, and browsers refuse to load those over file://
 * (CORS treats every local file as a distinct opaque origin). So the folder
 * needs to be served over http, even though nothing here is built or bundled.
 *
 * This is deliberately dependency-free: `node serve.mjs` works on a clean
 * machine with no npm install, no network, and no package resolution. That
 * matters because the single most common way to fail at "just open the game"
 * is an install step that breaks before you ever see a pixel.
 *
 *   node serve.mjs           serve on 5173 and open the game
 *   node serve.mjs --port 8080
 *   node serve.mjs --no-open
 */

import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { join, extname, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const ROOT = resolve(fileURLToPath(new URL(".", import.meta.url)));

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const val = (n, d) => { const i = argv.indexOf(n); return i === -1 ? d : argv[i + 1]; };
const PORT = parseInt(val("--port", "5173"), 10);

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js":   "text/javascript; charset=utf-8",
  ".mjs":  "text/javascript; charset=utf-8",
  ".css":  "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg":  "image/svg+xml",
  ".png":  "image/png",
  ".ico":  "image/x-icon",
};

const server = createServer(async (req, res) => {
  try {
    let path = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    if (path.endsWith("/")) path += "index.html";

    // never serve outside the project directory
    const file = join(ROOT, normalize(path));
    if (!file.startsWith(ROOT)) { res.writeHead(403).end("forbidden"); return; }

    const info = await stat(file);
    if (info.isDirectory()) { res.writeHead(302, { Location: path + "/" }).end(); return; }

    const body = await readFile(file);
    res.writeHead(200, {
      "Content-Type": TYPES[extname(file)] || "application/octet-stream",
      "Cache-Control": "no-store",           // always serve your latest edit
    });
    res.end(body);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain" }).end("not found");
  }
});

function open(url) {
  const cmd = process.platform === "darwin" ? "open"
            : process.platform === "win32" ? "cmd"
            : "xdg-open";
  const args = process.platform === "win32" ? ["/c", "start", "", url] : [url];
  try { spawn(cmd, args, { stdio: "ignore", detached: true }).unref(); } catch {}
}

server.listen(PORT, () => {
  const url = `http://localhost:${PORT}/`;
  console.log(`
  DRIFT is running.

    game     ${url}
    editor   ${url}tools/editor.html

  Ctrl-C to stop. Edits are picked up on refresh — there is no build step.
`);
  if (!flag("--no-open")) open(url);
});

server.on("error", (e) => {
  if (e.code === "EADDRINUSE") {
    console.error(`\n  Port ${PORT} is busy. Try:  node serve.mjs --port ${PORT + 1}\n`);
    process.exit(1);
  }
  throw e;
});
