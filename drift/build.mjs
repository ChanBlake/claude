#!/usr/bin/env node
/* DRIFT — build a distributable executable.
 *
 *   node build.mjs              build for the machine you're on
 *   node build.mjs --win        force Windows targets
 *   node build.mjs --all        Windows + macOS + Linux
 *   node build.mjs --portable   single .exe, no installer (easiest to hand around)
 *
 * Why a script instead of a raw electron-builder command: this checks the things
 * that actually go wrong — Node too old, no network, missing icon, a broken sector
 * — and says so in plain language instead of failing three minutes into a build.
 *
 * The sector verifier runs FIRST and hard-blocks the build. An unsolvable level
 * should never reach an executable, let alone a store page.
 */

import { spawn } from "node:child_process";
import { existsSync, readFileSync, statSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(fileURLToPath(new URL(".", import.meta.url)));
const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);

const C = { dim:"\x1b[2m", red:"\x1b[31m", green:"\x1b[32m", amber:"\x1b[33m",
            teal:"\x1b[36m", bold:"\x1b[1m", off:"\x1b[0m" };
const say  = (m) => console.log(m);
const step = (m) => console.log(`\n${C.teal}${C.bold}▸ ${m}${C.off}`);
const ok   = (m) => console.log(`  ${C.green}✓${C.off} ${m}`);
const warn = (m) => console.log(`  ${C.amber}!${C.off} ${m}`);
const die  = (m, hint) => {
  console.error(`\n  ${C.red}✗ ${m}${C.off}`);
  if (hint) console.error(`  ${C.dim}${hint}${C.off}`);
  process.exit(1);
};

function run(cmd, args, opts = {}) {
  return new Promise((res, rej) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: "inherit", shell: process.platform === "win32", ...opts });
    p.on("error", rej);
    p.on("close", (code) => (code === 0 ? res() : rej(new Error(`${cmd} exited ${code}`))));
  });
}
function capture(cmd, args) {
  return new Promise((res) => {
    const p = spawn(cmd, args, { cwd: ROOT, shell: process.platform === "win32" });
    let out = "";
    p.stdout?.on("data", (d) => (out += d));
    p.stderr?.on("data", (d) => (out += d));
    p.on("error", () => res({ code: 1, out }));
    p.on("close", (code) => res({ code, out }));
  });
}

/* ── preflight ─────────────────────────────────────────────── */
say(`\n${C.bold}DRIFT — build${C.off}`);

step("Checking the toolchain");
const major = parseInt(process.versions.node.split(".")[0], 10);
if (major < 18) die(`Node ${process.versions.node} is too old.`, "Electron builds need Node 18 or newer — nodejs.org");
ok(`Node ${process.versions.node}`);

for (const f of ["index.html", "src/main.js", "src/levels.js", "electron/main.cjs", "package.json"]) {
  if (!existsSync(join(ROOT, f))) die(`Missing ${f}`, "Run this from inside the drift/ folder.");
}
ok("project files present");

if (existsSync(join(ROOT, "build/icon.ico"))) ok("icon.ico found");
else warn("no build/icon.ico — the exe will use Electron's default icon");

/* ── the gate ──────────────────────────────────────────────── */
step("Verifying all sectors");
try {
  await run(process.execPath, ["tools/verify.mjs"]);
} catch {
  die("A sector failed verification.",
      "The build is blocked on purpose: an unsolvable level must not ship.\nFix what the report named, then run this again.");
}

/* ── dependencies ──────────────────────────────────────────── */
step("Checking dependencies");
const haveElectron = existsSync(join(ROOT, "node_modules/electron"));
const haveBuilder  = existsSync(join(ROOT, "node_modules/electron-builder"));

if (!haveElectron || !haveBuilder) {
  warn("Electron isn't installed yet — this downloads roughly 250MB, once.");
  const net = await capture("npm", ["ping", "--silent"]);
  if (net.code !== 0) {
    die("No connection to the npm registry.",
        "Building an .exe needs Electron's prebuilt binaries, which have to be downloaded.\n" +
        "Connect to the internet and run this again. Nothing else about the game needs a network.");
  }
  say(`  ${C.dim}installing…${C.off}`);
  try { await run("npm", ["install", "--no-audit", "--no-fund"]); }
  catch { die("npm install failed.", "Scroll up for npm's reason — usually a proxy or a permissions issue."); }
}
ok("electron + electron-builder ready");

/* ── targets ───────────────────────────────────────────────── */
const targets = [];
if (has("--all")) targets.push("--win", "--mac", "--linux");
else if (has("--win")) targets.push("--win");
else if (has("--mac")) targets.push("--mac");
else if (has("--linux")) targets.push("--linux");
else targets.push(process.platform === "darwin" ? "--mac" : process.platform === "win32" ? "--win" : "--linux");

if (has("--portable") && targets.includes("--win")) targets.push("-c.win.target=portable");

if (targets.includes("--win") && process.platform !== "win32") {
  warn("Cross-building a Windows exe from " + process.platform + ".");
  warn("electron-builder handles this, but code signing does not cross-build —");
  warn("the exe will be unsigned and Windows will show a SmartScreen warning.");
}

step("Building " + targets.filter((t) => t.startsWith("--")).join(" "));
try {
  await run("npx", ["electron-builder", ...targets]);
} catch {
  die("electron-builder failed.", "Scroll up for the reason. Wine is required to cross-build Windows installers from Linux;\n--portable avoids that for a plain exe.");
}

/* ── report ────────────────────────────────────────────────── */
step("Done");
const dist = join(ROOT, "dist");
if (existsSync(dist)) {
  const interesting = readdirSync(dist).filter((f) => /\.(exe|dmg|AppImage|zip)$/i.test(f) || statSync(join(dist, f)).isDirectory());
  for (const f of interesting) {
    const p = join(dist, f);
    const s = statSync(p);
    const size = s.isDirectory() ? "folder" : (s.size / 1048576).toFixed(0) + " MB";
    console.log(`  ${C.green}→${C.off} dist/${f}  ${C.dim}${size}${C.off}`);
  }
  console.log(`\n  ${C.dim}A .exe is what you double-click. The unpacked folder (win-unpacked)`);
  console.log(`  is what you point SteamPipe at — Steam wants a directory, not an installer.${C.off}\n`);
} else {
  warn("no dist/ folder — check the output above");
}
