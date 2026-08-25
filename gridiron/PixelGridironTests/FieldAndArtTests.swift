//  FieldAndArtTests.swift
//  Field geometry, and the integrity of the hand-written pixel grids.
//
//  The art tests look trivial until a grid is edited by hand and one row loses a
//  character — at which point the sprite silently shears and the bug looks like
//  a rendering problem rather than a typo.

import XCTest
@testable import PixelGridiron

final class FieldTests: XCTestCase {

    func testFieldDimensions() {
        XCTAssertEqual(Field.totalLength, 120, accuracy: 0.001)
        XCTAssertEqual(Field.homeGoalLine, 10, accuracy: 0.001)
        XCTAssertEqual(Field.awayGoalLine, 110, accuracy: 0.001)
        XCTAssertEqual(Field.midfieldX, 60, accuracy: 0.001)
    }

    func testYardsToGoalIsSymmetric() {
        XCTAssertEqual(Field.yardsToGoal(from: 60, direction: 1), 50, accuracy: 0.001)
        XCTAssertEqual(Field.yardsToGoal(from: 60, direction: -1), 50, accuracy: 0.001)
        XCTAssertEqual(Field.yardsToGoal(from: 100, direction: 1), 10, accuracy: 0.001)
        XCTAssertEqual(Field.yardsToGoal(from: 20, direction: -1), 10, accuracy: 0.001)
    }

    func testYardLineLabels() {
        XCTAssertEqual(Field.yardLineLabel(x: 60, direction: 1), "MIDFIELD")
        XCTAssertEqual(Field.yardLineLabel(x: 60, direction: -1), "MIDFIELD")
        XCTAssertEqual(Field.yardLineLabel(x: 100, direction: 1), "OPP 10")
        XCTAssertEqual(Field.yardLineLabel(x: 30, direction: 1), "OWN 20")
        XCTAssertEqual(Field.yardLineLabel(x: 90, direction: -1), "OWN 20")
    }

    func testPaintedNumbers() {
        XCTAssertEqual(Field.paintedNumber(atX: 60), 50)
        XCTAssertEqual(Field.paintedNumber(atX: 30), 20)
        XCTAssertEqual(Field.paintedNumber(atX: 90), 20)
        XCTAssertNil(Field.paintedNumber(atX: 63))
        XCTAssertNil(Field.paintedNumber(atX: 5))
    }

    func testBallIsSpottedOnAHashWhenItDiesNearASideline() {
        XCTAssertEqual(Field.hashSpot(for: 1), Field.southHash, accuracy: 0.001)
        XCTAssertEqual(Field.hashSpot(for: Field.width - 1), Field.northHash, accuracy: 0.001)
        // Between the hashes, the ball stays where it is.
        XCTAssertEqual(Field.hashSpot(for: Field.midfieldY), Field.midfieldY, accuracy: 0.001)
    }

    func testBreakingThePlane() {
        XCTAssertTrue(Field.brokeThePlane(Vec2(110.1, 20), direction: 1))
        XCTAssertFalse(Field.brokeThePlane(Vec2(109.9, 20), direction: 1))
        XCTAssertTrue(Field.brokeThePlane(Vec2(9.9, 20), direction: -1))
    }

    func testOwnEndZoneDetection() {
        XCTAssertTrue(Field.inOwnEndZone(Vec2(5, 20), direction: 1))
        XCTAssertFalse(Field.inOwnEndZone(Vec2(5, 20), direction: -1))
        XCTAssertTrue(Field.inOwnEndZone(Vec2(115, 20), direction: -1))
    }

    func testClampToFieldKeepsPointsOnTheSurface() {
        let clamped = Field.clampToField(Vec2(-40, 900))
        XCTAssertEqual(clamped.x, 0, accuracy: 0.001)
        XCTAssertEqual(clamped.y, Field.width, accuracy: 0.001)
    }
}

final class VectorTests: XCTestCase {

