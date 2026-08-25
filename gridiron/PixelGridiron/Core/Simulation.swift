//  Simulation.swift
//  One play, from the snap to the whistle.
//
//  The simulation is deterministic: same `PlaySetup` seed plus the same sequence
//  of `PlayInput` values produces the same `PlayResult` every time. It is stepped
//  at a fixed 1/60 by the scene, never at the display's variable delta, because
//  a variable step would make that guarantee worthless.
//
//  Steering behaviour for each assignment lives in SimulationAI.swift.

import Foundation

final class PlaySimulation {

    // MARK: - State

    /// Writable from SimulationAI.swift, which lives in the same module.
    var players: [SimPlayer] = []
    var ball: BallLocation = .dead(position: .zero)
    private(set) var elapsed: Double = 0
    private(set) var result: PlayResult?

    let setup: PlaySetup
    let lineOfScrimmage: Double
    let lineToGain: Double

    var rng: RNG

    /// True once the ball has changed hands mid-play — an interception, a fumble
    /// recovery, or a kick being fielded. Everything downstream reads
    /// `offenseDirection` and `isAttacking(_:)` rather than the original sides,
    /// so a return needs no special-case code anywhere else.
    var turnover = false

    private(set) var snapped = false
    private var handoffTo: Int?
    private var handoffAt: Double = 0
    private var throwReleaseAt: Double?
    private var throwTargetID: Int?
    /// Set when the ball has been kicked and the coverage should sprint.
    var kickInFlight = false
    var lastCarrierID: Int?
    var passWasAttempted = false
    var passWasCompleted = false
    /// Where a field goal was kicked from, for the missed-kick takeover spot.
    var kickFromSpot: Double = 0
    var fieldGoalBlocked = false
    /// Decided the moment the ball leaves the foot; the flight is just theatre.
    var fieldGoalGood: Bool?
    /// Set when a punt or kickoff is heading out the back of the end zone.
    var kickIsTouchback = false
    /// Time at which the ball leaves the kicker's foot, once a kick play is snapped.
    var pendingKickAt: Double?

    /// Set by the kick meter so the renderer can draw the ball at the posts.
    var kickTargetDescription: String?

    // MARK: - Init

    init(setup: PlaySetup) {
        self.setup = setup
        self.lineOfScrimmage = setup.lineOfScrimmage
        self.lineToGain = setup.lineOfScrimmage + Double(setup.direction) * 10
        self.rng = RNG(seed: setup.seed)
        buildFormations()
    }

    /// Direction the team currently holding the ball is attacking.
    var offenseDirection: Int { turnover ? -setup.direction : setup.direction }

    /// Is this player on the side that currently has the ball?
    func isAttacking(_ p: SimPlayer) -> Bool { p.isOffense != turnover }

    var isFinished: Bool { result != nil }

    // MARK: - Formation

    private func buildFormations() {
        let dir = Double(setup.direction)
        players.removeAll(keepingCapacity: true)

        func spot(_ node: RouteNode) -> Vec2 {
            Vec2(setup.lineOfScrimmage + dir * node.downfield,
                 clamp(setup.ballY + dir * node.lateral, 1.6, Field.width - 1.6))
        }

        for (i, profile) in setup.offenseRoster.offense.enumerated() {
            let align = setup.offensePlay.alignments[min(i, setup.offensePlay.alignments.count - 1)]
            var p = SimPlayer(id: profile.id,
                              profile: profile,
                              side: setup.offense,
                              isOffense: true,
                              unitIndex: i,
                              pos: spot(align))
            p.origin = p.pos
            p.facing = dir > 0 ? 0 : .pi
            p.offenseAssignment = setup.offensePlay.assignments[min(i, setup.offensePlay.assignments.count - 1)]
            players.append(p)
        }

        for (i, profile) in setup.defenseRoster.defense.enumerated() {
            let align = setup.defensePlay.alignments[min(i, setup.defensePlay.alignments.count - 1)]
            var p = SimPlayer(id: profile.id + 1000,
                              profile: profile,
                              side: setup.offense.opponent,
                              isOffense: false,
                              unitIndex: i,
                              pos: spot(align))
            p.origin = p.pos
            p.facing = dir > 0 ? .pi : 0
            p.defenseAssignment = setup.defensePlay.assignments[min(i, setup.defensePlay.assignments.count - 1)]
            players.append(p)
        }

        // Quarterback starts with the ball in his hands.
        if let qb = offenseIndex(0) {
            players[qb].hasBall = true
            ball = .held(playerID: players[qb].id)
        }
        resolveRoutes()
        assignUserControl()
    }

