# PIXEL BOWL

A one-thumb pixel football game for a phone. **Turn the phone sideways** — the
field runs left to right and you drive toward the **left-hand** end zone, or the
right-hand one if you'd rather (title screen → YOU ATTACK).
Offense only, drag to aim and release to throw.

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
| **Throw** | press and drag left — a crosshair moves downfield ahead of your thumb; release to throw there |
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

**The camera is zoomed past the sidelines.** It shows 23 of the field's 30
yards and follows the ball across as well as along, so players read at a size
worth animating.

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
node tools/test.js        # 95 checks: termination, determinism, rules, balance
node tools/skill.js       # the same games played by four different standards of thumb
node tools/cpu.js         # points per drive for the opponent's simulated possession
node tools/balance.js     # plays whole games, reports the numbers you'd feel
node tools/drives.js      # where possessions start and what they produce
node tools/plays.js       # a few hundred snaps of each play, low variance
npm i && node tools/shots.js   # renders it in Chromium and screenshots every screen
```

`tools/skill.js` exists because one scripted player tells you nothing about the
*ceiling*, and the ceiling is what someone who has played fifty games actually
meets. It runs four standards of thumb, including DIVER — a player who found one
play that works and stopped looking. If the defence never answers that, the game
has no ceiling at all, and the scoreboard says so.

`tools/drives.js` and `tools/plays.js` exist because whole-game averages hid
the two worst bugs in this thing. Thirty games give about eighty carries — far
too few to tell a two-yard change from noise — and a per-play average says
nothing about *where a possession began*, which is what actually decides how
many points a yard is worth. `plays.js` runs each play a few hundred times for
a distribution rather than a mean; `drives.js` reports field position and how
long a touchdown drive took.

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

Per snap, sampled over a few thousand plays, against the real thing in brackets:

| | Pixel Bowl | (NFL) |
|---|---|---|
| Yards per carry | 4.4 | 4.3 |
| Yards per completion | 12.1 | 11.5 |
| — of which after the catch | 4.6 | 5.0 |
| Completions 35 yards or longer | 5% | 4% |
| Completion rate | 68% | 65% |
| Interception rate | 3.3% | 2.3% |

Whole games, as **average margin** by how well the game is played (`tools/skill.js`,
twelve games a cell — small enough that these move a few points run to run):

| | ROOKIE | PRO | ALL-PRO |
|---|---|---|---|
| Ordinary | +12 | −5 | −2 |
| Careful | +11 | +6 | −1 |
| Sharp | +10 | +1 | −12 |
| One play, over and over | +14 | 0 | −11 |

The opponent's simulated possession is worth **1.5 / 1.8 / 2.6 points a drive**
across the three grades, against a real-football 2.2 — which with seven or eight
possessions a side is the whole difficulty ladder in one number
(`tools/cpu.js`; the drive simulator is cheap enough to run four hundred
possessions in a second, so it is tuned directly rather than through whole games).

Play counts are low and yards per play high because a quarter is three minutes,
not fifteen — the game is a highlight reel of a game, not a game.

### What a 72–2 scoreline was actually made of

A playtest came back 72–2, and none of it was the passing game being generous.
Four separate things, in rough order of blame:

1. **The opponent punted the wrong way.** Their possession is simulated, and
   they drive toward decreasing `y` — but the punt read `los + punt`, copied
   from your own punt, where `y` goes up. Every time they gave the ball up you
   got it around their 30. Average starting field position was 35 yards from
   the end zone; it is now 61. That single sign was most of the scoreline.
2. **Deep balls didn't fade.** Catch odds ignored how far the ball had flown,
   so a 45-yard bomb was caught as often as a checkdown. A third of every
   completion went 35 yards or more; now 12%.
3. **Nothing contested a pass — it adjudicated one.** A defender an inch closer
   to the ball than the receiver killed the throw outright. Once the coverage
   started taking real pursuit angles that fired on a quarter of all attempts,
   which is where "an interception every other play" came from. Position is now
   a penalty on the catch, not a verdict.
4. **The run game didn't exist.** All eleven defenders converged on the handoff
   from frame one with perfect angles; carries averaged 0.7 yards. Nobody
   diagnoses a run that fast — the box now reads it in 0.3s and the secondary in
   0.7s, and that half-second is the only reason a crease ever exists. Carries
   average 5.3 yards now.

### Why it played like a blowout every week

A second round of playtesting came back "I win every game by 40+", and the cause
was three things stacked:

1. **Anyone in an offensive shirt could catch a forward pass.** `arrive` took the
   nearest man on your side of the ball, so a guard standing in the way of a
   throw over the middle caught it — nineteen percent of completions on a
   thumb-aimed pass were made by a lineman. Only eligible receivers can catch it
   now.

2. **Nobody on defence ever sprinted.** `sprint` was set by the ball carrier's AI
   and by your thumb, and by nothing else. So every ball carrier in the game was
   permanently 14% faster than every man pursuing him *and* nine points harder to
   bring down. A back who cleared the front was simply never caught: DIVE
   averaged 10 to 23 yards a carry against every front but goal line. It now
   averages 4.4, and no carry in a sample of nine hundred went past twenty yards
   untouched.

3. **The defence never noticed what you kept calling.** Fronts were chosen from
   down and distance alone, so you could run the same play forty times in a game
   and never once be answered for it — which is exactly what a person does the
   moment they find something that works. It now keeps a decaying memory of your
   run/pass split and answers a one-sided one, hard at ALL-PRO and lazily at
   ROOKIE. `tools/skill.js` measures this directly with a player who calls DIVE
   and nothing else: that player went from +34 a game on PRO to about even.

Difficulty also does more than it used to. It was two numbers — how often the
CPU called the right front, and a reaction lag. It now also sets how hard a
defender in position makes a catch, how quickly they read your tendencies, and
how well their own possession goes.

### Where the margin was actually coming from

A third round came back 56–3, and the honest answer is that **I could not
reproduce it** — the best scripted player I can write scores about twenty. But
chasing it turned up four real faults, three of them in the half of the game you
never touch:

1. **Team strength had an absurd grip on the opponent's possession.** `edge` was
   `(their strength − yours) × 0.012`, and it was then multiplied by six inside
   the yardage roll *and* added straight onto every outcome threshold. Across the
   eight teams that scaled their yardage anywhere from 6% to 164% of normal. Pick
   the best team in the league against a middling one and the CPU is quietly shut
   out — the margin comes from the team-select screen rather than from anything
   you did with the ball. It is a quarter of the size now, and bounded.

2. **A large enough difficulty bonus made an interception impossible.** The bonus
   was added to the outcome roll and compared against fixed thresholds, so at PRO
   the threshold went negative and the opponent could not throw a pick at all.
   Difficulty now bends each threshold by a fraction of itself instead.

3. **The ball magnet was one-sided.** A receiver breaks off his route for a throw
   in the air from eleven yards away; a defender in man coverage only broke on it
   from nine. A ball thrown at the grass between them was the receiver's by
   arithmetic before anybody ran a step. Same radius for both now.

4. A quarterback who ran out of bounds behind his own line was credited with a
   rush for minus nine rather than being sacked, which was most of the negative
   rushing yardage in games with no run calls.

The final screen now reports **TOUCHDOWNS** and **DRIVES BEGAN** — the average
yard line your possessions started on. Between them and TOTAL YARDS, a scoreline
is self-diagnosing: eight touchdowns from 192 yards means short fields, not a
good passing day, and there was no way to see that from inside the game.

### Two bugs that were control, not simulation

Both were invisible to the automated tests because the tests played with no
thumb on the screen.

**Your thumb drove the other team's returner.** `attacking()` flips on a
turnover, and the code picked the user's player with `attacking(carrier())` —
so the instant you threw a pick, the stick you were holding forward was
driving the man returning it. Your own eleven were chasing correctly the whole
time, which is why the AI test passed; from the player's seat it looked like
nobody was trying. The thumb now always holds one of yours, and gets the man
best placed to make the tackle. `tools/test.js` asserts it, and that assertion
fails on 101 of 101 picks against the build that shipped it.

**The opponent's drive ticker ran the field backwards.** The mini-field in the
"they have the ball" panel drew `y` left-to-right; the actual field draws it
right-to-left, because you attack leftward. So the moment they took possession
the game showed you a field pointing the opposite way to the one you had been
playing on. It now matches, with both goals labelled and a chevron showing
which way they are coming.

**Effects are driven by watching the simulation, never by it.** The renderer
notices a completion, a body hitting the deck or a ball in the air and produces
the catch pose, the turf spray and the trail itself. Nothing in `makePlay` knows
a renderer exists.

**The known weak spot is still the run game near the goal line**, though it is
no longer a brick wall: a short-yardage carry against the goal-line front used
to average −0.8 yards, which meant fourth and one was not convertible at all.
The middle filler now plays a shallow zone instead of a third man in the same
crease, and it averages about zero — stingy, which is the point of the front,
rather than impossible. Which front the CPU calls still dominates the result
far more than it should. `tools/test.js` prints the goal-line spread on every
run so a regression is visible rather than silent.

Also not built: season or team management, penalties, onside kicks, overtime
(a tie stays a tie), and a service worker (Add to Home Screen works, but it
needs the network on first load).
