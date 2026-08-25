//  SFX.swift
//  Procedural chiptune audio. No sound files ship with the game.
//
//  Every effect is synthesised into a PCM buffer once at start-up and played
//  through a small pool of player nodes. Rendering ahead of time rather than in
//  a live render callback keeps the audio thread free of allocation and locks,
//  which is the usual way a game like this ends up with clicks and drop-outs.

import AVFoundation

final class SFX {

    enum Effect: String, CaseIterable {
        case whistle
        case snap
        case tackle
        case bigHit
        case catchBall
        case incomplete
        case kick
        case firstDown
        case touchdown
        case turnover
        case cheer
        case uiMove
        case uiSelect
        case uiBack
        case horn
    }

    static let shared = SFX()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0

    private let musicPlayer = AVAudioPlayerNode()
    private var musicBuffer: AVAudioPCMBuffer?

    private let sampleRate: Double = 22_050
    private var started = false

    var isMuted: Bool = false {
        didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : volume }
    }

    var volume: Float = 0.7 {
        didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : volume }
    }

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        buildBuffers()
        buildGraph()
    }

    // MARK: - Lifecycle

    /// Starts the audio session and engine. Safe to call repeatedly.
    func start() {
        guard !started else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // `.ambient` means the game never interrupts music the player already
        // has going, which for a pick-up-and-play title is the polite default.
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    func stop() {
        musicPlayer.stop()
        engine.pause()
        started = false
    }

    private func buildGraph() {
        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            voices.append(node)
        }
        engine.attach(musicPlayer)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
    }

    // MARK: - Playback

    func play(_ effect: Effect) {
        guard started, !isMuted, let buffer = buffers[effect] else { return }
        let node = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        if !node.isPlaying { node.play() }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    func startMusic() {
        guard started, let buffer = musicBuffer else { return }
        guard !musicPlayer.isPlaying else { return }
        musicPlayer.volume = 0.35
        musicPlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        musicPlayer.play()
    }

    func stopMusic() {
        musicPlayer.stop()
    }

    // MARK: - Synthesis

    private func buildBuffers() {
        for effect in Effect.allCases {
            buffers[effect] = render(effect)
        }
        musicBuffer = renderMusic()
    }

    /// Allocates a mono buffer of `seconds` and hands its sample array to `body`.
    private func makeBuffer(_ seconds: Double, _ body: (inout [Float], Double) -> Void) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var samples = [Float](repeating: 0, count: Int(frames))
        body(&samples, sampleRate)
        for i in 0..<Int(frames) {
            channel[i] = max(-1, min(1, samples[i]))
        }
        return buffer
    }

    /// A square wave, returned as a Double so the envelope maths downstream
    /// stays in one precision. `duty` under 0.5 gives the thinner NES-ish timbre.
    private func square(_ phase: Double, duty: Double = 0.5) -> Double {
        phase.truncatingRemainder(dividingBy: 1.0) < duty ? 1.0 : -1.0
    }

    private func render(_ effect: Effect) -> AVAudioPCMBuffer? {
        switch effect {
        case .whistle:
            // Two close tones beating against each other, like a real one.
            return makeBuffer(0.42) { s, rate in
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = min(1, t * 40) * exp(-t * 3.2)
                    let a = self.square(2350 * t, duty: 0.5)
                    let b = self.square(2510 * t, duty: 0.5)
                    s[i] = Float(env * 0.16 * (a + b) * 0.5)
                }
            }

        case .snap:
            return makeBuffer(0.09) { s, rate in
                var seed = RNG(seed: 7)
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = exp(-t * 55)
                    s[i] = Float((seed.unit() * 2 - 1) * env * 0.35)
                }
            }

        case .tackle:
            return makeBuffer(0.20) { s, rate in
                var seed = RNG(seed: 11)
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = exp(-t * 22)
                    let noise = seed.unit() * 2 - 1
                    let thud = self.square(90 * t, duty: 0.5)
                    s[i] = Float((noise * 0.5 + thud * 0.5) * env * 0.42)
                }
            }

        case .bigHit:
            return makeBuffer(0.34) { s, rate in
                var seed = RNG(seed: 13)
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = exp(-t * 11)
                    let noise = seed.unit() * 2 - 1
                    // Pitch drops through the hit — the classic arcade impact.
                    let freq = 140 * exp(-t * 6) + 40
                    let body = self.square(freq * t, duty: 0.35)
                    s[i] = Float((noise * 0.45 + body * 0.55) * env * 0.55)
                }
            }

        case .catchBall:
            return makeBuffer(0.14) { s, rate in
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = exp(-t * 26)
                    s[i] = Float((self.square(660 * t, duty: 0.25)) * env * 0.22)
                }
            }

        case .incomplete:
            return makeBuffer(0.26) { s, rate in
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = exp(-t * 9)
                    let freq = 420 * (1 - t * 0.6)
                    s[i] = Float((self.square(freq * t, duty: 0.5)) * env * 0.18)
                }
            }

        case .kick:
            return makeBuffer(0.22) { s, rate in
                var seed = RNG(seed: 17)
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = exp(-t * 18)
                    let noise = (seed.unit() * 2 - 1) * 0.4
                    let thump = self.square(180 * exp(-t * 8) * t, duty: 0.4)
                    s[i] = Float((noise + thump) * env * 0.4)
                }
            }

        case .firstDown:
            return self.arpeggio([523.25, 659.25, 783.99], noteLength: 0.075, gain: 0.2)

        case .touchdown:
            return self.arpeggio([523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5],
                                 noteLength: 0.11, gain: 0.24)

        case .turnover:
            return self.arpeggio([440.0, 349.23, 293.66, 233.08], noteLength: 0.1, gain: 0.22)

        case .cheer:
            return makeBuffer(1.5) { s, rate in
                var seed = RNG(seed: 23)
                var low: Double = 0
                for i in s.indices {
                    let t = Double(i) / rate
                    // A swell of filtered noise reads as a crowd well enough.
                    let env = min(1, t * 4) * exp(-max(0, t - 0.5) * 2.2)
                    let noise = seed.unit() * 2 - 1
                    low += (noise - low) * 0.06
                    s[i] = Float(low * env * 0.5)
                }
            }

        case .uiMove:
            return makeBuffer(0.05) { s, rate in
                for i in s.indices {
                    let t = Double(i) / rate
                    s[i] = Float((self.square(880 * t, duty: 0.5)) * exp(-t * 60) * 0.14)
                }
            }

        case .uiSelect:
            return self.arpeggio([659.25, 987.77], noteLength: 0.055, gain: 0.16)

        case .uiBack:
            return self.arpeggio([440.0, 329.63], noteLength: 0.055, gain: 0.14)

        case .horn:
            return makeBuffer(1.1) { s, rate in
                for i in s.indices {
                    let t = Double(i) / rate
                    let env = min(1, t * 12) * min(1, max(0, (1.1 - t) * 5))
                    let a = self.square(146.83 * t, duty: 0.5)
                    let b = self.square(220.0 * t, duty: 0.5)
                    s[i] = Float((a * 0.6 + b * 0.4) * env * 0.24)
                }
            }
        }
    }

    private func arpeggio(_ notes: [Double], noteLength: Double, gain: Double) -> AVAudioPCMBuffer? {
        let total = noteLength * Double(notes.count)
        return makeBuffer(total) { s, rate in
            for i in s.indices {
                let t = Double(i) / rate
                let noteIndex = min(notes.count - 1, Int(t / noteLength))
                let localT = t - Double(noteIndex) * noteLength
                let env = min(1, localT * 90) * exp(-localT * 9)
                s[i] = Float((self.square(notes[noteIndex] * t, duty: 0.4)) * env * gain)
            }
        }
    }

    /// A short marching loop for the title screen. Two square voices and a
    /// noise backbeat, sixteen steps, repeated.
    private func renderMusic() -> AVAudioPCMBuffer? {
        let bpm = 132.0
        let stepLength = 60.0 / bpm / 2      // eighth notes
        let melody: [Double?] = [
            392.00, nil, 523.25, nil, 587.33, nil, 523.25, nil,
            466.16, nil, 523.25, nil, 392.00, nil, nil, nil,
            349.23, nil, 466.16, nil, 523.25, nil, 466.16, nil,
            392.00, nil, 349.23, nil, 293.66, nil, nil, nil,
        ]
        let bass: [Double?] = [
            98.00, nil, 98.00, nil, 130.81, nil, 130.81, nil,
            116.54, nil, 116.54, nil, 98.00, nil, 98.00, nil,
            87.31, nil, 87.31, nil, 116.54, nil, 116.54, nil,
            98.00, nil, 98.00, nil, 73.42, nil, 73.42, nil,
        ]
        let steps = melody.count
        let total = stepLength * Double(steps)

        return makeBuffer(total) { s, rate in
            var seed = RNG(seed: 99)
            for i in s.indices {
                let t = Double(i) / rate
                let step = min(steps - 1, Int(t / stepLength))
                let localT = t - Double(step) * stepLength

                var sample = 0.0
                if let note = melody[step] {
                    let env = min(1, localT * 120) * exp(-localT * 7)
                    sample += (self.square(note * t, duty: 0.25)) * env * 0.16
                }
                if let note = bass[step] {
                    let env = min(1, localT * 90) * exp(-localT * 5)
                    sample += (self.square(note * t, duty: 0.5)) * env * 0.14
                }
                // Snare on the backbeat.
                if step % 8 == 4 {
                    let env = exp(-localT * 34)
                    sample += (seed.unit() * 2 - 1) * env * 0.10
                }
                s[i] = Float(sample)
            }
        }
    }
}
