//  RNG.swift
//  Seeded, deterministic randomness.
//
//  Every roll the simulation makes — broken tackles, contested catches, fumbles,
//  AI hesitation — draws from here. A play seeded with the same number and fed
//  the same inputs produces the same result on every device, which is what makes
//  the simulation tests in PixelGridironTests meaningful.

import Foundation

/// SplitMix64. Small, fast, passes the statistical tests that matter for a game,
/// and — unlike `SystemRandomNumberGenerator` — reproducible.
struct RNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zero state, which SplitMix64 handles fine but which makes
        // "seed 0" look suspiciously structured in the first few draws.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `[0, 1)`.
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform in `[low, high)`.
    mutating func double(_ low: Double, _ high: Double) -> Double {
        low + unit() * (high - low)
    }

    /// Uniform in `[low, high]`.
    mutating func int(_ low: Int, _ high: Int) -> Int {
        guard high > low else { return low }
        return low + Int(next() % UInt64(high - low + 1))
    }

    /// True with probability `p`. `chance(0)` is never, `chance(1)` is always.
    mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }

    /// Roughly normal, mean 0, standard deviation 1 — the sum of three uniforms.
    /// Cheaper than Box–Muller and the tails are tighter, which suits ratings
    /// rolls where a 5-sigma outcome would just read as a bug.
    mutating func bell() -> Double {
        (unit() + unit() + unit() - 1.5) * 2.0
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(0, items.count - 1)]
    }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var out = items
        guard out.count > 1 else { return out }
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            out.swapAt(i, int(0, i))
        }
        return out
    }
}
