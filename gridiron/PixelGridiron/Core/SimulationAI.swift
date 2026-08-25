//  SimulationAI.swift
//  Steering behaviour for the thirteen players the human is not holding.
//
//  Every assignment resolves to a *desired velocity* for the frame. Nothing here
//  moves a player directly — `PlaySimulation.integrate` owns that, so the AI and
//  the human are subject to exactly the same acceleration and turn limits.

import Foundation

extension PlaySimulation {

    // MARK: - Entry point

    func driveAI(dt: Double) {
        releaseThrowIfDue()

        for i in players.indices {
            guard !players[i].isUserControlled else { continue }
            guard players[i].motion == .running || players[i].motion == .engaged else { continue }
            setDesired(i, isAttacking(players[i]) ? offenseSteering(i, dt) : defenseSteering(i, dt))
        }

        cpuQuarterbackDecision()
        cpuCarrierSprint()
    }

    // MARK: - Shared queries

    /// Distance from `point` to the nearest player on the given side of the ball.
    func nearestOpponentDistance(to point: Vec2, attacking: Bool) -> Double {
        var best = Double.infinity
        for p in players where p.motion != .down && isAttacking(p) == attacking {
            best = min(best, p.pos.distance(to: point))
        }
        return best
    }

    func defendersNear(_ point: Vec2, within radius: Double, attacking: Bool) -> Int {
        players.reduce(0) { count, p in
            guard p.motion != .down, isAttacking(p) == attacking else { return count }
            return p.pos.distance(to: point) <= radius ? count + 1 : count
        }
    }

    /// The defence breaks on the ball once it is clearly a run, a scramble, or
    /// loose. Before that, zone defenders honour their drops.
    var ballIsInPlay: Bool {
        if case .loose = ball { return true }
        guard let c = carrier else { return false }
        if c.position != .quarterback { return true }
        // A quarterback who has crossed the line is a runner.
        return offenseDirection > 0 ? c.pos.x > lineOfScrimmage : c.pos.x < lineOfScrimmage
    }

    /// Where the ball will be in `seconds`, for pursuit angles.
    func projectedBallPoint(_ seconds: Double) -> Vec2 {
        if case .flight(let f) = ball { return f.to }
        guard let c = carrier else { return ballPosition }
        return Field.clampToField(c.pos + c.vel * seconds)
    }

    private func setDesired(_ i: Int, _ v: Vec2) {
        desiredStore[i] = v
    }

    // MARK: - Offense

    private func offenseSteering(_ i: Int, _ dt: Double) -> Vec2 {
        let me = players[i]
        if me.hasBall { return carrierSteering(i) }

        switch me.offenseAssignment {
        case .dropback(let depth):
            return dropbackSteering(i, depth: depth)

        case .carry:
            // Waiting on the handoff — drift toward the mesh point.
            return followRoute(i, arriveRadius: 0.6)

        case .route:
            return routeSteering(i)

        case .delayedRoute:
            if players[i].delayTimer > 0 { return passProtectSteering(i) }
            return routeSteering(i)

        case .passProtect:
            return passProtectSteering(i)

        case .runBlock(let bias):
            return runBlockSteering(i, lateralBias: bias)

        case .none:
            return .zero
        }
    }

    /// The quarterback's drop, plus a step up or a slide away from pressure.
    private func dropbackSteering(_ i: Int, depth: Double) -> Vec2 {
        let me = players[i]
        let dir = Double(setup.direction)
        let target = Vec2(me.origin.x - dir * depth, me.origin.y)
        let top = me.topSpeed(at: elapsed)

        var steer = (target - me.pos)
        if steer.length < 0.5 { steer = .zero }

        // Feel the rush: slide away from the nearest unblocked defender.
        var escape = Vec2.zero
        for p in players where !isAttacking(p) && p.motion != .down && p.engagedWith == nil {
            let d = p.pos.distance(to: me.pos)
            if d < 4.5 {
                escape += (me.pos - p.pos).normalized * (4.5 - d)
            }
        }

        let combined = steer.normalized * 0.6 + escape.normalized * 0.9
        return combined.normalized * top * (escape.lengthSquared > 0 ? 0.85 : 0.55)
    }