    /// Converts every route from team-local offsets into absolute field targets.
    private func resolveRoutes() {
        let dir = Double(setup.direction)
        for i in players.indices {
            guard players[i].isOffense else { continue }
            let route: [RouteNode]
            switch players[i].offenseAssignment {
            case .route(let nodes):
                route = nodes
            case .carry(let nodes):
                route = nodes
            case .delayedRoute(let delay, let nodes):
                route = nodes
                players[i].delayTimer = delay
            default:
                continue
            }
            let origin = players[i].origin
            players[i].routeTargets = route.map {
                Vec2(origin.x + dir * $0.downfield,
                     clamp(origin.y + dir * $0.lateral, 1.2, Field.width - 1.2))
            }
            players[i].routeSpeed = route.first?.speed ?? 1.0
        }
    }

    // MARK: - Lookups

    func offenseIndex(_ unitIndex: Int) -> Int? {
        players.firstIndex { $0.isOffense && $0.unitIndex == unitIndex }
    }

    func defenseIndex(_ unitIndex: Int) -> Int? {
        players.firstIndex { !$0.isOffense && $0.unitIndex == unitIndex }
    }

    func index(ofID id: Int) -> Int? {
        players.firstIndex { $0.id == id }
    }

    var carrierIndex: Int? {
        players.firstIndex { $0.hasBall }
    }

    var carrier: SimPlayer? {
        carrierIndex.map { players[$0] }
    }

    /// Eligible receivers, in the order the pass buttons appear.
    var passOptions: [Int] {
        players.enumerated()
            .filter { _, p in
                guard p.isOffense, !p.hasBall else { return false }
                switch p.offenseAssignment {
                case .route, .delayedRoute: return true
                default: return false
                }
            }
            .sorted { $0.element.unitIndex < $1.element.unitIndex }
            .map { $0.element.id }
    }

    var userPlayerID: Int? {
        players.first { $0.isUserControlled }?.id
    }

    var ballPosition: Vec2 {
        switch ball {
        case .held(let id):
            return index(ofID: id).map { players[$0].pos } ?? .zero
        case .flight(let f):
            return f.currentPosition
        case .loose(let p, _, _):
            return p
        case .dead(let p):
            return p
        }
    }

    var ballHeight: Double {
        if case .flight(let f) = ball { return f.currentHeight }
        return 0
    }

    var snapshot: PlaySnapshot {
        PlaySnapshot(players: players,
                     ball: ball,
                     ballPosition: ballPosition,
                     ballHeight: ballHeight,
                     elapsed: elapsed,
                     lineOfScrimmage: lineOfScrimmage,
                     lineToGain: lineToGain,
                     userPlayerID: userPlayerID,
                     passOptions: canThrow ? passOptions : [],
                     isFinished: isFinished)
    }

    /// The quarterback may throw while he holds the ball behind the line.
    var canThrow: Bool {
        guard snapped, !turnover, setup.offensePlay.isPassPlay, throwReleaseAt == nil else { return false }
        guard let c = carrierIndex, players[c].position == .quarterback else { return false }
        let behindLine = setup.direction > 0
            ? players[c].pos.x <= lineOfScrimmage + 0.2
            : players[c].pos.x >= lineOfScrimmage - 0.2
        return behindLine
    }

    // MARK: - Snap

    func snap() {
        guard !snapped else { return }
        snapped = true
        for i in players.indices where players[i].motion == .set {
            players[i].motion = .running
        }
        // Set up the handoff on run plays.
        if let rb = players.firstIndex(where: { $0.isOffense && isCarryAssignment($0.offenseAssignment) }) {
            handoffTo = players[rb].id
            handoffAt = setup.offensePlay.kind == .run ? 0.38 : 0
        }
        // Kicks are not instant: the snap, the hold and the step into the ball
        // all happen before the foot meets it.
        switch setup.offensePlay.kind {
        case .punt, .kickoff:
            pendingKickAt = 0.55
        case .fieldGoal, .extraPoint:
            pendingKickAt = 0.75
        default:
            break
        }
    }

    private func isCarryAssignment(_ a: OffenseAssignment?) -> Bool {
        if case .carry = a { return true }
        return false
    }

    // MARK: - Step

