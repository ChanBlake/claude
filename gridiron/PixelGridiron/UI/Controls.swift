//  Controls.swift
//  The touch controls: a floating joystick on the left, a contextual button
//  cluster on the right.
//
//  The joystick has no fixed home. Put a thumb down anywhere in the left third
//  and that is where the stick is for as long as the thumb stays down — on a
//  phone, a stick you have to find is a stick you fight.

import SpriteKit

/// A chunky pixel button with a held state and a one-frame press edge.
final class PixelButton: SKNode {

    private let plate = SKSpriteNode()
    private let bevel = SKSpriteNode()
    private let label: PixelLabel
    private let subLabel: PixelLabel

    let identifier: String
    private(set) var isHeld = false
    /// Set on the frame the button goes down; cleared by `consumeEdges()`.
    private(set) var wasPressed = false

    var radius: CGFloat
    var tint: PixelColor {
        didSet { redraw() }
    }

    init(identifier: String,
         title: String,
         subtitle: String = "",
         radius: CGFloat = 40,
         tint: PixelColor = Palette.panelLight) {
        self.identifier = identifier
        self.radius = radius
        self.tint = tint
        self.label = PixelLabel(title, pixelSize: 3, color: Palette.text)
        self.subLabel = PixelLabel(subtitle, pixelSize: 2, color: Palette.textDim)
        super.init()

        bevel.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        plate.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(bevel)
        addChild(plate)

        label.position = CGPoint(x: 0, y: -CGFloat(PixelFont.glyphHeight) * 3 / 2)
        addChild(label)
        subLabel.position = CGPoint(x: 0, y: -radius * 0.62)
        addChild(subLabel)

        redraw()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var title: String {
        get { label.text }
        set { label.text = newValue }
    }

    var subtitle: String {
        get { subLabel.text }
        set { subLabel.text = newValue }
    }

    private func redraw() {
        let size = CGSize(width: radius * 2, height: radius * 2)
        plate.texture = TextureFactory.solid(isHeld ? tint.lightened(0.25) : tint)
        plate.size = size
        bevel.texture = TextureFactory.solid(Palette.ink)
        bevel.size = CGSize(width: size.width + 6, height: size.height + 6)
        plate.position = CGPoint(x: 0, y: isHeld ? -2 : 0)
        label.position = CGPoint(x: 0,
                                 y: -CGFloat(PixelFont.glyphHeight) * 3 / 2 + (isHeld ? -2 : 0))
        alpha = isEnabled ? 1.0 : 0.35
    }

    var isEnabled = true {
        didSet { redraw() }
    }

    /// `point` is in the control pad's coordinate space, whose origin is the
    /// bottom-left of the screen.
    func contains(_ point: CGPoint) -> Bool {
        guard isEnabled else { return false }
        // A generous hit area — fingers are not precise, and a missed button in
        // traffic costs more than an overlap ever does.
        return abs(point.x - position.x) <= radius * 1.18
            && abs(point.y - position.y) <= radius * 1.18
    }

    func press() {
        guard !isHeld else { return }
        isHeld = true
        wasPressed = true
        redraw()
    }

    func release() {
        guard isHeld else { return }
        isHeld = false
        redraw()
    }

    func consumeEdge() -> Bool {
        defer { wasPressed = false }
        return wasPressed
    }
}

/// The floating left-thumb stick.
final class VirtualJoystick: SKNode {

    private let base = SKSpriteNode()
    private let knob = SKSpriteNode()
    private(set) var vector: Vec2 = .zero
    private var origin: CGPoint = .zero
    private(set) var isActive = false

    /// Full deflection distance, in points.
    var travel: CGFloat = 46

