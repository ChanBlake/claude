# DRIFT — where it actually stands

You asked how to make this better. Here's my honest read, in the order I'd do it.

## The headline

**The engineering is well ahead of the design.** DRIFT has a solvability prover, a cargo
push-solver, a shortcut detector, a loadout-necessity audit, a composer, a secret-finder,
CI, and a one-command build. What it does not have is evidence that any of it is *fun*.

That imbalance is my fault and it's worth naming plainly. Every time you found a problem,
I built a tool so that class of problem couldn't recur. Those tools are genuinely useful —
they caught six unsolvable sectors and a skip that made three-stage levels into corridors.
But correctness tooling has a ceiling, and DRIFT has hit it. Nothing I can write will tell
you whether sector 17 is satisfying or exhausting.

## 1. Cut before you add — this is the big one

This is the recommendation I'd push hardest, and it partly undoes what you last asked for.

Expanding every sector to three stages made the game 69 screens. But several of those
third stages were **composed, not designed** — I mirrored proven geometry or wrote a
variation on the same beat, then let the verifier confirm it was solvable. Solvable is not
the same as worth playing. A stage that repeats the previous stage's idea at a different
angle is padding, and padding is worse than a shorter game because it teaches players that
your levels don't respect their time.

My guess at the offenders, based on how they were built: the third stages of **Ceiling,
Inversion, Null Lock, Undertow, Polarity, Alternator**. Each is "the same mechanic again,
slightly rearranged."

The test for keeping a stage: *does it ask a question the previous stage didn't?* If not,
cut it. 18 sharp sectors beat 24 padded ones, and cutting is two lines in `compose.py`.

I'd rather tell you this than let you ship length you didn't need.

## 2. Playtest with the heatmap — everything else depends on it

`tools/heatmap.html` is new and it's the most valuable thing in this update. The game now
records where you die, how long each sector takes against par, where you stall for 25
seconds without touching anything, and which cores never get found. Settings → Export
playtest data, paste it in.

It names two failure shapes the verifier structurally cannot see:

- **Spiky** — lots of deaths, fast clear. Usually one jump that reads as possible but
  isn't. Fixable with a tile.
- **Unclear** — stalls without deaths. The player doesn't know what the level wants. That's
  a communication failure, and after Zone I there's no hint to lean on, so it's the risk
  the quiet HUD introduced.

It also reports where a run *stopped*, which is the single most useful number you can get.
Watch three people play. Where they hesitate tells you more than where they die.

## 3. Give the zones distinct identities

Right now all four zones look the same and differ only by a drone pitch. Zone III is
called Core Housing and Zone IV is the open void — they should not read identically. This
is cheap: a per-zone background tint and star density, maybe a different hull palette.
Twenty minutes of work for a large perceived-quality jump, and it makes progress *feel*
like progress.

## 4. Controller support

Steam users expect it, the Gamepad API is about a day's work, and the game's inputs are
simple enough that it's nearly mechanical. This is the largest gap between "good browser
game" and "credible paid release."

## 5. Make cores mean something

48 cores exist and collecting them all does nothing but change a number. Options, cheapest
first: a per-zone gate ("6 cores opens the Zone IV shortcut"), an end-screen rank, or a
bonus sector that only unlocks at 48. Right now the incentive is completionism alone,
which reaches a narrow audience.

## 6. Things I'd deliberately not do yet

- **More mechanics.** Seven is plenty; several aren't fully mined. Phase lattice and
  drop-through plating barely combine with rewind anywhere.
- **A story.** The zone logs are enough texture. A narrative layer on an unproven core is
  effort in the wrong place.
- **Shrinking the build with Tauri.** 90MB is unremarkable on Steam. Don't take on a Rust
  toolchain to save megabytes nobody counts.

## Known weaknesses in my own tooling

Since you'll be relying on these, you should know where they're soft:

- **The verifier doesn't model rewind.** It governs the return trip, not reachability. A
  sector could in principle require a rewind that isn't possible and pass.
- **It doesn't model ferry timing.** Sweeps are treated as fully swept.
- **It treats plating as permanently solid** — stricter than the runtime, deliberately, so
  no route depends on the floor giving way. Two sectors grew explicit openings because of
  this.
- **The shortcut check is heuristic.** It measures forced vertical travel between stage
  seams and exempts sectors gated by a door or lattice, because it can't see those gates.
  A sector could be skippable in a way it doesn't model.
- **My row-capped skip measurement is unreliable** and I left it out of the shipped
  verifier: capping which rows the player may use also blocks falling, so the simulated
  player hovers. It reported Event Horizon as skippable, which is an artifact.

## One bug worth flagging

While adding telemetry I found that the multi-core change from the previous session had
never actually applied — a script threw before writing and I reported success from the
wrong signal. Collecting the *first* core in a sector was marking it fully looted, so half
the collectibles were pointless. Fixed, and the HUD now reads `◆ 1/2 CORES`.

That's a good argument for the heatmap over my assurances: it would have shown you cores
being "collected" at an impossible rate.

## If you only do one thing

Play sectors 1 through 24 in one sitting, export the data, and open the heatmap. Then cut
the stages that didn't earn their place. Everything above matters less than that.
