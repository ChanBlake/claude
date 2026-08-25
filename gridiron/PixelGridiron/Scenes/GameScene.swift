//  GameScene.swift
//  A game of football: the phase machine, the camera, and the bridge between
//  `PlaySimulation` and what is on screen.
//
//  The scene owns no rules. It asks `Rules` what a play meant and `Coach` what
//  the CPU wants, then arranges pixels accordingly. Everything that decides an
//  outcome lives in Core/ and is testable without a simulator.

import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

final class GameScene: SKScene {

    // MARK: - Configuration

    private let config: MatchConfig
    private var state: MatchState
    private var rng: RNG

    /// Called when the game is over.
    var onFinish: ((MatchOutcome) -> Void)?

    // MARK: - Scene graph

    private let world = SKNode()
    private let fieldNode = FieldNode()
    private let ballNode = BallNode()
    private var playerNodes: [PlayerNode] = []

    private let hudLayer = SKNode()
    private let hud = HUDNode()
    private let controlPad = ControlPad()
    private let playCall = PlayCallOverlay()
    private let kickMeter = KickMeterNode()
    private let pauseButton = PixelButton(identifier: "pause", title: "II", radius: 18,
                                          tint: Palette.panel)

    private let cameraNode = SKCameraNode()

    // MARK: - Flow

    /// What the *screen* is doing. `MatchState.phase` says what the rules think;
    /// this says what the player is looking at and what input is live.
    ///
    /// Timed states carry a countdown rather than a deadline, so they work
    /// identically whether they are entered from `didMove` (before any frame has
    /// a timestamp) or from the middle of an update.
    private enum Flow: Equatable {
        case choosingOffense
        case choosingDefense
        case kicking
        case presnap
        case live
        case deadBall(remaining: Double)
        case tryChoice
        /// The CPU has scored and is about to take its try.
        case cpuTry(remaining: Double, twoPoint: Bool)
        case waiting(remaining: Double, next: GamePhase)
        case finished
        case paused
    }

    private var flow: Flow = .waiting(remaining: 0.4, next: .kickoff)
    private var flowBeforePause: Flow?

    private var simulation: PlaySimulation?
    private var pendingOffensePlay: OffensePlay?
    private var pendingDefensePlay: DefensePlay?
    private var pendingKickKind: PendingKick = .kickoff
    private var availableOffenseCalls: [OffensePlay] = []

    private enum PendingKick { case fieldGoal, punt, kickoff, extraPoint }

    /// The clock as it stood at the snap. The scene ticks the clock live for
    /// the look of the thing; `Rules.apply` is the authority on how much time a
    /// play actually cost, so the live tick is rewound before the rules run.
    private var clockAtSnap: Double = 0

    private var lastUpdate: TimeInterval = 0
    private var accumulator: Double = 0
    private static let fixedStep: Double = 1.0 / 60.0

    // MARK: - Init

    init(config: MatchConfig, size: CGSize) {
        self.config = config
        self.state = MatchState(home: config.home,
                                away: config.away,
                                quarterLength: config.quarterSeconds,
                                seed: config.seed)
        self.rng = RNG(seed: config.seed ^ 0xA5A5_1234)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Palette.ink.skColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        buildSceneGraph()
        layoutInterface()
        SFX.shared.start()
        SFX.shared.stopMusic()
        Haptics.prepare()
        startGame()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard !playerNodes.isEmpty else { return }
        layoutInterface()
    }

    private func buildSceneGraph() {
        addChild(world)
        world.addChild(fieldNode)
        world.addChild(ballNode)

        for _ in 0..<14 {
            let node = PlayerNode()
            node.isHidden = true
            world.addChild(node)
            playerNodes.append(node)
        }

        camera = cameraNode
        addChild(cameraNode)

        hudLayer.zPosition = ZLayer.hud
        cameraNode.addChild(hudLayer)
        hudLayer.addChild(hud)
        hudLayer.addChild(controlPad)
        hudLayer.addChild(playCall)
        hudLayer.addChild(kickMeter)
        hudLayer.addChild(pauseButton)

        playCall.onSelect = { [weak self] index in self?.playCardTapped(index) }

        fieldNode.build(home: state.home, away: state.away, homeDirection: state.homeDirection)
    }

