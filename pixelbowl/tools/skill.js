#!/usr/bin/env node
/*
 * How good does a player have to be to run the score up? balance.js drives the
 * game with one fixed, fairly ordinary player, which tells you nothing about
 * the ceiling — and the ceiling is what someone who has played fifty games
 * actually experiences. This plays the same games at three levels of thumb.
 *
 *   node tools/skill.js [games] [path-to-index.html]
 */
"use strict";
const path = require("path");
const { loadGame } = require(path.join(__dirname, "harness.js"));

const GAMES = +(process.argv[2] || 10);
const FILE = process.argv[3] || null;
const QLEN = +(process.env.QLEN || 180);

// A player is three decisions: when to throw, who to throw to, and whether to
// go for it. LOOSE throws on rhythm at whoever scores best; GOOD waits for real
// separation; SHARP waits longer, refuses throws the distance fade would eat,
// and plays fourth down like someone who wants the win.
const LEVELS = {
  LOOSE: { sep: 0, hold: 0.0, maxAir: 99, go: 0.0 },
  GOOD:  { sep: 2.6, hold: 1.1, maxAir: 34, go: 0.5 },
  SHARP: { sep: 3.6, hold: 2.2, maxAir: 26, go: 0.85 },
  // The player who found something that works and stopped looking. If the
  // defence never answers this, the game has no ceiling at all.
  DIVER: { sep: 0, hold: 0.0, maxAir: 99, go: 0.9, spam: "play:dive" },
};

function playGames(levelName, diff, games) {
  const L = LEVELS[levelName];
  const A = loadGame(FILE ? { file: FILE } : {});
  A.SETTINGS.diff = diff;
  const { FIELD, TEAMS, makeRNG, CFG } = A;
  const tot = { us: 0, them: 0, plays: 0, yards: 0, comp: 0, att: 0, to: 0, first: 0, stuck: 0, margin: [] };

  for (let g = 0; g < games; g++) {
    A.SCREEN = "game";
    const rng = makeRNG(4100 + g * 53);
    A.newGame(TEAMS[g % 8].ab, TEAMS[(g + 4) % 8].ab);
    const st = A.G.st;
    st.quarterLen = QLEN; st.clock = QLEN;
    let frames = 0;
    const H = 1 / 60;

    while (st.phase !== "final" && frames < 60 * 60 * 14) {
      A.draw();
      if (st.phase === "playcall") {
        const opts = A.HOT.filter(b => b.id.startsWith("play:"));
        const toGoal = FIELD.oppGoal - st.los;
        let pick;
        if (st.down === 4) {
          const fg = A.HOT.find(b => b.id === "fg");
          const p = A.HOT.find(b => b.id === "punt");
          const spam = L.spam ? opts.find(o => o.id === L.spam) : null;
          const goForIt = st.toGo <= 2 ? rng.chance(0.4 + L.go * 0.6)
                        : st.toGo <= 5 && toGoal < 45 ? rng.chance(L.go * 0.5) : false;
          pick = goForIt ? (spam || bestFor(opts, st, rng))
                         : (fg && toGoal < 40 ? fg : (p || rng.pick(opts)));
        } else pick = L.spam ? (opts.find(o => o.id === L.spam) || bestFor(opts, st, rng))
                             : bestFor(opts, st, rng);
        if (pick) A.Input.tap = pick.id;
      } else if (st.phase === "presnap") A.Input.snap = true;
      else if (st.phase === "try") A.Input.tap = "xp";
      else if (st.phase === "kick" && st.kick && !st.kick.flight) {
        // A better player kicks straighter.
        const wob = levelName === "SHARP" ? 0.5 : levelName === "GOOD" ? 1.0 : 1.6;
        A.resolveKick(rng.range(-wob, wob), rng.range(0.75, 1));
      }
      else if (st.phase === "defense") A.Input.tap = "advance";
      else if (st.phase === "live" && A.G.play) drivePlay(A, st, L, CFG, FIELD, rng);
      A.update(H);
      frames++;
    }
    if (st.phase !== "final") tot.stuck++;
    tot.us += st.us; tot.them += st.them; tot.margin.push(st.us - st.them);
    tot.plays += st.stats.us.plays; tot.yards += st.stats.us.yards;
    tot.comp += st.stats.us.comp; tot.att += st.stats.us.att;
    tot.to += st.stats.us.to; tot.first += st.stats.us.first;
  }
  return tot;
}

