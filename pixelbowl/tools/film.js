#!/usr/bin/env node
/*
 * Films a run play in a real Chromium and lays the frames out as a
 * contact sheet, so an animation can be looked at rather than reasoned
 * about. Nothing else in the toolchain can see a tackle.
 *
 *   node tools/film.js [outdir] [play] [frames] [everyN]
 */
"use strict";
const fs = require("fs"), path = require("path"), { chromium } = require("playwright");
const ROOT = path.join(__dirname, "..");
const OUT = process.argv[2] || "/tmp/film";
const PLAY = process.argv[3] || "dive";
const NFRAMES = +(process.argv[4] || 26);
const EVERY = +(process.argv[5] || 4);

function buildTestPage() {
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const epilogue = `
    globalThis.API = {
      get ARTW(){return ARTW}, get ARTH(){return ARTH}, get UNIT(){return UNIT},
      get G(){return G}, get Input(){return Input}, get SCREEN(){return SCREEN},
      set SCREEN(v){SCREEN=v},
      newGame, snapPlay, playById, giveUs, update, draw, present,
      get scrX(){return scrX}, get scrY(){return scrY},
      set frozen(v){ FROZEN = v; },
    };
    let FROZEN = false;
    // Take the render loop off the wall clock so frames can be stepped.
    frame = function(){};`;
  const out = html.replace(/\n<\/script>/, "\n" + epilogue + "\n</script>");
  const file = "/tmp/pbfilm.html";
  fs.writeFileSync(file, out);
  return "file://" + file;
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  const ctx = await browser.newContext({
    viewport: { width: 844, height: 390 }, deviceScaleFactor: 2,
    isMobile: true, hasTouch: true,
  });
  const page = await ctx.newPage();
  const logs = [];
  page.on("pageerror", e => logs.push("PAGEERROR: " + e.message));
  await page.goto(buildTestPage());
  await page.click("#start");
  await page.waitForTimeout(300);

  const shots = await page.evaluate(async ({ PLAY, NFRAMES, EVERY }) => {
    const A = globalThis.API;
    A.SCREEN = "game";
    A.newGame("IRN", "SUN");
    A.G.st.quarterLen = 300; A.G.st.clock = 300;
    A.giveUs(30);
    A.snapPlay(A.playById(PLAY));
    A.G.st.phase = "presnap";
    const H = 1 / 60;
    const out = [];
    // Steer straight downfield so the run meets a defender.
    let thrown = false;
    for (let i = 0; i < NFRAMES * EVERY; i++) {
      if (i === EVERY) A.Input.snap = true;
      A.Input.steerY = 1; A.Input.steerX = 0; A.Input.sprint = true;
      const sim0 = A.G.play;
      if (!thrown && sim0 && sim0.snapped && sim0.qbHasIt() && sim0.t > 1.2) {
        const t = sim0.targets()[0];
        if (t) { A.Input.throwTo = { x: t.x, y: t.y + 3 }; thrown = true; }
      }
      A.update(H);
      A.draw(); A.present();
      if (i % EVERY === 0) {
        const st = A.G.st.phase;
        const sim = A.G.play;
        const cv = document.getElementById("screen");
        // A crop around the ball, blown up, so a tackle can actually be seen.
        const z = document.createElement("canvas");
        const CW = 150, CH = 110, ZOOM = 3;
        z.width = CW * ZOOM; z.height = CH * ZOOM;
        const g = z.getContext("2d");
        g.imageSmoothingEnabled = false;
        const u = A.UNIT;
        const b = sim ? sim.ball : { x: 26, y: A.G.st.los };
        const cx0 = Math.max(0, Math.min(A.ARTW - CW, Math.round(A.scrX(b.y) - CW / 2)));
        const cy0 = Math.max(0, Math.min(A.ARTH - CH, Math.round(A.scrY(b.x) - CH / 2)));
        g.drawImage(cv, cx0 * u, cy0 * u, CW * u, CH * u, 0, 0, z.width, z.height);
        out.push({
          png: cv.toDataURL("image/png"),
          zoom: z.toDataURL("image/png"),
          label: `${(i * H).toFixed(2)}s ${st}` + (sim && sim.over ? " OVER" : ""),
          speeds: sim ? sim.P.map(p => Math.round(Math.hypot(p.vx, p.vy) * 10) / 10) : [],
        });
      }
    }
    return out;
  }, { PLAY, NFRAMES, EVERY });

  shots.forEach((s, i) => {
    fs.writeFileSync(path.join(OUT, String(i).padStart(2, "0") + ".png"),
                     Buffer.from(s.png.split(",")[1], "base64"));
    fs.writeFileSync(path.join(OUT, "z" + String(i).padStart(2, "0") + ".png"),
                     Buffer.from(s.zoom.split(",")[1], "base64"));
  });
  console.log(shots.map((s, i) => `${String(i).padStart(2)}  ${s.label}  moving=${s.speeds.filter(v => v > 0.4).length}/${s.speeds.length}`).join("\n"));
  if (logs.length) console.log("\n" + logs.join("\n"));
  await browser.close();
  console.log("\nframes in " + OUT);
})();
