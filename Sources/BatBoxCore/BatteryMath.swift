import Foundation

public enum BatteryMath {
    /// Charge percent from current/max capacity, clamped to 0...100.
    /// A non-positive max (unknown capacity) yields nil.
    public static func percent(current: Double, maxCapacity: Double) -> Double? {
        guard maxCapacity > 0 else { return nil }
        return min(100, max(0, current / maxCapacity * 100))
    }

    /// Color tier: high > 50, medium 20...50, low < 20.
    public static func tier(percent: Double) -> LevelTier {
        if percent > 50 { return .high }
        if percent >= 20 { return .medium }
        return .low
    }

    /// Whole minutes from a seconds value; 0 (or less) means "not applicable".
    public static func timeMinutes(seconds: Int) -> Int? {
        guard seconds > 0 else { return nil }
        return Int(round(Double(seconds) / 60))
    }
}
