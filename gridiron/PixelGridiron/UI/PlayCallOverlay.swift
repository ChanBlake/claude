//  PlayCallOverlay.swift
//  The play-call screen, and the little route diagram on each card.

import SpriteKit

/// A postage-stamp diagram of a play: dots for the formation, dotted lines for
/// where everyone goes.
final class PlayDiagramNode: SKNode {

    private let size: CGSize
    private var marks: [SKSpriteNode] = []

    init(size: CGSize) {
        self.size = size
        super.init()
        let turf = SKSpriteNode(texture: TextureFactory.solid(Palette.turfShadow))
        turf.size = size
        addChild(turf)

        let scrimmage = SKSpriteNode(texture: TextureFactory.solid(Palette.chalkDim))
        scrimmage.size = CGSize(width: size.width, height: 1)
        scrimmage.position = CGPoint(x: 0, y: -size.height * 0.18)
        addChild(scrimmage)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Diagram space: 34 yards wide, 26 yards deep, with the line of scrimmage
    /// at 18% below centre — matching the chalk line drawn above.
    private func project(downfield: Double, lateral: Double) -> CGPoint {
        CGPoint(x: CGFloat(lateral / 34.0) * size.width,
                y: -size.height * 0.18 + CGFloat(downfield / 26.0) * size.height)
    }

    private func dot(_ point: CGPoint, _ color: PixelColor, _ side: CGFloat) {
        let node = SKSpriteNode(texture: TextureFactory.solid(color))
        node.size = CGSize(width: side, height: side)
        node.position = point
        node.zPosition = 1
        addChild(node)
        marks.append(node)
    }

    /// Dotted line between two points, so the routes read at postage-stamp size.
    private func trail(from a: CGPoint, to b: CGPoint, _ color: PixelColor) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        let steps = max(1, Int(length / 3))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            dot(CGPoint(x: a.x + dx * t, y: a.y + dy * t), color, 1)
        }
    }

    func show(_ play: OffensePlay, accent: PixelColor) {
        marks.forEach { $0.removeFromParent() }
        marks.removeAll()

        for (i, alignment) in play.alignments.enumerated() {
            let start = project(downfield: alignment.downfield, lateral: alignment.lateral)
            guard i < play.assignments.count else { continue }

            var route: [RouteNode] = []
            var color = Palette.chalkDim
            switch play.assignments[i] {
            case .route(let nodes):
                route = nodes; color = accent
            case .delayedRoute(_, let nodes):
                route = nodes; color = accent
            case .carry(let nodes):
                route = nodes; color = Palette.accentHot
            case .dropback(let depth):
                route = [RouteNode(-depth, 0)]; color = Palette.textDim
            case .passProtect, .runBlock:
                color = Palette.chalkDim
            }

            var cursor = start
            for node in route {
                let next = project(downfield: alignment.downfield + node.downfield,
                                   lateral: alignment.lateral + node.lateral)
                trail(from: cursor, to: next, color)
                cursor = next
            }
            dot(start, Palette.text, 3)
        }
    }
}

/// One selectable card.
final class PlayCardNode: SKNode {

    private let panel: PanelNode
    private let title = PixelLabel("", pixelSize: 2, color: Palette.text)
    private let line1 = PixelLabel("", pixelSize: 1, color: Palette.textDim)
    private let line2 = PixelLabel("", pixelSize: 1, color: Palette.textDim)
    private let diagram: PlayDiagramNode

    let cardSize: CGSize
    private(set) var isHighlighted = false

