import Foundation

// MARK: - Remote opencode metrics (host side)
//
// Compact port of the window OpenBox's remote mode: fetch /session (and
// per-session messages when the server lacks session-level usage) from an
// `opencode serve` instance using HTTP basic auth, then aggregate into an
// OpenCodeSnapshot for the widget.

enum RemoteOpenCodeLoader {
    enum RemoteError: Error {
        case invalidURL
        case unauthorized
        case serverError(Int)
        case transport(String)
    }

    static func load(serverURL: String, token: String) async throws -> OpenCodeSnapshot {
        let base = try normalizedBase(serverURL)
        let auth = "Basic " + Data("opencode:\(token)".utf8).base64EncodedString()

        let sessions: [RemoteSession] = try await get(base, auth, path: "/session")
        let now = Date()
        let sessionCutoff = now.timeIntervalSince1970 * 1000 - 14 * 86_400 * 1000

        if sessions.contains(where: { $0.cost != nil || $0.tokens != nil }) {
            return aggregate(sessions: sessions, now: now)
        }

        var messages: [RemoteMessage] = []
        for remoteSession in sessions where remoteSession.time.updated >= sessionCutoff {
            let envelopes: [RemoteMessageEnvelope] = try await get(
                base, auth, path: "/session/\(remoteSession.id)/message"
            )
            messages.append(contentsOf: envelopes.map(\.info))
        }
        return aggregate(sessions: sessions, messages: messages, now: now)
    }

    // MARK: - Server JSON shapes

    private struct RemoteTime: Codable {
        let created: Double
        let updated: Double
    }

    private struct RemoteModel: Codable {
        let id: String
        let providerID: String?
        let variant: String?
    }

    private struct RemoteSession: Codable {
        let id: String
        let time: RemoteTime
        let cost: Double?
        let tokens: RemoteTokens?
        let model: RemoteModel?
    }

    private struct RemoteCache: Codable {
        let read: Double
        let write: Double
    }

    private struct RemoteTokens: Codable {
        let input: Double
        let output: Double
        let cache: RemoteCache
    }

    private struct RemoteMessageTime: Codable {
        let created: Double
    }

    private struct RemoteMessage: Codable {
        let id: String
        let sessionID: String
        let role: String
        let time: RemoteMessageTime
        let modelID: String?
        let providerID: String?
        let cost: Double?
        let tokens: RemoteTokens?
    }

    private struct RemoteMessageEnvelope: Codable {
        let info: RemoteMessage
    }

    // MARK: - Aggregation (mirrors the window's RemoteMetrics)

    private static let daySeconds = 86_400.0
    private static let sessionWindow: TimeInterval = 14 * daySeconds
    private static let messageWindow: TimeInterval = 13 * daySeconds
    private static let todayWindow: TimeInterval = daySeconds

    private static func aggregate(sessions: [RemoteSession], now: Date) -> OpenCodeSnapshot {
        let nowMilliseconds = now.timeIntervalSince1970 * 1000
        let sessionCutoff = nowMilliseconds - sessionWindow * 1000
        let todayCutoff = nowMilliseconds - todayWindow * 1000

        var totalInput: Int64 = 0
        var totalOutput: Int64 = 0
        var totalCost = 0.0
        var dayTotals: [String: (Int64, Int64)] = [:]
        var modelTotals: [String: (cost: Double, input: Int64, output: Int64)] = [:]
        var todaySessionIDs = Set<String>()

        for remoteSession in sessions {
            guard remoteSession.time.updated >= sessionCutoff else { continue }
            let input = Int64(remoteSession.tokens?.input ?? 0)
            let output = Int64(remoteSession.tokens?.output ?? 0)
            let cost = remoteSession.cost ?? 0

            totalInput += input
            totalOutput += output
            totalCost += cost

            let day = utcDayString(from: remoteSession.time.created)
            dayTotals[day, default: (0, 0)].0 += input
            dayTotals[day, default: (0, 0)].1 += output

            let key = modelKey(for: remoteSession.model)
            let totals = modelTotals[key] ?? (0, 0, 0)
            modelTotals[key] = (totals.cost + cost, totals.input + input, totals.output + output)

            if remoteSession.time.created >= todayCutoff {
                todaySessionIDs.insert(remoteSession.id)
            }
        }

        let todayInput = sumToday(sessions: sessions, cutoff: todayCutoff, \.tokens, \.time.created, keyPath: \.input)
        let todayOutput = sumToday(sessions: sessions, cutoff: todayCutoff, \.tokens, \.time.created, keyPath: \.output)
        let todayCost = sessions
            .filter { $0.time.created >= todayCutoff }
            .reduce(0.0) { $0 + ($1.cost ?? 0) }

        return OpenCodeSnapshot(
            writtenAt: now,
            sessions: Int64(todaySessionIDs.count),
            input: todayInput,
            output: todayOutput,
            cost: round4(todayCost),
            daily: daily(from: dayTotals),
            models: models(from: modelTotals),
            tools: [],
            totalInput: totalInput,
            totalOutput: totalOutput,
            totalCost: round4(totalCost)
        )
    }

