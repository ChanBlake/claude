//  Vec2.swift
//  Pure 2D vector math. No platform imports — this file, and everything else in
//  Core/, must compile on any Swift toolchain so the rules and simulation can be
//  unit-tested without a simulator.

import Foundation

/// A point or direction on the field, measured in **yards**.
///
/// Field space is described in `Field.swift`: `x` runs the length of the field,
/// `y` runs across it. Nothing in Core knows about points, pixels or screens.
struct Vec2: Equatable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (v: Vec2, s: Double) -> Vec2 { Vec2(v.x * s, v.y * s) }
    static func * (s: Double, v: Vec2) -> Vec2 { v * s }
    static func / (v: Vec2, s: Double) -> Vec2 { Vec2(v.x / s, v.y / s) }
    static prefix func - (v: Vec2) -> Vec2 { Vec2(-v.x, -v.y) }

    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }
    static func *= (a: inout Vec2, s: Double) { a = a * s }

    var lengthSquared: Double { x * x + y * y }
    var length: Double { (x * x + y * y).squareRoot() }

    /// Unit vector, or `.zero` for a zero-length vector (never NaN).
    var normalized: Vec2 {
        let len = length
        guard len > 1e-9 else { return .zero }
        return Vec2(x / len, y / len)
    }

    /// Rotated 90° counter-clockwise. Used for blocking angles and juke steps.
    var perpendicular: Vec2 { Vec2(-y, x) }

    func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }

    func distance(to other: Vec2) -> Double { (self - other).length }
    func distanceSquared(to other: Vec2) -> Double { (self - other).lengthSquared }

    /// Clamped to at most `max` in length. Speed limits go through here.
    func limited(to max: Double) -> Vec2 {
        let lenSq = lengthSquared
        guard lenSq > max * max, lenSq > 1e-12 else { return self }
        return self * (max / lenSq.squareRoot())
    }

    var angle: Double { atan2(y, x) }

    static func fromAngle(_ radians: Double, length: Double = 1) -> Vec2 {
        Vec2(cos(radians) * length, sin(radians) * length)
    }

    static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 {
        a + (b - a) * t
    }
}

extension Vec2: CustomStringConvertible {
    var description: String { String(format: "(%.2f, %.2f)", x, y) }
}

/// Moves `value` toward `target` by at most `maxDelta`. Used anywhere a value
/// needs to ramp rather than snap — stamina, camera zoom, meter fills.
func moveToward(_ value: Double, _ target: Double, _ maxDelta: Double) -> Double {
    if abs(target - value) <= maxDelta { return target }
    return value + (target > value ? maxDelta : -maxDelta)
}

func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(max(value, low), high)
}

func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
    min(max(value, low), high)
}
