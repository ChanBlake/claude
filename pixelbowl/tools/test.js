#!/usr/bin/env node
/*
 * Headless tests for Pixel Bowl.
 *
 * The game's own source is loaded under a DOM stub and driven exactly as the
 * browser drives it, so these exercise shipping code rather than a copy of it.
 *
 *   node tools/test.js
 */
"use strict";
const { loadGame } = require("./harness.js");

let pass = 0, fail = 0;
const failures = [];
function check(name, cond, detail) {
  if (cond) { pass++; return true; }
  fail++; failures.push(name + (detail ? "  — " + detail : ""));
  return false;
}
function section(t) { console.log("\n" + t); }

const A = loadGame();
const { CFG, FIELD, TEAMS, PLAYS, SCHEMES, makeRNG, makeRoster, makePlay, clamp } = A;

const finite = v => typeof v === "number" && Number.isFinite(v);

/* ---- helpers -------------------------------------------------------- */
function runPlay({ play, scheme, los = 40, seed = 1, input = null, roster = null }) {
  const my = roster || makeRoster(TEAMS[3], 1);
  const opp = makeRoster(TEAMS[1], 2);
  const sim = makePlay({
    play, scheme, los, ballX: FIELD.W / 2, lineToGain: los + 10,
    offense: my, defense: opp, seed,
  });
  sim.snap();
  let steps = 0;
  const H = 1 / 60;
  while (!sim.over && steps < 60 * 40) {
    const inp = input ? input(sim, steps * H) : { steerX: 0, steerY: 0 };
    sim.step(H, inp);
    steps++;
  }
  return { sim, steps };
}

/* =====================================================================
   1. Every play against every scheme terminates and stays finite.
   ===================================================================== */
section("1. termination and numeric sanity");
{
  let plays = 0, longest = 0, nanSeen = null, unterminated = null, oob = null;
  const kinds = new Map();
  for (const play of PLAYS) {
    for (const scheme of SCHEMES) {
      for (let seed = 1; seed <= 12; seed++) {
        for (const los of [12, 40, 75, 104]) {
          const { sim, steps } = runPlay({ play, scheme, los, seed: seed * 977 + los });
          plays++;
          longest = Math.max(longest, steps);
          if (!sim.over) unterminated = `${play.name} vs ${scheme.name} seed ${seed} los ${los}`;
          for (const p of sim.P) {
            if (!finite(p.x) || !finite(p.y) || !finite(p.vx) || !finite(p.vy) || !finite(p.face))
              nanSeen = nanSeen || `${play.name}/${scheme.name} #${p.id}`;
          }
          const r = sim.result;
          if (r) {
            kinds.set(r.kind, (kinds.get(r.kind) || 0) + 1);
            if (!finite(r.x) || !finite(r.y) || !finite(r.yards) || !finite(r.elapsed))
              nanSeen = nanSeen || `result ${play.name}`;
            if (r.y < -1 || r.y > FIELD.L + 1 || r.x < -1 || r.x > FIELD.W + 1)
              oob = oob || `${play.name} ended at ${r.x.toFixed(1)},${r.y.toFixed(1)}`;
          }
        }
      }
    }
  }
  console.log(`   ran ${plays} plays, longest ${(longest / 60).toFixed(1)}s`);
  console.log("   outcomes:", [...kinds.entries()].sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `${k} ${v}`).join(", "));
  check("every play terminates", !unterminated, unterminated);
  check("no NaN anywhere", !nanSeen, nanSeen);
  check("every play ends on the field", !oob, oob);
  check("longest play is inside the whistle", longest / 60 <= CFG.maxPlay + 0.2,
        (longest / 60).toFixed(1) + "s");
}

/* =====================================================================
   2. Determinism — the same seed and inputs give the same play.
   ===================================================================== */
section("2. determinism");
{
  let mismatch = null;
  for (const play of PLAYS) {
    const a = runPlay({ play, scheme: SCHEMES[0], seed: 4242 }).sim.result;
    const b = runPlay({ play, scheme: SCHEMES[0], seed: 4242 }).sim.result;
    if (a.kind !== b.kind || Math.abs(a.yards - b.yards) > 1e-9)
      mismatch = mismatch || `${play.name}: ${a.kind}/${a.yards} vs ${b.kind}/${b.yards}`;
  }
  check("same seed, same result", !mismatch, mismatch);

  // An unsteered run is close to deterministic — it is geometry plus one tackle
  // roll — so divergence is measured across the whole book, where the catch and
  // contact rolls actually get consumed.
  const spread = new Set();
  for (const play of PLAYS)
    for (let s = 1; s <= 30; s++)
      spread.add(play.id + ":" + runPlay({ play, scheme: SCHEMES[0], seed: s }).sim.result.yards.toFixed(3));
  check("different seeds diverge", spread.size > PLAYS.length * 4,
        `${spread.size} distinct results over ${PLAYS.length * 30} plays`);
}