    /// Advances the play by `dt` seconds. Call with a fixed `dt`.
    func step(dt: Double, input: PlayInput) {
        guard result == nil else { return }
        guard snapped else {
            // Pre-snap: nobody moves, but the input is still read so the scene
            // can hand us a snap.
            if input.snapPressed { snap() }
            elapsed += dt
            if elapsed > Tuning.presnapTimeout { snap() }
            return
        }

        elapsed += dt

        if setup.offensePlay.kind == .kneel {
            finishKneel()
            return
        }

        updateTimers(dt)
        if let due = pendingKickAt, elapsed >= due {
            pendingKickAt = nil
            executeKick()
            if result != nil { return }
        }
        updateHandoff()
        assignUserControl()
        applyUserInput(input, dt: dt)
        driveAI(dt: dt)
        integrate(dt: dt)
        resolveEngagements(dt: dt)
        updateBall(dt: dt)
        resolveContact(dt: dt)
        checkBoundaries()

        if result == nil && elapsed > Tuning.maxPlayDuration {
            endPlay(.tackled(outOfBounds: false), at: ballPosition, headline: "PLAY BLOWN DEAD")
        }
    }

    private func updateTimers(_ dt: Double) {
        for i in players.indices {
            players[i].motionTimer = max(0, players[i].motionTimer - dt)
            players[i].delayTimer = max(0, players[i].delayTimer - dt)
            players[i].shedImmunity = max(0, players[i].shedImmunity - dt)

            if players[i].isSprinting && players[i].motion == .running {
                players[i].stamina = max(0, players[i].stamina - Tuning.sprintDrainPerSecond * dt)
                if players[i].stamina <= Tuning.sprintExhausted { players[i].isSprinting = false }
            } else {
                players[i].stamina = min(1, players[i].stamina + Tuning.sprintRecoverPerSecond * dt)
            }

            switch players[i].motion {
            case .diving where players[i].motionTimer <= 0:
                players[i].motion = .stumbling
                players[i].motionTimer = Tuning.diveRecovery
            case .stumbling where players[i].motionTimer <= 0:
                players[i].motion = .running
            default:
                break
            }
        }
    }

    private func updateHandoff() {
        guard let targetID = handoffTo, elapsed >= handoffAt else { return }
        guard let from = carrierIndex, let to = index(ofID: targetID), from != to else {
            handoffTo = nil
            return
        }
        guard players[from].position == .quarterback else { handoffTo = nil; return }
        players[from].hasBall = false
        players[to].hasBall = true
        ball = .held(playerID: targetID)
        lastCarrierID = targetID
        handoffTo = nil
    }

    // MARK: - User control

    /// Decides which player the human is holding this frame.
    private func assignUserControl() {
        guard let userSide = setup.userSide else {
            for i in players.indices { players[i].isUserControlled = false }
            return
        }

        var target: Int?

        if let c = carrierIndex, players[c].side == userSide {
            // You always steer the man with the ball.
            target = c
        } else if case .flight(let f) = ball, !f.isKick,
                  let intended = f.intendedID, let idx = index(ofID: intended),
                  players[idx].side == userSide {
            // While a pass is in the air, you steer the receiver it is going to.
            target = idx
        } else if let existing = players.firstIndex(where: { $0.isUserControlled && $0.side == userSide }),
                  players[existing].motion != .down {
            target = existing
        } else {
            target = nearestToBall(side: userSide)
        }

        for i in players.indices { players[i].isUserControlled = (i == target) }
    }

    private func nearestToBall(side: TeamSide) -> Int? {
        let bp = ballPosition
        return players.indices
            .filter { players[$0].side == side && players[$0].motion != .down }
            .min { players[$0].pos.distanceSquared(to: bp) < players[$1].pos.distanceSquared(to: bp) }
    }

    /// Per-frame desired velocities, filled by user input and then by the AI
    /// in SimulationAI.swift. Rebuilt every frame; never read across frames.
    var desiredStore: [Vec2] = []

    private func applyUserInput(_ input: PlayInput, dt: Double) {
        desiredStore = Array(repeating: .zero, count: players.count)

        guard let userSide = setup.userSide,
              let ui = players.firstIndex(where: { $0.isUserControlled }) else { return }

        // Switching defenders.
        if input.actionPressed && !isAttacking(players[ui]) {
            if let next = nearestToBall(side: userSide), next != ui {
                players[ui].isUserControlled = false
                players[next].isUserControlled = true
                return
            }
        }

        let me = ui
        if players[me].canBeSteered {
            desiredStore[me] = input.stick.limited(to: 1) * players[me].topSpeed(at: elapsed)
            players[me].isSprinting = input.sprint
        }

        // Throwing.
        if let slot = input.passTargetSlot, canThrow {
            let options = passOptions
            if slot < options.count { beginThrow(to: options[slot]) }
        }

        // Dive: a lunging tackle on defence, a forward dive on offence.
        if input.divePressed && players[me].motion == .running {
            players[me].motion = .diving
            players[me].motionTimer = Tuning.diveDuration
            let aim = input.stick.lengthSquared > 0.04
                ? input.stick.normalized
                : Vec2.fromAngle(players[me].facing)
            players[me].vel = aim * players[me].topSpeed(at: elapsed) * Tuning.diveSpeedMultiplier
        }

        // Juke: a hard lateral step that costs stamina and shrugs a pursuit angle.
        if input.actionPressed && isAttacking(players[me]) && players[me].hasBall
            && players[me].motion == .running && players[me].stamina > 0.25 {
            let lateral = Vec2.fromAngle(players[me].facing).perpendicular
            let side: Double = input.stick.dot(lateral) >= 0 ? 1 : -1
            players[me].pos += lateral * side * 0.9
            players[me].stamina = max(0, players[me].stamina - 0.18)
            // Anyone locked onto him loses a step.
            for j in players.indices where !isAttacking(players[j]) {
                if players[j].pos.distance(to: players[me].pos) < 3.0 && rng.chance(0.55) {
                    players[j].motion = .stumbling
                    players[j].motionTimer = 0.3
                }
            }
        }
        _ = dt
    }

