# DRIFT — Station Salvage

A sci-fi puzzle platformer about rewinding time, inverting gravity, and decisions you
cannot walk back. 30 scrolling sectors across five themed zones, three stages each —
roughly 87 screens of level, with 60 data cores to find.
No engine, no build step, no assets: the whole game is ES modules, a canvas, and
procedural audio.

## Running it

```bash
node serve.mjs           # play at localhost:5173 — no install, no network
node tools/verify.mjs    # prove all 24 sectors are solvable
```

Both are dependency-free; Node 18+ is the only requirement. ES modules cannot load over
`file://`, so opening `index.html` directly will not work — that is what `serve.mjs` is
for. The editor lives at `localhost:5173/tools/editor.html`.

For the native build (this one does need `npm install`, for Electron):

```bash
npm install && npm run app
```

`PLAYING.md` covers the three ways to run it and which to pick; `QUICKSTART.md` has a
suggested test pass and troubleshooting.

## The design rule

Difficulty comes from level design, not execution. Concretely, that means:

- Forgiving inputs — 6 frames of coyote time, 7 frames of jump buffering, variable jump
  height on release, instant respawn.
- Every gap that must not be cleared is placed well outside the jump envelope, not
  barely outside it. The shallowest "you cannot jump this" drop is 256px against a
  222px double jump.
- **Each sector issues its own loadout.** Most give you one tool. Locked abilities stay
  locked and buzz when pressed. This is the main difficulty lever: a puzzle built around
  rewind is not solvable by double-jumping past it.
- **The screen goes quiet after Zone I.** Sectors 1–6 show the hint strip and the full
  HUD labels while you're learning a mechanic. From Zone II on, the hint disappears and
  the readout dims to buffer, loadout and reset — the level has to communicate through
  its own geometry, not a caption. Sector cards still explain themselves before you
  start; that's a beat you dismiss, not furniture you play behind.

Every ability a sector grants is *proven necessary* — remove it and the sector becomes
unsolvable. The verifier enforces this, and it has deleted redundant grants from five
sectors that were quietly handing out free passes.

## Mechanics

| | |
|---|---|
| **Burst** | one mid-air boost per landing |
| **Flip** | inverts your personal gravity; ceilings become floors |
| **Rewind** | 30s buffer that restores you and loose cargo — but *not* latched switches, phase state, anchored cargo, or spent plating |
| **Null fields** | gravity off; thrust and momentum only |
| **Brittle plating** | one crossing, then gone for good |
| **Drop-through plating** | jump up through it, hold S to sink |
| **Phase lattice** | two block sets, one solid at a time; couplers swap which |
| **Cargo** | loose cargo rewinds, anchored cargo doesn't — that asymmetry is the puzzle engine |
| **False walls** | render as hull with one shade of difference; walk straight through |
| **Conveyor plating** | carries you *and cargo* — moves mass where you can't push it |
| **Phantom projector** | replays the path you just walked; your own ghost holds a plate |

The projector is the one to notice. It doesn't add a system beside rewind — it *reuses the
rewind buffer*, replaying your recorded path forwards. That makes you the second player,
which is the answer to "two plates and one of you." New mechanics should deepen the spine
rather than sit next to it, and this is what that looks like.

**Data cores** are optional, two per sector, and a sector only counts as 100% when both
are recovered. Half are hidden behind false walls; the rest sit at the reachable tile
furthest from the route between spawn and airlock — a deliberate detour rather than
something you pass through. Every core is proven reachable by the verifier, which is what
lets them be hidden well without ever being unfair.

The rewind asymmetry is the core idea: get somewhere you cannot return from, change the
world there, then rewind *yourself* out while the change stays.

## Zone themes

Each zone owns a palette, sky, hull treatment, star density and hazard colour, in
`src/themes.js` — Hull is cold and intact, Cargo is amber and industrial, Core is
irradiated violet, Void is deep and nearly empty, Relay is live green signal. These are
presentation only; nothing there touches collision or reach, so a theme can never make a
sector unsolvable.

## Layout

```
index.html         markup shell
serve.mjs          dependency-free dev server
build.mjs          one-command executable build
src/
  config.js        all tuning; derives the jump envelope the verifier uses
  levels.js        GENERATED — 30 sectors as ASCII grids
  themes.js        per-zone palettes
  game.js          physics, camera, rendering, UI, input
  audio.js         procedural sfx + zone drone
  save.js          progress; browser storage or the native shim
  main.js          entry point
  style.css        presentation
tools/
  compose.py       sector composer — chambers in, levels.js out
  verify.mjs       sector solvability prover
  bundle.mjs       builds the single-file standalone
  editor.html      visual editor with live verification
electron/          native shell for distribution
```

`src/levels.js` is generated. Edit chambers in `tools/compose.py`, then:

```bash
python3 tools/compose.py && node tools/verify.mjs && node tools/bundle.mjs
```