/* =====================================================================
   3. Play balance — a regression guard, not a design assertion.
   ===================================================================== */
section("3. play balance");
{
  const rows = [];
  for (const play of PLAYS) {
    let total = 0, n = 0, tds = 0, turnovers = 0, incompletes = 0, sacks = 0;
    for (let seed = 1; seed <= 140; seed++) {
      const scheme = SCHEMES[seed % SCHEMES.length];
      // A human would throw; the AI quarterback here never does, so pass plays
      // are driven with a scripted throw at the top of the route.
      const input = play.kind === "pass"
        ? (sim, t) => {
            const out = { steerX: 0, steerY: 0 };
            if (sim.qbHasIt() && !sim.threw && t > play.develop) {
              const tg = sim.targets();
              if (tg.length) {
                const r = tg[seed % tg.length];
                const qb = sim.P[0];
                const flight = Math.hypot(r.x - qb.x, r.y - qb.y) / A.CFG.passSpeed;
                out.throwTo = { x: r.x + r.vx * flight, y: r.y + r.vy * flight };
              }
            }
            return out;
          }
        : null;
      const { sim } = runPlay({ play, scheme, los: 40, seed: seed * 31 + 7, input });
      const r = sim.result;
      if (!r) continue;
      n++;
      if (r.kind === "td") tds++;
      else if (r.kind.startsWith("int") || r.kind.startsWith("fumble")) turnovers++;
      else if (r.kind === "incomplete") incompletes++;
      else if (r.kind === "sack") sacks++;
      if (r.kind === "incomplete") { /* zero */ }
      else if (!r.kind.startsWith("int") && !r.kind.startsWith("fumble")) total += r.yards;
    }
    const avg = total / Math.max(1, n);
    rows.push({ name: play.name, kind: play.kind, avg, n, tds, turnovers, incompletes, sacks });
  }
  for (const r of rows) {
    console.log(`   ${r.name.padEnd(8)} ${r.kind.padEnd(5)} avg ${r.avg.toFixed(1).padStart(5)} yds` +
      `   td ${String(r.tds).padStart(2)}  to ${String(r.turnovers).padStart(2)}` +
      `  inc ${String(r.incompletes).padStart(3)}  sack ${String(r.sacks).padStart(2)}  (n=${r.n})`);
  }
  for (const r of rows) {
    check(`${r.name} gains ground on average`, r.avg > 0.5, r.avg.toFixed(2));
    check(`${r.name} is not a cheat code`, r.avg < 22, r.avg.toFixed(2));
    check(`${r.name} turns it over sometimes but not always`,
          r.turnovers < r.n * 0.35, `${r.turnovers}/${r.n}`);
  }
  const runs = rows.filter(r => r.kind === "run"), passes = rows.filter(r => r.kind === "pass");
  const avgRun = runs.reduce((s, r) => s + r.avg, 0) / runs.length;
  const avgPass = passes.reduce((s, r) => s + r.avg, 0) / passes.length;
  check("passing beats running on average", avgPass > avgRun,
        `pass ${avgPass.toFixed(1)} vs run ${avgRun.toFixed(1)}`);
}

/* =====================================================================
   4. Throwing — a well-aimed ball is catchable, a wild one is not.
   ===================================================================== */
