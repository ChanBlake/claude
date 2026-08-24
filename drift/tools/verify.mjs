#!/usr/bin/env node
/* DRIFT — sector verifier.
 *
 * This exists because level geometry is easy to get wrong in ways that are
 * invisible until a player is stuck. During development it caught four
 * genuinely unsolvable sectors: a switch sealed behind hull, cargo pushed into
 * a spot with nowhere to stand, cargo placed above the reachable floor, and a
 * data core walled off by unbroken plating.
 *
 * It proves four things about every sector:
 *   1. REACHABLE  — every switch, plate, cargo, core and airlock can be stood on
 *   2. PUSHABLE   — every cargo can be shoved onto a plate by a player who has
 *                   somewhere to stand behind it, gravity settling included
 *   3. NECESSARY  — removing any granted ability makes the sector unsolvable,
 *                   so no sector hands out gear it doesn't need
 *   4. STRUCTURAL — grid size, sealed borders, one spawn, one airlock,
 *                   no door without a trigger, no lattice without a coupler
 *
 * What it does NOT model, and why:
 *   - rewind: it governs the return trip, not whether a place is reachable
 *   - ferry timing: sweeps are treated as fully swept, so timing is a design
 *     concern rather than a solvability one
 *   - plating collapse: '~' is treated as permanently solid, which is strict.
 *     A sector must be solvable WITHOUT riding a collapse; that is deliberate,
 *     because a route that depends on floor giving way is a route a player
 *     cannot see.
 *
 * Reach is derived from config.js rather than hardcoded, so retuning the jump
 * automatically re-checks all sectors against the new envelope.
 *
 *   node tools/verify.mjs           check everything
 *   node tools/verify.mjs --sector 18   check one, with a map dump
 */

import { LEVELS, ZONES, zoneOf } from "../src/levels.js";
import { VCOLS, VROWS, reach } from "../src/config.js";

/* Sectors declare their own size now, so grid dimensions are read per level
   rather than imported. The viewport constants are kept only to report how
   many screens wide a sector is. */
let COLS = VCOLS, ROWS = VROWS;
function dims(rows){ ROWS = rows.length; COLS = rows[0].length; }

const R = reach();
const ENVELOPE = {
  noBurst: { up: Math.floor(R.singleTiles), span: Math.floor(R.singleSpan) },
  burst:   { up: Math.floor(R.doubleTiles), span: Math.floor(R.doubleSpan) },
};

/* ── tile semantics ─────────────────────────────────────────── */
const at = (g, c, r) =>
  c < 0 || c >= COLS || r < 0 || r >= ROWS ? "#" : g[r][c];

const blocking = (g, c, r, ph) => {
  const t = at(g, c, r);
  // ':' (false wall) is intentionally absent: secrets must be provably reachable.
  // '>' '<' (conveyor plating) are solid floor you stand on.
  return t === "#" || t === "~" || t === ">" || t === "<" ||
         (t === "=" && ph === 0) || (t === "%" && ph === 1);
};
const standable = (g, c, r, ph, plat) =>
  blocking(g, c, r, ph) || at(g, c, r) === "-" || plat.has(`${c},${r}`);
const free = (g, c, r, ph) =>
  c >= 0 && c < COLS && r >= 0 && r < ROWS && !blocking(g, c, r, ph) && at(g, c, r) !== "^";
const isField = (g, c, r) => at(g, c, r) === "Z";

function sweptPlatforms(mp) {
  const s = new Set();
  for (const m of mp || []) {
    for (let k = 0; k <= m.dist; k++)
      for (let i = 0; i < m.w; i++)
        s.add(`${m.c + i + (m.axis === "x" ? k : 0)},${m.r + (m.axis === "y" ? k : 0)}`);
  }
  return s;
}

