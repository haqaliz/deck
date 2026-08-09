import Foundation

// MARK: - Server JSON shapes (opencode serve)
//
// Mirrors the OpenAPI types: /session returns Session[], /session/{id}/message
// returns { info: Message, parts: Part[] }[]. Only assistant messages carry
// cost/tokens; user messages are ignored.

public struct RemoteTime: Codable, Equatable {
    public let created: Double
    public let updated: Double

    public init(created: Double, updated: Double) {
        self.created = created
        self.updated = updated
    }
}

public struct RemoteSession: Codable, Equatable {
    public let id: String
    public let time: RemoteTime

    public init(id: String, time: RemoteTime) {
        self.id = id
        self.time = time
    }
}

public struct RemoteMessageTime: Codable, Equatable {
    public let created: Double

    public init(created: Double) {
        self.created = created
    }
}

public struct RemoteCache: Codable, Equatable {
    public let read: Double
    public let write: Double

    public init(read: Double, write: Double) {
        self.read = read
        self.write = write
    }
}

public struct RemoteTokens: Codable, Equatable {
    public let input: Double
    public let output: Double
    public let cache: RemoteCache

    public init(input: Double, output: Double, cache: RemoteCache) {
        self.input = input
        self.output = output
        self.cache = cache
    }
}

public struct RemoteMessage: Codable, Equatable {
    public let id: String
    public let sessionID: String
    public let role: String
    public let time: RemoteMessageTime
    public let modelID: String?
    public let providerID: String?
    public let cost: Double?
    public let tokens: RemoteTokens?

    public init(
        id: String,
        sessionID: String,
        role: String,
        time: RemoteMessageTime,
        modelID: String?,
        providerID: String?,
        cost: Double?,
        tokens: RemoteTokens?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.time = time
        self.modelID = modelID
        self.providerID = providerID
        self.cost = cost
        self.tokens = tokens
    }
}

public struct RemoteMessageEnvelope: Codable, Equatable {
    public let info: RemoteMessage

    public init(info: RemoteMessage) {
        self.info = info
    }
}

// MARK: - Aggregation

public enum RemoteMetrics {
    private static let daySeconds = 86_400.0
    private static let sessionWindow: TimeInterval = 14 * daySeconds
    private static let messageWindow: TimeInterval = 13 * daySeconds
    private static let todayWindow: TimeInterval = daySeconds

    /// Aggregates server sessions + messages into widget metrics.
    ///
    /// Mirrors the local SQL queries:
    /// - sessions must have been updated within the last 14 days;
    /// - only assistant messages with `time.created` within the last 13 days
    ///   are counted; "today" = last 24h;
    /// - day buckets use UTC (matches SQL `date(time_created/1000,'unixepoch')`).
    ///
    /// Note: local `today.sessions` counts sessions *created* in 24h; remote
    /// counts sessions with ≥1 counted message in the window (semantic drift,
    /// documented in prd.md §6).
    public static func aggregate(
        sessions: [RemoteSession],
        messages: [RemoteMessage],
        now: Date
    ) -> OpenCodeMetrics {
        let nowMilliseconds = now.timeIntervalSince1970 * 1000
        let sessionCutoff = nowMilliseconds - sessionWindow * 1000
        let messageCutoff = nowMilliseconds - messageWindow * 1000
        let todayCutoff = nowMilliseconds - todayWindow * 1000

        let activeSessionIDs = Set(sessions
            .filter { $0.time.updated >= sessionCutoff }
            .map(\.id))

        var metrics = OpenCodeMetrics()
        var dayTotals: [String: (input: Int64, output: Int64)] = [:]
        var modelTotals: [String: (cost: Double, input: Int64, output: Int64)] = [:]
        var todaySessionIDs = Set<String>()

        for message in messages {
            guard
                activeSessionIDs.contains(message.sessionID),
                message.role == "assistant",
                message.time.created >= messageCutoff
            else { continue }

            let input = Int64(message.tokens?.input ?? 0)
            let output = Int64(message.tokens?.output ?? 0)
            let cacheRead = Int64(message.tokens?.cache.read ?? 0)
            let cacheWrite = Int64(message.tokens?.cache.write ?? 0)
            let cost = message.cost ?? 0

            metrics.messages += 1
            metrics.input += input
            metrics.output += output
            metrics.cacheRead += cacheRead
            metrics.cacheWrite += cacheWrite
            metrics.cost += cost

            let day = utcDayString(from: message.time.created)
            dayTotals[day, default: (0, 0)].input += input
            dayTotals[day, default: (0, 0)].output += output

            let modelKey = modelKey(for: message)
            modelTotals[modelKey, default: (0, 0, 0)].cost += cost
            modelTotals[modelKey, default: (0, 0, 0)].input += input
            modelTotals[modelKey, default: (0, 0, 0)].output += output

            if message.time.created >= todayCutoff {
                metrics.todayInput += input
                metrics.todayOutput += output
                metrics.todayCost += cost
                todaySessionIDs.insert(message.sessionID)
            }
        }

        metrics.sessions = Set(messages
            .filter { activeSessionIDs.contains($0.sessionID) && $0.time.created >= messageCutoff }
            .map(\.sessionID)).count
        metrics.todaySessions = todaySessionIDs.count
        metrics.cost = (metrics.cost * 10_000).rounded() / 10_000

        metrics.daily = dayTotals.keys.sorted().compactMap { day in
            guard let totals = dayTotals[day] else { return nil }
            return DayUsage(day: day, input: totals.input, output: totals.output)
        }

        metrics.models = modelTotals.keys
            .sorted { modelTotals[$0]!.cost > modelTotals[$1]!.cost }
            .prefix(3)
            .compactMap { key in
                guard let totals = modelTotals[key] else { return nil }
                let parsed = ModelParser.parse(key)
                return ModelUsage(
                    model: key,
                    provider: parsed.provider,
                    modelID: parsed.id,
                    variant: parsed.variant,
                    cost: (totals.cost * 10_000).rounded() / 10_000,
                    input: totals.input,
                    output: totals.output
                )
            }

        return metrics
    }

    private static func modelKey(for message: RemoteMessage) -> String {
        let provider = message.providerID ?? "local"
        let id = message.modelID ?? "unknown"
        return "\(provider)/\(id)"
    }

    private static func utcDayString(from epochMilliseconds: Double) -> String {
        let seconds = Int64(epochMilliseconds / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: Date(timeIntervalSince1970: TimeInterval(seconds))
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
