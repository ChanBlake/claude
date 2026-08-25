//  Playbook.swift
//  Formations, routes and assignments.
//
//  Everything here is expressed in **team-local yards**: `downfield` is positive
//  toward the end zone the offense is attacking, `lateral` is positive toward the
//  north sideline. `Simulation` converts to field coordinates once, at the snap,
//  by multiplying `downfield` by the team's direction.

import Foundation

/// One leg of a route. The receiver runs to `offset` (relative to where it lined
/// up) and then moves on to the next node.
struct RouteNode: Equatable {
    var downfield: Double
    var lateral: Double
    /// Fraction of top speed for this leg. Comebacks and drags are run slower so
    /// the break reads clearly at arcade zoom.
    var speed: Double = 1.0

    init(_ downfield: Double, _ lateral: Double, speed: Double = 1.0) {
        self.downfield = downfield
        self.lateral = lateral
        self.speed = speed
    }
}

/// What an offensive player does after the snap.
enum OffenseAssignment: Equatable {
    /// Drop straight back `depth` yards and look to throw.
    case dropback(depth: Double)
    /// Take the handoff and follow `path`, then run to daylight.
    case carry(path: [RouteNode])
    /// Run a route and become a passing target.
    case route([RouteNode])
    /// Stay in front of the quarterback and absorb rushers.
    case passProtect
    /// Drive toward the play side and hit the first defender there.
    case runBlock(lateralBias: Double)
    /// Sell the block for `delay` seconds, then release into a route (screens).
    case delayedRoute(delay: Double, route: [RouteNode])
}

/// What a defender does after the snap.
enum DefenseAssignment: Equatable {
    /// Attack the quarterback.
    case rush
    /// Attack the quarterback but stay disciplined against the scramble.
    case containRush(lateralSide: Double)
    /// Shadow the offensive player at `offenseIndex`.
    case manCover(offenseIndex: Int)
    /// Drop to a landmark and break on the ball once it is thrown.
    case zone(depth: Double, lateral: Double, radius: Double)
    /// Fill the gap and meet the run; only rushes late.
    case runFill(lateralBias: Double)
    /// Mirror the quarterback, in case he pulls it down.
    case spy
}

enum PlayKind: Equatable {
    case run
    case pass
    case screen
    case punt
    case fieldGoal
    case kneel
    case extraPoint
    case kickoff
}

/// A single offensive call: where the seven line up and what they do.
struct OffensePlay: Equatable {
    var name: String
    /// Two-line description shown on the play-call card.
    var blurb: String
    var kind: PlayKind
    /// Aligned to `Roster.offensePositions`: QB, RB, WR, WR, TE, OL, OL.
    var alignments: [RouteNode]
    var assignments: [OffenseAssignment]
    /// Seconds the AI quarterback will hold the ball before checking it down.
    var developTime: Double
    /// Rough yardage this play wants, used by the CPU play-caller.
    var targetGain: Double

    var isPassPlay: Bool { kind == .pass || kind == .screen }
}

/// A single defensive call.
struct DefensePlay: Equatable {
    var name: String
    var blurb: String
    /// Aligned to `Roster.defensePositions`: DL, DL, LB, LB, CB, CB, S.
    var alignments: [RouteNode]
    var assignments: [DefenseAssignment]
    /// How well this call holds up against the run and the pass, 0…1. The CPU
    /// play-caller and the post-snap "matchup" bonus both read these.
    var runStrength: Double
    var passStrength: Double
}

enum Playbook {

    // MARK: - Offense

    /// Standard alignment: QB under centre, RB behind him, two wideouts split,
    /// tight end on the line, two blockers either side of centre.
    private static let baseSet: [RouteNode] = [
        RouteNode(-1.0, 0.0),    // QB
        RouteNode(-5.5, -0.5),   // RB
        RouteNode(0.0, -11.0),   // WR X (south)
        RouteNode(0.0, 11.0),    // WR Z (north)
        RouteNode(0.0, 4.5),     // TE
        RouteNode(0.0, -2.0),    // OL
        RouteNode(0.0, 2.0),     // OL
    ]

    private static let gunSet: [RouteNode] = [
        RouteNode(-5.0, 0.0),    // QB in the gun
        RouteNode(-5.0, -3.0),   // RB beside him
        RouteNode(0.0, -13.0),   // WR X
        RouteNode(0.0, 13.0),    // WR Z
        RouteNode(0.0, 6.0),     // TE split wide-ish
        RouteNode(0.0, -2.0),    // OL
        RouteNode(0.0, 2.0),     // OL
    ]

