import Foundation

// MARK: - HomeBox snapshot
//
// wttr.in is a network fetch — the widget sandbox has no network entitlement —
// so the host agent fetches weather every 60s and writes this snapshot into the
// container. The HomeBox widget renders it; the world-clock rows need no data
// at all (local TimeZone identifiers).

struct HomeBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    var location: String
    var country: String
    var condition: WeatherCondition
    /// Up to 3 forecast days, oldest first.
    var days: [WeatherDay]
}

struct WeatherCondition: Codable, Equatable {
    /// WW weather code (113 clear, 116 partly cloudy, …); nil when absent.
    var code: Int?
    var desc: String
    var tempC: Double?
    var tempF: Double?
    var feelsLikeC: Double?
    var feelsLikeF: Double?
    var humidity: Double?
    var windDir: String
    var windKmph: Double?
}

struct WeatherDay: Codable, Equatable {
    /// Calendar day at the location, "yyyy-MM-dd".
    var date: String
    var maxTempC: Double?
    var maxTempF: Double?
    var minTempC: Double?
    var minTempF: Double?
    var desc: String
}

enum HomeBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("weather.json")
    }

    static func load() -> HomeBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(HomeBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: HomeBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}

// MARK: - wttr.in fetch (host/agent only — unsandboxed)

enum HostWeatherLoader {
    enum WeatherError: Error {
        case invalidLocation
        case serverError(Int)
        case transport(String)
        case invalidPayload
    }

    /// Fetches current conditions + 3-day forecast for `location`
    /// (free-text city or "lat,lon"; empty → wttr.in geolocates).
    static func fetch(location: String) async throws -> HomeBoxSnapshot {
        let url = try makeURL(location: location)

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WeatherError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.transport("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            throw WeatherError.serverError(http.statusCode)
        }
        guard let parsed = WttrParser.parse(data) else {
            throw WeatherError.invalidPayload
        }
        return HomeBoxSnapshot(
            writtenAt: Date(),
            location: parsed.location,
            country: parsed.country,
            condition: parsed.current,
            days: parsed.days
        )
    }

    private static func makeURL(location: String) throws -> URL {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let encoded else { throw WeatherError.invalidLocation }
        let base = "https://wttr.in"
        let path = encoded.isEmpty ? "" : "/\(encoded)"
        guard let url = URL(string: base + path + "?format=j1") else {
            throw WeatherError.invalidLocation
        }
        return url
    }
}

// MARK: - wttr.in j1 parser
//
// Contract notes (verified against the live payload): every numeric field is a
// String; weatherDesc values carry trailing whitespace; weather[] has 3 days.

struct ParsedWeather: Equatable {
    /// Resolved place name (nearest_area), or "" when unknown.
    var location: String
    var country: String
    var current: WeatherCondition
    /// Up to 3 forecast days, oldest first.
    var days: [WeatherDay]
}

enum WttrParser {
    static func parse(_ data: Data) -> ParsedWeather? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let currentList = json["current_condition"] as? [[String: Any]],
            let currentEntry = currentList.first
        else { return nil }

        let current = condition(from: currentEntry)

        let area = (json["nearest_area"] as? [[String: Any]])?.first
        let location = stringListValue(area?["areaName"], index: 0) ?? ""
        let country = stringListValue(area?["country"], index: 0) ?? ""

        let days = (json["weather"] as? [[String: Any]])?.map(day(from:)) ?? []

        return ParsedWeather(
            location: location,
            country: country,
            current: current,
            days: days
        )
    }

    private static func condition(from entry: [String: Any]) -> WeatherCondition {
        WeatherCondition(
            code: intValue(entry["weatherCode"]),
            desc: trimmedString(entry["weatherDesc"]),
            tempC: doubleValue(entry["temp_C"]),
            tempF: doubleValue(entry["temp_F"]),
            feelsLikeC: doubleValue(entry["FeelsLikeC"]),
            feelsLikeF: doubleValue(entry["FeelsLikeF"]),
            humidity: doubleValue(entry["humidity"]),
            windDir: trimmedString(entry["winddir16Point"]),
            windKmph: doubleValue(entry["windspeedKmph"])
        )
    }

    private static func day(from entry: [String: Any]) -> WeatherDay {
        WeatherDay(
            date: (entry["date"] as? String) ?? "",
            maxTempC: doubleValue(entry["maxtempC"]),
            maxTempF: doubleValue(entry["maxtempF"]),
            minTempC: doubleValue(entry["mintempC"]),
            minTempF: doubleValue(entry["mintempF"]),
            desc: trimmedString(entry["weatherDesc"])
        )
    }

    /// The j1 shape wraps desc values in a list: weatherDesc[0].value.
    private static func trimmedString(_ raw: Any?) -> String {
        guard let list = raw as? [[String: Any]], let value = list.first?["value"] as? String else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringListValue(_ raw: Any?, index: Int) -> String? {
        guard let list = raw as? [[String: Any]], list.indices.contains(index) else { return nil }
        return list[index]["value"] as? String
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        guard let string = raw as? String, !string.isEmpty else { return nil }
        return Double(string)
    }

    private static func intValue(_ raw: Any?) -> Int? {
        guard let string = raw as? String, !string.isEmpty else { return nil }
        return Int(string)
    }
}

// MARK: - WW weather code → SF Symbol (used by the widget face)

enum WeatherIcon {
    /// SF Symbol for a World Weather Online code; "cloud" for unknown/nil.
    static func symbol(for code: Int?) -> String {
        guard let code else { return "cloud" }
        return mapping[code] ?? "cloud"
    }

    private static let mapping: [Int: String] = [
        113: "sun.max",
        116: "cloud.sun",
        119: "cloud",
        122: "cloud.fill",
        143: "cloud.fog",
        176: "cloud.drizzle",
        179: "cloud.snow",
        182: "cloud.sleet",
        185: "cloud.sleet",
        200: "cloud.bolt.rain",
        227: "wind.snow",
        230: "cloud.snow",
        248: "cloud.fog",
        260: "cloud.fog.fill",
        263: "cloud.drizzle",
        266: "cloud.drizzle",
        281: "cloud.drizzle.fill",
        284: "cloud.drizzle.fill",
        293: "cloud.drizzle",
        296: "cloud.drizzle",
        299: "cloud.rain",
        302: "cloud.rain",
        305: "cloud.rain.fill",
        308: "cloud.heavyrain",
        311: "cloud.hail",
        314: "cloud.hail",
        317: "cloud.sleet",
        320: "cloud.sleet",
        323: "cloud.snow",
        326: "cloud.snow",
        329: "cloud.snow.fill",
        332: "cloud.snow.fill",
        335: "cloud.snow.fill",
        338: "cloud.snow.fill",
        350: "cloud.hail",
        353: "cloud.sun.rain",
        356: "cloud.sun.rain.fill",
        359: "cloud.rain.fill",
        362: "cloud.sun.rain",
        365: "cloud.sun.rain",
        368: "cloud.sun.snow",
        371: "cloud.sun.snow",
        374: "cloud.hail",
        377: "cloud.hail",
        386: "cloud.bolt.rain",
        389: "cloud.bolt.rain.fill",
        392: "cloud.bolt.snow",
        395: "cloud.bolt.snow.fill",
    ]
}

// MARK: - World clock rows (local-only, zero fetch — used by the widget face)

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
