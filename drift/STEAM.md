# Shipping DRIFT on Steam

The game code is done and packaged. What follows is the part no amount of code can do
for you — it's mostly paperwork, art, and waiting.

## What's already handled

- **Executable builds.** `npm run dist` produces Windows, macOS and Linux builds via
  electron-builder. The verifier runs first, so a broken sector cannot be packaged.
- **Save location.** Progress writes to Electron's `userData` directory. That's the path
  you point Steam Cloud at.
- **Sandboxing.** The renderer has no node integration and cannot navigate away from the
  game — the usual reasons an Electron game gets flagged.
- **No runtime dependencies.** Nothing to license, nothing to attribute, no CDN that can
  go down after release.

## What you still need

### 1. Steamworks account — $100, one-time

Register at partner.steamgames.com. The fee is per app and is refunded once the app
grosses $1,000. Budget 3–7 days for identity and tax verification before you can touch
the store page.

### 2. Store assets

This is the real work. Steam requires specific dimensions and rejects sloppy ones:

| Asset | Size | Notes |
|---|---|---|
| Header capsule | 460×215 | the one people actually see |
| Small capsule | 231×87 | must be legible at this size |
| Main capsule | 1232×706 | store front features |
| Vertical capsule | 748×896 | seasonal sales |
| Library capsule | 600×900 | in-library |
| Library hero | 3840×1240 | |
| Screenshots | 1920×1080 | 5 minimum, more is better |
| Trailer | 1920×1080 | ~60s, gameplay in the first 5 seconds |

DRIFT's visual identity is already consistent — near-black, one accent colour per
mechanic (teal switches, amber lattice, violet rewind, oxide hazards). Build the capsules
from that palette rather than inventing a new look.

For the trailer, lead with the rewind ghost trail and a gravity flip. Those read
instantly in motion and are what makes the game look unlike other puzzle platformers.

### 3. Steamworks SDK — optional

The game needs none of it to ship. Add `steamworks.js` only if you want achievements,
Steam Cloud, or the overlay. Natural achievements here: clear a zone, recover all 24 data
cores, beat par on every sector, clear a sector without dying.

Cloud config, if you add it:

```
Root: WinAppDataLocal   Subdirectory: DRIFT   Pattern: save.json
```

### 4. Build upload

Use SteamPipe (`steamcmd`) with an app build script pointing at `dist/win-unpacked` and
friends. Set up depots per platform. Steam's docs on this are genuinely good.

### 5. Review and the two-week rule

- First build review: ~1–5 business days.
- **Store pages must be public at least 2 weeks before release.** This is not negotiable
  and it is the deadline people miss.
- Set your release date only once the build is uploaded and the page is live.

## An honest assessment

The mechanical foundation is solid: four mechanics that combine rather than sit beside
each other, per-sector loadouts that make each puzzle mean one thing, and a verifier that
makes shipping an unsolvable level structurally difficult.

What a paid release would still want:

- **More content.** 24 sectors is roughly 60–90 minutes. That's short for paid; it's
  well-judged for free or a demo. The editor and verifier exist precisely so adding
  sectors 25–60 is a design problem rather than an engineering one.
- **A reason to replay.** Par times and data cores are in. Speedrun timers, a ghost of
  your best run, or a daily sector would deepen it.
- **Playtesting by people who aren't you.** The verifier proves sectors are *solvable*.
  It cannot tell you they're *fun*, or that a hint reads clearly, or that sector 17 is
  where people quit. Nothing substitutes for watching five strangers play.
- **Controller support.** Gamepad API, roughly a day's work, and Steam users expect it.

My honest read: as a free browser release or an itch.io page, it's ready. For a paid
Steam release, the content needs to roughly double and it needs real playtesting first.
The scaffolding for both is now in place.
