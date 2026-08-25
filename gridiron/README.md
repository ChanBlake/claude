# PIXEL GRIDIRON

A seven-a-side arcade football game for iOS. Native Swift and SpriteKit, no engine,
no third-party packages, and **no image or audio assets** — every sprite is a
character grid in source, every sound is synthesised at launch, and the field is a
procedural texture built from the rulebook's own geometry.

Eight fictional clubs, a six-play offensive book and a five-call defensive book,
four-down football with punts, field goals, two-point tries, safeties, turnovers
and a clock that stops for the right reasons.

## Building it

```bash
open PixelGridiron.xcodeproj      # then ⌘R
```

Xcode 15 or newer, iOS 16 or newer, landscape only, iPhone and iPad. There are no
dependencies to resolve and nothing to install. Set your own team under
**Signing & Capabilities** before running on a device; the Simulator needs
nothing.

Tests are ⌘U, or:

```bash
xcodebuild test -project PixelGridiron.xcodeproj \
  -scheme PixelGridiron -destination 'platform=iOS Simulator,name=iPhone 15'
```

Two scripts do the jobs that are easy to get wrong by hand, and both are
dependency-free Python 3:

```bash
python3 tools/gen_xcodeproj.py    # regenerate the project from what is on disk
python3 tools/verify.py           # structural checks that need no toolchain
```

`gen_xcodeproj.py` walks the source tree and rewrites `project.pbxproj`, so
target membership is a fact about the filesystem rather than something to
remember. Run it after adding a file. `verify.py` checks target membership,
delimiter balance, the platform-freedom of `Core/`, and the integrity of the
hand-written pixel grids.

## Controls

Landscape. Left thumb steers, right thumb acts.

| | Offense | Defense |
|---|---|---|
| Move | left thumb, anywhere in the left 40% | same |
| Snap | `SNAP` | — |
| Throw | `A` `B` `C` `D` — badges float over the matching receivers | — |
| Sprint | `GO` (hold, drains the stamina bar) | `GO` |
| Juke | `JUKE` — a hard sidestep that trips up pursuit | — |
| Dive | `DIVE` — lunge forward, ends the play | `HIT` — diving tackle |
| Switch player | — | `SWAP`, takes the man nearest the ball |
| Pause | `II`, top left | `II` |

The stick has no fixed home: put a thumb down anywhere in the left zone and that
is where the stick is until you lift it. The camera never rotates, so pushing
right always moves you toward higher x — which end zone that is depends on the
drive, and the yellow first-down line and the mini field at the top say which.

Kicks use a two-stage meter: tap once to set power, once more to stop the needle
in the green. The kick is decided the instant it leaves the foot; the flight is
theatre.

## Architecture

```
PixelGridiron/
  App/        UIKit shell — a window, a view controller, an Info.plist
  Core/       the game itself. No SpriteKit, no UIKit, no CoreGraphics.
  Render/     pixel grids, the texture factory, the field, the player sprite
  UI/         HUD, touch controls, play-call cards, the kick meter
  Scenes/     title, game, results — the phase machine and the camera
  Audio/      procedural chiptune synthesis
  Support/    haptics and UserDefaults
```

**The one architectural rule: `Core/` imports nothing but `Foundation`.**
`tools/verify.py` enforces it. Everything that decides an outcome — the rulebook,
the play simulation, the AI, the CPU coach — lives there and is exercised by
`PixelGridironTests` without a scene, a texture or a run loop. A whole game plays
out in that test suite in milliseconds.

The layering, top to bottom:

| File | |
|---|---|
| `Core/Rules.swift` | Down and distance, the clock, scoring, possession. Reads a `PlayResult`; never asks how the play happened. |
| `Core/Simulation.swift` | One play, snap to whistle. Fixed 1/60 timestep, seeded RNG, fully deterministic. |
| `Core/SimulationAI.swift` | Steering for the thirteen players you are not holding. Every assignment resolves to a desired velocity — the AI and the human go through identical acceleration and turn limits. |
| `Core/SimulationKicks.swift` | Punts, kickoffs, field goals, extra points. |
| `Core/Tuning.swift` | **Every number that decides how the game feels.** Nothing else hard-codes a speed, a radius or a probability. |
| `Core/Playbook.swift` | Formations, routes and assignments, in team-local yards. |
| `Core/Coach.swift` | What the CPU calls, when it goes for it, whether it kicks. |
| `Render/PixelArt.swift` | Seven player frames and the ball, as character grids. |
| `Render/PixelFont.swift` | A 5×7 bitmap font. All interface text goes through it. |
| `Render/FieldNode.swift` | The whole playing surface baked into one procedural texture. |
| `Scenes/GameScene.swift` | The bridge: asks `Rules` what a play meant, asks `Coach` what the CPU wants, arranges pixels. Owns no rules of its own. |

## The design rules

**Difficulty comes from reading the field, not from the CPU cheating.** The
difficulty setting changes how often the CPU makes the *correct read* for its
situation — never how fast its players run. A rubber-banded speed boost is the
thing that makes an arcade sports game feel cheap, and there isn't one here.

**The simulation is deterministic.** Same seed plus the same input sequence
produces the same result on every device, every time. That is why it is stepped
at a fixed 1/60 rather than at the display's variable delta, why every roll draws
from a seeded SplitMix64, and why the tests can assert on outcomes rather than on
ranges.

**A kick is decided at the foot.** The meter is the whole mechanic; a flight
simulation that could still rescue a badly stopped meter would make it decorative.

**Arcade proportions, honest rules.** The field is narrowed to 40 yards (from the
regulation 53⅓) because at a zoom where a play reads, a regulation width puts
both sidelines off screen. The rules on top of it are real: four downs, ten
yards, hash marks, touchbacks at the 25 and the 20, ends swapped every quarter, a
missed field goal spotted at the kick, a safety followed by a free kick from the
20.

**No assets.** Not a purity exercise — it means recolouring a team is three
`PixelColor` values, the repository is text all the way down, and every diff is
readable.

## Teams

Eight invented clubs. The cities are real places, the teams are not, and no
existing league's names, marks or colour schemes are used.

| | | Strength |
|---|---|---|
| GLS | Glasstown Voltage | +7 |
| NGT | Northgate Sentinels | +6 |
| SUN | Sunridge Scorpions | +5 |
| IRN | Ironport Anchors | +3 |
| CSC | Cascade Timberjacks | +1 |
| MBY | Marrow Bay Gulls | −1 |
| HLC | Hollow Creek Hounds | −2 |
| DST | Dustfall Coyotes | −4 |

Strength shifts every rating on the roster by the same amount, so a good team is
good everywhere rather than lopsided. Rosters are generated deterministically
from the team and a seed, so the same matchup always fields the same players.

## Modes

- **Exhibition** — pick your team, pick an opponent, play one game.
- **Cup run** — three single-elimination rounds against a random bracket. Lose
  once and the run is over. Career record and cup wins persist.

Quarter length (2/4/6/8 minutes), difficulty, sound, music and haptics all live
under Options.

## Known gaps

- No App Store icon or asset catalog — the project builds and runs without one,
  but you will want to add `Assets.xcassets` before shipping.
- No penalties, no fair catch, no onside kick, no overtime: a tie stays a tie.
- Special-teams returns use the same steering as a scrimmage play, so coverage
  lanes are looser than a dedicated model would give.
