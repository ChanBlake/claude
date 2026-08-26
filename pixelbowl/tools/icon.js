#!/usr/bin/env node
/* The home-screen icon, drawn by the game itself so it cannot drift from it.
 *   node tools/icon.js */
"use strict";
const fs = require("fs"), path = require("path"), { chromium } = require("playwright");
const ROOT = path.join(__dirname, "..");

(async () => {
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const epi = `globalThis.API = { get ctx(){return ctx}, drawFigure, animateFigure, present,
     get COL(){return COL}, rect,
     set ART(v){ ARTW = v.w; ARTH = v.h; backCv.width=v.w; backCv.height=v.h;
                 UNIT = v.u; cv.width=v.w*v.u; cv.height=v.h*v.u;
                 ctx.imageSmoothingEnabled=false; } };`;
  fs.writeFileSync("/tmp/pbicon.html", html.replace(/\n<\/script>/, "\n" + epi + "\n</script>"));
  const browser = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  const page = await (await browser.newContext({ viewport: { width: 700, height: 700 } })).newPage();
  const logs = []; page.on("pageerror", e => logs.push("PAGEERROR: " + e.message));
  await page.goto("file:///tmp/pbicon.html");
  await page.click("#start");
  await page.waitForTimeout(200);

  for (const [size, unit] of [[192, 3], [512, 8], [1024, 16]]) {
    const png = await page.evaluate(({ unit }) => {
      const A = globalThis.API, ctx = A.ctx, COL = A.COL;
      A.ART = { w: 64, h: 64, u: unit };
      ctx.fillStyle = COL.turf; ctx.fillRect(0, 0, 64, 64);
      for (let i = 0; i < 5; i++) A.rect(0, i * 14, 64, 7, COL.mow);
      A.rect(0, 0, 64, 2, COL.night2); A.rect(0, 62, 64, 2, COL.night2);
      A.rect(12, 0, 1, 64, COL.chalk); A.rect(51, 0, 1, 64, COL.chalk);
      const team = { jersey: "#1B3A6B", pants: "#D8DEE6", helmet: "#14294C", trim: "#E8B33A" };
      const p = { pos: "RB", idx: 1, side: "off", id: 1, hit: null, _stride: 0, mot: "run" };
      for (let k = 0; k < 60; k++) A.animateFigure(p, "run", 1 / 60, { turnover: false, windup: -1 }, null);
      ctx.save();
      ctx.translate(32, 4); ctx.scale(2.3, 2.3); ctx.translate(-32, -4);
      A.drawFigure(p, team, "run", 32, 26, false, Math.PI * 0.75, true, 1);
      ctx.restore();
      A.present();
      return document.getElementById("screen").toDataURL("image/png");
    }, { unit });
    const out = path.join(ROOT, "icon-" + size + ".png");
    fs.writeFileSync(out, Buffer.from(png.split(",")[1], "base64"));
    console.log("wrote " + path.basename(out) + " (" + fs.statSync(out).size + " bytes)");
  }
  if (logs.length) console.log(logs.join("\n"));
  await browser.close();
})();
