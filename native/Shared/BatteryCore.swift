import Foundation

// MARK: - Battery pure logic (formatters + math)
//
// Extracted from DeckWidgets/Loaders/BatteryMetrics.swift so the formatters are
// testable in DeckSharedTests (the widget target can't be compiled into a
// unit-test bundle). The IOKit loader feeds these pure functions and keeps the
// BatterySnapshot shape. Pure-core extraction (LiveBoxDiskCore precedent) —
// no IOKit import lands in the app/agent/test targets.

enum PowerSource: Equatable {
    case battery
    case ac
}

enum BatteryFormatters {
    /// "71%"
    static func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    /// "6h 34m", "45m"; nil → "—"
    static func formatTime(minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// "Charging" / "Discharging" / "Full" / "AC Power"
    static func formatState(isCharging: Bool, isCharged: Bool, powerSource: PowerSource) -> String {
        if powerSource == .ac && isCharged { return "AC Power" }
        if isCharged { return "Full" }
        if isCharging { return "Charging" }
        return "Discharging"
    }
}

enum BatteryMath {
    /// Charge percent from current/max capacity, clamped to 0...100.
    static func percent(current: Double, maxCapacity: Double) -> Double? {
        guard maxCapacity > 0 else { return nil }
        return min(100, max(0, current / maxCapacity * 100))
    }

    /// Normalises IOKit's reported time estimate.
    ///
    /// `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullChargeKey` are already in
    /// MINUTES — this used to divide by 60 as though they were seconds, which
    /// rendered a real "1:02 remaining" as "1m". IOKit uses 0 for "not
    /// applicable" and -1 for "still calculating"; both mean no estimate.
    static func timeMinutes(reported: Int) -> Int? {
        guard reported > 0 else { return nil }
        return reported
    }
}