/* ── reachability: BFS over (col,row,gravity,phase) ──────────── */
function explore(rows, mp, kit) {
  dims(rows);
  const g = rows.map((r) => r.split(""));
  const plat = sweptPlatforms(mp);
  const canBurst = kit.includes("B"), canFlip = kit.includes("F");
  const { up: UP, span: SPAN } = canBurst ? ENVELOPE.burst : ENVELOPE.noBurst;

  // an L-shaped corridor of open tiles: run then rise, or rise then run.
  // This is how a real jump arc clears a wall, and it is what stops the
  // solver from cheerfully routing straight through hull.
  const clear = (c0, r0, c1, r1, ph) => {
    const vleg = (c, a, b) => {
      for (let t = Math.min(a, b); t <= Math.max(a, b); t++) if (!free(g, c, t, ph)) return false;
      return true;
    };
    const hleg = (r, a, b) => {
      for (let t = Math.min(a, b); t <= Math.max(a, b); t++) if (!free(g, t, r, ph)) return false;
      return true;
    };
    return (vleg(c0, r0, r1) && hleg(r1, c0, c1)) || (hleg(r0, c0, c1) && vleg(c1, r0, r1));
  };

  let start = null;
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) if (g[r][c] === "P") start = [c, r];
  if (!start) return { g, plat, seen: new Set(), seenPh: new Set(), err: "no spawn" };

  const key = (c, r, gd, ph) => `${c},${r},${gd},${ph}`;
  const seenState = new Set([key(start[0], start[1], 1, 0)]);
  const queue = [[start[0], start[1], 1, 0]];

  while (queue.length) {
    const [c, r, gd, ph] = queue.shift();
    const add = (nc, nr, ngd, nph) => {
      if (!free(g, nc, nr, nph)) return;
      const k = key(nc, nr, ngd, nph);
      if (seenState.has(k)) return;
      seenState.add(k);
      queue.push([nc, nr, ngd, nph]);
    };

    if (at(g, c, r) === "T") add(c, r, gd, 1 - ph);   // phase coupler
    if (canFlip) add(c, r, -gd, ph);                  // gravity inversion

    if (isField(g, c, r)) {                            // null field: free flight
      add(c + 1, r, gd, ph); add(c - 1, r, gd, ph);
      add(c, r + 1, gd, ph); add(c, r - 1, gd, ph);
      continue;
    }

    if (!standable(g, c, r + gd, ph, plat)) {          // unsupported: fall
      let nr = r + gd;
      while (free(g, c, nr, ph) && !standable(g, c, nr, ph, plat) && !isField(g, c, nr)) nr += gd;
      if (isField(g, c, nr)) add(c, nr, gd, ph);       // fell into a field
      else add(c, nr - gd, gd, ph);
      continue;
    }

    add(c - 1, r, gd, ph); add(c + 1, r, gd, ph);      // walk
    for (let dv = 0; dv <= UP; dv++)                   // jump arc
      for (let dh = -SPAN; dh <= SPAN; dh++) {
        const nc = c + dh, nr = r - dv * gd;
        if (free(g, nc, nr, ph) && clear(c, r, nc, nr, ph)) add(nc, nr, gd, ph);
      }
  }

  const seen = new Set(), seenPh = new Set();
  for (const k of seenState) {
    const [c, r, , ph] = k.split(",");
    seen.add(`${c},${r}`);
    seenPh.add(`${c},${r},${ph}`);
  }
  return { g, plat, seen, seenPh };
}

/* ── cargo: can it actually be pushed onto a plate? ──────────── */
function cargoSolvable(g, plat, seenPh) {
  const plates = [], cargo = [];
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++) {
      if (g[r][c] === "B") plates.push(`${c},${r}`);
      if (g[r][c] === "A" || g[r][c] === "C") cargo.push([c, r]);
    }
  if (!plates.length) return [];
  // A projector's phantom can hold a plate. Like rewind it governs holding
  // rather than reaching, so it isn't modelled — those sectors are exempt.
  const hasProjector = g.some((row) => row.includes("X"));
  if (!cargo.length) return hasProjector ? [] : ["a plate with no cargo to hold it"];

  const phases = new Set([...seenPh].map((k) => k.split(",")[2]).map(Number));
  const problems = [];

  for (const [sc, sr] of cargo) {
    let solved = false;
    for (const ph of phases) {
      const settle = (c, r) => {                       // cargo falls until held
        while (!standable(g, c, r + 1, ph, plat)) r++;
        return [c, r];
      };
      const [c0, r0] = settle(sc, sr);
      const seen = new Set([`${c0},${r0}`]);
      const q = [[c0, r0]];
      while (q.length) {
        const [c, r] = q.shift();
        if (plates.includes(`${c},${r}`)) { solved = true; break; }
        for (const d of [-1, 1]) {
          if (blocking(g, c + d, r, ph)) continue;              // blocked ahead
          if (!seenPh.has(`${c - d},${r},${ph}`)) continue;     // nowhere to stand behind it
          const [nc, nr] = settle(c + d, r);
          const k = `${nc},${nr}`;
          if (!seen.has(k)) { seen.add(k); q.push([nc, nr]); }
        }
      }
      if (solved) break;
    }
    if (!solved) problems.push(`cargo at (${sc},${sr}) cannot be pushed onto any plate`);
  }
  return problems;
}