`config.js` is the single source of tuning truth. Change `JUMP` and the verifier
re-derives the reach and re-checks all 24 sectors against the new envelope — a retune
cannot silently invalidate a sector built against the old one.

## Playtesting

`tools/heatmap.html` turns a play session into answers the verifier structurally cannot
give. The game records deaths with positions, clear times against par, 25-second stalls,
and cores found; Settings → Export playtest data, then paste it into the viewer. It shows
a death heatmap per sector and names two failure shapes — *spiky* (dies a lot, clears
fast: one bad jump) and *unclear* (stalls without dying: the level isn't communicating).

Read `DESIGN-REVIEW.md` for a candid assessment of where the game actually stands, what
I'd cut, and where this tooling is soft.

## The verifier

Level geometry fails in ways that are invisible until a player is stuck. During
development this tool caught four genuinely unsolvable sectors: a switch sealed behind
hull, cargo pushed into a spot with nowhere to stand behind it, cargo placed above the
only reachable floor, and a data core walled off by unbroken plating.

It proves five things per sector:

1. **Reachable** — every switch, plate, cargo, core and airlock can be occupied, via a
   BFS over `(column, row, gravity, phase)` using an L-shaped corridor test so jump arcs
   cannot route through hull.
2. **Pushable** — every cargo can be shoved onto a plate, with gravity settling between
   pushes and a requirement that the player can actually stand behind it.
3. **Necessary** — removing any granted ability makes the sector unsolvable.
4. **Structural** — grid size, sealed borders, one spawn, one airlock, no door without a
   trigger, no lattice without a coupler, no plate without cargo.
5. **Not skippable** — stage seams must be far enough apart vertically that you cannot
   enter a stage and leave it a tile later. This catches the failure where an open sector
   lets you climb to the ceiling and run its whole length untouched, turning three stages
   into a corridor. Sectors gated by a closed door or a lattice wall are exempt: those are
   doing the gating, and the solver treats both as passable so it cannot see them.

What it deliberately does not model:

- **Rewind** governs the return trip, not whether a place is reachable.
- **Ferry timing** is treated as fully swept — timing is a design concern, not a
  solvability one.
- **Whether a level is fun.** It proves sectors are solvable and not trivially skippable.
  It cannot tell you a stage earns its length, or that a hint reads clearly.
- **Plating collapse**: `~` is treated as permanently solid. A sector must be solvable
  *without* riding a collapse, because a route that depends on the floor giving way is a
  route the player cannot see. This is stricter than the runtime and intentionally so —
  it forced two sectors to grow explicit openings.

It is dependency-free and runs in CI on every push.

```bash
node tools/verify.mjs              # all sectors
node tools/verify.mjs --sector 18  # one sector, with a reachability map
```

## Authoring sectors

Open `tools/editor.html`, paint with the palette, and it re-verifies on every edit —
reachability shading, cargo solvability, loadout necessity, structural checks. It warns
when a sector solves *without* an ability you granted, which is the most common design
smell. Copy the export and paste it into `src/levels.js`.

Tiles:

```
#  hull                    ~  brittle plating        -  drop-through plating
^  hazard                  Z  null field             =  lattice alpha (solid at phase 0)
D  door                    T  phase coupler          %  lattice beta  (solid at phase 1)
S  latch switch            B  pressure plate         o  data core (optional)
C  loose cargo             A  anchored cargo         P  spawn        E  airlock
```

Sectors are built from 25×15 **chambers** joined edge to edge, so a level is 49 or 73
tiles wide and the camera scrolls. Composing rather than typing 73-character rows is
deliberate: the most common way to break a level is a row one character short, and that
class of mistake is impossible when the join arithmetic is fixed. The seam between two
chambers is a doorway on whichever rows you name.

## Building an executable

```bash
node build.mjs --win --portable    # single self-contained .exe
node build.mjs --all               # Windows + macOS + Linux
```

Or double-click `BUILD-WINDOWS.bat` / `BUILD-MACOS.command`. The first build downloads
Electron (~250MB) and needs a network; nothing else in the project does. The verifier
runs first and hard-blocks the build, so a broken sector cannot become an executable.

See `BUILD.md` for targets, code signing and size tradeoffs, and `STEAM.md` for the
store checklist.

## Accessibility

Respects `prefers-reduced-motion`. Screen shake can be disabled. The zone drone has its
own level, separate from the sound effects, and can be turned fully off — low-frequency
ambience is felt as much as heard, so it accumulates over a session in a way that doesn't
register as "loud"; it should never be something you have to mute the whole game to escape. Assist mode triples the
rewind buffer and shrinks the hazard hitbox without altering any sector's loadout, so
every puzzle still solves the same way. Touch controls appear automatically on coarse
pointers.

## License

Your call — nothing here has third-party dependencies at runtime.