    init(size: CGSize) {
        cardSize = size
        panel = PanelNode(size: size, fill: Palette.panel, edge: Palette.panelEdge)
        diagram = PlayDiagramNode(size: CGSize(width: size.width - 18, height: size.height * 0.46))
        super.init()

        addChild(panel)
        title.alignment = 0
        title.position = CGPoint(x: 0, y: size.height / 2 - 18)
        addChild(title)

        diagram.position = CGPoint(x: 0, y: 4)
        addChild(diagram)

        line1.alignment = 0
        line1.position = CGPoint(x: 0, y: -size.height / 2 + 20)
        line2.alignment = 0
        line2.position = CGPoint(x: 0, y: -size.height / 2 + 10)
        addChild(line1)
        addChild(line2)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(offense play: OffensePlay, accent: PixelColor) {
        title.text = play.name
        let lines = play.blurb.split(separator: "\n", omittingEmptySubsequences: false)
        line1.text = String(lines.first ?? "")
        line2.text = lines.count > 1 ? String(lines[1]) : ""
        diagram.isHidden = false
        diagram.show(play, accent: accent)
    }

    func configure(defense play: DefensePlay, accent: PixelColor) {
        title.text = play.name
        let lines = play.blurb.split(separator: "\n", omittingEmptySubsequences: false)
        line1.text = String(lines.first ?? "")
        line2.text = lines.count > 1 ? String(lines[1]) : ""
        // Defensive cards show the strength bars instead of a route diagram —
        // what matters is what the call gives up, not where the bodies start.
        diagram.isHidden = true
        _ = accent
    }

    func setHighlighted(_ value: Bool) {
        isHighlighted = value
        panel.texture = TextureFactory.solid(value ? Palette.panelLight : Palette.panel)
    }

    func contains(_ point: CGPoint) -> Bool {
        abs(point.x - position.x) <= cardSize.width / 2
            && abs(point.y - position.y) <= cardSize.height / 2
    }
}

/// The full play-call screen.
final class PlayCallOverlay: SKNode {

    private let scrim = SKSpriteNode()
    private let heading = PixelLabel("", pixelSize: 3, color: Palette.accent)
    private let subheading = PixelLabel("", pixelSize: 2, color: Palette.textDim)
    private var cards: [PlayCardNode] = []

    /// Called with the index of the card that was tapped.
    var onSelect: ((Int) -> Void)?

    private var layoutSize: CGSize = .zero

    override init() {
        super.init()
        zPosition = ZLayer.overlay
        scrim.texture = TextureFactory.solid(Palette.ink)
        scrim.anchorPoint = CGPoint(x: 0, y: 0)
        scrim.alpha = 0.82
        addChild(scrim)

        heading.alignment = 0
        subheading.alignment = 0
        addChild(heading)
        addChild(subheading)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func layout(in size: CGSize) {
        layoutSize = size
        scrim.size = size
        heading.position = CGPoint(x: size.width / 2, y: size.height - 44)
        subheading.position = CGPoint(x: size.width / 2, y: size.height - 62)
    }

    private func rebuildCards(count: Int) {
        guard cards.count != count else { return }
        cards.forEach { $0.removeFromParent() }
        cards.removeAll()

        let columns = count <= 4 ? count : (count + 1) / 2
        let rows = count <= 4 ? 1 : 2
        let margin: CGFloat = 24
        let gap: CGFloat = 12
        let available = layoutSize.width - margin * 2
        let cardWidth = (available - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let topOfCards = layoutSize.height - 80
        let bottomOfCards: CGFloat = 24
        let cardHeight = (topOfCards - bottomOfCards - gap * CGFloat(rows - 1)) / CGFloat(rows)

        for i in 0..<count {
            let column = i % columns
            let row = i / columns
            let card = PlayCardNode(size: CGSize(width: cardWidth, height: cardHeight))
            card.position = CGPoint(
                x: margin + cardWidth / 2 + CGFloat(column) * (cardWidth + gap),
                y: topOfCards - cardHeight / 2 - CGFloat(row) * (cardHeight + gap))
            addChild(card)
            cards.append(card)
        }
    }

    func showOffense(_ plays: [OffensePlay], title: String, subtitle: String, accent: PixelColor) {
        rebuildCards(count: plays.count)
        heading.text = title
        subheading.text = subtitle
        for (card, play) in zip(cards, plays) {
            card.configure(offense: play, accent: accent)
            card.setHighlighted(false)
        }
        isHidden = false
    }

    func showDefense(_ plays: [DefensePlay], title: String, subtitle: String, accent: PixelColor) {
        rebuildCards(count: plays.count)
        heading.text = title
        subheading.text = subtitle
        for (card, play) in zip(cards, plays) {
            card.configure(defense: play, accent: accent)
            card.setHighlighted(false)
        }
        isHidden = false
    }

    func hide() {
        isHidden = true
    }

    /// `point` is in this node's coordinate space.
    func handleTap(_ point: CGPoint) {
        guard !isHidden else { return }
        for (i, card) in cards.enumerated() where card.contains(point) {
            card.setHighlighted(true)
            onSelect?(i)
            return
        }
    }
}
