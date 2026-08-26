#!/usr/bin/env node
/* An incompletion, frame by frame: does the ball bounce and roll, and does
 * the man who reached for it look like he reached?  node tools/incomplete.js <out> */
"use strict";
const fs = require("fs"), path = require("path"), { chromium } = require("playwright");
const ROOT = path.join(__dirname, ".."), OUT = process.argv[2] || "/tmp/inc";
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const epi = `globalThis.API = { get G(){return G}, set SCREEN(v){SCREEN=v},
    newGame, giveUs, snapPlay, playById, update, draw, present,
    get Input(){return Input}, get FX(){return FX}, get FIELD(){return FIELD},
    get scrX(){return scrX}, get scrY(){return scrY}, get ARTW(){return ARTW},
    get ARTH(){return ARTH}, get UNIT(){return UNIT} };`;
  fs.writeFileSync("/tmp/pbinc.html", html.replace(/\n<\/script>/, "\n" + epi + "\n</script>"));
  const b = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"] });
  const page = await (await b.newContext({ viewport: { width: 844, height: 390 },
    deviceScaleFactor: 2, isMobile: true, hasTouch: true })).newPage();
  const errs = []; page.on("pageerror", e => errs.push("ERR " + e.message));
  await page.goto("file:///tmp/pbinc.html");
  await page.click("#start"); await page.waitForTimeout(250);
  const out = await page.evaluate(() => {
    const A = globalThis.API, shots = [], log = [];
    A.SCREEN = "game"; A.newGame("IRN", "SUN");
    A.G.st.quarterLen = 300; A.G.st.clock = 300;
    A.giveUs(40);
    A.snapPlay(A.playById("verts"));
    A.G.st.phase = "presnap";
    const H = 1 / 60;
    let thrown = false;
    for (let i = 0; i < 320; i++) {
      if (i === 4) A.Input.snap = true;
      const sim = A.G.play;
      if (!thrown && sim && sim.snapped && sim.qbHasIt() && sim.t > 1.3) {
        // At a patch of grass nobody is near, so it cannot be caught.
        A.Input.throwTo = { x: 27, y: A.G.st.los + 44 }; thrown = true;
      }
      A.update(H); A.draw(); A.present();
      const L = A.FX.loose;
      if (L) log.push(`${(i * H).toFixed(2)}s h=${L.h.toFixed(2)} spin=${L.spin.toFixed(1)}`);
      if (L && shots.length < 4 && log.length % 7 === 1) {
        const cv = document.getElementById("screen");
        const z = document.createElement("canvas"); z.width = 420; z.height = 300;
        const g = z.getContext("2d"); g.imageSmoothingEnabled = false;
        const u = A.UNIT;
        const cx = Math.max(0, Math.min(A.ARTW - 140, Math.round(A.scrX(L.y) - 70)));
        const cy = Math.max(0, Math.min(A.ARTH - 100, Math.round(A.scrY(L.x) - 50)));
        g.drawImage(cv, cx * u, cy * u, 140 * u, 100 * u, 0, 0, 420, 300);
        shots.push(z.toDataURL("image/png"));
      }
    }
    return { shots, log: log.slice(0, 14).join("\n"), result: A.G.st.lastKind || "" };
  });
  out.shots.forEach((d, i) =>
    fs.writeFileSync(path.join(OUT, "b" + i + ".png"), Buffer.from(d.split(",")[1], "base64")));
  console.log(out.log || "(no loose ball recorded)");
  if (errs.length) console.log(errs.join("\n"));
  await b.close(); console.log("\nframes in " + OUT);
})();
