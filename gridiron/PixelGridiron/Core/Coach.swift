//  Coach.swift
//  The CPU's decisions: what to call, when to go for it, whether to kick.
//
//  Deliberately legible rather than clever. A coach you can predict after three
//  drives is more fun to play against than one that is merely hard, and every
//  branch here is something a human would recognise as a reason.

import Foundation

enum Coach {

    /// What the offence should do on this down.
    enum FourthDownChoice: Equatable {
        case goForIt
        case punt
        case fieldGoal
    }

    /// Difficulty scales how well the CPU reads the situation, not how fast its
    /// players run — a rubber-banded speed boost is the thing that makes arcade
    /// sports games feel cheap.
    enum Difficulty: Int, CaseIterable, Codable {
        case rookie = 0
        case pro = 1
        case allPro = 2

        var name: String {
            switch self {
            case .rookie: return "ROOKIE"
            case .pro: return "PRO"
            case .allPro: return "ALL-PRO"
            }
        }

        /// Chance the CPU makes the read its situation actually calls for,
        /// rather than picking at random from its playbook.
        var readQuality: Double {
            switch self {
            case .rookie: return 0.45
            case .pro: return 0.72
            case .allPro: return 0.90
            }
        }
    }

    // MARK: - Fourth down

    static func fourthDownChoice(_ state: MatchState, difficulty: Difficulty) -> FourthDownChoice {
        let toGo = state.distance
        let fgDistance = state.fieldGoalDistance
        let side = state.possession
        let deficit = state.score(side.opponent) - state.score(side)
        let secondsLeft = state.clock.remaining
        let lateInGame = state.clock.quarter >= 4

        // Desperation overrides everything.
        if lateInGame && secondsLeft < 120 && deficit > 3 && fgDistance > 45 {
            return .goForIt
        }
        if lateInGame && secondsLeft < 40 && deficit > 0 && deficit <= 3 && fgDistance < 52 {
            return .fieldGoal
        }

        // Comfortably in range and it is worth three.
        if fgDistance <= 46 && (toGo > 2 || deficit > 0) {
            return .fieldGoal
        }

        // Short yardage in plus territory is a go.
        if toGo <= 2 && state.yardsToGoal < 55 {
            return .goForIt
        }

        // Deep in your own end, punt and live to fight.
        if state.yardsToGoal > 60 { return .punt }

        if fgDistance <= 52 && toGo > 4 { return .fieldGoal }
        return .punt
    }

    /// Kick the extra point or go for two.
    static func goesForTwo(_ state: MatchState, difficulty: Difficulty) -> Bool {
        guard let scoring = state.pendingTryFor else { return false }
        let margin = state.score(scoring) - state.score(scoring.opponent)
        let lateInGame = state.clock.quarter >= 4 && state.clock.remaining < 300

        guard lateInGame else { return false }
        // The classic chart: go for two when it turns a one-score game the right
        // way round.
        return margin == -2 || margin == 1 || margin == 5 || margin == 12
    }

    // MARK: - Play calling

    static func callOffense(_ state: MatchState,
                            difficulty: Difficulty,
                            rng: inout RNG) -> OffensePlay {
        // Situations that call themselves.
        if shouldKneel(state) { return Playbook.kneel }
        if isHailMarySituation(state) { return Playbook.hailMary }

        guard rng.chance(difficulty.readQuality) else {
            return rng.pick(Playbook.offenseCalls)
        }

        let toGo = state.distance
        let down = state.down
        let clockPressure = state.clock.quarter % 2 == 0 && state.clock.remaining < 90
        let trailing = state.score(state.possession) < state.score(state.defense)

        // Short yardage: run it.
        if toGo <= 2 && !clockPressure {
            return rng.chance(0.7) ? Playbook.dive : Playbook.sweep
        }
        // Long yardage: throw it.
        if toGo >= 8 || down >= 3 {
            if clockPressure || toGo >= 14 {
                return rng.chance(0.6) ? Playbook.verticals : Playbook.slants
            }
            return rng.chance(0.55) ? Playbook.slants : Playbook.screen
        }
        // Hurry-up: nothing that eats clock.
        if clockPressure && trailing {
            return rng.chance(0.5) ? Playbook.slants : Playbook.verticals
        }
        // Otherwise stay balanced, with a shot play mixed in.
        let roll = rng.unit()
        if roll < 0.30 { return Playbook.dive }
        if roll < 0.50 { return Playbook.sweep }
        if roll < 0.72 { return Playbook.slants }
        if roll < 0.88 { return Playbook.playAction }
        return Playbook.verticals
    }

