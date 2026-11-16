import Foundation

// MARK: - LogBox snapshot
//
// Manifold logs are a network fetch — the widget sandbox has no network
// entitlement — so DeckAgent queries Elastic every 60s and writes this
// snapshot. The widget renders it; the API key is never sent anywhere but the
// account's own base URL.
//
// Two cadences. Counts and the last error are cheap (~10ms) and refresh every
// tick. The 24h trend is ~4.4s, so it refreshes at most every 15 minutes and is
// reused in between (`slowUpdatedAt`).

struct LogBoxPoint: Codable, Equatable {
    var at: Date
    var count: Int
}

struct LogBoxCount: Codable, Equatable {
    var name: String
    var count: Int
}

struct LogBoxLine: Codable, Equatable {
    var at: Date
    var service: String
    var level: String
    var message: String
}

struct LogBoxSnapshot: Codable, Equatable {
    var accountID: String
    var environment: String
    var writtenAt: Date
    /// When the 24h block below was last refreshed. Nil means it never was.
    var slowUpdatedAt: Date?
    var smallMinutes: Int
    var largeMinutes: Int
    var errorSmall: Int
    var warnSmall: Int
    var errorLarge: Int
    var warnLarge: Int
    var trend: [LogBoxPoint]
    var services: [LogBoxCount]
    var templates: [LogBoxCount]
    var lastErrorAt: Date?
    /// The newest error/critical documents, capped at five. Present only when
    /// the user opted into raw text; templates mode stores none.
    var recent: [LogBoxLine]
    var note: String?

    init(
        accountID: String, environment: String, writtenAt: Date,
        slowUpdatedAt: Date?, smallMinutes: Int, largeMinutes: Int,
        errorSmall: Int, warnSmall: Int, errorLarge: Int, warnLarge: Int,
        trend: [LogBoxPoint], services: [LogBoxCount], templates: [LogBoxCount],
        lastErrorAt: Date?, recent: [LogBoxLine], note: String?
    ) {
        self.accountID = accountID
        self.environment = environment
        self.writtenAt = writtenAt
        self.slowUpdatedAt = slowUpdatedAt
        self.smallMinutes = smallMinutes
        self.largeMinutes = largeMinutes
        self.errorSmall = errorSmall
        self.warnSmall = warnSmall
        self.errorLarge = errorLarge
        self.warnLarge = warnLarge
        self.trend = trend
        self.services = services
        self.templates = templates
        self.lastErrorAt = lastErrorAt
        self.recent = recent
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID) ?? ""
        environment = try c.decodeIfPresent(String.self, forKey: .environment)
            ?? LogEnvironment.prd.rawValue
        writtenAt = try c.decodeIfPresent(Date.self, forKey: .writtenAt) ?? Date()
        slowUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .slowUpdatedAt)
        smallMinutes = try c.decodeIfPresent(Int.self, forKey: .smallMinutes) ?? 15
        largeMinutes = try c.decodeIfPresent(Int.self, forKey: .largeMinutes) ?? 1440
        errorSmall = try c.decodeIfPresent(Int.self, forKey: .errorSmall) ?? 0
        warnSmall = try c.decodeIfPresent(Int.self, forKey: .warnSmall) ?? 0
        errorLarge = try c.decodeIfPresent(Int.self, forKey: .errorLarge) ?? 0
        warnLarge = try c.decodeIfPresent(Int.self, forKey: .warnLarge) ?? 0
        trend = try c.decodeIfPresent([LogBoxPoint].self, forKey: .trend) ?? []
        services = try c.decodeIfPresent([LogBoxCount].self, forKey: .services) ?? []
        templates = try c.decodeIfPresent([LogBoxCount].self, forKey: .templates) ?? []
        lastErrorAt = try c.decodeIfPresent(Date.self, forKey: .lastErrorAt)
        recent = try c.decodeIfPresent([LogBoxLine].self, forKey: .recent) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

enum LogBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("logbox.json")
    }

    static func load() -> LogBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LogBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: LogBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}

// MARK: - Queries (pure)

