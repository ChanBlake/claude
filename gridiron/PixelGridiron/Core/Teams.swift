//  Teams.swift
//  Team identities, player positions, and the ratings the simulation reads.

import Foundation

/// An 8-bit-per-channel colour. Core has no UIKit, so palettes live here as raw
/// components and `Palette.swift` in Render/ lifts them into `SKColor`.
struct PixelColor: Equatable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    /// `PixelColor(0x1E90FF)` — convenient for pasting hex out of a palette tool.
    init(_ hex: UInt32) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
    }

    /// Blend toward `other`. Used for the shaded side of a sprite and for the
    /// darker mow stripe on the turf.
    func mixed(with other: PixelColor, _ t: Double) -> PixelColor {
        let f = clamp(t, 0, 1)
        func lerp(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8(clamp(Double(a) + (Double(b) - Double(a)) * f, 0, 255))
        }
        return PixelColor(lerp(r, other.r), lerp(g, other.g), lerp(b, other.b))
    }

    func darkened(_ t: Double) -> PixelColor { mixed(with: PixelColor(0x000000), t) }
    func lightened(_ t: Double) -> PixelColor { mixed(with: PixelColor(0xFFFFFF), t) }

    /// Perceived brightness, 0…1. Drives the automatic choice between dark and
    /// light lettering on an end zone.
    var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
    }
}

/// The seven positions on each side of an arcade 7-on-7 unit.
enum Position: String, CaseIterable, Codable {
    // Offense
    case quarterback = "QB"
    case runningBack = "RB"
    case wideReceiver = "WR"
    case tightEnd = "TE"
    case lineman = "OL"
    // Defense
    case defensiveLine = "DL"
    case linebacker = "LB"
    case cornerback = "CB"
    case safety = "S"
    // Special teams
    case kicker = "K"

    var isOffense: Bool {
        switch self {
        case .quarterback, .runningBack, .wideReceiver, .tightEnd, .lineman, .kicker:
            return true
        default:
            return false
        }
    }

    /// Eligible to catch a forward pass.
    var isReceiver: Bool {
        self == .wideReceiver || self == .tightEnd || self == .runningBack
    }
}

/// Per-player attributes, 0…100, where 50 is a replacement-level arcade player.
///
/// The simulation never reads a rating directly as a speed or a probability — it
/// goes through `Sim.Tuning`, so the whole game can be rebalanced from one file
/// without touching the rosters.
struct Ratings: Codable, Equatable {
    var speed: Double = 50       // top speed
    var accel: Double = 50       // how fast top speed arrives
    var agility: Double = 50     // turn rate, juke effectiveness
    var power: Double = 50       // breaking and shedding
    var hands: Double = 50       // catching, ball security
    var tackling: Double = 50    // bringing the carrier down
    var coverage: Double = 50    // staying attached in coverage
    var blocking: Double = 50    // holding a block
    var awareness: Double = 50   // AI reaction delay, route timing, kick accuracy

    static let average = Ratings()

    /// Every rating shifted by the same amount and re-clamped. Team strength is
    /// applied this way so a "good team" is good everywhere rather than lopsided.
    func shifted(by delta: Double) -> Ratings {
        var r = self
        r.speed = clamp(r.speed + delta, 1, 99)
        r.accel = clamp(r.accel + delta, 1, 99)
        r.agility = clamp(r.agility + delta, 1, 99)
        r.power = clamp(r.power + delta, 1, 99)
        r.hands = clamp(r.hands + delta, 1, 99)
        r.tackling = clamp(r.tackling + delta, 1, 99)
        r.coverage = clamp(r.coverage + delta, 1, 99)
        r.blocking = clamp(r.blocking + delta, 1, 99)
        r.awareness = clamp(r.awareness + delta, 1, 99)
        return r
    }

