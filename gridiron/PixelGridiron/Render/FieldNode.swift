//  FieldNode.swift
//  The field: turf, paint, numbers, end zones, goalposts, and the two lines
//  that actually matter.
//
//  The whole surface is baked into a single procedural texture rather than
//  assembled from a few hundred small nodes. It is one draw call, it is honestly
//  pixel art rather than vector shapes pretending to be, and it means the mow
//  stripes and the hash marks land on exact pixel boundaries.

import SpriteKit

/// Converts field yards into scene points. One art pixel is `artPixel` points,
/// and every renderable position is snapped to that grid.
enum FieldGeometry {
    /// Points per yard on screen. Chosen so a 40-yard-wide field nearly fills a
    /// landscape phone vertically while a play still reads at a glance.
    static let pointsPerYard: CGFloat = 22
    /// Size of one art pixel, in points. Keeps sprites crisp at 2× and 3×.
    static let artPixel: CGFloat = 2

    static var pixelsPerYard: CGFloat { pointsPerYard / artPixel }

    static func point(_ v: Vec2) -> CGPoint {
        CGPoint(x: CGFloat(v.x) * pointsPerYard, y: CGFloat(v.y) * pointsPerYard)
    }

    static func x(_ yards: Double) -> CGFloat { CGFloat(yards) * pointsPerYard }
    static func y(_ yards: Double) -> CGFloat { CGFloat(yards) * pointsPerYard }

    /// Snaps a point to the art-pixel grid so sprites never land on a half pixel.
    static func snap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x / artPixel).rounded() * artPixel,
                y: (p.y / artPixel).rounded() * artPixel)
    }

    static var fieldSize: CGSize {
        CGSize(width: x(Field.totalLength), height: y(Field.width))
    }
}

/// Bakes the playing surface into one texture.
enum FieldTexture {

    /// Texture dimensions in art pixels.
    static var pixelWidth: Int { Int((FieldGeometry.fieldSize.width / FieldGeometry.artPixel).rounded()) }
    static var pixelHeight: Int { Int((FieldGeometry.fieldSize.height / FieldGeometry.artPixel).rounded()) }

    /// A small painter that owns a pixel buffer and knows the field's units.
    private struct Canvas {
        var pixels: [UInt32]
        let width: Int
        let height: Int

        init(width: Int, height: Int, fill: PixelColor) {
            self.width = width
            self.height = height
            self.pixels = [UInt32](repeating: Canvas.word(fill), count: width * height)
        }

        static func word(_ c: PixelColor) -> UInt32 {
            (UInt32(c.r) << 24) | (UInt32(c.g) << 16) | (UInt32(c.b) << 8) | 0xFF
        }

        /// Row 0 of the buffer is the top of the image, which is the *north*
        /// sideline — the y flip lives here and nowhere else.
        mutating func rect(x: Int, y: Int, w: Int, h: Int, _ c: PixelColor) {
            guard w > 0, h > 0 else { return }
            let word = Canvas.word(c)
            for row in max(0, y)..<min(height, y + h) {
                let base = row * width
                for column in max(0, x)..<min(width, x + w) {
                    pixels[base + column] = word
                }
            }
        }

        /// Draws a rasterised string. `scale` repeats each font pixel.
        mutating func text(_ string: String, x: Int, y: Int, scale: Int, _ c: PixelColor,
                           rotated: Bool = false) {
            let bits = PixelFont.rasterize(string)
            for (ry, row) in bits.enumerated() {
                for (cx, on) in row.enumerated() where on {
                    // Rotating 90° clockwise swaps the axes; end-zone lettering
                    // reads up the field the way it does on a real one.
                    let ox = rotated ? ry : cx
                    let oy = rotated ? (row.count - 1 - cx) : ry
                    rect(x: x + ox * scale, y: y + oy * scale, w: scale, h: scale, c)
                }
            }
        }
    }

    /// Yards → texture pixels along the length of the field.
    private static func px(_ yards: Double) -> Int {
        Int((yards * Double(FieldGeometry.pixelsPerYard)).rounded())
    }

    /// Yards across the field → texture row, flipping so y=0 is the bottom.
    private static func py(_ yards: Double) -> Int {
        pixelHeight - 1 - Int((yards * Double(FieldGeometry.pixelsPerYard)).rounded())
    }