    static func callDefense(_ state: MatchState,
                            difficulty: Difficulty,
                            rng: inout RNG) -> DefensePlay {
        guard rng.chance(difficulty.readQuality) else {
            return rng.pick(Playbook.defenseCalls)
        }

        let toGo = state.distance
        let down = state.down
        let goalLine = state.yardsToGoal <= 5
        let lateAndAhead = state.clock.quarter >= 4
            && state.clock.remaining < 120
            && state.score(state.defense) > state.score(state.possession)

        if goalLine { return Playbook.runStuff }
        if lateAndAhead { return Playbook.prevent }
        if toGo <= 2 { return rng.chance(0.65) ? Playbook.runStuff : Playbook.balanced }
        if down >= 3 && toGo >= 7 {
            return rng.chance(0.5) ? Playbook.manBlitz : Playbook.coverTwo
        }
        let roll = rng.unit()
        if roll < 0.34 { return Playbook.balanced }
        if roll < 0.58 { return Playbook.coverTwo }
        if roll < 0.80 { return Playbook.manBlitz }
        return Playbook.runStuff
    }

    /// Meter values for a CPU kick — good kickers stop it closer to the middle.
    static func kickMeter(for kicker: PlayerProfile,
                          distance: Double,
                          difficulty: Difficulty,
                          rng: inout RNG) -> (power: Double, accuracy: Double) {
        let steadiness = clamp(kicker.ratings.awareness / 99.0, 0.2, 1.0)
        let spread = (1.05 - steadiness) * (1.25 - difficulty.readQuality * 0.5)
        let accuracy = rng.bell() * 0.11 * spread
        // Take just enough leg for the distance, plus a margin.
        let needed = clamp((distance - 25) / 35.0, 0.35, 1.0)
        let power = clamp(needed + 0.12 + rng.bell() * 0.05 * spread, 0.3, 1.0)
        return (power, accuracy)
    }

    // MARK: - Situations

    static func shouldKneel(_ state: MatchState) -> Bool {
        guard state.clock.quarter >= 4 else { return false }
        guard state.score(state.possession) > state.score(state.defense) else { return false }
        // Enough time can be run off with kneel-downs to end it.
        let playsLeft = ceil(state.clock.remaining / (Tuning.huddleSeconds + 2))
        return state.down <= 3 && playsLeft <= Double(4 - state.down) + 1
    }

    static func isHailMarySituation(_ state: MatchState) -> Bool {
        let endOfHalf = (state.clock.quarter == 2 || state.clock.quarter == 4)
            && state.clock.remaining <= 6
        guard endOfHalf else { return false }
        return state.yardsToGoal <= 55
    }

    /// The plays a human is offered on this down: the six base calls, plus
    /// whatever the situation makes available.
    static func availableCalls(_ state: MatchState) -> [OffensePlay] {
        var calls = Playbook.offenseCalls
        if state.down == 4 {
            calls.append(Playbook.punt)
            if state.fieldGoalDistance <= 60 { calls.append(Playbook.fieldGoal) }
        }
        if isHailMarySituation(state) { calls.insert(Playbook.hailMary, at: 0) }
        if state.clock.quarter >= 4 && state.clock.remaining < 120
            && state.score(state.possession) > state.score(state.defense) {
            calls.append(Playbook.kneel)
        }
        return calls
    }
}