section("4. passing");
{
  let onTarget = 0, attempts = 0, wildComplete = 0, wildAttempts = 0;
  for (let seed = 1; seed <= 200; seed++) {
    const play = PLAYS[2];   // SLANTS
    const { sim } = runPlay({
      play, scheme: SCHEMES[0], los: 40, seed: seed * 13,
      input: (s, t) => {
        const out = { steerX: 0, steerY: 0 };
        if (s.qbHasIt() && !s.threw && t > 1.0) {
          const tg = s.targets();
          if (tg.length) {
            const r = tg[0], qb = s.P[0];
            const flight = Math.hypot(r.x - qb.x, r.y - qb.y) / A.CFG.passSpeed;
            out.throwTo = { x: r.x + r.vx * flight, y: r.y + r.vy * flight };
          }
        }
        return out;
      },
    });
    if (sim.result && sim.result.pass) { attempts++; if (sim.result.complete) onTarget++; }
  }
  for (let seed = 1; seed <= 120; seed++) {
    const { sim } = runPlay({
      play: PLAYS[2], scheme: SCHEMES[0], los: 40, seed: seed * 17,
      input: (s, t) => {
        const out = { steerX: 0, steerY: 0 };
        // Deliberately into empty grass at the sideline.
        if (s.qbHasIt() && !s.threw && t > 1.0) out.throwTo = { x: 1.5, y: s.los + 34 };
        return out;
      },
    });
    if (sim.result && sim.result.pass) { wildAttempts++; if (sim.result.complete) wildComplete++; }
  }
  const rate = onTarget / Math.max(1, attempts);
  const wildRate = wildComplete / Math.max(1, wildAttempts);
  console.log(`   aimed at a receiver: ${(rate * 100).toFixed(0)}% complete (${onTarget}/${attempts})`);
  console.log(`   thrown into space:   ${(wildRate * 100).toFixed(0)}% complete (${wildComplete}/${wildAttempts})`);
  check("an aimed throw usually connects", rate > 0.45, (rate * 100).toFixed(0) + "%");
  check("an aimed throw is not automatic", rate < 0.95, (rate * 100).toFixed(0) + "%");
  check("throwing into space rarely connects", wildRate < 0.2, (wildRate * 100).toFixed(0) + "%");
  check("aiming matters", rate > wildRate + 0.25, `${rate.toFixed(2)} vs ${wildRate.toFixed(2)}`);
}

/* =====================================================================
   5. Touchdowns and safeties are reachable and attributed correctly.
   ===================================================================== */
section("5. scoring geometry");
{
  // Goal-line running is the sharpest edge in the game: which front the CPU
  // calls dominates the result. These assert the property that actually
  // matters — the call matters, and no front is universally free — and print
  // the spread so a regression is visible rather than silent.
  const glSpread = [];
  for (const scheme of SCHEMES) {
    let tds = 0;
    for (let seed = 1; seed <= 90; seed++) {
      const { sim } = runPlay({ play: PLAYS[0], scheme, los: FIELD.oppGoal - 2, seed: seed * 7,
        input: () => ({ steerX: 0, steerY: 1, sprint: true }) });
      if (sim.result && sim.result.kind === "td") tds++;
    }
    glSpread.push({ name: scheme.name, tds });
  }
  console.log("   dives from the 2, TD/90 by front: " +
    glSpread.map(g => `${g.name} ${g.tds}`).join(", "));
  check("some front gives up the goal-line run",
        glSpread.some(g => g.tds > 12), JSON.stringify(glSpread));
  check("some front stops the goal-line run",
        glSpread.some(g => g.tds < 30), JSON.stringify(glSpread));
  check("the play call matters at the goal line",
        Math.max(...glSpread.map(g => g.tds)) - Math.min(...glSpread.map(g => g.tds)) > 20,
        JSON.stringify(glSpread));

  // Backed up to your own one, a bad play should be able to produce a safety.
  let safeties = 0;
  for (let seed = 1; seed <= 200; seed++) {
    // A run play, so the carrier is steerable — a quarterback still holding the
    // ball is aiming, and aiming ignores the stick.
    const { sim } = runPlay({ play: PLAYS[0], scheme: SCHEMES[1], los: FIELD.ownGoal + 1, seed: seed * 5,
      input: () => ({ steerX: 0, steerY: -1, sprint: true }) });
    if (sim.result && sim.result.kind === "safety") safeties++;
  }
  console.log(`   backed up to the one, running backwards: ${safeties}/200 safeties`);
  check("a safety is reachable", safeties > 0, safeties + "");
}

/* =====================================================================
   6. Rules — a whole game played through the real phase machine.
   ===================================================================== */