enum LogBoxQuery {
    /// One body shape for the fast and the slow query. `trendBucketMinutes`
    /// adds the 24h histogram inside the error-only filter, so the trend counts
    /// errors rather than the error+warn superset the query returns.
    static func searchBody(
        fromMinutes: Int, service: String, trendBucketMinutes: Int?
    ) -> [String: Any] {
        var filters: [[String: Any]] = [
            ["range": ["@timestamp": ["gte": "now-\(fromMinutes)m"]]],
            ["terms": ["log.level": ["error", "critical", "warn"]]],
        ]
        let service = service.trimmingCharacters(in: .whitespacesAndNewlines)
        if !service.isEmpty {
            filters.append(["term": ["service.name": service]])
        }

        var errorAggs: [String: Any] = [
            "services": ["terms": ["field": "service.name", "size": 5]],
            "templates": ["terms": ["field": "manifold.message_template", "size": 5]],
        ]
        if let trendBucketMinutes {
            errorAggs["trend"] = [
                "date_histogram": [
                    "field": "@timestamp",
                    "fixed_interval": "\(max(1, trendBucketMinutes))m",
                ]
            ]
        }

        return [
            "size": 0,
            "track_total_hits": true,
            "query": ["bool": ["filter": filters]],
            "aggs": [
                "error": [
                    "filter": ["terms": ["log.level": ["error", "critical"]]],
                    "aggs": errorAggs,
                ],
                "warn": ["filter": ["term": ["log.level": "warn"]]],
            ],
        ]
    }

    static func lastErrorBody(fromMinutes: Int, service: String) -> [String: Any] {
        var filters: [[String: Any]] = [
            ["range": ["@timestamp": ["gte": "now-\(fromMinutes)m"]]],
            ["terms": ["log.level": ["error", "critical"]]],
        ]
        let service = service.trimmingCharacters(in: .whitespacesAndNewlines)
        if !service.isEmpty {
            filters.append(["term": ["service.name": service]])
        }
        return [
            "size": 5,
            "sort": [["@timestamp": "desc"]],
            "query": ["bool": ["filter": filters]],
            "_source": ["@timestamp", "message", "manifold.message_template", "service", "log"],
        ]
    }

    /// 24h into ~48 bars: enough shape for a medium widget without asking ES
    /// for 288 buckets every 15 minutes.
    static func trendBucketMinutes(forMinutes minutes: Int) -> Int {
        max(5, minutes / 48)
    }
}

// MARK: - Parsers (pure)

enum ElasticLogParser {
    struct Counts: Equatable {
        var error: Int
        var warn: Int
        var services: [LogBoxCount]
        var templates: [LogBoxCount]
        var trend: [LogBoxPoint]
    }

    static func counts(_ data: Data) -> Counts? {
        guard
            let root = json(data),
            let aggs = root["aggregations"] as? [String: Any],
            let error = aggs["error"] as? [String: Any]
        else { return nil }
        let warn = aggs["warn"] as? [String: Any]
        return Counts(
            error: error["doc_count"] as? Int ?? 0,
            warn: warn?["doc_count"] as? Int ?? 0,
            services: buckets(error["services"]),
            templates: buckets(error["templates"]),
            trend: trend(error["trend"])
        )
    }

    static func recent(_ data: Data) -> [LogBoxLine] {
        guard
            let root = json(data),
            let hits = (root["hits"] as? [String: Any])?["hits"] as? [[String: Any]]
        else { return [] }
        return hits.compactMap { hit in
            guard
                let source = hit["_source"] as? [String: Any],
                let at = InfraDate.parse(source["@timestamp"] as? String)
            else { return nil }
            let service = (source["service"] as? [String: Any])?["name"] as? String ?? ""
            let level = (source["log"] as? [String: Any])?["level"] as? String ?? ""
            let message = (source["message"] as? String)
                ?? ((source["manifold"] as? [String: Any])?["message_template"] as? String)
                ?? ""
            return LogBoxLine(at: at, service: service, level: level, message: message)
        }
    }

    private static func buckets(_ value: Any?) -> [LogBoxCount] {
        guard
            let agg = value as? [String: Any],
            let rows = agg["buckets"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let key = row["key"] as? String else { return nil }
            return LogBoxCount(name: key, count: row["doc_count"] as? Int ?? 0)
        }
    }

    private static func trend(_ value: Any?) -> [LogBoxPoint] {
        guard
            let agg = value as? [String: Any],
            let rows = agg["buckets"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let at = InfraDate.parse(row["key_as_string"] as? String) else { return nil }
            return LogBoxPoint(at: at, count: row["doc_count"] as? Int ?? 0)
        }
    }