    static func build(home: TeamIdentity, away: TeamIdentity, homeDirection: Int) -> SKTexture {
        let w = pixelWidth
        let h = pixelHeight
        var canvas = Canvas(width: w, height: h, fill: Palette.turfLight)

        let ppy = Double(FieldGeometry.pixelsPerYard)     // pixels per yard
        let lineThickness = max(1, Int(ppy * 0.35))
        let goalThickness = max(2, Int(ppy * 0.6))

        // Mow stripes every five yards, between the goal lines.
        var yard = Field.homeGoalLine
        var dark = false
        while yard < Field.awayGoalLine {
            if dark {
                canvas.rect(x: px(yard), y: 0, w: px(5), h: h, Palette.turfDark)
            }
            dark.toggle()
            yard += 5
        }

        // End zones, painted in each team's colour. The team defending the low-x
        // end owns that end zone.
        let lowTeam = homeDirection > 0 ? home : away
        let highTeam = homeDirection > 0 ? away : home
        canvas.rect(x: 0, y: 0, w: px(Field.endZoneDepth), h: h, lowTeam.endZone)
        canvas.rect(x: px(Field.awayGoalLine), y: 0,
                    w: w - px(Field.awayGoalLine), h: h, highTeam.endZone)

        // End-zone lettering, running up the field like the real thing.
        drawEndZoneName(&canvas, team: lowTeam,
                        xStart: px(Field.endZoneDepth / 2), rotated: true)
        drawEndZoneName(&canvas, team: highTeam,
                        xStart: px(Field.awayGoalLine + Field.endZoneDepth / 2), rotated: true)

        // Yard lines every five yards.
        var line = Field.homeGoalLine
        while line <= Field.awayGoalLine + 0.01 {
            let isGoalLine = abs(line - Field.homeGoalLine) < 0.01
                || abs(line - Field.awayGoalLine) < 0.01
            let thickness = isGoalLine ? goalThickness : lineThickness
            canvas.rect(x: px(line) - thickness / 2, y: 0, w: thickness, h: h, Palette.chalk)
            line += 5
        }

        // Hash marks: one per yard, at both hashes and just inside both sidelines.
        let hashLength = max(1, Int(ppy * 0.7))
        let tickLength = max(1, Int(ppy * 0.9))
        var mark = Field.homeGoalLine + 1
        while mark < Field.awayGoalLine {
            if abs(mark.truncatingRemainder(dividingBy: 5)) > 0.01 {
                let mx = px(mark)
                canvas.rect(x: mx, y: py(Field.southHash) - hashLength / 2,
                            w: max(1, lineThickness - 1), h: hashLength, Palette.chalk)
                canvas.rect(x: mx, y: py(Field.northHash) - hashLength / 2,
                            w: max(1, lineThickness - 1), h: hashLength, Palette.chalk)
                canvas.rect(x: mx, y: py(1.2) - tickLength, w: max(1, lineThickness - 1),
                            h: tickLength, Palette.chalkDim)
                canvas.rect(x: mx, y: py(Field.width - 1.2), w: max(1, lineThickness - 1),
                            h: tickLength, Palette.chalkDim)
            }
            mark += 1
        }

        // Sidelines.
        let border = max(2, Int(ppy * 0.5))
        canvas.rect(x: 0, y: 0, w: w, h: border, Palette.chalk)
        canvas.rect(x: 0, y: h - border, w: w, h: border, Palette.chalk)

        // Painted yard numbers near both sidelines.
        drawYardNumbers(&canvas)

        return TextureFactory.texture(width: w, height: h, pixels: canvas.pixels)
    }

    private static func drawEndZoneName(_ canvas: inout Canvas, team: TeamIdentity,
                                        xStart: Int, rotated: Bool) {
        let name = team.nickname
        let scale = max(2, Int(Double(FieldGeometry.pixelsPerYard) * 0.55))
        // Rotated text is as tall as the string is long.
        let textLength = PixelFont.measure(name) * scale
        let textDepth = PixelFont.glyphHeight * scale
        let x = xStart - textDepth / 2
        let y = (pixelHeight - textLength) / 2
        canvas.text(name, x: x, y: y, scale: scale, team.endZoneTextColor, rotated: rotated)
    }

    private static func drawYardNumbers(_ canvas: inout Canvas) {
        let scale = max(2, Int(Double(FieldGeometry.pixelsPerYard) * 0.5))
        var x = Field.homeGoalLine + 10
        while x <= Field.awayGoalLine - 10 + 0.01 {
            guard let number = Field.paintedNumber(atX: x) else { x += 10; continue }
            let label = String(number)
            let widthPx = PixelFont.measure(label) * scale
            let heightPx = PixelFont.glyphHeight * scale
            let cx = px(x) - widthPx / 2

            canvas.text(label, x: cx, y: py(6.5) - heightPx / 2, scale: scale, Palette.chalkDim)
            canvas.text(label, x: cx, y: py(Field.width - 6.5) - heightPx / 2,
                        scale: scale, Palette.chalkDim)
            x += 10
        }
    }
}

/// The field, plus the two lines that move: the line of scrimmage and the line
/// to gain.
final class FieldNode: SKNode {

    private let turf = SKSpriteNode()
    private let scrimmageLine = SKSpriteNode()
    private let gainLine = SKSpriteNode()
    private let crowdTop = SKNode()
    private let crowdBottom = SKNode()
    private var goalposts: [SKNode] = []

    private var builtDirection: Int?
    private var builtHome: String?

