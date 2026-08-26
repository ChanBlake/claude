"use strict";
const fs=require("fs"),{chromium}=require("playwright");
const ROOT="/home/user/claude/pixelbowl";
const html=fs.readFileSync(ROOT+"/index.html","utf8");
const epi=`globalThis.API={get ARTW(){return ARTW},get ARTH(){return ARTH},get UNIT(){return UNIT},
  get NEEDS_ROTATE(){return NEEDS_ROTATE},draw,present};`;
fs.writeFileSync("/tmp/pbrot.html",html.replace(/\n<\/script>/,"\n"+epi+"\n</script>"));
(async()=>{
  const b=await chromium.launch({executablePath:"/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    args:["--no-sandbox","--disable-dev-shm-usage"]});
  const p=await (await b.newContext({viewport:{width:390,height:844},deviceScaleFactor:3,
    isMobile:true,hasTouch:true})).newPage();
  const logs=[];p.on("pageerror",e=>logs.push("ERR "+e.message));
  await p.goto("file:///tmp/pbrot.html");
  await p.click("#start"); await p.waitForTimeout(300);
  const info=await p.evaluate(()=>{const A=globalThis.API;A.draw();A.present();
    return {ARTW:A.ARTW,ARTH:A.ARTH,UNIT:A.UNIT,rot:A.NEEDS_ROTATE};});
  console.log(JSON.stringify(info));
  await p.screenshot({path:process.argv[2]});
  if(logs.length)console.log(logs.join("\n"));
  await b.close();
})();