    // MARK: - Integration

    private func integrate(dt: Double) {
        for i in players.indices {
            guard players[i].motion != .down, players[i].motion != .set else {
                players[i].vel = .zero
                continue
            }

            let top = players[i].topSpeed(at: elapsed)

            if players[i].motion == .diving {
                // A dive is ballistic: no steering, just the launch velocity.
                players[i].pos += players[i].vel * dt
                players[i].pos = Field.clampToField(players[i].pos)
                continue
            }

            let want = desiredStore[i].limited(to: top)
            let accel = Tuning.acceleration(players[i].ratings)
            var v = players[i].vel

            if want.lengthSquared < 0.01 {
                // Coast to a stop rather than snapping.
                let damp = max(0, 1 - Tuning.idleDamping * dt)
                v *= damp
            } else {
                let delta = want - v
                let maxDelta = accel * dt
                v += delta.limited(to: maxDelta)
            }

            v = v.limited(to: top)
            players[i].vel = v
            players[i].pos += v * dt
            players[i].pos = Field.clampToField(players[i].pos)

            // Facing lags velocity so a cut reads as a turn rather than a snap.
            if v.lengthSquared > 0.25 {
                let targetAngle = v.angle
                var diff = targetAngle - players[i].facing
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                let maxTurn = Tuning.turnRate(players[i].ratings) * dt
                players[i].facing += clamp(diff, -maxTurn, maxTurn)
            }
        }

        separatePlayers()
    }

    /// Keeps bodies from occupying the same yard. Cheap O(n²) — n is 14.
    private func separatePlayers() {
        let minDist: Double = 0.85
        for i in players.indices {
            guard players[i].motion != .down else { continue }
            for j in (i + 1)..<players.count {
                guard players[j].motion != .down else { continue }
                let delta = players[j].pos - players[i].pos
                let dist = delta.length
                guard dist < minDist, dist > 1e-6 else { continue }
                let push = delta.normalized * ((minDist - dist) * 0.5)
                // The heavier man gives less ground.
                let wi = players[i].ratings.power
                let wj = players[j].ratings.power
                let total = max(1, wi + wj)
                players[i].pos -= push * (2 * wj / total)
                players[j].pos += push * (2 * wi / total)
                players[i].pos = Field.clampToField(players[i].pos)
                players[j].pos = Field.clampToField(players[j].pos)
            }
        }
    }

    // MARK: - Blocking

    private func resolveEngagements(dt: Double) {
        for i in players.indices {
            guard let partnerID = players[i].engagedWith, let j = index(ofID: partnerID) else { continue }
            let dist = players[i].pos.distance(to: players[j].pos)
            if dist > Tuning.disengageRadius || players[j].motion == .down || players[j].motion == .diving {
                breakEngagement(i)
                continue
            }
            guard players[i].isOffense else { continue }   // resolve each pair once

            // The rusher works to shed; the blocker works to hold.
            let blocker = players[i]
            let rusher = players[j]
            let advantage = rusher.ratings.power - blocker.ratings.blocking
            let rate = max(0.05, Tuning.shedBaseRate + advantage * Tuning.shedRatingWeight)
            players[j].shedProgress += rate * dt
            if players[j].shedProgress >= Tuning.shedThreshold {
                breakEngagement(i)
                players[j].shedImmunity = Tuning.shedImmunityTime
                players[j].shedProgress = 0
                players[i].motion = .stumbling
                players[i].motionTimer = 0.4
            }
        }
    }

