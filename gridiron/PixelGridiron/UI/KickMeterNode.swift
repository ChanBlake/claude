//  KickMeterNode.swift
//  The two-stage kick meter: power, then accuracy.
//
//  The kick is decided here and nowhere else. A kick that could still be rescued
//  by the flight simulation would make the meter decorative.

import SpriteKit

final class KickMeterNode: SKNode {

    enum Stage: Equatable {
        case power
        case accuracy
        case done
    }

    private let panel = PanelNode(size: CGSize(width: 300, height: 74))
    private let title = PixelLabel("", pixelSize: 2, color: Palette.textDim)
    private let track = SKSpriteNode()
    private let fill = SKSpriteNode()
    private let sweetSpot = SKSpriteNode()
    private let needle = SKSpriteNode()
    private let hint = PixelLabel("TAP TO SET POWER", pixelSize: 2, color: Palette.text)

    private(set) var stage: Stage = .power
    /// 0…1 once the power stage is locked.
    private(set) var power: Double = 0
    /// −1…1 once the accuracy stage is locked; 0 is dead centre.
    private(set) var accuracy: Double = 0

    private var cursor: Double = 0
    private var direction: Double = 1
    private let trackWidth: CGFloat = 260
    private let trackHeight: CGFloat = 18

    /// Sweep speed in full traversals per second.
    private var sweepRate: Double = 1.15

    override init() {
        super.init()
        zPosition = ZLayer.overlay
        addChild(panel)

        title.alignment = 0
        title.position = CGPoint(x: 0, y: 20)
        panel.addChild(title)

        track.texture = TextureFactory.solid(Palette.ink)
        track.size = CGSize(width: trackWidth, height: trackHeight)
        track.position = CGPoint(x: 0, y: -2)
        panel.addChild(track)

        fill.texture = TextureFactory.solid(Palette.accentHot)
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.size = CGSize(width: 0, height: trackHeight - 4)
        fill.position = CGPoint(x: -trackWidth / 2, y: -2)
        fill.zPosition = 1
        panel.addChild(fill)

        sweetSpot.texture = TextureFactory.solid(Palette.good)
        sweetSpot.size = CGSize(width: trackWidth * CGFloat(Tuning.kickAccuracySweetSpot) * 2,
                                height: trackHeight - 4)
        sweetSpot.position = CGPoint(x: 0, y: -2)
        sweetSpot.zPosition = 1
        sweetSpot.isHidden = true
        panel.addChild(sweetSpot)

        needle.texture = TextureFactory.solid(Palette.text)
        needle.size = CGSize(width: 4, height: trackHeight + 8)
        needle.zPosition = 3
        needle.position = CGPoint(x: -trackWidth / 2, y: -2)
        panel.addChild(needle)

        hint.alignment = 0
        hint.position = CGPoint(x: 0, y: -30)
        panel.addChild(hint)

        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts a fresh attempt. `difficulty` speeds the sweep up a little so a
    /// long kick is not the same button press as a chip shot.
    func begin(title text: String, speed: Double) {
        title.text = text
        stage = .power
        cursor = 0
        direction = 1
        power = 0
        accuracy = 0
        sweepRate = speed
        sweetSpot.isHidden = true
        fill.size = CGSize(width: 0, height: trackHeight - 4)
        fill.texture = TextureFactory.solid(Palette.accentHot)
        hint.text = "TAP TO SET POWER"
        isHidden = false
    }

    func update(_ dt: Double) {
        guard !isHidden, stage != .done else { return }
        cursor += direction * sweepRate * dt
        if cursor >= 1 { cursor = 1; direction = -1 }
        if cursor <= 0 { cursor = 0; direction = 1 }

        needle.position = CGPoint(x: -trackWidth / 2 + trackWidth * CGFloat(cursor), y: -2)
        if stage == .power {
            fill.size = CGSize(width: trackWidth * CGFloat(cursor), height: trackHeight - 4)
        }
    }

    /// Locks the current stage. Returns true once the whole kick is set.
    @discardableResult
    func tap() -> Bool {
        switch stage {
        case .power:
            power = cursor
            stage = .accuracy
            // The accuracy sweep starts from the left again and runs faster.
            cursor = 0
            direction = 1
            sweepRate *= 1.45
            sweetSpot.isHidden = false
            fill.texture = TextureFactory.solid(Palette.panelEdge)
            hint.text = "TAP IN THE GREEN"
            return false
        case .accuracy:
            // The track reads −1 at the left and +1 at the right.
            accuracy = cursor * 2 - 1
            stage = .done
            hint.text = abs(accuracy) <= Tuning.kickAccuracySweetSpot ? "PURE" : "OFF CENTRE"
            needle.texture = TextureFactory.solid(
                abs(accuracy) <= Tuning.kickAccuracySweetSpot ? Palette.good : Palette.bad)
            return true
        case .done:
            return true
        }
    }

    func layout(in size: CGSize) {
        position = CGPoint(x: size.width / 2, y: size.height * 0.30)
    }

    func dismiss() {
        isHidden = true
        stage = .done
    }
}
