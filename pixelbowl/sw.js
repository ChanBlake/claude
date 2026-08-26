/* Pixel Bowl, offline.
 *
 * Network first so a new version reaches you the next time you open the game
 * with signal, cache second so it opens at all without any. Everything the
 * game needs is in this list — there is no CDN, no font host and no API.
 */
const CACHE = "pixelbowl-v2";
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

/* "Network first" is a lie unless you say which network.
 *
 * A plain `fetch(request)` is served by the browser's OWN http cache before it
 * ever reaches the wire, and GitHub Pages sends index.html with a ten-minute
 * max-age — so this handler would hand back a stale page, cache it as if it
 * were fresh, and the game would sit on an old build for as long as the phone
 * felt like it. `no-store` is what makes the first hop actually go out.
 */
self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  if (new URL(req.url).origin !== self.location.origin) return;

  e.respondWith(
    fetch(new Request(req.url, { cache: "no-store", credentials: "same-origin" }))
      .then(res => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(req).then(hit => hit || caches.match("./index.html")))
  );
});
