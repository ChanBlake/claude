#!/usr/bin/env node
/*
 * Play a whole career headlessly — every game, every screen, every tap — and
 * report what a decade does to a roster. A season is the one part of this game
 * whose bugs only show up after an hour of play, which is exactly the kind of
 * bug a person should never be the one to find.
 *
 *   YEARS=12 node tools/career.js
 */
"use strict";
// Play a whole career headlessly: three seasons, every game, every screen tap.
const { loadGame } = require(require("path").join(__dirname, "harness.js"));
const A = loadGame();
const { FIELD, CFG, makeRNG } = A;
A.SETTINGS.diff = 1;

const rng = makeRNG(31337);
const tap = id => { A.Input.tap = id; };
const hot = id => A.HOT.find(b => b.id === id);
let frames = 0;
const H = 1 / 60;
const step = () => { A.draw(); A.update(H); frames++; };

// Start a career.
A.SCREEN = "title";
step();
tap("season"); step();
if (A.SCREEN !== "teams") throw new Error("expected team select, got " + A.SCREEN);
step();
tap("team:GLS"); step();
if (A.SCREEN !== "hub") throw new Error("expected hub, got " + A.SCREEN);

const before = A.LEAGUE.roster.off.map(p => ({ n: p.last, ovr: A.overallOf(p), age: p.age }));
console.log("YEAR 1 ROSTER");
before.forEach((p, i) => console.log(`   ${A.LEAGUE.roster.off[i].pos.padEnd(3)} ${p.n.padEnd(10)} age ${p.age}  ovr ${p.ovr}  ceil ${A.LEAGUE.roster.off[i].pot}`));

function playOneGame() {
  const st = A.G.st;
  st.quarterLen = 180; st.clock = 180;
  let n = 0;
  while (st.phase !== "final" && n < 60 * 60 * 8) {
    A.draw();
    if (st.phase === "playcall") {
      const opts = A.HOT.filter(b => b.id.startsWith("play:"));
      let p = rng.pick(opts);
      if (st.down === 4) { const pu = hot("punt"), fg = hot("fg");
        p = (FIELD.oppGoal - st.los) < 38 && fg ? fg : (pu || p); }
      if (p) tap(p.id);
    } else if (st.phase === "presnap") A.Input.snap = true;
    else if (st.phase === "try") tap("xp");
    else if (st.phase === "kick" && st.kick && !st.kick.flight) A.resolveKick(rng.range(-1.5, 1.5), rng.range(0.8, 1));
    else if (st.phase === "defense") tap("advance");
    else if (st.phase === "live" && A.G.play) {
      const sim = A.G.play;
      if (sim.qbHasIt() && !sim.threw && sim.t > (st.chosen.develop || 1)) {
        const tg = sim.targets();
        if (tg.length) {
          const qb = sim.P[0];
          let best = null, bs = -1e9;
          for (const r of tg) {
            const open = Math.min(...sim.P.filter(q => q.side === "def" && q.mot !== "down")
              .map(q => Math.hypot(q.x - r.x, q.y - r.y)));
            const sc = open * 1.6 + (r.y - st.los) * 0.3;
            if (sc > bs) { bs = sc; best = r; }
          }
          let f = 0;
          for (let k = 0; k < 3; k++)
            f = Math.hypot(best.x + best.vx * f - qb.x, best.y + best.vy * f - qb.y) / CFG.passSpeed;
          A.Input.throwTo = { x: best.x + best.vx * f, y: best.y + best.vy * f };
        }
      } else if (sim.ball.state === "air") { A.Input.steerX = 0; A.Input.steerY = 0; A.Input.sprint = false; }
      else { const c = sim.P.find(q => q.hasBall);
             if (c) { A.Input.steerX = 0; A.Input.steerY = 1; A.Input.sprint = true; } }
    }
    A.update(H); n++;
  }
  if (st.phase !== "final") throw new Error("game never finished");
}

for (let year = 1; year <= +(process.env.YEARS || 3); year++) {
  let guard = 0, record = "?", made = false;
  while (A.LEAGUE.phase !== "offseason" && guard++ < 40) {
    const c0 = A.LEAGUE.clubs[A.LEAGUE.my];
    if (A.LEAGUE.phase === "regular") {
      record = `${c0.w}-${c0.l}${c0.t ? "-" + c0.t : ""}`;
      made = A.standings().slice(0, 4).some(r => r.ab === A.LEAGUE.my);
    }
    step();
    if (A.SCREEN === "hub") {
      if (hot("kickoff")) { tap("kickoff"); step(); playOneGame(); step();
        // final screen -> growth -> hub
        tap("menu"); step();
        if (A.SCREEN !== "growth") throw new Error("expected growth, got " + A.SCREEN);
        step(); tap("hub"); step();
      } else if (hot("watch")) { tap("watch"); step(); }
      else if (hot("offseason")) {
              record = `${c.w}-${c.l}${c.t ? "-" + c.t : ""}`;
        made = A.standings().slice(0, 4).some(r => r.ab === A.LEAGUE.my);
        tap("offseason"); step(); break;
      }
    } else if (A.SCREEN === "offseason") break;
    else step();
  }
  // Off-season: look at the three prospects and take one.
  step();
  if (A.SCREEN !== "offseason") { tap("offseason"); step(); }
  const o = A.LEAGUE.offseason;
  console.log(`\nYEAR ${year}: ${record}${made ? " (playoffs)" : ""}  champion ${A.LEAGUE.champion}` +
    `  retired ${o.retired.length}  draft [${o.draft.map(p => p.pos + " " + A.overallOf(p) + "/" + p.pot).join(", ")}]`);
  const best = o.draft.map((p, i) => ({ i, v: p.pot })).sort((a, b) => b.v - a.v)[0];
  tap("draft:" + best.i); step();
  if (A.SCREEN !== "hub") throw new Error("draft did not return to the hub: " + A.SCREEN);
}

console.log("\nAFTER " + (process.env.YEARS || 3) + " SEASONS");
A.LEAGUE.roster.off.forEach(p => console.log(
  `   ${p.pos.padEnd(3)} ${p.last.padEnd(10)} age ${p.age}  ovr ${A.overallOf(p)}  ceil ${p.pot}  lvl ${p.lvl}`));
console.log(`   K   ${A.LEAGUE.roster.k.last.padEnd(10)} age ${A.LEAGUE.roster.k.age}  ovr ${A.overallOf(A.LEAGUE.roster.k)}`);
console.log(`   DEFENCE ${A.LEAGUE.def}   titles ${A.LEAGUE.title}   year now ${A.LEAGUE.year}`);