    /// Runs the assigned route, then works back to open grass.
    private func routeSteering(_ i: Int) -> Vec2 {
        let me = players[i]
        if me.routeIndex < me.routeTargets.count {
            return followRoute(i, arriveRadius: 1.1)
        }
        // Route finished: drift away from the nearest defender, staying in bounds.
        let top = me.topSpeed(at: elapsed) * 0.75
        var away = Vec2.zero
        for p in players where !isAttacking(p) && p.motion != .down {
            let d = p.pos.distance(to: me.pos)
            if d < 7 { away += (me.pos - p.pos).normalized * (7 - d) }
        }
        if away.lengthSquared < 0.01 {
            // Nobody near — keep working downfield slowly.
            away = Vec2(Double(setup.direction), 0)
        }
        var v = away.normalized * top
        // Do not run yourself out of bounds.
        if me.pos.y < 3 { v.y = abs(v.y) }
        if me.pos.y > Field.width - 3 { v.y = -abs(v.y) }
        return v
    }

    private func followRoute(_ i: Int, arriveRadius: Double) -> Vec2 {
        var me = players[i]
        guard me.routeIndex < me.routeTargets.count else {
            players[i] = me
            return .zero
        }
        let target = me.routeTargets[me.routeIndex]
        let delta = target - me.pos
        if delta.length <= arriveRadius {
            me.routeIndex += 1
            players[i] = me
            if me.routeIndex >= me.routeTargets.count { return delta.normalized * me.topSpeed(at: elapsed) }
            return followRoute(i, arriveRadius: arriveRadius)
        }
        players[i] = me
        return delta.normalized * me.topSpeed(at: elapsed) * me.routeSpeed
    }

    /// Pass protection: pick up the most dangerous rusher and get in his way.
    private func passProtectSteering(_ i: Int) -> Vec2 {
        let me = players[i]
        if me.motion == .engaged { return anchorSteering(i) }

        guard let qb = players.firstIndex(where: {
            isAttacking($0) && $0.position == .quarterback
        }) else { return .zero }
        let protectPoint = players[qb].pos

        guard let threat = mostDangerousRusher(to: protectPoint, blocker: i) else {
            // Nobody to block: shuffle in front of the quarterback.
            let ahead = protectPoint + Vec2(Double(setup.direction) * 1.6, 0)
            return (ahead - me.pos).limited(to: 1).normalized * me.topSpeed(at: elapsed) * 0.5
        }

        let t = players[threat]
        // Aim at a point between the rusher and the quarterback, slightly on the
        // rusher's side so the blocker meets him rather than trailing him.
        let toQB = (protectPoint - t.pos).normalized
        let intercept = t.pos + toQB * Tuning.blockInterceptLead

        if me.pos.distance(to: t.pos) < Tuning.engageRadius {
            engage(i, with: threat)
            return .zero
        }
        return (intercept - me.pos).normalized * me.topSpeed(at: elapsed)
    }

    /// While engaged, a blocker drives his man away from the ball.
    private func anchorSteering(_ i: Int) -> Vec2 {
        let me = players[i]
        guard let partnerID = me.engagedWith, let j = index(ofID: partnerID) else { return .zero }
        let away = (players[j].pos - ballPosition).normalized
        return away * me.topSpeed(at: elapsed)
    }

    private func mostDangerousRusher(to point: Vec2, blocker: Int) -> Int? {
        var best: Int?
        var bestScore = Double.infinity
        for j in players.indices {
            let p = players[j]
            guard !isAttacking(p), p.motion == .running, p.engagedWith == nil, p.shedImmunity <= 0 else { continue }
            // Only rushers are worth blocking; coverage players are somebody
            // else's problem.
            switch p.defenseAssignment {
            case .rush, .containRush, .runFill, .spy, .none:
                break
            default:
                continue
            }
            // Prefer the man closest to the quarterback, tie-broken toward the
            // blocker so two blockers do not pick the same target.
            let score = p.pos.distance(to: point) * 1.0 + p.pos.distance(to: players[blocker].pos) * 0.35
            // Somebody else already has him.
            if players.contains(where: { $0.engagedWith == p.id }) { continue }
            if score < bestScore { bestScore = score; best = j }
        }
        return best
    }