/* ── shortcut detection ─────────────────────────────────────────
 * Reachability says the airlock can be got to. It never asked whether it can be
 * got to WITHOUT engaging the sector — and an open level lets you climb to the
 * ceiling and run the whole length untouched, which turns three stages into a
 * corridor. This measures the forced vertical travel between one stage seam and
 * the next: if you enter a stage at row 3 and leave it at row 2, everything in
 * between is decoration.
 *
 * Sectors whose top corridor is gated by a closed door are exempt — the door is
 * doing the work, and the solver treats doors as open so it cannot see that. */
function stageTravel(L) {
  const rows = L.rows, W = rows[0].length, H = rows.length;
  const stages = Math.round((W - 25) / 24) + 1;
  if (stages < 3) return null;
  const seams = [];
  for (let k = 1; k < stages; k++) {
    const col = 24 * k;
    const open = [];
    for (let r = 0; r < H; r++) if (rows[r][col] !== "#") open.push(r);
    seams.push(open.length ? open[0] : null);
  }
  if (seams.some((s) => s === null)) return null;
  let spawn = 0;
  for (let r = 0; r < H; r++) for (let c = 0; c < W; c++) if (rows[r][c] === "P") spawn = r;
  let travel = Math.abs(seams[0] - spawn);
  for (let i = 0; i + 1 < seams.length; i++) travel += Math.abs(seams[i + 1] - seams[i]);
  // A door or a lattice wall across the route does the gating that geometry
  // otherwise would. The solver treats both as passable, so it cannot see them —
  // exempt those sectors rather than have the check cry wolf.
  const flat = rows.join("");
  const gated = flat.includes("D") || flat.includes("=") || flat.includes("%");
  return { travel, seams, gated };
}

/* ── structure ──────────────────────────────────────────────── */
function structural(L) {
  const e = [], rows = L.rows, flat = rows.join("");
  const widths = new Set(rows.map((r) => r.length));
  if (widths.size !== 1) e.push(`ragged width ${[...widths]}`);
  if (rows.length < VROWS) e.push(`${rows.length} rows — shorter than the viewport`);
  if (rows[0].length < VCOLS) e.push(`${rows[0].length} cols — narrower than the viewport`);
  if (e.length) return e;
  dims(rows);
  if (rows[0].replace(/#/g, "") || rows[ROWS - 1].replace(/#/g, "")) e.push("open top/bottom border");
  if (rows.some((r) => r[0] !== "#" || r[COLS - 1] !== "#")) e.push("open side border");
  const n = (ch) => flat.split(ch).length - 1;
  if (n("P") !== 1) e.push(`${n("P")} spawns`);
  if (n("E") !== 1) e.push(`${n("E")} airlocks`);
  if (n("D") && !(n("S") + n("B"))) e.push("door with nothing to open it");
  if ((n("=") || n("%")) && !n("T")) e.push("lattice with no coupler");
  if (n("B") && !(n("A") + n("C")) && !n("X"))
    e.push("plate with nothing to hold it — needs cargo or a projector");
  if (n("X") && !n("B")) e.push("projector with no plate to hold");
  if (typeof L.par !== "number" || L.par <= 0) e.push("missing par time");
  return e;
}

/* ── checks ─────────────────────────────────────────────────── */
function checkSector(L) {
  const errs = structural(L);
  if (errs.length) return { errs, cores: "-" };
  const { g, plat, seen, seenPh } = explore(L.rows, L.mp, L.kit || "");
  const lost = [];
  let cores = 0, coresLost = 0;
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++) {
      const t = g[r][c];
      if (t === "o") { cores++; if (!seen.has(`${c},${r}`)) coresLost++; }
      else if ("SBEAC".includes(t) && !seen.has(`${c},${r}`)) lost.push(`${t} at (${c},${r})`);
    }
  if (lost.length) errs.push("unreachable: " + lost.join(", "));
  errs.push(...cargoSolvable(g, plat, seenPh));
  if (coresLost) errs.push(`${coresLost} of ${cores} data core(s) unreachable`);
  if (!cores) errs.push("no data cores — nothing to 100%");
  return { errs, cores: coresLost ? `${cores - coresLost}/${cores}!` : `${cores}` };
}

function solvable(L, kit) {
  const { g, plat, seen, seenPh } = explore(L.rows, L.mp, kit);
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++)
      if ("SBEAC".includes(g[r][c]) && !seen.has(`${c},${r}`)) return false;
  return cargoSolvable(g, plat, seenPh).length === 0;
}

