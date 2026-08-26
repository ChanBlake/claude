#!/usr/bin/env node
/*
 * Low-variance per-play sampler. Whole games give ~80 carries across thirty
 * games, which is far too few to tune a run game on — two settings a yard
 * apart look identical under that much noise. This runs a few hundred snaps of
 * each kind against a rotating set of defensive fronts and reports the shape of
 * the distribution, not just the mean.
 *
 *   node tools/plays.js [seeds-per-play] [path-to-index.html]
 */
"use strict";
const path = require("path");
const { loadGame } = require(path.join(__dirname, "harness.js"));

const N = +(process.argv[2] || 260);
const A = loadGame(process.argv[3] ? { file: process.argv[3] } : {});
const { PLAYS, SCHEMES, TEAMS, FIELD, makePlay, makeRoster, CFG } = A;

function runPlay(play, scheme, seed, los) {
  const sim = makePlay({
    play, scheme, los, ballX: FIELD.W / 2, lineToGain: los + 10,
    offense: makeRoster(TEAMS[3], 1), defense: makeRoster(TEAMS[1], 2), seed,
  });
  sim.snap();
  const H = 1 / 60;
  let t = 0, catchY = null, catcher = null;
  while (!sim.over && t < 40) {
    let inp = { steerX: 0, steerY: 0, sprint: true };
    if (play.kind === "pass" && sim.qbHasIt() && !sim.threw && t > play.develop) {
      // Throw to the most open man, led by flight time — what a good player does.
      const tg = sim.targets();
      if (tg.length) {
        const qb = sim.P[0];
        let best = null, bs = -1e9;
        for (const r of tg) {
          const open = Math.min(...sim.P.filter(p => p.side === "def" && p.mot !== "down")
            .map(p => Math.hypot(p.x - r.x, p.y - r.y)));
          const sc = open * 1.6 + (r.y - los) * 0.3;
          if (sc > bs) { bs = sc; best = r; }
        }
        // Solve for where he will be when the ball gets there, rather than
        // guessing from where he is now — three passes converge.
        let f = 0;
        for (let k = 0; k < 3; k++)
          f = Math.hypot(best.x + best.vx * f - qb.x, best.y + best.vy * f - qb.y) / CFG.passSpeed;
        inp.throwTo = { x: best.x + best.vx * f, y: best.y + best.vy * f };
      }
    } else if (sim.ball.state !== "air") {
      const c = sim.P.find(p => p.hasBall);
      if (c && c.side === "off" && process.env.STEER !== "0") {
        // Steer toward the biggest gap ahead — what a competent thumb does.
        let bx = 0, bs = -1e9;
        for (let dx = -1; dx <= 1; dx += 0.25) {
          const tx = c.x + dx * 4, ty = c.y + 3;
          const near = Math.min(...sim.P.filter(q => q.side === "def" && q.mot !== "down")
            .map(q => Math.hypot(q.x - tx, q.y - ty)));
          if (near > bs && tx > 2 && tx < FIELD.W - 2) { bs = near; bx = dx; }
        }
        inp.steerX = bx; inp.steerY = 1; inp.sprint = true;
      }
    }
    sim.step(H, inp);
    if (sim.completed && catchY == null) {
      const c = sim.P.find(p => p.hasBall);
      if (c) { catchY = c.y; catcher = c.pos; }
    }
    t += H;
  }
  return { r: sim.result, catchY, catcher };
}

const pct = (v, n) => (v / Math.max(1, n) * 100).toFixed(0) + "%";
const stat = { run: [], pass: [], air: [], yac: [] };
const byScheme = {}, byPlay = {}, why = {}, byPos = {}, cross = {};
const tally = { att: 0, comp: 0, inc: 0, sack: 0, to: 0, td: 0, carries: 0 };

for (const play of PLAYS) {
  for (let i = 0; i < N; i++) {
    const scheme = SCHEMES[i % SCHEMES.length];
    const los = [22, 40, 58, 76][i % 4];
    const { r, catchY, catcher } = runPlay(play, scheme, i * 31 + 7, los);
    if (catcher) byPos[catcher] = (byPos[catcher] || 0) + 1;
    if (!r) continue;
    if (r.kind === "td") tally.td++;
    if (r.kind.startsWith("int") || r.kind.startsWith("fumble")) { tally.to++; if (play.kind === "pass") tally.att++; continue; }
    if (play.kind === "pass") {
      tally.att++;
      if (r.kind === "incomplete") { tally.inc++; why[r.headline] = (why[r.headline] || 0) + 1; continue; }
      if (r.kind === "sack") { tally.sack++; continue; }
      tally.comp++;
      stat.pass.push(r.yards);
      if (catchY != null) { stat.air.push(catchY - los); stat.yac.push(r.y - catchY); }
    } else { tally.carries++; stat.run.push(r.yards); (byScheme[scheme.name] = byScheme[scheme.name] || []).push(r.yards); (byPlay[play.name] = byPlay[play.name] || []).push(r.yards);
      (cross[play.name + " vs " + scheme.name] = cross[play.name + " vs " + scheme.name] || []).push(r.yards); }
  }
}

const mean = a => a.reduce((s, v) => s + v, 0) / Math.max(1, a.length);
const shape = a => {
  const b = [0, 0, 0, 0, 0];
  for (const v of a) b[v < 0 ? 0 : v < 5 ? 1 : v < 10 ? 2 : v < 20 ? 3 : 4]++;
  return ["<0", "0-4", "5-9", "10-19", "20+"].map((k, i) => `${k} ${pct(b[i], a.length)}`).join("  ");
};

console.log(`runs   n=${stat.run.length}  avg ${mean(stat.run).toFixed(2)}   ${shape(stat.run)}`);
console.log(`comps  n=${stat.pass.length}  avg ${mean(stat.pass).toFixed(2)}   ${shape(stat.pass)}`);
console.log(`       air ${mean(stat.air).toFixed(1)} + yac ${mean(stat.yac).toFixed(1)}   35+ ${pct(stat.pass.filter(v => v >= 35).length, stat.pass.length)}`);
console.log(`passing ${tally.comp}/${tally.att} = ${pct(tally.comp, tally.att)}   sacks ${pct(tally.sack, tally.att)}   turnovers ${tally.to}`);
console.log("runs by front: " + Object.entries(byScheme).map(([k, v]) => `${k} ${mean(v).toFixed(1)}`).join("  "));
console.log("runs by play:  " + Object.entries(byPlay).map(([k, v]) => `${k} ${mean(v).toFixed(1)}`).join("  "));
console.log("caught by: " + Object.entries(byPos).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join("  "));
console.log("incompletions: " + Object.entries(why).map(([k, v]) => `${k} ${v}`).join("  "));
if (process.env.CROSS) {
  console.log("run play x front:");
  for (const [k, v] of Object.entries(cross)) console.log(`   ${k.padEnd(24)} ${mean(v).toFixed(1).padStart(6)}  (n=${v.length})`);
}
console.log(`NFL for reference: runs 4.3 (<0 12%, 20+ 4%)  comps 11.5 (air 7 + yac 5, 35+ 4%)  comp% 65  sack% 7`);
