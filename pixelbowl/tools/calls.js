"use strict";
const { loadGame } = require("/home/user/claude/pixelbowl/tools/harness.js");
const A = loadGame();
A.SCREEN = "game"; A.newGame("IRN", "SUN");
const st = A.G.st;
const rng = A.makeRNG(99);
const sit = (down, toGo) => {
  const counts = {};
  for (let i = 0; i < 400; i++) {
    st.down = down; st.toGo = toGo; st.los = 45; st.q = 1; st.clock = 180;
    st.tend = { run: 1, pass: 1 };
    const sc = A.callScheme(st, rng);
    counts[sc.name] = (counts[sc.name] || 0) + 1;
  }
  const top = Object.entries(counts).sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `${k} ${Math.round(v / 4)}%`).join("  ");
  console.log(`${down} & ${String(toGo).padEnd(2)} | ${top}`);
};
sit(1, 10); sit(2, 9); sit(2, 4); sit(3, 4); sit(3, 12); sit(4, 1); sit(1, 2);
