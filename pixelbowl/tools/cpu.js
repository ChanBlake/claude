#!/usr/bin/env node
/*
 * The opponent's possession, sampled on its own. You never play defence, so
 * their drive is simulated — and points per drive is the whole difficulty
 * ladder in one number. Four hundred possessions run in about a second, which
 * makes this the right place to tune it rather than through whole games.
 *
 *   DIFF=0|1|2 node tools/cpu.js
 */
"use strict";
const { loadGame } = require(require("path").join(__dirname, "harness.js"));
const A = loadGame(process.argv[2] ? { file: process.argv[2] } : {});
const { FIELD, makeRNG } = A;
A.SETTINGS.diff = +(process.env.DIFF || 1);

// Simulate their possession over and over and score it, without the cost of
// playing whole games. Points per drive is the number that matters: with about
// seven or eight possessions a side, a real team averages roughly 0.3 TDs and
// 0.2 field goals a drive — call it 2.6 points.
for (const [mine, theirs] of [["GLS", "SUN"], ["IRN", "SUN"], ["DST", "GLS"], ["IRN", "IRN"]]) {
  A.SCREEN = "game";
  A.newGame(mine, theirs);
  A.setRNG(makeRNG(4242));
  const st = A.G.st;
  const tally = {}; let pts = 0, plays = 0, n = 400;
  for (let i = 0; i < n; i++) {
    st.us = 0; st.them = 0;
    A.startTheirDrive(FIELD.oppGoal - 25);
    const d = st.drive;
    tally[d.result] = (tally[d.result] || 0) + 1;
    plays += d.events.filter(e => e.kind === "play").length;
    pts += d.result === "td" ? 7 : d.result === "fg" ? 3 : 0;
    st.drive = null;
  }
  console.log(`${mine} (str ${st.my.str}) vs ${theirs} (str ${st.opp.str}): ` +
    `${(pts / n).toFixed(2)} pts a drive, ${(plays / n).toFixed(1)} plays  ` +
    Object.entries(tally).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${(v / n * 100).toFixed(0)}%`).join("  "));
}
