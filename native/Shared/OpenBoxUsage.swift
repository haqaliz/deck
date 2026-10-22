import Foundation

// MARK: - OpenBox Go usage (real Console meters)
//
// The Console Go page renders `GET /console/api/go/status`. These are the same
// meters the dashboard shows — not a local re-derivation from session costs,
// which buckets a whole session at its creation time and disagrees with the
// server's rolling accounting.
//
// Monetary fields arrive as decimal strings in microcents: 100,000,000 = $1.

struct OpenBoxUsage: Codable, Equatable {
    var writtenAt: Date
    var product: String
    var cancelAtPeriodEnd: Bool
    var fiveHour: Meter?
    var week: Meter?
    var month: Meter?

    var hasMeters: Bool {
        fiveHour != nil || week != nil || month != nil
    }

    /// "GO" / "GO PLUS" for the section header.
    var productLabel: String {
        product == "go-plus" ? "GO PLUS" : "GO"
    }
}

extension OpenBoxUsage {
    struct Meter: Codable, Equatable {
        var usedMicroCents: Int64
        var limitMicroCents: Int64
        var resetsAt: Date?

        private enum CodingKeys: String, CodingKey {
            case usedMicroCents, limitMicroCents, resetsAt
        }

        init(usedMicroCents: Int64, limitMicroCents: Int64, resetsAt: Date?) {
            self.usedMicroCents = usedMicroCents
            self.limitMicroCents = limitMicroCents
            self.resetsAt = resetsAt
        }

        /// The Console serialises BigInt fields as strings; accept a number too
        /// so a serialisation change cannot blank the section.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            usedMicroCents = try Self.microCents(c, .usedMicroCents)
            limitMicroCents = try Self.microCents(c, .limitMicroCents)
            resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
        }

        /// 0...∞; the view clamps the bar, the badge says "100%+".
        var percent: Double {
            guard limitMicroCents > 0 else { return 0 }
            return Double(usedMicroCents) / Double(limitMicroCents) * 100
        }

        var percentText: String {
            let rounded = Int(percent.rounded())
            if percent >= 100 { return "100%+" }
            // The Console prints ">99%" for 99.5–99.9 rather than 100%.
            if rounded >= 100 { return ">99%" }
            return "\(rounded)%"
        }

        var remainingMicroCents: Int64 {
            max(limitMicroCents - usedMicroCents, 0)
        }

        private static func microCents(
            _ c: KeyedDecodingContainer<Meter.CodingKeys>, _ key: Meter.CodingKeys
        ) throws -> Int64 {
            if let text = try? c.decode(String.self, forKey: key), let value = Int64(text) {
                return value
            }
            if let value = try? c.decode(Int64.self, forKey: key) { return value }
            if let value = try? c.decode(Double.self, forKey: key) { return Int64(value) }
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c, debugDescription: "Expected microcents as a string or number"
            )
        }
    }
}

enum OpenBoxUsageFormatters {
    /// "$0.07", "$8.50", "$12" — integer limits stay short in the row.
    static func money(_ microCents: Int64) -> String {
        let value = Double(microCents) / 100_000_000
        if value >= 1, value.rounded() == value {
            return String(format: "$%.0f", value)
        }
        return String(format: "$%.2f", value)
    }
}

enum OpenBoxUsageStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("openbox-usage.json")
    }

    static func load() -> OpenBoxUsage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(OpenBoxUsage.self, from: data)
    }

    static func save(_ usage: OpenBoxUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }

    /// No file means the section hides — used when the feature is off or the
    /// subscription ended, never on a transient fetch failure.
    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