    func breakEngagement(_ i: Int) {
        if let partnerID = players[i].engagedWith, let j = index(ofID: partnerID) {
            players[j].engagedWith = nil
            if players[j].motion == .engaged { players[j].motion = .running }
        }
        players[i].engagedWith = nil
        if players[i].motion == .engaged { players[i].motion = .running }
    }

    func engage(_ blocker: Int, with rusher: Int) {
        guard players[blocker].engagedWith == nil,
              players[rusher].engagedWith == nil,
              players[rusher].shedImmunity <= 0,
              players[rusher].motion == .running,
              players[blocker].motion == .running else { return }
        players[blocker].engagedWith = players[rusher].id
        players[rusher].engagedWith = players[blocker].id
        players[blocker].motion = .engaged
        players[rusher].motion = .engaged
        players[rusher].shedProgress = 0
    }

    // MARK: - Ball

    private func updateBall(dt: Double) {
        guard case .flight(var f) = ball else {
            if case .loose(let p, let v, let timer) = ball {
                updateLooseBall(position: p, velocity: v, timer: timer, dt: dt)
            }
            return
        }

        f.elapsed += dt
        if f.hasLanded {
            ball = .flight(f)
            if f.isFieldGoal {
                resolveFieldGoalArrival()
            } else if f.isKick {
                resolveKickArrival(f)
            } else {
                resolvePassArrival(f)
            }
        } else {
            ball = .flight(f)
        }
    }

    private func updateLooseBall(position: Vec2, velocity: Vec2, timer: Double, dt: Double) {
        var p = position + velocity * dt
        p = Field.clampToField(p)
        let v = velocity * max(0, 1 - 3.2 * dt)
        let remaining = timer - dt

        // First man there falls on it. On a kick that was muffed before it was
        // ever possessed, only the receiving team can fall on it — the arcade
        // simplification keeps a muff to "lost return yards" rather than opening
        // a possession case the rulebook here has no spot for.
        let kickNotYetFielded = isKickPlay && !turnover
        var best: Int?
        var bestDist = Tuning.recoveryRadius
        for i in players.indices where players[i].motion != .down {
            if kickNotYetFielded && isAttacking(players[i]) { continue }
            let d = players[i].pos.distance(to: p)
            if d < bestDist { bestDist = d; best = i }
        }
        if let winner = best {
            recoverFumble(by: winner, at: p)
            return
        }
        if remaining <= 0 || Field.isOutOfBounds(p) {
            // Nobody got there. The last team to have it keeps it where it stopped.
            recoverByDefault(at: p)
            return
        }
        ball = .loose(position: p, velocity: v, timer: remaining)
    }

    /// Starts a throw. The AI calls this once it has picked a target; the human
    /// path goes through `applyUserInput`.
    func forceThrow(to receiverID: Int) { beginThrow(to: receiverID) }

    private func beginThrow(to receiverID: Int) {
        guard throwReleaseAt == nil else { return }
        throwTargetID = receiverID
        throwReleaseAt = elapsed + Tuning.throwWindup
    }

    /// Releases a throw whose windup has completed. Called from `driveAI`.
    func releaseThrowIfDue() {
        guard let due = throwReleaseAt, elapsed >= due,
              let targetID = throwTargetID,
              let qb = carrierIndex, let r = index(ofID: targetID) else { return }
        throwReleaseAt = nil
        throwTargetID = nil

        let from = players[qb].pos
        let passSpeed = Tuning.passSpeedBase
            + players[qb].ratings.power * Tuning.passSpeedPerPower

        // Converge on a lead point: where the receiver will be when it arrives.
        var flightTime = from.distance(to: players[r].pos) / passSpeed
        var aim = players[r].pos
        for _ in 0..<3 {
            aim = players[r].pos + players[r].vel * (flightTime * Tuning.passLeadFactor)
            aim = Field.clampToField(aim)
            flightTime = from.distance(to: aim) / passSpeed
        }

        // Accuracy: awareness tightens the throw, pressure loosens it.
        let pressured = defendersNear(players[qb].pos, within: Tuning.pressureRadius, attacking: false) > 0
        let precision = 1.0 - clamp(players[qb].ratings.awareness / 140.0, 0, 0.85)
        var scatter = Tuning.passScatterBase * precision
        if pressured { scatter += Tuning.passScatterPressure * precision }
        let offset = Vec2(rng.bell() * scatter, rng.bell() * scatter)
        let landing = Field.clampToField(aim + offset)

        let distance = from.distance(to: landing)
        let duration = clamp(distance / passSpeed, Tuning.passFlightMin, Tuning.passFlightMax)
        let apex = min(distance * Tuning.passArcRatio, Tuning.passArcMax)

        players[qb].hasBall = false
        lastCarrierID = players[qb].id
        passWasAttempted = true
        ball = .flight(BallFlight(from: from, to: landing, duration: duration,
                                  apex: apex, thrownBy: players[qb].id,
                                  intendedID: targetID))
    }

