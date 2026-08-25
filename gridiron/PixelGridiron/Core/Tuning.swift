//  Tuning.swift
//  Every number that decides how the game feels, in one place.
//
//  Nothing in Simulation.swift hard-codes a speed, a radius or a probability —
//  it all comes from here. Rebalancing the game means editing this file and
//  re-running the simulation tests, not hunting through the AI.

import Foundation

enum Tuning {

    // MARK: - Movement

    /// Top speed in yards per second at rating 0 and rating 99.
    static let speedFloor: Double = 4.2
    static let speedCeiling: Double = 9.6
    /// Acceleration in yards per second squared at rating 0 and rating 99.
    static let accelFloor: Double = 11.0
    static let accelCeiling: Double = 26.0
    /// How sharply a player can change direction, in radians per second.
    static let turnFloor: Double = 4.5
    static let turnCeiling: Double = 11.0
    /// Friction applied when a player has no steering input.
    static let idleDamping: Double = 7.0

    /// Sprint multiplies top speed and drains the stamina bar.
    static let sprintMultiplier: Double = 1.16
    static let sprintDrainPerSecond: Double = 0.34
    static let sprintRecoverPerSecond: Double = 0.22
    /// Below this, sprint stops working until the bar refills past `sprintUnlock`.
    static let sprintExhausted: Double = 0.02
    static let sprintUnlock: Double = 0.25

    // MARK: - Contact

    /// A defender inside this radius of the ball carrier can attempt a tackle.
    static let tackleRadius: Double = 1.25
    /// A dive extends reach but commits the defender.
    static let diveRadius: Double = 2.4
    static let diveDuration: Double = 0.55
    static let diveRecovery: Double = 0.85
    static let diveSpeedMultiplier: Double = 1.45

    /// Base chance a tackle attempt succeeds, before ratings.
    static let tackleBaseChance: Double = 0.55
    /// Each point of (tackling − power) moves the odds by this much.
    static let tackleRatingWeight: Double = 0.0055
    /// A carrier at full sprint is harder to bring down.
    static let tackleSprintPenalty: Double = 0.10
    /// A defender meeting the carrier head-on gets a bonus; chasing from behind
    /// gets a penalty. Scaled by the dot product of the two facings.
    static let tackleAngleWeight: Double = 0.16

    /// After a broken tackle the carrier is slowed and the defender stumbles.
    static let brokenTackleCarrierSlow: Double = 0.55
    static let brokenTackleCarrierSlowTime: Double = 0.35
    static let brokenTackleStumbleTime: Double = 0.75
    /// A carrier can only break so many in a row before he goes down.
    static let maxBrokenTackles: Int = 3

    /// Chance of a fumble on a successful tackle, before ratings.
    static let fumbleBaseChance: Double = 0.022
    /// Each point of (tackler power − carrier hands) moves it by this much.
    static let fumbleRatingWeight: Double = 0.0006
    /// A quarterback sacked while winding up is the likeliest fumble in the game.
    static let sackFumbleMultiplier: Double = 2.1
    /// How long a loose ball stays live before it is whistled dead.
    static let looseBallDuration: Double = 1.6
    static let recoveryRadius: Double = 0.9

    // MARK: - Blocking

    /// Distance at which a blocker latches onto a rusher.
    static let engageRadius: Double = 1.15
    /// Distance beyond which an engagement breaks on its own.
    static let disengageRadius: Double = 2.2
    /// While engaged, both players move at this fraction of top speed.
    static let engagedSpeedMultiplier: Double = 0.22
    /// Shed progress needed to break free.
    static let shedThreshold: Double = 1.0
    /// Shed accrued per second at equal ratings, and the swing per rating point.
    static let shedBaseRate: Double = 0.42
    static let shedRatingWeight: Double = 0.011
    /// A shed rusher is briefly unblockable so he actually gets through.
    static let shedImmunityTime: Double = 0.5
    /// How far ahead of a rusher a blocker tries to place himself.
    static let blockInterceptLead: Double = 0.9

    // MARK: - Passing

    /// Yards per second a thrown ball travels, before arm strength.
    static let passSpeedBase: Double = 17.0
    static let passSpeedPerPower: Double = 0.075
    /// Minimum and maximum time a ball can be in the air.
    static let passFlightMin: Double = 0.28
    static let passFlightMax: Double = 2.6
    /// Height of the arc at its apex, in yards, per yard of horizontal distance.
    static let passArcRatio: Double = 0.16
    static let passArcMax: Double = 5.0

