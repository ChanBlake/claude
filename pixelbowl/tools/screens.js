#!/usr/bin/env node
/* Shots of the season screens, which the drive-a-game script never reaches.
 *   node tools/screens.js [outdir] */
"use strict";
const fs = require("fs"), path = require("path"), { chromium } = require("playwright");
const ROOT = path.join(__dirname, ".."), OUT = process.argv[2] || "/tmp/screens";

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const epi = `globalThis.API = { get SCREEN(){return SCREEN}, set SCREEN(v){SCREEN=v},
    get LEAGUE(){return LEAGUE}, newSeasonLeague, runDraft, draw, present, update,
    get G(){return G}, newGame, saveLeague, startNextSeason, kickOffSeasonGame,
    buildOffseason, makeRNG };`;
  fs.writeFileSync("/tmp/pbscreens.html", html.replace(/\n<\/script>/, "\n" + epi + "\n</script>"));
  const browser = await chromium.launch({
    executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  const page = await (await browser.newContext({
    viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
  })).newPage();
  const logs = []; page.on("pageerror", e => logs.push("PAGEERROR: " + e.message));
  await page.goto("file:///tmp/pbscreens.html");
  await page.click("#start");
  await page.waitForTimeout(250);

  const shots = await page.evaluate(() => {
    const A = globalThis.API;
    const out = {};
    const grab = name => { A.draw(); A.present();
      out[name] = document.getElementById("screen").toDataURL("image/png"); };
    localStorage.clear();
    A.SCREEN = "title"; grab("1-title");
    A.SCREEN = "teams"; grab("2-teams");
    A.newSeasonLeague("IRN");
    A.SCREEN = "hub"; grab("3-hub");
    A.SCREEN = "roster"; grab("4-roster");
    A.SCREEN = "table"; grab("5-table");
    A.LEAGUE.phase = "offseason";
    A.LEAGUE.offseason = A.buildOffseason(A.makeRNG(7));
    A.runDraft();
    A.SCREEN = "offseason"; grab("6-offseason");
    A.SCREEN = "growth"; grab("7-growth");
    return out;
  });
  for (const [k, v] of Object.entries(shots))
    fs.writeFileSync(path.join(OUT, k + ".png"), Buffer.from(v.split(",")[1], "base64"));
  if (logs.length) console.log(logs.join("\n"));
  await browser.close();
  console.log("screens in " + OUT);
})();
