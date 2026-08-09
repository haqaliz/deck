import Foundation

public enum BatteryFormatters {
    /// "71%"
    public static func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    /// "6h 34m", "45m"; nil → "—"
    public static func formatTime(minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// "107"; nil → "—"
    public static func formatCycles(_ count: Int?) -> String {
        guard let count else { return "—" }
        return "\(count)"
    }

    /// "Charging" / "Discharging" / "Full" / "AC Power"
    public static func formatState(isCharging: Bool, isCharged: Bool, powerSource: PowerSource) -> String {
        if powerSource == .ac && isCharged { return "AC Power" }
        if isCharged { return "Full" }
        if isCharging { return "Charging" }
        return "Discharging"
    }
}
