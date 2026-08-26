#!/usr/bin/env node
/*
 * Drive-level diagnostics. The per-play averages in balance.js can look sane
 * while the scoreboard is absurd, because points come from *drives*: where a
 * possession starts decides how few yards a touchdown costs. This walks whole
 * games and reports, for every possession we get, where it started, how many
 * snaps it lasted, and what it produced.
 *
 *   node tools/drives.js [games]
 */
"use strict";
const { loadGame } = require("./harness.js");

const GAMES = +(process.argv[2] || 12);
const A = loadGame();
const { FIELD, TEAMS, makeRNG } = A;
const QLEN = +(process.env.QLEN || 180);
A.SETTINGS.diff = 1;

const drives = [];          // one row per possession of ours
const gains = { pass: [], rush: [] };   // per-play gains, for the tail
const air = [], yac = [];               // where a completion is caught vs where it ends
const theirs = { td: 0, fg: 0, punt: 0, turnover: 0, miss: 0 };
let usPts = 0, themPts = 0;

for (let g = 0; g < GAMES; g++) {
  A.SCREEN = "game";
  const rng = makeRNG(5000 + g * 37);
  A.newGame(TEAMS[g % 8].ab, TEAMS[(g + 4) % 8].ab);
  const st = A.G.st;
  st.quarterLen = QLEN; st.clock = QLEN;
  let frames = 0;
  const H = 1 / 60;

  let cur = null, lastPoss = null, lastUs = 0, lastThem = 0, lastPlays = 0, lastYards = 0;
  let lastPass = 0, lastRush = 0, lastAtt = 0, lastComp = 0;
  let catchY = null, scored = false;
  const close = how => { if (cur) { cur.how = how; drives.push(cur); cur = null; } };

  while (st.phase !== "final" && frames < 60 * 60 * 14) {
    A.draw();
    if (st.phase === "playcall") {
      const opts = A.HOT.filter(b => b.id.startsWith("play:"));
      let pick;
      if (st.down === 4) {
        const fg = A.HOT.find(b => b.id === "fg");
        const p = A.HOT.find(b => b.id === "punt");
        pick = (st.toGo <= 2 && rng.chance(0.5)) ? rng.pick(opts) : (fg && rng.chance(0.7) ? fg : (p || rng.pick(opts)));
      } else if (st.toGo <= 3) {
        pick = opts.find(o => o.id === "play:dive") || rng.pick(opts);
      } else if (st.toGo >= 8) {
        pick = rng.pick(opts.filter(o => ["play:curls", "play:verts", "play:slants"].includes(o.id))) || rng.pick(opts);
      } else pick = rng.pick(opts);
      if (pick) A.Input.tap = pick.id;
    } else if (st.phase === "presnap") A.Input.snap = true;
    else if (st.phase === "try") A.Input.tap = "xp";
    else if (st.phase === "kick" && st.kick && !st.kick.flight) A.resolveKick(rng.range(-1.6, 1.6), rng.range(0.7, 1));
    else if (st.phase === "defense") A.Input.tap = "advance";
    else if (st.phase === "live" && A.G.play) {
      const sim = A.G.play;
      if (sim.qbHasIt() && !sim.threw && sim.t > (st.chosen.develop || 1)) {
        const tg = sim.targets();
        if (tg.length) {
          const qb = sim.P[0];
          let best = null, bestScore = -1e9;
          for (const r of tg) {
            const open = Math.min(...sim.P.filter(p => p.side === "def" && p.mot !== "down")
              .map(p => Math.hypot(p.x - r.x, p.y - r.y)));
            const score = open * 1.6 + (r.y - st.los) * 0.3;
            if (score > bestScore) { bestScore = score; best = r; }
          }
          const flight = Math.hypot(best.x - qb.x, best.y - qb.y) / A.CFG.passSpeed;
          A.Input.throwTo = { x: best.x + best.vx * flight, y: best.y + best.vy * flight };
        }
      } else if (sim.ball.state === "air") {
        A.Input.steerX = 0; A.Input.steerY = 0; A.Input.sprint = false;
      } else {
        const c = sim.P.find(p => p.hasBall);
        if (c) {
          let bx = 0, bs = -1e9;
          for (let dx = -1; dx <= 1; dx += 0.25) {
            const tx = c.x + dx * 4, ty = c.y + 3;
            const near = Math.min(...sim.P.filter(p => p.side === "def" && p.mot !== "down")
              .map(p => Math.hypot(p.x - tx, p.y - ty)));
            if (near > bs && tx > 2 && tx < FIELD.W - 2) { bs = near; bx = dx; }
          }
          A.Input.steerX = bx; A.Input.steerY = 1; A.Input.sprint = true;
        } else { A.Input.steerX = 0; A.Input.steerY = 0; A.Input.sprint = false; }
      }
    }

    // --- observe ----------------------------------------------------
    if (st.stats.us.plays !== lastPlays) {
      const dp = st.stats.us.pass - lastPass, dr = st.stats.us.rush - lastRush;
      if (st.stats.us.att !== lastAtt) { if (st.stats.us.comp !== lastComp) gains.pass.push(dp); }
      else gains.rush.push(dr);
      lastPlays = st.stats.us.plays; lastPass = st.stats.us.pass; lastRush = st.stats.us.rush;
      lastAtt = st.stats.us.att; lastComp = st.stats.us.comp;
    }
    if (A.G.play && A.G.play.completed && catchY == null) catchY = A.G.play.P.find(p => p.hasBall) ? A.G.play.P.find(p => p.hasBall).y : null;
    if (A.G.play && A.G.play.over && catchY != null && !scored) {
      scored = true;
      air.push(catchY - st.los); yac.push(A.G.play.result.y - catchY);
    }
    if (!A.G.play || !A.G.play.completed) { if (!A.G.play) { catchY = null; scored = false; } }
    const poss = st.poss;
    if (poss === "us" && lastPoss !== "us") {
      cur = { start: st.los, toGoal: FIELD.oppGoal - st.los, plays0: st.stats.us.plays, yards0: st.stats.us.yards, q: st.q };
      lastPlays = st.stats.us.plays; lastYards = st.stats.us.yards;
    }
    if (cur) { cur.plays = st.stats.us.plays - cur.plays0; cur.yards = st.stats.us.yards - cur.yards0; }
    if (st.us > lastUs) {
      const d = st.us - lastUs;
      if (d >= 6 && cur) close("td");
      lastUs = st.us;
    }
    if (st.them > lastThem) {
      const d = st.them - lastThem;
      if (cur && d === 2) close("safety");
      lastThem = st.them;
    }
    if (poss !== "us" && lastPoss === "us") close(cur && cur.how ? cur.how : "give-up");
    if (poss === "them" && lastPoss !== "them" && st.drive) theirs[st.drive.result] = (theirs[st.drive.result] || 0) + 1;
    lastPoss = poss;

    A.update(H);
    frames++;
  }
  close("clock");
  usPts += st.us; themPts += st.them;
}