    static let dive = OffensePlay(
        name: "HB DIVE",
        blurb: "Straight ahead. Low risk, low reward,\nand the clock keeps running.",
        kind: .run,
        alignments: baseSet,
        assignments: [
            .dropback(depth: 0),
            .carry(path: [RouteNode(1.5, 0.5), RouteNode(6, 0.5)]),
            .route([RouteNode(6, -1, speed: 0.7)]),
            .route([RouteNode(6, 1, speed: 0.7)]),
            .runBlock(lateralBias: 0.5),
            .runBlock(lateralBias: -0.4),
            .runBlock(lateralBias: 0.4),
        ],
        developTime: 0.6,
        targetGain: 4)

    static let sweep = OffensePlay(
        name: "TOSS SWEEP",
        blurb: "Get outside and turn upfield.\nBig if it breaks, ugly if it doesn't.",
        kind: .run,
        alignments: baseSet,
        assignments: [
            .dropback(depth: 0),
            .carry(path: [RouteNode(-2.0, 9.0), RouteNode(1.0, 13.0), RouteNode(10, 14.0)]),
            .route([RouteNode(8, -2, speed: 0.8)]),
            .route([RouteNode(2, 3, speed: 0.9)]),
            .runBlock(lateralBias: 1.0),
            .runBlock(lateralBias: 0.9),
            .runBlock(lateralBias: 0.2),
        ],
        developTime: 1.1,
        targetGain: 6)

    static let slants = OffensePlay(
        name: "QUICK SLANTS",
        blurb: "Three-step drop, throw it now.\nBeats the blitz, moves the chains.",
        kind: .pass,
        alignments: gunSet,
        assignments: [
            .dropback(depth: 3),
            .route([RouteNode(2, 1), RouteNode(8, 6)]),
            .route([RouteNode(3, 0), RouteNode(9, 5)]),
            .route([RouteNode(3, 0), RouteNode(9, -5)]),
            .route([RouteNode(5, 0), RouteNode(6, -6, speed: 0.85)]),
            .passProtect,
            .passProtect,
        ],
        developTime: 1.4,
        targetGain: 7)

    static let verticals = OffensePlay(
        name: "FOUR VERTS",
        blurb: "Everybody deep. Hold the ball,\ntake the shot, wear the sack.",
        kind: .pass,
        alignments: gunSet,
        assignments: [
            .dropback(depth: 6),
            .route([RouteNode(6, -2), RouteNode(22, -3)]),
            .route([RouteNode(14, -1), RouteNode(26, -2)]),
            .route([RouteNode(14, 1), RouteNode(26, 2)]),
            .route([RouteNode(12, 2), RouteNode(24, 4)]),
            .passProtect,
            .passProtect,
        ],
        developTime: 2.6,
        targetGain: 18)

    static let playAction = OffensePlay(
        name: "PLAY ACTION POST",
        blurb: "Fake the dive, then go over the top.\nSlow to develop — hope the line holds.",
        kind: .pass,
        alignments: baseSet,
        assignments: [
            .dropback(depth: 7),
            .delayedRoute(delay: 0.9, route: [RouteNode(3, -4), RouteNode(9, -8)]),
            .route([RouteNode(16, 0), RouteNode(28, 7)]),
            .route([RouteNode(10, 1), RouteNode(11, 9, speed: 0.9)]),
            .route([RouteNode(7, 1), RouteNode(8, -5, speed: 0.85)]),
            .passProtect,
            .passProtect,
        ],
        developTime: 3.0,
        targetGain: 20)

    static let screen = OffensePlay(
        name: "HALFBACK SCREEN",
        blurb: "Let them come, then dump it off\nbehind the rush. Punishes a blitz.",
        kind: .screen,
        alignments: gunSet,
        assignments: [
            .dropback(depth: 5),
            .delayedRoute(delay: 0.7, route: [RouteNode(-1, -6), RouteNode(0, -9)]),
            .route([RouteNode(12, -1)]),
            .route([RouteNode(12, 1)]),
            .route([RouteNode(9, 3)]),
            .delayedRoute(delay: 0.8, route: [RouteNode(1, -7), RouteNode(6, -9)]),
            .passProtect,
        ],
        developTime: 1.9,
        targetGain: 9)

    /// Offered on the last play of a half when only a touchdown will do.
    static let hailMary = OffensePlay(
        name: "HAIL MARY",
        blurb: "One throw, everybody in the end zone.\nIt is not a good play. It is the only play.",
        kind: .pass,
        alignments: gunSet,
        assignments: [
            .dropback(depth: 8),
            .route([RouteNode(20, -6), RouteNode(45, -8)]),
            .route([RouteNode(24, -2), RouteNode(48, -3)]),
            .route([RouteNode(24, 2), RouteNode(48, 3)]),
            .route([RouteNode(22, 5), RouteNode(46, 8)]),
            .passProtect,
            .passProtect,
        ],
        developTime: 3.4,
        targetGain: 40)

