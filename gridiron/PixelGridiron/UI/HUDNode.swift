//  HUDNode.swift
//  Scoreboard, situation line, result banner, stamina, and the mini field.

import SpriteKit

/// A flat pixel panel with an outline. Every box in the interface is one of these.
final class PanelNode: SKSpriteNode {
    private let border = SKSpriteNode()

    init(size: CGSize, fill: PixelColor = Palette.panel, edge: PixelColor = Palette.panelEdge) {
        super.init(texture: TextureFactory.solid(fill), color: .clear, size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        border.texture = TextureFactory.solid(edge)
        border.size = CGSize(width: size.width + 4, height: size.height + 4)
        border.zPosition = -1
        addChild(border)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func resize(_ size: CGSize) {
        self.size = size
        border.size = CGSize(width: size.width + 4, height: size.height + 4)
    }
}

/// The permanent on-screen furniture during a game.
final class HUDNode: SKNode {

    private let scoreboard = PanelNode(size: CGSize(width: 320, height: 34))
    private let homeAbbr = PixelLabel("", pixelSize: 3, color: Palette.text)
    private let homeScore = PixelLabel("0", pixelSize: 4, color: Palette.text)
    private let awayAbbr = PixelLabel("", pixelSize: 3, color: Palette.text)
    private let awayScore = PixelLabel("0", pixelSize: 4, color: Palette.text)
    private let clockLabel = PixelLabel("0:00", pixelSize: 3, color: Palette.accent)
    private let quarterLabel = PixelLabel("1ST", pixelSize: 2, color: Palette.textDim)

    private let situation = PanelNode(size: CGSize(width: 280, height: 22))
    private let situationLabel = PixelLabel("", pixelSize: 2, color: Palette.text)

    private let possessionPip = SKSpriteNode()

    private let banner = PanelNode(size: CGSize(width: 340, height: 46),
                                   fill: Palette.ink, edge: Palette.accent)
    private let bannerLabel = PixelLabel("", pixelSize: 4, color: Palette.accent)

    private let staminaBack = SKSpriteNode()
    private let staminaFill = SKSpriteNode()

    private let miniField = MiniFieldNode()

    private var size: CGSize = .zero

    override init() {
        super.init()
        zPosition = ZLayer.hud

        scoreboard.addChild(homeAbbr)
        scoreboard.addChild(homeScore)
        scoreboard.addChild(awayAbbr)
        scoreboard.addChild(awayScore)
        scoreboard.addChild(clockLabel)
        scoreboard.addChild(quarterLabel)
        addChild(scoreboard)

        situation.addChild(situationLabel)
        addChild(situation)

        possessionPip.texture = TextureFactory.solid(Palette.accent)
        possessionPip.size = CGSize(width: 6, height: 6)
        scoreboard.addChild(possessionPip)

        banner.addChild(bannerLabel)
        banner.alpha = 0
        banner.zPosition = ZLayer.banner
        addChild(banner)

        staminaBack.texture = TextureFactory.solid(Palette.panel)
        staminaBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        staminaFill.texture = TextureFactory.solid(Palette.good)
        staminaFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        staminaFill.zPosition = 1
        addChild(staminaBack)
        addChild(staminaFill)

        addChild(miniField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    func layout(in size: CGSize) {
        self.size = size
        let top = size.height

        scoreboard.resize(CGSize(width: 300, height: 34))
        scoreboard.position = CGPoint(x: size.width / 2, y: top - 30)

        homeAbbr.alignment = -1
        homeAbbr.position = CGPoint(x: -138, y: 2)
        homeScore.alignment = -1
        homeScore.position = CGPoint(x: -138, y: -14)

        awayAbbr.alignment = 1
        awayAbbr.position = CGPoint(x: 138, y: 2)
        awayScore.alignment = 1
        awayScore.position = CGPoint(x: 138, y: -14)

        clockLabel.alignment = 0
        clockLabel.position = CGPoint(x: 0, y: -2)
        quarterLabel.alignment = 0
        quarterLabel.position = CGPoint(x: 0, y: -16)

        situation.resize(CGSize(width: 300, height: 20))
        situation.position = CGPoint(x: size.width / 2, y: top - 60)
        situationLabel.alignment = 0
        situationLabel.position = CGPoint(x: 0, y: -7)

        banner.resize(CGSize(width: min(420, size.width - 60), height: 48))
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.56)
        bannerLabel.alignment = 0
        bannerLabel.position = CGPoint(x: 0, y: -14)

        staminaBack.size = CGSize(width: 110, height: 8)
        staminaBack.position = CGPoint(x: 24, y: 22)
        staminaFill.size = CGSize(width: 110, height: 8)
        staminaFill.position = staminaBack.position

        miniField.layout()
        miniField.position = CGPoint(x: size.width / 2, y: top - 84)
    }

    // MARK: - Updating

    func update(_ state: MatchState) {
        homeAbbr.text = state.home.abbreviation
        awayAbbr.text = state.away.abbreviation
        homeScore.text = String(state.scoreHome)
        awayScore.text = String(state.scoreAway)
        homeAbbr.color = state.home.trim
        awayAbbr.color = state.away.trim
        clockLabel.text = state.clock.display
        quarterLabel.text = state.clock.quarterLabel

        // A pip on the side of whoever has the ball.
        possessionPip.isHidden = state.phase == .final
        possessionPip.position = CGPoint(x: state.possession == .home ? -152 : 152, y: -6)

        let timeouts = String(repeating: "·", count: max(0, state.timeouts[state.possession.rawValue]))
        switch state.phase {
        case .final:
            situationLabel.text = "FINAL"
        case .kickoff:
            situationLabel.text = "KICKOFF"
        case .pointAfter:
            situationLabel.text = "POINT AFTER TRY"
        case .halftime:
            situationLabel.text = "HALFTIME"
        case .quarterBreak:
            situationLabel.text = "END OF \(state.clock.quarterLabel) QUARTER"
        default:
            situationLabel.text = "\(state.downAndDistanceText)  ·  \(state.ballOnText)  \(timeouts)"
        }
    }

    func updateStamina(_ value: Double, visible: Bool) {
        staminaBack.isHidden = !visible
        staminaFill.isHidden = !visible
        guard visible else { return }
        let clamped = clamp(value, 0, 1)
        staminaFill.size = CGSize(width: 110 * CGFloat(clamped), height: 8)
        staminaFill.texture = TextureFactory.solid(clamped < 0.25 ? Palette.bad : Palette.good)
    }

    func updateMiniField(_ snapshot: PlaySnapshot,
                         home: TeamIdentity,
                         away: TeamIdentity,
                         visible: Bool) {
        miniField.isHidden = !visible
        guard visible else { return }
        miniField.update(snapshot, home: home, away: away)
    }

    // MARK: - Banner

    func showBanner(_ text: String, color: PixelColor = Palette.accent, duration: Double = 1.6) {
        bannerLabel.text = text
        bannerLabel.color = color
        banner.removeAllActions()
        banner.alpha = 0
        banner.setScale(0.9)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.0, duration: 0.12)]),
            .wait(forDuration: duration),
            .fadeOut(withDuration: 0.25),
        ]))
    }

    func hideBanner() {
        banner.removeAllActions()
        banner.alpha = 0
    }
}

