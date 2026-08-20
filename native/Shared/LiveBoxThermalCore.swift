import Foundation

// MARK: - Thermal pressure level (LiveBox thermal row)
//
// System thermal pressure from ProcessInfo.processInfo.thermalState, mapped to
// the shared warn/alarm tint language. Pure logic lives here (not in the
// widget) so DeckSharedTests can cover it — the widget target can't compile
// into a unit-test bundle.
//
// The mapping takes a raw Int rather than ProcessInfo.ThermalState so tests
// don't have to fabricate a ProcessInfo; the widget passes
// `ProcessInfo.processInfo.thermalState.rawValue`.

enum ThermalLevel: Int {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3
}

enum LiveBoxThermalCore {
    /// Out-of-range values clamp rather than fall back to `.nominal`: a state
    /// beyond critical must never render as an untinted, calm-looking row.
    static func level(rawValue: Int) -> ThermalLevel {
        ThermalLevel(rawValue: rawValue) ?? (rawValue > ThermalLevel.critical.rawValue ? .critical : .nominal)
    }

    static func label(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: return "NOMINAL"
        case .fair: return "FAIR"
        case .serious: return "SERIOUS"
        case .critical: return "CRITICAL"
        }
    }

    /// Nominal and fair are never tinted — the "idle values are never tinted"
    /// rule shared with NetBox threshold coloring.
    static func tier(_ level: ThermalLevel) -> ThresholdTier {
        switch level {
        case .nominal, .fair: return .normal
        case .serious: return .warn
        case .critical: return .alarm
        }
    }
}