    private static func aggregate(sessions: [RemoteSession], messages: [RemoteMessage], now: Date) -> OpenCodeSnapshot {
        let nowMilliseconds = now.timeIntervalSince1970 * 1000
        let sessionCutoff = nowMilliseconds - sessionWindow * 1000
        let messageCutoff = nowMilliseconds - messageWindow * 1000
        let todayCutoff = nowMilliseconds - todayWindow * 1000

        let activeSessionIDs = Set(sessions
            .filter { $0.time.updated >= sessionCutoff }
            .map(\.id))

        var totalInput: Int64 = 0
        var totalOutput: Int64 = 0
        var totalCost = 0.0
        var dayTotals: [String: (Int64, Int64)] = [:]
        var modelTotals: [String: (cost: Double, input: Int64, output: Int64)] = [:]
        var todaySessionIDs = Set<String>()
        var countedSessionIDs = Set<String>()

        for message in messages where message.role == "assistant" && message.time.created >= messageCutoff {
            guard activeSessionIDs.contains(message.sessionID) else { continue }
            let input = Int64(message.tokens?.input ?? 0)
            let output = Int64(message.tokens?.output ?? 0)
            let cost = message.cost ?? 0

            countedSessionIDs.insert(message.sessionID)
            totalInput += input
            totalOutput += output
            totalCost += cost

            let day = utcDayString(from: message.time.created)
            dayTotals[day, default: (0, 0)].0 += input
            dayTotals[day, default: (0, 0)].1 += output

            let key = "\(message.providerID ?? "local")/\(message.modelID ?? "unknown")"
            let totals = modelTotals[key] ?? (0, 0, 0)
            modelTotals[key] = (totals.cost + cost, totals.input + input, totals.output + output)

            if message.time.created >= todayCutoff {
                todaySessionIDs.insert(message.sessionID)
            }
        }

        let todayInput = messages
            .filter { activeSessionIDs.contains($0.sessionID) && $0.time.created >= todayCutoff }
            .reduce(Int64(0)) { $0 + Int64($1.tokens?.input ?? 0) }
        let todayOutput = messages
            .filter { activeSessionIDs.contains($0.sessionID) && $0.time.created >= todayCutoff }
            .reduce(Int64(0)) { $0 + Int64($1.tokens?.output ?? 0) }
        let todayCost = messages
            .filter { activeSessionIDs.contains($0.sessionID) && $0.time.created >= todayCutoff }
            .reduce(0.0) { $0 + ($1.cost ?? 0) }

        return OpenCodeSnapshot(
            writtenAt: now,
            sessions: Int64(countedSessionIDs.count),
            input: todayInput,
            output: todayOutput,
            cost: round4(todayCost),
            daily: daily(from: dayTotals),
            models: models(from: modelTotals),
            tools: [],
            totalInput: totalInput,
            totalOutput: totalOutput,
            totalCost: round4(totalCost)
        )
    }

    // MARK: - Helpers

    private static func sumToday(
        sessions: [RemoteSession],
        cutoff: Double,
        _ tokens: KeyPath<RemoteSession, RemoteTokens?>,
        _ time: KeyPath<RemoteSession, Double>,
        keyPath: KeyPath<RemoteTokens, Double>
    ) -> Int64 {
        sessions
            .filter { $0.time.created >= cutoff }
            .reduce(Int64(0)) { $0 + Int64($1.tokens?[keyPath: keyPath] ?? 0) }
    }

    private static func modelKey(for model: RemoteModel?) -> String {
        guard let model else { return "local/unknown" }
        return "\(model.providerID ?? "local")/\(model.id)"
    }

    private static func daily(from dayTotals: [String: (Int64, Int64)]) -> [OpenCodeSnapshot.Day] {
        dayTotals.keys.sorted().compactMap { day in
            guard let totals = dayTotals[day] else { return nil }
            return OpenCodeSnapshot.Day(day: day, input: totals.0, output: totals.1)
        }
    }

    private static func models(from modelTotals: [String: (cost: Double, input: Int64, output: Int64)]) -> [OpenCodeSnapshot.Model] {
        modelTotals.keys
            .sorted { modelTotals[$0]!.cost > modelTotals[$1]!.cost }
            .prefix(3)
            .compactMap { key in
                guard let totals = modelTotals[key] else { return nil }
                return OpenCodeSnapshot.Model(
                    model: key,
                    cost: round4(totals.cost),
                    input: totals.input,
                    output: totals.output
                )
            }
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

    private static func round4(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    // MARK: - Transport

    private static func normalizedBase(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty else {
            throw RemoteError.invalidURL
        }
        return url
    }

    private static func get<T: Decodable>(_ base: URL, _ auth: String, path: String) async throws -> T {
        guard let url = URL(string: base.absoluteString + path) else {
            throw RemoteError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RemoteError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteError.transport("Not an HTTP response")
        }
        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw RemoteError.transport("Invalid JSON: \(error.localizedDescription)")
            }
        case 401, 403:
            throw RemoteError.unauthorized
        default:
            throw RemoteError.serverError(http.statusCode)
        }
    }
}
