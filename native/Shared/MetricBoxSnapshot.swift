import Foundation

// MARK: - MetricBox snapshot
//
// One Grafana `/api/ds/query` per tick builds the whole host table; a second
// fetches the container leaderboard; a third is the firing-alert list. The
// widget sandbox has no network, so DeckAgent writes this and the face reads it.
//
// The datasource is discovered from `/api/datasources` (the default Prometheus)
// rather than hard-coded, so a different Grafana URL or a re-created datasource
// still works.

struct MetricHost: Codable, Equatable, Identifiable {
    var host: String
    var cpu: Double? = nil
    var ram: Double? = nil
    var disk: Double? = nil
    /// Seconds since the node exporter last reported. Small is healthy.
    var lastSeenSeconds: Double? = nil
    var uptimeSeconds: Double? = nil
    var gpuPercent: Double? = nil
    var vramPercent: Double? = nil
    var gpuTemperature: Double? = nil
    var cpuWatts: Double? = nil
    var gpuWatts: Double? = nil
    var kwh24h: Double? = nil

    var id: String { host }
    var totalWatts: Double? {
        guard cpuWatts != nil || gpuWatts != nil else { return nil }
        return (cpuWatts ?? 0) + (gpuWatts ?? 0)
    }
}

struct MetricAgent: Codable, Equatable, Identifiable {
    var host: String
    var name: String
    var cpu: Double? = nil
    var ram: Double? = nil
    var vram: Double? = nil
    var gpu: Double? = nil

    var id: String { "\(host)/\(name)" }
    var score: Double { (vram ?? 0) / 1_073_741_824 + (gpu ?? 0) + (cpu ?? 0) / 100 }
}

struct MetricAlert: Codable, Equatable, Identifiable {
    var name: String
    var severity: String
    var summary: String
    var host: String

    var id: String { "\(name)-\(host)" }
}

struct MetricBoxSnapshot: Codable, Equatable {
    var hosts: [MetricHost]
    var agents: [MetricAgent]
    var firingAlerts: [MetricAlert]
    var trendHost: String?
    var trendCPU: [Double]
    var writtenAt: Date
    var note: String?

    init(
        hosts: [MetricHost], agents: [MetricAgent], firingAlerts: [MetricAlert],
        trendHost: String?, trendCPU: [Double], writtenAt: Date, note: String?
    ) {
        self.hosts = hosts
        self.agents = agents
        self.firingAlerts = firingAlerts
        self.trendHost = trendHost
        self.trendCPU = trendCPU
        self.writtenAt = writtenAt
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try c.decodeIfPresent([MetricHost].self, forKey: .hosts) ?? []
        agents = try c.decodeIfPresent([MetricAgent].self, forKey: .agents) ?? []
        firingAlerts = try c.decodeIfPresent([MetricAlert].self, forKey: .firingAlerts) ?? []
        trendHost = try c.decodeIfPresent(String.self, forKey: .trendHost)
        trendCPU = try c.decodeIfPresent([Double].self, forKey: .trendCPU) ?? []
        writtenAt = try c.decodeIfPresent(Date.self, forKey: .writtenAt) ?? Date()
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

enum MetricBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("metricbox.json")
    }

    static func load() -> MetricBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MetricBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: MetricBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}

/// Fleet ordering: a silent machine is the first thing to see, then the
/// busiest. Pure so both the medium and large faces agree.
enum MetricBoxSort {
    static let silentAfter: TimeInterval = 120

    static func worstFirst(_ hosts: [MetricHost], hidden: [String] = []) -> [MetricHost] {
        hosts
            .filter { !hidden.contains($0.host) }
            .sorted { lhs, rhs in
                let lhsSilent = (lhs.lastSeenSeconds ?? 0) > silentAfter
                let rhsSilent = (rhs.lastSeenSeconds ?? 0) > silentAfter
                if lhsSilent != rhsSilent { return lhsSilent }
                if lhsSilent {
                    return (lhs.lastSeenSeconds ?? 0) > (rhs.lastSeenSeconds ?? 0)
                }
                let lhsPressure = max(lhs.cpu ?? 0, lhs.ram ?? 0, lhs.disk ?? 0)
                let rhsPressure = max(rhs.cpu ?? 0, rhs.ram ?? 0, rhs.disk ?? 0)
                if lhsPressure != rhsPressure { return lhsPressure > rhsPressure }
                return lhs.host < rhs.host
            }
    }

    static func monthlyCost(kwh24h: Double?, ratePerKWh: Double) -> Double? {
        guard let kwh24h else { return nil }
        return kwh24h * 30 * ratePerKWh
    }
}

// MARK: - Queries (pure)

enum MetricBoxQuery {
    /// Host labels come from the settings picker, but a hand-edited file is a
    /// trust boundary: only a plain label is allowed into PromQL.
    static func safeHost(_ raw: String) -> String? {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
        guard host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return host
    }

