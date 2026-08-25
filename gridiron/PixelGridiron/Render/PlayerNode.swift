//  PlayerNode.swift
//  One player on screen, and the ball.

import SpriteKit

/// Draws a single `SimPlayer`. Nodes are pooled by the scene and re-pointed at
/// whichever player occupies that slot, so a play never allocates mid-frame.
final class PlayerNode: SKNode {

    private let shadow = SKSpriteNode(texture: TextureFactory.shadowBlob(diameter: 10))
    private let body = SKSpriteNode()
    private let marker = PixelLabel("", pixelSize: 2, color: Palette.accent)
    private let selectionRing = SKSpriteNode()

    private var team: TeamIdentity?
    private var currentFrame: PlayerFrame = .stand
    /// Distance run since the last frame change, which is what drives the run
    /// cycle — a slow player's legs turn over slower, for free.
    private var strideAccumulator: Double = 0
    private var strideFrame = 0

    override init() {
        super.init()

        shadow.size = CGSize(width: FieldGeometry.artPixel * 10,
                             height: FieldGeometry.artPixel * 5)
        shadow.zPosition = ZLayer.shadows
        shadow.position = CGPoint(x: 0, y: FieldGeometry.artPixel)
        addChild(shadow)

        selectionRing.texture = TextureFactory.solid(Palette.accent)
        selectionRing.size = CGSize(width: FieldGeometry.artPixel * 12,
                                    height: FieldGeometry.artPixel * 2)
        selectionRing.zPosition = ZLayer.shadows + 1
        selectionRing.position = CGPoint(x: 0, y: 0)
        selectionRing.isHidden = true
        addChild(selectionRing)

        body.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        body.zPosition = 1
        addChild(body)

        marker.zPosition = 2
        marker.alignment = 0
        addChild(marker)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Points the node at a team, rebuilding textures only when the team changes.
    func configure(team: TeamIdentity) {
        guard self.team?.abbreviation != team.abbreviation else { return }
        self.team = team
        applyFrame(currentFrame, force: true)
    }

    func update(with player: SimPlayer,
                team: TeamIdentity,
                isPassOption: Bool,
                optionLabel: String?,
                dt: Double) {
        configure(team: team)

        position = FieldGeometry.snap(FieldGeometry.point(player.pos))
        // Players lower on the screen overlap those above them.
        zPosition = ZLayer.players + CGFloat(Field.width - player.pos.y)

        // Facing: sprites are drawn facing right.
        let facingLeft = cos(player.facing) < 0
        body.xScale = facingLeft ? -1 : 1

        applyFrame(frame(for: player, dt: dt), force: false)

        selectionRing.isHidden = !player.isUserControlled
        shadow.isHidden = player.motion == .down

        if let label = optionLabel, isPassOption {
            marker.text = label
            marker.color = Palette.accent
            marker.position = CGPoint(x: 0, y: FieldGeometry.artPixel * 19)
            marker.isHidden = false
        } else {
            // The ring under his feet already says who you are holding.
            marker.isHidden = true
        }
    }

    private func frame(for player: SimPlayer, dt: Double) -> PlayerFrame {
        switch player.motion {
        case .down:
            return .down
        case .diving:
            return .dive
        case .engaged:
            return .block
        case .set:
            return .stand
        case .stumbling:
            return .stand
        case .celebrating:
            return .carry
        case .running:
            break
        }

        let speed = player.vel.length
        guard speed > 0.4 else {
            strideAccumulator = 0
            return player.hasBall ? .carry : .stand
        }

        // One frame change every 1.1 yards of ground covered.
        strideAccumulator += speed * dt
        if strideAccumulator > 1.1 {
            strideAccumulator = 0
            strideFrame = (strideFrame + 1) % 2
        }
        if player.hasBall {
            return strideFrame == 0 ? .carry : .runB
        }
        switch player.offenseAssignment {
        case .passProtect, .runBlock:
            return .block
        default:
            return strideFrame == 0 ? .runA : .runB
        }
    }

    private func applyFrame(_ frame: PlayerFrame, force: Bool) {
        guard let team = team else { return }
        guard force || frame != currentFrame else { return }
        currentFrame = frame
        let texture = PixelArt.texture(frame, team: team)
        body.texture = texture
        body.size = CGSize(width: texture.size().width * FieldGeometry.artPixel,
                           height: texture.size().height * FieldGeometry.artPixel)
    }
}

/// The ball: a sprite plus a shadow that separates from it as the ball rises.
final class BallNode: SKNode {

    private let sprite = SKSpriteNode(texture: PixelArt.ballTexture())
    private let shadow = SKSpriteNode(texture: TextureFactory.shadowBlob(diameter: 8))
    private var spin: CGFloat = 0

    override init() {
        super.init()
        let size = sprite.texture?.size() ?? CGSize(width: 7, height: 5)
        sprite.size = CGSize(width: size.width * FieldGeometry.artPixel,
                             height: size.height * FieldGeometry.artPixel)
        sprite.zPosition = ZLayer.ball
        addChild(sprite)

        shadow.size = CGSize(width: FieldGeometry.artPixel * 6,
                             height: FieldGeometry.artPixel * 3)
        shadow.zPosition = ZLayer.ballShadow
        addChild(shadow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `height` is in yards above the turf.
    func update(position ballPos: Vec2, height: Double, visible: Bool, dt: Double) {
        isHidden = !visible
        guard visible else { return }

        let ground = FieldGeometry.point(ballPos)
        shadow.position = FieldGeometry.snap(ground)
        // The lift is exaggerated relative to the field scale; at true scale a
        // 4-yard-high pass barely leaves the turf on screen.
        let lift = CGFloat(height) * FieldGeometry.pointsPerYard * 0.9
        sprite.position = FieldGeometry.snap(CGPoint(x: ground.x, y: ground.y + lift))

        let shrink = max(0.45, 1 - CGFloat(height) * 0.05)
        shadow.setScale(shrink)
        shadow.alpha = shrink

        if height > 0.05 {
            spin += CGFloat(dt) * 12
            sprite.zRotation = spin
        } else {
            sprite.zRotation = 0
        }
        position = .zero
    }
}