    /// Run blocking: get to the play side and hit the first man there.
    private func runBlockSteering(_ i: Int, lateralBias: Double) -> Vec2 {
        let me = players[i]
        if me.motion == .engaged { return anchorSteering(i) }

        let dir = Double(setup.direction)
        // Blockers work ahead of the ball, biased toward the play side.
        let aimPoint = ballPosition + Vec2(dir * 3.0, dir * lateralBias * 4.0)

        var best: Int?
        var bestDist = Double.infinity
        for j in players.indices {
            let p = players[j]
            guard !isAttacking(p), p.motion == .running, p.engagedWith == nil, p.shedImmunity <= 0 else { continue }
            if players.contains(where: { $0.engagedWith == p.id }) { continue }
            let d = p.pos.distance(to: aimPoint)
            if d < bestDist { bestDist = d; best = j }
        }

        guard let target = best, bestDist < 14 else {
            return (aimPoint - me.pos).normalized * me.topSpeed(at: elapsed) * 0.8
        }

        if me.pos.distance(to: players[target].pos) < Tuning.engageRadius {
            engage(i, with: target)
            return .zero
        }
        let lead = players[target].pos + players[target].vel * 0.2
        return (lead - me.pos).normalized * me.topSpeed(at: elapsed)
    }

    /// The ball carrier, when the CPU is running him: head for the goal line,
    /// bending around traffic.
    private func carrierSteering(_ i: Int) -> Vec2 {
        let me = players[i]
        let dir = Double(offenseDirection)
        let top = me.topSpeed(at: elapsed)

        // A quarterback on a pass play holds his ground until he decides to run.
        if me.position == .quarterback && setup.offensePlay.isPassPlay && !turnover {
            let pressure = nearestOpponentDistance(to: me.pos, attacking: false)
            let shouldScramble = pressure < Tuning.qbScrambleRadius
                || elapsed > setup.offensePlay.developTime + Tuning.qbPanicTime * 1.6
            if !shouldScramble {
                if case .dropback(let depth) = me.offenseAssignment {
                    return dropbackSteering(i, depth: depth)
                }
                return .zero
            }
        }

        let goalX = Field.attackingGoalLine(direction: offenseDirection)
        var steer = Vec2(dir, 0)

        // Repel from defenders, weighted by how directly they are in the way.
        var avoid = Vec2.zero
        for p in players where !isAttacking(p) && p.motion != .down {
            let delta = me.pos - p.pos
            let d = delta.length
            guard d < Tuning.carrierAvoidRadius, d > 0.01 else { continue }
            // A defender behind you is not a threat.
            let ahead = (p.pos.x - me.pos.x) * dir
            let weight = ahead > -1 ? 1.0 : 0.25
            avoid += delta.normalized * ((Tuning.carrierAvoidRadius - d) / Tuning.carrierAvoidRadius) * weight
        }
        steer += avoid.normalized * Tuning.carrierAvoidWeight

        // Do not drift out of bounds unless there is nowhere else to go.
        if me.pos.y < 4 { steer.y += (4 - me.pos.y) * 0.4 }
        if me.pos.y > Field.width - 4 { steer.y -= (me.pos.y - (Field.width - 4)) * 0.4 }

        // Near the goal line, straight ahead beats clever.
        if abs(goalX - me.pos.x) < 6 { steer = Vec2(dir, steer.y * 0.3) }

        return steer.normalized * top
    }

    /// The CPU sprints when it is worth sprinting: in the open, or near the line
    /// to gain.
    private func cpuCarrierSprint() {
        guard let c = carrierIndex, !players[c].isUserControlled else { return }
        let openness = nearestOpponentDistance(to: players[c].pos, attacking: false)
        players[c].isSprinting = openness > 2.5 && players[c].stamina > Tuning.sprintUnlock
    }

    // MARK: - Defense

    private func defenseSteering(_ i: Int, _ dt: Double) -> Vec2 {
        let me = players[i]

        if me.motion == .engaged { return shedSteering(i) }

        // A kick in the air changes everyone's job: one man fields it, the rest
        // set the wall in front of where it is coming down.
        if kickInFlight, case .flight(let f) = ball, f.isKick, !f.isFieldGoal {
            return returnUnitSteering(i, landing: f.to)
        }

        // Once the ball is a live runner, everyone pursues.
        if ballIsInPlay { return pursuitSteering(i) }

        switch me.defenseAssignment {
        case .rush:
            return rushSteering(i, contain: 0)
        case .containRush(let side):
            return rushSteering(i, contain: side)
        case .manCover(let offenseIndex):
            return manCoverSteering(i, target: offenseIndex)
        case .zone(let depth, let lateral, let radius):
            return zoneSteering(i, depth: depth, lateral: lateral, radius: radius)
        case .runFill(let bias):
            return runFillSteering(i, bias: bias)
        case .spy:
            return spySteering(i)
        case .none:
            return pursuitSteering(i)
        }
    }