    private func resolvePassArrival(_ f: BallFlight) {
        let landing = f.to

        // Everyone with a shot at the ball, nearest first.
        let contenders = players.indices
            .filter { players[$0].motion != .down }
            .map { ($0, players[$0].pos.distance(to: landing)) }
            .filter { $0.1 <= Tuning.catchRadius }
            .sorted { $0.1 < $1.1 }

        guard !contenders.isEmpty else {
            endPlay(.incomplete, at: landing, headline: "INCOMPLETE")
            return
        }

        let offenseCandidate = contenders.first { isAttacking(players[$0.0]) }
        let defenseCandidate = contenders.first { !isAttacking(players[$0.0]) }

        // A defender who gets there first has a real chance at the pick.
        if let def = defenseCandidate,
           offenseCandidate == nil || def.1 < (offenseCandidate?.1 ?? .infinity) {
            let d = players[def.0]
            var pick = Tuning.interceptShare
                + (d.ratings.hands + d.ratings.coverage - 100) * 0.5 * Tuning.interceptRatingWeight
            pick = clamp(pick, 0.05, 0.8)
            if rng.chance(pick) {
                intercept(by: def.0, at: landing)
            } else {
                endPlay(.incomplete, at: landing, headline: "BROKEN UP")
            }
            return
        }

        guard let rec = offenseCandidate else {
            endPlay(.incomplete, at: landing, headline: "INCOMPLETE")
            return
        }

        let r = players[rec.0]
        var chance = Tuning.catchBaseChance + (r.ratings.hands - 50) * Tuning.catchRatingWeight
        // Contested: a defender in the neighbourhood makes it harder.
        if let def = defenseCandidate {
            let contest = clamp(1.0 - def.1 / (Tuning.catchRadius * 1.6), 0, 1)
            chance -= contest * (0.22 + (players[def.0].ratings.coverage - 50) * 0.003)
        }
        chance = clamp(chance, 0.12, 0.99)

        if rng.chance(chance) {
            complete(to: rec.0, at: landing)
        } else if let def = defenseCandidate, rng.chance(Tuning.interceptShare * 0.6) {
            intercept(by: def.0, at: landing)
        } else {
            endPlay(.incomplete, at: landing, headline: rec.1 < 0.7 ? "DROPPED" : "INCOMPLETE")
        }
    }

    private func complete(to index: Int, at landing: Vec2) {
        players[index].hasBall = true
        players[index].pos = landing
        lastCarrierID = players[index].id
        passWasCompleted = true
        ball = .held(playerID: players[index].id)
        // Receivers who were running routes now block for the catch.
        for i in players.indices where players[i].isOffense && i != index {
            if case .route = players[i].offenseAssignment {
                players[i].offenseAssignment = .runBlock(lateralBias: 0)
            }
        }
    }

    private func intercept(by index: Int, at landing: Vec2) {
        turnover = true
        players[index].hasBall = true
        players[index].pos = landing
        lastCarrierID = players[index].id
        ball = .held(playerID: players[index].id)
        flipAssignmentsForReturn(carrier: index)
    }

    /// After a change of possession the eleven — well, thirteen — other players
    /// need new jobs: the new offence blocks, the new defence pursues.
    func flipAssignmentsForReturn(carrier: Int) {
        for i in players.indices where i != carrier {
            if isAttacking(players[i]) {
                players[i].offenseAssignment = .runBlock(lateralBias: 0)
                players[i].defenseAssignment = nil
            } else {
                players[i].defenseAssignment = .runFill(lateralBias: 0)
                players[i].offenseAssignment = nil
            }
            breakEngagement(i)
        }
    }

    // MARK: - Fumbles

    private func fumble(from index: Int, hitBy tackler: Int) {
        players[index].hasBall = false
        let direction = (players[index].pos - players[tackler].pos).normalized
        let kick = direction * rng.double(3.0, 7.5) + Vec2(rng.bell(), rng.bell()) * 1.6
        ball = .loose(position: players[index].pos, velocity: kick, timer: Tuning.looseBallDuration)
        players[index].motion = .down
        players[index].vel = .zero
    }

    /// True for punts and kickoffs, where a loose ball follows different rules.
    var isKickPlay: Bool {
        setup.offensePlay.kind == .punt || setup.offensePlay.kind == .kickoff
    }