    override init() {
        super.init()
        turf.anchorPoint = CGPoint(x: 0, y: 0)
        turf.zPosition = ZLayer.turf
        addChild(turf)

        for (node, color) in [(scrimmageLine, Palette.markerScrimmage),
                              (gainLine, Palette.markerFirstDown)] {
            node.texture = TextureFactory.solid(color)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.size = CGSize(width: FieldGeometry.artPixel * 2,
                               height: FieldGeometry.fieldSize.height)
            node.zPosition = ZLayer.markers
            node.alpha = 0.85
            addChild(node)
        }

        crowdTop.zPosition = ZLayer.crowd
        crowdBottom.zPosition = ZLayer.crowd
        addChild(crowdTop)
        addChild(crowdBottom)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Rebuilds the surface. Cheap enough to call when the teams swap ends.
    func build(home: TeamIdentity, away: TeamIdentity, homeDirection: Int) {
        let key = "\(home.abbreviation)-\(away.abbreviation)"
        guard builtDirection != homeDirection || builtHome != key else { return }
        builtDirection = homeDirection
        builtHome = key

        turf.texture = FieldTexture.build(home: home, away: away, homeDirection: homeDirection)
        turf.size = FieldGeometry.fieldSize
        turf.position = .zero

        buildCrowd()
        buildGoalposts()
    }

    /// Two bands of speckled colour behind the sidelines. Not a crowd so much as
    /// the suggestion of one, which at this zoom is all that is needed.
    private func buildCrowd() {
        crowdTop.removeAllChildren()
        crowdBottom.removeAllChildren()

        let depth: CGFloat = 90
        let size = FieldGeometry.fieldSize
        var rng = RNG(seed: 0xC0FFEE)

        for (container, baseY) in [(crowdBottom, -depth), (crowdTop, size.height)] {
            let backdrop = SKSpriteNode(texture: TextureFactory.solid(Palette.crowdBase))
            backdrop.anchorPoint = CGPoint(x: 0, y: 0)
            backdrop.size = CGSize(width: size.width, height: depth)
            backdrop.position = CGPoint(x: 0, y: baseY)
            container.addChild(backdrop)

            // Speckle. One node per speck would be thousands of draws, so the
            // specks are baked into a tiling strip instead.
            let stripWidth = 128
            let stripHeight = Int(depth / FieldGeometry.artPixel)
            var pixels = [UInt32](repeating: 0, count: stripWidth * stripHeight)
            for i in 0..<(stripWidth * stripHeight) where rng.chance(0.16) {
                let c = rng.pick(Palette.crowdSpecks)
                pixels[i] = (UInt32(c.r) << 24) | (UInt32(c.g) << 16) | (UInt32(c.b) << 8) | 0xFF
            }
            let strip = TextureFactory.texture(width: stripWidth, height: stripHeight, pixels: pixels)
            var offset: CGFloat = 0
            let stripPointWidth = CGFloat(stripWidth) * FieldGeometry.artPixel
            while offset < size.width {
                let node = SKSpriteNode(texture: strip)
                node.anchorPoint = CGPoint(x: 0, y: 0)
                node.size = CGSize(width: stripPointWidth, height: depth)
                node.position = CGPoint(x: offset, y: baseY)
                container.addChild(node)
                offset += stripPointWidth
            }
        }
    }

    private func buildGoalposts() {
        goalposts.forEach { $0.removeFromParent() }
        goalposts.removeAll()

        for backLine in [0.0, Field.totalLength] {
            let post = SKNode()
            post.zPosition = ZLayer.goalposts
            let x = FieldGeometry.x(backLine)
            let centreY = FieldGeometry.y(Field.midfieldY)
            let halfWidth = FieldGeometry.y(Field.uprightWidth / 2)
            let barY = centreY

            func bar(_ w: CGFloat, _ h: CGFloat, _ pos: CGPoint) {
                let n = SKSpriteNode(texture: TextureFactory.solid(Palette.goalpost))
                n.size = CGSize(width: w, height: h)
                n.position = pos
                post.addChild(n)
            }

            // Crossbar across the field, uprights sticking out either side.
            bar(FieldGeometry.artPixel * 2, halfWidth * 2,
                CGPoint(x: x, y: barY))
            let uprightLength = FieldGeometry.x(Field.uprightHeight) * 0.5
            let direction: CGFloat = backLine == 0 ? 1 : -1
            bar(uprightLength, FieldGeometry.artPixel * 2,
                CGPoint(x: x + direction * uprightLength / 2, y: barY - halfWidth))
            bar(uprightLength, FieldGeometry.artPixel * 2,
                CGPoint(x: x + direction * uprightLength / 2, y: barY + halfWidth))

            addChild(post)
            goalposts.append(post)
        }
    }

    /// Moves the two live lines. `lineToGain` is hidden when it is the goal line,
    /// which is already painted.
    func update(lineOfScrimmage: Double, lineToGain: Double, hideGainLine: Bool) {
        scrimmageLine.position = FieldGeometry.snap(
            CGPoint(x: FieldGeometry.x(lineOfScrimmage), y: 0))
        gainLine.position = FieldGeometry.snap(
            CGPoint(x: FieldGeometry.x(lineToGain), y: 0))
        gainLine.isHidden = hideGainLine
    }
}
