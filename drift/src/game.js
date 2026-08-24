/* DRIFT — engine. Physics, rendering, UI and input.
   Sector data lives in levels.js; tuning in config.js. Nothing here hardcodes
   a number the verifier also depends on — those all come from config. */

import {TILE,VCOLS,VROWS,W,H,GRAV,MAXFALL,RUN,ACC,FRIC,JUMP,BURST_SCALE,CUT,
        ZG_THRUST,ZG_DRAG,ZG_MAX,BASE_BUFFER,REWIND_SPEED,COYOTE,JBUF,FUSE,
        ASSIST_BUFFER,CAM_DEADZONE_X,CAM_DEADZONE_Y,CAM_LERP,CAM_LOOKAHEAD} from "./config.js";
import {ZONES,zoneOf,LEVELS} from "./levels.js";
import {themeFor} from "./themes.js";
import {save,saveNow,loadSave,wipe,clearedSet,coreSet,backendLabel} from "./save.js";
import {S,setDrone,setPaused} from "./audio.js";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* How many cores each sector actually holds, and how many exist in total.
   The progress readouts used to divide by LEVELS.length, which counted *sectors
   fully looted* while calling them cores — with Zone V holding one core a sector
   and everywhere else holding two, that read 30 when the real number is 54. */
const CORES_IN  = LEVELS.map(L => L.rows.reduce((k,r)=>k+(r.split("o").length-1), 0));
const CORES_ALL = CORES_IN.reduce((a,b)=>a+b, 0);
/* A sector only enters save.cores when every core in it is recovered, so summing
   its capacity over that set is an exact count, not an estimate. */
const coresFound = () => [...coreSet()].reduce((k,i)=>k+(CORES_IN[i]||0), 0);
const zoneRange = zi => [ZONES[zi].at, zi+1<ZONES.length ? ZONES[zi+1].at : LEVELS.length];