    private static func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Loader (host only)

enum LogBoxLoader {
    /// The 24h block is heavy; fifteen minutes is the compromise between a
    /// stale trend and paying 4.4s on every tick.
    static let slowRefresh: TimeInterval = 15 * 60

    static func fetch(
        credential: ResolvedCredential,
        settings: LogBoxSettings,
        previous: LogBoxSnapshot?
    ) async throws -> LogBoxSnapshot {
        guard let base = InfraEndpoint.base(credential.baseURL) else {
            throw InfraProviderError.notConfigured
        }
        let index = settings.environment.index
        guard let searchURL = InfraEndpoint.url(base, "\(index)/_search") else {
            throw InfraProviderError.notConfigured
        }

        let fastBody = try encode(
            LogBoxQuery.searchBody(
                fromMinutes: settings.smallWindowMinutes,
                service: settings.service,
                trendBucketMinutes: nil
            )
        )
        let fastData = try await InfraHTTP.post(
            searchURL, token: credential.token, scheme: "ApiKey", body: fastBody
        )
        guard let fast = ElasticLogParser.counts(fastData) else {
            throw InfraProviderError.invalidPayload
        }

        let now = Date()
        let sameTarget = previous?.accountID == credential.id
            && previous?.environment == settings.environment.rawValue
        let slowFresh = sameTarget
            && now.timeIntervalSince(previous?.slowUpdatedAt ?? .distantPast) < slowRefresh

        var slowUpdatedAt = slowFresh ? previous?.slowUpdatedAt : nil
        var errorLarge = slowFresh ? (previous?.errorLarge ?? 0) : 0
        var warnLarge = slowFresh ? (previous?.warnLarge ?? 0) : 0
        var trend = slowFresh ? (previous?.trend ?? []) : []
        var services = slowFresh ? (previous?.services ?? []) : []
        var templates = slowFresh ? (previous?.templates ?? []) : []
        var note: String?

        if !slowFresh {
            do {
                let slowBody = try encode(
                    LogBoxQuery.searchBody(
                        fromMinutes: settings.largeWindowMinutes,
                        service: settings.service,
                        trendBucketMinutes: LogBoxQuery.trendBucketMinutes(
                            forMinutes: settings.largeWindowMinutes
                        )
                    )
                )
                let slowData = try await InfraHTTP.post(
                    searchURL, token: credential.token, scheme: "ApiKey", body: slowBody
                )
                guard let slow = ElasticLogParser.counts(slowData) else {
                    throw InfraProviderError.invalidPayload
                }
                slowUpdatedAt = now
                errorLarge = slow.error
                warnLarge = slow.warn
                trend = slow.trend
                services = slow.services
                templates = slow.templates
            } catch {
                // A failed slow query must not blank a face that has a good
                // fast count. Reuse the previous block when there is one and
                // say so only when there is nothing to show.
                if previous == nil || !sameTarget {
                    note = "24h trend unavailable"
                }
            }
        }

        let lastData = try? await InfraHTTP.post(
            searchURL, token: credential.token, scheme: "ApiKey",
            body: try encode(
                LogBoxQuery.lastErrorBody(
                    fromMinutes: settings.largeWindowMinutes,
                    service: settings.service
                )
            )
        )
        let recent = settings.textMode == .templates
            ? []
            : (lastData.map(ElasticLogParser.recent) ?? (sameTarget ? previous?.recent : nil) ?? [])

        return LogBoxSnapshot(
            accountID: credential.id,
            environment: settings.environment.rawValue,
            writtenAt: now,
            slowUpdatedAt: slowUpdatedAt,
            smallMinutes: settings.smallWindowMinutes,
            largeMinutes: settings.largeWindowMinutes,
            errorSmall: fast.error,
            warnSmall: fast.warn,
            errorLarge: errorLarge,
            warnLarge: warnLarge,
            trend: trend,
            services: services,
            templates: templates,
            lastErrorAt: recent.first?.at ?? (sameTarget ? previous?.lastErrorAt : nil),
            recent: recent,
            note: note
        )
    }

    private static func encode(_ body: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(body) else {
            throw InfraProviderError.invalidPayload
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
}
