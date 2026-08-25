# PIXEL GRIDIRON — file manifest

Every file, what it does, and whether the game needs it.

**32 source files · 3 test files · no assets · no dependencies.**

---

## Start here

| File | |
|---|---|
| `PixelGridiron.xcodeproj` | Open it, press ⌘R |
| `README.md` | Architecture, controls, the design rules |
| `tools/verify.py` | Structural checks that need no Swift toolchain |

---

## Core — the game (no SpriteKit, no UIKit)

| File | | Need it? |
|---|---|---|
| `Vec2.swift` | 2D vector maths in yards, plus `clamp` | yes |
| `RNG.swift` | Seeded SplitMix64. Every roll in the game draws from it | yes |
| `Field.swift` | Field geometry and the yard-line vocabulary | yes |
| `Teams.swift` | `PixelColor`, positions, ratings, the eight clubs, roster generation | yes |
| `Tuning.swift` | **All tuning.** Speeds, radii, probabilities, clock rate | yes |
| `Playbook.swift` | Formations, routes, assignments, special-teams units | yes |
| `Rules.swift` | Down and distance, the clock, scoring, possession, `MatchState` | yes |
| `SimTypes.swift` | `SimPlayer`, the ball, `PlayInput`, `PlaySetup`, `PlaySnapshot` | yes |
| `Simulation.swift` | One play: physics, contact, passing, fumbles, whistle | yes |
| `SimulationAI.swift` | Steering behaviour per assignment; the CPU quarterback | yes |
| `SimulationKicks.swift` | Punts, kickoffs, field goals, extra points | yes |
| `Coach.swift` | CPU play calling, fourth-down and two-point decisions | yes |

## Render — pixels

| File | | Need it? |
|---|---|---|
| `Palette.swift` | Non-team colours, `PixelColor → SKColor`, z-ordering | yes |
| `TextureFactory.swift` | Character grids → `SKTexture`, with a cache | yes |
| `PixelArt.swift` | **The sprites.** Seven player frames, the ball, the markers | yes |
| `PixelFont.swift` | 5×7 bitmap font and `PixelLabel` | yes |
| `FieldNode.swift` | `FieldGeometry`, the baked field texture, goalposts, crowd | yes |
| `PlayerNode.swift` | One player on screen, and the ball | yes |

## UI — what you touch

| File | | Need it? |
|---|---|---|
| `Controls.swift` | Floating joystick, pixel buttons, the contextual pad | yes |
| `HUDNode.swift` | Scoreboard, situation line, banner, stamina, mini field | yes |
| `PlayCallOverlay.swift` | Play cards and their route diagrams | yes |
| `KickMeterNode.swift` | The two-stage kick meter | yes |

## Scenes — flow

| File | | Need it? |
|---|---|---|
| `MatchConfig.swift` | What a game needs to start, and what it reports at the end | yes |
| `GameScene.swift` | The phase machine, the camera, the fixed-timestep loop | yes |
| `TitleScene.swift` | Title, team select, options, how-to-play | yes |
| `ResultsScene.swift` | Final score and box score | yes |
| `MenuKit.swift` | Menu rows, team tiles, the drifting backdrop | yes |

## Audio, Support, App

| File | | Need it? |
|---|---|---|
| `Audio/SFX.swift` | Chiptune synthesis: fifteen effects and a title loop | yes |
| `Support/Haptics.swift` | Taptic wrapper, with a no-op path off iOS | yes |
| `Support/Persistence.swift` | Settings, career records, cup runs | yes |
| `App/AppDelegate.swift` | Entry point, deliberately thin | yes |
| `App/GameViewController.swift` | Hosts the `SKView`, owns scene switching | yes |
| `App/Info.plist` | Landscape-only, no storyboard | yes |

## Tests

| File | |
|---|---|
| `RulesTests.swift` | The rulebook, driven with synthetic play results |
| `SimulationTests.swift` | Formation, determinism, termination, kicking, and a full headless game |
| `FieldAndArtTests.swift` | Geometry, vectors, RNG, pixel-grid integrity, rosters, playbook |

## Tools

| File | |
|---|---|
| `gen_xcodeproj.py` | Regenerates `project.pbxproj` from the filesystem |
| `verify.py` | Target membership, delimiter balance, `Core/` platform-freedom, art integrity |
