#!/usr/bin/env node
/*
 * Balance harness: plays whole games with a scripted competent player and
 * reports the numbers a person would actually feel — points, yards per play,
 * completion rate, turnovers. Per-play averages proved a bad proxy; a run that
 * averages 0.2 yards against one front and 18 against another still has to add
 * up to a sane game.
 *
 *   node tools/balance.js [engagedSpeed] [engageR]
 */
"use strict";
const { loadGame } = require("./harness.js");

function playGames(over, games = 14, diff = 1) {
  const A = loadGame();
  Object.assign(A.CFG, over);
  A.SETTINGS.diff = diff;
  const { FIELD, TEAMS, makeRNG } = A;
  const QLEN = +(process.env.QLEN || 180);
  const totals = { us: 0, them: 0, plays: 0, yards: 0, comp: 0, att: 0, to: 0, first: 0, td: 0, frames: 0, stuck: 0 };

  for (let g = 0; g < games; g++) {
    A.SCREEN = "game";
    const rng = makeRNG(5000 + g * 37);
    A.newGame(TEAMS[g % 8].ab, TEAMS[(g + 4) % 8].ab);
    const st = A.G.st;
    st.quarterLen = QLEN; st.clock = QLEN;
    let frames = 0;
    const H = 1 / 60;

    while (st.phase !== "final" && frames < 60 * 60 * 14) {
      A.draw();
      if (st.phase === "playcall") {
        // A competent caller: run on short yardage, throw on long.
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
          // Lead the receiver by the flight time — what the reticle teaches.
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
          // Thumb off the screen while the ball is up — a stale drag steers the
          // receiver away from it.
          A.Input.steerX = 0; A.Input.steerY = 0; A.Input.sprint = false;
        } else {
          const c = sim.P.find(p => p.hasBall);
          if (c) {
            // Steer toward the biggest gap ahead.
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
      A.update(H);
      frames++;
    }
    if (st.phase !== "final") totals.stuck++;
    totals.us += st.us; totals.them += st.them; totals.frames += frames;
    totals.plays += st.stats.us.plays; totals.yards += st.stats.us.yards;
    totals.comp += st.stats.us.comp; totals.att += st.stats.us.att;
    totals.to += st.stats.us.to; totals.first += st.stats.us.first; totals.td += st.stats.us.td;
  }
  const n = games;
  return {
    pts: (totals.us / n).toFixed(1), opp: (totals.them / n).toFixed(1),
    plays: (totals.plays / n).toFixed(1),
    ypp: (totals.yards / Math.max(1, totals.plays)).toFixed(1),
    firsts: (totals.first / n).toFixed(1),
    comp: totals.att ? Math.round(totals.comp / totals.att * 100) + "%" : "-",
    to: (totals.to / n).toFixed(1),
    mins: (totals.frames / n / 60 / 60).toFixed(1),
    stuck: totals.stuck,
  };
}

const grids = process.argv[2]
  ? [{ engagedSpeed: +process.argv[2], engageR: +(process.argv[3] || 1.1) }]
  : [{}];

console.log("diff | pts  opp | plays  ypp  1sts  comp   TO | mins stuck");
for (let d = 0; d < 3; d++) {
  const A0 = loadGame();
  const r = playGames(Object.assign({}, grids[0], { __diff: d }), 14, d);
  console.log(`  ${["ROOK","PRO ","ALL "][d]} | ${r.pts.padStart(4)} ${r.opp.padStart(4)} | ` +
    `${r.plays.padStart(5)} ${r.ypp.padStart(4)} ${r.firsts.padStart(5)} ${r.comp.padStart(5)} ${r.to.padStart(4)} | ${r.mins.padStart(4)} ${r.stuck}`);
}