/// A postage-stamp field showing all fourteen players and the ball, so the
/// half of the field the camera cannot show is still legible.
final class MiniFieldNode: SKNode {

    private let backdrop = SKSpriteNode()
    private var pips: [SKSpriteNode] = []
    private let ballPip = SKSpriteNode()
    private let scrimmagePip = SKSpriteNode()
    private let gainPip = SKSpriteNode()

    private let width: CGFloat = 240
    private let height: CGFloat = 26

    override init() {
        super.init()
        backdrop.texture = TextureFactory.solid(Palette.turfDark)
        backdrop.size = CGSize(width: width, height: height)
        backdrop.alpha = 0.85
        addChild(backdrop)

        for (pip, color) in [(scrimmagePip, Palette.markerScrimmage),
                             (gainPip, Palette.markerFirstDown)] {
            pip.texture = TextureFactory.solid(color)
            pip.size = CGSize(width: 2, height: height)
            pip.zPosition = 1
            addChild(pip)
        }

        ballPip.texture = TextureFactory.solid(Palette.ballLace)
        ballPip.size = CGSize(width: 4, height: 4)
        ballPip.zPosition = 3
        addChild(ballPip)

        for _ in 0..<14 {
            let pip = SKSpriteNode(texture: TextureFactory.solid(Palette.text))
            pip.size = CGSize(width: 4, height: 4)
            pip.zPosition = 2
            addChild(pip)
            pips.append(pip)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func layout() {
        backdrop.size = CGSize(width: width, height: height)
    }

    private func project(_ p: Vec2) -> CGPoint {
        CGPoint(x: (CGFloat(p.x / Field.totalLength) - 0.5) * width,
                y: (CGFloat(p.y / Field.width) - 0.5) * height)
    }

    func update(_ snapshot: PlaySnapshot, home: TeamIdentity, away: TeamIdentity) {
        scrimmagePip.position = CGPoint(
            x: (CGFloat(snapshot.lineOfScrimmage / Field.totalLength) - 0.5) * width, y: 0)
        gainPip.position = CGPoint(
            x: (CGFloat(snapshot.lineToGain / Field.totalLength) - 0.5) * width, y: 0)
        ballPip.position = project(snapshot.ballPosition)

        for (i, pip) in pips.enumerated() {
            guard i < snapshot.players.count else { pip.isHidden = true; continue }
            let player = snapshot.players[i]
            pip.isHidden = false
            pip.position = project(player.pos)
            let team = player.side == .home ? home : away
            pip.texture = TextureFactory.solid(player.isUserControlled ? Palette.accent : team.jersey)
            pip.size = player.hasBall ? CGSize(width: 6, height: 6) : CGSize(width: 4, height: 4)
        }
    }
}