    /// Baseline profile for a position before team strength and jitter.
    static func baseline(for position: Position) -> Ratings {
        var r = Ratings()
        switch position {
        case .quarterback:
            r.speed = 48; r.accel = 50; r.agility = 52; r.power = 40
            r.hands = 60; r.tackling = 20; r.coverage = 20; r.blocking = 25; r.awareness = 70
        case .runningBack:
            r.speed = 72; r.accel = 74; r.agility = 76; r.power = 62
            r.hands = 58; r.tackling = 30; r.coverage = 25; r.blocking = 40; r.awareness = 55
        case .wideReceiver:
            r.speed = 80; r.accel = 76; r.agility = 72; r.power = 42
            r.hands = 74; r.tackling = 25; r.coverage = 35; r.blocking = 30; r.awareness = 58
        case .tightEnd:
            r.speed = 58; r.accel = 56; r.agility = 50; r.power = 68
            r.hands = 66; r.tackling = 35; r.coverage = 30; r.blocking = 62; r.awareness = 56
        case .lineman:
            r.speed = 34; r.accel = 40; r.agility = 34; r.power = 80
            r.hands = 15; r.tackling = 35; r.coverage = 10; r.blocking = 82; r.awareness = 52
        case .defensiveLine:
            r.speed = 46; r.accel = 56; r.agility = 44; r.power = 82
            r.hands = 25; r.tackling = 72; r.coverage = 18; r.blocking = 30; r.awareness = 54
        case .linebacker:
            r.speed = 62; r.accel = 64; r.agility = 60; r.power = 70
            r.hands = 40; r.tackling = 80; r.coverage = 56; r.blocking = 35; r.awareness = 66
        case .cornerback:
            r.speed = 82; r.accel = 80; r.agility = 78; r.power = 40
            r.hands = 52; r.tackling = 52; r.coverage = 78; r.blocking = 20; r.awareness = 62
        case .safety:
            r.speed = 72; r.accel = 70; r.agility = 66; r.power = 55
            r.hands = 48; r.tackling = 70; r.coverage = 68; r.blocking = 22; r.awareness = 72
        case .kicker:
            r.speed = 40; r.accel = 40; r.agility = 40; r.power = 55
            r.hands = 40; r.tackling = 10; r.coverage = 10; r.blocking = 10; r.awareness = 75
        }
        return r
    }
}

/// Everything cosmetic and competitive about a team, minus the roster.
struct TeamIdentity: Equatable {
    var city: String
    var nickname: String
    var abbreviation: String        // three letters, for the scoreboard
    var jersey: PixelColor
    var trim: PixelColor
    var helmet: PixelColor
    var pants: PixelColor
    var endZone: PixelColor
    /// Applied to every rating on the roster. −8 is a doormat, +8 is a juggernaut.
    var strength: Double

    var fullName: String { "\(city) \(nickname)" }

    /// Lettering that stays readable on this team's end zone paint.
    var endZoneTextColor: PixelColor {
        endZone.luminance > 0.55 ? PixelColor(0x14181C) : PixelColor(0xF2F5F7)
    }
}

/// The eight fictional teams the game ships with.
///
/// All invented — the cities are real places, the clubs are not, and no
/// existing league's marks, names or colour schemes are used.
enum League {
    static let teams: [TeamIdentity] = [
        TeamIdentity(city: "IRONPORT", nickname: "ANCHORS", abbreviation: "IRN",
                     jersey: PixelColor(0x1B3A6B), trim: PixelColor(0xE8B33A),
                     helmet: PixelColor(0x14294C), pants: PixelColor(0xD8DEE6),
                     endZone: PixelColor(0x1B3A6B), strength: 3),

        TeamIdentity(city: "CASCADE", nickname: "TIMBERJACKS", abbreviation: "CSC",
                     jersey: PixelColor(0x1E6B41), trim: PixelColor(0xF0E9D6),
                     helmet: PixelColor(0x3B2A18), pants: PixelColor(0xF0E9D6),
                     endZone: PixelColor(0x1E6B41), strength: 1),

        TeamIdentity(city: "SUNRIDGE", nickname: "SCORPIONS", abbreviation: "SUN",
                     jersey: PixelColor(0xC2451E), trim: PixelColor(0x2B2118),
                     helmet: PixelColor(0xE0812C), pants: PixelColor(0x2B2118),
                     endZone: PixelColor(0xC2451E), strength: 5),

        TeamIdentity(city: "GLASSTOWN", nickname: "VOLTAGE", abbreviation: "GLS",
                     jersey: PixelColor(0x3C2E6B), trim: PixelColor(0x6FE3D2),
                     helmet: PixelColor(0x2A2050), pants: PixelColor(0xC9CEDA),
                     endZone: PixelColor(0x3C2E6B), strength: 7),

        TeamIdentity(city: "MARROW BAY", nickname: "GULLS", abbreviation: "MBY",
                     jersey: PixelColor(0xE3E7EC), trim: PixelColor(0x1E7BA6),
                     helmet: PixelColor(0x1E7BA6), pants: PixelColor(0x1E7BA6),
                     endZone: PixelColor(0x1E7BA6), strength: -1),

        TeamIdentity(city: "DUSTFALL", nickname: "COYOTES", abbreviation: "DST",
                     jersey: PixelColor(0x8A6A3C), trim: PixelColor(0x2F2A24),
                     helmet: PixelColor(0xB89A67), pants: PixelColor(0x2F2A24),
                     endZone: PixelColor(0x8A6A3C), strength: -4),

        TeamIdentity(city: "NORTHGATE", nickname: "SENTINELS", abbreviation: "NGT",
                     jersey: PixelColor(0x1F1F26), trim: PixelColor(0xC0392B),
                     helmet: PixelColor(0x1F1F26), pants: PixelColor(0x8E9199),
                     endZone: PixelColor(0x1F1F26), strength: 6),

        TeamIdentity(city: "HOLLOW CREEK", nickname: "HOUNDS", abbreviation: "HLC",
                     jersey: PixelColor(0x6B1F2E), trim: PixelColor(0xDCC7A1),
                     helmet: PixelColor(0x4A1520), pants: PixelColor(0xDCC7A1),
                     endZone: PixelColor(0x6B1F2E), strength: -2),
    ]

