//  TextureFactory.swift
//  Turns pixel grids into SKTextures.
//
//  The game ships no image assets. Every sprite, every glyph and every piece of
//  field furniture is a small character grid in source, rasterised once here and
//  cached. That keeps the repository text-only and makes recolouring a team a
//  matter of changing three `PixelColor`s rather than redrawing anything.

import SpriteKit
import CoreGraphics

enum TextureFactory {

    private static var cache: [String: SKTexture] = [:]
    private static let cacheLimit = 512

    /// Clears cached textures. Called on a memory warning.
    static func purge() {
        cache.removeAll(keepingCapacity: false)
    }

    // MARK: - Raw construction

    /// Builds a texture from raw RGBA pixels. `pixels` is row-major, top row first.
    static func texture(width: Int, height: Int, pixels: [UInt32]) -> SKTexture {
        precondition(pixels.count == width * height, "pixel buffer does not match dimensions")
        var data = pixels
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                                      | CGBitmapInfo.byteOrder32Big.rawValue)

        let image: CGImage? = data.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
            return ctx.makeImage()
        }

        guard let cgImage = image else {
            return SKTexture()
        }
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .nearest
        return texture
    }

    /// Packs a colour into the premultiplied RGBA word the context expects.
    private static func word(_ color: PixelColor, alpha: UInt8 = 255) -> UInt32 {
        if alpha == 0 { return 0 }
        let a = UInt32(alpha)
        let r = UInt32(UInt16(color.r) * UInt16(alpha) / 255)
        let g = UInt32(UInt16(color.g) * UInt16(alpha) / 255)
        let b = UInt32(UInt16(color.b) * UInt16(alpha) / 255)
        return (r << 24) | (g << 16) | (b << 8) | a
    }

    // MARK: - Grids

    /// Rasterises a character grid. Characters not present in `palette` are
    /// transparent, which is how `.` works without being special-cased.
    static func texture(grid: [String],
                        palette: [Character: PixelColor],
                        cacheKey: String? = nil) -> SKTexture {
        if let key = cacheKey, let hit = cache[key] { return hit }

        let height = grid.count
        let width = grid.map(\.count).max() ?? 0
        guard width > 0, height > 0 else { return SKTexture() }

        var pixels = [UInt32](repeating: 0, count: width * height)
        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let color = palette[ch] else { continue }
                pixels[y * width + x] = word(color)
            }
        }

        let tex = texture(width: width, height: height, pixels: pixels)
        if let key = cacheKey { store(key, tex) }
        return tex
    }

    // MARK: - Text

    static func textTexture(_ text: String,
                            color: PixelColor,
                            shadow: PixelColor?) -> SKTexture {
        let key = "T|\(text)|\(color.r),\(color.g),\(color.b)|\(shadow.map { "\($0.r),\($0.g),\($0.b)" } ?? "-")"
        if let hit = cache[key] { return hit }

        let bits = PixelFont.rasterize(text)
        let baseWidth = bits.first?.count ?? 1
        let baseHeight = bits.count
        let pad = shadow == nil ? 0 : 1
        let width = baseWidth + pad
        let height = baseHeight + pad

        var pixels = [UInt32](repeating: 0, count: width * height)
        if let shadow = shadow {
            let s = word(shadow)
            for y in 0..<baseHeight {
                for x in 0..<baseWidth where bits[y][x] {
                    pixels[(y + 1) * width + (x + 1)] = s
                }
            }
        }
        let f = word(color)
        for y in 0..<baseHeight {
            for x in 0..<baseWidth where bits[y][x] {
                pixels[y * width + x] = f
            }
        }

        let tex = texture(width: width, height: height, pixels: pixels)
        store(key, tex)
        return tex
    }

    // MARK: - Flat fills

    static func solid(_ color: PixelColor, width: Int = 1, height: Int = 1) -> SKTexture {
        let key = "S|\(color.r),\(color.g),\(color.b)|\(width)x\(height)"
        if let hit = cache[key] { return hit }
        let tex = texture(width: width, height: height,
                          pixels: [UInt32](repeating: word(color), count: width * height))
        store(key, tex)
        return tex
    }

    /// A soft round shadow, used under players and the ball.
    static func shadowBlob(diameter: Int) -> SKTexture {
        let key = "B|\(diameter)"
        if let hit = cache[key] { return hit }
        let d = max(2, diameter)
        var pixels = [UInt32](repeating: 0, count: d * d)
        let r = Double(d) / 2
        for y in 0..<d {
            for x in 0..<d {
                let dx = (Double(x) + 0.5 - r) / r
                let dy = (Double(y) + 0.5 - r) / (r * 0.55)
                let dist = (dx * dx + dy * dy).squareRoot()
                guard dist <= 1 else { continue }
                let alpha = UInt8(clamp((1 - dist) * 150, 0, 150))
                pixels[y * d + x] = word(PixelColor(0x000000), alpha: alpha)
            }
        }
        let tex = texture(width: d, height: d, pixels: pixels)
        store(key, tex)
        return tex
    }

    private static func store(_ key: String, _ texture: SKTexture) {
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = texture
    }
}
