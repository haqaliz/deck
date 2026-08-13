import Foundation

// MARK: - Weather models

struct WeatherCondition: Equatable {
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

struct WeatherDay: Equatable {
    /// Calendar day at the location, "yyyy-MM-dd".
    var date: String
    var maxTempC: Double?
    var maxTempF: Double?
    var minTempC: Double?
    var minTempF: Double?
    var desc: String
}

struct ParsedWeather: Equatable {
    /// Resolved place name (nearest_area), or "" when unknown.
    var location: String
    var country: String
    var current: WeatherCondition
    /// Up to 3 forecast days, oldest first.
    var days: [WeatherDay]
}

// MARK: - wttr.in j1 parser
//
// Contract notes (verified against the live payload): every numeric field is a
// String; weatherDesc values carry trailing whitespace; weather[] has 3 days.

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