    /// How far ahead of the receiver the quarterback leads the throw.
    static let passLeadFactor: Double = 0.9
    /// Scatter, in yards, added to the landing spot. Scales down with awareness
    /// and up with pressure.
    static let passScatterBase: Double = 1.9
    static let passScatterPressure: Double = 2.6
    /// A defender within this distance of the quarterback counts as pressure.
    static let pressureRadius: Double = 2.0

    /// A pass can be caught by anyone within this radius of the landing spot.
    static let catchRadius: Double = 1.7
    /// Base chance the intended receiver hangs on to an uncontested ball.
    static let catchBaseChance: Double = 0.93
    static let catchRatingWeight: Double = 0.004
    /// When a defender is closer than the receiver, this is the chance the pass
    /// is picked rather than merely broken up.
    static let interceptShare: Double = 0.42
    static let interceptRatingWeight: Double = 0.005

    /// Quarterback must be behind the line of scrimmage to throw.
    static let throwWindup: Double = 0.22

    // MARK: - Kicking

    /// Range of a field goal at kicker power 0 and 99, in yards from the posts.
    static let kickRangeFloor: Double = 38
    static let kickRangeCeiling: Double = 62
    /// Half-width of the "perfect" band on the accuracy meter, 0…1.
    static let kickAccuracySweetSpot: Double = 0.055
    /// Yards the ball drifts sideways per unit of accuracy error, at 40 yards.
    static let kickDriftPerError: Double = 26.0
    /// Chance a kick is blocked when a rusher is unblocked at the snap.
    static let kickBlockChance: Double = 0.12

    static let puntHangTimeBase: Double = 3.4
    static let puntDistanceFloor: Double = 30
    static let puntDistanceCeiling: Double = 56
    static let kickoffDistanceFloor: Double = 52
    static let kickoffDistanceCeiling: Double = 72

    // MARK: - AI

    /// Reaction delay in seconds at awareness 99 and awareness 0.
    static let reactionFast: Double = 0.10
    static let reactionSlow: Double = 0.42
    /// How far a man defender plays off his receiver, in yards.
    static let coverageCushion: Double = 1.4
    /// How far a defender projects the carrier's position when taking a pursuit
    /// angle, in seconds.
    static let pursuitLookahead: Double = 0.45
    /// Radius a ball carrier "feels" defenders inside when picking a lane.
    static let carrierAvoidRadius: Double = 6.0
    static let carrierAvoidWeight: Double = 1.6
    /// The CPU quarterback throws to the best available option once the play has
    /// developed, and checks down after this long.
    static let qbPanicTime: Double = 1.2
    /// A CPU quarterback scrambles when pressure gets this close.
    static let qbScrambleRadius: Double = 1.6

    // MARK: - Play flow

    /// Longest a single play can run before it is whistled dead — a backstop
    /// against a carrier who somehow never gets touched.
    static let maxPlayDuration: Double = 22.0
    /// Seconds of game clock burned per second of live play. The whole game runs
    /// at this multiple so a four-minute quarter is a real quarter's worth of
    /// snaps rather than a slideshow.
    static let clockSpeed: Double = 1.9
    /// Extra clock burned between snaps when the clock is running.
    static let huddleSeconds: Double = 6.0
    /// Length of the presnap window before the ball is snapped automatically.
    static let presnapTimeout: Double = 6.0
    /// How long a result banner stays up before the next play call.
    static let deadBallSeconds: Double = 1.9

    // MARK: - Derived helpers

    /// Maps a 0…99 rating onto `[floor, ceiling]`.
    static func scaled(_ rating: Double, _ floor: Double, _ ceiling: Double) -> Double {
        floor + (ceiling - floor) * clamp(rating, 0, 99) / 99.0
    }

    static func topSpeed(_ r: Ratings) -> Double { scaled(r.speed, speedFloor, speedCeiling) }
    static func acceleration(_ r: Ratings) -> Double { scaled(r.accel, accelFloor, accelCeiling) }
    static func turnRate(_ r: Ratings) -> Double { scaled(r.agility, turnFloor, turnCeiling) }
    static func reaction(_ r: Ratings) -> Double { scaled(99 - r.awareness, reactionFast, reactionSlow) }
}
