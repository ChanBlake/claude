# Opening and testing DRIFT

## The fastest way to just play it

Double-click **`drift-standalone.html`**. That's the whole game in one file — no server,
no Node, no install. It works offline and it's the right thing to send someone who just
wants to try it.

The only thing it can't do is save your progress between sessions, because a page opened
from `file://` has no storage host to write to.

## Running the project folder

The project version is ES modules, and browsers refuse to load those over `file://` —
every local file counts as a separate opaque origin, so the imports get blocked by CORS.
Opening `index.html` directly gives you a black rectangle and a console full of module
errors. That's expected, not a bug.

So it needs to be served over http. There's a server built in, with no dependencies:

```bash
cd drift
node serve.mjs
```

That serves on port 5173 and opens your browser. Nothing to install first — no
`npm install`, no network. If the port is busy: `node serve.mjs --port 8080`.

Requires Node 18 or newer (`node --version`).

### As a native app

```bash
npm install     # this one does need the network — it pulls Electron
npm run app
```

This is what Steam would actually ship, and the only mode where progress saves to a real
file on disk.

## Verifying the sectors

```bash
node tools/verify.mjs
```

No install needed. It proves all 30 sectors are reachable, that cargo can be pushed onto
its plate, that no sector issues an ability it doesn't need, and that the structure is
sound. Exit code is non-zero if anything is broken, so it works as a pre-commit hook or
in CI.

To inspect one sector, with a map of every tile the solver proved you can stand on:

```bash
node tools/verify.mjs --sector 18
```

The `·` marks are reachable tiles. If something you expected to be reachable isn't
marked, that's your bug — and it's much faster than replaying the level to find out.

## The editor

With the server running, open `http://localhost:5173/tools/editor.html`.

Paint with the palette, drag to fill, right-click to erase, `1`–`9` for quick picks, `Z`
to undo. It re-verifies on every single edit and shades the reachable region live. Pick
any existing sector from the dropdown to study or fork it. Copy the export block and
paste it into `src/levels.js`.

The warning to watch for is *"solvable, but issues gear it doesn't need"* — it means you
granted an ability the sector doesn't require, which hands the player a free pass around
your puzzle. That's the most common design mistake and it's the reason the check exists.

## A test pass worth doing

The verifier proves sectors are solvable. It cannot tell you they feel good. These are
the things it structurally cannot catch:

**Feel** — Sector 1. Walk, jump, land. Does the character feel heavy or floaty? Every
sector inherits this, so it's worth getting opinionated about early. All of it lives in
`src/config.js`.

**Teaching** — Sectors 2, 3, 4, 7, 13. Each introduces one mechanic. Play them cold and
ask whether the room taught you the idea before it tested you on it.

**The rewind asymmetry** — Sector 7, then 14. This is the game's central idea: you go
somewhere you can't come back from, change the world there, and rewind *yourself* out
while the change stays. If that doesn't land by sector 14, nothing later will work.

**Loadout restriction** — Sector 20 or 21. No rewind, no burst, no flip. Does the
constraint read as interesting or as missing?

**One-way commitment** — Sector 18. Set the lattice wrong before you spend the plating
and you strand yourself. Reset is one keypress, and after 40 idle seconds a prompt
appears — but check whether that feels like a fair lesson or a cheap trap. This is the
most likely place a real player gets annoyed.

**Pacing at the new length** — sectors are now two to three screens wide instead of one,
which is the biggest change and the one most likely to have gone wrong. Watch for the
middle of a long sector feeling like filler between two ideas rather than a second beat
of the same idea. If a chamber isn't pulling its weight, cut it in `tools/compose.py`
rather than padding it.

**False walls** — a dozen sectors hide a core behind one. They render as hull with a
shade of difference, and a dotted seam fades in when you stand within about three tiles.
Check that finding one feels like a discovery rather than like the game glitched; that
proximity tell is the whole difference and it's one number in `game.js`.

**The quiet HUD** — from sector 7 on there's no hint strip. Play 7 and 13 cold and check
that the room still teaches its trick without the caption. If it doesn't, the fix is the
level, not a hint.

**Difficulty curve** — play 1 through 24 in one sitting and note where you stall. My
guess is 17 or 18. Ordering is a one-line change in `tools/compose.py`.

Watch someone else play if you possibly can. Where they hesitate tells you more than
where they die.

## When something looks wrong

**Black rectangle, module errors in console** — you opened `index.html` from the
filesystem. Use `node serve.mjs`.

**No sound** — browsers block audio until you interact with the page. Click once. `M`
toggles mute; volume is in Settings.

**Progress not saving** — Settings now shows which storage the build found. If it reads
*not saving*, you're in private browsing or storage is disabled; switch modes or use
`npm run app`, which writes to a real file on disk.

**A sector seems impossible** — run `node tools/verify.mjs --sector N` first. If it
reports solvable and shades the objective as reachable, it's a design clarity problem,
not a broken level, and the fix is usually the hint or the sightline. If it reports
broken, that's a real bug and the output names the tile.