    /// The receiving team while a punt or kickoff is in the air.
    private func returnUnitSteering(_ i: Int, landing: Vec2) -> Vec2 {
        let me = players[i]
        let top = me.topSpeed(at: elapsed)

        // Closest man to the landing spot is the returner.
        var fielder: Int?
        var bestDist = Double.infinity
        for j in players.indices where !isAttacking(players[j]) && players[j].motion != .down {
            let d = players[j].pos.distance(to: landing)
            if d < bestDist { bestDist = d; fielder = j }
        }

        if fielder == i {
            let delta = landing - me.pos
            if delta.length < 0.5 { return .zero }
            return delta.normalized * top
        }

        // Everyone else forms up a few yards in front of the catch, between the
        // returner and the nearest coverage man.
        let dir = Double(setup.direction)
        let lane = Double(me.unitIndex - 3) * 3.0
        let wall = Field.clampToField(Vec2(landing.x - dir * 6.0,
                                           clamp(landing.y + lane, 2, Field.width - 2)))
        let delta = wall - me.pos
        if delta.length < 1.0 { return .zero }
        return delta.normalized * top * 0.9
    }

    /// An engaged rusher pushes toward the ball while he works to get free.
    private func shedSteering(_ i: Int) -> Vec2 {
        let me = players[i]
        return (ballPosition - me.pos).normalized * me.topSpeed(at: elapsed)
    }

    private func rushSteering(_ i: Int, contain: Double) -> Vec2 {
        let me = players[i]
        guard let qb = players.firstIndex(where: { isAttacking($0) && $0.hasBall })
                ?? players.firstIndex(where: { isAttacking($0) && $0.position == .quarterback })
        else { return .zero }

        var target = players[qb].pos
        if contain != 0 {
            // A contain rusher stays outside so the scramble has nowhere to go.
            target.y += contain * 2.6
        }
        // Aim slightly upfield of the quarterback so the rush closes rather than
        // chases.
        target.x -= Double(setup.direction) * 0.8
        return (target - me.pos).normalized * me.topSpeed(at: elapsed)
    }

    private func manCoverSteering(_ i: Int, target offenseIndex: Int) -> Vec2 {
        let me = players[i]
        guard let t = players.firstIndex(where: {
            isAttacking($0) && $0.unitIndex == offenseIndex
        }) else { return zoneSteering(i, depth: 10, lateral: 0, radius: 10) }

        let receiver = players[t]
        // Sit on the quarterback's side of the receiver, a cushion off.
        let cushionDir = Vec2(Double(setup.direction), 0)
        let lead = receiver.pos + receiver.vel * Tuning.reaction(me.ratings)
        var spot = lead - cushionDir * Tuning.coverageCushion

        // Better coverage means tighter mirroring; worse coverage lags.
        let quality = clamp(me.ratings.coverage / 99.0, 0.2, 1.0)
        spot = Vec2.lerp(receiver.pos, spot, quality)

        // If the ball is in the air toward this receiver, attack the catch point.
        if case .flight(let f) = ball, !f.isKick {
            if f.intendedID == receiver.id || f.to.distance(to: me.pos) < 8 {
                return (f.to - me.pos).normalized * me.topSpeed(at: elapsed)
            }
        }
        return (spot - me.pos).limited(to: 30).normalized * me.topSpeed(at: elapsed)
    }

