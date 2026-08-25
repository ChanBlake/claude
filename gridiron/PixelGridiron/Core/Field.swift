//  Field.swift
//  Field geometry and the yard-line vocabulary the rest of the game speaks.

import Foundation

/// Field coordinates, in yards.
///
///     x: 0 ............ 10 ................................ 110 .......... 120
///        |  home end zone |          100 yards of play        | away end zone |
///        back line     home goal                          away goal      back line
///
///     y: 0 = south sideline, `Field.width` = north sideline
///
/// The **home** team defends the low-x end zone and drives toward high x.
/// The **away** team does the opposite. `Team.direction` is +1 or -1 accordingly.
enum Field {
    /// Playing surface between the goal lines.
    static let playLength: Double = 100
    /// Depth of each end zone.
    static let endZoneDepth: Double = 10
    /// Total length including both end zones.
    static let totalLength: Double = playLength + endZoneDepth * 2   // 120

    /// Arcade-narrowed from the regulation 53⅓ yards. At the zoom this game
    /// renders at, a regulation width puts both sidelines off-screen and the
    /// play stops reading; 40 yards keeps nearly the whole width visible.
    static let width: Double = 40

    static let southSideline: Double = 0
    static let northSideline: Double = width
    static let midfieldY: Double = width / 2

    static let homeGoalLine: Double = endZoneDepth          // 10
    static let awayGoalLine: Double = endZoneDepth + playLength  // 110
    static let midfieldX: Double = totalLength / 2          // 60

    /// Hash marks, where the ball is spotted when a play ends near a sideline.
    static let southHash: Double = width / 2 - 3.0
    static let northHash: Double = width / 2 + 3.0

    /// Goalposts sit on the back line of each end zone, `uprightWidth` apart.
    static let uprightWidth: Double = 6.2
    static let uprightHeight: Double = 10.0
    static let crossbarHeight: Double = 3.33

    /// Clamps a position to the playing surface, end zones included.
    static func clampToField(_ p: Vec2) -> Vec2 {
        Vec2(clamp(p.x, 0, totalLength), clamp(p.y, southSideline, northSideline))
    }

    static func isOutOfBounds(_ p: Vec2) -> Bool {
        p.y <= southSideline || p.y >= northSideline || p.x <= 0 || p.x >= totalLength
    }

    /// Spot for the next snap: on a hash if the play died near a sideline,
    /// otherwise where it died.
    static func hashSpot(for y: Double) -> Double {
        if y < southHash { return southHash }
        if y > northHash { return northHash }
        return y
    }

    /// Converts an absolute x to the broadcast phrasing — "OWN 34", "OPP 12",
    /// "MIDFIELD" — from the point of view of the team driving in `direction`.
    static func yardLineLabel(x: Double, direction: Int) -> String {
        let clamped = clamp(x, 0, totalLength)
        // Distance from the goal line this team is attacking.
        let toGoal = direction > 0 ? (awayGoalLine - clamped) : (clamped - homeGoalLine)
        if toGoal <= 0 { return "GOAL" }
        if toGoal >= playLength { return "OWN GOAL" }
        let yardLine = toGoal > 50 ? Int((playLength - toGoal).rounded()) : Int(toGoal.rounded())
        if yardLine == 50 { return "MIDFIELD" }
        return (toGoal > 50 ? "OWN " : "OPP ") + String(yardLine)
    }

    /// The number painted on the field at absolute x — 10, 20, …, 50, …, 20, 10.
    /// Returns nil between the marked lines and inside the end zones.
    static func paintedNumber(atX x: Double) -> Int? {
        let fromHomeGoal = x - homeGoalLine
        guard fromHomeGoal >= 10, fromHomeGoal <= 90 else { return nil }
        let rounded = (fromHomeGoal / 10).rounded()
        guard abs(fromHomeGoal - rounded * 10) < 0.01 else { return nil }
        let n = Int(rounded) * 10
        return n > 50 ? 100 - n : n
    }

    /// Yards from `x` to the goal line the team driving in `direction` attacks.
    static func yardsToGoal(from x: Double, direction: Int) -> Double {
        direction > 0 ? (awayGoalLine - x) : (x - homeGoalLine)
    }

    /// x of the goal line a team attacks / defends.
    static func attackingGoalLine(direction: Int) -> Double {
        direction > 0 ? awayGoalLine : homeGoalLine
    }

    static func defendingGoalLine(direction: Int) -> Double {
        direction > 0 ? homeGoalLine : awayGoalLine
    }

    /// x of the back line of the end zone a team attacks — where its goalposts sit.
    static func attackingBackLine(direction: Int) -> Double {
        direction > 0 ? totalLength : 0
    }

    /// Did a ball carrier at `p` cross the goal line it was attacking?
    static func brokeThePlane(_ p: Vec2, direction: Int) -> Bool {
        direction > 0 ? p.x >= awayGoalLine : p.x <= homeGoalLine
    }

    /// Is `p` inside the end zone the team driving in `direction` is defending?
    /// (A ball carrier tackled here is a safety.)
    static func inOwnEndZone(_ p: Vec2, direction: Int) -> Bool {
        direction > 0 ? p.x < homeGoalLine : p.x > awayGoalLine
    }
}
