import Foundation

public enum OpenCodeFormatters {
public static func formatTokens(_ value: Int64) -> String {
        let n = Double(value)
        if n >= 1_000_000_000 { return String(format: "%.2fB", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", n / 1_000) }
        return "\(value)"
    }

public static func formatCost(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

public static func shortDay(_ day: String) -> String {
        String(day.dropFirst(5))
    }
}
