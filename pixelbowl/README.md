# PIXEL BOWL

A one-thumb pixel football game for a phone. **Turn the phone sideways** — the
field runs left to right and you drive toward the right-hand end zone. Offense
only, drag to aim and release to throw.

Runs in mobile Safari with no App Store, no Xcode and no Mac. One HTML file,
no build step, no dependencies, and no image or audio assets: every sprite is
a character grid in source, the 5×7 font is a lookup table, the field is drawn
procedurally, and all fifteen sounds are synthesised in the Web Audio API.

## Playing it

Open `index.html` on the phone — any static host, or a local one:

```bash
python3 -m http.server 8000    # then http://<your-ip>:8000 on the phone
```

On iPhone, **Share → Add to Home Screen** gives you a full-screen app with no
browser chrome. Hold it sideways; the game says so if you don't.

## Controls

One thumb, three meanings, decided by what is on screen.

| | |
|---|---|
| **Call a play** | tap a card. Twelve plays over two pages — swipe the row to turn the page. On 4th down you also get PUNT and FIELD GOAL |
| **Snap** | tap anywhere |
| **Throw** | press and drag — a crosshair moves on the field ahead of your thumb; release to throw there |
| **Run** | `RUN` tucks it, then drag to steer. The carrier runs forward on his own; you steer, you don't drive |
| **Kick** | drag down and release. Sideways aims, length is power, the wind arrow matters — and past the mark on the bar, extra power buys distance with accuracy |

You are aiming at a **spot on the grass**, not at a receiver. Lead him — the
dotted arc shows where the ball lands, and receivers break on the ball once it
is up, so "about right" is good enough. Throwing at a covered man is how you
get picked.

You never play defense. Their possession is simulated and read out a line at a
time, which keeps a game to a few minutes and keeps your thumb on the half of
the game you actually control.

## Architecture

One file, in labelled sections:

| | |
|---|---|
| `CFG` | **All tuning.** Every speed, radius and probability. Nothing else hard-codes one |
| `RNG` | Seeded, reproducible. The seed is printed on the results screen |
| `TEAMS` | Eight invented clubs, deterministic roster generation |
| `GLYPHS` / `ART` | The 5×7 font and the sprite grids |
| `Sound` | Web Audio synthesis — squares, noise, envelopes |
| `PLAYS` / `SCHEMES` | Routes and assignments, in team-local yards |
| `makePlay` | One snap, snap to whistle. Fixed 1/60 step, deterministic |
| `G` / `newGame` | Rules, drives, the phase machine |
| `simulateTheirDrive` | The opponent's possession, abstracted |
| Render / Input | Art-pixel rendering at an integer scale; one pointer |

**One coordinate frame for everything.** You attack toward y = 110, they attack
toward y = 10. Nothing ever mirrors, so "the ball is on the 35" means the same
thing to the renderer, the rulebook and the drive sim. The simulation thinks in
"y is downfield, x is across" and the screen is landscape — that 90° rotation
lives in two functions (`scrX`/`scrY`) and the input handler, and nowhere else.

**Positions round to device pixels, not art pixels.** Sprites are baked at the
art scale and blitted 1:1, so they stay crisp while moving on a grid five or
six times finer. Rounding in art space is what made it judder.

**Difficulty changes how the defense reads the play** — how often it calls the
right front, and how fast its defenders react. It never changes how fast anyone
runs.

## Testing

The game's own source is loaded under a DOM stub and driven exactly as the
browser drives it, so the tests exercise shipping code rather than a copy.

```bash
node tools/test.js        # 59 checks: termination, determinism, rules, balance
node tools/balance.js     # plays whole games, reports the numbers you'd feel
npm i && node tools/shots.js   # renders it in Chromium and screenshots every screen
```

`tools/test.js` runs 1,440 plays across every play/front/field-position
combination checking nothing hangs, goes NaN or ends off the field; asserts the
simulation is reproducible; then plays complete games through the real phase
machine asserting the state never goes illegal between snaps.

`tools/shots.js` is the one that matters for anything visual: the Node harness
stubs every drawing call to a no-op, so only a real browser proves the game
looks like anything. It drives a drive at an iPhone viewport and saves a shot of
each screen. It found the aim cursor dragging off the top of the display, an
unreadable kick screen drawn straight onto the turf, and painted yard numbers
at three times life size — none of which the logic tests could see.

`tools/make_artifact.py` strips the standalone document down to the body-only
form an Artifact accepts, so there is one source of truth.

## Where it stands

Measured on PRO over 14 full games with a scripted competent player:

| | |
|---|---|
| Score | you 32–37, them 11–13 |
| Plays | 23–26 a game |
| Yards per play | 7.3–7.5 |
| Completions | 43–51% |
| Turnovers | ~1.2 a game |

**The known weak spot is the run game near the goal line.** Which front the CPU
calls dominates the result: a dive from the 2 scores on 90 of 90 against a base
look and 3 of 90 against a goal-line front, with the other three fronts around
a third. The passing game — which is what the one-thumb scheme is built around
— behaves well at 43–56% and a sane turnover rate. `tools/test.js` prints the
goal-line spread on every run so a regression is visible rather than silent.

Also not built: season or team management, penalties, onside kicks, overtime
(a tie stays a tie), and a service worker (Add to Home Screen works, but it
needs the network on first load).
