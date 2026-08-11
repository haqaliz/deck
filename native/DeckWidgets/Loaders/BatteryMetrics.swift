import Foundation
import IOKit.ps

// MARK: - Battery state (IOKit power source, no subprocess)

enum PowerSource: Equatable {
    case battery
    case ac
}

struct BatterySnapshot: Equatable {
    let levelPercent: Double?
    let timeToEmptyMinutes: Int?
    let timeToFullMinutes: Int?
    let isCharging: Bool
    let isCharged: Bool
    let isPresent: Bool
    let powerSource: PowerSource
}

enum BatteryMetricsLoader {
    /// A full battery snapshot; missing keys degrade to nil, never crash.
    static func snapshot() -> BatterySnapshot {
        var current: Double?
        var maxCapacity: Double?
        var isCharging = false
        var isCharged = false
        var isPresent = true
        var powerSource: PowerSource = .battery
        var timeToEmptySeconds: Int?
        var timeToFullSeconds: Int?

        if
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let first = list.first,
            let desc = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any]
        {
            current = number(desc[kIOPSCurrentCapacityKey])
            maxCapacity = number(desc[kIOPSMaxCapacityKey])
            isCharging = bool(desc[kIOPSIsChargingKey])
            isCharged = bool(desc[kIOPSIsChargedKey])
            isPresent = bool(desc[kIOPSIsPresentKey], fallback: true)
            if (desc[kIOPSPowerSourceStateKey] as? String) == "AC Power" {
                powerSource = .ac
            }
            timeToEmptySeconds = int(desc[kIOPSTimeToEmptyKey])
            timeToFullSeconds = int(desc[kIOPSTimeToFullChargeKey])
        } else {
            isPresent = false
        }

        let level: Double? = (current != nil && maxCapacity != nil)
            ? percent(current: current!, maxCapacity: maxCapacity!)
            : nil

        return BatterySnapshot(
            levelPercent: level,
            timeToEmptyMinutes: timeToEmptySeconds.flatMap(timeMinutes),
            timeToFullMinutes: timeToFullSeconds.flatMap(timeMinutes),
            isCharging: isCharging,
            isCharged: isCharged || (level ?? 0) >= 100,
            isPresent: isPresent,
            powerSource: powerSource
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func bool(_ value: Any?, fallback: Bool = false) -> Bool {
        (value as? Bool) ?? fallback
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// Charge percent from current/max capacity, clamped to 0...100.
    private static func percent(current: Double, maxCapacity: Double) -> Double? {
        guard maxCapacity > 0 else { return nil }
        return min(100, max(0, current / maxCapacity * 100))
    }

    /// Whole minutes from a seconds value; 0 (or less) means "not applicable".
    private static func timeMinutes(seconds: Int) -> Int? {
        guard seconds > 0 else { return nil }
        return Int(round(Double(seconds) / 60))
    }
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
