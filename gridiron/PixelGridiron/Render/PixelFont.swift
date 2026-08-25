//  PixelFont.swift
//  A 5×7 bitmap font, drawn the same way the sprites are.
//
//  A real typeface at this zoom would fight the art. Everything the game prints
//  — scoreboard, play cards, menus — goes through here, so the whole interface
//  sits on the same pixel grid as the players.

import SpriteKit

enum PixelFont {

    static let glyphWidth = 5
    static let glyphHeight = 7
    /// Blank columns between characters.
    static let tracking = 1

    /// `#` is an on pixel, `.` is off. Every glyph is exactly 7 rows of 5.
    private static let glyphs: [Character: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        ":": [".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        ".": [".....", ".....", ".....", ".....", ".....", "..#..", "....."],
        ",": [".....", ".....", ".....", ".....", "..#..", "..#..", ".#..."],
        "'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
        "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
        "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
        "&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
        "/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
        "(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
        ")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
        "%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
        "·": [".....", ".....", "..#..", "..#..", ".....", ".....", "....."],
        "×": [".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "....."],
        "→": [".....", "..#..", "...#.", "#####", "...#.", "..#..", "....."],
    ]

    private static let fallback = ["#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#####"]

    static func glyph(_ c: Character) -> [String] {
        glyphs[c] ?? glyphs[Character(String(c).uppercased())] ?? fallback
    }

    /// Width in font pixels of a rendered string.
    static func measure(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.count * (glyphWidth + tracking) - tracking
    }

    /// Renders `text` into a pixel grid: `nil` for transparent, `true` for ink.
    static func rasterize(_ text: String) -> [[Bool]] {
        let width = max(1, measure(text))
        var rows = Array(repeating: Array(repeating: false, count: width), count: glyphHeight)
        var x = 0
        for c in text {
            let g = glyph(c)
            for (ry, row) in g.enumerated() {
                for (cx, ch) in row.enumerated() where ch == "#" {
                    let px = x + cx
                    if px < width { rows[ry][px] = true }
                }
            }
            x += glyphWidth + tracking
        }
        return rows
    }
}

/// A node that draws a string of pixel text. Rebuilding is cheap enough to do
/// every frame for the clock, but `text` short-circuits when nothing changed.
final class PixelLabel: SKNode {
    private let sprite = SKSpriteNode()
    private var cachedText: String = ""
    private var cachedColor: PixelColor = Palette.text
    private var cachedShadow: PixelColor?

    /// Size of one font pixel, in points.
    var pixelSize: CGFloat {
        didSet { if pixelSize != oldValue { rebuild(force: true) } }
    }

    var color: PixelColor {
        didSet { if color != oldValue { rebuild(force: true) } }
    }

    /// Drop shadow offset one pixel down and right. `nil` disables it.
    var shadow: PixelColor? {
        didSet { rebuild(force: true) }
    }

    /// -1 left, 0 centre, 1 right.
    var alignment: CGFloat = 0 {
        didSet { layout() }
    }

    var text: String = "" {
        didSet { rebuild(force: false) }
    }

    init(_ text: String = "",
         pixelSize: CGFloat = 2,
         color: PixelColor = Palette.text,
         shadow: PixelColor? = Palette.ink) {
        self.pixelSize = pixelSize
        self.color = color
        self.shadow = shadow
        super.init()
        sprite.anchorPoint = CGPoint(x: 0, y: 0)
        sprite.texture?.filteringMode = .nearest
        addChild(sprite)
        self.text = text
        rebuild(force: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var pixelWidth: CGFloat {
        CGFloat(PixelFont.measure(text)) * pixelSize
    }

    var pixelHeight: CGFloat {
        CGFloat(PixelFont.glyphHeight) * pixelSize
    }

    private func rebuild(force: Bool) {
        guard force || text != cachedText || color != cachedColor || shadow != cachedShadow else { return }
        cachedText = text
        cachedColor = color
        cachedShadow = shadow

        guard !text.isEmpty else {
            sprite.texture = nil
            sprite.size = .zero
            return
        }

        let texture = TextureFactory.textTexture(text, color: color, shadow: shadow)
        sprite.texture = texture
        sprite.size = CGSize(width: texture.size().width * pixelSize,
                             height: texture.size().height * pixelSize)
        layout()
    }

    private func layout() {
        let w = sprite.size.width
        switch alignment {
        case ..<0: sprite.position = CGPoint(x: 0, y: 0)
        case 0: sprite.position = CGPoint(x: -w / 2, y: 0)
        default: sprite.position = CGPoint(x: -w, y: 0)
        }
    }
}