    private func layoutInterface() {
        // The HUD layer hangs off the camera with its origin at the bottom-left
        // of the screen, so every control is positioned in plain screen
        // coordinates no matter where the camera has wandered.
        hudLayer.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        hud.layout(in: size)
        controlPad.layout(in: size)
        playCall.layout(in: size)
        kickMeter.layout(in: size)
        pauseButton.position = CGPoint(x: 30, y: size.height - 30)
    }

    // MARK: - Starting

    private func startGame() {
        let receiving: TeamSide = rng.chance(0.5) ? .home : .away
        Rules.startKickoff(receiving: receiving, &state)
        hud.update(state)
        hud.showBanner("\(state.identity(receiving).abbreviation) RECEIVES", duration: 1.3)
        SFX.shared.play(.horn)
        flow = .waiting(remaining: 1.7, next: .kickoff)
    }

    // MARK: - Phase entry

    private func enterPhase(_ phase: GamePhase) {
        state.phase = phase
        hud.update(state)

        switch phase {
        case .kickoff:
            prepareKick(.kickoff)

        case .playCall:
            beginPlayCall()

        case .pointAfter:
            beginPointAfter()

        case .quarterBreak:
            hud.showBanner("END OF QUARTER", duration: 1.4)
            SFX.shared.play(.horn)
            flow = .waiting(remaining: 1.8, next: state.pendingKickoff ? .kickoff : .playCall)

        case .halftime:
            hud.showBanner("HALFTIME", duration: 1.8)
            SFX.shared.play(.horn)
            flow = .waiting(remaining: 2.2, next: .kickoff)

        case .final:
            finishGame()

        case .presnap, .live, .deadBall, .coinToss:
            break
        }
    }

    // MARK: - Play calling

    private func beginPlayCall() {
        simulation = nil
        clearField()

        // Burn the huddle. A quarter can expire here, between snaps.
        let after = Rules.runOffPlayClock(&state, proposed: .playCall)
        if after != .playCall {
            enterPhase(after)
            return
        }

        hud.update(state)
        fieldNode.build(home: state.home, away: state.away, homeDirection: state.homeDirection)
        fieldNode.update(lineOfScrimmage: state.lineOfScrimmage,
                         lineToGain: state.lineToGain,
                         hideGainLine: state.lineToGainIsGoalLine)
        centreCamera(on: Vec2(state.lineOfScrimmage, state.ballY), immediate: true)

        let situationLine = "\(state.ballOnText)   ·   \(state.clock.quarterLabel) \(state.clock.display)"

        guard let userSide = config.userSide else {
            // Attract mode: the CPU calls both sides.
            pendingOffensePlay = cpuOffenseCall()
            pendingDefensePlay = Coach.callDefense(state, difficulty: config.difficulty, rng: &rng)
            routeAfterOffenseCall()
            return
        }

        if state.possession == userSide {
            availableOffenseCalls = Coach.availableCalls(state)
            pendingDefensePlay = Coach.callDefense(state, difficulty: config.difficulty, rng: &rng)
            playCall.showOffense(availableOffenseCalls,
                                 title: "YOUR BALL · \(state.downAndDistanceText)",
                                 subtitle: situationLine,
                                 accent: state.identity(userSide).trim)
            controlPad.setMode(.hidden)
            flow = .choosingOffense
        } else {
            let call = cpuOffenseCall()
            pendingOffensePlay = call

            // There is no defence to call against a kick. Say what is coming and
            // go straight to the snap with the right return unit on the field.
            if call.kind == .punt || call.kind == .fieldGoal {
                hud.showBanner(call.kind == .punt ? "THEY PUNT" : "FIELD GOAL ATTEMPT",
                               duration: 1.2)
                prepareKick(call.kind == .punt ? .punt : .fieldGoal)
                return
            }

            playCall.showDefense(Playbook.defenseCalls,
                                 title: "THEIR BALL · \(state.downAndDistanceText)",
                                 subtitle: situationLine,
                                 accent: state.identity(userSide).trim)
            controlPad.setMode(.hidden)
            flow = .choosingDefense
        }
    }