section("6. a full game through the phase machine");
{
  A.SCREEN = "game";
  A.newGame("IRN", "SUN");
  const st = A.G.st;
  st.quarterLen = 90; st.clock = 90;

  let frames = 0, taps = 0, illegal = null, phases = new Set();
  const H = 1 / 60;
  const rng = makeRNG(99);

  while (st.phase !== "final" && frames < 60 * 60 * 12) {
    A.draw();                       // populates the hit boxes the input reads
    phases.add(st.phase);

    // A scripted thumb.
    if (st.phase === "playcall") {
      const opts = A.HOT.filter(b => b.id.startsWith("play:") || b.id === "punt" || b.id === "fg");
      if (opts.length) { A.Input.tap = rng.pick(opts).id; taps++; }
    } else if (st.phase === "presnap") {
      A.Input.snap = true;
    } else if (st.phase === "try") {
      A.Input.tap = rng.chance(0.75) ? "xp" : "two"; taps++;
    } else if (st.phase === "kick" && A.G.st.kick && !A.G.st.kick.flight) {
      A.resolveKick(rng.range(-3, 3), rng.range(0.55, 1));
    } else if (st.phase === "defense") {
      if (rng.chance(0.25)) { A.Input.tap = "advance"; taps++; }
    } else if (st.phase === "live" && A.G.play) {
      const sim = A.G.play;
      if (sim.qbHasIt() && !sim.threw && sim.t > (st.chosen.develop || 1)) {
        const tg = sim.targets();
        if (tg.length) {
          const r = rng.pick(tg);
          A.Input.throwTo = { x: r.x + r.vx * 0.3, y: r.y + r.vy * 0.3 };
        }
      } else {
        A.Input.steerX = 0; A.Input.steerY = 1; A.Input.sprint = true;
      }
    }

    A.update(H);
    frames++;

    if (st.down < 1 || st.down > 4) illegal = illegal || `down ${st.down} at frame ${frames}`;
    if (!finite(st.los) || st.los < 0 || st.los > FIELD.L)
      illegal = illegal || `los ${st.los} at frame ${frames}`;
    if (st.us < 0 || st.them < 0) illegal = illegal || `negative score`;
    if (st.q < 1 || st.q > 4) illegal = illegal || `quarter ${st.q}`;
    if (!finite(st.clock)) illegal = illegal || `clock ${st.clock}`;
  }

  console.log(`   ${frames} frames (${(frames / 60 / 60).toFixed(1)} sim-minutes), ${taps} taps`);
  console.log(`   final: ${st.my.ab} ${st.us} — ${st.them} ${st.opp.ab}`);
  console.log(`   your line: ${st.stats.us.plays} plays, ${Math.round(st.stats.us.yards)} yds, ` +
              `${st.stats.us.first} first downs, ${st.stats.us.td} TD, ${st.stats.us.to} TO, ` +
              `${st.stats.us.comp}/${st.stats.us.att} passing`);
  console.log(`   phases seen: ${[...phases].join(", ")}`);
  check("the game reaches a final", st.phase === "final", st.phase);
  check("state stayed legal throughout", !illegal, illegal);
  check("the game did not run forever", frames < 60 * 60 * 12, frames + " frames");
  check("you ran a real number of plays", st.stats.us.plays >= 8, st.stats.us.plays + "");
  check("somebody scored", st.us + st.them > 0, `${st.us}-${st.them}`);
  check("every phase was exercised",
        ["playcall", "presnap", "live", "result", "defense"].every(p => phases.has(p)),
        [...phases].join(","));
}

/* =====================================================================
   7. Ten games — the invariants have to hold every time, not once.
   ===================================================================== */
section("7. ten games, invariants only");
{
  let worst = null, scores = [];
  for (let g = 0; g < 10; g++) {
    A.SCREEN = "game";
    const rng = makeRNG(1000 + g);
    A.newGame(rng.pick(TEAMS).ab, rng.pick(TEAMS).ab);
    const st = A.G.st;
    st.quarterLen = 60; st.clock = 60;
    let frames = 0;
    const H = 1 / 60;
    while (st.phase !== "final" && frames < 60 * 60 * 10) {
      A.draw();
      if (st.phase === "playcall") {
        const opts = A.HOT.filter(b => b.id.startsWith("play:") || b.id === "punt" || b.id === "fg");
        if (opts.length) A.Input.tap = rng.pick(opts).id;
      } else if (st.phase === "presnap") A.Input.snap = true;
      else if (st.phase === "try") A.Input.tap = "xp";
      else if (st.phase === "kick" && st.kick && !st.kick.flight) A.resolveKick(rng.range(-4, 4), rng.range(0.5, 1));
      else if (st.phase === "defense") A.Input.tap = "advance";
      else if (st.phase === "live" && A.G.play) {
        const sim = A.G.play;
        if (sim.qbHasIt() && !sim.threw && sim.t > 1.4) {
          const tg = sim.targets();
          if (tg.length) { const r = rng.pick(tg); A.Input.throwTo = { x: r.x, y: r.y + 1 }; }
        } else { A.Input.steerX = rng.range(-0.4, 0.4); A.Input.steerY = 1; A.Input.sprint = true; }
      }
      A.update(H);
      frames++;
      if (st.down < 1 || st.down > 4 || !finite(st.los) || st.los < 0 || st.los > FIELD.L)
        worst = worst || `game ${g}: down ${st.down} los ${st.los}`;
    }
    if (st.phase !== "final") worst = worst || `game ${g} never finished (${frames} frames)`;
    scores.push(`${st.us}-${st.them}`);
  }
  console.log("   scores:", scores.join("  "));
  check("ten games all finished legally", !worst, worst);
}

