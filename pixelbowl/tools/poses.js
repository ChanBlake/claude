#!/usr/bin/env node
/* A sheet of every figure pose at every build, blown up, so the art can be
 * looked at instead of imagined.  node tools/poses.js [out.png] */
"use strict";
const fs = require("fs"), path = require("path"), { chromium } = require("playwright");
const ROOT = path.join(__dirname, "..");
const OUT = process.argv[2] || "/tmp/poses.png";

(async () => {
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const epi = `globalThis.API = { get ctx(){return ctx}, get BUILD(){return BUILD},
     drawFigure, animateFigure, get COL(){return COL}, present,
     get backCv(){return backCv}, resize, text,
     set ART(v){ ARTW = v.w; ARTH = v.h; backCv.width=v.w; backCv.height=v.h;
                 UNIT = v.u; cv.width=v.w*v.u; cv.height=v.h*v.u;
                 cv.style.width=(v.w*v.u)+'px'; cv.style.height=(v.h*v.u)+'px';
                 ctx.imageSmoothingEnabled=false; } };`;
  fs.writeFileSync("/tmp/pbposes.html", html.replace(/\n<\/script>/, "\n" + epi + "\n</script>"));
  const browser = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  const page = await (await browser.newContext({ viewport: { width: 1200, height: 700 } })).newPage();
  const logs = []; page.on("pageerror", e => logs.push("PAGEERROR: " + e.message));
  await page.goto("file:///tmp/pbposes.html");
  await page.click("#start");
  await page.waitForTimeout(200);

  const png = await page.evaluate(() => {
    const A = globalThis.API, ctx = A.ctx;
    const POSES = ["stand", "run", "run2", "tackle", "block", "catch", "stumble", "down", "throwIt", "release"];
    const BUILDS = ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB"];
    const CELLW = 34, CELLH = 40, PAD = 26;
    A.ART = { w: PAD + POSES.length * CELLW, h: 14 + BUILDS.length * CELLH, u: 4 };
    ctx.fillStyle = "#2E6B3A"; ctx.fillRect(0, 0, 9999, 9999);
    const team = { jersey: "#D9532B", pants: "#22303C", helmet: "#E8E2D6", trim: "#173049" };
    POSES.forEach((pose, i) => A.text(pose.toUpperCase(), PAD + i * CELLW + CELLW / 2, 3, { scale: 1 }));
    BUILDS.forEach((pos, r) => {
      A.text(pos, 2, 14 + r * CELLH + CELLH / 2, { align: -1 });
      POSES.forEach((pose, i) => {
        const real = pose === "run2" ? "run" : pose;
        const p = { pos, idx: 3, side: "off", id: r * 20 + i, hit: real === "down" ? { x: 0, y: 1, deep: 1 } : null,
                    _stride: 0, mot: real === "down" ? "down" : "run" };
        // Settle the eased state on the pose rather than showing frame one.
        for (let k = 0; k < 90; k++) A.animateFigure(p, real, 1 / 60, { turnover: false, windup: -1 }, null);
        const phase = pose === "run2" ? Math.PI : Math.PI / 2;
        A.drawFigure(p, team, real, PAD + i * CELLW + CELLW / 2, 14 + r * CELLH + CELLH - 6,
                     false, phase, pose === "run" || pose === "stand", 1);
      });
    });
    A.present();
    return document.getElementById("screen").toDataURL("image/png");
  });
  fs.writeFileSync(OUT, Buffer.from(png.split(",")[1], "base64"));
  if (logs.length) console.log(logs.join("\n"));
  await browser.close();
  console.log("wrote " + OUT);
})();
