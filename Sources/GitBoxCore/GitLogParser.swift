import Foundation

public enum GitLogParser {
    /// Counts commits per `yyyy-MM-dd` day string. Blank and malformed lines
    /// (anything that isn't a strictly padded `yyyy-MM-dd`) are skipped.
    public static func dayCounts(from raw: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in raw.split(separator: "\n") {
            let day = String(line)
            guard isDayLabel(day) else { continue }
            counts[day, default: 0] += 1
        }
        return counts
    }

    private static func isDayLabel(_ day: String) -> Bool {
        guard day.count == 10, day[day.index(day.startIndex, offsetBy: 4)] == "-",
              day[day.index(day.startIndex, offsetBy: 7)] == "-",
              day.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
        guard let date = formatter.date(from: day) else { return false }
        return formatter.string(from: date) == day
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
