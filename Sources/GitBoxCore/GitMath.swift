import Foundation

public enum GitMath {
    /// `yyyy-MM-dd` label for a date in the given calendar.
    public static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// The last `n` calendar-day labels ending at `today`, oldest first.
    public static func daysBack(_ n: Int, today: Date, calendar: Calendar) -> [String] {
        guard n > 0 else { return [] }
        return (0..<n).map { offset in
            let date = calendar.date(byAdding: .day, value: -(n - 1 - offset), to: today) ?? today
            return dayLabel(date, calendar: calendar)
        }
    }

    /// Ordered counts for the window, oldest first; days outside the window are
    /// dropped. A fetch window wider than the chart window lands here.
    public static func bucket(counts: [String: Int], window: [String]) -> [Int] {
        window.map { counts[$0] ?? 0 }
    }

    /// Consecutive days with at least one commit, counting back from today.
    /// Grace rule: an empty today does not break the run — counting starts at
    /// yesterday until today is over.
    public static func streak(counts: [String: Int], window: [String]) -> Int {
        var index = window.count - 1
        guard index >= 0 else { return 0 }
        if (counts[window[index]] ?? 0) == 0 {
            index -= 1
        }
        var run = 0
        while index >= 0 {
            guard (counts[window[index]] ?? 0) > 0 else { break }
            run += 1
            index -= 1
        }
        return run
    }
}