    override init() {
        super.init()
        base.texture = TextureFactory.solid(Palette.panel)
        base.size = CGSize(width: travel * 2, height: travel * 2)
        base.alpha = 0.35
        addChild(base)

        knob.texture = TextureFactory.solid(Palette.accent)
        knob.size = CGSize(width: 34, height: 34)
        knob.alpha = 0.85
        addChild(knob)

        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func begin(at point: CGPoint) {
        origin = point
        isActive = true
        isHidden = false
        base.position = point
        knob.position = point
        vector = .zero
    }

    func move(to point: CGPoint) {
        guard isActive else { return }
        var delta = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let length = (delta.x * delta.x + delta.y * delta.y).squareRoot()
        if length > travel {
            delta.x *= travel / length
            delta.y *= travel / length
        }
        knob.position = CGPoint(x: origin.x + delta.x, y: origin.y + delta.y)
        // Below the dead zone the stick reads as centred, so a resting thumb
        // does not creep.
        let deadZone: CGFloat = 6
        if length < deadZone {
            vector = .zero
        } else {
            vector = Vec2(Double(delta.x / travel), Double(delta.y / travel)).limited(to: 1)
        }
    }

    func end() {
        isActive = false
        isHidden = true
        vector = .zero
    }
}

/// The contextual right-hand button cluster plus the joystick.
final class ControlPad: SKNode {

    enum Mode: Equatable {
        case hidden
        /// Waiting for the snap.
        case presnap
        /// Quarterback with the ball on a pass play: receiver buttons.
        case passing(labels: [String])
        /// Anyone carrying the ball.
        case carrying
        /// Playing defence.
        case defending
        /// A kick meter is up; the only control is "stop it".
        case kicking
    }

    let joystick = VirtualJoystick()
    private var buttons: [PixelButton] = []
    private var mode: Mode = .hidden
    private var activeTouches: [ObjectIdentifier: String] = [:]
    private var joystickTouch: ObjectIdentifier?

    private var layoutSize: CGSize = .zero

    override init() {
        super.init()
        zPosition = ZLayer.controls
        addChild(joystick)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    func layout(in size: CGSize) {
        layoutSize = size
        rebuild()
    }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        rebuild()
    }

    private func rebuild() {
        buttons.forEach { $0.removeFromParent() }
        buttons.removeAll()
        guard layoutSize.width > 0 else { return }

        let margin: CGFloat = 26
        let right = layoutSize.width - margin
        let bottom = margin

        func add(_ button: PixelButton, _ position: CGPoint) {
            button.position = position
            addChild(button)
            buttons.append(button)
        }

        switch mode {
        case .hidden:
            joystick.end()

        case .presnap:
            let snap = PixelButton(identifier: "snap", title: "SNAP", subtitle: "HIKE",
                                   radius: 52, tint: Palette.accentHot)
            add(snap, CGPoint(x: right - 52, y: bottom + 62))

        case .passing(let labels):
            // Receiver buttons in a diamond, so the thumb can reach all four
            // without looking. Order matches the badges over the receivers.
            let centre = CGPoint(x: right - 86, y: bottom + 96)
            let spread: CGFloat = 56
            let offsets = [CGPoint(x: 0, y: -spread),
                           CGPoint(x: -spread, y: 0),
                           CGPoint(x: spread, y: 0),
                           CGPoint(x: 0, y: spread)]
            for (i, label) in labels.prefix(4).enumerated() {
                let button = PixelButton(identifier: "pass\(i)", title: label,
                                         radius: 30, tint: Palette.panelLight)
                add(button, CGPoint(x: centre.x + offsets[i].x, y: centre.y + offsets[i].y))
            }
            let scramble = PixelButton(identifier: "sprint", title: "RUN", subtitle: "SPRINT",
                                       radius: 34, tint: Palette.panel)
            add(scramble, CGPoint(x: right - 34, y: bottom + 30))

        case .carrying:
            let sprint = PixelButton(identifier: "sprint", title: "GO", subtitle: "SPRINT",
                                     radius: 46, tint: Palette.accentHot)
            add(sprint, CGPoint(x: right - 46, y: bottom + 52))
            let juke = PixelButton(identifier: "action", title: "JUKE", radius: 34,
                                   tint: Palette.panelLight)
            add(juke, CGPoint(x: right - 130, y: bottom + 40))
            let dive = PixelButton(identifier: "dive", title: "DIVE", radius: 34,
                                   tint: Palette.panelLight)
            add(dive, CGPoint(x: right - 108, y: bottom + 118))

        case .defending:
            let tackle = PixelButton(identifier: "dive", title: "HIT", subtitle: "TACKLE",
                                     radius: 46, tint: Palette.accentHot)
            add(tackle, CGPoint(x: right - 46, y: bottom + 52))
            let swap = PixelButton(identifier: "action", title: "SWAP", subtitle: "PLAYER",
                                   radius: 34, tint: Palette.panelLight)
            add(swap, CGPoint(x: right - 130, y: bottom + 40))
            let sprint = PixelButton(identifier: "sprint", title: "GO", radius: 34,
                                     tint: Palette.panel)
            add(sprint, CGPoint(x: right - 108, y: bottom + 118))

        case .kicking:
            let stop = PixelButton(identifier: "kick", title: "KICK", subtitle: "TAP TO STOP",
                                   radius: 58, tint: Palette.accent)
            add(stop, CGPoint(x: layoutSize.width / 2, y: bottom + 66))
        }
    }

