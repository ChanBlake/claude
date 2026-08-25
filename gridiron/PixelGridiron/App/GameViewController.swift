//  GameViewController.swift
//  Hosts the SpriteKit view and owns which scene is on screen.

import UIKit
import SpriteKit

final class GameViewController: UIViewController {

    private var skView: SKView { view as! SKView }
    private var lastConfig: MatchConfig?

    override func loadView() {
        let view = SKView(frame: UIScreen.main.bounds)
        view.ignoresSiblingOrder = true
        view.showsFPS = false
        view.showsNodeCount = false
        // Nearest-neighbour everywhere; the whole game is pixel art and a
        // smoothed sprite is immediately obvious.
        view.preferredFramesPerSecond = 60
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.ink.skColor
        showTitle()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        TextureFactory.purge()
    }

    // MARK: - Scene switching

    private func present(_ scene: SKScene, transition: SKTransition? = nil) {
        scene.size = skView.bounds.size
        scene.scaleMode = .resizeFill
        if let transition = transition {
            skView.presentScene(scene, transition: transition)
        } else {
            skView.presentScene(scene)
        }
    }

    private func showTitle() {
        let scene = TitleScene(size: skView.bounds.size)
        scene.onStartMatch = { [weak self] config in self?.startMatch(config) }
        present(scene, transition: .fade(withDuration: 0.35))
    }

    private func startMatch(_ config: MatchConfig) {
        lastConfig = config
        let scene = GameScene(config: config, size: skView.bounds.size)
        scene.onFinish = { [weak self] outcome in self?.showResults(outcome) }
        present(scene, transition: .doorway(withDuration: 0.5))
    }

    private func showResults(_ outcome: MatchOutcome) {
        recordOutcome(outcome)

        let scene = ResultsScene(outcome: outcome, size: skView.bounds.size)
        scene.onMainMenu = { [weak self] in self?.showTitle() }
        scene.onRematch = { [weak self] in
            guard var config = self?.lastConfig else { self?.showTitle(); return }
            config.seed = UInt64.random(in: 0..<UInt64.max)
            config.cupContext = nil
            self?.startMatch(config)
        }
        scene.onNextCupRound = { [weak self] in self?.startNextCupRound() }
        present(scene, transition: .fade(withDuration: 0.4))
    }

    /// Books the result into career records, and advances a cup run if this was
    /// one of its rounds.
    private func recordOutcome(_ outcome: MatchOutcome) {
        guard let side = outcome.userSide else { return }
        let mine = side == .home ? outcome.homeScore : outcome.awayScore
        let theirs = side == .home ? outcome.awayScore : outcome.homeScore
        Store.recordResult(playerScore: mine, opponentScore: theirs)

        guard outcome.cupContext != nil, var run = Store.cup, !run.isComplete else { return }
        if mine > theirs {
            run.advance(playerScore: mine, opponentScore: theirs)
            if run.isComplete {
                var records = Store.records
                records.cupWins += 1
                Store.records = records
                Store.cup = nil
            } else {
                Store.cup = run
            }
        } else {
            // A cup run ends the first time you lose.
            Store.cup = nil
        }
    }

    private func startNextCupRound() {
        guard let run = Store.cup, let opponentAbbr = run.currentOpponent,
              let player = League.team(named: run.playerTeam),
              let opponent = League.team(named: opponentAbbr) else {
            showTitle()
            return
        }
        var config = MatchConfig.exhibition(playerTeam: player,
                                            opponent: opponent,
                                            settings: Store.settings)
        config.cupContext = run.roundName
        startMatch(config)
    }
}
