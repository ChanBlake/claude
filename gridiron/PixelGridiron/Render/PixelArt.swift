//  PixelArt.swift
//  Every sprite in the game, as a character grid.
//
//  All figures face **right**; the renderer flips the node's x-scale to face
//  left. Grids are anchored at the bottom centre so a prone dive frame and an
//  upright running frame line up at the feet without per-frame offsets.
//
//  Legend
//    .  transparent      k  outline        h  helmet     f  facemask
//    s  skin             j  jersey         t  trim       p  pants
//    c  shoe             b  ball           l  lace

import SpriteKit

enum PlayerFrame: String, CaseIterable {
    case stand
    case runA
    case runB
    case carry
    case block
    case dive
    case down
}

enum PixelArt {

    // MARK: - Player frames

    static let stand: [String] = [
        "....kkkk....",
        "...khhhhk...",
        "..khhhhhhk..",
        "..khhhhffk..",
        "...ksssk....",
        "..kkjjjjkk..",
        ".kjjjjjjjjk.",
        ".kjttjjttjk.",
        ".kjjjjjjjjk.",
        "..kjjjjjjk..",
        "..kkppppkk..",
        "...kppppk...",
        "...kp..pk...",
        "...kp..pk...",
        "...kc..ck...",
        "...kk..kk...",
    ]

    static let runA: [String] = [
        "....kkkk....",
        "...khhhhk...",
        "..khhhhhhk..",
        "..khhhhffk..",
        "...ksssk....",
        ".kkkjjjjkk..",
        ".kjjjjjjjjk.",
        "kjjttjjttjk.",
        ".kjjjjjjjjkk",
        "..kjjjjjjk..",
        "..kkppppkk..",
        "..kppppppk..",
        ".kp..k..pk..",
        ".kc...k.pk..",
        ".kk...kck...",
        "......kk....",
    ]

    static let runB: [String] = [
        "....kkkk....",
        "...khhhhk...",
        "..khhhhhhk..",
        "..khhhhffk..",
        "...ksssk....",
        "..kkjjjjkk..",
        ".kjjjjjjjjk.",
        ".kjttjjttjk.",
        ".kjjjjjjjjk.",
        "..kjjjjjjk..",
        "...kppppk...",
        "...kppppk...",
        "...kppppk...",
        "...kp.pk....",
        "...kc.ck....",
        "...kk.kk....",
    ]

    static let carry: [String] = [
        "....kkkk....",
        "...khhhhk...",
        "..khhhhhhk..",
        "..khhhhffk..",
        "...ksssk....",
        "..kkjjjjkk..",
        ".kjjjjjjjjk.",
        ".kjttjjttjkb",
        ".kjjjjjjjbbb",
        "..kjjjjjjkb.",
        "..kkppppkk..",
        "...kppppk...",
        "...kp..pk...",
        "...kp..pk...",
        "...kc..ck...",
        "...kk..kk...",
    ]

    static let block: [String] = [
        "....kkkk......",
        "...khhhhk.....",
        "..khhhhhhk....",
        "..khhhhffk....",
        "...ksssk......",
        "..kkjjjjkk....",
        ".kjjjjjjjjkkk.",
        ".kjttjjttjssk.",
        ".kjjjjjjjjkkk.",
        "..kjjjjjjk....",
        "..kkppppkk....",
        "...kppppk.....",
        "..kp...pk.....",
        "..kc...pk.....",
        "..kk...ck.....",
        ".......kk.....",
    ]

    static let dive: [String] = [
        "..........kkkk..",
        ".........khhhhk.",
        "kk......khhhhffk",
        "kckkkk..kssk....",
        ".kkjjjkkjjjk....",
        "..kjjjjjjjjjk...",
        "..kppppjjjjk....",
        ".kppppk.kkk.....",
        "kck.kk..........",
        "kk..............",
    ]

    static let down: [String] = [
        "................",
        "....kkkkkk......",
        "...kjjjjjjkkkk..",
        "..kjjjjjjjhhhhk.",
        ".kppppjjjjhhffk.",
        "kcppppkkkkkkkk..",
        "kk.kkk..........",
        "................",
    ]

    static func grid(_ frame: PlayerFrame) -> [String] {
        switch frame {
        case .stand: return stand
        case .runA: return runA
        case .runB: return runB
        case .carry: return carry
        case .block: return block
        case .dive: return dive
        case .down: return down
        }
    }

    // MARK: - Ball

    static let football: [String] = [
        "..bbb..",
        ".bbbbb.",
        "bbblbbb",
        ".bbbbb.",
        "..bbb..",
    ]

    static let ballPalette: [Character: PixelColor] = [
        "b": Palette.ball,
        "l": Palette.ballLace,
    ]

    // MARK: - Palettes

    /// Builds the colour map for one team's uniform. The helmet is darkened a
    /// touch on the shaded side so the sprite does not read as a flat decal.
    static func palette(for team: TeamIdentity) -> [Character: PixelColor] {
        [
            "k": Palette.outline,
            "h": team.helmet,
            "f": Palette.facemask,
            "s": Palette.skin,
            "j": team.jersey,
            "t": team.trim,
            "p": team.pants,
            "c": Palette.shoe,
            "b": Palette.ball,
            "l": Palette.ballLace,
        ]
    }

    /// A stable cache key for a team's version of a frame.
    static func cacheKey(_ frame: PlayerFrame, team: TeamIdentity) -> String {
        "P|\(frame.rawValue)|\(team.abbreviation)|\(team.jersey.r),\(team.jersey.g),\(team.jersey.b)"
    }

    static func texture(_ frame: PlayerFrame, team: TeamIdentity) -> SKTexture {
        TextureFactory.texture(grid: grid(frame),
                               palette: palette(for: team),
                               cacheKey: cacheKey(frame, team: team))
    }

    static func ballTexture() -> SKTexture {
        TextureFactory.texture(grid: football, palette: ballPalette, cacheKey: "BALL")
    }

    // MARK: - Marker sprites

    /// The down marker and the chain marker that sit on the sideline.
    static let downMarker: [String] = [
        "..kkk..",
        ".kaaak.",
        ".kaaak.",
        "..kkk..",
        "...k...",
        "...k...",
        "...k...",
        "...k...",
        "..kkk..",
    ]

    static func markerTexture(_ color: PixelColor, key: String) -> SKTexture {
        TextureFactory.texture(grid: downMarker,
                               palette: ["k": Palette.outline, "a": color],
                               cacheKey: "M|\(key)")
    }
}
