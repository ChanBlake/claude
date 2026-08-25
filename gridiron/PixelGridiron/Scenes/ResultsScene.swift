//  ResultsScene.swift
//  Final score, box score, and what to do next.

import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

final class ResultsScene: SKScene {

    var onRematch: (() -> Void)?
    var onMainMenu: (() -> Void)?
    var onNextCupRound: (() -> Void)?

    private let outcome: MatchOutcome
    private let backdrop = MenuBackdrop()
    private let content = SKNode()
    private var rows: [MenuRow] = []

    init(outcome: MatchOutcome, size: CGSize) {
        self.outcome = outcome
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Palette.ink.skColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var isReady = false

    override func didMove(to view: SKView) {
        isReady = true
        addChild(backdrop)
        addChild(content)
        content.zPosition = 10
        build()
        if Store.settings.musicEnabled { SFX.shared.startMusic() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isReady else { return }
        build()
    }

    private func build() {
        backdrop.build(in: size)
        content.removeAllChildren()
        rows.removeAll()

        let headline: String
        var headlineColor = Palette.accent
        switch outcome.userWon {
        case .some(true):
            headline = "YOU WIN"
            headlineColor = Palette.good
        case .some(false):
            headline = "YOU LOSE"
            headlineColor = Palette.bad
        case .none:
            headline = outcome.userSide == nil ? "FINAL" : "TIE GAME"
        }

        let title = PixelLabel(headline, pixelSize: 6, color: headlineColor)
        title.alignment = 0
        title.position = CGPoint(x: size.width / 2, y: size.height - 52)
        content.addChild(title)

        if let context = outcome.cupContext {
            let sub = PixelLabel(context, pixelSize: 2, color: Palette.textDim)
            sub.alignment = 0
            sub.position = CGPoint(x: size.width / 2, y: size.height - 72)
            content.addChild(sub)
        }

        // Score line.
        let score = PixelLabel(
            "\(outcome.home.abbreviation) \(outcome.homeScore)   -   \(outcome.awayScore) \(outcome.away.abbreviation)",
            pixelSize: 5, color: Palette.text)
        score.alignment = 0
        score.position = CGPoint(x: size.width / 2, y: size.height - 116)
        content.addChild(score)

        buildBoxScore(topY: size.height - 156)
        buildButtons()
    }

    private func buildBoxScore(topY: CGFloat) {
        let lines: [(String, String, String)] = [
            ("FIRST DOWNS", "\(outcome.homeStats.firstDowns)", "\(outcome.awayStats.firstDowns)"),
            ("TOTAL YARDS", yards(outcome.homeStats.totalYards), yards(outcome.awayStats.totalYards)),
            ("RUSHING", yards(outcome.homeStats.rushYards), yards(outcome.awayStats.rushYards)),
            ("PASSING", yards(outcome.homeStats.passYards), yards(outcome.awayStats.passYards)),
            ("COMP / ATT",
             "\(outcome.homeStats.completions)/\(outcome.homeStats.passAttempts)",
             "\(outcome.awayStats.completions)/\(outcome.awayStats.passAttempts)"),
            ("SACKS ALLOWED", "\(outcome.homeStats.sacksAllowed)", "\(outcome.awayStats.sacksAllowed)"),
            ("TURNOVERS",
             "\(outcome.homeStats.interceptionsThrown + outcome.homeStats.fumblesLost)",
             "\(outcome.awayStats.interceptionsThrown + outcome.awayStats.fumblesLost)"),
        ]

        let panelWidth = min(400, size.width - 60)
        let panel = PanelNode(size: CGSize(width: panelWidth,
                                           height: CGFloat(lines.count) * 16 + 24))
        panel.position = CGPoint(x: size.width / 2,
                                 y: topY - (CGFloat(lines.count) * 16 + 24) / 2)
        content.addChild(panel)

        var y = CGFloat(lines.count) * 16 / 2 - 4
        for (label, homeValue, awayValue) in lines {
            let name = PixelLabel(label, pixelSize: 2, color: Palette.textDim)
            name.alignment = 0
            name.position = CGPoint(x: 0, y: y - 7)
            panel.addChild(name)

            let left = PixelLabel(homeValue, pixelSize: 2, color: outcome.home.trim)
            left.alignment = -1
            left.position = CGPoint(x: -panelWidth / 2 + 14, y: y - 7)
            panel.addChild(left)

            let right = PixelLabel(awayValue, pixelSize: 2, color: outcome.away.trim)
            right.alignment = 1
            right.position = CGPoint(x: panelWidth / 2 - 14, y: y - 7)
            panel.addChild(right)

            y -= 16
        }
    }

    private func yards(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func buildButtons() {
        var items: [(String, String)] = []
        if let run = Store.cup, !run.isComplete, outcome.cupContext != nil {
            items.append(("next", "NEXT: \(run.roundName)"))
        }
        items.append(("rematch", "REMATCH"))
        items.append(("menu", "MAIN MENU"))

        let width = min(300, size.width - 100)
        var y: CGFloat = 96
        for (identifier, title) in items {
            let row = MenuRow(identifier: identifier, title: title,
                              size: CGSize(width: width, height: 34))
            row.position = CGPoint(x: size.width / 2, y: y)
            content.addChild(row)
            rows.append(row)
            y -= 42
        }
    }

    #if canImport(UIKit)
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: content)
        guard let row = rows.first(where: { $0.contains(point) }) else { return }
        SFX.shared.play(.uiSelect)
        Haptics.tap()
        switch row.identifier {
        case "next": onNextCupRound?()
        case "rematch": onRematch?()
        default: onMainMenu?()
        }
    }
    #endif
}
