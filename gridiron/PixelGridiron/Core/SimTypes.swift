//  SimTypes.swift
//  The moving parts of a single play: players, the ball, and the input that
//  drives whichever player the human is holding.

import Foundation

/// What a player is doing right now. Drives both physics and which sprite frame
/// the renderer picks.
enum PlayerMotion: Equatable {
    case set            // pre-snap, feet planted
    case running
    case engaged        // locked up in a block
    case diving         // committed lunge (tackle attempt or a carrier's dive)
    case stumbling      // lost balance after a broken tackle or a shed
    case down           // play over for this player
    case celebrating
}

/// One of the fourteen players on the field.
struct SimPlayer {
    var id: Int
    var profile: PlayerProfile
    var side: TeamSide
    var isOffense: Bool
    /// Index within its unit (0…6), matching `Roster.offensePositions` order.
    var unitIndex: Int

    var pos: Vec2
    var vel: Vec2 = .zero
    /// Facing in radians. Lags velocity by `Tuning.turnRate` so turns read.
    var facing: Double = 0

    var motion: PlayerMotion = .set
    var motionTimer: Double = 0

    var stamina: Double = 1.0
    var isSprinting: Bool = false

    var offenseAssignment: OffenseAssignment?
    var defenseAssignment: DefenseAssignment?

    /// Absolute field targets derived from the route at the snap.
    var routeTargets: [Vec2] = []
    var routeIndex: Int = 0
    var routeSpeed: Double = 1.0
    /// Counts down before a delayed route releases, or before an AI reacts.
    var delayTimer: Double = 0

    /// The player this one is locked up with, if any.
    var engagedWith: Int?
    var shedProgress: Double = 0
    var shedImmunity: Double = 0

    var hasBall: Bool = false
    var brokenTackles: Int = 0
    var slowUntil: Double = 0
    var slowFactor: Double = 1.0

    /// Set for the single player the human is steering.
    var isUserControlled: Bool = false

    /// Where this player started the play. Routes are relative to it.
    var origin: Vec2 = .zero

    var ratings: Ratings { profile.ratings }
    var position: Position { profile.position }

    /// Effective top speed after sprint, stamina and any slow effect.
    func topSpeed(at time: Double) -> Double {
        var s = Tuning.topSpeed(ratings)
        if isSprinting && stamina > Tuning.sprintExhausted { s *= Tuning.sprintMultiplier }
        if time < slowUntil { s *= slowFactor }
        switch motion {
        case .engaged: s *= Tuning.engagedSpeedMultiplier
        case .stumbling: s *= 0.25
        case .down, .set, .celebrating: s = 0
        case .diving: s *= Tuning.diveSpeedMultiplier
        case .running: break
        }
        return s
    }

    var canBeSteered: Bool {
        motion == .running || motion == .engaged
    }
}

/// A ball in flight — a forward pass, a punt, a kickoff, or a field goal.
struct BallFlight {
    var from: Vec2
    var to: Vec2
    var elapsed: Double = 0
    var duration: Double
    /// Apex height in yards; the renderer lifts the sprite by the parabola.
    var apex: Double
    var thrownBy: Int
    /// The intended receiver, if this is a pass.
    var intendedID: Int?
    var isKick: Bool = false
    /// Set for kicks that are aimed at the uprights rather than at a player.
    var isFieldGoal: Bool = false

    var progress: Double { duration <= 0 ? 1 : clamp(elapsed / duration, 0, 1) }

    var currentPosition: Vec2 {
        Vec2.lerp(from, to, progress)
    }

    /// Height above the turf, in yards, at the current point of the flight.
    var currentHeight: Double {
        let t = progress
        return apex * 4 * t * (1 - t)
    }

    var hasLanded: Bool { elapsed >= duration }
}

/// Where the ball is.
enum BallLocation {
    case held(playerID: Int)
    case flight(BallFlight)
    /// On the ground and live, with a countdown before the whistle.
    case loose(position: Vec2, velocity: Vec2, timer: Double)
    case dead(position: Vec2)

    var isLive: Bool {
        if case .dead = self { return false }
        return true
    }
}

/// One frame of human input, in **field space** — the scene has already rotated
/// the on-screen stick into field coordinates, so the simulation never learns
/// which way the camera is pointing.
struct PlayInput {
    /// Desired direction, length 0…1.
    var stick: Vec2 = .zero
    var sprint: Bool = false
    /// Rising edge of the primary action: juke on offence, switch on defence.
    var actionPressed: Bool = false
    /// Rising edge of the secondary action: dive on offence, tackle on defence.
    var divePressed: Bool = false
    /// Rising edge of "throw to the receiver in this slot", 0…2.
    var passTargetSlot: Int?
    /// Rising edge of the snap.
    var snapPressed: Bool = false

    static let none = PlayInput()
}

/// How a play is being set up. The scene builds one of these and hands it to
/// `PlaySimulation`.
struct PlaySetup {
    var offense: TeamSide
    var direction: Int
    var lineOfScrimmage: Double
    var ballY: Double
    var offensePlay: OffensePlay
    var defensePlay: DefensePlay
    var offenseRoster: Roster
    var defenseRoster: Roster
    /// Which side the human is playing. `nil` means CPU vs CPU (attract mode).
    var userSide: TeamSide?
    var seed: UInt64
    /// Used by the kick meter; `nil` for a normal snap.
    var kickPower: Double?
    var kickAccuracy: Double?
    /// True when this play is a two-point conversion rather than a normal down.
    var isTwoPointTry: Bool = false
}

/// Live, per-frame information the HUD and camera need while a play runs.
struct PlaySnapshot {
    var players: [SimPlayer]
    var ball: BallLocation
    var ballPosition: Vec2
    var ballHeight: Double
    var elapsed: Double
    var lineOfScrimmage: Double
    var lineToGain: Double
    var userPlayerID: Int?
    /// Receiver ids in pass-button order, or empty when passing is not available.
    var passOptions: [Int]
    var isFinished: Bool
}
