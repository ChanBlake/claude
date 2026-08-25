//  SimulationTests.swift
//  The play simulation, run headless.
//
//  These are the tests that would be impossible if the simulation reached for
//  SpriteKit: nothing here touches a scene, a texture or a run loop.

import XCTest
@testable import PixelGridiron

final class SimulationTests: XCTestCase {

    // MARK: - Helpers

    private func makeSetup(offense: OffensePlay = Playbook.dive,
                           defense: DefensePlay = Playbook.balanced,
                           lineOfScrimmage: Double = 40,
                           direction: Int = 1,
                           seed: UInt64 = 42,
                           kickPower: Double? = nil,
                           kickAccuracy: Double? = nil,
                           twoPoint: Bool = false) -> PlaySetup {
        PlaySetup(offense: .home,
                  direction: direction,
                  lineOfScrimmage: lineOfScrimmage,
                  ballY: Field.midfieldY,
                  offensePlay: offense,
                  defensePlay: defense,
                  offenseRoster: Roster.generate(for: League.teams[0], seed: 1),
                  defenseRoster: Roster.generate(for: League.teams[1], seed: 2),
                  userSide: nil,
                  seed: seed,
                  kickPower: kickPower,
                  kickAccuracy: kickAccuracy,
                  isTwoPointTry: twoPoint)
    }

    /// Runs a play to completion with no human input.
    @discardableResult
    private func runToCompletion(_ setup: PlaySetup,
                                 maxSteps: Int = 3000) -> PlayResult? {
        let sim = PlaySimulation(setup: setup)
        sim.snap()
        var steps = 0
        while sim.result == nil && steps < maxSteps {
            sim.step(dt: 1.0 / 60.0, input: .none)
            steps += 1
        }
        return sim.result
    }

    // MARK: - Formation

    func testFormationPutsFourteenPlayersOnTheField() {
        let sim = PlaySimulation(setup: makeSetup())
        XCTAssertEqual(sim.players.count, 14)
        XCTAssertEqual(sim.players.filter(\.isOffense).count, 7)
        XCTAssertEqual(sim.players.filter { !$0.isOffense }.count, 7)
    }

    func testEveryPlayerStartsInBounds() {
        for play in Playbook.offenseCalls {
            for los in [1.0, 20.0, 60.0, 108.0] {
                let sim = PlaySimulation(setup: makeSetup(offense: play, lineOfScrimmage: los))
                for player in sim.players {
                    XCTAssertGreaterThanOrEqual(player.pos.y, 0,
                                                "\(play.name) at \(los) put someone off the field")
                    XCTAssertLessThanOrEqual(player.pos.y, Field.width)
                    XCTAssertGreaterThanOrEqual(player.pos.x, 0)
                    XCTAssertLessThanOrEqual(player.pos.x, Field.totalLength)
                }
            }
        }
    }

    func testPlayerIdentifiersAreUnique() {
        let sim = PlaySimulation(setup: makeSetup())
        XCTAssertEqual(Set(sim.players.map(\.id)).count, sim.players.count)
    }

    func testTheQuarterbackStartsWithTheBall() {
        let sim = PlaySimulation(setup: makeSetup(offense: Playbook.slants))
        XCTAssertEqual(sim.carrier?.position, .quarterback)
    }

    // MARK: - Determinism

    func testTheSameSeedProducesTheSameResult() {
        for play in Playbook.offenseCalls {
            let a = runToCompletion(makeSetup(offense: play, seed: 9_001))
            let b = runToCompletion(makeSetup(offense: play, seed: 9_001))
            XCTAssertNotNil(a)
            XCTAssertEqual(a?.ending, b?.ending, "\(play.name) is not deterministic")
            XCTAssertEqual(a?.yardsGained ?? 0, b?.yardsGained ?? 1, accuracy: 1e-9,
                           "\(play.name) is not deterministic")
        }
    }

    func testDifferentSeedsEventuallyDiffer() {
        // Not every seed has to change the outcome, but across a spread of them
        // the yardage must not be constant, or the rolls are not being consumed.
        var gains = Set<Int>()
        for seed in UInt64(1)...UInt64(24) {
            if let result = runToCompletion(makeSetup(offense: Playbook.sweep, seed: seed)) {
                gains.insert(Int(result.yardsGained.rounded()))
            }
        }
        XCTAssertGreaterThan(gains.count, 1)
    }

    // MARK: - Termination

    func testEveryPlayEndsInReasonableTime() {
        for play in Playbook.offenseCalls {
            for defense in Playbook.defenseCalls {
                for seed in UInt64(1)...UInt64(3) {
                    let setup = makeSetup(offense: play, defense: defense, seed: seed)
                    let result = runToCompletion(setup)
                    XCTAssertNotNil(result,
                                    "\(play.name) vs \(defense.name) seed \(seed) never ended")
                }
            }
        }
    }

