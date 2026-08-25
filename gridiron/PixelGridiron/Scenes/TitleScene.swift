//  TitleScene.swift
//  Front end: title, team select, options, and the how-to-play card.

import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

final class TitleScene: SKScene {

    /// Handed a fully configured match when the player is ready to play.
    var onStartMatch: ((MatchConfig) -> Void)?

    private enum Screen: Equatable {
        case title
        case pickTeam(forCup: Bool)
        case pickOpponent
        case options
        case howToPlay
    }

    private let backdrop = MenuBackdrop()
    private let content = SKNode()

    private let logo = PixelLabel("PIXEL GRIDIRON", pixelSize: 6, color: Palette.accent)
    private let tagline = PixelLabel("SEVEN-A-SIDE ARCADE FOOTBALL", pixelSize: 2, color: Palette.text)
    private let footer = PixelLabel("", pixelSize: 1, color: Palette.textDim)

    private var rows: [MenuRow] = []
    private var tiles: [TeamTile] = []

    private var screen: Screen = .title
    private var settings = Store.settings
    private var chosenTeam: TeamIdentity = League.teams[0]
    private var cupPending = false

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Palette.ink.skColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var isReady = false

    override func didMove(to view: SKView) {
        isReady = true
        addChild(backdrop)
        addChild(content)
        content.zPosition = 10

        logo.alignment = 0
        tagline.alignment = 0
        footer.alignment = 0
        content.addChild(logo)
        content.addChild(tagline)
        content.addChild(footer)

        chosenTeam = League.team(named: settings.favouriteTeam) ?? League.teams[0]

        SFX.shared.start()
        SFX.shared.isMuted = !settings.soundEnabled
        Haptics.isEnabled = settings.hapticsEnabled
        if settings.musicEnabled { SFX.shared.startMusic() }

        layout()
        show(.title)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isReady else { return }
        layout()
        show(screen)
    }

    private func layout() {
        backdrop.build(in: size)
        logo.position = CGPoint(x: size.width / 2, y: size.height - 54)
        tagline.position = CGPoint(x: size.width / 2, y: size.height - 78)
        footer.position = CGPoint(x: size.width / 2, y: 18)
    }

    // MARK: - Screens

    private func clearWidgets() {
        rows.forEach { $0.removeFromParent() }
        rows.removeAll()
        tiles.forEach { $0.removeFromParent() }
        tiles.removeAll()
        helpLabels.forEach { $0.removeFromParent() }
        helpLabels.removeAll()
    }

    private func show(_ newScreen: Screen) {
        screen = newScreen
        clearWidgets()

        switch newScreen {
        case .title:
            logo.text = "PIXEL GRIDIRON"
            tagline.text = "SEVEN-A-SIDE ARCADE FOOTBALL"
            let records = Store.records
            footer.text = records.gamesPlayed == 0
                ? "NO GAMES PLAYED YET"
                : "CAREER \(records.summary)   ·   CUPS \(records.cupWins)"
            buildRows([
                ("exhibition", "EXHIBITION", "ONE GAME"),
                ("cup", "CUP RUN", Store.cup == nil ? "THREE ROUNDS" : "IN PROGRESS"),
                ("how", "HOW TO PLAY", ""),
                ("options", "OPTIONS", ""),
            ])

        case .pickTeam(let forCup):
            cupPending = forCup
            logo.text = "PICK YOUR TEAM"
            tagline.text = forCup ? "WIN THREE AND TAKE THE CUP" : "WHO ARE YOU?"
            footer.text = "THE BAR IS TEAM STRENGTH"
            buildTiles()

        case .pickOpponent:
            logo.text = "PICK AN OPPONENT"
            tagline.text = "\(chosenTeam.fullName) VISIT"
            footer.text = ""
            buildTiles(excluding: chosenTeam)

        case .options:
            logo.text = "OPTIONS"
            tagline.text = ""
            footer.text = ""
            buildRows([
                ("quarter", "QUARTER LENGTH", "\(settings.quarterMinutes) MIN"),
                ("difficulty", "DIFFICULTY", settings.difficulty.name),
                ("sound", "SOUND", settings.soundEnabled ? "ON" : "OFF"),
                ("music", "MUSIC", settings.musicEnabled ? "ON" : "OFF"),
                ("haptics", "VIBRATION", settings.hapticsEnabled ? "ON" : "OFF"),
                ("reset", "CLEAR RECORDS", Store.records.summary),
                ("back", "BACK", ""),
            ])

        case .howToPlay:
            logo.text = "HOW TO PLAY"
            tagline.text = ""
            footer.text = "TAP ANYWHERE TO GO BACK"
            buildHelp()
        }
    }

