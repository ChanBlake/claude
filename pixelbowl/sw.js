/* Pixel Bowl, offline.
 *
 * Network first so a new version reaches you the next time you open the game
 * with signal, cache second so it opens at all without any. Everything the
 * game needs is in this list — there is no CDN, no font host and no API.
 */
const CACHE = "pixelbowl-v1";
const ASSETS = ["./", "./index.html", "./manifest.webmanifest",
                "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE)
    .then(c => c.addAll(ASSETS))
    .then(() => self.skipWaiting())
    .catch(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  e.respondWith(
    fetch(e.request).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match(e.request).then(hit => hit || caches.match("./index.html")))
  );
});