    private func playCardTapped(_ index: Int) {
        SFX.shared.play(.uiSelect)
        Haptics.tap()

        switch flow {
        case .choosingOffense:
            guard index < availableOffenseCalls.count else { return }
            pendingOffensePlay = availableOffenseCalls[index]
            playCall.hide()
            routeAfterOffenseCall()

        case .choosingDefense:
            guard index < Playbook.defenseCalls.count else { return }
            pendingDefensePlay = Playbook.defenseCalls[index]
            playCall.hide()
            beginSnapSetup()

        case .tryChoice:
            playCall.hide()
            chooseTry(twoPoint: index == 1)

        default:
            break
        }
    }

    /// What the CPU offence wants, including the fourth-down decision that
    /// `Coach.callOffense` deliberately does not make for itself.
    private func cpuOffenseCall() -> OffensePlay {
        if state.down == 4 && state.pendingTryFor == nil && !state.pendingKickoff {
            switch Coach.fourthDownChoice(state, difficulty: config.difficulty) {
            case .punt: return Playbook.punt
            case .fieldGoal: return Playbook.fieldGoal
            case .goForIt: break
            }
        }
        return Coach.callOffense(state, difficulty: config.difficulty, rng: &rng)
    }

    /// A punt or field goal goes to the meter first; everything else snaps.
    private func routeAfterOffenseCall() {
        switch pendingOffensePlay?.kind {
        case .punt: prepareKick(.punt)
        case .fieldGoal: prepareKick(.fieldGoal)
        default: beginSnapSetup()
        }
    }

    // MARK: - Point after

    private func beginPointAfter() {
        clearField()
        guard let scoring = state.pendingTryFor else {
            enterPhase(.kickoff)
            return
        }
        SFX.shared.play(.touchdown)
        SFX.shared.play(.cheer)
        Haptics.success()
        hud.showBanner("TOUCHDOWN \(state.identity(scoring).abbreviation)!",
                       color: state.identity(scoring).trim, duration: 1.6)

        guard scoring == config.userSide else {
            let twoPoint = Coach.goesForTwo(state, difficulty: config.difficulty)
            flow = .cpuTry(remaining: 1.9, twoPoint: twoPoint)
            return
        }

        let kick = OffensePlay(name: "KICK THE POINT",
                               blurb: "One point, from the 15.\nAlmost automatic.",
                               kind: .extraPoint,
                               alignments: Playbook.fieldGoal.alignments,
                               assignments: Playbook.fieldGoal.assignments,
                               developTime: 1.2, targetGain: 0)
        let two = OffensePlay(name: "GO FOR TWO",
                              blurb: "Two points, one snap from the 2.\nOr nothing at all.",
                              kind: .pass,
                              alignments: Playbook.slants.alignments,
                              assignments: Playbook.slants.assignments,
                              developTime: 1.4, targetGain: 2)
        playCall.showOffense([kick, two],
                             title: "POINT AFTER TRY",
                             subtitle: "PICK YOUR POINTS",
                             accent: state.identity(scoring).trim)
        controlPad.setMode(.hidden)
        flow = .tryChoice
    }

    private func chooseTry(twoPoint: Bool) {
        Rules.setUpTry(twoPoint: twoPoint, &state)
        if twoPoint {
            pendingOffensePlay = Playbook.slants
            pendingDefensePlay = Playbook.runStuff
            beginSnapSetup(isTwoPointTry: true)
        } else {
            pendingOffensePlay = OffensePlay(name: "EXTRA POINT",
                                             blurb: "",
                                             kind: .extraPoint,
                                             alignments: Playbook.fieldGoal.alignments,
                                             assignments: Playbook.fieldGoal.assignments,
                                             developTime: 1.2, targetGain: 0)
            prepareKick(.extraPoint)
        }
    }