    static let hostExpressions: [(ref: String, expr: String)] = [
        ("A", "100 - avg by (host)(rate(node_cpu_seconds_total{mode=\"idle\"}[2m]))*100"),
        ("B", "100*(1 - node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)"),
        ("C", "100*(1 - node_filesystem_avail_bytes{mountpoint=\"/\"}/node_filesystem_size_bytes{mountpoint=\"/\"})"),
        ("D", "time() - tlast_over_time(up{job=\"node\"}[30d])"),
        ("E", "time() - node_boot_time_seconds"),
        ("F", "max by (host)(nvidia_smi_utilization_gpu_ratio)*100"),
        ("G", "max by (host)(nvidia_smi_memory_used_bytes/nvidia_smi_memory_total_bytes)*100"),
        ("H", "max by (host)(nvidia_smi_temperature_gpu)"),
        ("I", "sum by (host)(rate(node_rapl_package_joules_total[2m]))"),
        ("J", "sum by (host)(nvidia_smi_power_draw_watts)"),
        ("K", "(avg_over_time((sum by (host)(nvidia_smi_power_draw_watts))[24h:5m])*24/1000) + on(host) (sum by (host)(increase(node_rapl_package_joules_total[24h]))/3.6e6)"),
    ]

    static let agentExpressions: [(ref: String, expr: String)] = [
        ("A", "topk(10, sum by (host, name)(rate(container_cpu_usage_seconds_total{name!=\"\"}[2m]))*100)"),
        ("B", "topk(10, sum by (host, name)(container_memory_working_set_bytes{name!=\"\"}))"),
        ("C", "topk(10, sum by (host, container)(gpu_container_memory_used_bytes))"),
        ("D", "topk(10, sum by (host, container)(gpu_container_sm_utilization_percent))"),
    ]

    static func singleHostCPU(host: String) -> String? {
        guard let host = safeHost(host) else { return nil }
        return "100 - avg by (host)(rate(node_cpu_seconds_total{mode=\"idle\",host=\"\(host)\"}[2m]))*100"
    }

    static func body(
        uid: String, expressions: [(ref: String, expr: String)],
        from: Date, to: Date, instant: Bool, maxDataPoints: Int?
    ) -> [String: Any] {
        let queries: [[String: Any]] = expressions.map { item in
            var query: [String: Any] = [
                "refId": item.ref,
                "datasource": ["type": "prometheus", "uid": uid],
                "expr": item.expr,
                "instant": instant,
                "range": !instant,
            ]
            if let maxDataPoints, !instant {
                query["maxDataPoints"] = maxDataPoints
                query["intervalMs"] = max(60_000, Int(
                    to.timeIntervalSince(from) * 1000 / Double(max(1, maxDataPoints))
                ))
            }
            return query
        }
        return [
            "from": String(Int(from.timeIntervalSince1970 * 1000)),
            "to": String(Int(to.timeIntervalSince1970 * 1000)),
            "queries": queries,
        ]
    }
}

// MARK: - Parsers (pure)

struct GrafanaSeries: Equatable {
    var labels: [String: String]
    var values: [Double]
}

enum GrafanaDSQueryParser {
    static func series(_ data: Data, refID: String) -> [GrafanaSeries]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [String: Any],
            let result = results[refID] as? [String: Any]
        else { return nil }
        if let status = result["status"] as? Int, status != 200 { return nil }
        guard let frames = result["frames"] as? [[String: Any]] else { return [] }

        return frames.compactMap { frame in
            guard
                let schema = frame["schema"] as? [String: Any],
                let fields = schema["fields"] as? [[String: Any]],
                let valueField = fields.first(where: { $0["type"] as? String == "number" }),
                let data = frame["data"] as? [String: Any],
                let columns = data["values"] as? [[Any]],
                let values = columns.last
            else { return nil }
            let numbers = values.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard !numbers.isEmpty else { return nil }
            let labels = valueField["labels"] as? [String: String] ?? [:]
            return GrafanaSeries(labels: labels, values: numbers)
        }
    }
}

enum GrafanaDatasourceParser {
    /// The default Prometheus/VictoriaMetrics datasource, or the first one.
    static func prometheusUID(_ data: Data) -> String? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        let prometheus = rows.filter { $0["type"] as? String == "prometheus" }
        let chosen = prometheus.first { $0["isDefault"] as? Bool == true } ?? prometheus.first
        guard let uid = chosen?["uid"] as? String, !uid.isEmpty else { return nil }
        return uid
    }
}

enum GrafanaAlertParser {
    static func firing(_ data: Data) -> [MetricAlert] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return rows.compactMap { row in
            let labels = row["labels"] as? [String: String] ?? [:]
            let annotations = row["annotations"] as? [String: String] ?? [:]
            guard let name = labels["alertname"], !name.isEmpty else { return nil }
            return MetricAlert(
                name: name,
                severity: labels["severity"] ?? "warning",
                summary: annotations["summary"] ?? "",
                host: labels["host"] ?? labels["instance"] ?? ""
            )
        }
    }
}

// MARK: - Loader (host only)