    /// Kneel-down. Ends the play immediately and burns clock.
    static let kneel = OffensePlay(
        name: "KNEEL DOWN",
        blurb: "Take the knee. Burn the clock.\nThe lead is the only thing that matters.",
        kind: .kneel,
        alignments: gunSet,
        assignments: [
            .dropback(depth: 2),
            .passProtect, .passProtect, .passProtect,
            .passProtect, .passProtect, .passProtect,
        ],
        developTime: 0.1,
        targetGain: -1)

    static let punt = OffensePlay(
        name: "PUNT",
        blurb: "Flip the field and play defence.",
        kind: .punt,
        alignments: [
            RouteNode(-12.0, 0.0),   // punter
            RouteNode(-2.0, -4.0),
            RouteNode(0.0, -13.0),
            RouteNode(0.0, 13.0),
            RouteNode(0.0, 5.0),
            RouteNode(0.0, -2.5),
            RouteNode(0.0, 2.5),
        ],
        assignments: [
            .dropback(depth: 0),
            .passProtect, .route([RouteNode(35, -6)]), .route([RouteNode(35, 6)]),
            .passProtect, .passProtect, .passProtect,
        ],
        developTime: 1.2,
        targetGain: 0)

    static let fieldGoal = OffensePlay(
        name: "FIELD GOAL",
        blurb: "Three points, if the meter cooperates.",
        kind: .fieldGoal,
        alignments: [
            RouteNode(-7.0, 0.0),    // holder
            RouteNode(-8.0, -1.5),   // kicker
            RouteNode(0.0, -7.0),
            RouteNode(0.0, 7.0),
            RouteNode(0.0, 4.5),
            RouteNode(0.0, -2.5),
            RouteNode(0.0, 2.5),
        ],
        assignments: [
            .dropback(depth: 0), .passProtect, .passProtect, .passProtect,
            .passProtect, .passProtect, .passProtect,
        ],
        developTime: 1.3,
        targetGain: 0)

    static let kickoff = OffensePlay(
        name: "KICKOFF",
        blurb: "Boot it deep and go cover it.",
        kind: .kickoff,
        alignments: [
            RouteNode(0.0, 0.0),
            RouteNode(-3.0, -9.0), RouteNode(-3.0, -5.0), RouteNode(-3.0, 5.0),
            RouteNode(-3.0, 9.0), RouteNode(-3.0, -13.0), RouteNode(-3.0, 13.0),
        ],
        assignments: [
            .dropback(depth: 0),
            .route([RouteNode(60, -6)]), .route([RouteNode(60, -2)]),
            .route([RouteNode(60, 2)]), .route([RouteNode(60, 6)]),
            .route([RouteNode(60, -10)]), .route([RouteNode(60, 10)]),
        ],
        developTime: 0.6,
        targetGain: 0)

    static let kickReturn = DefensePlay(
        name: "KICK RETURN",
        blurb: "Catch it, wedge left, go.",
        alignments: [
            RouteNode(30.0, -12.0), RouteNode(30.0, 12.0),
            RouteNode(40.0, -6.0), RouteNode(40.0, 6.0),
            RouteNode(50.0, -3.0), RouteNode(50.0, 3.0),
            RouteNode(62.0, 0.0),
        ],
        assignments: [
            .runFill(lateralBias: -1), .runFill(lateralBias: 1),
            .runFill(lateralBias: -0.5), .runFill(lateralBias: 0.5),
            .runFill(lateralBias: -0.2), .runFill(lateralBias: 0.2),
            .spy,
        ],
        runStrength: 0.5,
        passStrength: 0.5)

    /// The six plays a human picks between on a normal down.
    static let offenseCalls: [OffensePlay] = [dive, sweep, slants, verticals, playAction, screen]

    // MARK: - Defense

    /// Alignments are relative to the ball, in the *defence's* frame — so
    /// `downfield` positive is toward the offence's end zone, which for a
    /// defender means backpedalling territory.
    private static let baseFront: [RouteNode] = [
        RouteNode(1.5, -2.5),    // DL
        RouteNode(1.5, 2.5),     // DL
        RouteNode(5.0, -5.0),    // LB
        RouteNode(5.0, 5.0),     // LB
        RouteNode(7.0, -11.0),   // CB
        RouteNode(7.0, 11.0),    // CB
        RouteNode(13.0, 0.0),    // S
    ]

    static let runStuff = DefensePlay(
        name: "GOAL LINE",
        blurb: "Everyone in the box. Nothing runs.\nAnything thrown is a problem.",
        alignments: [
            RouteNode(1.0, -3.0), RouteNode(1.0, 3.0),
            RouteNode(3.0, -6.0), RouteNode(3.0, 6.0),
            RouteNode(5.0, -10.0), RouteNode(5.0, 10.0),
            RouteNode(7.0, 0.0),
        ],
        assignments: [
            .rush, .rush,
            .runFill(lateralBias: -1), .runFill(lateralBias: 1),
            .manCover(offenseIndex: 2), .manCover(offenseIndex: 3),
            .runFill(lateralBias: 0),
        ],
        runStrength: 0.92,
        passStrength: 0.30)

