# How to play DRIFT

There are three ways to run it. They're not equivalent, and the difference is mostly about
whether your progress survives.

## Quick answer

**Keep using the standalone file** — that's the right call for just playing. It's one file,
no setup, works offline.

One thing changed: it can now **save your progress**. Previously, a downloaded copy opened
by double-clicking had nowhere to store anything, so every session started from sector 1
with no cores and no best times. It now falls back to your browser's own storage. Settings
shows which state you're in, so it's never a mystery:

| Settings says | What it means |
|---|---|
| *saving in this browser* | normal — progress persists on this machine, in this browser |
| *saving to this app* | you're in the native build or a host that provides storage |
| *not saving — progress ends with this session* | private/incognito mode, or storage disabled |

If you see the last one, switch out of private browsing or use the native build.

Two caveats worth knowing. Progress is tied to **that browser on that machine** — a
different browser is a different save. And if you keep an old copy of the file around,
it'll share the same save, which is usually what you want but means an outdated build can
read newer data.

## The three ways

**Standalone file.** Double-click `drift-standalone.html`. Best for playing, and the right
thing to send anyone else. No install, no server, no network.

**Project folder.** `node serve.mjs`, then play at localhost:5173. Only worth it if you're
editing — you get separate modules, the sector editor at `/tools/editor.html`, and the
heatmap at `/tools/heatmap.html`. Opening `index.html` directly will *not* work; ES modules
can't load over `file://`, and you'll get a black rectangle.

**Native app.** `npm install && npm run app`. This is what Steam would ship. Progress goes
to a real file on disk rather than browser storage, so it survives clearing your browser
data. Needs the network once, for Electron.

## Playing well

- **Sound is off until you click.** Browsers block audio until you interact with the page.
  `M` mutes everything, and Settings has two separate sliders: **Volume** for the sound
  effects and **Ambience** for the zone drone underneath them. Ambience starts at 35% and
  can go to off — the drone is atmosphere, not information, so losing it costs you
  nothing. Nothing you need to hear lives in it.
- **`K` restarts a sector** at any time, as does the ⟲ RESET button. Several sectors are
  one-way by design, so if you strand yourself that's the way out — and a prompt appears
  after 40 idle seconds.
- **Assist mode** (Settings) triples the rewind buffer and shrinks your hazard hitbox. It
  never changes a sector's loadout, so every puzzle still solves the same way. It's there
  to be used.
- **Two cores per sector**, and a sector only counts as 100% when you have both. About half
  are behind false walls — hull with one shade of difference, and a dotted seam that fades
  in when you're within about three tiles.
- **From sector 7 on there are no hints.** That's deliberate; the level is supposed to
  explain itself through its layout. If one doesn't, that's a bug in the level, not in you.

## If you want to send me feedback that's actually useful

Play through, then **Settings → Export playtest data**. That downloads
`drift-playtest.json` with where you died, how long each sector took against par, where you
stalled, and which cores you found.

Open `tools/heatmap.html` (via `node serve.mjs`) and load that file. It draws a death
heatmap per sector and flags two things I can't otherwise see: sectors where you died a lot
but cleared fast (one bad jump), and sectors where you stalled without dying (the level
isn't communicating). It also reports where your run stopped.

That's far more actionable than "sector 17 felt hard" — it tells me *which tile*.