// --- report --------------------------------------------------------
const n = GAMES;
const scoring = drives.filter(d => d.how === "td");
const avg = (a, f) => a.length ? (a.reduce((s, d) => s + f(d), 0) / a.length) : 0;
const bucket = {};
for (const d of drives) {
  const k = d.toGoal >= 80 ? "80+" : d.toGoal >= 60 ? "60-79" : d.toGoal >= 40 ? "40-59" : d.toGoal >= 20 ? "20-39" : "<20";
  (bucket[k] = bucket[k] || { n: 0, td: 0 }).n++;
  if (d.how === "td") bucket[k].td++;
}

console.log(`${n} games   us ${(usPts / n).toFixed(1)}  them ${(themPts / n).toFixed(1)}`);
console.log(`possessions/game ${(drives.length / n).toFixed(1)}   TD drives/game ${(scoring.length / n).toFixed(1)}`);
console.log(`avg start: ${avg(drives, d => d.toGoal).toFixed(1)} yds from the end zone`);
console.log(`TD drives: ${avg(scoring, d => d.plays).toFixed(1)} plays, ${avg(scoring, d => d.yards).toFixed(1)} yards, started ${avg(scoring, d => d.toGoal).toFixed(1)} out`);
console.log("start bucket   n    TD%");
for (const k of ["80+", "60-79", "40-59", "20-39", "<20"]) {
  const b = bucket[k]; if (!b) continue;
  console.log(`  ${k.padEnd(6)} ${String(b.n).padStart(5)}  ${(b.td / b.n * 100).toFixed(0)}%`);
}
const ends = {};
for (const d of drives) ends[d.how] = (ends[d.how] || 0) + 1;
console.log("our drives end:", Object.entries(ends).map(([k, v]) => `${k} ${(v / n).toFixed(1)}`).join("  "));
const hist = a => {
  const b = [0, 0, 0, 0, 0, 0];
  for (const v of a) b[v < 0 ? 0 : v < 5 ? 1 : v < 10 ? 2 : v < 20 ? 3 : v < 35 ? 4 : 5]++;
  return b.map((v, i) => `${["<0", "0-4", "5-9", "10-19", "20-34", "35+"][i]}:${(v / a.length * 100).toFixed(0)}%`).join(" ");
};
console.log(`completed-pass gains (n=${gains.pass.length}, avg ${(gains.pass.reduce((s, v) => s + v, 0) / gains.pass.length).toFixed(1)}): ${hist(gains.pass)}`);
console.log(`run gains         (n=${gains.rush.length}, avg ${(gains.rush.reduce((s, v) => s + v, 0) / gains.rush.length).toFixed(1)}): ${hist(gains.rush)}`);
const mean = a => a.reduce((s, v) => s + v, 0) / Math.max(1, a.length);
console.log(`completions: air ${mean(air).toFixed(1)} + yac ${mean(yac).toFixed(1)} (n=${air.length})`);
console.log("their drives end:", Object.entries(theirs).map(([k, v]) => `${k} ${(v / n).toFixed(1)}`).join("  "));