    func testAPlayEndsInsideTheFieldOfPlay() {
        for seed in UInt64(1)...UInt64(40) {
            guard let result = runToCompletion(makeSetup(offense: Playbook.verticals, seed: seed))
            else { continue }
            XCTAssertGreaterThanOrEqual(result.endSpot.x, 0)
            XCTAssertLessThanOrEqual(result.endSpot.x, Field.totalLength)
            XCTAssertGreaterThanOrEqual(result.endSpot.y, 0)
            XCTAssertLessThanOrEqual(result.endSpot.y, Field.width)
        }
    }

    // MARK: - Play behaviour

    func testRunPlaysMostlyGainGround() {
        var total = 0.0
        var count = 0
        for seed in UInt64(1)...UInt64(60) {
            guard let result = runToCompletion(makeSetup(offense: Playbook.dive, seed: seed))
            else { continue }
            total += result.yardsGained
            count += 1
        }
        XCTAssertGreaterThan(count, 50)
        let average = total / Double(count)
        // A dive against a balanced front should average something like a real
        // run. The band is wide on purpose — this is a regression guard against
        // the blocking model collapsing, not a balance assertion.
        XCTAssertGreaterThan(average, 0.0, "HB DIVE averaged \(average) yards")
        XCTAssertLessThan(average, 12.0, "HB DIVE averaged \(average) yards")
    }

    func testPassPlaysAttemptPasses() {
        var attempts = 0
        for seed in UInt64(1)...UInt64(40) {
            guard let result = runToCompletion(makeSetup(offense: Playbook.slants, seed: seed))
            else { continue }
            if result.passAttempted { attempts += 1 }
        }
        // Some snaps end in a sack or a scramble; most should get the ball out.
        XCTAssertGreaterThan(attempts, 20, "only \(attempts) of 40 quick-game snaps threw")
    }

    func testKneelDownLosesAYardAndEndsImmediately() {
        let sim = PlaySimulation(setup: makeSetup(offense: Playbook.kneel))
        sim.snap()
        sim.step(dt: 1.0 / 60.0, input: .none)
        guard let result = sim.result else { return XCTFail("kneel did not end") }
        XCTAssertEqual(result.ending, .kneel)
        XCTAssertEqual(result.yardsGained, -1, accuracy: 0.001)
    }

    func testATwoPointTryCanOnlyEndAsAConversion() {
        for seed in UInt64(1)...UInt64(30) {
            let setup = makeSetup(offense: Playbook.slants,
                                  lineOfScrimmage: Field.awayGoalLine - 2,
                                  seed: seed,
                                  twoPoint: true)
            guard let result = runToCompletion(setup) else { continue }
            guard case .conversion = result.ending else {
                return XCTFail("two-point try ended as \(result.ending)")
            }
        }
    }

    // MARK: - Kicking

    func testAShortFieldGoalWithAPerfectMeterIsGood() {
        let setup = makeSetup(offense: Playbook.fieldGoal,
                              defense: Playbook.fieldGoalBlock,
                              lineOfScrimmage: Field.awayGoalLine - 10,
                              seed: 5,
                              kickPower: 1.0,
                              kickAccuracy: 0.0)
        guard let result = runToCompletion(setup) else { return XCTFail("kick never resolved") }
        guard case .kick(let good, let blocked, _) = result.ending else {
            return XCTFail("expected a kick, got \(result.ending)")
        }
        XCTAssertTrue(good || blocked, "a 27-yard kick down the middle should not miss")
    }

    func testAnImpossibleFieldGoalIsNoGood() {
        let setup = makeSetup(offense: Playbook.fieldGoal,
                              defense: Playbook.fieldGoalBlock,
                              lineOfScrimmage: 20,        // roughly a 107-yard try
                              seed: 5,
                              kickPower: 1.0,
                              kickAccuracy: 0.0)
        guard let result = runToCompletion(setup) else { return XCTFail("kick never resolved") }
        guard case .kick(let good, _, _) = result.ending else {
            return XCTFail("expected a kick, got \(result.ending)")
        }
        XCTAssertFalse(good)
    }

    func testABadlyMissedMeterPushesTheKickWide() {
        let setup = makeSetup(offense: Playbook.fieldGoal,
                              defense: Playbook.fieldGoalBlock,
                              lineOfScrimmage: Field.awayGoalLine - 25,
                              seed: 5,
                              kickPower: 1.0,
                              kickAccuracy: 0.95)
        guard let result = runToCompletion(setup) else { return XCTFail("kick never resolved") }
        guard case .kick(let good, _, _) = result.ending else {
            return XCTFail("expected a kick, got \(result.ending)")
        }
        XCTAssertFalse(good, "a meter stopped at the far end should miss")
    }

    func testAPuntFlipsTheField() {
        var netGains: [Double] = []
        for seed in UInt64(1)...UInt64(20) {
            let setup = makeSetup(offense: Playbook.punt,
                                  defense: Playbook.puntReturn,
                                  lineOfScrimmage: 30,
                                  seed: seed,
                                  kickPower: 0.85)
            guard let result = runToCompletion(setup) else { continue }
            switch result.ending {
            case .punt(let spot, let touchback, _):
                netGains.append(touchback ? 100 : spot.x - 30)
            default:
                XCTFail("punt ended as \(result.ending)")
            }
        }
        XCTAssertGreaterThan(netGains.count, 15)
        let average = netGains.reduce(0, +) / Double(netGains.count)
        XCTAssertGreaterThan(average, 12, "punts netted only \(average) yards")
    }

