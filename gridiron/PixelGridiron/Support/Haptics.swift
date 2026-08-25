//  Haptics.swift
//  Thin wrapper so the scenes never touch UIKit's feedback generators directly.

#if os(iOS)
import UIKit

enum Haptics {

    static var isEnabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notice = UINotificationFeedbackGenerator()

    /// Warms the Taptic Engine so the first buzz of a play is not late.
    static func prepare() {
        guard isEnabled else { return }
        light.prepare()
        medium.prepare()
        heavy.prepare()
    }

    static func tap() {
        guard isEnabled else { return }
        light.impactOccurred()
    }

    static func hit() {
        guard isEnabled else { return }
        medium.impactOccurred()
    }

    static func bigHit() {
        guard isEnabled else { return }
        heavy.impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        notice.notificationOccurred(.success)
    }

    static func failure() {
        guard isEnabled else { return }
        notice.notificationOccurred(.error)
    }
}
#else
enum Haptics {
    static var isEnabled = true
    static func prepare() {}
    static func tap() {}
    static func hit() {}
    static func bigHit() {}
    static func success() {}
    static func failure() {}
}
#endif
