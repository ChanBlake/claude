//  MatchConfig.swift
//  What a game needs to know before it starts.

import Foundation

struct MatchConfig {
    var home: TeamIdentity
    var away: TeamIdentity
    /// The side the human plays. `nil` runs a CPU-vs-CPU demo.
    var userSide: TeamSide?
    var quarterSeconds: Double
    var difficulty: Coach.Difficulty
    var seed: UInt64
    /// Set when this game is a round of a cup run.
    var cupContext: String?

    var userTeam: TeamIdentity? {
        guard let side = userSide else { return nil }
        return side == .home ? home : away
    }

    static func exhibition(playerTeam: TeamIdentity,
                           opponent: TeamIdentity,
                           settings: GameSettings,
                           seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) -> MatchConfig {
        MatchConfig(home: playerTeam,
                    away: opponent,
                    userSide: .home,
                    quarterSeconds: settings.quarterSeconds,
                    difficulty: settings.difficulty,
                    seed: seed,
                    cupContext: nil)
    }
}

/// What happened, handed to the results screen.
struct MatchOutcome {
    var home: TeamIdentity
    var away: TeamIdentity
    var homeScore: Int
    var awayScore: Int
    var homeStats: TeamStats
    var awayStats: TeamStats
    var userSide: TeamSide?
    var cupContext: String?

    var userWon: Bool? {
        guard let side = userSide else { return nil }
        let mine = side == .home ? homeScore : awayScore
        let theirs = side == .home ? awayScore : homeScore
        if mine == theirs { return nil }
        return mine > theirs
    }
}