function bestFor(opts, st, rng) {
  if (!opts.length) return null;
  const want = st.toGo <= 3 ? ["play:dive", "play:draw", "play:sweep", "play:slants"]
             : st.toGo <= 7 ? ["play:slants", "play:mesh", "play:out", "play:curls", "play:sweep"]
             : ["play:curls", "play:verts", "play:post", "play:flood", "play:out"];
  const hit = opts.filter(o => want.includes(o.id));
  return hit.length ? rng.pick(hit) : rng.pick(opts);
}

function drivePlay(A, st, L, CFG, FIELD, rng) {
  const sim = A.G.play;
  const live = sim.P.filter(p => p.side === "def" && p.mot !== "down");
  const sepOf = r => Math.min(...live.map(p => Math.hypot(p.x - r.x, p.y - r.y)));

  if (sim.qbHasIt() && !sim.threw) {
    const t = sim.t, dev = st.chosen.develop || 1;
    if (t < dev) return;
    const qb = sim.P[0];
    // Under real pressure you throw it anyway.
    const heat = Math.min(...live.map(p => Math.hypot(p.x - qb.x, p.y - qb.y)));
    const forced = heat < 3.0 || t > dev + L.hold + 1.6;
    let best = null, bestSep = -1;
    for (const r of sim.targets()) {
      const air = Math.hypot(r.x - qb.x, r.y - qb.y);
      if (!forced && air > L.maxAir) continue;
      const sep = sepOf(r) + (r.y - st.los) * 0.04;
      if (sep > bestSep) { bestSep = sep; best = r; }
    }
    if (!best) return;
    if (!forced && bestSep < L.sep && t < dev + L.hold) return;
    const flight = Math.hypot(best.x - qb.x, best.y - qb.y) / CFG.passSpeed;
    A.Input.throwTo = { x: best.x + best.vx * flight, y: best.y + best.vy * flight };
    return;
  }
  if (sim.ball.state === "air") { A.Input.steerX = 0; A.Input.steerY = 0; A.Input.sprint = false; return; }
  const c = sim.P.find(p => p.hasBall);
  if (!c) { A.Input.steerX = 0; A.Input.steerY = 0; A.Input.sprint = false; return; }
  // Steer toward the biggest gap ahead.
  let bx = 0, bs = -1e9;
  for (let dx = -1; dx <= 1; dx += 0.2) {
    const tx = c.x + dx * 4, ty = c.y + 3;
    const near = Math.min(...live.map(p => Math.hypot(p.x - tx, p.y - ty)));
    if (near > bs && tx > 2 && tx < FIELD.W - 2) { bs = near; bx = dx; }
  }
  A.Input.steerX = bx; A.Input.steerY = 1; A.Input.sprint = true;
  void rng;
}

console.log("player  diff  |  score      margin   plays  ypp  1sts  comp   TO");
const ONLY = (process.env.ONLY || "").split(",").filter(Boolean);
for (const lv of (ONLY.length ? ONLY : ["LOOSE", "GOOD", "SHARP", "DIVER"])) {
  for (let d = 0; d < 3; d++) {
    const t = playGames(lv, d, GAMES);
    const n = GAMES;
    const avgM = t.margin.reduce((a, b) => a + b, 0) / n;
    const blow = t.margin.filter(m => m >= 21).length;
    console.log(`${lv.padEnd(6)} ${["ROOK", "PRO ", "ALL "][d]}  | ` +
      `${(t.us / n).toFixed(1).padStart(5)}-${(t.them / n).toFixed(1).padEnd(5)} ` +
      `${(avgM > 0 ? "+" : "") + avgM.toFixed(1)}`.padStart(7) +
      `  (${blow}/${n} by 21+)  ${(t.plays / n).toFixed(0).padStart(3)} ` +
      `${(t.yards / Math.max(1, t.plays)).toFixed(1).padStart(5)} ${(t.first / n).toFixed(1).padStart(5)} ` +
      `${t.att ? Math.round(t.comp / t.att * 100) + "%" : "-"}`.padStart(5) +
      ` ${(t.to / n).toFixed(1)}`);
  }
}
