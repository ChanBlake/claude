//  Palette.swift
//  The game's colours, and the bridge from Core's platform-free `PixelColor`
//  into SpriteKit.

import SpriteKit

extension PixelColor {
    var skColor: SKColor {
        SKColor(red: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: 1.0)
    }
}

/// Everything that is not a team colour.
enum Palette {
    // Turf
    static let turfLight = PixelColor(0x3E7A3A)
    static let turfDark = PixelColor(0x356C32)
    static let turfShadow = PixelColor(0x2A5628)
    static let chalk = PixelColor(0xEDF2ED)
    static let chalkDim = PixelColor(0xBCC9BC)

    // Chrome
    static let ink = PixelColor(0x0E1114)
    static let panel = PixelColor(0x161C22)
    static let panelLight = PixelColor(0x232C35)
    static let panelEdge = PixelColor(0x3A4753)
    static let text = PixelColor(0xE9EFF4)
    static let textDim = PixelColor(0x8C9AA6)
    static let accent = PixelColor(0xF2C14E)
    static let accentHot = PixelColor(0xE8613A)
    static let good = PixelColor(0x63C67A)
    static let bad = PixelColor(0xD9534F)

    // Field furniture
    static let ball = PixelColor(0x7B4A22)
    static let ballLace = PixelColor(0xF0EDE4)
    static let goalpost = PixelColor(0xE8C63A)
    static let skin = PixelColor(0xC98F63)
    static let skinDark = PixelColor(0x9A6B45)
    static let facemask = PixelColor(0xB9C2CA)
    static let outline = PixelColor(0x12161A)
    static let shoe = PixelColor(0x1A1E22)

    // Crowd bands behind the sidelines — cheap, but the field stops feeling like
    // it is floating in a void.
    static let crowdBase = PixelColor(0x1C2430)
    static let crowdSpecks: [PixelColor] = [
        PixelColor(0x2E3A48), PixelColor(0x3D4C5C), PixelColor(0x55606E),
        PixelColor(0x6E5A4A), PixelColor(0x4A5566), PixelColor(0x8A7A66),
    ]

    static let markerFirstDown = PixelColor(0xF2C14E)
    static let markerScrimmage = PixelColor(0x5FA8E8)
}

/// Z-ordering. One place, so nothing ever fights over what is on top.
enum ZLayer {
    static let crowd: CGFloat = -60
    static let turf: CGFloat = -50
    static let paint: CGFloat = -45
    static let markers: CGFloat = -40
    static let shadows: CGFloat = -10
    static let players: CGFloat = 0
    static let ball: CGFloat = 40
    static let ballShadow: CGFloat = -5
    static let goalposts: CGFloat = 60
    static let fieldOverlay: CGFloat = 80
    static let hud: CGFloat = 200
    static let controls: CGFloat = 220
    static let overlay: CGFloat = 300
    static let banner: CGFloat = 320
}