    // MARK: - Touches

    /// The left third of the screen belongs to the stick.
    private var joystickZoneWidth: CGFloat { layoutSize.width * 0.42 }

    func touchBegan(_ id: ObjectIdentifier, at point: CGPoint) {
        if let button = buttons.first(where: { $0.contains(point) }) {
            button.press()
            activeTouches[id] = button.identifier
            return
        }
        if point.x < joystickZoneWidth, joystickTouch == nil {
            joystickTouch = id
            joystick.begin(at: point)
        }
    }

    func touchMoved(_ id: ObjectIdentifier, to point: CGPoint) {
        if id == joystickTouch {
            joystick.move(to: point)
            return
        }
        // Sliding off a button releases it, the way a hardware button would.
        if let identifier = activeTouches[id],
           let button = buttons.first(where: { $0.identifier == identifier }),
           !button.contains(point) {
            button.release()
            activeTouches[id] = nil
        }
    }

    func touchEnded(_ id: ObjectIdentifier) {
        if id == joystickTouch {
            joystickTouch = nil
            joystick.end()
        }
        if let identifier = activeTouches[id],
           let button = buttons.first(where: { $0.identifier == identifier }) {
            button.release()
        }
        activeTouches[id] = nil
    }

    func releaseAll() {
        buttons.forEach { $0.release() }
        activeTouches.removeAll()
        joystickTouch = nil
        joystick.end()
    }

    // MARK: - Reading input

    private func button(_ identifier: String) -> PixelButton? {
        buttons.first { $0.identifier == identifier }
    }

    /// Builds this frame's input and clears every press edge.
    ///
    /// The camera never rotates, so screen space and field space share an
    /// orientation and the stick needs no transform: push right, run toward
    /// higher x. Which end zone that is depends on the drive, and the first-down
    /// marker and mini field are what say so.
    func consumeInput() -> PlayInput {
        var input = PlayInput()
        input.stick = joystick.vector
        input.sprint = button("sprint")?.isHeld ?? false
        input.actionPressed = button("action")?.consumeEdge() ?? false
        input.divePressed = button("dive")?.consumeEdge() ?? false
        input.snapPressed = button("snap")?.consumeEdge() ?? false
        for i in 0..<4 where button("pass\(i)")?.consumeEdge() == true {
            input.passTargetSlot = i
        }
        return input
    }

    /// True on the frame the kick meter button is tapped.
    func consumeKickTap() -> Bool {
        button("kick")?.consumeEdge() ?? false
    }
}
