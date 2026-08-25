//  SimulationKicks.swift
//  Punts, kickoffs, field goals and extra points.
//
//  A kick is decided the instant it leaves the foot — the flight is theatre. That
//  is deliberate: a meter-based kick that could still be "saved" by the arc would
//  make the meter meaningless, and a kick that lands where the meter said it
//  would is the whole reason to have a meter.

import Foundation

extension PlaySimulation {

    /// The kicker for the team currently on offence.
    var kickerProfile: PlayerProfile {
        setup.offenseRoster.kicker
    }

    /// Called once the snap, the hold and the plant have played out.
    func executeKick() {
        switch setup.offensePlay.kind {
        case .punt:
            beginPunt()
        case .kickoff:
            beginKickoff()
        case .fieldGoal, .extraPoint:
            beginFieldGoal()
        default:
            break
        }
    }

    // MARK: - Field goals

    /// Distance of the current field-goal attempt, from the spot of the kick to
    /// the crossbar.
    var fieldGoalYardage: Double {
        let spot = lineOfScrimmage - Double(setup.direction) * 7
        let posts = Field.attackingGoalLine(direction: setup.direction)
            + Double(setup.direction) * 10
        return abs(posts - spot)
    }

    func beginFieldGoal() {
        let dir = Double(setup.direction)
        let spot = Vec2(lineOfScrimmage - dir * 7, setup.ballY)
        kickFromSpot = spot.x

        // Was anybody through clean at the snap? That is a block.
        let unblocked = players.contains { p in
            !isAttacking(p) && p.engagedWith == nil
                && p.pos.distance(to: spot) < 4.5
        }
        if unblocked && rng.chance(Tuning.kickBlockChance) {
            fieldGoalBlocked = true
            fieldGoalGood = false
            endPlay(.kick(good: false, blocked: true, fromSpot: kickFromSpot),
                    at: spot, headline: "BLOCKED!")
            return
        }

        let power = setup.kickPower ?? 0.8
        let accuracyError = setup.kickAccuracy ?? 0.0    // 0 is dead centre
        let distance = fieldGoalYardage

        // Range comes from the kicker's leg and how full the power meter was.
        let leg = Tuning.scaled(kickerProfile.ratings.power,
                                Tuning.kickRangeFloor, Tuning.kickRangeCeiling)
        let range = leg * (0.72 + 0.38 * clamp(power, 0, 1))
        let hasTheLeg = distance <= range

        // Sideways drift grows with distance and with how badly the accuracy
        // meter was stopped. A great kicker's meter is more forgiving.
        let steadiness = clamp(kickerProfile.ratings.awareness / 99.0, 0.2, 1.0)
        let effectiveError = abs(accuracyError) <= Tuning.kickAccuracySweetSpot
            ? 0.0
            : (abs(accuracyError) - Tuning.kickAccuracySweetSpot) * (accuracyError < 0 ? -1 : 1)
        let drift = effectiveError * Tuning.kickDriftPerError
            * (distance / 40.0) * (1.6 - steadiness)

        let postsX = Field.attackingGoalLine(direction: setup.direction) + dir * 10
        let aimY = clamp(setup.ballY + drift, 1.0, Field.width - 1.0)
        let good = hasTheLeg && abs(aimY - Field.midfieldY) <= Field.uprightWidth / 2

        fieldGoalGood = good
        kickIsTouchback = false

        // If the kick is short, land it where it actually died.
        let landingX = hasTheLeg ? postsX : spot.x + dir * range
        let landing = Field.clampToField(Vec2(landingX, aimY))
        let flightDistance = spot.distance(to: landing)

        kickInFlight = true
        ball = .flight(BallFlight(from: spot, to: landing,
                                  duration: clamp(flightDistance / 26.0, 0.7, 2.4),
                                  apex: min(flightDistance * 0.22, 9.0),
                                  thrownBy: kickerProfile.id,
                                  intendedID: nil,
                                  isKick: true,
                                  isFieldGoal: true))
        kickTargetDescription = good ? "GOOD" : (hasTheLeg ? "WIDE" : "SHORT")
    }

    func resolveFieldGoalArrival() {
        let good = fieldGoalGood ?? false
        let spot = ballPosition
        let isTry = setup.offensePlay.kind == .extraPoint || setup.isTwoPointTry
        let headline: String
        if good {
            headline = isTry ? "EXTRA POINT GOOD" : "FIELD GOAL IS GOOD!"
        } else {
            headline = "NO GOOD — \(kickTargetDescription ?? "MISSED")"
        }
        endPlay(.kick(good: good, blocked: fieldGoalBlocked, fromSpot: kickFromSpot),
                at: spot, headline: headline)
    }

    // MARK: - Punts