    // MARK: - Kicks

    private func prepareKick(_ kind: PendingKick) {
        clearField()
        pendingKickKind = kind

        switch kind {
        case .kickoff:
            pendingOffensePlay = Playbook.kickoff
            pendingDefensePlay = Playbook.kickReturn
        case .punt:
            pendingOffensePlay = Playbook.punt
            pendingDefensePlay = Playbook.puntReturn
        case .fieldGoal:
            pendingOffensePlay = Playbook.fieldGoal
            pendingDefensePlay = Playbook.fieldGoalBlock
        case .extraPoint:
            pendingDefensePlay = Playbook.fieldGoalBlock
        }

        fieldNode.build(home: state.home, away: state.away, homeDirection: state.homeDirection)
        fieldNode.update(lineOfScrimmage: state.lineOfScrimmage,
                         lineToGain: state.lineToGain,
                         hideGainLine: true)
        centreCamera(on: Vec2(state.lineOfScrimmage, state.ballY), immediate: true)
        hud.update(state)

        // The kicking team is whoever currently has the ball.
        let kicking = state.possession
        guard kicking == config.userSide else {
            let distance = (kind == .fieldGoal || kind == .extraPoint)
                ? state.fieldGoalDistance : 45
            let meter = Coach.kickMeter(for: state.roster(kicking).kicker,
                                        distance: distance,
                                        difficulty: config.difficulty,
                                        rng: &rng)
            beginSnapSetup(kickPower: meter.power, kickAccuracy: meter.accuracy)
            return
        }

        let label: String
        var speed = 1.15
        switch kind {
        case .fieldGoal:
            label = "FIELD GOAL · \(Int(state.fieldGoalDistance.rounded())) YARDS"
            // A longer kick gets a faster meter — the pressure is the point.
            speed = 1.0 + state.fieldGoalDistance / 90
        case .extraPoint:
            label = "EXTRA POINT"
            speed = 1.0
        case .punt:
            label = "PUNT"
        case .kickoff:
            label = "KICKOFF"
        }
        kickMeter.begin(title: label, speed: speed)
        controlPad.setMode(.kicking)
        flow = .kicking
    }

    // MARK: - Snapping

    private func beginSnapSetup(kickPower: Double? = nil,
                                kickAccuracy: Double? = nil,
                                isTwoPointTry: Bool = false) {
        guard let offensePlay = pendingOffensePlay,
              let defensePlay = pendingDefensePlay else { return }

        playCall.hide()
        kickMeter.dismiss()

        let setup = PlaySetup(offense: state.possession,
                              direction: state.offenseDirection,
                              lineOfScrimmage: state.lineOfScrimmage,
                              ballY: state.ballY,
                              offensePlay: offensePlay,
                              defensePlay: defensePlay,
                              offenseRoster: state.roster(state.possession),
                              defenseRoster: state.roster(state.defense),
                              userSide: config.userSide,
                              seed: rng.next(),
                              kickPower: kickPower,
                              kickAccuracy: kickAccuracy,
                              isTwoPointTry: isTwoPointTry)

        let sim = PlaySimulation(setup: setup)
        simulation = sim
        accumulator = 0
        clockAtSnap = state.clock.remaining
        syncNodes(dt: 0)

        let isScrimmagePlay = offensePlay.kind == .run
            || offensePlay.kind == .pass
            || offensePlay.kind == .screen
            || offensePlay.kind == .kneel
        fieldNode.update(lineOfScrimmage: state.lineOfScrimmage,
                         lineToGain: state.lineToGain,
                         hideGainLine: state.lineToGainIsGoalLine || !isScrimmagePlay)

        // The human snaps his own scrimmage plays; kicks and the CPU snap
        // themselves.
        let userIsOnOffense = config.userSide == state.possession
        if userIsOnOffense && isScrimmagePlay {
            controlPad.setMode(.presnap)
            flow = .presnap
        } else {
            sim.snap()
            SFX.shared.play(.snap)
            enterLive()
        }
    }

