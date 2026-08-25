//  Persistence.swift
//  Settings and records, kept in UserDefaults.
//
//  Nothing here is worth a database. What it is worth is being impossible to
//  corrupt: every read has a default, so a missing or garbage key degrades to a
//  fresh profile instead of a crash on launch.

import Foundation

/// Player-facing options.
struct GameSettings: Codable, Equatable {
    var quarterMinutes: Int = 4
    var difficulty: Coach.Difficulty = .pro
    var soundEnabled: Bool = true
    var musicEnabled: Bool = true
    var hapticsEnabled: Bool = true
    /// The team the player picked last, by abbreviation.
    var favouriteTeam: String = "IRN"

    static let quarterOptions = [2, 4, 6, 8]

    var quarterSeconds: Double { Double(quarterMinutes) * 60 }
}

/// Lifetime records.
struct Records: Codable, Equatable {
    var gamesPlayed = 0
    var wins = 0
    var losses = 0
    var ties = 0
    var pointsFor = 0
    var pointsAgainst = 0
    var longestTouchdown = 0
    var cupWins = 0

    var winPercentage: Double {
        gamesPlayed == 0 ? 0 : Double(wins) / Double(gamesPlayed)
    }

    var summary: String {
        "\(wins)-\(losses)" + (ties > 0 ? "-\(ties)" : "")
    }
}

enum Store {

    private static let settingsKey = "pixelgridiron.settings.v1"
    private static let recordsKey = "pixelgridiron.records.v1"
    private static let cupKey = "pixelgridiron.cup.v1"

    private static let defaults = UserDefaults.standard

    // MARK: - Settings

    static var settings: GameSettings {
        get { decode(settingsKey) ?? GameSettings() }
        set { encode(newValue, settingsKey) }
    }

    static var records: Records {
        get { decode(recordsKey) ?? Records() }
        set { encode(newValue, recordsKey) }
    }

    /// A cup run in progress, or nil.
    static var cup: CupRun? {
        get { decode(cupKey) }
        set {
            if let value = newValue {
                encode(value, cupKey)
            } else {
                defaults.removeObject(forKey: cupKey)
            }
        }
    }

    static func recordResult(playerScore: Int, opponentScore: Int) {
        var r = records
        r.gamesPlayed += 1
        r.pointsFor += playerScore
        r.pointsAgainst += opponentScore
        if playerScore > opponentScore { r.wins += 1 }
        else if playerScore < opponentScore { r.losses += 1 }
        else { r.ties += 1 }
        records = r
    }

    // MARK: - Plumbing

    private static func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

/// A single-elimination run through the league: quarter-final, semi-final, final.
struct CupRun: Codable, Equatable {
    var playerTeam: String
    /// Opponent abbreviations, in the order they must be beaten.
    var bracket: [String]
    var round: Int = 0
    var scoresFor: [Int] = []
    var scoresAgainst: [Int] = []

    var isComplete: Bool { round >= bracket.count }

    var currentOpponent: String? {
        round < bracket.count ? bracket[round] : nil
    }

    var roundName: String {
        switch bracket.count - round {
        case 1: return "THE FINAL"
        case 2: return "SEMI-FINAL"
        case 3: return "QUARTER-FINAL"
        default: return "ROUND \(round + 1)"
        }
    }

    static func start(playerTeam: String, seed: UInt64) -> CupRun {
        var rng = RNG(seed: seed)
        let others = League.teams
            .map(\.abbreviation)
            .filter { $0 != playerTeam }
        let bracket = Array(rng.shuffled(others).prefix(3))
        return CupRun(playerTeam: playerTeam, bracket: bracket)
    }

    mutating func advance(playerScore: Int, opponentScore: Int) {
        scoresFor.append(playerScore)
        scoresAgainst.append(opponentScore)
        round += 1
    }
}
