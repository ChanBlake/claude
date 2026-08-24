/* Procedural audio — no asset files, no load time, no licensing. */
import {save} from "./save.js";
let paused=true;
export function setPaused(p){ paused=p; }
let actx=null, drone=null, droneGain=null, droneFilt=null;
function AC(){
  if(!actx){ try{ actx=new (window.AudioContext||window.webkitAudioContext)(); }catch(e){ return null; } }
  if(actx.state==="suspended") actx.resume();
  return actx;
}
export function sfx(f0,f1,dur,type,vol){
  const a=AC(); if(!a||save.vol<=0) return;
  try{
    const o=a.createOscillator(), g=a.createGain(), t=a.currentTime;
    o.type=type||"square"; o.frequency.setValueAtTime(f0,t);
    o.frequency.exponentialRampToValueAtTime(Math.max(20,f1),t+dur);
    g.gain.setValueAtTime(0,t);
    g.gain.linearRampToValueAtTime((vol||.06)*save.vol,t+.008);
    g.gain.exponentialRampToValueAtTime(.0001,t+dur);
    o.connect(g);g.connect(a.destination);o.start(t);o.stop(t+dur+.02);
  }catch(e){}
}
export const S={
  jump:()=>sfx(400,660,.10,"square",.05), burst:()=>sfx(280,880,.16,"sawtooth",.05),
  land:()=>sfx(170,90,.07,"sine",.05),    flip:()=>sfx(520,190,.16,"triangle",.05),
  latch:()=>sfx(620,1180,.16,"square",.06), plate:()=>sfx(300,520,.12,"triangle",.06),
  door:()=>sfx(150,300,.34,"sine",.07),   crack:()=>sfx(240,120,.14,"sawtooth",.05),
  die:()=>sfx(330,70,.30,"sawtooth",.07), tickr:()=>sfx(880,660,.03,"sine",.02),
  deny:()=>sfx(150,90,.10,"square",.045), reset:()=>sfx(240,420,.14,"triangle",.05),
  core:()=>{sfx(700,1050,.10,"sine",.06);setTimeout(()=>sfx(1050,1400,.16,"sine",.05),90);},
  toggle:()=>sfx(440,300,.12,"square",.055),
  exit:()=>{sfx(520,780,.14,"sine",.07);setTimeout(()=>sfx(780,1180,.22,"sine",.06),110);}
};
/* Zone ambience.
 *
 * This was a bare sine at 41–67Hz running at a fixed level under everything,
 * which is exactly the recipe for something that wears on you: low frequencies
 * are felt as much as heard, so they don't register as "loud" but they do
 * accumulate over a session.
 *
 * Three changes. It's much quieter by default. It runs through a lowpass so
 * it's a floor rather than a tone. And it has its OWN level, independent of the
 * sound effects, so it can be turned off without losing the audio that actually
 * tells you things.
 */
const DRONE_CEILING = .0055;      // was .016 — roughly a third

export function setDrone(hz){
  const a=AC(); if(!a) return;
  try{
    if(!drone){
      drone=a.createOscillator();
      droneFilt=a.createBiquadFilter();
      droneGain=a.createGain();
      drone.type="sine";
      droneFilt.type="lowpass"; droneFilt.frequency.value=180; droneFilt.Q.value=.4;
      droneGain.gain.value=0;
      drone.connect(droneFilt); droneFilt.connect(droneGain);
      droneGain.connect(a.destination);
      drone.start();
    }
    // an octave up from the old pitch: still low, but out of the rumble band
    drone.frequency.setTargetAtTime(hz*2,a.currentTime,.6);
    const amb = save.amb===undefined ? .5 : save.amb;
    const target = (paused || amb<=0) ? 0 : DRONE_CEILING*amb*save.vol;
    droneGain.gain.setTargetAtTime(target,a.currentTime,1.2);   // slower, so it never swells
  }catch(e){}
}

