// Minimal DOM stub so the game's own source can be loaded and driven under
// Node. Nothing here reimplements game logic — it only satisfies the browser
// APIs the file touches, so the tests exercise the shipping code.
"use strict";
const fs = require("fs"), path = require("path"), vm = require("vm");

function fakeCtx() {
  const noop = () => {};
  return new Proxy({
    canvas: null, imageSmoothingEnabled: false, fillStyle: "#000",
    fillRect: noop, drawImage: noop, save: noop, restore: noop,
    translate: noop, rotate: noop, scale: noop, clearRect: noop,
    beginPath: noop, closePath: noop, moveTo: noop, lineTo: noop, stroke: noop, fill: noop,
  }, { get: (t, k) => (k in t ? t[k] : noop), set: (t, k, v) => (t[k] = v, true) });
}
function fakeCanvas(w = 390, h = 844) {
  const c = {
    width: w, height: h, style: {}, clientWidth: w, clientHeight: h,
    getContext: () => fakeCtx(),
    addEventListener: () => {}, removeEventListener: () => {},
    getBoundingClientRect: () => ({ left: 0, top: 0, width: w, height: h }),
    classList: { add() {}, remove() {} }, remove() {},
  };
  return c;
}

function loadGame({ width = 844, height = 390, file = null } = {}) {
  const html = fs.readFileSync(file || path.join(__dirname, "..", "index.html"), "utf8");
  const js = html.match(/<script>\n([\s\S]*)\n<\/script>/)[1];

  const store = new Map();
  const els = { screen: fakeCanvas(width, height), shell: fakeCanvas(width, height), boot: fakeCanvas(), start: fakeCanvas() };

  const sandbox = {
    console,
    Math, Date, JSON, Object, Array, String, Number, Boolean, Map, Set, Error,
    isNaN, isFinite, parseInt, parseFloat, Proxy, Infinity, NaN, undefined,
    document: {
      getElementById: id => els[id] || fakeCanvas(),
      createElement: () => fakeCanvas(1, 1),
      addEventListener: () => {},
    },
    localStorage: {
      getItem: k => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => store.set(k, v),
      removeItem: k => store.delete(k),
    },
    requestAnimationFrame: () => 0,
    setTimeout: () => 0,
    performance: { now: () => 0 },
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.window.addEventListener = () => {};
  // `const` at script scope does not land on the global object, so the game's
  // source is followed by an epilogue that hands the tests what they need.
  const epilogue = `
    globalThis.API = { CFG, FIELD, TEAMS, PLAYS, SCHEMES, DIFFS, G, RNG, Input,
      makeRNG, makeRoster, makePlay, playById, callScheme, teamBy,
      newGame, giveUs, applyResult, snapPlay, punt, beginKick, resolveKick,
      startTheirDrive, advanceTheirDrive, simulateTheirDrive, downText, fieldLabel,
      fgDistance, inFGRange, update, draw, handleTap, hitTest, resize,
      textW, glyphRows, GLYPHS, ART, BALL_ART, clamp, FX, RUN_CYCLE,
      fieldX, fyAtScreen, scrX, scrY, driveRight, noteTendency,
      get SCREEN() { return SCREEN; }, set SCREEN(v) { SCREEN = v; },
      get SETTINGS() { return SETTINGS; },
      get RECORD() { return RECORD; },
      get HOT() { return HOT; },
      setRNG(r) { RNG = r; },
    };`;
  vm.createContext(sandbox);
  vm.runInContext(js + "\n" + epilogue, sandbox, { filename: "pixelbowl.js" });
  return sandbox.API;
}
module.exports = { loadGame };
