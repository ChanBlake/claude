/* DRIFT — tuning. Every number the verifier depends on lives here.
   tools/verify.mjs re-derives the jump envelope from these, so changing
   JUMP or GRAV automatically re-checks all 30 sectors against the new reach. */

export const TILE=32;
/* The VIEWPORT is a fixed 25x15 tiles. Level grids are no longer tied to it —
   a sector declares its own width and height and the camera scrolls to fit. */
export const VCOLS=25, VROWS=15;
export const W=VCOLS*TILE, H=VROWS*TILE;

/* Camera. The deadzone is what keeps the view from twitching on every small
   step; the lerp is what keeps it from snapping when you cross the edge of it. */
export const CAM_DEADZONE_X=140, CAM_DEADZONE_Y=90;
export const CAM_LERP=.11, CAM_LOOKAHEAD=46;

export const GRAV=.5, MAXFALL=12;
export const RUN=3.4, ACC=.8, FRIC=.72;
export const JUMP=10.5, BURST_SCALE=.96, CUT=4.2;
export const ZG_THRUST=.30, ZG_DRAG=.965, ZG_MAX=3.3;

export const BASE_BUFFER=1800;   // frames of rewind history (30s at 60fps)
export const REWIND_SPEED=2;     // history frames consumed per tick
export const COYOTE=6, JBUF=7;   // forgiveness windows
export const FUSE=48;            // frames before brittle plating gives way
export const ASSIST_BUFFER=3;    // buffer multiplier in assist mode

/* Derived reach — used by the verifier and by level design.
   Recomputed rather than hardcoded so tuning changes can't silently
   invalidate a sector that was built against the old envelope. */
export function reach(){
  const rise=v=>{let y=0,vy=-v;while(vy<0){y+=vy;vy+=GRAV;}return -y;};
  const air=v=>{let y=0,vy=-v,f=0;while(y<=0||f<2){y+=vy;vy+=GRAV;f++;if(y>=0&&f>2)break;}return f;};
  const h1=rise(JUMP), h2=h1+rise(JUMP*BURST_SCALE);
  return {
    singleRise:h1, doubleRise:h2,
    singleTiles:h1/TILE, doubleTiles:h2/TILE,
    singleSpan:air(JUMP)*RUN/TILE, doubleSpan:air(JUMP)*1.7*RUN/TILE
  };
}
