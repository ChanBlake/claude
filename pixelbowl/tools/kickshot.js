#!/usr/bin/env node
/* The two stages of a kick, side by side. node tools/kickshot.js <outdir> */
"use strict";
const fs = require("fs"), path = require("path"), { chromium } = require("playwright");
const ROOT = path.join(__dirname, ".."), OUT = process.argv[2] || "/tmp/kick";
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const epi = `globalThis.API = { get G(){return G}, get SCREEN(){return SCREEN},
    set SCREEN(v){SCREEN=v}, newGame, giveUs, beginKick, update, draw, present,
    get FIELD(){return FIELD} };`;
  fs.writeFileSync("/tmp/pbkick.html", html.replace(/\n<\/script>/, "\n" + epi + "\n</script>"));
  const b = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"] });
  const page = await (await b.newContext({ viewport: { width: 844, height: 390 },
    deviceScaleFactor: 3, isMobile: true, hasTouch: true })).newPage();
  const errs = []; page.on("pageerror", e => errs.push("ERR " + e.message));
  await page.goto("file:///tmp/pbkick.html");
  await page.click("#start"); await page.waitForTimeout(250);
  const shots = await page.evaluate(() => {
    const A = globalThis.API, out = {};
    const grab = n => { A.draw(); A.present();
      out[n] = document.getElementById("screen").toDataURL("image/png"); };
    A.SCREEN = "game"; A.newGame("IRN", "SUN");
    A.G.st.quarterLen = 300; A.G.st.clock = 300;
    A.giveUs(A.FIELD.oppGoal - 24);
    A.beginKick("fg");
    const k = A.G.st.kick;
    for (let i = 0; i < 44; i++) A.update(1 / 60);
    grab("1-power");
    k.stage = "aim"; k.aimT = 0;
    for (let i = 0; i < 26; i++) A.update(1 / 60);
    grab("2-aim-early");
    for (let i = 0; i < 60; i++) A.update(1 / 60);
    grab("3-aim-late");
    return out;
  });
  for (const [n, v] of Object.entries(shots))
    fs.writeFileSync(path.join(OUT, n + ".png"), Buffer.from(v.split(",")[1], "base64"));
  if (errs.length) console.log(errs.join("\n"));
  await b.close(); console.log("kick shots in " + OUT);
})();