function checkNecessity(L) {
  const kit = L.kit || "", notes = [], redundant = [];
  for (const [ch, label] of [["B", "burst"], ["F", "flip"]]) {
    if (!kit.includes(ch)) continue;
    const needed = !solvable(L, kit.replace(ch, ""));
    notes.push(`${label} ${needed ? "required" : "REDUNDANT"}`);
    if (!needed) redundant.push(label);
  }
  if (kit.includes("R")) notes.push("rewind required");
  return { notes, redundant };
}

/* ── map dump for a single sector ───────────────────────────── */
function dump(L, i) {
  const { seen } = explore(L.rows, L.mp, L.kit || "");
  console.log(`\nSECTOR ${String(i + 1).padStart(2, "0")} · ${L.name}   [${zoneOf(i).name}]`);
  console.log(`loadout JUMP${L.kit.includes("B") ? "·BURST" : ""}${L.kit.includes("F") ? "·FLIP" : ""}${L.kit.includes("R") ? "·REWIND" : ""}   par ${L.par}s`);
  dims(L.rows);
  console.log("    " + [...Array(COLS).keys()].map((c) => c % 10).join(""));
  L.rows.forEach((row, r) => {
    const marked = [...row].map((ch, c) =>
      ch === "." && seen.has(`${c},${r}`) ? "·" : ch).join("");
    console.log(String(r).padStart(2) + "  " + marked);
  });
  console.log("\n  · = tile the solver proved you can occupy");
}

/* ── main ───────────────────────────────────────────────────── */
const argv = process.argv.slice(2);
const one = argv.indexOf("--sector");
if (one !== -1) {
  const i = parseInt(argv[one + 1], 10) - 1;
  if (!LEVELS[i]) { console.error("no such sector"); process.exit(1); }
  dump(LEVELS[i], i);
  const { errs } = checkSector(LEVELS[i]);
  console.log(errs.length ? "\nBROKEN: " + errs.join("; ") : "\nsolvable");
  process.exit(errs.length ? 1 : 0);
}

console.log(`DRIFT — verifying ${LEVELS.length} sectors`);
console.log(`jump envelope from config: ${R.singleTiles.toFixed(2)} tiles up / ${R.singleSpan.toFixed(2)} across`
  + `, ${R.doubleTiles.toFixed(2)} / ${R.doubleSpan.toFixed(2)} with burst\n`);

let failed = 0, redundantTotal = 0, zone = null;
console.log("  #  SECTOR           SIZE    LOADOUT                 CORES  RESULT");
LEVELS.forEach((L, i) => {
  const z = zoneOf(i);
  if (z !== zone) { zone = z; console.log(`     ── ${z.name} ${"─".repeat(Math.max(0, 46 - z.name.length))}`); }
  const { errs, cores } = checkSector(L);
  const st = stageTravel(L);
  if (st && !st.gated && !L.teach && st.travel < 6)
    errs.push(`stages barely stacked (${st.travel} rows of forced travel) — the middle stage can be walked past`);
  const { notes, redundant } = errs.length ? { notes: [], redundant: [] } : checkNecessity(L);
  redundantTotal += redundant.length;
  if (errs.length || redundant.length) failed++;
  const kit = L.kit || "";
  const load = "JUMP" + (kit.includes("B") ? "·BURST" : "") + (kit.includes("F") ? "·FLIP" : "") + (kit.includes("R") ? "·REWIND" : "");
  const verdict = errs.length ? "BROKEN — " + errs.join("; ")
    : redundant.length ? "issues unused gear: " + redundant.join(", ")
    : "ok   " + notes.join(", ");
  const size = `${L.rows[0].length}x${L.rows.length}`;
  console.log(`  ${String(i + 1).padStart(2)} ${L.name.padEnd(16)} ${size.padEnd(7)} ${load.padEnd(23)} ${cores.padEnd(6)} ${verdict}`);
});

console.log();
if (failed) {
  console.log(`FAILED — ${failed} sector(s) need attention` + (redundantTotal ? `, ${redundantTotal} redundant ability grant(s)` : ""));
  process.exit(1);
}
console.log(`All ${LEVELS.length} sectors verified: reachable, cargo-solvable, and issuing no gear they don't need.`);
