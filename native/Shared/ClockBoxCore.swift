import Foundation

// MARK: - ClockBox pure logic
//
// Everything ClockBox needs, with no IOKit, no subprocess, no network and no
// snapshot file — the widget resolves `TimeZone` and `Date` at render time.
// ClockBox is the first Deck widget on neither data path (see CLAUDE.md), so
// this file is its entire data layer.
//
// Grew out of `ZoneRows` in HomeBoxSnapshot.swift when the world-clock half of
// HomeBox became its own widget.

/// Where a city's calendar day sits relative to the reference zone's.
/// The widest real offset span is ~26h, so these three cases are exhaustive.
enum ClockRelativeDay: Equatable {
    case yesterday
    case today
    case tomorrow

    var label: String {
        switch self {
        case .yesterday: return "Yesterday"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        }
    }
}

/// One entry in the settings city picker. `displayName` carries the country
/// ("Toronto, Canada") because that is what the picker shows; the widget face
/// uses the short form via `ClockBoxCore.displayName(id:)`.
struct ClockCity: Equatable {
    let displayName: String
    let id: String
}

/// One rendered clock.
struct ClockRow: Equatable {
    let id: String
    let name: String
    let time: String
    let day: ClockRelativeDay
    let offset: String
}

enum ClockBoxCore {
    /// Sentinel for "wherever this Mac is", carried over from
    /// `HomeBoxSettings.timezoneIDs` whose default was ["local", "UTC"].
    /// Deliberately not an IANA identifier: the machine's zone can change.
    static let localID = "local"

    /// How many cities may be stored. The large face shows all of them; the
    /// medium face shows fewer because three columns is what fits legibly.
    static let maxCities = 6
    static let mediumCapacity = 3
    static let largeCapacity = 6

    // MARK: Resolution

    static func resolve(id: String) -> TimeZone? {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == localID { return .current }
        return TimeZone(identifier: trimmed)
    }

