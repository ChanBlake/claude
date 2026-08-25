#!/usr/bin/env node
/*
 * Renders the game in a real Chromium at an iPhone viewport and drives it
 * through a drive, saving screenshots. The Node test harness stubs every
 * drawing call to a no-op, so this is the only thing that proves the game
 * actually looks like anything.
 *
 *   node tools/shots.js [outdir]
 */
"use strict";
const fs = require("fs"), path = require("path"), { chromium } = require("playwright");

const ROOT = path.join(__dirname, "..");
const OUT = process.argv[2] || "/tmp/shots";

// The page's own symbols are script-scoped, so a test copy gets an epilogue
// that hands the driver the hit boxes and the art-pixel dimensions.
function buildTestPage() {
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const epilogue = `
    globalThis.API = {
      get ARTW(){return ARTW}, get ARTH(){return ARTH}, get UNIT(){return UNIT},
      get HOT(){return HOT}, get SCREEN(){return SCREEN}, set SCREEN(v){SCREEN=v},
      get G(){return G}, get Input(){return Input}, get PLAYS(){return PLAYS},
      get FIELD(){return FIELD},
    };`;
  const out = html.replace(/\n<\/script>/, "\n" + epilogue + "\n</script>");
  const file = "/tmp/pbtest.html";
  fs.writeFileSync(file, out);
  return "file://" + file;
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  // The container ships a Chromium that predates the npm package's pinned
  // build, so launch the one that is actually here rather than downloading.
  const browser = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  const ctx = await browser.newContext({
    viewport: { width: 844, height: 390 },
    deviceScaleFactor: 3,
    isMobile: true,
    hasTouch: true,
  });
  const page = await ctx.newPage();
  const logs = [];
  page.on("console", m => logs.push(m.type() + ": " + m.text()));
  page.on("pageerror", e => logs.push("PAGEERROR: " + e.message));

  await page.goto(buildTestPage());
  await page.waitForTimeout(400);
  const shot = async name => {
    await page.screenshot({ path: path.join(OUT, name + ".png") });
    return name;
  };

  // Art-space point → page CSS point.
  async function artPoint(ax, ay) {
    return page.evaluate(([ax, ay]) => {
      const c = document.getElementById("screen");
      const r = c.getBoundingClientRect();
      return { x: r.left + (ax / API.ARTW) * r.width, y: r.top + (ay / API.ARTH) * r.height };
    }, [ax, ay]);
  }
  async function tapArt(ax, ay) {
    const p = await artPoint(ax, ay);
    await page.mouse.click(p.x, p.y);
    await page.waitForTimeout(260);
  }
  async function tapId(id) {
    const box = await page.evaluate(i => {
      const b = API.HOT.find(h => h.id === i);
      return b ? { x: b.x + b.w / 2, y: b.y + b.h / 2 } : null;
    }, id);
    if (!box) throw new Error("no hit box: " + id + "  (have: " +
      (await page.evaluate(() => API.HOT.map(h => h.id).join(","))) + ")");
    await tapArt(box.x, box.y);
    return true;
  }

  await shot("01-boot");
  await page.click("#start");
  await page.waitForTimeout(600);
  await shot("02-title");

  await tapId("start");
  await shot("03-teams");
  await tapId("team:IRN");
  await shot("04-opponent");
  await tapId("team:SUN");
  await page.waitForTimeout(1800);          // the opening banner
  await shot("05-first-look");

  // Capture the opponent's drive ticker and a result banner if they come up.
  for (let i = 0; i < 40; i++) {
    const phase = await page.evaluate(() => API.G.st && API.G.st.phase);
    if (phase === "defense") { await shot("05b-defense"); break; }
    if (phase === "playcall") break;
    await page.waitForTimeout(200);
  }

  // Get to a play call, whichever side has the ball.
  for (let i = 0; i < 60; i++) {
    const phase = await page.evaluate(() => API.G.st && API.G.st.phase);
    if (phase === "playcall") break;
    if (phase === "defense") { try { await tapId("advance"); } catch (e) { /* between events */ } }
    await page.waitForTimeout(220);
  }
  await shot("06-playcall");

  {
    const a = await artPoint(250, 200), b = await artPoint(150, 200);
    await page.mouse.move(a.x, a.y); await page.mouse.down();
    await page.mouse.move(b.x, b.y, { steps: 8 }); await page.mouse.up();
    await page.waitForTimeout(250);
    await shot("06b-playcall-page2");
    const c = await artPoint(150, 200), d2 = await artPoint(250, 200);
    await page.mouse.move(c.x, c.y); await page.mouse.down();
    await page.mouse.move(d2.x, d2.y, { steps: 8 }); await page.mouse.up();
    await page.waitForTimeout(250);
  }
  await tapId("play:verts");
  await page.waitForTimeout(300);
  await shot("07-presnap");

  await tapArt(140, 150);                    // snap
  await page.waitForTimeout(900);
  await shot("08-live");

  // Drag to aim: press low, drag up, hold — then screenshot the crosshair.
  const from = await artPoint(320, 190);
  const to = await artPoint(150, 120);
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(to.x, to.y, { steps: 12 });
  await page.waitForTimeout(160);
  await shot("09-aiming");
  await page.mouse.up();
  await page.waitForTimeout(700);
  await shot("10-ball-in-air");
  await page.waitForTimeout(300);
  await shot("10b-banner");
  await page.waitForTimeout(1600);
  await shot("11-after-play");

  // Fourth down, to see the kick meter.
  await page.evaluate(() => {
    const s = API.G.st;
    s.down = 4; s.toGo = 6; s.los = 88; s.lineToGain = 94;
    s.phase = "playcall"; API.G.play = null;
  });
  await page.waitForTimeout(200);
  await shot("12-fourth-down");
  try {
    await tapId("fg"); await page.waitForTimeout(300); await shot("13-kick-meter");
    const kf = await artPoint(200, 120), kt = await artPoint(250, 112);
    await page.mouse.move(kf.x, kf.y); await page.mouse.down();
    await page.mouse.move(kt.x, kt.y, { steps: 10 });
    await page.waitForTimeout(150); await shot("14-kick-charging");
    await page.mouse.up(); await page.waitForTimeout(1000); await shot("15-kick-flight");
  } catch (e) { logs.push("fg: " + e.message); }

  const diag = await page.evaluate(() => ({
    ARTW: API.ARTW, ARTH: API.ARTH, UNIT: API.UNIT,
    canvas: (() => { const c = document.getElementById("screen");
      return { w: c.width, h: c.height, css: c.style.width + " x " + c.style.height }; })(),
    phase: API.G.st && API.G.st.phase,
  }));
  console.log(JSON.stringify(diag, null, 2));
  if (logs.length) { console.log("\nconsole:"); logs.slice(0, 25).forEach(l => console.log("  " + l)); }
  await browser.close();
  console.log("\nshots in " + OUT);
})();
