import Foundation

// MARK: - Threshold tier (shared alarm coloring for LiveBox + NetBox)
//
// Pure logic extracted so threshold coloring is testable in DeckSharedTests
// (the widget target can't be compiled into a unit-test bundle). LiveBox
// colors metric rows + chart lines by current-value tier (ROADMAP.md:69);
// NetBox will reuse the same rules (ROADMAP.md:81).

enum ThresholdTier {
    case normal
    case warn
    case alarm

    /// Alarm wins over warn when warn > alarm (prd.md §2).
    static func tier(value: Double, warn: Double, alarm: Double) -> ThresholdTier {
        if value >= alarm { return .alarm }
        if value >= warn { return .warn }
        return .normal
    }

    /// Standard warn (amber) and alarm (red) colors so every widget speaks
    /// the same alarm language.
    static let warnColor = RGBA(red: 1.0, green: 0.76, blue: 0.05)
    static let alarmColor = RGBA(red: 1.0, green: 0.25, blue: 0.2)
}
