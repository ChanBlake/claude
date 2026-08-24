# DRIFT — file manifest

Every file in the project, what it does, and whether you need it.

**30 sectors · five themed zones · ~87 screens · 54 data cores · all verified.**

---

## Start here

| File | |
|---|---|
| **`drift-standalone.html`** | The whole game in one file. Double-click it. This is what to send anyone. |
| **`PLAYING.md`** | The three ways to run it and which to pick |
| **`README.md`** | Architecture, mechanics, the design rule |
| **`DESIGN-REVIEW.md`** | My candid read on what's weak and what I'd cut |

---

## The game

| File | | Need it? |
|---|---|---|
| `index.html` | Markup shell — the HUD, screens, touch pads | yes |
| `src/main.js` | Entry point, deliberately thin | yes |
| `src/game.js` | Engine: physics, camera, rendering, UI, input | yes |
| `src/config.js` | **All tuning.** Derives the jump envelope the verifier uses | yes |
| `src/levels.js` | **GENERATED** — 30 sectors as ASCII grids. Don't hand-edit | yes |
| `src/themes.js` | Per-zone palettes, skies, hull treatments | yes |
| `src/audio.js` | Procedural sound effects and zone ambience | yes |
| `src/save.js` | Progress; host storage → browser storage → memory | yes |
| `src/style.css` | Presentation. No images, no webfonts | yes |

`config.js` is the single source of tuning truth. Change `JUMP` and the verifier re-derives
reach and re-checks all 30 sectors against the new envelope — a retune can't silently
invalidate a sector built against the old one.

## Tools

| File | |
|---|---|
| `tools/compose.py` | **Sector source.** Builds levels.js from 25×15 chambers. Edit levels here |
| `tools/verify.mjs` | Proves sectors are reachable, cargo-solvable, not skippable, and issue no unused gear |
| `tools/editor.html` | Visual chamber editor with live verification |
| `tools/heatmap.html` | Playtest analysis — death maps, stalls, where a run stopped |
| `tools/bundle.mjs` | Builds `drift-standalone.html` from the modules |
| `tools/find-secrets.py` | Searches for legal secret-pocket placements |
| `tools/find-highways.py` | Finds lanes that let you cross a sector without engaging |
| `tools/tune-seams.py` | Picks stage seams that force full traversal |

The verifier has caught six unsolvable sectors, a cargo dead-end, a skip that turned
three-stage levels into corridors, and five sectors handing out abilities they didn't need.
It runs in CI and gates the build.

## Running and shipping

| File | |
|---|---|
| `serve.mjs` | Dependency-free dev server. `node serve.mjs` — no install, no network |
| `build.mjs` | One-command executable build with preflight checks |
| `BUILD-WINDOWS.bat` | Double-click to build a Windows .exe |
| `BUILD-MACOS.command` | Double-click to build a macOS app |
| `electron/main.cjs` | Native shell — sandboxed renderer, save to disk |
| `electron/preload.cjs` | Storage shim matching the browser API |
| `package.json` | Scripts and electron-builder config |
| `build/icon.*` | App icon set, generated from the game's palette |
| `.github/workflows/verify.yml` | CI: fails the build if a sector breaks |

## Docs

`README.md` · `PLAYING.md` · `QUICKSTART.md` · `BUILD.md` · `STEAM.md` ·
`DESIGN-REVIEW.md` · `MANIFEST.md`

---

## The three commands that matter

```bash
node serve.mjs           # play / edit at localhost:5173
node tools/verify.mjs    # prove all 30 sectors are solvable
npm run levels           # compose → verify → rebundle, after editing sectors
```

## If you change a level

`src/levels.js` is generated. Edit chambers in `tools/compose.py`, then:

```bash
python3 tools/compose.py && node tools/verify.mjs && node tools/bundle.mjs
```

CI also checks the committed `levels.js` matches what the chambers produce, so a stale
generated file can't pass verification while the source says something different.

## What no file here can tell you

The tooling proves sectors are correct. It cannot tell you a stage earns its length, that a
hint reads clearly, or which sector people quit at. That's what `tools/heatmap.html` and
three strangers playing are for — and it's still the highest-leverage thing left.