export function boot(){
  /* ══════════════ STATE ══════════════ */
  const cv=document.getElementById("cv"), ctx=cv.getContext("2d");
  let grid=[], lvl=0, deaths=0, runDeaths=0, runStart=0, lvlStart=0, lvlMs=0;
  let player=null, exitPt=null, switches=[], plates=[], crates=[], plats=[], cores=[], toggles=[];
  let fuses=new Map(), phase=0, tCool=0;
  let history=[], rewinding=false, dead=0, won=0, paused=true, shake=0, tick=0, parts=[];
  let kit={burst:1,flip:1,rewind:1}, denyT=0, denyKey="", idleT=0, gotCore=false, runMode=false;
  let coresGot=0, coresTotal=0;
  let projectors=[], phantom=null;      // phantom replays YOUR last 12s from the rewind buffer
  let TH=themeFor(0);            // active zone theme — presentation only

  /* ── playtest telemetry ──────────────────────────────────────────
     The verifier proves a sector is solvable. It cannot tell you a stage earns
     its length, or that people quit at 17. This records the handful of things
     that answer those questions: where you die, how long each sector takes,
     where you stall, and which cores nobody ever finds. Local only. */
  const tele = save.tele || (save.tele = {deaths:[], clears:[], stalls:[]});
  function record(list, row){
    list.push(row);
    if(list.length > 4000) list.splice(0, list.length - 4000);
  }
  let COLS=VCOLS, ROWS=VROWS, LW=W, LH=H;              // level grid size in tiles / pixels
  let cam={x:0,y:0,tx:0,ty:0};                          // view origin, pixels
  const BUFFER=()=> save.assist? BASE_BUFFER*ASSIST_BUFFER : BASE_BUFFER;

  const keys=Object.create(null);
  const K={left:["KeyA","ArrowLeft","tL","gL"],right:["KeyD","ArrowRight","tR","gR"],
           up:["KeyW","ArrowUp","gU"],down:["KeyS","ArrowDown","tD","gD"]};
  const held=s=>s.some(k=>keys[k]);
  let stars=[];
  function seedStars(n,count){
    let s=n*9301+49297; const rnd=()=>((s=(s*9301+49297)%233280)/233280);
    stars=[]; const N=count||80;
    for(let i=0;i<N;i++) stars.push({x:rnd()*W,y:rnd()*H,r:rnd()*1.4+.25,a:rnd()*.5+.12,sp:rnd()*.2+.03});
  }

  /* ══════════════ LOAD ══════════════ */
  function loadLevel(i){
    lvl=i; const L=LEVELS[i], k=L.kit||"";
    kit={burst:k.includes("B"),flip:k.includes("F"),rewind:k.includes("R")};
    grid=L.rows.map(r=>r.split(""));
    ROWS=grid.length; COLS=grid[0].length; LW=COLS*TILE; LH=ROWS*TILE;
    switches=[];plates=[];crates=[];plats=[];cores=[];toggles=[];projectors=[];phantom=null;exitPt=null;
    fuses=new Map();parts=[];phase=0;tCool=0;
    player={x:32,y:32,w:20,h:26,vx:0,vy:0,gd:1,onGround:false,wasGround:false,airJump:true,
            coyote:0,jbuf:0,face:1,zg:false,thrust:0};
    for(let r=0;r<ROWS;r++)for(let c=0;c<COLS;c++){
      const ch=grid[r][c], px=c*TILE, py=r*TILE;
      if(ch==="P"){player.x=px+(TILE-player.w)/2;player.y=py+TILE-player.h;grid[r][c]=".";}
      else if(ch==="E"){exitPt={x:px,y:py};grid[r][c]=".";}
      else if(ch==="S"){switches.push({x:px,y:py,latched:false,pop:0});grid[r][c]=".";}
      else if(ch==="B"){plates.push({x:px,y:py,on:false,was:false});grid[r][c]=".";}
      else if(ch==="T"){toggles.push({x:px,y:py,pop:0});grid[r][c]=".";}
      else if(ch==="X"){projectors.push({x:px,y:py,used:false,pop:0});grid[r][c]=".";}
      else if(ch==="o"){cores.push({x:px+8,y:py+8,w:16,h:16,got:false});grid[r][c]=".";}
      else if(ch==="C"||ch==="A"){crates.push({x:px+3,y:py+3,w:26,h:26,vy:0,anchored:ch==="A"});grid[r][c]=".";}
    }
    (L.mp||[]).forEach(m=>{
      const dist=m.dist*TILE;
      plats.push({x0:m.c*TILE,y0:m.r*TILE,x:m.c*TILE,y:m.r*TILE,w:m.w*TILE,h:TILE,
                  axis:m.axis,dist,speed:m.speed,p:(m.phase||0)*dist,dir:1});
    });
    plats.forEach(p=>{ if(p.axis==="x") p.x=p.x0+p.p; else p.y=p.y0+p.p; });
    history=[];rewinding=false;dead=0;won=0;deaths=0;shake=0;idleT=0;denyT=0;
    cam.x=cam.tx=clampCamX(player.x-W/2); cam.y=cam.ty=clampCamY(player.y-H/2);
    gotCore=false; coresGot=0; coresTotal=cores.length; lvlStart=performance.now(); lvlMs=0;
    /* Loading a sector from a menu means the pause is already running; re-anchor
       it here so show() credits back only the wait that belongs to this sector. */
    if(paused) pauseAt=lvlStart;
    seedStars(i+3, TH.starCount);
    const z=zoneOf(i);
    document.getElementById("lvlNum").textContent=String(i+1).padStart(2,"0");
    document.getElementById("lvlName").textContent=L.name;
    document.getElementById("zone").textContent=z.name;
    /* Zone I still explains itself. Everywhere after, the level has to speak
       through its own layout — a permanent hint strip reads as a manual. */
    const hintEl=document.getElementById("hint");
    hintEl.textContent = L.teach ? L.hint : "";
    hintEl.classList.toggle("off", !L.teach);
    document.getElementById("hudBot").classList.toggle("quiet", !L.teach);
    document.getElementById("deaths").textContent=0;
    TH=themeFor(ZONES.indexOf(z));
    setDrone(TH.drone);
  }

  /* ══════════════ CAMERA ══════════════
     Levels are wider and taller than the view now. The camera holds still while
     the player moves inside a deadzone, then eases after them — a hard follow on
     a precision platformer makes the whole screen twitch on every step. */
  const clampCamX=x=> LW<=W ? (LW-W)/2 : Math.max(0,Math.min(LW-W,x));
  const clampCamY=y=> LH<=H ? (LH-H)/2 : Math.max(0,Math.min(LH-H,y));
  function updateCam(snap){
    const px=player.x+player.w/2, py=player.y+player.h/2;
    const look=player.face*CAM_LOOKAHEAD*(Math.abs(player.vx)>1?1:0);
    let cx=cam.tx+W/2, cy=cam.ty+H/2;
    if(px-look < cx-CAM_DEADZONE_X) cx=px-look+CAM_DEADZONE_X;
    if(px-look > cx+CAM_DEADZONE_X) cx=px-look-CAM_DEADZONE_X;
    if(py < cy-CAM_DEADZONE_Y) cy=py+CAM_DEADZONE_Y;
    if(py > cy+CAM_DEADZONE_Y) cy=py-CAM_DEADZONE_Y;
    cam.tx=clampCamX(cx-W/2); cam.ty=clampCamY(cy-H/2);
    if(snap){ cam.x=cam.tx; cam.y=cam.ty; }
    else { cam.x+=(cam.tx-cam.x)*CAM_LERP; cam.y+=(cam.ty-cam.y)*CAM_LERP; }
  }

/* ══════════════ WORLD ══════════════ */
  const doorsOpen=()=> (switches.length+plates.length>0)
    && switches.every(s=>s.latched) && plates.every(p=>p.on);
  function tileAt(c,r){ return (c<0||c>=COLS||r<0||r>=ROWS) ? "#" : grid[r][c]; }
  const BELT=.9;                       // tiles/sec the plating carries you
  function beltAt(c,r){ const t=tileAt(c,r); return t===">"?1:t==="<"?-1:0; }
  function tileSolid(c,r){
    const t=tileAt(c,r);
    if(t===">"||t==="<") return true;
    return t==="#" || t==="~" || (t==="D"&&!doorsOpen())
        || (t==="="&&phase===0) || (t==="%"&&phase===1);
  }
  function hitTiles(x,y,w,h){
    const c0=Math.floor(x/TILE),c1=Math.floor((x+w-1)/TILE);
    const r0=Math.floor(y/TILE),r1=Math.floor((y+h-1)/TILE);
    for(let r=r0;r<=r1;r++)for(let c=c0;c<=c1;c++) if(tileSolid(c,r)) return true;
    return false;
  }
  /* drop-through plating: only solid to something moving in its own gravity sense */
  function hitTilesY(x,y,w,h,dir,ignoreDrop){
    if(hitTiles(x,y,w,h)) return true;
    if(ignoreDrop) return false;
    const c0=Math.floor(x/TILE),c1=Math.floor((x+w-1)/TILE);
    const r0=Math.floor(y/TILE),r1=Math.floor((y+h-1)/TILE);
    for(let r=r0;r<=r1;r++)for(let c=c0;c<=c1;c++){
      if(tileAt(c,r)!=="-") continue;
      const top=r*TILE, bot=top+TILE;
      if(dir>0 && y+h-1 >= top && y+h-1 < top+18 ) return true;   // landing from above
      if(dir<0 && y <= bot-1 && y > bot-19) return true;          // landing from below (inverted)
    }
    return false;
  }
  function hasChar(x,y,w,h,ch){
    const c0=Math.floor(x/TILE),c1=Math.floor((x+w-1)/TILE);
    const r0=Math.floor(y/TILE),r1=Math.floor((y+h-1)/TILE);
    for(let r=r0;r<=r1;r++)for(let c=c0;c<=c1;c++) if(tileAt(c,r)===ch) return true;
    return false;
  }
  const ovl=(a,b)=> a.x<b.x+b.w && a.x+a.w>b.x && a.y<b.y+b.h && a.y+a.h>b.y;
  function platHit(x,y,w,h){ const b={x,y,w,h}; for(const p of plats) if(ovl(b,p)) return p; return null; }
  function crateHit(x,y,w,h,skip){ const b={x,y,w,h}; for(const c of crates){ if(c===skip) continue; if(ovl(b,c)) return c; } return null; }
  const solidX=(x,y,w,h)=> hitTiles(x,y,w,h) || !!platHit(x,y,w,h);

  /* ══════════════ FERRIES ══════════════ */
  function updatePlats(){
    for(const p of plats){
      const ox=p.x, oy=p.y;
      p.p+=p.speed*p.dir;
      if(p.p>=p.dist){p.p=p.dist;p.dir=-1;} else if(p.p<=0){p.p=0;p.dir=1;}
      if(p.axis==="x") p.x=p.x0+p.p; else p.y=p.y0+p.p;
      const dx=p.x-ox, dy=p.y-oy;
      if(!dx&&!dy) continue;
      if(riding(player,ox,oy,p)) shove(player,dx,dy);
      for(const c of crates) if(riding(c,ox,oy,p)) shove(c,dx,dy);
      unstick(player,p,dx,dy);
      for(const c of crates) unstick(c,p,dx,dy);
    }
  }
  function riding(e,ox,oy,p){
    const gd=(e===player)?player.gd:1;
    const foot={x:e.x+2, y: gd>0 ? e.y+e.h-1 : e.y-3, w:e.w-4, h:4};
    return ovl(foot,{x:ox,y:oy,w:p.w,h:p.h});
  }
  function shove(e,dx,dy){
    const nx=e.x+dx, ny=e.y+dy;
    if(!hitTiles(nx,e.y,e.w,e.h) && !crateHit(nx,e.y,e.w,e.h,e)) e.x=nx;
    if(!hitTiles(e.x,ny,e.w,e.h) && !crateHit(e.x,ny,e.w,e.h,e)) e.y=ny;
  }
  function unstick(e,p,dx,dy){
    if(!ovl(e,p)) return;
    if(dx>0) e.x=p.x+p.w; else if(dx<0) e.x=p.x-e.w;
    if(dy>0) e.y=p.y+p.h; else if(dy<0) e.y=p.y-e.h;
  }

  /* ══════════════ CARGO ══════════════ */
  function pushCrate(cr,dx){
    const n=Math.max(1,Math.ceil(Math.abs(dx))), s=dx/n;
    for(let i=0;i<n;i++){
      const nx=cr.x+s;
      if(solidX(nx,cr.y,cr.w,cr.h)||crateHit(nx,cr.y,cr.w,cr.h,cr)) return false;
      cr.x=nx;
    }
    return true;
  }
  function crateFall(){
    for(const cr of crates){
      cr.vy=Math.min(cr.vy+GRAV,MAXFALL);
      const n=Math.max(1,Math.ceil(Math.abs(cr.vy))), s=cr.vy/n;
      for(let i=0;i<n;i++){
        const ny=cr.y+s;
        if(hitTilesY(cr.x,ny,cr.w,cr.h,1,false)||platHit(cr.x,ny,cr.w,cr.h)||crateHit(cr.x,ny,cr.w,cr.h,cr)){cr.vy=0;break;}
        cr.y=ny;
      }
    }
  }

  /* ══════════════ PLAYER ══════════════ */
  function moveX(dx){
    const n=Math.max(1,Math.ceil(Math.abs(dx))), s=dx/n;
    for(let i=0;i<n;i++){
      const nx=player.x+s;
      if(solidX(nx,player.y,player.w,player.h)){player.vx=0;return;}
      const cr=crateHit(nx,player.y,player.w,player.h);
      if(cr && !pushCrate(cr,s)){player.vx=0;return;}
      player.x=nx;
    }
  }
  function moveY(dy){
    const n=Math.max(1,Math.ceil(Math.abs(dy))), s=dy/n;
    const dropping = held(K.down) && !player.zg;
    for(let i=0;i<n;i++){
      const ny=player.y+s;
      const hit = hitTilesY(player.x,ny,player.w,player.h,Math.sign(s),dropping)
               || platHit(player.x,ny,player.w,player.h)
               || crateHit(player.x,ny,player.w,player.h);
      if(hit){
        if(Math.sign(s)===player.gd) player.onGround=true;
        player.vy=0;return;
      }
      player.y=ny;
    }
  }

  /* ══════════════ PLATING / PHASE / CORES ══════════════ */
  function checkFuses(){
    if(player.onGround){
      const fy = player.gd>0 ? player.y+player.h+1 : player.y-1;
      const c0=Math.floor((player.x+2)/TILE), c1=Math.floor((player.x+player.w-3)/TILE);
      const r=Math.floor(fy/TILE);
      for(let c=c0;c<=c1;c++) if(tileAt(c,r)==="~"){
        const k=r*COLS+c;
        if(!fuses.has(k)){ fuses.set(k,FUSE); S.crack(); }
      }
    }
    for(const [k,v] of [...fuses]){
      if(v<=0){
        const r=Math.floor(k/COLS), c=k%COLS;
        grid[r][c]="."; fuses.delete(k); shake=Math.max(shake,3); idleT=0; S.crack();
        for(let i=0;i<10;i++) puff(c*TILE+16,r*TILE+16,"#A78BFA",2.6);
      } else fuses.set(k,v-1);
    }
  }
  /* Touch a projector and it plays back the path you just walked. The phantom
     is literally your rewind history run forwards, so it holds plates exactly
     where you stood — the answer to "two plates, one of you". */
  function checkProjectors(){
    for(const p of projectors){
      if(p.pop>0) p.pop-=.03;
      if(p.used) continue;
      if(ovl(player,{x:p.x+4,y:p.y+4,w:24,h:24})){
        const take=Math.min(history.length, 720);          // up to 12s of your path
        if(take<30) continue;                              // nothing worth replaying yet
        phantom={frames:history.slice(-take).map(s=>({x:s.x,y:s.y})), i:0, loop:true};
        p.used=true; p.pop=1; shake=5; idleT=0; S.latch();
        for(let i=0;i<16;i++) puff(p.x+16,p.y+16,"#5EE0C8",2.8);
      }
    }
  }
  function stepPhantom(){
    if(!phantom) return;
    phantom.i++;
    if(phantom.i>=phantom.frames.length) phantom.i = phantom.loop ? 0 : phantom.frames.length-1;
  }
  const phantomBox=()=>{
    if(!phantom) return null;
    const f=phantom.frames[phantom.i];
    return {x:f.x, y:f.y, w:player.w, h:player.h};
  };
  function checkToggles(){
    if(tCool>0) tCool--;
    for(const t of toggles){
      if(t.pop>0) t.pop-=.04;
      if(tCool>0) continue;
      if(ovl(player,{x:t.x+4,y:t.y+4,w:24,h:24})){
        phase=1-phase; tCool=26; t.pop=1; shake=4; idleT=0; S.toggle();
        for(let i=0;i<14;i++) puff(t.x+16,t.y+16,phase?"#A78BFA":"#FFC46B",2.6);
        // never let a phase flip fuse the player inside solid lattice
        if(hitTiles(player.x,player.y,player.w,player.h)) nudgeOut();
      }
    }
  }
  function nudgeOut(){
    for(let d=1;d<=TILE*2;d++)
      for(const [dx,dy] of [[0,-d],[0,d],[-d,0],[d,0]])
        if(!hitTiles(player.x+dx,player.y+dy,player.w,player.h)){ player.x+=dx; player.y+=dy; return; }
  }
  function checkCores(){
    for(const c of cores){
      if(c.got) continue;
      if(ovl(player,c)){
        c.got=true; coresGot++; idleT=0;
        gotCore = coresGot===coresTotal;     // all-or-nothing: both cores or no mark
        S.core();
        for(let i=0;i<18;i++) puff(c.x+8,c.y+8,"#FFC46B",2.8);
        if(gotCore){ shake=Math.max(shake,4); setTimeout(()=>S.core(),150); }
      }
    }
  }

  /* ══════════════ PARTICLES ══════════════ */
  function puff(x,y,color,spd,n){
    n=n||1;
    for(let i=0;i<n;i++){
      const a=Math.random()*Math.PI*2, s=Math.random()*(spd||2);
      parts.push({x,y,vx:Math.cos(a)*s,vy:Math.sin(a)*s,life:1,col:color,sz:Math.random()*2+1});
    }
  }
  function updateParts(){
    for(let i=parts.length-1;i>=0;i--){
      const p=parts[i]; p.x+=p.vx; p.y+=p.vy; p.vx*=.94; p.vy=p.vy*.94+.08; p.life-=.035;
      if(p.life<=0) parts.splice(i,1);
    }
  }

  /* ══════════════ STEP ══════════════ */
  function step(){
    tick++;
    const cx=player.x+player.w/2, cy=player.y+player.h/2;
    player.zg = tileAt(Math.floor(cx/TILE),Math.floor(cy/TILE))==="Z";
    player.wasGround=player.onGround; player.onGround=false;
    updatePlats();

    const L=held(K.left), R=held(K.right), U=held(K.up), D=held(K.down);
    if(L!==R) player.face=L?-1:1;

    if(player.zg){
      if(L)player.vx-=ZG_THRUST; if(R)player.vx+=ZG_THRUST;
      if(U)player.vy-=ZG_THRUST; if(D)player.vy+=ZG_THRUST;
      player.vx*=ZG_DRAG; player.vy*=ZG_DRAG;
      player.vx=Math.max(-ZG_MAX,Math.min(ZG_MAX,player.vx));
      player.vy=Math.max(-ZG_MAX,Math.min(ZG_MAX,player.vy));
      if(L||R||U||D){ player.thrust=6; if(tick%4===0) puff(cx-player.face*8,cy+6,"#5EE0C8",1.2); }
      else player.thrust=Math.max(0,player.thrust-1);
      player.airJump=true;
    }else{
      if(L&&!R)player.vx-=ACC; else if(R&&!L)player.vx+=ACC; else player.vx*=FRIC;
      player.vx=Math.max(-RUN,Math.min(RUN,player.vx));
      player.vy+=GRAV*player.gd;
      player.vy=Math.max(-MAXFALL,Math.min(MAXFALL,player.vy));
      player.thrust=Math.max(0,player.thrust-1);
    }

    moveX(player.vx);
    moveY(player.vy);

    if(player.onGround){
      if(!player.wasGround){
        S.land();
        for(let i=0;i<5;i++) puff(cx+(Math.random()-.5)*14, player.gd>0?player.y+player.h:player.y,"#7C88A6",1.4);
      }
      player.coyote=COYOTE; player.airJump=true;
    } else if(player.coyote>0) player.coyote--;
    if(player.jbuf>0) player.jbuf--;

    if(player.jbuf>0){
      if(player.zg){ player.vy-=2.2*player.gd; player.jbuf=0; player.thrust=8; S.jump(); }
      else if(player.coyote>0){ player.vy=-JUMP*player.gd; player.coyote=0; player.jbuf=0; S.jump(); }
      else if(player.airJump){
        if(kit.burst){
          player.vy=-JUMP*BURST_SCALE*player.gd; player.airJump=false; player.jbuf=0; player.thrust=12; S.burst();
          for(let i=0;i<8;i++) puff(cx, player.gd>0?player.y+player.h:player.y,"#FFC46B",2.2);
        } else { player.jbuf=0; deny("burst"); }
      }
    }

    // conveyor carry — applied after movement so it reads as the floor moving,
    // not as a change in your own speed
    if(player.onGround && !player.zg){
      const fy = player.gd>0 ? player.y+player.h+1 : player.y-1;
      const d = beltAt(Math.floor((player.x+player.w/2)/TILE), Math.floor(fy/TILE));
      if(d) moveX(d*BELT*player.gd);
    }
    for(const cr of crates){
      const d = beltAt(Math.floor((cr.x+cr.w/2)/TILE), Math.floor((cr.y+cr.h+1)/TILE));
      if(d && cr.vy===0) pushCrate(cr, d*BELT);
    }
    crateFall(); checkFuses(); checkToggles(); checkProjectors(); stepPhantom(); checkCores();

    for(const s of switches){
      if(!s.latched && ovl(player,{x:s.x+4,y:s.y+4,w:24,h:24})){
        s.latched=true; s.pop=1; shake=5; idleT=0; S.latch();
        for(let i=0;i<14;i++) puff(s.x+16,s.y+16,"#5EE0C8",2.6);
        if(doorsOpen()) S.door();
      }
      if(s.pop>0) s.pop-=.04;
    }
    for(const p of plates){
      const z={x:p.x+2,y:p.y+8,w:28,h:24};
      const ph=phantomBox();
      p.was=p.on;
      p.on = ovl(player,z) || crates.some(c=>ovl(c,z)) || (ph && ovl(ph,z));
      if(p.on&&!p.was){ idleT=0; S.plate(); if(doorsOpen()) S.door(); }
    }

    const m = save.assist? 8 : 5;
    if(hasChar(player.x+m,player.y+m,player.w-m*2,player.h-m*2,"^")) kill();
    if(exitPt && ovl(player,{x:exitPt.x+2,y:exitPt.y+2,w:28,h:28})) winLevel();
  }

  function kill(){
    if(dead||won) return;
    dead=1; deaths++; runDeaths++; shake=11; idleT=0; S.die();
    record(tele.deaths,{s:lvl,x:Math.round(player.x),y:Math.round(player.y),t:Math.round(lvlMs/1000)});
    document.getElementById("deaths").textContent=deaths;
    for(let i=0;i<26;i++) puff(player.x+10,player.y+13,"#FF7A5C",4);
  }
  function winLevel(){
    if(won||dead) return;
    won=1; shake=6; S.exit();
    const secs=Math.max(1,Math.round(lvlMs/1000));
    const cl=clearedSet(); cl.add(lvl); save.cleared=[...cl];
    if(gotCore){ const cs=coreSet(); cs.add(lvl); save.cores=[...cs]; }
    if(!save.best[lvl] || secs<save.best[lvl]) save.best[lvl]=secs;
    save.last=Math.min(lvl+1,LEVELS.length-1);
    record(tele.clears,{s:lvl,ms:Math.round(lvlMs),d:deaths,c:coresGot,ct:coresTotal,par:LEVELS[lvl].par});
    saveNow(); buildMenu(); titleProgress();
    for(let i=0;i<24;i++) puff(exitPt.x+16,exitPt.y+16,"#5EE0C8",3);
  }

  /* ══════════════ REWIND ══════════════ */
  function snap(){
    history.push({x:player.x,y:player.y,vx:player.vx,vy:player.vy,gd:player.gd,aj:player.airJump,f:player.face,
      cr:crates.map(c=>c.anchored?null:{x:c.x,y:c.y,vy:c.vy}),
      mp:plats.map(p=>({p:p.p,d:p.dir}))});
    if(history.length>BUFFER()) history.shift();
  }
  function unsnap(){
    const s=history.pop(); if(!s) return;
    player.x=s.x;player.y=s.y;player.vx=s.vx;player.vy=s.vy;
    player.gd=s.gd;player.airJump=s.aj;player.face=s.f;
    s.cr.forEach((c,i)=>{ if(c&&crates[i]){crates[i].x=c.x;crates[i].y=c.y;crates[i].vy=c.vy;} });
    s.mp.forEach((m,i)=>{ const p=plats[i]; if(!p) return; p.p=m.p; p.dir=m.d;
      if(p.axis==="x") p.x=p.x0+p.p; else p.y=p.y0+p.p; });
  }

  /* ══════════════ UPDATE ══════════════ */
  function resetSector(){ if(!LEVELS[lvl]) return; loadLevel(lvl); if(paused) show(null); S.reset(); }
  function deny(which){ if(denyT>0&&denyKey===which) return; denyT=20; denyKey=which; S.deny(); }

  function update(){
    updateParts();
    if(denyT>0) denyT--;
    if(shake>0) shake-=.55;
    if(paused) return;
    if(!dead && !won){ lvlMs=performance.now()-lvlStart; idleT++; }

    if(won){ won++; if(won>26) nextLevel(); return; }
    if(dead){ dead++; if(dead>28) loadLevel(lvl); return; }

    const rw=keys.KeyR||keys.gRW;
    if(rw && !kit.rewind) deny("rewind");
    if(kit.rewind && rw && history.length>1){
      rewinding=true;
      for(let i=0;i<REWIND_SPEED;i++) if(history.length>1) unsnap();
      if(tick%9===0) S.tickr();
      tick++;
      for(const p of plates){
        const z={x:p.x+2,y:p.y+8,w:28,h:24};
        p.on = ovl(player,z) || crates.some(c=>ovl(c,z));
      }
    }else{ rewinding=false; step(); snap(); }
    updateCam(false);
  }
  function nextLevel(){
    if(!runMode || lvl+1>=LEVELS.length){ endRun(); return; }
    loadLevel(lvl+1); showCard();
  }

  /* ══════════════ RENDER ══════════════ */
  /* Visible tile window. Drawing a 73-wide sector tile-by-tile every frame is
     wasted work when only 25 columns are on screen. */
  let v0c=0,v1c=0,v0r=0,v1r=0;
  function viewport(){
    v0c=Math.max(0,Math.floor(cam.x/TILE));      v1c=Math.min(COLS-1,Math.ceil((cam.x+W)/TILE));
    v0r=Math.max(0,Math.floor(cam.y/TILE));      v1r=Math.min(ROWS-1,Math.ceil((cam.y+H)/TILE));
  }
  function render(){
    ctx.save();
    if(shake>.2&&!reduceMotion&&save.shake) ctx.translate((Math.random()-.5)*shake,(Math.random()-.5)*shake);
    ctx.fillStyle=TH.sky; ctx.fillRect(-24,-24,W+48,H+48);
    const sg=ctx.createRadialGradient(W/2,H*.1,0,W/2,H*.1,H*1.25);
    sg.addColorStop(0,TH.glow); sg.addColorStop(1,"rgba(0,0,0,0)");
    ctx.fillStyle=sg; ctx.fillRect(0,0,W,H);
    /* Starfield parallaxes against the camera — the cheapest depth cue there is,
       and it makes a long sector read as travel instead of a treadmill. */
    for(const s of stars){
      const x=(((s.x-cam.x*s.sp*.55)%W)+W)%W;
      const y=reduceMotion? s.y : ((((s.y-cam.y*s.sp*.55)+tick*s.sp*.3)%H)+H)%H;
      ctx.globalAlpha=s.a*TH.starAlpha; ctx.fillStyle=TH.star; ctx.fillRect(x,y,s.r,s.r);
    }
    ctx.globalAlpha=1;
    viewport();
    ctx.translate(-Math.round(cam.x),-Math.round(cam.y));
    ctx.strokeStyle=TH.grid; ctx.lineWidth=1; ctx.beginPath();
    for(let c=v0c;c<=v1c+1;c++){ctx.moveTo(c*TILE+.5,cam.y);ctx.lineTo(c*TILE+.5,cam.y+H);}
    for(let r=v0r;r<=v1r+1;r++){ctx.moveTo(cam.x,r*TILE+.5);ctx.lineTo(cam.x+W,r*TILE+.5);}
    ctx.stroke();
    drawFields(); drawTiles(); drawDoors(); drawPlats(); drawPlates();
    drawSwitches(); drawToggles(); drawProjectors(); drawCores(); drawCrates(); drawExit();
    drawPhantom();
    drawGhosts(); drawParticles(); drawPlayer(); drawOverlays();
    ctx.restore();
  }
  function drawFields(){
    const t=reduceMotion?0:tick;
    for(let r=v0r;r<=v1r;r++)for(let c=v0c;c<=v1c;c++){
      if(grid[r][c]!=="Z") continue;
      const x=c*TILE,y=r*TILE;
      ctx.fillStyle="rgba(94,224,200,.065)"; ctx.fillRect(x,y,TILE,TILE);
      ctx.fillStyle="rgba(94,224,200,.34)";
      const ox=(c*13+r*7)%TILE, oy=((r*17+c*5)+t*.55)%TILE;
      ctx.fillRect(x+ox,y+oy,2,2); ctx.fillRect(x+(ox+17)%TILE,y+(oy+19)%TILE,1.5,1.5);
    }
    ctx.strokeStyle="rgba(94,224,200,.32)"; ctx.lineWidth=1.5;
    for(let r=v0r;r<=v1r;r++)for(let c=v0c;c<=v1c;c++){
      if(grid[r][c]!=="Z") continue;
      const x=c*TILE,y=r*TILE; ctx.beginPath();
      if(tileAt(c,r-1)!=="Z"){ctx.moveTo(x,y+1);ctx.lineTo(x+TILE,y+1);}
      if(tileAt(c,r+1)!=="Z"){ctx.moveTo(x,y+TILE-1);ctx.lineTo(x+TILE,y+TILE-1);}
      if(tileAt(c-1,r)!=="Z"){ctx.moveTo(x+1,y);ctx.lineTo(x+1,y+TILE);}
      if(tileAt(c+1,r)!=="Z"){ctx.moveTo(x+TILE-1,y);ctx.lineTo(x+TILE-1,y+TILE);}
      ctx.stroke();
    }
  }
  const hullish=(c,r)=>{const t=tileAt(c,r);return t==="#"||t===":";};
  function drawTiles(){
    for(let r=v0r;r<=v1r;r++)for(let c=v0c;c<=v1c;c++){
      const ch=grid[r][c], x=c*TILE, y=r*TILE;
      if(ch==="#"){
        ctx.fillStyle=TH.hull; ctx.fillRect(x,y,TILE,TILE);
        ctx.fillStyle=TH.hullIn; ctx.fillRect(x+4,y+4,TILE-8,TILE-8);
        ctx.fillStyle=TH.hullEdge;
        if(!hullish(c,r-1)) ctx.fillRect(x,y,TILE,2);
        if(!hullish(c,r+1)) ctx.fillRect(x,y+TILE-2,TILE,2);
        if(!hullish(c-1,r)) ctx.fillRect(x,y,2,TILE);
        if(!hullish(c+1,r)) ctx.fillRect(x+TILE-2,y,2,TILE);
        if(((c*7+r*11)%9)===0){ ctx.fillStyle=TH.rivet; ctx.fillRect(x+13,y+13,6,6); }
      }
      else if(ch===">"||ch==="<"){
        const d = ch===">"?1:-1;
        ctx.fillStyle=TH.hull; ctx.fillRect(x,y,TILE,TILE);
        ctx.fillStyle=TH.hullIn; ctx.fillRect(x+2,y+8,TILE-4,TILE-10);
        ctx.fillStyle=TH.hullEdge; ctx.fillRect(x,y,TILE,3);
        // travelling chevrons: the belt has to read as moving even at a glance
        const off = reduceMotion ? 0 : (tick*1.6*d)%16;
        ctx.fillStyle="#5EE0C8"; ctx.globalAlpha=.55;
        for(let i=-1;i<3;i++){
          const bx = x + ((i*16 + off) + 32) % 32;
          ctx.beginPath();
          ctx.moveTo(bx, y+4); ctx.lineTo(bx+5*d, y+7); ctx.lineTo(bx, y+10);
          ctx.closePath(); ctx.fill();
        }
        ctx.globalAlpha=1;
      }
      else if(ch===":"){
        /* Same silhouette as hull. The tell is one shade on the inner face, a
           missing rivet, and a hairline seam — enough to reward looking, not
           enough to give itself away in passing. */
        ctx.fillStyle=TH.hull; ctx.fillRect(x,y,TILE,TILE);
        ctx.fillStyle=TH.hullIn; ctx.fillRect(x+4,y+4,TILE-8,TILE-8);
        ctx.fillStyle=TH.hullEdge;
        if(!hullish(c,r-1)) ctx.fillRect(x,y,TILE,2);
        if(!hullish(c,r+1)) ctx.fillRect(x,y+TILE-2,TILE,2);
        if(!hullish(c-1,r)) ctx.fillRect(x,y,2,TILE);
        if(!hullish(c+1,r)) ctx.fillRect(x+TILE-2,y,2,TILE);
        const near = player ? Math.hypot((player.x+10)-(x+16),(player.y+13)-(y+16)) : 999;
      const tell = Math.max(0, 1 - Math.max(0, near-40)/70);   // fades in within ~3 tiles
      ctx.fillStyle="rgba(232,227,216,"+(.05+tell*.10).toFixed(3)+")";
      ctx.fillRect(x+4,y+15,TILE-8,1);
      if(tell>0){
        ctx.save();
        ctx.globalAlpha=tell*.55; ctx.strokeStyle="#A78BFA"; ctx.lineWidth=1;
        ctx.setLineDash([3,4]); ctx.lineDashOffset=reduceMotion?0:-tick*.3;
        ctx.strokeRect(x+3.5,y+3.5,TILE-7,TILE-7);
        ctx.restore();
      }
      }
      else if(ch==="-"){
        ctx.fillStyle="#20283F"; ctx.fillRect(x,y,TILE,7);
        ctx.fillStyle="#46557E"; ctx.fillRect(x,y,TILE,2);
        ctx.fillStyle="rgba(70,85,126,.5)";
        for(let i=0;i<3;i++) ctx.fillRect(x+4+i*10,y+8,5,2);
      }
      else if(ch==="~"){
        const k=r*COLS+c, f=fuses.get(k);
        const j=(f!==undefined&&!reduceMotion&&save.shake)?(Math.random()-.5)*2.4:0;
        const a=f!==undefined?.5+.5*Math.sin(tick*.6):1;
        ctx.save(); ctx.translate(j,j);
        ctx.fillStyle="#241d3a"; ctx.fillRect(x,y,TILE,TILE);
        ctx.globalAlpha=a; ctx.strokeStyle="#A78BFA"; ctx.lineWidth=1.5;
        ctx.strokeRect(x+1.5,y+1.5,TILE-3,TILE-3);
        ctx.beginPath(); ctx.moveTo(x+5,y+TILE-6); ctx.lineTo(x+13,y+11);
        ctx.lineTo(x+19,y+20); ctx.lineTo(x+TILE-5,y+7); ctx.stroke();
        ctx.globalAlpha=1; ctx.restore();
      }
      else if(ch==="="||ch==="%"){
        const solid=(ch==="="&&phase===0)||(ch==="%"&&phase===1);
        const col=ch==="="?"#FFC46B":"#A78BFA";
        if(solid){
          ctx.fillStyle=ch==="="?"#2E2718":"#241d3a"; ctx.fillRect(x,y,TILE,TILE);
          ctx.strokeStyle=col; ctx.lineWidth=2; ctx.strokeRect(x+1,y+1,TILE-2,TILE-2);
          ctx.globalAlpha=.5; ctx.beginPath();
          ctx.moveTo(x+6,y+16);ctx.lineTo(x+16,y+6);ctx.lineTo(x+26,y+16);ctx.lineTo(x+16,y+26);
          ctx.closePath(); ctx.stroke(); ctx.globalAlpha=1;
        }else{
          ctx.globalAlpha=.20; ctx.strokeStyle=col; ctx.lineWidth=1;
          ctx.setLineDash([3,4]); ctx.strokeRect(x+2.5,y+2.5,TILE-5,TILE-5);
          ctx.setLineDash([]); ctx.globalAlpha=1;
        }
      }
      else if(ch==="^"){
        const below=["#","~","-"].includes(tileAt(c,r+1)), above=["#","~","-"].includes(tileAt(c,r-1));
        ctx.fillStyle=TH.hazard+"22"; ctx.fillRect(x,y,TILE,TILE);
        ctx.fillStyle=TH.hazard;
        const sp=(bx,by,d)=>{ctx.beginPath();ctx.moveTo(bx,by);ctx.lineTo(bx+8,by-14*d);ctx.lineTo(bx+16,by);ctx.closePath();ctx.fill();};
        if(below||(!below&&!above)){ sp(x,y+TILE-2,1); sp(x+16,y+TILE-2,1); }
        if(above||(!below&&!above)){ sp(x,y+2,-1); sp(x+16,y+2,-1); }
      }
    }
  }
  function drawDoors(){
    const open=doorsOpen();
    for(let r=v0r;r<=v1r;r++)for(let c=v0c;c<=v1c;c++){
      if(grid[r][c]!=="D") continue;
      const x=c*TILE,y=r*TILE;
      if(open){
        ctx.strokeStyle="rgba(94,224,200,.4)"; ctx.lineWidth=1; ctx.strokeRect(x+.5,y+.5,TILE-1,TILE-1);
        ctx.fillStyle="rgba(94,224,200,.07)"; ctx.fillRect(x,y,TILE,TILE);
        ctx.fillStyle="rgba(94,224,200,.5)"; ctx.fillRect(x+2,y+2,6,2); ctx.fillRect(x+TILE-8,y+TILE-4,6,2);
      }else{
        ctx.fillStyle="#2A2036"; ctx.fillRect(x,y,TILE,TILE);
        ctx.fillStyle="#FFC46B"; for(let i=0;i<4;i++) ctx.fillRect(x+3,y+5+i*7,TILE-6,3);
        ctx.strokeStyle="#FFC46B"; ctx.lineWidth=1; ctx.strokeRect(x+.5,y+.5,TILE-1,TILE-1);
      }
    }
  }
  function drawPlats(){
    for(const p of plats){
      ctx.fillStyle="#232B42"; ctx.fillRect(p.x,p.y,p.w,p.h);
      ctx.fillStyle="#3C4A70"; ctx.fillRect(p.x,p.y,p.w,3);
      ctx.fillStyle="#11162a"; ctx.fillRect(p.x+3,p.y+8,p.w-6,p.h-11);
      ctx.fillStyle="#FFC46B";
      const d=p.axis==="x"?(p.dir>0?1:-1):0;
      for(let i=0;i<Math.floor(p.w/TILE);i++){
        const bx=p.x+i*TILE+16; ctx.globalAlpha=.55;
        if(d>0){ctx.beginPath();ctx.moveTo(bx-4,p.y+16);ctx.lineTo(bx+3,p.y+20);ctx.lineTo(bx-4,p.y+24);ctx.closePath();ctx.fill();}
        else if(d<0){ctx.beginPath();ctx.moveTo(bx+4,p.y+16);ctx.lineTo(bx-3,p.y+20);ctx.lineTo(bx+4,p.y+24);ctx.closePath();ctx.fill();}
        else ctx.fillRect(bx-4,p.y+19,8,2);
        ctx.globalAlpha=1;
      }
      ctx.strokeStyle="rgba(60,74,112,.9)"; ctx.lineWidth=1; ctx.strokeRect(p.x+.5,p.y+.5,p.w-1,p.h-1);
    }
  }
  function drawPlates(){
    for(const p of plates){
      ctx.fillStyle="#11162a"; ctx.fillRect(p.x+1,p.y+TILE-5,TILE-2,5);
      ctx.fillStyle=p.on?"#5EE0C8":"#3A4460";
      ctx.fillRect(p.x+3,p.y+TILE-(p.on?7:11),TILE-6,p.on?5:4);
      if(p.on){ ctx.globalAlpha=.18; ctx.fillStyle="#5EE0C8"; ctx.fillRect(p.x,p.y+TILE-18,TILE,18); ctx.globalAlpha=1; }
      ctx.fillStyle=p.on?"rgba(94,224,200,.8)":"rgba(124,136,166,.6)";
      ctx.fillRect(p.x+5,p.y+TILE-3,3,2); ctx.fillRect(p.x+TILE-8,p.y+TILE-3,3,2);
    }
  }
  function drawSwitches(){
    for(const s of switches){
      const cx=s.x+16, cy=s.y+16;
      ctx.strokeStyle=s.latched?"#5EE0C8":"#7C88A6"; ctx.lineWidth=2;
      ctx.beginPath(); ctx.arc(cx,cy,9,0,Math.PI*2); ctx.stroke();
      if(s.latched){
        ctx.fillStyle="#5EE0C8"; ctx.beginPath(); ctx.arc(cx,cy,5,0,Math.PI*2); ctx.fill();
        ctx.globalAlpha=.16; ctx.beginPath();
        ctx.arc(cx,cy,15+(reduceMotion?0:Math.sin(tick/12)*2),0,Math.PI*2); ctx.fill();
        if(s.pop>0){ ctx.globalAlpha=s.pop*.5; ctx.strokeStyle="#5EE0C8"; ctx.lineWidth=2;
          ctx.beginPath(); ctx.arc(cx,cy,9+(1-s.pop)*22,0,Math.PI*2); ctx.stroke(); }
        ctx.globalAlpha=1;
      }else{ ctx.fillStyle="#3A4460"; ctx.beginPath(); ctx.arc(cx,cy,4,0,Math.PI*2); ctx.fill(); }
    }
  }
  function drawToggles(){
    for(const t of toggles){
      const cx=t.x+16, cy=t.y+16, col=phase===0?"#FFC46B":"#A78BFA";
      ctx.strokeStyle=col; ctx.lineWidth=2;
      ctx.beginPath();
      for(let i=0;i<6;i++){ const a=Math.PI/3*i+(reduceMotion?0:tick/60);
        const px=cx+Math.cos(a)*10, py=cy+Math.sin(a)*10; i?ctx.lineTo(px,py):ctx.moveTo(px,py); }
      ctx.closePath(); ctx.stroke();
      ctx.fillStyle=col; ctx.globalAlpha=.5; ctx.beginPath(); ctx.arc(cx,cy,4,0,Math.PI*2); ctx.fill();
      if(t.pop>0){ ctx.globalAlpha=t.pop*.5; ctx.lineWidth=2;
        ctx.beginPath(); ctx.arc(cx,cy,10+(1-t.pop)*24,0,Math.PI*2); ctx.stroke(); }
      ctx.globalAlpha=1;
    }
  }
  function drawProjectors(){
    for(const p of projectors){
      const cx=p.x+16, cy=p.y+16;
      ctx.strokeStyle=p.used?"#3E4763":"#5EE0C8"; ctx.lineWidth=2;
      ctx.beginPath(); ctx.arc(cx,cy,10,-2.2,2.2); ctx.stroke();
      ctx.beginPath(); ctx.arc(cx,cy,5,0,Math.PI*2); ctx.stroke();
      if(!p.used && !reduceMotion){
        ctx.globalAlpha=.25+.2*Math.sin(tick/14); ctx.fillStyle="#5EE0C8";
        ctx.beginPath(); ctx.arc(cx,cy,4,0,Math.PI*2); ctx.fill(); ctx.globalAlpha=1;
      }
      if(p.pop>0){ ctx.globalAlpha=p.pop*.5; ctx.strokeStyle="#5EE0C8";
        ctx.beginPath(); ctx.arc(cx,cy,10+(1-p.pop)*26,0,Math.PI*2); ctx.stroke(); ctx.globalAlpha=1; }
    }
  }
  function drawPhantom(){
    const b=phantomBox(); if(!b) return;
    ctx.globalAlpha=.4; ctx.fillStyle="#5EE0C8"; ctx.fillRect(b.x,b.y,b.w,b.h);
    ctx.globalAlpha=.75; ctx.strokeStyle="#5EE0C8"; ctx.lineWidth=1;
    ctx.strokeRect(b.x+.5,b.y+.5,b.w-1,b.h-1);
    ctx.globalAlpha=.5; ctx.fillStyle="#0C1020"; ctx.fillRect(b.x+2,b.y+4,b.w-4,7);
    ctx.globalAlpha=1;
  }
  function drawCores(){
    for(const c of cores){
      if(c.got) continue;
      const cx=c.x+8, cy=c.y+8, b=reduceMotion?0:Math.sin(tick/18)*2;
      ctx.save(); ctx.translate(cx,cy+b); ctx.rotate(reduceMotion?0:tick/70);
      ctx.strokeStyle="#FFC46B"; ctx.lineWidth=2;
      ctx.beginPath(); ctx.moveTo(0,-8);ctx.lineTo(8,0);ctx.lineTo(0,8);ctx.lineTo(-8,0);ctx.closePath(); ctx.stroke();
      ctx.fillStyle="rgba(255,196,107,.35)"; ctx.fill();
      ctx.restore();
      ctx.globalAlpha=.14; ctx.fillStyle="#FFC46B";
      ctx.beginPath(); ctx.arc(cx,cy+b,14,0,Math.PI*2); ctx.fill(); ctx.globalAlpha=1;
    }
  }
  function drawCrates(){
    for(const c of crates){
      ctx.fillStyle=c.anchored?"#2B2740":"#3A4460"; ctx.fillRect(c.x,c.y,c.w,c.h);
      ctx.strokeStyle=c.anchored?"#A78BFA":"#8C97B4"; ctx.lineWidth=2;
      ctx.strokeRect(c.x+1,c.y+1,c.w-2,c.h-2);
      if(c.anchored){
        ctx.beginPath(); ctx.moveTo(c.x+7,c.y+7); ctx.lineTo(c.x+c.w-7,c.y+c.h-7);
        ctx.moveTo(c.x+c.w-7,c.y+7); ctx.lineTo(c.x+7,c.y+c.h-7); ctx.stroke();
      }else{
        ctx.strokeStyle="rgba(232,227,216,.32)"; ctx.lineWidth=1;
        ctx.strokeRect(c.x+6,c.y+6,c.w-12,c.h-12);
      }
    }
  }
  function drawExit(){
    if(!exitPt) return;
    const cx=exitPt.x+16, cy=exitPt.y+16, pu=reduceMotion?0:Math.sin(tick/16)*2;
    ctx.strokeStyle="#5EE0C8"; ctx.lineWidth=2;
    ctx.beginPath(); ctx.arc(cx,cy,11+pu,0,Math.PI*2); ctx.stroke();
    ctx.globalAlpha=.3; ctx.beginPath(); ctx.arc(cx,cy,15+pu*1.7,0,Math.PI*2); ctx.stroke(); ctx.globalAlpha=1;
    ctx.fillStyle="rgba(94,224,200,.22)"; ctx.beginPath(); ctx.arc(cx,cy,7,0,Math.PI*2); ctx.fill();
    for(let i=0;i<4;i++){
      const a=tick/40+i*Math.PI/2;
      ctx.fillStyle="rgba(94,224,200,.7)";
      ctx.fillRect(cx+Math.cos(a)*13-1,cy+Math.sin(a)*13-1,2,2);
    }
  }
  function drawGhosts(){
    if(!rewinding) return;
    for(let i=history.length-1,n=0;i>=0&&n<8;i-=8,n++){
      const g=history[i]; ctx.globalAlpha=.11*(1-n/8);
      ctx.fillStyle="#A78BFA"; ctx.fillRect(g.x,g.y,player.w,player.h);
    }
    ctx.globalAlpha=1;
  }
  function drawParticles(){
    for(const p of parts){ ctx.globalAlpha=Math.max(0,p.life); ctx.fillStyle=p.col; ctx.fillRect(p.x,p.y,p.sz,p.sz); }
    ctx.globalAlpha=1;
  }
  function drawPlayer(){
    if(dead) return;
    const p=player, up=p.gd===1;
    if(p.thrust>0){
      ctx.globalAlpha=Math.min(1,p.thrust/12);
      const fy=up?p.y+p.h:p.y-9;
      ctx.fillStyle="#FFC46B"; ctx.fillRect(p.x+5,fy,4,9); ctx.fillRect(p.x+p.w-9,fy,4,9);
      ctx.fillStyle="#FF7A5C"; ctx.fillRect(p.x+6,fy+(up?4:0),2,5); ctx.fillRect(p.x+p.w-8,fy+(up?4:0),2,5);
      ctx.globalAlpha=1;
    }
    ctx.fillStyle="#E8E3D8";
    ctx.beginPath();
    const x=p.x,y=p.y,w=p.w,h=p.h,r=3;
    ctx.moveTo(x+r,y);ctx.arcTo(x+w,y,x+w,y+h,r);ctx.arcTo(x+w,y+h,x,y+h,r);
    ctx.arcTo(x,y+h,x,y,r);ctx.arcTo(x,y,x+w,y,r);ctx.closePath();ctx.fill();
    ctx.fillStyle="#11162a"; ctx.fillRect(p.x+2,p.y+(up?4:p.h-12),p.w-4,8);
    ctx.fillStyle=p.zg?"#5EE0C8":(p.airJump&&kit.burst?"#5EE0C8":"#7C88A6");
    ctx.fillRect(p.face>0?p.x+p.w-8:p.x+3, p.y+(up?6:p.h-10),5,4);
    ctx.fillStyle="rgba(124,136,166,.5)"; ctx.fillRect(p.x+3,p.y+(up?p.h-6:2),p.w-6,3);
    ctx.strokeStyle="rgba(7,9,18,.65)"; ctx.lineWidth=1; ctx.strokeRect(p.x+.5,p.y+.5,p.w-1,p.h-1);
  }
  function drawOverlays(){
    ctx.translate(Math.round(cam.x),Math.round(cam.y));   // overlays are screen-space
    if(rewinding&&!reduceMotion){
      ctx.fillStyle="rgba(167,139,250,.07)"; ctx.fillRect(0,0,W,H);
      ctx.fillStyle="rgba(167,139,250,.11)";
      for(let y=(tick*7)%6;y<H;y+=6) ctx.fillRect(0,y,W,1.5);
      ctx.strokeStyle="rgba(167,139,250,.5)"; ctx.lineWidth=2; ctx.strokeRect(1,1,W-2,H-2);
    }
    if(player&&player.gd===-1&&!rewinding){
      ctx.strokeStyle="rgba(255,122,92,.22)"; ctx.lineWidth=2; ctx.strokeRect(1,1,W-2,H-2);
    }
    if(dead){ ctx.fillStyle="rgba(255,122,92,"+Math.max(0,.45-dead/70)+")"; ctx.fillRect(0,0,W,H); }
    if(won){ ctx.fillStyle="rgba(94,224,200,"+Math.min(.5,won/40)+")"; ctx.fillRect(0,0,W,H); }
    const g=ctx.createRadialGradient(W/2,H/2,H*.35,W/2,H/2,H*.85);
    g.addColorStop(0,"rgba(0,0,0,0)"); g.addColorStop(1,"rgba(0,0,0,"+TH.vignette+")");
    ctx.fillStyle=g; ctx.fillRect(0,0,W,H);
  }

  /* ══════════════ HUD ══════════════ */
  const fmt=s=>Math.floor(s/60)+":"+String(Math.floor(s%60)).padStart(2,"0");
  function chip(node,locked,active,key,label){
    node.textContent=label;
    node.classList.toggle("locked",locked);
    node.classList.toggle("on",!locked&&active);
    node.classList.toggle("deny",denyT>0&&denyKey===key);
  }
  function hud(){
    const f=document.getElementById("bufFill"), pct=history.length/BUFFER()*100;
    f.style.width=kit.rewind?pct.toFixed(1)+"%":"0%";
    f.classList.toggle("low",rewinding&&pct<18);
    document.getElementById("bufWrap").classList.toggle("locked",!kit.rewind);
    chip(document.getElementById("chipBurst"),!kit.burst,!!player&&player.airJump,"burst","BURST");
    chip(document.getElementById("chipFlip"),!kit.flip,!!player&&player.gd===-1,"flip",
         player&&player.gd===-1?"FLIP ↑":"FLIP ↓");
    chip(document.getElementById("chipRwd"),!kit.rewind,rewinding,"rewind","RWND");
    document.getElementById("clock").textContent=fmt(lvlMs/1000);
    const cd=document.getElementById("coreDot");
    cd.classList.toggle("got",gotCore);
    cd.innerHTML = coresTotal ? "◆ "+coresGot+"/"+coresTotal+"<span class=\"lblword\"> CORES</span>" : "";
    cd.style.display=coresTotal?"":"none";
    document.getElementById("nudge").classList.toggle("show",!paused&&idleT>2400);
    // a stall is 25s in one sector without touching anything — the shape of "I'm lost"
    if(!paused && idleT===1500 && player)
      record(tele.stalls,{s:lvl,x:Math.round(player.x),y:Math.round(player.y)});
  }

  /* ══════════════ SCREENS ══════════════ */
  const el=id=>document.getElementById(id);
  const scr={title:el("scrTitle"),card:el("scrCard"),menu:el("scrMenu"),opt:el("scrOpt"),end:el("scrEnd")};
  let pauseAt=0;                  // when the current pause began; 0 while playing
  /* lvlStart and runStart are wall-clock anchors, and update() skips the frames
     where a screen is up — so every second spent reading a sector card or sitting
     in the pause menu was still billed to your clear time, and to your best. Roll
     the anchors forward by however long the game was actually stopped. */
  function show(s){
    const now=performance.now();
    if(s && !paused) pauseAt=now;
    else if(!s && paused && pauseAt){ const d=now-pauseAt; lvlStart+=d; runStart+=d; pauseAt=0; }
    Object.values(scr).forEach(x=>x.classList.remove("show"));
    if(s)s.classList.add("show");
    paused=!!s; setPaused(paused);
    setDrone(themeFor(ZONES.indexOf(zoneOf(lvl))).drone);
  }
  function showCard(){
    const z=zoneOf(lvl), L=LEVELS[lvl], k=L.kit||"";
    el("cardZone").textContent=z.name;
    el("cardNum").textContent="SECTOR "+String(lvl+1).padStart(2,"0")+" · "+LEVELS.length;
    el("cardTitle").textContent=L.name;
    el("cardLog").textContent = (lvl===z.at)? z.log : "";
    el("cardHint").textContent=L.hint;
    const on=["JUMP"],off=[];
    (k.includes("B")?on:off).push("BURST");(k.includes("F")?on:off).push("FLIP");(k.includes("R")?on:off).push("REWIND");
    el("cardKit").innerHTML="Loadout &nbsp;"+on.join(" · ")+
      (off.length?"<span style='color:#3E4763;text-decoration:line-through'> &nbsp;"+off.join(" · ")+"</span>":"")+
      "<br><span style='color:#3E4763'>PAR "+fmt(L.par)+(save.best[lvl]?" &nbsp;·&nbsp; BEST "+fmt(save.best[lvl]):"")+"</span>";
    show(scr.card);
  }
  function titleProgress(){
    el("titleProg").textContent=save.cleared.length+" / "+LEVELS.length+" sectors · "+
      coresFound()+" / "+CORES_ALL+" cores";
    el("btnCont").style.display=save.cleared.length?"":"none";
  }
  /* Cores used to be a number that went up and did nothing else — 54 collectibles
     whose only reward was completionism. A rank ladder is the cheapest thing that
     makes recovering them mean something, and the per-zone tally answers the
     question a completionist actually has: which zone still owes me. */
  const RANKS=[
    [1,   "FULL SALVAGE",   "Every core recovered. Nothing left aboard."],
    [.75, "SALVAGE LEAD",   null],
    [.5,  "SALVAGE CREW",   null],
    [0,   "STATION CLEARED",null],
  ];
  function endRun(){
    const found=coresFound(), left=CORES_ALL-found;
    const full=save.cleared.length===LEVELS.length;
    el("endSec").textContent=save.cleared.length+" / "+LEVELS.length;
    el("endCore").textContent=found+" / "+CORES_ALL;
    el("endTime").textContent=fmt((performance.now()-runStart)/1000);
    el("endDeaths").textContent=runDeaths;
    if(full){
      const [,rank,note]=RANKS.find(r=>found/CORES_ALL>=r[0]);
      el("endRank").textContent=rank;
      el("endNote").textContent=note || (left+" core"+(left===1?"":"s")+" still out there.");
    }else{
      const un=LEVELS.length-save.cleared.length;
      el("endRank").textContent="RUN ENDED";
      el("endNote").textContent=un+" sector"+(un===1?"":"s")+" still sealed.";
    }
    const cl=clearedSet(), cs=coreSet();
    el("endZones").innerHTML=ZONES.map((z,zi)=>{
      const [a,b]=zoneRange(zi); let sc=0,cc=0,ct=0;
      for(let i=a;i<b;i++){ if(cl.has(i)) sc++; ct+=CORES_IN[i]; if(cs.has(i)) cc+=CORES_IN[i]; }
      return "<span>"+z.name+"</span><b"+(cc===ct&&sc===b-a?" class=\"full\"":"")+
             ">"+sc+"/"+(b-a)+" &nbsp;◆ "+cc+"/"+ct+"</b>";
    }).join("");
    show(scr.end);
  }
  function buildMenu(){
    const g=el("lvlGrid"); if(!g) return;
    g.innerHTML=""; const cl=clearedSet(), cs=coreSet();
    let zi=-1;
    LEVELS.forEach((L,i)=>{
      const z=ZONES.indexOf(zoneOf(i));
      if(z!==zi){
        zi=z; const h=document.createElement("div"); h.className="zhead";
        const [a,b]=zoneRange(z); let sc=0,cc=0,ct=0;
        for(let j=a;j<b;j++){ if(cl.has(j)) sc++; ct+=CORES_IN[j]; if(cs.has(j)) cc+=CORES_IN[j]; }
        h.innerHTML="<span>"+ZONES[z].name+"</span>"+
          "<span class=\"ztally\">"+sc+"/"+(b-a)+" &nbsp;◆ "+cc+"/"+ct+"</span>";
        g.appendChild(h);
      }
      const b=document.createElement("button");
      b.className="lvlBtn"+(cl.has(i)?" done":"");
      const k=L.kit||"";
      const mark=(cs.has(i)?"<span style='color:var(--amber)'>◆</span>":"<span style='color:#2A3350'>◆</span>");
      b.innerHTML="<b><span class='mk'>"+mark+"</span>"+String(i+1).padStart(2,"0")+" · "+L.name+"</b>"+
        "JUMP"+(k.includes("B")?"·BURST":"")+(k.includes("F")?"·FLIP":"")+(k.includes("R")?"·REWIND":"")+
        (save.best[i]?"<br>best "+fmt(save.best[i]):"");
      b.addEventListener("click",()=>{runMode=false;loadLevel(i);showCard();});
      g.appendChild(b);
    });
  }
  const refreshDrone=()=>setDrone(themeFor(ZONES.indexOf(zoneOf(lvl))).drone);
  const isFull=()=>!!(document.fullscreenElement||document.webkitFullscreenElement);
  function toggleFull(){
    const root=document.documentElement;
    const go = isFull()
      ? (document.exitFullscreen||document.webkitExitFullscreen||(()=>{})).call(document)
      : (root.requestFullscreen||root.webkitRequestFullscreen||(()=>{})).call(root);
    if(go && go.catch) go.catch(()=>{});   // denied without a gesture; not worth surfacing
  }
  function applyOpts(){
    const s=el("saveState");
    if(s){ s.textContent=backendLabel();
           s.style.color = backendLabel().startsWith("not") ? "var(--oxide)" : "var(--dim)"; }
    el("optVol").value=Math.round(save.vol*100);
    el("volVal").textContent=Math.round(save.vol*100)+"%";
    const amb = save.amb===undefined ? .35 : save.amb;
    el("optAmb").value=Math.round(amb*100);
    el("ambVal").textContent = amb<=0 ? "off" : Math.round(amb*100)+"%";
    el("optShake").classList.toggle("on",!!save.shake);
    el("optShake").textContent=save.shake?"On":"Off";
    el("optAssist").classList.toggle("on",!!save.assist);
    el("optAssist").textContent=save.assist?"On":"Off";
    el("optFull").classList.toggle("on",isFull());
    el("optFull").textContent=isFull()?"On":"Off";
  }
  function startRun(from){
    runMode=true; runStart=performance.now(); runDeaths=0;
    loadLevel(from); showCard();
  }

  /* ══════════════ INPUT ══════════════ */
  function doJump(){ if(player) player.jbuf=JBUF; }
  function doFlip(){
    if(!player) return;
    if(!kit.flip){ deny("flip"); return; }
    player.gd*=-1; player.vy=0; player.airJump=true; shake=4; S.flip();
    for(let i=0;i<10;i++) puff(player.x+10,player.y+13,"#FF7A5C",2.2);
  }
  addEventListener("keydown",e=>{
    if(["Space","ArrowUp","ArrowDown","ArrowLeft","ArrowRight"].includes(e.code)) e.preventDefault();
    if(scr.card.classList.contains("show")){ show(null); return; }
    if(e.code==="Escape"){
      if(scr.opt.classList.contains("show")) show(scr.menu);
      else if(scr.menu.classList.contains("show")) show(null);
      else if(!scr.title.classList.contains("show")&&!scr.end.classList.contains("show")) show(scr.menu);
      return;
    }
    if(Object.values(scr).some(s=>s.classList.contains("show"))) return;
    keys[e.code]=true;
    if(e.code==="Space"&&!e.repeat) doJump();
    if(e.code==="KeyF"&&!e.repeat) doFlip();
    if(e.code==="KeyK") resetSector();
  });
  addEventListener("keyup",e=>{
    keys[e.code]=false;
    if(e.code==="Space"&&player&&!player.zg&&player.vy*player.gd<-CUT) player.vy=-CUT*player.gd;
  });
  addEventListener("blur",()=>{for(const k in keys)keys[k]=false;});
  /* Switching tabs used to leave the sector clock running and the zone drone
     humming under whatever you switched to. Stop for real, and let show() credit
     the time back. The title screen is already stopped, so leave it alone. */
  document.addEventListener("visibilitychange",()=>{
    if(document.hidden && !paused && !scr.title.classList.contains("show")) show(scr.menu);
  });

  el("btnStart").addEventListener("click",()=>startRun(0));
  el("btnCont").addEventListener("click",()=>startRun(save.last||0));
  el("btnSel").addEventListener("click",()=>show(scr.menu));
  el("btnEndSel").addEventListener("click",()=>show(scr.menu));
  el("btnOpt").addEventListener("click",()=>show(scr.opt));
  el("btnOpt2").addEventListener("click",()=>show(scr.opt));
  el("btnOptBack").addEventListener("click",()=>show(save.cleared.length||runMode?scr.menu:scr.title));
  el("btnResume").addEventListener("click",()=>show(null));
  el("btnRestart").addEventListener("click",resetSector);
  el("btnQuit").addEventListener("click",()=>{runMode=false;show(scr.title);});
  el("btnAgain").addEventListener("click",()=>startRun(0));
  ["mousedown","touchstart"].forEach(ev=>
    el("btnReset").addEventListener(ev,e=>{e.preventDefault();e.stopPropagation();resetSector();el("btnReset").blur();},{passive:false}));
  el("optVol").addEventListener("input",e=>{save.vol=e.target.value/100;applyOpts();refreshDrone();saveNow();});
el("optAmb").addEventListener("input",e=>{save.amb=e.target.value/100;applyOpts();refreshDrone();saveNow();});
  el("optShake").addEventListener("click",()=>{save.shake=save.shake?0:1;applyOpts();saveNow();});
  el("optAssist").addEventListener("click",()=>{save.assist=save.assist?0:1;applyOpts();saveNow();});
  el("optFull").addEventListener("click",toggleFull);
  document.addEventListener("fullscreenchange",applyOpts);
  /* The toggles are divs so they can sit in the options grid, which means they
     get none of a button's keyboard behaviour for free. Give it back rather than
     leaving a control only a mouse or a pad can reach. */
  document.querySelectorAll(".tog").forEach(t=>t.addEventListener("keydown",e=>{
    if(e.code==="Enter"||e.code==="Space"){ e.preventDefault(); t.click(); }
  }));
  el("btnTele").addEventListener("click",async()=>{
  const blob=JSON.stringify({v:1,when:Date.now(),tele:save.tele,
    best:save.best,cleared:save.cleared,cores:save.cores});
  const b=el("btnTele");
  // Download first: navigator.clipboard needs a secure context, and a
  // double-clicked file:// page isn't one, so copying silently failed there.
  try{
    const url=URL.createObjectURL(new Blob([blob],{type:"application/json"}));
    const a=document.createElement("a");
    a.href=url; a.download="drift-playtest.json"; a.click();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
    b.textContent="Saved drift-playtest.json";
  }catch(e){
    try{ await navigator.clipboard.writeText(blob); b.textContent="Copied to clipboard"; }
    catch(e2){ console.log(blob); b.textContent="Written to console"; }
  }
  setTimeout(()=>b.textContent="Export playtest data",2800);
});
el("btnWipe").addEventListener("click",()=>{
    wipe().then(()=>{buildMenu();titleProgress();});
    el("btnWipe").textContent="Erased";
    setTimeout(()=>el("btnWipe").textContent="Erase progress",1400);
  });

  if(matchMedia("(pointer: coarse)").matches){
    el("touch").classList.add("on");
    const bind=(id,down,up)=>{
      const n=el(id);
      n.addEventListener("touchstart",e=>{e.preventDefault();down();},{passive:false});
      n.addEventListener("touchend",e=>{e.preventDefault();if(up)up();},{passive:false});
      n.addEventListener("touchcancel",()=>{if(up)up();});
    };
    bind("tL",()=>keys.tL=true,()=>keys.tL=false);
    bind("tR",()=>keys.tR=true,()=>keys.tR=false);
    bind("tD",()=>keys.tD=true,()=>keys.tD=false);
    bind("tJ",()=>{if(!paused)doJump();},null);
    bind("tF",()=>{if(!paused)doFlip();},null);
    bind("tW",()=>keys.KeyR=true,()=>keys.KeyR=false);
    bind("tK",()=>{if(!paused)resetSector();},null);
    el("scrCard").addEventListener("touchstart",()=>{if(scr.card.classList.contains("show"))show(null);});
  }


  /* ══════════════ GAMEPAD ══════════════
     A platformer you cannot play on a controller reads as a prototype, and this
     was the largest gap between DRIFT and something you would put in front of a
     Steam user. The Gamepad API has no events for button state, so this polls
     once a frame and writes the same virtual keys the touch overlay already
     uses — the physics, the HUD and the deny logic never learn a pad exists.

     Menus need their own pass because there is no focus model to inherit: a
     canvas game has nothing the browser would tab through on its own. */
  const PAD={on:false, prev:{}, rep:0, held:false};
  const DEADZONE=.35, REPEAT_FIRST=16, REPEAT_NEXT=6;
  const down=(gp,i)=>{ const b=gp.buttons[i]; return !!b && (b.pressed || b.value>.5); };
  function firstPad(){
    const list = navigator.getGamepads ? navigator.getGamepads() : [];
    for(const g of list) if(g && g.connected) return g;
    return null;
  }
  function padClear(){ keys.gL=keys.gR=keys.gU=keys.gD=keys.gRW=false; }
  function padUI(on){
    document.body.classList.toggle("pad",on);
    el("padHint").classList.toggle("show",on);
  }
  function padPoll(){
    const gp=firstPad();
    if(!gp){ if(PAD.on){ PAD.on=false; PAD.prev={}; padClear(); padUI(false); } return; }
    if(!PAD.on){ PAD.on=true; padUI(true); }

    const ax=gp.axes[0]||0, ay=gp.axes[1]||0;
    const now={
      L: ax<-DEADZONE||down(gp,14),  R: ax>DEADZONE||down(gp,15),
      U: ay<-DEADZONE||down(gp,12),  D: ay>DEADZONE||down(gp,13),
      A: down(gp,0), B: down(gp,1), X: down(gp,2), Y: down(gp,3),
      RW: down(gp,4)||down(gp,5)||down(gp,6)||down(gp,7),
      ST: down(gp,9)||down(gp,8),
    };
    const hit=k=>now[k]&&!PAD.prev[k];
    if(Object.values(scr).some(x=>x.classList.contains("show"))) padMenu(now,hit);
    else padPlay(now,hit);
    PAD.prev=now;
  }
  function padPlay(now,hit){
    keys.gL=now.L; keys.gR=now.R; keys.gU=now.U; keys.gD=now.D; keys.gRW=now.RW;
    if(hit("A")) doJump();
    /* Releasing A cuts the jump short exactly as releasing SPACE does — variable
       jump height is half the forgiveness in the input model and a pad that
       can't do it plays like a different game. */
    if(!now.A && PAD.prev.A && player && !player.zg && player.vy*player.gd<-CUT)
      player.vy=-CUT*player.gd;
    if(hit("X")||hit("B")) doFlip();
    if(hit("Y")) resetSector();
    if(hit("ST")) show(scr.menu);
  }
  const padItems=()=>{
    const s=Object.values(scr).find(x=>x.classList.contains("show"));
    return s ? [...s.querySelectorAll("button,.tog,input[type=range]")].filter(e=>e.offsetParent) : [];
  };
  function padFocus(dir){
    const items=padItems(); if(!items.length) return;
    let i=items.indexOf(document.activeElement);
    i = i<0 ? (dir>0?0:items.length-1) : (i+dir+items.length)%items.length;
    items[i].focus();
    if(items[i].scrollIntoView) items[i].scrollIntoView({block:"nearest"});
  }
  function padBack(){
    if(scr.opt.classList.contains("show")) show(scr.menu);
    else if(scr.menu.classList.contains("show")) show(null);
    else if(scr.title.classList.contains("show")||scr.end.classList.contains("show")) return;
    else show(scr.menu);
  }
  function padMenu(now,hit){
    padClear();
    /* The card says "press any key"; on a pad that has to mean any button. */
    if(scr.card.classList.contains("show")){
      if(hit("A")||hit("B")||hit("X")||hit("Y")||hit("ST")) show(null);
      return;
    }
    const items=padItems();
    const focused=items.indexOf(document.activeElement)>=0;
    const any=now.U||now.D||now.L||now.R;
    if(items.length && !focused && (any||hit("A"))){ items[0].focus(); PAD.rep=REPEAT_FIRST; return; }

    const f=document.activeElement;
    const slider=f && f.tagName==="INPUT" && f.type==="range";
    const hdir=now.R?1:now.L?-1:0, vdir=now.D?1:now.U?-1:0;
    /* On a slider, left/right belongs to the value and up/down to the list —
       anything else makes volume impossible to set without a mouse. */
    const move=(slider&&hdir) ? 0 : (vdir||hdir);
    const slide=(slider&&hdir) ? hdir : 0;
    if(move||slide){
      if(PAD.rep<=0){
        if(slide){ f.value=+f.value + slide*(+f.step||1); f.dispatchEvent(new Event("input",{bubbles:true})); }
        else padFocus(move);
        PAD.rep = PAD.held ? REPEAT_NEXT : REPEAT_FIRST; PAD.held=true;
      }
      PAD.rep--;
    } else { PAD.rep=0; PAD.held=false; }

    if(hit("A") && f && typeof f.click==="function") f.click();
    if(hit("B")||hit("ST")) padBack();
  }
  addEventListener("gamepadconnected",()=>padUI(true));
  addEventListener("gamepaddisconnected",()=>{ if(!firstPad()){ PAD.on=false; padClear(); padUI(false); } });

  /* ══════════════ MAIN ══════════════ */
  buildMenu(); titleProgress(); applyOpts();
  loadSave();
  loadLevel(0);
  let acc=0,last=performance.now();
  function loop(now){
    const dt=Math.min(now-last,100); last=now; acc+=dt;
    padPoll();
    let guard=0;
    while(acc>=1000/60 && guard++<4){ update(); acc-=1000/60; }
    if(acc>1000/60) acc=0;
    render(); hud();
    requestAnimationFrame(loop);
  }
  requestAnimationFrame(loop);
}