    static let balanced = DefensePlay(
        name: "BASE DEFENSE",
        blurb: "No holes, no heroes.\nGood enough against everything.",
        alignments: baseFront,
        assignments: [
            .rush, .containRush(lateralSide: 1),
            .runFill(lateralBias: -0.6), .zone(depth: 9, lateral: 5, radius: 8),
            .manCover(offenseIndex: 2), .manCover(offenseIndex: 3),
            .zone(depth: 16, lateral: 0, radius: 13),
        ],
        runStrength: 0.62,
        passStrength: 0.62)

    static let manBlitz = DefensePlay(
        name: "MAN BLITZ",
        blurb: "Send five, cover the rest alone.\nSack or six.",
        alignments: [
            RouteNode(1.5, -3.0), RouteNode(1.5, 3.0),
            RouteNode(3.0, -6.5), RouteNode(3.0, 6.5),
            RouteNode(6.0, -11.0), RouteNode(6.0, 11.0),
            RouteNode(10.0, 3.0),
        ],
        assignments: [
            .rush, .rush,
            .rush, .rush,
            .manCover(offenseIndex: 2), .manCover(offenseIndex: 3),
            .manCover(offenseIndex: 4),
        ],
        runStrength: 0.48,
        passStrength: 0.45)

    static let coverTwo = DefensePlay(
        name: "COVER TWO",
        blurb: "Two safeties over the top.\nUnderneath is yours — take it.",
        alignments: [
            RouteNode(1.5, -2.5), RouteNode(1.5, 2.5),
            RouteNode(7.0, -7.0), RouteNode(7.0, 7.0),
            RouteNode(5.0, -12.0), RouteNode(5.0, 12.0),
            RouteNode(15.0, 0.0),
        ],
        assignments: [
            .rush, .containRush(lateralSide: -1),
            .zone(depth: 10, lateral: -7, radius: 9),
            .zone(depth: 10, lateral: 7, radius: 9),
            .zone(depth: 6, lateral: -13, radius: 8),
            .zone(depth: 6, lateral: 13, radius: 8),
            .zone(depth: 19, lateral: 0, radius: 16),
        ],
        runStrength: 0.45,
        passStrength: 0.78)

    static let prevent = DefensePlay(
        name: "PREVENT",
        blurb: "Give up the short stuff, guard the end zone.\nOnly sane when the clock is your friend.",
        alignments: [
            RouteNode(1.5, -2.0), RouteNode(1.5, 2.0),
            RouteNode(12.0, -9.0), RouteNode(12.0, 9.0),
            RouteNode(16.0, -14.0), RouteNode(16.0, 14.0),
            RouteNode(24.0, 0.0),
        ],
        assignments: [
            .rush, .spy,
            .zone(depth: 16, lateral: -10, radius: 11),
            .zone(depth: 16, lateral: 10, radius: 11),
            .zone(depth: 24, lateral: -13, radius: 13),
            .zone(depth: 24, lateral: 13, radius: 13),
            .zone(depth: 32, lateral: 0, radius: 20),
        ],
        runStrength: 0.22,
        passStrength: 0.88)

    static let defenseCalls: [DefensePlay] = [runStuff, balanced, manBlitz, coverTwo, prevent]

    /// Punt and field-goal return units — the defence's answer to special teams.
    static let puntReturn = DefensePlay(
        name: "PUNT RETURN",
        blurb: "Field it and find a crease.",
        alignments: [
            RouteNode(2.0, -4.0), RouteNode(2.0, 4.0),
            RouteNode(6.0, -8.0), RouteNode(6.0, 8.0),
            RouteNode(20.0, -10.0), RouteNode(20.0, 10.0),
            RouteNode(42.0, 0.0),
        ],
        assignments: [
            .rush, .rush,
            .runFill(lateralBias: -1), .runFill(lateralBias: 1),
            .runFill(lateralBias: -0.5), .runFill(lateralBias: 0.5),
            .spy,
        ],
        runStrength: 0.5,
        passStrength: 0.5)

    static let fieldGoalBlock = DefensePlay(
        name: "BLOCK ATTEMPT",
        blurb: "Get a hand up.",
        alignments: [
            RouteNode(1.0, -3.0), RouteNode(1.0, 3.0),
            RouteNode(1.0, -6.0), RouteNode(1.0, 6.0),
            RouteNode(2.0, -9.0), RouteNode(2.0, 9.0),
            RouteNode(6.0, 0.0),
        ],
        assignments: [.rush, .rush, .rush, .rush, .rush, .rush, .spy],
        runStrength: 0.5,
        passStrength: 0.5)
}
