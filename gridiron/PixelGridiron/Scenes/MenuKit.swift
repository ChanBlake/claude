//  MenuKit.swift
//  Shared pieces for the non-gameplay screens: menu rows, team tiles, and the
//  scrolling backdrop they all sit on.

import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

/// One selectable row in a menu.
final class MenuRow: SKNode {

    private let panel: PanelNode
    private let title: PixelLabel
    private let value: PixelLabel
    let identifier: String
    private let rowSize: CGSize

    init(identifier: String, title text: String, value valueText: String = "",
         size: CGSize = CGSize(width: 300, height: 34)) {
        self.identifier = identifier
        self.rowSize = size
        panel = PanelNode(size: size, fill: Palette.panel, edge: Palette.panelEdge)
        title = PixelLabel(text, pixelSize: 3, color: Palette.text)
        value = PixelLabel(valueText, pixelSize: 2, color: Palette.accent)
        super.init()
        addChild(panel)
        title.alignment = -1
        title.position = CGPoint(x: -size.width / 2 + 14, y: -CGFloat(PixelFont.glyphHeight) * 3 / 2)
        addChild(title)
        value.alignment = 1
        value.position = CGPoint(x: size.width / 2 - 14, y: -CGFloat(PixelFont.glyphHeight))
        addChild(value)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var valueText: String {
        get { value.text }
        set { value.text = newValue }
    }

    var titleText: String {
        get { title.text }
        set { title.text = newValue }
    }

    func setHighlighted(_ on: Bool) {
        panel.texture = TextureFactory.solid(on ? Palette.panelLight : Palette.panel)
        title.color = on ? Palette.accent : Palette.text
    }

    func contains(_ point: CGPoint) -> Bool {
        abs(point.x - position.x) <= rowSize.width / 2
            && abs(point.y - position.y) <= rowSize.height / 2
    }
}

/// A team swatch: helmet colours, abbreviation, and the club name.
final class TeamTile: SKNode {

    private let panel: PanelNode
    private let stripe = SKSpriteNode()
    private let abbr: PixelLabel
    private let name: PixelLabel
    private let record: PixelLabel
    private let tileSize: CGSize

    let team: TeamIdentity

    init(team: TeamIdentity, size: CGSize) {
        self.team = team
        self.tileSize = size
        panel = PanelNode(size: size, fill: team.jersey.darkened(0.45), edge: Palette.panelEdge)
        abbr = PixelLabel(team.abbreviation, pixelSize: 4, color: team.trim)
        name = PixelLabel(team.nickname, pixelSize: 1, color: Palette.text)
        record = PixelLabel("", pixelSize: 1, color: Palette.textDim)
        super.init()

        addChild(panel)
        stripe.texture = TextureFactory.solid(team.trim)
        stripe.size = CGSize(width: size.width, height: 4)
        stripe.position = CGPoint(x: 0, y: size.height / 2 - 8)
        addChild(stripe)

        abbr.alignment = 0
        abbr.position = CGPoint(x: 0, y: -2)
        addChild(abbr)

        name.alignment = 0
        name.position = CGPoint(x: 0, y: -size.height / 2 + 16)
        addChild(name)

        record.alignment = 0
        record.position = CGPoint(x: 0, y: -size.height / 2 + 6)
        record.text = strengthBar(team.strength)
        addChild(record)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Team strength as a five-block bar, so picking a team is an informed choice.
    private func strengthBar(_ strength: Double) -> String {
        let filled = clamp(Int(((strength + 8) / 16 * 5).rounded()), 0, 5)
        return String(repeating: "+", count: filled) + String(repeating: "-", count: 5 - filled)
    }

    func setHighlighted(_ on: Bool) {
        panel.texture = TextureFactory.solid(on ? team.jersey : team.jersey.darkened(0.45))
        setScale(on ? 1.06 : 1.0)
    }

    func contains(_ point: CGPoint) -> Bool {
        abs(point.x - position.x) <= tileSize.width / 2
            && abs(point.y - position.y) <= tileSize.height / 2
    }
}

/// The slowly drifting turf backdrop every menu screen sits on.
final class MenuBackdrop: SKNode {

    private var stripes: [SKSpriteNode] = []

    func build(in size: CGSize) {
        removeAllChildren()
        stripes.removeAll()

        let base = SKSpriteNode(texture: TextureFactory.solid(Palette.turfShadow))
        base.anchorPoint = .zero
        base.size = size
        addChild(base)

        // Diagonal chalk stripes, drifting. Cheap motion that reads as a field
        // without competing with the menu on top of it.
        let stripeWidth: CGFloat = 26
        var x: CGFloat = -size.height
        while x < size.width + size.height {
            let stripe = SKSpriteNode(texture: TextureFactory.solid(Palette.turfDark))
            stripe.anchorPoint = CGPoint(x: 0.5, y: 0)
            stripe.size = CGSize(width: stripeWidth, height: size.height * 1.6)
            stripe.position = CGPoint(x: x, y: -size.height * 0.3)
            stripe.zRotation = -0.32
            stripe.alpha = 0.55
            addChild(stripe)
            stripes.append(stripe)
            x += stripeWidth * 2.4
        }

        let drift = SKAction.sequence([
            .moveBy(x: stripeWidth * 2.4, y: 0, duration: 6.0),
            .moveBy(x: -stripeWidth * 2.4, y: 0, duration: 0),
        ])
        for stripe in stripes {
            stripe.run(.repeatForever(drift))
        }
    }
}