    private func zoneSteering(_ i: Int, depth: Double, lateral: Double, radius: Double) -> Vec2 {
        let me = players[i]
        let dir = Double(setup.direction)
        let landmark = Vec2(clamp(lineOfScrimmage + dir * depth, 1, Field.totalLength - 1),
                            clamp(setup.ballY + dir * lateral, 2, Field.width - 2))

        // Ball in the air into my zone: go get it.
        if case .flight(let f) = ball, !f.isKick {
            if f.to.distance(to: landmark) < radius + 3 {
                return (f.to - me.pos).normalized * me.topSpeed(at: elapsed)
            }
        }

        // Otherwise sink toward the landmark and shade the deepest threat inside
        // the zone.
        var threat: Vec2?
        var bestDepth = -Double.infinity
        for p in players where isAttacking(p) && p.position.isReceiver {
            guard p.pos.distance(to: landmark) < radius else { continue }
            let downfield = (p.pos.x - lineOfScrimmage) * dir
            if downfield > bestDepth { bestDepth = downfield; threat = p.pos }
        }

        let target = threat.map { Vec2.lerp(landmark, $0, 0.55) } ?? landmark
        let delta = target - me.pos
        if delta.length < 0.8 { return .zero }
        return delta.normalized * me.topSpeed(at: elapsed) * (threat == nil ? 0.8 : 1.0)
    }

    private func runFillSteering(_ i: Int, bias: Double) -> Vec2 {
        let me = players[i]
        let dir = Double(setup.direction)
        // Sit in the gap and read; the pursuit branch takes over once it is a run.
        let gap = Vec2(lineOfScrimmage + dir * 1.5,
                       clamp(setup.ballY + dir * bias * 5.0, 2, Field.width - 2))
        let delta = gap - me.pos
        if delta.length < 1.0 {
            // Already home — creep toward the ball.
            return (ballPosition - me.pos).normalized * me.topSpeed(at: elapsed) * 0.4
        }
        return delta.normalized * me.topSpeed(at: elapsed) * 0.85
    }

    private func spySteering(_ i: Int) -> Vec2 {
        let me = players[i]
        guard let qb = players.firstIndex(where: {
            isAttacking($0) && $0.position == .quarterback
        }) else { return pursuitSteering(i) }
        let dir = Double(setup.direction)
        let spot = players[qb].pos + Vec2(dir * 4.0, 0)
        let delta = spot - me.pos
        if delta.length < 1.2 { return .zero }
        return delta.normalized * me.topSpeed(at: elapsed) * 0.9
    }

    /// Take an angle on the ball carrier rather than chasing his current spot.
    private func pursuitSteering(_ i: Int) -> Vec2 {
        let me = players[i]
        let lookahead = Tuning.pursuitLookahead * clamp(me.ratings.awareness / 60.0, 0.5, 1.6)
        let aim = projectedBallPoint(lookahead)
        let delta = aim - me.pos
        if delta.lengthSquared < 0.01 { return .zero }
        return delta.normalized * me.topSpeed(at: elapsed)
    }

    // MARK: - CPU quarterback

    private func cpuQuarterbackDecision() {
        guard !turnover, setup.offensePlay.isPassPlay else { return }
        guard let qb = carrierIndex,
              players[qb].position == .quarterback,
              !players[qb].isUserControlled else { return }
        guard canThrow else { return }

        let develop = setup.offensePlay.developTime
        let pressure = nearestOpponentDistance(to: players[qb].pos, attacking: false)
        let panicking = elapsed > develop + Tuning.qbPanicTime
        let underDuress = pressure < Tuning.pressureRadius

        // Give the play a chance to develop before looking to throw at all.
        guard elapsed >= develop * 0.55 || underDuress else { return }

        guard let target = bestReceiver(from: qb, desperate: panicking || underDuress) else {
            return
        }
        if elapsed >= develop || panicking || underDuress {
            forceThrow(to: target)
        }
    }

    /// Scores every route runner on how open he is and how much he would gain.
    private func bestReceiver(from qb: Int, desperate: Bool) -> Int? {
        let dir = Double(setup.direction)
        var best: Int?
        var bestScore = desperate ? -Double.infinity : 1.0

        for id in passOptions {
            guard let r = index(ofID: id), players[r].motion == .running else { continue }
            let p = players[r]
            let separation = nearestOpponentDistance(to: p.pos, attacking: false)
            let downfield = (p.pos.x - lineOfScrimmage) * dir
            let throwDistance = players[qb].pos.distance(to: p.pos)

            // Openness matters most; yardage breaks ties; very long throws are
            // discounted because they hang in the air.
            var score = separation * 1.6 + downfield * 0.28 - max(0, throwDistance - 26) * 0.5
            if p.pos.y < 2.5 || p.pos.y > Field.width - 2.5 { score -= 3 }
            if separation < 1.2 { score -= 4 }
            if score > bestScore { bestScore = score; best = r }
        }
        return best.map { players[$0].id }
    }
}
