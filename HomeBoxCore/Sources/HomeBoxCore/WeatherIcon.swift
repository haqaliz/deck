import Foundation

// MARK: - WW weather code → SF Symbol

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