    private func recoverFumble(by index: Int, at spot: Vec2) {
        let recoveredByOffense = isAttacking(players[index])
        players[index].hasBall = true
        players[index].pos = spot
        ball = .held(playerID: players[index].id)
        lastCarrierID = players[index].id

        if recoveredByOffense {
            // Offence fell on its own fumble — the play is over there.
            endPlay(.fumble(recoveredBy: setup.offense, at: spot, returnedForTouchdown: false),
                    at: spot, headline: "FUMBLE — OFFENSE RECOVERS")
        } else {
            turnover = true
            flipAssignmentsForReturn(carrier: index)
            // The recovery is live: the defender can run with it.
        }
    }

    private func recoverByDefault(at spot: Vec2) {
        if isKickPlay && !turnover {
            let ending: PlayEnding = setup.offensePlay.kind == .punt
                ? .punt(spot: spot, touchback: false, returnedForTouchdown: false)
                : .kickoff(spot: spot, touchback: false, returnedForTouchdown: false)
            endPlay(ending, at: spot, headline: "MUFFED — BALL DEAD")
            return
        }
        endPlay(.fumble(recoveredBy: setup.offense, at: spot, returnedForTouchdown: false),
                at: spot, headline: "FUMBLE — BALL DEAD")
    }

    // MARK: - Contact

    private func resolveContact(dt: Double) {
        guard let c = carrierIndex, players[c].motion != .down else { return }
        let carrierPos = players[c].pos

        for i in players.indices {
            guard i != c, !isAttacking(players[i]), players[i].motion != .down else { continue }
            guard players[i].engagedWith == nil else { continue }

            let reach = players[i].motion == .diving ? Tuning.diveRadius : Tuning.tackleRadius
            guard players[i].pos.distance(to: carrierPos) <= reach else { continue }

            attemptTackle(by: i, on: c)
            if result != nil { return }
            if players[c].motion == .down { return }
        }
        _ = dt
    }

    private func attemptTackle(by tackler: Int, on carrierIdx: Int) {
        let t = players[tackler]
        let c = players[carrierIdx]

        var chance = Tuning.tackleBaseChance
        chance += (t.ratings.tackling - c.ratings.power) * Tuning.tackleRatingWeight
        if c.isSprinting { chance -= Tuning.tackleSprintPenalty }
        if t.motion == .diving { chance += 0.18 }

        // Meeting him head-on is a better tackle than chasing from behind.
        let closing = (c.pos - t.pos).normalized
        let facing = Vec2.fromAngle(t.facing)
        chance += facing.dot(closing) * Tuning.tackleAngleWeight

        // A carrier who has already broken tackles is running out of magic.
        chance += Double(c.brokenTackles) * 0.12
        if c.brokenTackles >= Tuning.maxBrokenTackles { chance = 1.0 }

        chance = clamp(chance, 0.05, 0.99)

        if rng.chance(chance) {
            // Down he goes — unless the ball comes out.
            var fumbleChance = Tuning.fumbleBaseChance
                + (t.ratings.power - c.ratings.hands) * Tuning.fumbleRatingWeight
            if c.position == .quarterback && isBehindLine(c.pos) {
                fumbleChance *= Tuning.sackFumbleMultiplier
            }
            fumbleChance = clamp(fumbleChance, 0, 0.14)

            if rng.chance(fumbleChance) {
                fumble(from: carrierIdx, hitBy: tackler)
                return
            }

            players[carrierIdx].motion = .down
            players[carrierIdx].vel = .zero
            players[tackler].motion = .down
            players[tackler].vel = .zero
            concludeTackle(carrierIdx: carrierIdx)
        } else {
            players[carrierIdx].brokenTackles += 1
            players[carrierIdx].slowUntil = elapsed + Tuning.brokenTackleCarrierSlowTime
            players[carrierIdx].slowFactor = Tuning.brokenTackleCarrierSlow
            players[tackler].motion = .stumbling
            players[tackler].motionTimer = Tuning.brokenTackleStumbleTime
            players[tackler].vel *= 0.2
        }
    }

    private func isBehindLine(_ p: Vec2) -> Bool {
        setup.direction > 0 ? p.x < lineOfScrimmage : p.x > lineOfScrimmage
    }

