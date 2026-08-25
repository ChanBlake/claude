//  RulesTests.swift
//  The rulebook, driven with synthetic play results.
//
//  `Rules.apply` never asks how a play happened, which is what makes this
//  possible: a whole game can be played here in milliseconds by handing it
//  hand-written `PlayResult`s.

import XCTest
@testable import PixelGridiron

final class RulesTests: XCTestCase {

    // MARK: - Helpers

    private func makeState(quarterLength: Double = 240) -> MatchState {
        MatchState(home: League.teams[0],
                   away: League.teams[1],
                   quarterLength: quarterLength,
                   seed: 1234)
    }

    private func gain(_ yards: Double, from state: MatchState, elapsed: Double = 5,
                      outOfBounds: Bool = false) -> PlayResult {
        let spot = Vec2(state.lineOfScrimmage + Double(state.offenseDirection) * yards,
                        state.ballY)
        return PlayResult(ending: .tackled(outOfBounds: outOfBounds),
                          endSpot: spot,
                          yardsGained: yards,
                          elapsed: elapsed,
                          headline: "TEST",
                          ballCarrierID: nil)
    }

    // MARK: - Down and distance

    func testFirstDownResetsChains() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 30, y: Field.midfieldY, &state)
        XCTAssertEqual(state.down, 1)
        XCTAssertEqual(state.distance, 10, accuracy: 0.001)
        XCTAssertEqual(state.lineToGain, 40, accuracy: 0.001)
    }

    func testShortGainAdvancesTheDown() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 30, y: Field.midfieldY, &state)
        let play = gain(4, from: state)
        Rules.apply(play, to: &state)
        XCTAssertEqual(state.down, 2)
        XCTAssertEqual(state.distance, 6, accuracy: 0.001)
        XCTAssertEqual(state.possession, .home)
    }

    func testReachingTheLineToGainIsAFirstDown() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 30, y: Field.midfieldY, &state)
        let first = gain(4, from: state)
        Rules.apply(first, to: &state)
        let second = gain(7, from: state)
        Rules.apply(second, to: &state)
        XCTAssertEqual(state.down, 1)
        XCTAssertEqual(state.distance, 10, accuracy: 0.001)
        XCTAssertEqual(state.stats[TeamSide.home.rawValue].firstDowns, 1)
    }

    func testFourthDownFailureTurnsTheBallOver() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 50, y: Field.midfieldY, &state)
        for _ in 0..<4 {
            let play = gain(1, from: state)
            Rules.apply(play, to: &state)
        }
        XCTAssertEqual(state.possession, .away)
        XCTAssertEqual(state.down, 1)
        // The away team now drives the other way from where the ball died.
        XCTAssertEqual(state.offenseDirection, -1)
        XCTAssertEqual(state.lineOfScrimmage, 54, accuracy: 0.001)
        XCTAssertEqual(state.lineToGain, 44, accuracy: 0.001)
    }

    func testInsideTheTenTheGoalLineBecomesTheLineToGain() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 104, y: Field.midfieldY, &state)
        XCTAssertTrue(state.lineToGainIsGoalLine)
        XCTAssertEqual(state.lineToGain, Field.awayGoalLine, accuracy: 0.001)
        XCTAssertEqual(state.downAndDistanceText, "1ST & GOAL")
    }

    func testASpotIsNeverInsideTheEndZone() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 30, y: Field.midfieldY, &state)
        // A twenty-five yard loss from the 30 would put the ball on the 5, which
        // is legal; a loss past the goal line is clamped, not conceded.
        let play = gain(-40, from: state)
        Rules.apply(play, to: &state)
        XCTAssertGreaterThan(state.lineOfScrimmage, Field.homeGoalLine)
    }

    // MARK: - Scoring

    func testTouchdownScoresSixAndQueuesTheTry() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 90, y: Field.midfieldY, &state)
        let result = PlayResult(ending: .touchdown,
                                endSpot: Vec2(Field.awayGoalLine, Field.midfieldY),
                                yardsGained: 20, elapsed: 6, headline: "TD",
                                ballCarrierID: nil)
        let next = Rules.apply(result, to: &state)
        XCTAssertEqual(state.scoreHome, 6)
        XCTAssertEqual(next, .pointAfter)
        XCTAssertEqual(state.pendingTryFor, .home)
    }

    func testExtraPointAddsOneAndQueuesAKickoff() {
        var state = makeState()
        state.pendingTryFor = .home
        state.possession = .home
        Rules.setUpTry(twoPoint: false, &state)
        let result = PlayResult(ending: .kick(good: true, blocked: false, fromSpot: 88),
                                endSpot: Vec2(120, Field.midfieldY),
                                yardsGained: 0, elapsed: 4, headline: "GOOD",
                                ballCarrierID: nil)
        let next = Rules.apply(result, to: &state)
        XCTAssertEqual(state.scoreHome, 1)
        XCTAssertNil(state.pendingTryFor)
        XCTAssertEqual(next, .kickoff)
        XCTAssertTrue(state.pendingKickoff)
        // The scoring team kicks off.
        XCTAssertEqual(state.possession, .home)
    }

    func testTwoPointConversionAddsTwo() {
        var state = makeState()
        state.pendingTryFor = .away
        state.possession = .away
        Rules.setUpTry(twoPoint: true, &state)
        let result = PlayResult(ending: .conversion(good: true),
                                endSpot: Vec2(Field.homeGoalLine, Field.midfieldY),
                                yardsGained: 2, elapsed: 5, headline: "GOOD",
                                ballCarrierID: nil)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.scoreAway, 2)
        XCTAssertNil(state.pendingTryFor)
    }

    func testFieldGoalScoresThree() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 85, y: Field.midfieldY, &state)
        let result = PlayResult(ending: .kick(good: true, blocked: false, fromSpot: 78),
                                endSpot: Vec2(120, Field.midfieldY),
                                yardsGained: 0, elapsed: 5, headline: "GOOD",
                                ballCarrierID: nil)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.scoreHome, 3)
    }

    func testMissedFieldGoalGivesTheBallBackAtTheSpotOfTheKick() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 60, y: Field.midfieldY, &state)
        let kickSpot = 53.0
        let result = PlayResult(ending: .kick(good: false, blocked: false, fromSpot: kickSpot),
                                endSpot: Vec2(120, Field.midfieldY),
                                yardsGained: 0, elapsed: 5, headline: "NO GOOD",
                                ballCarrierID: nil)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.possession, .away)
        XCTAssertEqual(state.lineOfScrimmage, kickSpot, accuracy: 0.001)
    }

    func testMissedFieldGoalFromDeepGivesTheBallAtTheTwenty() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 105, y: Field.midfieldY, &state)
        // The kick is taken from the 98; the defence's own 20 is x = 90.
        let result = PlayResult(ending: .kick(good: false, blocked: false, fromSpot: 98),
                                endSpot: Vec2(120, Field.midfieldY),
                                yardsGained: 0, elapsed: 5, headline: "NO GOOD",
                                ballCarrierID: nil)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.possession, .away)
        XCTAssertEqual(state.lineOfScrimmage, 90, accuracy: 0.001)
    }

    func testSafetyScoresTwoForTheDefenceAndSetsUpAFreeKick() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 12, y: Field.midfieldY, &state)
        let result = PlayResult(ending: .safety(concededBy: .home),
                                endSpot: Vec2(8, Field.midfieldY),
                                yardsGained: -4, elapsed: 4, headline: "SAFETY",
                                ballCarrierID: nil)
        let next = Rules.apply(result, to: &state)
        XCTAssertEqual(state.scoreAway, 2)
        XCTAssertEqual(next, .kickoff)
        // The team that conceded the safety kicks from its own 20.
        XCTAssertEqual(state.possession, .home)
        XCTAssertEqual(state.lineOfScrimmage, Field.homeGoalLine + 20, accuracy: 0.001)
    }

    // MARK: - Turnovers

    func testInterceptionFlipsPossessionAtTheReturnSpot() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        let result = PlayResult(ending: .interception(returnedTo: Vec2(62, 18),
                                                      returnedForTouchdown: false),
                                endSpot: Vec2(62, 18),
                                yardsGained: 22, elapsed: 7, headline: "INT",
                                ballCarrierID: nil,
                                completedPass: false,
                                passAttempted: true)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.possession, .away)
        XCTAssertEqual(state.down, 1)
        XCTAssertEqual(state.lineOfScrimmage, 62, accuracy: 0.001)
        XCTAssertEqual(state.stats[TeamSide.home.rawValue].interceptionsThrown, 1)
    }

    func testPickSixScoresForTheDefence() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        let result = PlayResult(ending: .interception(returnedTo: Vec2(Field.homeGoalLine, 20),
                                                      returnedForTouchdown: true),
                                endSpot: Vec2(Field.homeGoalLine, 20),
                                yardsGained: 0, elapsed: 9, headline: "PICK SIX",
                                ballCarrierID: nil,
                                completedPass: false,
                                passAttempted: true)
        let next = Rules.apply(result, to: &state)
        XCTAssertEqual(state.scoreAway, 6)
        XCTAssertEqual(state.possession, .away)
        XCTAssertEqual(state.pendingTryFor, .away)
        XCTAssertEqual(next, .pointAfter)
    }

    func testOffenceRecoveringItsOwnFumbleKeepsTheBall() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        let result = PlayResult(ending: .fumble(recoveredBy: .home, at: Vec2(43, 20),
                                                returnedForTouchdown: false),
                                endSpot: Vec2(43, 20),
                                yardsGained: 3, elapsed: 5, headline: "FUMBLE",
                                ballCarrierID: nil)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.possession, .home)
        XCTAssertEqual(state.down, 2)
    }

    // MARK: - Kicks and touchbacks

    func testPuntTouchbackSpotsAtTheTwenty() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 70, y: Field.midfieldY, &state)
        let result = PlayResult(ending: .punt(spot: Vec2(112, 20), touchback: true,
                                              returnedForTouchdown: false),
                                endSpot: Vec2(112, 20),
                                yardsGained: 0, elapsed: 6, headline: "TOUCHBACK",
                                ballCarrierID: nil)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.possession, .away)
        // The away team defends the high-x end zone, so its own 20 is x = 90.
        XCTAssertEqual(state.lineOfScrimmage, 90, accuracy: 0.001)
    }

    func testKickoffTouchbackSpotsAtTheTwentyFive() {
        var state = makeState()
        Rules.startKickoff(receiving: .away, &state)
        XCTAssertEqual(state.possession, .home)      // the kicking team holds it
        let result = PlayResult(ending: .kickoff(spot: Vec2(115, 20), touchback: true,
                                                 returnedForTouchdown: false),
                                endSpot: Vec2(115, 20),
                                yardsGained: 0, elapsed: 5, headline: "TOUCHBACK",
                                ballCarrierID: nil)
        Rules.apply(result, to: &state)
        XCTAssertEqual(state.possession, .away)
        XCTAssertEqual(state.lineOfScrimmage, Field.awayGoalLine - 25, accuracy: 0.001)
        XCTAssertFalse(state.pendingKickoff)
    }

    // MARK: - The clock

    func testTheClockStopsOnAnIncompletion() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        state.clock.isRunning = true
        let result = PlayResult(ending: .incomplete, endSpot: Vec2(40, Field.midfieldY),
                                yardsGained: 0, elapsed: 4, headline: "INCOMPLETE",
                                ballCarrierID: nil, completedPass: false, passAttempted: true)
        Rules.apply(result, to: &state)
        XCTAssertFalse(state.clock.isRunning)
    }

    func testTheClockKeepsRunningAfterATackleInBounds() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        let play = gain(5, from: state)
        Rules.apply(play, to: &state)
        XCTAssertTrue(state.clock.isRunning)
    }

    func testTheClockStopsWhenTheCarrierGoesOutOfBounds() {
        var state = makeState()
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        let play = gain(5, from: state, outOfBounds: true)
        Rules.apply(play, to: &state)
        XCTAssertFalse(state.clock.isRunning)
    }

    func testQuarterExpiryAdvancesTheQuarterAndSwapsEnds() {
        var state = makeState(quarterLength: 10)
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        let directionBefore = state.homeDirection
        let play = gain(3, from: state, elapsed: 20)
        Rules.apply(play, to: &state)
        XCTAssertEqual(state.clock.quarter, 2)
        XCTAssertEqual(state.homeDirection, -directionBefore)
        XCTAssertEqual(state.clock.remaining, 10, accuracy: 0.001)
    }

    func testHalftimeHandsTheBallToTheOtherReceiver() {
        var state = makeState(quarterLength: 10)
        Rules.startKickoff(receiving: .home, &state)
        state.clock.quarter = 2
        state.possession = .away
        Rules.setFirstDown(&state, at: 40, y: Field.midfieldY)
        let play = gain(2, from: state, elapsed: 30)
        let next = Rules.apply(play, to: &state)
        XCTAssertEqual(next, .halftime)
        XCTAssertEqual(state.clock.quarter, 3)
        // Home received to open the game, so home kicks off to start the half.
        XCTAssertEqual(state.possession, .home)
        XCTAssertTrue(state.pendingKickoff)
        XCTAssertEqual(state.timeouts, [3, 3])
    }

    func testTheGameEndsAfterTheFourthQuarter() {
        var state = makeState(quarterLength: 10)
        state.clock.quarter = 4
        Rules.giveBall(to: .home, at: 40, y: Field.midfieldY, &state)
        let play = gain(3, from: state, elapsed: 20)
        let next = Rules.apply(play, to: &state)
        XCTAssertEqual(next, .final)
        XCTAssertTrue(state.clock.isFinal)
    }

    func testTimeoutsAreSpentAndStopTheClock() {
        var state = makeState()
        state.clock.isRunning = true
        XCTAssertTrue(Rules.useTimeout(.home, &state))
        XCTAssertEqual(state.timeouts[TeamSide.home.rawValue], 2)
        XCTAssertFalse(state.clock.isRunning)
        state.timeouts[TeamSide.home.rawValue] = 0
        XCTAssertFalse(Rules.useTimeout(.home, &state))
    }
}
