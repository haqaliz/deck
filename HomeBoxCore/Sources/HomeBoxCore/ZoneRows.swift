import Foundation

// MARK: - World clock rows (local-only, zero fetch)

struct ZoneRow: Equatable {
    /// Display label: last identifier path component, "Local" for the
    /// current zone.
    var label: String
    /// Local wall-clock time "HH:MM" in that zone.
    var time: String
}

enum ZoneRows {
    static let maxCount = 3

    /// Builds time rows for the given identifiers, resolving "local" to the
    /// current zone. Invalid identifiers are dropped; the result keeps input
    /// order but with local rows first; capped at `maxCount`.
    static func build(identifiers: [String], at date: Date = Date()) -> [ZoneRow] {
        var localRows: [ZoneRow] = []
        var otherRows: [ZoneRow] = []
        for identifier in identifiers {
            let trimmed = identifier.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let zone: TimeZone?
            let label: String
            if trimmed == "local" {
                zone = .current
                label = "Local"
            } else {
                guard let resolved = TimeZone(identifier: trimmed) else { continue }
                zone = resolved
                label = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
            }
            guard let zone else { continue }
            let row = ZoneRow(label: label, time: Self.timeString(for: date, in: zone))
            if trimmed == "local" {
                localRows.append(row)
            } else {
                otherRows.append(row)
            }
        }
        return Array((localRows + otherRows).prefix(maxCount))
    }

    private static func timeString(for date: Date, in zone: TimeZone) -> String {
        let formatter = Self.formatter
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
