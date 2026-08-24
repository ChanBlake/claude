/* Persistent progress.
 *
 * DRIFT runs in three places and each offers a different way to persist:
 *
 *   1. a host-provided `storage` object  — the artifact viewer supplies this
 *   2. the Electron shell                — same API, backed by a real file on disk
 *   3. a plain browser (served locally, or a downloaded standalone file)
 *
 * The first two look identical here, which is why the native preload shims the
 * same shape. The third had nothing — so double-clicking the standalone file,
 * which is the most common way to play it, silently lost progress every
 * session. It now falls back to the browser's own storage.
 *
 * Order matters: the host object is preferred whenever it exists, so the
 * fallback never runs inside an environment that provides its own storage.
 * Everything is wrapped; saving is best-effort and must never block play.
 */
const KEY = "drift:save:v4";

export const save = { cleared: [], cores: [], best: {}, vol: 1, amb: .35, shake: 1, assist: 0, last: 0 };

/** Which backend we ended up with — surfaced in Settings so it's never a mystery. */
export let backend = "memory";

function localOK() {
  try {
    const t = "__drift_probe__";
    globalThis.localStorage.setItem(t, "1");
    globalThis.localStorage.removeItem(t);
    return true;
  } catch (e) {
    // Blocked by a file:// origin policy, private mode, or a disabled setting.
    return false;
  }
}

export async function saveNow() {
  const blob = JSON.stringify(save);
  try {
    if (globalThis.storage) { await globalThis.storage.set(KEY, blob); backend = "host"; return true; }
  } catch (e) { /* fall through to the browser */ }
  try {
    if (localOK()) { globalThis.localStorage.setItem(KEY, blob); backend = "browser"; return true; }
  } catch (e) { /* nothing left to try */ }
  backend = "memory";
  return false;
}

/* Older saves predate the ambience control and would otherwise inherit
   `undefined`, which reads as full volume. Fill in the new default instead. */
function migrate() {
  if (typeof save.amb !== "number") save.amb = .35;
}

export async function loadSave() {
  try {
    if (globalThis.storage) {
      const r = await globalThis.storage.get(KEY);
      if (r && r.value) Object.assign(save, JSON.parse(r.value));
      migrate(); backend = "host";
      return true;
    }
  } catch (e) { /* fall through */ }
  try {
    if (localOK()) {
      const raw = globalThis.localStorage.getItem(KEY);
      if (raw) Object.assign(save, JSON.parse(raw));
      migrate(); backend = "browser";
      return true;
    }
  } catch (e) { /* fall through */ }
  backend = "memory";
  return false;
}

export function wipe() {
  save.cleared = []; save.cores = []; save.best = {}; save.last = 0;
  save.tele = { deaths: [], clears: [], stalls: [] };
  return saveNow();
}

export const clearedSet = () => new Set(save.cleared);
export const coreSet = () => new Set(save.cores);

export const backendLabel = () => ({
  host: "saving to this app",
  browser: "saving in this browser",
  memory: "not saving — progress ends with this session",
}[backend]);
