import XCTest

/// M11's pure layer: the Elastic/Grafana parsers, the query shapes and the
/// deep links. The network paths are exercised by pressing Verify and by the
/// agent; these tests pin what the bytes mean.
final class InfraParserTests: XCTestCase {

    private func fixture(_ name: String) -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    // MARK: - Elastic

    func testFastCountsReadLevelsServicesAndTemplates() {
        let counts = ElasticLogParser.counts(fixture("logs_fast"))
        XCTAssertEqual(counts?.error, 33)
        XCTAssertEqual(counts?.warn, 36651)
        XCTAssertEqual(counts?.services.first, LogBoxCount(name: "jobrunner", count: 32))
        XCTAssertEqual(counts?.templates.first?.count, 24)
        XCTAssertEqual(counts?.trend, [])
    }

    func testSlowCountsReadTheErrorOnlyTrend() {
        let counts = ElasticLogParser.counts(fixture("logs_slow"))
        XCTAssertEqual(counts?.error, 5077)
        XCTAssertEqual(counts?.warn, 1876801)
        XCTAssertEqual(counts?.trend.count, 3)
        XCTAssertEqual(counts?.trend.map(\.count), [12, 0, 7])
        XCTAssertNotNil(counts?.trend.first?.at)
    }

    func testRecentErrorsCarryTimestampServiceLevelAndMessage() {
        let lines = ElasticLogParser.recent(fixture("logs_last"))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.service, "jobrunner")
        XCTAssertEqual(lines.first?.level, "error")
        XCTAssertEqual(lines.first?.message, "Exception in executing GetRawGpsAsync Method")
        XCTAssertNotNil(lines.first?.at)
    }

    func testHealthAndCountProbes() {
        let health = ElasticHealthParser.parse(fixture("elastic_health"))
        XCTAssertEqual(health?.cluster, "manifold-logs")
        XCTAssertEqual(health?.status, "green")
        XCTAssertEqual(ElasticCountParser.parse(fixture("elastic_count")), 10_581_995)
    }

    // MARK: - Grafana

    func testQueryFramesBecomeLabelledSeries() {
        let series = GrafanaDSQueryParser.series(fixture("grafana_query"), refID: "A")
        XCTAssertEqual(series?.count, 2)
        XCTAssertEqual(series?.first?.labels["host"], "x201")
        XCTAssertEqual(series?.first?.values, [34.1])
        XCTAssertEqual(series?.last?.values, [71.4])
    }

    func testAMissingRefIDIsNilNotAnEmptySuccess() {
        XCTAssertNil(GrafanaDSQueryParser.series(fixture("grafana_query"), refID: "Z"))
    }

    func testDatasourceDiscoveryPrefersTheDefaultPrometheus() {
        XCTAssertEqual(
            GrafanaDatasourceParser.prometheusUID(fixture("grafana_datasources")),
            "P4169E866C3094E38"
        )
    }

    func testFiringAlertsCarryNameSeverityAndHost() {
        let alerts = GrafanaAlertParser.firing(fixture("grafana_alerts"))
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.name, "House machine not reporting")
        XCTAssertEqual(alerts.first?.severity, "warning")
        XCTAssertEqual(alerts.first?.host, "x204")
    }

    // MARK: - Queries

    func testTheFastLogQueryHasNoTrendAndNoServiceFilterWhenUnset() {
        let body = LogBoxQuery.searchBody(fromMinutes: 15, service: "", trendBucketMinutes: nil)
        let aggs = body["aggs"] as? [String: Any]
        let error = aggs?["error"] as? [String: Any]
        XCTAssertNil((error?["aggs"] as? [String: Any])?["trend"])
        let filters = ((body["query"] as? [String: Any])?["bool"] as? [String: Any])?["filter"]
            as? [[String: Any]]
        XCTAssertFalse(filters?.contains { $0["term"] != nil } ?? true)
    }

    func testTheSlowLogQueryAddsTheTrendAndTheServiceFilter() {
        let body = LogBoxQuery.searchBody(
            fromMinutes: 1440, service: "jobrunner", trendBucketMinutes: 30
        )
        let aggs = body["aggs"] as? [String: Any]
        let error = aggs?["error"] as? [String: Any]
        XCTAssertNotNil((error?["aggs"] as? [String: Any])?["trend"])
        let filters = ((body["query"] as? [String: Any])?["bool"] as? [String: Any])?["filter"]
            as? [[String: Any]]
        XCTAssertTrue(filters?.contains { $0["term"] != nil } ?? false)
    }

    func testA24hTrendUsesAbout48Buckets() {
        XCTAssertEqual(LogBoxQuery.trendBucketMinutes(forMinutes: 1440), 30)
        XCTAssertEqual(LogBoxQuery.trendBucketMinutes(forMinutes: 15), 5)
    }

    func testHostLabelsAreValidatedBeforeReachingPromQL() {
        XCTAssertEqual(MetricBoxQuery.safeHost("x201"), "x201")
        XCTAssertEqual(MetricBoxQuery.safeHost(" x300 "), "x300")
        XCTAssertNil(MetricBoxQuery.safeHost(""))
        XCTAssertNil(MetricBoxQuery.safeHost("x201\"}"))
    }

    func testInstantAndRangeBodiesDifferAsTheAPIExpects() {
        let from = Date(timeIntervalSince1970: 0)
        let to = Date(timeIntervalSince1970: 60)
        let instant = MetricBoxQuery.body(
            uid: "u", expressions: [("A", "up")], from: from, to: to,
            instant: true, maxDataPoints: nil
        )
        let instantQuery = (instant["queries"] as? [[String: Any]])?.first
        XCTAssertEqual(instantQuery?["instant"] as? Bool, true)
        XCTAssertEqual(instantQuery?["range"] as? Bool, false)
        XCTAssertNil(instantQuery?["maxDataPoints"])

        let range = MetricBoxQuery.body(
            uid: "u", expressions: [("A", "up")], from: from, to: to,
            instant: false, maxDataPoints: 24
        )
        let rangeQuery = (range["queries"] as? [[String: Any]])?.first
        XCTAssertEqual(rangeQuery?["range"] as? Bool, true)
        XCTAssertEqual(rangeQuery?["maxDataPoints"] as? Int, 24)
    }

    // MARK: - Links

    func testKibanaLinkKeepsTheIndexAndEscapesTheQuery() {
        let url = InfraLinks.kibanaDiscover(
            uiURL: "https://x300.tail970481.ts.net/",
            index: "logs-manifold-prd",
            query: "log.level:(error OR critical)",
            fromMinutes: 15
        )
        XCTAssertTrue(url?.absoluteString.contains("logs-manifold-prd") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("error%20OR%20critical") ?? false)
    }

    func testGrafanaLinkCarriesTheHostAndRange() {
        let url = InfraLinks.grafanaDashboard(
            baseURL: "https://monitoring.4si8analytics.com/",
            uid: "fleet-overview", host: "x201", fromMinutes: 1440
        )
        XCTAssertTrue(url?.absoluteString.contains("/d/fleet-overview") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("var-host=x201") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("from=now-1440m") ?? false)
    }

    func testEmptyBasesDoNotProduceLinks() {
        XCTAssertNil(InfraLinks.kibanaDiscover(
            uiURL: "", index: "i", query: "q", fromMinutes: 15
        ))
        XCTAssertNil(InfraLinks.grafanaDashboard(
            baseURL: " ", uid: "u", host: nil, fromMinutes: 15
        ))
    }

    // MARK: - Account model

    func testInfraAccountURLsRoundTripAndTheTokenNeverDoes() throws {
        var account = CredentialAccount(kind: .elastic)
        account.baseURL = "https://x300.tail970481.ts.net:9200"
        account.uiURL = "https://x300.tail970481.ts.net"
        account.token = "super-secret"

        let data = try JSONEncoder().encode(account)
        let back = try JSONDecoder().decode(CredentialAccount.self, from: data)
        XCTAssertEqual(back.baseURL, account.baseURL)
        XCTAssertEqual(back.uiURL, account.uiURL)
        XCTAssertEqual(back.token, "")
    }

    func testEditingTheURLInvalidatesAVerification() {
        var account = CredentialAccount(kind: .grafana)
        account.token = "t"
        account.baseURL = "https://a.example"
        let fingerprint = account.credentialFingerprint
        account.baseURL = "https://b.example"
        XCTAssertNotEqual(account.credentialFingerprint, fingerprint)
    }

    // MARK: - Fleet ordering

    func testSilentHostsComeFirstThenTheBusiest() {
        let hosts = [
            MetricHost(host: "ok", cpu: 10, ram: 20, disk: 30, lastSeenSeconds: 3),
            MetricHost(host: "busy", cpu: 90, ram: 40, disk: 50, lastSeenSeconds: 4),
            MetricHost(host: "silent", cpu: 1, ram: 1, disk: 1, lastSeenSeconds: 900),
        ]
        XCTAssertEqual(MetricBoxSort.worstFirst(hosts).map(\.host), ["silent", "busy", "ok"])
    }

    func testHiddenHostsAreRemoved() {
        let hosts = [
            MetricHost(host: "x201", cpu: 10, lastSeenSeconds: 1),
            MetricHost(host: "x202", cpu: 90, lastSeenSeconds: 1),
        ]
        XCTAssertEqual(MetricBoxSort.worstFirst(hosts, hidden: ["x202"]).map(\.host), ["x201"])
    }

    func testMonthlyCostMultipliesTheDailyKWh() {
        XCTAssertEqual(MetricBoxSort.monthlyCost(kwh24h: 2, ratePerKWh: 0.12) ?? 0, 7.2, accuracy: 0.001)
        XCTAssertNil(MetricBoxSort.monthlyCost(kwh24h: nil, ratePerKWh: 0.12))
    }
}