    func testNormalizingAZeroVectorIsSafe() {
        XCTAssertEqual(Vec2.zero.normalized, .zero)
        XCTAssertFalse(Vec2.zero.normalized.x.isNaN)
    }

    func testLimitedCapsLength() {
        let v = Vec2(30, 40)           // length 50
        XCTAssertEqual(v.limited(to: 10).length, 10, accuracy: 0.0001)
        XCTAssertEqual(v.limited(to: 100).length, 50, accuracy: 0.0001)
    }

    func testPerpendicularIsOrthogonal() {
        let v = Vec2(3, -7)
        XCTAssertEqual(v.dot(v.perpendicular), 0, accuracy: 1e-9)
    }
}

final class RandomTests: XCTestCase {

    func testTheSameSeedGivesTheSameSequence() {
        var a = RNG(seed: 12345)
        var b = RNG(seed: 12345)
        for _ in 0..<50 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testUnitStaysInRange() {
        var rng = RNG(seed: 7)
        for _ in 0..<5000 {
            let value = rng.unit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testChanceHonoursItsBounds() {
        var rng = RNG(seed: 3)
        for _ in 0..<200 {
            XCTAssertFalse(rng.chance(0))
            XCTAssertTrue(rng.chance(1))
        }
    }

    func testIntIsInclusive() {
        var rng = RNG(seed: 99)
        var seen = Set<Int>()
        for _ in 0..<400 { seen.insert(rng.int(1, 4)) }
        XCTAssertEqual(seen, [1, 2, 3, 4])
    }
}

final class PixelArtTests: XCTestCase {

    private func assertRectangular(_ grid: [String], _ name: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(grid.isEmpty, "\(name) is empty", file: file, line: line)
        let widths = Set(grid.map(\.count))
        XCTAssertEqual(widths.count, 1,
                       "\(name) has ragged rows: \(widths.sorted())", file: file, line: line)
    }

    func testEveryPlayerFrameIsRectangular() {
        for frame in PlayerFrame.allCases {
            assertRectangular(PixelArt.grid(frame), frame.rawValue)
        }
    }

    func testEveryPlayerFrameUsesOnlyKnownPaletteCharacters() {
        let known = Set(PixelArt.palette(for: League.teams[0]).keys).union(["."])
        for frame in PlayerFrame.allCases {
            for row in PixelArt.grid(frame) {
                for character in row {
                    XCTAssertTrue(known.contains(character),
                                  "\(frame.rawValue) uses unknown character '\(character)'")
                }
            }
        }
    }

    func testBallAndMarkerGridsAreRectangular() {
        assertRectangular(PixelArt.football, "football")
        assertRectangular(PixelArt.downMarker, "downMarker")
    }

    func testEveryFontGlyphIsFiveBySeven() {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 :-.,'!?&/()+%"
        for character in characters {
            let glyph = PixelFont.glyph(character)
            XCTAssertEqual(glyph.count, PixelFont.glyphHeight,
                           "'\(character)' has \(glyph.count) rows")
            for row in glyph {
                XCTAssertEqual(row.count, PixelFont.glyphWidth,
                               "'\(character)' has a row of \(row.count)")
            }
        }
    }

    func testMeasureMatchesRasterWidth() {
        for text in ["", "A", "HELLO", "1ST & 10", "IRONPORT ANCHORS"] {
            let bits = PixelFont.rasterize(text)
            XCTAssertEqual(bits.count, PixelFont.glyphHeight)
            XCTAssertEqual(bits[0].count, max(1, PixelFont.measure(text)),
                           "width mismatch for \"\(text)\"")
        }
    }

    func testUnknownCharactersFallBackRatherThanCrash() {
        let glyph = PixelFont.glyph("\u{1F600}")
        XCTAssertEqual(glyph.count, PixelFont.glyphHeight)
    }
}

final class TeamTests: XCTestCase {

    func testEveryTeamHasAUniqueAbbreviation() {
        let abbreviations = League.teams.map(\.abbreviation)
        XCTAssertEqual(Set(abbreviations).count, abbreviations.count)
        for abbreviation in abbreviations {
            XCTAssertEqual(abbreviation.count, 3, "\(abbreviation) is not three letters")
        }
    }

    func testRosterGenerationIsDeterministicAndComplete() {
        let a = Roster.generate(for: League.teams[0], seed: 5)
        let b = Roster.generate(for: League.teams[0], seed: 5)
        XCTAssertEqual(a.offense.map(\.number), b.offense.map(\.number))
        XCTAssertEqual(a.offense.map(\.position), Roster.offensePositions)
        XCTAssertEqual(a.defense.map(\.position), Roster.defensePositions)
        XCTAssertEqual(a.kicker.position, .kicker)
    }

    func testJerseyNumbersDoNotCollideWithinATeam() {
        for team in League.teams {
            let roster = Roster.generate(for: team, seed: 11)
            let numbers = roster.offense.map(\.number) + roster.defense.map(\.number)
                + [roster.kicker.number]
            XCTAssertEqual(Set(numbers).count, numbers.count,
                           "\(team.abbreviation) has duplicate numbers")
        }
    }

    func testRatingsStayInRange() {
        for team in League.teams {
            let roster = Roster.generate(for: team, seed: 3)
            for player in roster.offense + roster.defense + [roster.kicker] {
                let r = player.ratings
                for value in [r.speed, r.accel, r.agility, r.power, r.hands,
                              r.tackling, r.coverage, r.blocking, r.awareness] {
                    XCTAssertGreaterThanOrEqual(value, 1)
                    XCTAssertLessThanOrEqual(value, 99)
                }
            }
        }
    }

    func testStrongTeamsRateHigherThanWeakOnes() {
        let strongest = League.teams.max { $0.strength < $1.strength }!
        let weakest = League.teams.min { $0.strength < $1.strength }!
        let strongRoster = Roster.generate(for: strongest, seed: 8)
        let weakRoster = Roster.generate(for: weakest, seed: 8)
        let strongAverage = strongRoster.offense.map(\.ratings.speed).reduce(0, +) / 7
        let weakAverage = weakRoster.offense.map(\.ratings.speed).reduce(0, +) / 7
        XCTAssertGreaterThan(strongAverage, weakAverage)
    }
}

final class PlaybookTests: XCTestCase {

    func testEveryPlayHasAnAssignmentForEveryPlayer() {
        for play in Playbook.offenseCalls + [Playbook.punt, Playbook.fieldGoal,
                                             Playbook.kickoff, Playbook.kneel,
                                             Playbook.hailMary] {
            XCTAssertEqual(play.alignments.count, 7, "\(play.name) alignments")
            XCTAssertEqual(play.assignments.count, 7, "\(play.name) assignments")
        }
        for play in Playbook.defenseCalls + [Playbook.puntReturn, Playbook.fieldGoalBlock,
                                             Playbook.kickReturn] {
            XCTAssertEqual(play.alignments.count, 7, "\(play.name) alignments")
            XCTAssertEqual(play.assignments.count, 7, "\(play.name) assignments")
        }
    }

    func testEveryPassPlayHasSomebodyToThrowTo() {
        for play in Playbook.offenseCalls where play.isPassPlay {
            let receivers = play.assignments.filter {
                if case .route = $0 { return true }
                if case .delayedRoute = $0 { return true }
                return false
            }
            XCTAssertGreaterThanOrEqual(receivers.count, 2,
                                        "\(play.name) has \(receivers.count) receivers")
        }
    }

    func testManCoverageTargetsExist() {
        for play in Playbook.defenseCalls {
            for assignment in play.assignments {
                if case .manCover(let index) = assignment {
                    XCTAssertTrue((0..<7).contains(index),
                                  "\(play.name) covers a player that does not exist")
                }
            }
        }
    }

    func testEveryPlayHasATwoLineBlurb() {
        for play in Playbook.offenseCalls {
            XCTAssertFalse(play.name.isEmpty)
            XCTAssertTrue(play.blurb.contains("\n"), "\(play.name) blurb is one line")
        }
    }
}
