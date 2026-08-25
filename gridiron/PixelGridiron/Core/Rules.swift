//  Rules.swift
//  The rulebook: possession, down and distance, the clock, and scoring.
//
//  This file is deliberately free of any notion of *how* a play happened. The
//  simulation hands it a `PlayResult`; this decides what that means for the game.
//  That split is what lets `RulesTests` drive a whole game with synthetic results.

import Foundation

enum TeamSide: Int, Codable, CaseIterable {
    case home = 0
    case away = 1

    var opponent: TeamSide { self == .home ? .away : .home }
}

/// How a play ended. Ordered roughly from "nothing unusual" to "everything changed".
enum PlayEnding: Equatable {
    /// Tackled, or ran out of bounds, in bounds of a normal down.
    case tackled(outOfBounds: Bool)
    /// Quarterback brought down behind the line.
    case sack
    /// Pass hit the ground.
    case incomplete
    /// Carrier crossed the goal line he was attacking.
    case touchdown
    /// The ball carrier was down in the end zone his team was defending.
    /// `concededBy` is that team — on a return it is not the team that started
    /// the play on offence, and it is the team that must free-kick.
    case safety(concededBy: TeamSide)
    /// Intercepted; `returnedTo` is where the new carrier was stopped.
    case interception(returnedTo: Vec2, returnedForTouchdown: Bool)
    /// Fumbled and recovered by the defence.
    case fumble(recoveredBy: TeamSide, at: Vec2, returnedForTouchdown: Bool)
    /// Kick attempt. `good` covers both field goals and extra points.
    case kick(good: Bool, blocked: Bool, fromSpot: Double)
    /// Punt came to rest / was returned to `spot`.
    case punt(spot: Vec2, touchback: Bool, returnedForTouchdown: Bool)
    /// Kickoff fielded or touched back.
    case kickoff(spot: Vec2, touchback: Bool, returnedForTouchdown: Bool)
    /// Kneel-down.
    case kneel
    /// Two-point conversion attempt resolved.
    case conversion(good: Bool)
}

/// What the simulation reports when a play is over.
struct PlayResult: Equatable {
    var ending: PlayEnding
    /// Where the ball ended up, in field coordinates.
    var endSpot: Vec2
    /// Signed yards from the line of scrimmage, in the offence's direction.
    var yardsGained: Double
    /// Game seconds the play itself consumed.
    var elapsed: Double
    /// One line for the result banner.
    var headline: String
    /// Player id credited with the play, for the box score.
    var ballCarrierID: Int?
    /// Set when the play was a completed pass, for the box score.
    var completedPass: Bool = false
    /// Set when a pass was attempted at all.
    var passAttempted: Bool = false
}

/// The running clock.
struct GameClock: Equatable {
    var quarter: Int = 1
    /// Seconds left in the current quarter.
    var remaining: Double
    var isRunning: Bool = false
    let quarterLength: Double

    init(quarterLength: Double) {
        self.quarterLength = quarterLength
        self.remaining = quarterLength
    }

    var isHalftime: Bool { quarter == 2 && remaining <= 0 }
    var isFinal: Bool { quarter >= 4 && remaining <= 0 }
    /// The two-minute warning window, where the clock rules get stricter.
    var inTwoMinuteDrill: Bool { (quarter == 2 || quarter == 4) && remaining <= 120 }