    /// Short label for the widget face: the curated city name without its
    /// country, else the identifier's last path component with underscores
    /// turned back into spaces ("America/New_York" -> "New York").
    static func displayName(id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        let resolvedID = trimmed == localID ? (TimeZone.current.identifier) : trimmed
        if let city = ClockBoxCities.curated.first(where: { $0.id == resolvedID }) {
            return String(city.displayName.split(separator: ",").first ?? "")
                .trimmingCharacters(in: .whitespaces)
        }
        let component = resolvedID.split(separator: "/").last.map(String.init) ?? resolvedID
        return component.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Time

    /// 24-hour wall-clock time in that zone.
    static func timeLabel(id: String, at date: Date) -> String {
        guard let zone = resolve(id: id) else { return "--:--" }
        let formatter = Self.timeFormatter
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    // MARK: Offset

    /// Signed offset from the *reference* zone — not from UTC. The native
    /// widget labels the user's own city "+0HRS" and everything else relative
    /// to it, so UTC is the wrong zero point.
    ///
    /// Both sides are evaluated with `secondsFromGMT(for:)` at the given date:
    /// a static offset is wrong for half the year wherever DST applies, and
    /// the two zones do not necessarily change on the same dates (Amsterdam
    /// shifts, Tehran has not since 2022). Minutes are never rounded —
    /// Kathmandu is +5:45 and must render as such.
    static func offsetLabel(id: String, relativeTo reference: TimeZone, at date: Date) -> String {
        guard let zone = resolve(id: id) else { return "" }
        let delta = zone.secondsFromGMT(for: date) - reference.secondsFromGMT(for: date)
        if delta == 0 { return "+0HRS" }
        let sign = delta < 0 ? "-" : "+"
        let magnitude = abs(delta)
        return String(format: "%@%d:%02d", sign, magnitude / 3600, (magnitude % 3600) / 60)
    }

    // MARK: Relative day

    static func relativeDay(id: String, relativeTo reference: TimeZone, at date: Date) -> ClockRelativeDay {
        guard let zone = resolve(id: id) else { return .today }
        let there = Self.dayNumber(for: date, in: zone)
        let here = Self.dayNumber(for: date, in: reference)
        if there < here { return .yesterday }
        if there > here { return .tomorrow }
        return .today
    }

    /// The calendar date in `zone` as a sortable `yyyymmdd` integer. Comparing
    /// these rather than calling `Calendar.isDate(_:inSameDayAs:)` twice keeps
    /// the yesterday/today/tomorrow decision to one integer comparison, and
    /// the encoding is monotonic across month and year boundaries.
    private static func dayNumber(for date: Date, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }

    // MARK: Rows

    /// Builds one row per identifier, dropping anything that will not resolve,
    /// keeping input order, capped at `limit`.
    ///
    /// The limit is the caller's to choose because each widget family fits a
    /// different number of columns, and `Shared` cannot import WidgetKit to
    /// learn the family itself.
    static func rows(
        ids: [String],
        relativeTo reference: TimeZone,
        at date: Date,
        limit: Int = maxCities
    ) -> [ClockRow] {
        var rows: [ClockRow] = []
        for id in ids {
            guard rows.count < limit, resolve(id: id) != nil else { continue }
            rows.append(
                ClockRow(
                    id: id,
                    name: displayName(id: id),
                    time: timeLabel(id: id, at: date),
                    day: relativeDay(id: id, relativeTo: reference, at: date),
                    offset: offsetLabel(id: id, relativeTo: reference, at: date)
                )
            )
        }
        return rows
    }

    /// The "main" clock — what the small face shows.
    ///
    /// An explicit choice from settings wins, including the user's own zone if
    /// that is what they picked. A stale choice (a city since removed from the
    /// list, or an unresolvable id) is ignored rather than blanking the face.
    ///
    /// With no explicit choice, auto keeps the original rule: the first
    /// *non-local* city, because a small widget rendering your own zone at
    /// "+0HRS" tells you nothing. Local is used only when it is all there is.
    static func mainCityID(ids: [String], preferred: String?) -> String? {
        let valid = ids.filter { resolve(id: $0) != nil }
        if let preferred, !preferred.trimmingCharacters(in: .whitespaces).isEmpty,
           valid.contains(preferred), resolve(id: preferred) != nil {
            return preferred
        }
        return valid.first { $0.trimmingCharacters(in: .whitespaces) != localID } ?? valid.first
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - Curated city table
//
// The settings picker offers these rather than all ~600 IANA identifiers, so
// the names read like the native widget's ("Toronto, Canada") instead of
// "America/Argentina/Buenos_Aires". Anything missing is still usable — an id
// typed into settings by hand resolves fine and falls back to its last path
// component for a label.

enum ClockBoxCities {
    static let curated: [ClockCity] = [
        // Americas
        ClockCity(displayName: "Anchorage, U.S.A.", id: "America/Anchorage"),
        ClockCity(displayName: "Bogotá, Colombia", id: "America/Bogota"),
        ClockCity(displayName: "Buenos Aires, Argentina", id: "America/Argentina/Buenos_Aires"),
        ClockCity(displayName: "Calgary, Canada", id: "America/Edmonton"),
        ClockCity(displayName: "Chicago, U.S.A.", id: "America/Chicago"),
        ClockCity(displayName: "Denver, U.S.A.", id: "America/Denver"),
        ClockCity(displayName: "Halifax, Canada", id: "America/Halifax"),
        ClockCity(displayName: "Honolulu, U.S.A.", id: "Pacific/Honolulu"),
        ClockCity(displayName: "Lima, Peru", id: "America/Lima"),
        ClockCity(displayName: "Los Angeles, U.S.A.", id: "America/Los_Angeles"),
        ClockCity(displayName: "Mexico City, Mexico", id: "America/Mexico_City"),
        ClockCity(displayName: "Montréal, Canada", id: "America/Montreal"),
        ClockCity(displayName: "New York, U.S.A.", id: "America/New_York"),
        ClockCity(displayName: "Phoenix, U.S.A.", id: "America/Phoenix"),
        ClockCity(displayName: "Santiago, Chile", id: "America/Santiago"),
        ClockCity(displayName: "São Paulo, Brazil", id: "America/Sao_Paulo"),
        ClockCity(displayName: "Toronto, Canada", id: "America/Toronto"),
        ClockCity(displayName: "Vancouver, Canada", id: "America/Vancouver"),
        ClockCity(displayName: "Winnipeg, Canada", id: "America/Winnipeg"),

        // Europe
        ClockCity(displayName: "Amsterdam, Netherlands", id: "Europe/Amsterdam"),
        ClockCity(displayName: "Athens, Greece", id: "Europe/Athens"),
        ClockCity(displayName: "Barcelona, Spain", id: "Europe/Madrid"),
        ClockCity(displayName: "Berlin, Germany", id: "Europe/Berlin"),
        ClockCity(displayName: "Brussels, Belgium", id: "Europe/Brussels"),
        ClockCity(displayName: "Bucharest, Romania", id: "Europe/Bucharest"),
        ClockCity(displayName: "Budapest, Hungary", id: "Europe/Budapest"),
        ClockCity(displayName: "Copenhagen, Denmark", id: "Europe/Copenhagen"),
        ClockCity(displayName: "Dublin, Ireland", id: "Europe/Dublin"),
        ClockCity(displayName: "Helsinki, Finland", id: "Europe/Helsinki"),
        ClockCity(displayName: "Istanbul, Türkiye", id: "Europe/Istanbul"),
        ClockCity(displayName: "Kyiv, Ukraine", id: "Europe/Kyiv"),
        ClockCity(displayName: "Lisbon, Portugal", id: "Europe/Lisbon"),
        ClockCity(displayName: "London, U.K.", id: "Europe/London"),
        ClockCity(displayName: "Moscow, Russia", id: "Europe/Moscow"),
        ClockCity(displayName: "Oslo, Norway", id: "Europe/Oslo"),
        ClockCity(displayName: "Paris, France", id: "Europe/Paris"),
        ClockCity(displayName: "Prague, Czechia", id: "Europe/Prague"),
        ClockCity(displayName: "Reykjavík, Iceland", id: "Atlantic/Reykjavik"),
        ClockCity(displayName: "Rome, Italy", id: "Europe/Rome"),
        ClockCity(displayName: "Stockholm, Sweden", id: "Europe/Stockholm"),
        ClockCity(displayName: "Vienna, Austria", id: "Europe/Vienna"),
        ClockCity(displayName: "Warsaw, Poland", id: "Europe/Warsaw"),
        ClockCity(displayName: "Zürich, Switzerland", id: "Europe/Zurich"),

        // Africa & Middle East
        ClockCity(displayName: "Abu Dhabi, U.A.E.", id: "Asia/Dubai"),
        ClockCity(displayName: "Cairo, Egypt", id: "Africa/Cairo"),
        ClockCity(displayName: "Cape Town, South Africa", id: "Africa/Johannesburg"),
        ClockCity(displayName: "Casablanca, Morocco", id: "Africa/Casablanca"),
        ClockCity(displayName: "Doha, Qatar", id: "Asia/Qatar"),
        ClockCity(displayName: "Jerusalem, Israel", id: "Asia/Jerusalem"),
        ClockCity(displayName: "Lagos, Nigeria", id: "Africa/Lagos"),
        ClockCity(displayName: "Nairobi, Kenya", id: "Africa/Nairobi"),
        ClockCity(displayName: "Riyadh, Saudi Arabia", id: "Asia/Riyadh"),
        ClockCity(displayName: "Tehran, Iran", id: "Asia/Tehran"),

        // Asia
        ClockCity(displayName: "Almaty, Kazakhstan", id: "Asia/Almaty"),
        ClockCity(displayName: "Bangkok, Thailand", id: "Asia/Bangkok"),
        ClockCity(displayName: "Beijing, China", id: "Asia/Shanghai"),
        ClockCity(displayName: "Colombo, Sri Lanka", id: "Asia/Colombo"),
        ClockCity(displayName: "Dhaka, Bangladesh", id: "Asia/Dhaka"),
        ClockCity(displayName: "Hong Kong, China", id: "Asia/Hong_Kong"),
        ClockCity(displayName: "Jakarta, Indonesia", id: "Asia/Jakarta"),
        ClockCity(displayName: "Karachi, Pakistan", id: "Asia/Karachi"),
        ClockCity(displayName: "Kathmandu, Nepal", id: "Asia/Kathmandu"),
        ClockCity(displayName: "Kolkata, India", id: "Asia/Kolkata"),
        ClockCity(displayName: "Kuala Lumpur, Malaysia", id: "Asia/Kuala_Lumpur"),
        ClockCity(displayName: "Manila, Philippines", id: "Asia/Manila"),
        ClockCity(displayName: "Seoul, South Korea", id: "Asia/Seoul"),
        ClockCity(displayName: "Singapore", id: "Asia/Singapore"),
        ClockCity(displayName: "Taipei, Taiwan", id: "Asia/Taipei"),
        ClockCity(displayName: "Tokyo, Japan", id: "Asia/Tokyo"),
        ClockCity(displayName: "Yangon, Myanmar", id: "Asia/Yangon"),

        // Oceania
        ClockCity(displayName: "Auckland, New Zealand", id: "Pacific/Auckland"),
        ClockCity(displayName: "Brisbane, Australia", id: "Australia/Brisbane"),
        ClockCity(displayName: "Melbourne, Australia", id: "Australia/Melbourne"),
        ClockCity(displayName: "Perth, Australia", id: "Australia/Perth"),
        ClockCity(displayName: "Sydney, Australia", id: "Australia/Sydney"),

        // Reference
        ClockCity(displayName: "UTC", id: "UTC"),
    ]
}