enum MetricBoxLoader {
    static func fetch(
        credential: ResolvedCredential,
        settings: MetricBoxSettings,
        previous: MetricBoxSnapshot?
    ) async throws -> MetricBoxSnapshot {
        guard let base = InfraEndpoint.base(credential.baseURL) else {
            throw InfraProviderError.notConfigured
        }
        guard let datasourcesURL = InfraEndpoint.url(base, "api/datasources") else {
            throw InfraProviderError.notConfigured
        }
        let datasourceData = try await InfraHTTP.get(
            datasourcesURL, token: credential.token, scheme: "Bearer"
        )
        guard let uid = GrafanaDatasourceParser.prometheusUID(datasourceData) else {
            throw InfraProviderError.notConfigured
        }
        guard let queryURL = InfraEndpoint.url(base, "api/ds/query") else {
            throw InfraProviderError.notConfigured
        }

        let now = Date()
        let from = now.addingTimeInterval(-300)
        let instantBody = try encode(
            MetricBoxQuery.body(
                uid: uid, expressions: MetricBoxQuery.hostExpressions,
                from: from, to: now, instant: true, maxDataPoints: nil
            )
        )
        let instantData = try await InfraHTTP.post(
            queryURL, token: credential.token, scheme: "Bearer", body: instantBody
        )

        var hosts: [String: MetricHost] = [:]
        func apply(_ ref: String, _ keyPath: WritableKeyPath<MetricHost, Double?>) {
            for series in GrafanaDSQueryParser.series(instantData, refID: ref) ?? [] {
                guard let host = series.labels["host"], !host.isEmpty,
                      let value = series.values.last else { continue }
                var row = hosts[host] ?? MetricHost(host: host)
                row[keyPath: keyPath] = value
                hosts[host] = row
            }
        }
        apply("A", \.cpu)
        apply("B", \.ram)
        apply("C", \.disk)
        apply("D", \.lastSeenSeconds)
        apply("E", \.uptimeSeconds)
        apply("F", \.gpuPercent)
        apply("G", \.vramPercent)
        apply("H", \.gpuTemperature)
        apply("I", \.cpuWatts)
        apply("J", \.gpuWatts)
        apply("K", \.kwh24h)

        guard !hosts.isEmpty else { throw InfraProviderError.invalidPayload }

        var note: String?
        var agents: [MetricAgent] = []
        var alerts: [MetricAlert] = []

        let agentBody = try encode(
            MetricBoxQuery.body(
                uid: uid, expressions: MetricBoxQuery.agentExpressions,
                from: from, to: now, instant: true, maxDataPoints: nil
            )
        )
        if let agentData = try? await InfraHTTP.post(
            queryURL, token: credential.token, scheme: "Bearer", body: agentBody
        ) {
            agents = parseAgents(agentData)
        } else {
            note = "top agents unavailable"
        }

        if let alertsURL = InfraEndpoint.url(
            base, "api/alertmanager/grafana/api/v2/alerts?active=true"
        ), let alertData = try? await InfraHTTP.get(
            alertsURL, token: credential.token, scheme: "Bearer"
        ) {
            alerts = GrafanaAlertParser.firing(alertData)
        }

        var trendHost: String?
        var trendCPU: [Double] = []
        if settings.face == .singleHost, let host = MetricBoxQuery.safeHost(settings.host),
           let expr = MetricBoxQuery.singleHostCPU(host: host) {
            let trendFrom = now.addingTimeInterval(-Double(settings.largeWindowMinutes) * 60)
            let trendBody = try encode(
                MetricBoxQuery.body(
                    uid: uid, expressions: [("A", expr)],
                    from: trendFrom, to: now, instant: false, maxDataPoints: 24
                )
            )
            if let trendData = try? await InfraHTTP.post(
                queryURL, token: credential.token, scheme: "Bearer", body: trendBody
            ) {
                trendCPU = GrafanaDSQueryParser.series(trendData, refID: "A")?
                    .first?.values ?? []
                trendHost = host
            }
        }

        return MetricBoxSnapshot(
            hosts: hosts.values.sorted { $0.host < $1.host },
            agents: agents,
            firingAlerts: alerts,
            trendHost: trendHost,
            trendCPU: trendCPU,
            writtenAt: now,
            note: note
        )
    }

    private static func parseAgents(_ data: Data) -> [MetricAgent] {
        var agents: [String: MetricAgent] = [:]
        func apply(_ ref: String, _ keyPath: WritableKeyPath<MetricAgent, Double?>) {
            for series in GrafanaDSQueryParser.series(data, refID: ref) ?? [] {
                guard let host = series.labels["host"], !host.isEmpty else { continue }
                let name = series.labels["name"] ?? series.labels["container"] ?? ""
                guard !name.isEmpty, let value = series.values.last else { continue }
                let key = "\(host)/\(name)"
                var row = agents[key] ?? MetricAgent(host: host, name: name)
                row[keyPath: keyPath] = value
                agents[key] = row
            }
        }
        apply("A", \.cpu)
        apply("B", \.ram)
        apply("C", \.vram)
        apply("D", \.gpu)
        return agents.values.sorted { $0.score > $1.score }.prefix(10).map { $0 }
    }

    private static func encode(_ body: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(body) else {
            throw InfraProviderError.invalidPayload
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
}