    /// Turns a completed tackle into a play result.
    private func concludeTackle(carrierIdx: Int) {
        let spot = players[carrierIdx].pos
        let dir = offenseDirection

        // A carrier down in the end zone he is defending is a safety, and
        // `offenseDirection` already accounts for a return — so this reads
        // correctly for an interception run backwards into your own end zone.
        if Field.inOwnEndZone(spot, direction: dir) {
            let conceding = turnover ? setup.offense.opponent : setup.offense
            endPlay(.safety(concededBy: conceding), at: spot, headline: "SAFETY")
            return
        }

        if turnover {
            endPlay(returnEnding(at: spot, touchdown: false), at: spot,
                    headline: returnHeadline(at: spot))
            return
        }

        let gained = Double(setup.direction) * (spot.x - lineOfScrimmage)
        let wasSack = players[carrierIdx].position == .quarterback
            && setup.offensePlay.isPassPlay && gained < 0
        if wasSack {
            endPlay(.sack, at: spot, headline: "SACKED FOR \(Int(abs(gained).rounded()))")
        } else {
            endPlay(.tackled(outOfBounds: false), at: spot, headline: gainHeadline(gained))
        }
    }

    private func gainHeadline(_ gained: Double) -> String {
        let yards = Int(gained.rounded())
        if yards == 0 { return "NO GAIN" }
        if yards < 0 { return "LOSS OF \(abs(yards))" }
        return "GAIN OF \(yards)"
    }

    private func returnEnding(at spot: Vec2, touchdown: Bool) -> PlayEnding {
        switch setup.offensePlay.kind {
        case .punt:
            return .punt(spot: spot, touchback: false, returnedForTouchdown: touchdown)
        case .kickoff:
            return .kickoff(spot: spot, touchback: false, returnedForTouchdown: touchdown)
        default:
            if passWasAttempted && !passWasCompleted {
                return .interception(returnedTo: spot, returnedForTouchdown: touchdown)
            }
            return .fumble(recoveredBy: setup.offense.opponent, at: spot,
                           returnedForTouchdown: touchdown)
        }
    }

    private func returnHeadline(at spot: Vec2) -> String {
        if setup.offensePlay.kind == .punt { return "PUNT RETURNED" }
        if setup.offensePlay.kind == .kickoff { return "KICK RETURNED" }
        if passWasAttempted && !passWasCompleted { return "INTERCEPTED" }
        return "FUMBLE RECOVERED"
    }

    // MARK: - Boundaries

    private func checkBoundaries() {
        guard result == nil, let c = carrierIndex, players[c].motion != .down else { return }
        let p = players[c].pos
        let dir = offenseDirection

        if Field.brokeThePlane(p, direction: dir) {
            players[c].motion = .celebrating
            if turnover {
                endPlay(returnEnding(at: p, touchdown: true), at: p, headline: "TOUCHDOWN!")
            } else {
                endPlay(.touchdown, at: p, headline: "TOUCHDOWN!")
            }
            return
        }

        if p.y <= Field.southSideline + 0.05 || p.y >= Field.northSideline - 0.05 {
            players[c].motion = .down
            if turnover {
                endPlay(returnEnding(at: p, touchdown: false), at: p, headline: returnHeadline(at: p))
            } else {
                let gained = Double(setup.direction) * (p.x - lineOfScrimmage)
                endPlay(.tackled(outOfBounds: true), at: p,
                        headline: "OUT OF BOUNDS · \(gainHeadline(gained))")
            }
        }
    }

    // MARK: - Ending a play

    func endPlay(_ rawEnding: PlayEnding, at spot: Vec2, headline: String) {
        guard result == nil else { return }
        // A two-point try is not a down and cannot score six. Every way it can
        // end collapses to "good" or "no good" before the rules ever see it.
        let ending = setup.isTwoPointTry ? convertTry(rawEnding) : rawEnding
        let gained = Double(setup.direction) * (spot.x - lineOfScrimmage)
        ball = .dead(position: spot)
        var line = headline
        if case .conversion(let good) = ending, setup.isTwoPointTry {
            line = good ? "TWO-POINT CONVERSION!" : "NO GOOD"
        }
        result = PlayResult(ending: ending,
                            endSpot: spot,
                            yardsGained: gained,
                            elapsed: elapsed * Tuning.clockSpeed,
                            headline: line,
                            ballCarrierID: lastCarrierID,
                            completedPass: passWasCompleted,
                            passAttempted: passWasAttempted)
        for i in players.indices where players[i].motion != .celebrating {
            players[i].motion = players[i].motion == .down ? .down : .set
            players[i].vel = .zero
        }
    }

    private func convertTry(_ ending: PlayEnding) -> PlayEnding {
        if case .conversion = ending { return ending }
        if case .touchdown = ending { return .conversion(good: true) }
        return .conversion(good: false)
    }

    private func finishKneel() {
        let spot = Vec2(lineOfScrimmage - Double(setup.direction), setup.ballY)
        endPlay(.kneel, at: spot, headline: "KNEEL DOWN")
    }
}
