#!/usr/bin/env node
/* Proves the installed experience before anyone installs it: serve the site
 * the workflow builds, register the worker, then pull the plug and reload.
 * localhost counts as a secure context, so this is the real code path.
 *   node tools/pwacheck.js <dir> */
"use strict";
const http = require("http"), fs = require("fs"), path = require("path");
const { chromium } = require("playwright");
const DIR = process.argv[2] || "/tmp/site";
const TYPES = { ".html": "text/html", ".js": "text/javascript",
                ".png": "image/png", ".webmanifest": "application/manifest+json" };

const server = http.createServer((req, res) => {
  let f = decodeURIComponent(req.url.split("?")[0]);
  if (f === "/") f = "/index.html";
  const p = path.join(DIR, f);
  if (!p.startsWith(DIR) || !fs.existsSync(p)) { res.writeHead(404); return res.end("no"); }
  res.writeHead(200, { "content-type": TYPES[path.extname(p)] || "application/octet-stream" });
  fs.createReadStream(p).pipe(res);
});

server.listen(0, async () => {
  const port = server.address().port;
  const base = "http://localhost:" + port + "/";
  const browser = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  const ctx = await browser.newContext({
    viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true,
  });
  const page = await ctx.newPage();
  const errs = []; page.on("pageerror", e => errs.push("PAGEERROR " + e.message));
  page.on("console", m => { if (m.type() === "error") errs.push("CONSOLE " + m.text()); });

  await page.goto(base + "index.html");
  await page.click("#start");
  await page.waitForTimeout(1500);

  const manifest = await page.evaluate(async () => {
    const r = await fetch("./manifest.webmanifest");
    return { ok: r.ok, type: r.headers.get("content-type"), body: await r.json() };
  });
  console.log("manifest:", manifest.ok, "|", manifest.type, "| icons:", manifest.body.icons.length,
              "| display:", manifest.body.display, "| orientation:", manifest.body.orientation);

  const reg = await page.evaluate(() =>
    navigator.serviceWorker.ready.then(r => !!r.active).catch(e => "ERR " + e));
  console.log("service worker active:", reg);

  const cached = await page.evaluate(async () => {
    const keys = await caches.keys();
    if (!keys.length) return { cache: "(none)", entries: [] };
    const c = await caches.open(keys[0]);
    return { cache: keys[0], entries: (await c.keys()).map(r => new URL(r.url).pathname).sort() };
  });
  console.log("cache:", cached.cache, "->", cached.entries.join(" "));

  // Now pull the plug: everything must still come off the shelf.
  await ctx.setOffline(true);
  await page.goto(base + "index.html");
  const offline = await page.evaluate(() => ({
    title: document.title, canvas: !!document.getElementById("screen"),
  }));
  await page.click("#start");
  await page.waitForTimeout(800);
  const drew = await page.evaluate(() => {
    const c = document.getElementById("screen");
    return c.width + "x" + c.height;
  });
  await page.screenshot({ path: "/tmp/offline.png" });
  console.log("OFFLINE reload:", JSON.stringify(offline), "canvas:", drew);
  console.log(errs.length ? "errors:\n  " + errs.join("\n  ") : "no page errors");
  await browser.close();
  server.close();
});