    var display: String {
        let total = Int(max(0, remaining).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var quarterLabel: String {
        switch quarter {
        case 1: return "1ST"
        case 2: return "2ND"
        case 3: return "3RD"
        case 4: return "4TH"
        default: return "OT"
        }
    }

    /// Burns `seconds`, never past zero. Returns true if the quarter just expired.
    @discardableResult
    mutating func tick(_ seconds: Double) -> Bool {
        guard isRunning, remaining > 0 else { return false }
        remaining = max(0, remaining - seconds)
        if remaining <= 0 {
            isRunning = false
            return true
        }
        return false
    }
}

/// Counting stats, one set per team.
struct TeamStats: Equatable {
    var firstDowns = 0
    var rushYards = 0.0
    var passYards = 0.0
    var passAttempts = 0
    var completions = 0
    var interceptionsThrown = 0
    var fumblesLost = 0
    var sacksAllowed = 0
    var penaltyYards = 0.0
    var timeOfPossession = 0.0
    var plays = 0

    var totalYards: Double { rushYards + passYards }
}

/// What the game is waiting on right now.
enum GamePhase: Equatable {
    case coinToss
    case kickoff
    case playCall
    case presnap
    case live
    case deadBall
    case pointAfter          // choosing kick or two-point
    case quarterBreak
    case halftime
    case final
}

/// The complete state of a game in progress. Everything the HUD renders and
/// everything the rules mutate lives here.
struct MatchState {
    var home: TeamIdentity
    var away: TeamIdentity
    var homeRoster: Roster
    var awayRoster: Roster

    var score: [Int] = [0, 0]
    var clock: GameClock
    var stats: [TeamStats] = [TeamStats(), TeamStats()]
    var timeouts: [Int] = [3, 3]

    var phase: GamePhase = .coinToss
    var possession: TeamSide = .home

    /// Which way the home team is driving this half: +1 or −1.
    var homeDirection: Int = 1

    var down: Int = 1
    var distance: Double = 10
    /// Absolute x of the line of scrimmage.
    var lineOfScrimmage: Double = Field.midfieldX
    /// Absolute y where the ball is spotted (hash or middle).
    var ballY: Double = Field.midfieldY
    /// Absolute x the offence must reach for a new set of downs.
    var lineToGain: Double = Field.midfieldX + 10

    /// The team that received the opening kickoff — the other team receives to
    /// start the second half.
    var openingReceiver: TeamSide = .home

    /// Set while a touchdown is on the board and the try has not been decided.
    var pendingTryFor: TeamSide?
    /// Set when a kickoff is owed. It survives a quarter break, so a score on
    /// the last play of a quarter still kicks off to start the next one.
    var pendingKickoff: Bool = false

    var lastResult: PlayResult?
    /// Rolling log of result headlines, newest last. The drive summary reads it.
    var playLog: [String] = []

    init(home: TeamIdentity, away: TeamIdentity, quarterLength: Double, seed: UInt64) {
        self.home = home
        self.away = away
        self.homeRoster = Roster.generate(for: home, seed: seed &* 31 &+ 7)
        self.awayRoster = Roster.generate(for: away, seed: seed &* 31 &+ 11)
        self.clock = GameClock(quarterLength: quarterLength)
    }

    // MARK: - Derived

    func identity(_ side: TeamSide) -> TeamIdentity { side == .home ? home : away }
    func roster(_ side: TeamSide) -> Roster { side == .home ? homeRoster : awayRoster }

    /// +1 or −1: the direction `side` is currently attacking.
    func direction(_ side: TeamSide) -> Int {
        side == .home ? homeDirection : -homeDirection
    }

    var offenseDirection: Int { direction(possession) }
    var defense: TeamSide { possession.opponent }

    var scoreHome: Int { score[TeamSide.home.rawValue] }
    var scoreAway: Int { score[TeamSide.away.rawValue] }

    func score(_ side: TeamSide) -> Int { score[side.rawValue] }

    /// "1ST & 10", "3RD & GOAL", "4TH & INCHES".
    var downAndDistanceText: String {
        let ordinal = ["", "1ST", "2ND", "3RD", "4TH"][clamp(down, 0, 4)]
        if lineToGainIsGoalLine { return "\(ordinal) & GOAL" }
        if distance < 1 { return "\(ordinal) & INCHES" }
        return "\(ordinal) & \(Int(distance.rounded()))"
    }

    var lineToGainIsGoalLine: Bool {
        let goalLine = Field.attackingGoalLine(direction: offenseDirection)
        return offenseDirection > 0 ? lineToGain >= goalLine - 0.01 : lineToGain <= goalLine + 0.01
    }

    var ballOnText: String {
        Field.yardLineLabel(x: lineOfScrimmage, direction: offenseDirection)
    }

    /// Yards from the line of scrimmage to the goal the offence is attacking.
    var yardsToGoal: Double {
        Field.yardsToGoal(from: lineOfScrimmage, direction: offenseDirection)
    }

    /// Distance of a field-goal attempt from the current spot: the snap goes
    /// 7 yards back and the posts are 10 yards behind the goal line.
    var fieldGoalDistance: Double { yardsToGoal + 17 }

    var leader: TeamSide? {
        if scoreHome == scoreAway { return nil }
        return scoreHome > scoreAway ? .home : .away
    }
}

/// The rulebook proper. Free functions over `MatchState` so every transition is
/// visible and testable, rather than scattered across the scene.
enum Rules {

    static let touchdownPoints = 6
    static let fieldGoalPoints = 3
    static let extraPointPoints = 1
    static let twoPointPoints = 2
    static let safetyPoints = 2

    static let kickoffFromOwn: Double = 35
    static let kickoffTouchbackTo: Double = 25
    static let puntTouchbackTo: Double = 20
    static let safetyFreeKickFromOwn: Double = 20
    static let extraPointSnapFromOpp: Double = 15
    static let twoPointSnapFromOpp: Double = 2

    // MARK: - Spotting

    /// Absolute x of a team's own `yard` line, given the way it is driving.
    static func ownYardLine(_ yard: Double, direction: Int) -> Double {
        direction > 0 ? Field.homeGoalLine + yard : Field.awayGoalLine - yard
    }

    /// Absolute x of the opponent's `yard` line, given the way the offence drives.
    static func opponentYardLine(_ yard: Double, direction: Int) -> Double {
        direction > 0 ? Field.awayGoalLine - yard : Field.homeGoalLine + yard
    }

    /// Places the ball for a fresh set of downs and recomputes the line to gain.
    static func setFirstDown(_ state: inout MatchState, at x: Double, y: Double) {
        state.down = 1
        state.lineOfScrimmage = clampSpot(x, direction: state.offenseDirection)
        state.ballY = Field.hashSpot(for: y)
        let goalLine = Field.attackingGoalLine(direction: state.offenseDirection)
        let toGoal = Field.yardsToGoal(from: state.lineOfScrimmage, direction: state.offenseDirection)
        if toGoal <= 10 {
            state.lineToGain = goalLine
            state.distance = toGoal
        } else {
            state.lineToGain = state.lineOfScrimmage + Double(state.offenseDirection) * 10
            state.distance = 10
        }
    }

    /// Keeps a spot out of the end zones — the ball is never snapped from one.
    /// Half-yard-line rule: the offence never starts closer than its own half-yard.
    static func clampSpot(_ x: Double, direction: Int) -> Double {
        let ownGoal = Field.defendingGoalLine(direction: direction)
        let oppGoal = Field.attackingGoalLine(direction: direction)
        if direction > 0 {
            return clamp(x, ownGoal + 0.5, oppGoal - 0.5)
        } else {
            return clamp(x, oppGoal + 0.5, ownGoal - 0.5)
        }
    }

    /// Hands possession to `side` at `x`, first and ten.
    static func giveBall(to side: TeamSide, at x: Double, y: Double, _ state: inout MatchState) {
        state.possession = side
        setFirstDown(&state, at: x, y: y)
    }

    // MARK: - Scoring

    static func addScore(_ points: Int, to side: TeamSide, _ state: inout MatchState) {
        state.score[side.rawValue] += points
    }

    // MARK: - Applying a play

    /// Folds a finished play into the game state and returns the phase the game
    /// should move to next.
    ///
    /// The caller is responsible for running the resulting phase (kickoff,
    /// point-after choice, next play call); `Rules` only decides which it is.
    @discardableResult
    static func apply(_ result: PlayResult, to state: inout MatchState) -> GamePhase {
        let offense = state.possession
        let defense = offense.opponent
        let direction = state.offenseDirection

        state.lastResult = result
        state.playLog.append(result.headline)
        if state.playLog.count > 40 { state.playLog.removeFirst(state.playLog.count - 40) }

        state.stats[offense.rawValue].plays += 1
        state.stats[offense.rawValue].timeOfPossession += result.elapsed

        // Book the yardage before possession can change underneath us.
        recordYardage(result, offense: offense, &state)

        // The clock runs by default and every branch below that should stop it
        // says so explicitly. Getting this backwards is the classic way a
        // football clock ends up frozen for a whole quarter.
        state.clock.isRunning = true

        // Burn the play clock. The quarter can expire mid-play; the play still
        // counts, and the quarter break is handled after the result is applied.
        let quarterExpired = burn(result.elapsed, &state)

        var next: GamePhase

        switch result.ending {
        case .touchdown:
            addScore(touchdownPoints, to: offense, &state)
            state.pendingTryFor = offense
            state.clock.isRunning = false
            next = .pointAfter

        case .interception(let spot, let returnedForTD):
            state.stats[offense.rawValue].interceptionsThrown += 1
            if returnedForTD {
                addScore(touchdownPoints, to: defense, &state)
                state.pendingTryFor = defense
                state.possession = defense
                state.clock.isRunning = false
                next = .pointAfter
            } else {
                state.clock.isRunning = false
                giveBall(to: defense, at: spot.x, y: spot.y, &state)
                next = .playCall
            }

        case .fumble(let recoveredBy, let spot, let returnedForTD):
            if recoveredBy != offense {
                state.stats[offense.rawValue].fumblesLost += 1
                if returnedForTD {
                    addScore(touchdownPoints, to: defense, &state)
                    state.pendingTryFor = defense
                    state.possession = defense
                    state.clock.isRunning = false
                    next = .pointAfter
                } else {
                    state.clock.isRunning = false
                    giveBall(to: recoveredBy, at: spot.x, y: spot.y, &state)
                    next = .playCall
                }
            } else {
                // Offence fell on it. Treat as a tackle at the recovery spot.
                next = advanceDowns(to: spot, outOfBounds: false, &state)
            }

        case .safety(let concededBy):
            addScore(safetyPoints, to: concededBy.opponent, &state)
            state.clock.isRunning = false
            // The team that gave up the safety free-kicks from its own 20.
            prepareKickoff(kicking: concededBy, from: safetyFreeKickFromOwn, &state)
            next = .kickoff

        case .kick(let good, _, let fromSpot):
            state.clock.isRunning = false
            if state.pendingTryFor != nil {
                // Extra point.
                if good { addScore(extraPointPoints, to: offense, &state) }
                state.pendingTryFor = nil
                prepareKickoff(kicking: offense, from: kickoffFromOwn, &state)
                next = .kickoff
            } else if good {
                addScore(fieldGoalPoints, to: offense, &state)
                prepareKickoff(kicking: offense, from: kickoffFromOwn, &state)
                next = .kickoff
            } else {
                // Miss: the defence takes over at the spot of the kick, or its
                // own 20, whichever is further from its own goal line.
                // Spot of the kick, unless that is inside the defence's own 20,
                // in which case it takes over on the 20.
                let kickSpot = fromSpot
                let defenceOwnTwenty = ownYardLine(20, direction: -direction)
                let takeover = direction > 0 ? min(kickSpot, defenceOwnTwenty)
                                             : max(kickSpot, defenceOwnTwenty)
                giveBall(to: defense, at: takeover, y: Field.midfieldY, &state)
                next = .playCall
            }

        case .conversion(let good):
            state.clock.isRunning = false
            if good { addScore(twoPointPoints, to: offense, &state) }
            state.pendingTryFor = nil
            prepareKickoff(kicking: offense, from: kickoffFromOwn, &state)
            next = .kickoff

        case .punt(let spot, let touchback, let returnedForTD):
            state.clock.isRunning = false
            if returnedForTD {
                addScore(touchdownPoints, to: defense, &state)
                state.pendingTryFor = defense
                state.possession = defense
                next = .pointAfter
            } else if touchback {
                let x = ownYardLine(puntTouchbackTo, direction: -direction)
                giveBall(to: defense, at: x, y: Field.midfieldY, &state)
                next = .playCall
            } else {
                giveBall(to: defense, at: spot.x, y: spot.y, &state)
                next = .playCall
            }

        case .kickoff(let spot, let touchback, let returnedForTD):
            state.clock.isRunning = false
            state.pendingKickoff = false
            let receiving = state.possession.opponent
            if returnedForTD {
                addScore(touchdownPoints, to: receiving, &state)
                state.pendingTryFor = receiving
                state.possession = receiving
                next = .pointAfter
            } else if touchback {
                state.possession = receiving
                let x = ownYardLine(kickoffTouchbackTo, direction: state.direction(receiving))
                giveBall(to: receiving, at: x, y: Field.midfieldY, &state)
                next = .playCall
            } else {
                giveBall(to: receiving, at: spot.x, y: spot.y, &state)
                next = .playCall
            }

        case .kneel:
            next = advanceDowns(to: Vec2(state.lineOfScrimmage - Double(direction),
                                         state.ballY),
                                outOfBounds: false, &state)

        case .incomplete:
            state.clock.isRunning = false
            next = advanceDowns(to: Vec2(state.lineOfScrimmage, state.ballY),
                                outOfBounds: false, &state)

        case .sack:
            state.stats[offense.rawValue].sacksAllowed += 1
            next = advanceDowns(to: result.endSpot, outOfBounds: false, &state)

        case .tackled(let outOfBounds):
            next = advanceDowns(to: result.endSpot, outOfBounds: outOfBounds, &state)
        }

        // A quarter that ran out mid-play overrides whatever came next, unless
        // the game is already over or a try is pending.
        if quarterExpired && next != .pointAfter {
            next = endOfQuarter(&state, proposed: next)
        }
        if state.clock.isFinal && next != .pointAfter {
            next = .final
        }

        state.phase = next
        return next
    }

    /// Normal down-and-distance bookkeeping for a play that ended in the field.
    private static func advanceDowns(to spot: Vec2, outOfBounds: Bool, _ state: inout MatchState) -> GamePhase {
        let direction = state.offenseDirection
        let newX = clampSpot(spot.x, direction: direction)

        if outOfBounds { state.clock.isRunning = false }

        // Reached the line to gain?
        let reached = direction > 0 ? newX >= state.lineToGain - 0.01
                                    : newX <= state.lineToGain + 0.01
        if reached {
            state.stats[state.possession.rawValue].firstDowns += 1
            setFirstDown(&state, at: newX, y: spot.y)
            return .playCall
        }

        state.lineOfScrimmage = newX
        state.ballY = Field.hashSpot(for: spot.y)
        state.distance = abs(state.lineToGain - newX)

        if state.down >= 4 {
            // Turnover on downs — the defence takes over right where it stopped.
            state.clock.isRunning = false
            giveBall(to: state.possession.opponent, at: newX, y: spot.y, &state)
            return .playCall
        }

        state.down += 1
        return .playCall
    }

    private static func recordYardage(_ result: PlayResult, offense: TeamSide, _ state: inout MatchState) {
        if result.passAttempted {
            state.stats[offense.rawValue].passAttempts += 1
            if result.completedPass {
                state.stats[offense.rawValue].completions += 1
                state.stats[offense.rawValue].passYards += result.yardsGained
            }
        } else {
            switch result.ending {
            case .kick, .punt, .kickoff, .conversion:
                break
            case .sack:
                state.stats[offense.rawValue].passYards += result.yardsGained
            default:
                state.stats[offense.rawValue].rushYards += result.yardsGained
            }
        }
    }

    /// Burns `seconds` of game clock. Returns true if the quarter expired.
    private static func burn(_ seconds: Double, _ state: inout MatchState) -> Bool {
        guard state.clock.remaining > 0 else { return false }
        let before = state.clock.remaining
        state.clock.remaining = max(0, before - seconds)
        return state.clock.remaining <= 0
    }

    /// Handles the end of a quarter. Returns the phase to run next.
    static func endOfQuarter(_ state: inout MatchState, proposed: GamePhase) -> GamePhase {
        state.clock.isRunning = false

        switch state.clock.quarter {
        case 1, 3:
            // Ends swap. A drive in progress mirrors across midfield so it
            // continues where it left off; a kickoff already owed is simply
            // re-spotted for the new direction.
            state.clock.quarter += 1
            state.clock.remaining = state.clock.quarterLength
            state.homeDirection = -state.homeDirection
            if state.pendingKickoff {
                prepareKickoff(kicking: state.possession, from: kickoffFromOwn, &state)
            } else {
                mirrorField(&state)
            }
            return .quarterBreak

        case 2:
            state.clock.quarter = 3
            state.clock.remaining = state.clock.quarterLength
            state.homeDirection = -state.homeDirection
            state.timeouts = [3, 3]
            // Whoever received the opening kickoff kicks off to start the half.
            prepareKickoff(kicking: state.openingReceiver, from: kickoffFromOwn, &state)
            return .halftime

        default:
            return .final
        }
    }

    /// Reflects the ball and the chains across midfield when the teams swap ends
    /// between the 1st/2nd and 3rd/4th quarters.
    private static func mirrorField(_ state: inout MatchState) {
        state.lineOfScrimmage = Field.totalLength - state.lineOfScrimmage
        state.lineToGain = Field.totalLength - state.lineToGain
        state.ballY = Field.width - state.ballY
    }

    /// Spots a kickoff (or a free kick after a safety).
    ///
    /// During a kickoff `state.possession` names the **kicking** team — it is the
    /// team with the ball in hand — and the receiving team is its opponent.
    static func prepareKickoff(kicking: TeamSide, from ownYard: Double, _ state: inout MatchState) {
        state.possession = kicking
        state.lineOfScrimmage = ownYardLine(ownYard, direction: state.direction(kicking))
        state.ballY = Field.midfieldY
        state.down = 1
        state.distance = 10
        state.lineToGain = state.lineOfScrimmage + Double(state.direction(kicking)) * 10
        state.pendingKickoff = true
    }

    /// Sets up the opening kickoff. `receiving` gets the ball.
    static func startKickoff(receiving: TeamSide, _ state: inout MatchState) {
        state.openingReceiver = receiving
        prepareKickoff(kicking: receiving.opponent, from: kickoffFromOwn, &state)
        state.phase = .kickoff
    }

    /// Sets up the snap for a point-after try.
    static func setUpTry(twoPoint: Bool, _ state: inout MatchState) {
        guard let scoring = state.pendingTryFor else { return }
        state.possession = scoring
        let yard = twoPoint ? twoPointSnapFromOpp : extraPointSnapFromOpp
        state.lineOfScrimmage = opponentYardLine(yard, direction: state.direction(scoring))
        state.ballY = Field.midfieldY
        state.down = 1
        state.distance = twoPoint ? twoPointSnapFromOpp : 0
        state.lineToGain = Field.attackingGoalLine(direction: state.direction(scoring))
        state.phase = .presnap
    }

    /// Burns the huddle between snaps, when the clock is running. Returns the
    /// phase to run next, which is `proposed` unless the quarter just expired.
    @discardableResult
    static func runOffPlayClock(_ state: inout MatchState, proposed: GamePhase) -> GamePhase {
        guard state.clock.isRunning, state.clock.remaining > 0 else { return proposed }
        state.clock.remaining = max(0, state.clock.remaining - Tuning.huddleSeconds)
        guard state.clock.remaining <= 0 else { return proposed }
        if state.clock.quarter >= 4 { return .final }
        return endOfQuarter(&state, proposed: proposed)
    }

    /// Spends a timeout, if the team has one. Returns whether it worked.
    @discardableResult
    static func useTimeout(_ side: TeamSide, _ state: inout MatchState) -> Bool {
        guard state.timeouts[side.rawValue] > 0 else { return false }
        state.timeouts[side.rawValue] -= 1
        state.clock.isRunning = false
        return true
    }
}