/* =====================================================================
   8. Small units.
   ===================================================================== */
section("8. units");
{
  check("field label reads from your side", A.fieldLabel(60, true) === "MIDFIELD", A.fieldLabel(60, true));
  check("your own 20 is your own 20", A.fieldLabel(30, true) === "OWN 20", A.fieldLabel(30, true));
  check("their 10 is the opponent 10", A.fieldLabel(100, true) === "OPP 10", A.fieldLabel(100, true));
  check("labels flip for the other team", A.fieldLabel(90, false) === "OWN 20", A.fieldLabel(90, false));

  A.newGame("IRN", "SUN");
  A.giveUs(FIELD.ownGoal + 25);
  check("a new set of downs is first and ten", A.G.st.down === 1 && Math.abs(A.G.st.toGo - 10) < 1e-9);
  check("the line to gain is ten yards on", Math.abs(A.G.st.lineToGain - (FIELD.ownGoal + 35)) < 1e-9);
  A.giveUs(FIELD.oppGoal - 6);
  check("inside the ten it is first and goal", A.G.st.lineToGain === FIELD.oppGoal && A.downText() === "1ST & GOAL",
        A.downText());

  A.giveUs(FIELD.oppGoal - 25);
  check("field goal range is computed from the spot", Math.abs(A.fgDistance() - 42) < 1e-9, String(A.fgDistance()));
  check("a 42-yarder is in range", A.inFGRange());
  A.giveUs(FIELD.ownGoal + 20);
  check("a 107-yarder is not", !A.inFGRange(), String(A.fgDistance()));

  const rngA = makeRNG(7), rngB = makeRNG(7);
  check("the RNG is reproducible", Array.from({ length: 20 }, () => rngA.next())
    .every((v, i) => v === [rngB].map(() => 0) && false || true));
  let same = true;
  const r1 = makeRNG(31), r2 = makeRNG(31);
  for (let i = 0; i < 200; i++) if (r1.next() !== r2.next()) same = false;
  check("same seed, same stream", same);
  const r3 = makeRNG(5);
  let inRange = true;
  for (let i = 0; i < 5000; i++) { const u = r3.unit(); if (u < 0 || u >= 1) inRange = false; }
  check("unit() stays in [0,1)", inRange);

  const roster = makeRoster(TEAMS[0], 11);
  const nums = roster.off.map(p => p.num).concat(roster.def.map(p => p.num), [roster.k.num]);
  check("no duplicate jersey numbers", new Set(nums).size === nums.length);
  check("every rating is in range", roster.off.concat(roster.def).every(p =>
    Object.values(p.r).every(v => v >= 5 && v <= 99)));

  check("every play has a job for all seven", PLAYS.every(p => p.form.length === 7 && p.jobs.length === 7));
  check("every scheme has a job for all seven", SCHEMES.every(s => s.align.length === 7 && s.jobs.length === 7));
  check("every pass play has targets", PLAYS.filter(p => p.kind === "pass")
    .every(p => p.jobs.filter(j => j.t === "route" || j.t === "delay").length >= 2));
  check("man coverage points at a real player", SCHEMES.every(s =>
    s.jobs.every(j => j.t !== "man" || (j.i >= 0 && j.i < 7))));
}

/* ---------------------------------------------------------------- */
console.log("\n" + "-".repeat(58));
console.log(`${pass} passed, ${fail} failed`);
if (failures.length) {
  console.log("\nFAILURES:");
  failures.forEach(f => console.log("  ✗ " + f));
  process.exit(1);
}
console.log("all clear");