    func beginPunt() {
        let dir = Double(setup.direction)
        let spot = Vec2(lineOfScrimmage - dir * 12, setup.ballY)
        kickFromSpot = spot.x

        let power = setup.kickPower ?? 0.8
        let leg = Tuning.scaled(kickerProfile.ratings.power,
                                Tuning.puntDistanceFloor, Tuning.puntDistanceCeiling)
        let distance = leg * (0.65 + 0.45 * clamp(power, 0, 1))
        let drift = (setup.kickAccuracy ?? 0) * 9.0

        let landingX = spot.x + dir * distance
        let goalLine = Field.attackingGoalLine(direction: setup.direction)
        let intoEndZone = dir > 0 ? landingX >= goalLine : landingX <= goalLine

        let landing = Field.clampToField(
            Vec2(landingX, clamp(setup.ballY + drift, 1.5, Field.width - 1.5)))

        kickIsTouchback = intoEndZone
        kickInFlight = true
        launchKick(from: spot, to: landing,
                   hang: Tuning.puntHangTimeBase * (0.8 + 0.35 * clamp(power, 0, 1)))
        sendCoverageDownfield(to: landing)
    }

    // MARK: - Kickoffs

    func beginKickoff() {
        let dir = Double(setup.direction)
        let spot = Vec2(lineOfScrimmage, setup.ballY)
        kickFromSpot = spot.x

        let power = setup.kickPower ?? 0.85
        let leg = Tuning.scaled(kickerProfile.ratings.power,
                                Tuning.kickoffDistanceFloor, Tuning.kickoffDistanceCeiling)
        let distance = leg * (0.75 + 0.32 * clamp(power, 0, 1))
        let drift = (setup.kickAccuracy ?? 0) * 7.0

        let landingX = spot.x + dir * distance
        let goalLine = Field.attackingGoalLine(direction: setup.direction)
        let intoEndZone = dir > 0 ? landingX >= goalLine : landingX <= goalLine

        let landing = Field.clampToField(
            Vec2(landingX, clamp(setup.ballY + drift, 2.0, Field.width - 2.0)))

        kickIsTouchback = intoEndZone
        kickInFlight = true
        launchKick(from: spot, to: landing, hang: 3.6)
        sendCoverageDownfield(to: landing)
    }

    // MARK: - Shared kick plumbing

    private func launchKick(from: Vec2, to: Vec2, hang: Double) {
        let distance = from.distance(to: to)
        ball = .flight(BallFlight(from: from, to: to,
                                  duration: hang,
                                  apex: min(distance * 0.30, 14.0),
                                  thrownBy: kickerProfile.id,
                                  intendedID: nil,
                                  isKick: true,
                                  isFieldGoal: false))
        // The ball has left the kicking team's hands.
        for i in players.indices where players[i].hasBall {
            players[i].hasBall = false
        }
    }

    /// Everyone on the kicking team releases and runs at the landing spot.
    private func sendCoverageDownfield(to landing: Vec2) {
        for i in players.indices where isAttacking(players[i]) {
            players[i].offenseAssignment = .route([])
            players[i].routeTargets = [landing]
            players[i].routeIndex = 0
            players[i].routeSpeed = 1.0
            players[i].isSprinting = true
            breakEngagement(i)
        }
    }

    /// A punt or kickoff has come down.
    func resolveKickArrival(_ flight: BallFlight) {
        let landing = flight.to
        let isPunt = setup.offensePlay.kind == .punt

        if kickIsTouchback {
            let ending: PlayEnding = isPunt
                ? .punt(spot: landing, touchback: true, returnedForTouchdown: false)
                : .kickoff(spot: landing, touchback: true, returnedForTouchdown: false)
            endPlay(ending, at: landing, headline: "TOUCHBACK")
            return
        }

        // Whoever on the receiving team is closest fields it.
        var returner: Int?
        var bestDist = Double.infinity
        for i in players.indices where !isAttacking(players[i]) && players[i].motion != .down {
            let d = players[i].pos.distance(to: landing)
            if d < bestDist { bestDist = d; returner = i }
        }

        guard let r = returner, bestDist < 9.0 else {
            // Nobody near it — the ball is dead where it landed.
            let ending: PlayEnding = isPunt
                ? .punt(spot: landing, touchback: false, returnedForTouchdown: false)
                : .kickoff(spot: landing, touchback: false, returnedForTouchdown: false)
            endPlay(ending, at: landing, headline: isPunt ? "PUNT DOWNED" : "BALL DEAD")
            return
        }

        // Muffed catch: a returner with bad hands, under pressure, can drop it.
        let pressure = nearestOpponentDistance(to: landing, attacking: true)
        var muffChance = 0.05 - (players[r].ratings.hands - 50) * 0.0009
        if pressure < 3.0 { muffChance += 0.07 }
        if rng.chance(clamp(muffChance, 0, 0.2)) {
            players[r].pos = landing
            ball = .loose(position: landing,
                          velocity: Vec2(rng.bell(), rng.bell()) * 4.0,
                          timer: Tuning.looseBallDuration)
            return
        }

        turnover = true
        kickInFlight = false
        players[r].hasBall = true
        players[r].pos = landing
        lastCarrierID = players[r].id
        ball = .held(playerID: players[r].id)
        flipAssignmentsForReturn(carrier: r)
    }
}