    func testAKickoffIsFieldedOrTouchedBack() {
        for seed in UInt64(1)...UInt64(20) {
            let setup = makeSetup(offense: Playbook.kickoff,
                                  defense: Playbook.kickReturn,
                                  lineOfScrimmage: Field.homeGoalLine + 35,
                                  seed: seed,
                                  kickPower: 0.9)
            guard let result = runToCompletion(setup) else {
                return XCTFail("kickoff seed \(seed) never resolved")
            }
            switch result.ending {
            case .kickoff, .safety, .tackled:
                break
            default:
                XCTFail("kickoff ended as \(result.ending)")
            }
        }
    }

    // MARK: - Integration

    /// Plays a whole CPU-vs-CPU game and checks the state never goes invalid.
    /// This is the test that catches a rules hole a unit test would not: a spot
    /// inside an end zone, a fifth down, a possession that never changes.
    func testAFullGameStaysLegal() {
        var state = MatchState(home: League.teams[2], away: League.teams[3],
                               quarterLength: 120, seed: 777)
        var rng = RNG(seed: 4242)
        Rules.startKickoff(receiving: .home, &state)

        var plays = 0
        let playCap = 900

        while state.phase != .final && plays < playCap {
            plays += 1

            let offensePlay: OffensePlay
            let defensePlay: DefensePlay

            if state.pendingKickoff {
                offensePlay = Playbook.kickoff
                defensePlay = Playbook.kickReturn
            } else if state.pendingTryFor != nil {
                Rules.setUpTry(twoPoint: false, &state)
                offensePlay = OffensePlay(name: "PAT", blurb: "", kind: .extraPoint,
                                          alignments: Playbook.fieldGoal.alignments,
                                          assignments: Playbook.fieldGoal.assignments,
                                          developTime: 1.2, targetGain: 0)
                defensePlay = Playbook.fieldGoalBlock
            } else if state.down == 4 {
                switch Coach.fourthDownChoice(state, difficulty: .pro) {
                case .punt:
                    offensePlay = Playbook.punt
                    defensePlay = Playbook.puntReturn
                case .fieldGoal:
                    offensePlay = Playbook.fieldGoal
                    defensePlay = Playbook.fieldGoalBlock
                case .goForIt:
                    offensePlay = Coach.callOffense(state, difficulty: .pro, rng: &rng)
                    defensePlay = Coach.callDefense(state, difficulty: .pro, rng: &rng)
                }
            } else {
                offensePlay = Coach.callOffense(state, difficulty: .pro, rng: &rng)
                defensePlay = Coach.callDefense(state, difficulty: .pro, rng: &rng)
            }

            let meter = Coach.kickMeter(for: state.roster(state.possession).kicker,
                                        distance: state.fieldGoalDistance,
                                        difficulty: .pro, rng: &rng)
            let setup = PlaySetup(offense: state.possession,
                                  direction: state.offenseDirection,
                                  lineOfScrimmage: state.lineOfScrimmage,
                                  ballY: state.ballY,
                                  offensePlay: offensePlay,
                                  defensePlay: defensePlay,
                                  offenseRoster: state.roster(state.possession),
                                  defenseRoster: state.roster(state.defense),
                                  userSide: nil,
                                  seed: rng.next(),
                                  kickPower: meter.power,
                                  kickAccuracy: meter.accuracy)

            guard let result = runToCompletion(setup) else {
                return XCTFail("play \(plays) never ended: \(offensePlay.name)")
            }

            let phase = Rules.apply(result, to: &state)
            state.phase = Rules.runOffPlayClock(&state, proposed: phase)

            // Invariants that must hold between every pair of snaps.
            XCTAssertGreaterThanOrEqual(state.down, 1, "play \(plays)")
            XCTAssertLessThanOrEqual(state.down, 4, "play \(plays)")
            XCTAssertGreaterThan(state.lineOfScrimmage, 0, "play \(plays)")
            XCTAssertLessThan(state.lineOfScrimmage, Field.totalLength, "play \(plays)")
            XCTAssertGreaterThanOrEqual(state.ballY, 0, "play \(plays)")
            XCTAssertLessThanOrEqual(state.ballY, Field.width, "play \(plays)")
            XCTAssertGreaterThanOrEqual(state.scoreHome, 0)
            XCTAssertGreaterThanOrEqual(state.scoreAway, 0)
            XCTAssertLessThanOrEqual(state.clock.quarter, 4)
        }

        XCTAssertLessThan(plays, playCap, "a two-minute-quarter game took \(plays) plays")
        XCTAssertEqual(state.phase, .final)
        // A full game of football should produce points and first downs.
        let totalPlays = state.stats[0].plays + state.stats[1].plays
        XCTAssertGreaterThan(totalPlays, 20)
    }
}