    private func enterLive() {
        flow = .live
        updateControlMode()
    }

    private func updateControlMode() {
        guard let sim = simulation, let userSide = config.userSide else {
            controlPad.setMode(.hidden)
            return
        }

        if let carrier = sim.carrier {
            if carrier.side == userSide {
                if sim.canThrow {
                    let labels = ["A", "B", "C", "D"]
                    let options = sim.passOptions
                    controlPad.setMode(.passing(labels: Array(labels.prefix(max(1, options.count)))))
                } else {
                    controlPad.setMode(.carrying)
                }
            } else {
                controlPad.setMode(.defending)
            }
            return
        }

        // Ball in the air or on the ground: you are steering whoever is
        // highlighted, and which buttons make sense depends on his side.
        if let user = sim.players.first(where: { $0.isUserControlled }) {
            controlPad.setMode(sim.isAttacking(user) ? .carrying : .defending)
        } else {
            controlPad.setMode(.defending)
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? Self.fixedStep : min(0.1, currentTime - lastUpdate)
        lastUpdate = currentTime

        switch flow {
        case .paused, .finished:
            return

        case .waiting(let remaining, let next):
            let left = remaining - dt
            if left <= 0 {
                enterPhase(next)
            } else {
                flow = .waiting(remaining: left, next: next)
            }
            return

        case .cpuTry(let remaining, let twoPoint):
            let left = remaining - dt
            if left <= 0 {
                chooseTry(twoPoint: twoPoint)
            } else {
                flow = .cpuTry(remaining: left, twoPoint: twoPoint)
            }
            return

        case .choosingOffense, .choosingDefense, .tryChoice:
            return

        case .kicking:
            kickMeter.update(dt)
            if controlPad.consumeKickTap() {
                SFX.shared.play(.uiSelect)
                Haptics.tap()
                if kickMeter.tap() {
                    beginSnapSetup(kickPower: kickMeter.power,
                                   kickAccuracy: kickMeter.accuracy)
                }
            }
            return

        case .deadBall(let remaining):
            let left = remaining - dt
            if left <= 0 {
                advanceAfterPlay()
            } else {
                flow = .deadBall(remaining: left)
                syncNodes(dt: dt)
            }
            return

        case .presnap, .live:
            break
        }

        guard let sim = simulation else { return }

        let input = controlPad.consumeInput()

        // Fixed timestep. The simulation is deterministic only if it is always
        // stepped by the same amount, so the display's variable delta is
        // accumulated rather than passed straight through. Input edges are fed
        // to the first substep only — feeding a press to four substeps would
        // fire a juke four times.
        accumulator += dt
        var steps = 0
        while accumulator >= Self.fixedStep && steps < 6 {
            sim.step(dt: Self.fixedStep, input: steps == 0 ? input : holdOnly(input))
            accumulator -= Self.fixedStep
            steps += 1
            if sim.isFinished { break }
        }
        if steps >= 6 { accumulator = 0 }

        if flow == .presnap && sim.snapped {
            SFX.shared.play(.snap)
            enterLive()
        }
        if flow == .live { updateControlMode() }

        syncNodes(dt: dt)
        updateLiveClock(dt: dt, sim: sim)

        if let result = sim.result, flow == .live || flow == .presnap {
            concludePlay(result)
        }
    }

    /// The held parts of an input, with every press edge stripped.
    private func holdOnly(_ input: PlayInput) -> PlayInput {
        var held = PlayInput()
        held.stick = input.stick
        held.sprint = input.sprint
        return held
    }

    /// The game clock ticks while the ball is live.
    private func updateLiveClock(dt: Double, sim: PlaySimulation) {
        guard flow == .live, sim.snapped, !sim.isFinished else { return }
        guard state.clock.remaining > 0 else { return }
        state.clock.remaining = max(0, state.clock.remaining - dt * Tuning.clockSpeed)
        hud.update(state)
    }

    private func concludePlay(_ result: PlayResult) {
        controlPad.releaseAll()
        controlPad.setMode(.hidden)
        announceResult(result)
        flow = .deadBall(remaining: Tuning.deadBallSeconds)
    }

    private func announceResult(_ result: PlayResult) {
        var color = Palette.accent
        switch result.ending {
        case .touchdown:
            color = Palette.good
        case .interception, .fumble:
            color = Palette.bad
            SFX.shared.play(.turnover)
            Haptics.failure()
        case .incomplete:
            SFX.shared.play(.incomplete)
        case .kick(let good, _, _):
            color = good ? Palette.good : Palette.bad
            if good { Haptics.success() } else { Haptics.failure() }
        case .sack:
            color = Palette.bad
            SFX.shared.play(.bigHit)
            Haptics.bigHit()
        case .tackled:
            SFX.shared.play(.tackle)
            Haptics.hit()
        default:
            break
        }
        SFX.shared.play(.whistle)
        hud.showBanner(result.headline, color: color,
                       duration: max(0.6, Tuning.deadBallSeconds - 0.4))
    }

    /// Folds the finished play into the rules and moves on.
    private func advanceAfterPlay() {
        guard let sim = simulation, let result = sim.result else {
            enterPhase(.playCall)
            return
        }

        let downBefore = state.down
        let possessionBefore = state.possession
        // Undo the cosmetic live tick before the rules burn the real elapsed time.
        state.clock.remaining = clockAtSnap
        let next = Rules.apply(result, to: &state)
        hud.update(state)

        // A first down earns its own little fanfare.
        if state.possession == possessionBefore, state.down == 1, downBefore != 1,
           case .tackled = result.ending {
            SFX.shared.play(.firstDown)
            hud.showBanner("FIRST DOWN", color: Palette.markerFirstDown, duration: 1.0)
        }

        simulation = nil
        enterPhase(next)
    }

    private func finishGame() {
        flow = .finished
        controlPad.setMode(.hidden)
        playCall.hide()
        kickMeter.dismiss()
        clearField()
        SFX.shared.play(.horn)
        hud.showBanner("FINAL", duration: 2.5)

        let outcome = MatchOutcome(home: state.home,
                                   away: state.away,
                                   homeScore: state.scoreHome,
                                   awayScore: state.scoreAway,
                                   homeStats: state.stats[TeamSide.home.rawValue],
                                   awayStats: state.stats[TeamSide.away.rawValue],
                                   userSide: config.userSide,
                                   cupContext: config.cupContext)
        run(.sequence([.wait(forDuration: 1.8),
                       .run { [weak self] in self?.onFinish?(outcome) }]))
    }

    // MARK: - Rendering

    private func clearField() {
        playerNodes.forEach { $0.isHidden = true }
        ballNode.isHidden = true
        hud.updateStamina(0, visible: false)
    }

    private func syncNodes(dt: Double) {
        guard let sim = simulation else { return }
        let snapshot = sim.snapshot

        let optionIDs = snapshot.passOptions
        let labels = ["A", "B", "C", "D"]

        for (i, node) in playerNodes.enumerated() {
            guard i < snapshot.players.count else {
                node.isHidden = true
                continue
            }
            let player = snapshot.players[i]
            node.isHidden = false
            let team = player.side == .home ? state.home : state.away
            let optionIndex = optionIDs.firstIndex(of: player.id)
            node.update(with: player,
                        team: team,
                        isPassOption: optionIndex != nil,
                        optionLabel: optionIndex.map { labels[min($0, labels.count - 1)] },
                        dt: dt)
        }

        // A carried ball is drawn at hip height rather than hidden, so you can
        // always see who has it even mid-stride.
        var ballVisible = true
        var ballHeight = snapshot.ballHeight
        var ballPosition = snapshot.ballPosition
        switch snapshot.ball {
        case .held:
            ballHeight = 0.85
            ballPosition = Vec2(ballPosition.x, ballPosition.y)
        case .dead:
            ballVisible = false
        default:
            break
        }
        ballNode.update(position: ballPosition, height: ballHeight,
                        visible: ballVisible, dt: dt)

        fieldNode.update(lineOfScrimmage: snapshot.lineOfScrimmage,
                         lineToGain: state.lineToGain,
                         hideGainLine: state.lineToGainIsGoalLine)

        if let userID = snapshot.userPlayerID, let idx = sim.index(ofID: userID) {
            hud.updateStamina(sim.players[idx].stamina, visible: flow == .live)
        } else {
            hud.updateStamina(0, visible: false)
        }
        hud.updateMiniField(snapshot, home: state.home, away: state.away,
                            visible: flow == .live || flow == .presnap)

        followCamera(snapshot: snapshot, dt: dt)
    }

    // MARK: - Camera

    private func followCamera(snapshot: PlaySnapshot, dt: Double) {
        // Lead the ball a little in the direction of the play, so a runner is
        // not pinned to the centre of the screen with nothing ahead of him.
        var focus = snapshot.ballPosition
        if let carrier = snapshot.players.first(where: { $0.hasBall }) {
            focus = carrier.pos + carrier.vel * 0.35
        }
        centreCamera(on: focus, immediate: false, dt: dt)
    }

    private func centreCamera(on focus: Vec2, immediate: Bool, dt: Double = 1.0 / 60.0) {
        let target = clampCamera(FieldGeometry.point(focus))
        if immediate {
            cameraNode.position = target
            return
        }
        // Exponential follow, framerate-independent: fast enough to keep up with
        // a breakaway, slow enough that a juke does not whip the whole screen.
        let response = CGFloat(1 - pow(0.0015, dt))
        cameraNode.position = CGPoint(
            x: cameraNode.position.x + (target.x - cameraNode.position.x) * response,
            y: cameraNode.position.y + (target.y - cameraNode.position.y) * response)
    }

    /// Keeps the view inside the field plus a margin for the crowd bands.
    private func clampCamera(_ point: CGPoint) -> CGPoint {
        let field = FieldGeometry.fieldSize
        let halfW = size.width / 2
        let halfH = size.height / 2
        let marginX: CGFloat = 40
        let marginY: CGFloat = 70

        // On a screen wider or taller than the field there is nothing to clamp
        // to, so the camera parks in the middle of that axis instead.
        let minX = min(field.width / 2, halfW - marginX)
        let maxX = max(field.width / 2, field.width - halfW + marginX)
        let minY = min(field.height / 2, halfH - marginY)
        let maxY = max(field.height / 2, field.height - halfH + marginY)

        return CGPoint(x: min(max(point.x, minX), maxX),
                       y: min(max(point.y, minY), maxY))
    }

    // MARK: - Touches

    #if canImport(UIKit)
    private var pauseTouch: ObjectIdentifier?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)

            if pauseButton.contains(touch.location(in: hudLayer)) {
                pauseButton.press()
                pauseTouch = id
                continue
            }
            if flow == .paused { continue }
            if !playCall.isHidden {
                playCall.handleTap(touch.location(in: playCall))
                continue
            }
            controlPad.touchBegan(id, at: touch.location(in: controlPad))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where ObjectIdentifier(touch) != pauseTouch {
            controlPad.touchMoved(ObjectIdentifier(touch), to: touch.location(in: controlPad))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if id == pauseTouch {
                pauseTouch = nil
                _ = pauseButton.consumeEdge()
                pauseButton.release()
                togglePause()
                continue
            }
            controlPad.touchEnded(id)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pauseTouch = nil
        pauseButton.release()
        for touch in touches {
            controlPad.touchEnded(ObjectIdentifier(touch))
        }
    }
    #endif

    // MARK: - Pause

    private func togglePause() {
        if flow == .paused {
            flow = flowBeforePause ?? .deadBall(remaining: 0.1)
            flowBeforePause = nil
            hud.hideBanner()
        } else {
            flowBeforePause = flow
            flow = .paused
            controlPad.releaseAll()
            hud.showBanner("PAUSED", duration: 3600)
        }
    }
}