    static func team(named abbreviation: String) -> TeamIdentity? {
        teams.first { $0.abbreviation == abbreviation }
    }
}

/// A roster entry. `id` is stable for the length of a game and is how the
/// simulation, the renderer and the HUD agree on who is who.
struct PlayerProfile: Equatable {
    var id: Int
    var number: Int
    var position: Position
    var ratings: Ratings
    /// Index within the position group — WR 0 is the X, WR 1 is the Z.
    var depth: Int
}

/// A full 7-on-7 roster plus a kicker, generated deterministically from the
/// team's strength and a seed so the same matchup always fields the same players.
struct Roster {
    var offense: [PlayerProfile]
    var defense: [PlayerProfile]
    var kicker: PlayerProfile

    static let offensePositions: [Position] = [
        .quarterback, .runningBack, .wideReceiver, .wideReceiver, .tightEnd, .lineman, .lineman,
    ]
    static let defensePositions: [Position] = [
        .defensiveLine, .defensiveLine, .linebacker, .linebacker, .cornerback, .cornerback, .safety,
    ]

    static func generate(for identity: TeamIdentity, seed: UInt64) -> Roster {
        var rng = RNG(seed: seed)
        var nextID = 0
        var usedNumbers = Set<Int>()

        func makeNumber(for position: Position) -> Int {
            // Loose nods to traditional numbering, without being precious about it.
            let range: ClosedRange<Int>
            switch position {
            case .quarterback: range = 1...19
            case .runningBack: range = 20...39
            case .wideReceiver: range = 80...89
            case .tightEnd: range = 40...49
            case .lineman: range = 60...79
            case .defensiveLine: range = 90...99
            case .linebacker: range = 50...59
            case .cornerback: range = 20...39
            case .safety: range = 20...39
            case .kicker: range = 1...9
            }
            for _ in 0..<40 {
                let n = rng.int(range.lowerBound, range.upperBound)
                if usedNumbers.insert(n).inserted { return n }
            }
            // Exhausted the band — fall back to any free number.
            for n in 0...99 where usedNumbers.insert(n).inserted { return n }
            return 0
        }

        func makeGroup(_ positions: [Position]) -> [PlayerProfile] {
            var depthCounters: [Position: Int] = [:]
            return positions.map { position in
                let depth = depthCounters[position, default: 0]
                depthCounters[position] = depth + 1
                // Team strength plus a small per-player wobble, so even a strong
                // team has someone you can pick on.
                let jitter = rng.bell() * 5.0
                let ratings = Ratings.baseline(for: position)
                    .shifted(by: identity.strength + jitter)
                let profile = PlayerProfile(id: nextID,
                                            number: makeNumber(for: position),
                                            position: position,
                                            ratings: ratings,
                                            depth: depth)
                nextID += 1
                return profile
            }
        }

        let offense = makeGroup(offensePositions)
        let defense = makeGroup(defensePositions)
        let kickerRatings = Ratings.baseline(for: .kicker).shifted(by: identity.strength)
        let kicker = PlayerProfile(id: nextID,
                                   number: makeNumber(for: .kicker),
                                   position: .kicker,
                                   ratings: kickerRatings,
                                   depth: 0)
        return Roster(offense: offense, defense: defense, kicker: kicker)
    }
}