    private func buildRows(_ items: [(String, String, String)]) {
        let rowHeight: CGFloat = 38
        let gap: CGFloat = 10
        let width = min(360, size.width - 80)
        let total = CGFloat(items.count) * rowHeight + CGFloat(items.count - 1) * gap
        var y = size.height / 2 + total / 2 - rowHeight / 2 - 24

        for (identifier, title, value) in items {
            let row = MenuRow(identifier: identifier, title: title, value: value,
                              size: CGSize(width: width, height: rowHeight))
            row.position = CGPoint(x: size.width / 2, y: y)
            content.addChild(row)
            rows.append(row)
            y -= rowHeight + gap
        }
    }

    private func buildTiles(excluding: TeamIdentity? = nil) {
        let teams = League.teams.filter { $0.abbreviation != excluding?.abbreviation }
        let columns = 4
        let rowsCount = Int(ceil(Double(teams.count) / Double(columns)))
        let margin: CGFloat = 34
        let gap: CGFloat = 10
        let tileWidth = (size.width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let tileHeight = min(tileWidth * 0.9, (size.height - 190) / CGFloat(rowsCount) - gap)
        let totalHeight = CGFloat(rowsCount) * tileHeight + CGFloat(rowsCount - 1) * gap
        let top = size.height / 2 + totalHeight / 2 - tileHeight / 2 - 20

        for (i, team) in teams.enumerated() {
            let column = i % columns
            let row = i / columns
            let tile = TeamTile(team: team, size: CGSize(width: tileWidth, height: tileHeight))
            tile.position = CGPoint(
                x: margin + tileWidth / 2 + CGFloat(column) * (tileWidth + gap),
                y: top - CGFloat(row) * (tileHeight + gap))
            content.addChild(tile)
            tiles.append(tile)
        }
    }

    private func buildHelp() {
        let lines = [
            "OFFENSE",
            "  PICK A PLAY, THEN TAP SNAP.",
            "  LEFT THUMB ANYWHERE ON THE LEFT IS THE STICK.",
            "  A B C D THROW TO THE MATCHING RECEIVER.",
            "  GO IS SPRINT - IT DRAINS THE BAR.",
            "  JUKE SIDESTEPS. DIVE ENDS THE PLAY FORWARD.",
            "",
            "DEFENSE",
            "  SWAP TAKES THE MAN NEAREST THE BALL.",
            "  HIT IS A DIVING TACKLE - MISS IT AND YOU ARE DOWN.",
            "",
            "RULES",
            "  FOUR DOWNS TO MAKE TEN YARDS.",
            "  ON FOURTH YOU MAY PUNT OR TRY A FIELD GOAL.",
            "  THE CLOCK RUNS ON RUNS AND CATCHES IN BOUNDS.",
        ]
        var y = size.height - 112
        for line in lines {
            let isHeading = !line.hasPrefix("  ") && !line.isEmpty
            let label = PixelLabel(line, pixelSize: 2,
                                   color: isHeading ? Palette.accent : Palette.text)
            label.alignment = -1
            label.position = CGPoint(x: 40, y: y)
            content.addChild(label)
            helpLabels.append(label)
            y -= 18
        }
    }

    private var helpLabels: [PixelLabel] = []

    // MARK: - Actions

    private func activate(_ identifier: String) {
        SFX.shared.play(.uiSelect)
        Haptics.tap()

        switch identifier {
        case "exhibition":
            show(.pickTeam(forCup: false))
        case "cup":
            if let run = Store.cup, !run.isComplete {
                resumeCup(run)
            } else {
                show(.pickTeam(forCup: true))
            }
        case "how":
            show(.howToPlay)
        case "options":
            show(.options)
        case "back":
            saveSettings()
            show(.title)

        case "quarter":
            let options = GameSettings.quarterOptions
            let index = options.firstIndex(of: settings.quarterMinutes) ?? 1
            settings.quarterMinutes = options[(index + 1) % options.count]
            refreshOptionRows()
        case "difficulty":
            let all = Coach.Difficulty.allCases
            let index = all.firstIndex(of: settings.difficulty) ?? 1
            settings.difficulty = all[(index + 1) % all.count]
            refreshOptionRows()
        case "sound":
            settings.soundEnabled.toggle()
            SFX.shared.isMuted = !settings.soundEnabled
            refreshOptionRows()
        case "music":
            settings.musicEnabled.toggle()
            if settings.musicEnabled { SFX.shared.startMusic() } else { SFX.shared.stopMusic() }
            refreshOptionRows()
        case "haptics":
            settings.hapticsEnabled.toggle()
            Haptics.isEnabled = settings.hapticsEnabled
            refreshOptionRows()
        case "reset":
            Store.records = Records()
            Store.cup = nil
            refreshOptionRows()

        default:
            break
        }
    }

    private func refreshOptionRows() {
        saveSettings()
        for row in rows {
            switch row.identifier {
            case "quarter": row.valueText = "\(settings.quarterMinutes) MIN"
            case "difficulty": row.valueText = settings.difficulty.name
            case "sound": row.valueText = settings.soundEnabled ? "ON" : "OFF"
            case "music": row.valueText = settings.musicEnabled ? "ON" : "OFF"
            case "haptics": row.valueText = settings.hapticsEnabled ? "ON" : "OFF"
            case "reset": row.valueText = Store.records.summary
            default: break
            }
        }
    }

    private func saveSettings() {
        Store.settings = settings
    }

    private func pickTeam(_ team: TeamIdentity) {
        SFX.shared.play(.uiSelect)
        Haptics.tap()
        chosenTeam = team
        settings.favouriteTeam = team.abbreviation
        saveSettings()

        if cupPending {
            let run = CupRun.start(playerTeam: team.abbreviation,
                                   seed: UInt64.random(in: 0..<UInt64.max))
            Store.cup = run
            resumeCup(run)
        } else {
            show(.pickOpponent)
        }
    }

    private func pickOpponent(_ team: TeamIdentity) {
        SFX.shared.play(.uiSelect)
        SFX.shared.stopMusic()
        Haptics.tap()
        onStartMatch?(MatchConfig.exhibition(playerTeam: chosenTeam,
                                             opponent: team,
                                             settings: settings))
    }

    private func resumeCup(_ run: CupRun) {
        guard let opponentAbbr = run.currentOpponent,
              let player = League.team(named: run.playerTeam),
              let opponent = League.team(named: opponentAbbr) else {
            Store.cup = nil
            show(.title)
            return
        }
        SFX.shared.stopMusic()
        var config = MatchConfig.exhibition(playerTeam: player,
                                            opponent: opponent,
                                            settings: settings)
        config.cupContext = run.roundName
        onStartMatch?(config)
    }

    // MARK: - Touches

    #if canImport(UIKit)
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: content)

        if case .howToPlay = screen {
            SFX.shared.play(.uiBack)
            show(.title)
            return
        }

        if let row = rows.first(where: { $0.contains(point) }) {
            activate(row.identifier)
            return
        }
        if let tile = tiles.first(where: { $0.contains(point) }) {
            switch screen {
            case .pickTeam: pickTeam(tile.team)
            case .pickOpponent: pickOpponent(tile.team)
            default: break
            }
            return
        }

        // Tapping empty space backs out of a picker.
        switch screen {
        case .pickTeam, .pickOpponent:
            SFX.shared.play(.uiBack)
            show(.title)
        default:
            break
        }
    }
    #endif
}
