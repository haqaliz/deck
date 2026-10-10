import XCTest

// Each provider is a pure function over a decoded snapshot. A missing snapshot
// is "that source has nothing", never an error row.

final class SpotlightClipSearchTests: XCTestCase {
    private func item(_ preview: String, content: String?, kind: ClipKind = .text,
                      detail: String = "") -> ClipItem {
        ClipItem(id: UUID(), date: Date(timeIntervalSince1970: 0), kind: kind,
                 preview: preview, detail: detail, content: content)
    }

    func testMatchesFullContentNotJustThePreview() {
        let snap = ClipBoxSnapshot(writtenAt: Date(), items: [
            item("deploy notes…", content: "deploy notes: rotate the staging password"),
        ])
        let hits = ClipSearch.results(query: "staging", snapshot: snap)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].action, .copy("deploy notes: rotate the staging password"))
        XCTAssertEqual(hits[0].provider, .clip)
    }

    /// Images and "other" items carry no content, so there is nothing to copy
    /// back from here; offering them would be a row whose Enter does nothing.
    func testItemsWithoutContentAreNotOffered() {
        let snap = ClipBoxSnapshot(writtenAt: Date(), items: [
            item("Image 800x600", content: nil, kind: .image),
        ])
        XCTAssertTrue(ClipSearch.results(query: "image", snapshot: snap).isEmpty)
    }

    func testNilSnapshotYieldsNothing() {
        XCTAssertTrue(ClipSearch.results(query: "x", snapshot: nil).isEmpty)
    }

    func testIDsAreUniquePerItem() {
        let a = item("same", content: "same"), b = item("same", content: "same")
        let hits = ClipSearch.results(query: "same", snapshot: ClipBoxSnapshot(writtenAt: Date(), items: [a, b]))
        XCTAssertEqual(Set(hits.map(\.id)).count, 2)
    }
}

final class SpotlightDevSearchTests: XCTestCase {
    private let snap = DevBoxSnapshot(
        writtenAt: Date(),
        ports: [PortInfo(command: "node", host: "127.0.0.1", port: 3000),
                PortInfo(command: "postgres", host: "*", port: 5432)],
        containers: [ContainerInfo(name: "redis-cache", image: "redis:7", status: "Up 2 hours",
                                   cpuPercent: nil, memPercent: nil)],
        dockerState: .running)

    func testFindsAPortByNumber() {
        let hits = DevSearch.results(query: "5432", snapshot: snap)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].action, .copy("5432"))
    }

    func testFindsAPortByProcessName() {
        let hits = DevSearch.results(query: "node", snapshot: snap)
        XCTAssertEqual(hits.map(\.action), [.copy("3000")])
    }

    func testFindsAContainerByNameOrImage() {
        XCTAssertEqual(DevSearch.results(query: "redis-cache", snapshot: snap).first?.action,
                       .copy("redis-cache"))
        XCTAssertEqual(DevSearch.results(query: "redis:7", snapshot: snap).count, 1)
    }

    func testPortAndContainerIDsDoNotCollide() {
        let both = DevBoxSnapshot(
            writtenAt: Date(),
            ports: [PortInfo(command: "redis", host: "*", port: 6379)],
            containers: [ContainerInfo(name: "redis", image: "redis", status: "Up",
                                       cpuPercent: nil, memPercent: nil)],
            dockerState: .running)
        let hits = DevSearch.results(query: "redis", snapshot: both)
        XCTAssertEqual(Set(hits.map(\.id)).count, 2)
    }

    func testNilSnapshotYieldsNothing() {
        XCTAssertTrue(DevSearch.results(query: "node", snapshot: nil).isEmpty)
    }
}

final class SpotlightClockSearchTests: XCTestCase {
    /// 2026-01-15 12:00 UTC: no DST edge cases for the zones used below.
    private let now = Date(timeIntervalSince1970: 1_768_478_400)
    private let utc = TimeZone(identifier: "UTC")!

    func testFindsACuratedCityByName() throws {
        let hits = ClockSearch.results(query: "tokyo", configuredIDs: [], now: now, reference: utc)
        let tokyo = try XCTUnwrap(hits.first)
        XCTAssertEqual(tokyo.provider, .time)
        XCTAssertEqual(tokyo.action, .copy("21:00"))
        XCTAssertTrue(tokyo.subtitle.contains("21:00"))
        XCTAssertTrue(tokyo.subtitle.contains("+9:00"))
    }

    func testFindsByIANAIdentifier() {
        XCTAssertFalse(ClockSearch.results(query: "Asia/Tokyo", configuredIDs: [], now: now, reference: utc).isEmpty)
    }

    func testRelativeDayAppearsInTheSubtitle() throws {
        // 12:00 UTC is already past midnight in Auckland (UTC+13 in January).
        let hits = ClockSearch.results(query: "auckland", configuredIDs: [], now: now, reference: utc)
        XCTAssertTrue(try XCTUnwrap(hits.first).subtitle.contains("Tomorrow"))
    }

    func testAConfiguredZoneOutsideTheCuratedListIsSearchable() {
        let hits = ClockSearch.results(query: "Reykjavik", configuredIDs: ["Atlantic/Reykjavik"], now: now, reference: utc)
        XCTAssertEqual(hits.count, 1)
    }

    func testAConfiguredCuratedCityIsNotListedTwice() {
        let hits = ClockSearch.results(query: "tokyo", configuredIDs: ["Asia/Tokyo"], now: now, reference: utc)
        XCTAssertEqual(hits.count, 1)
    }

    func testInvalidConfiguredIDIsIgnored() {
        XCTAssertTrue(ClockSearch.results(query: "nowhere", configuredIDs: ["Not/AZone"], now: now, reference: utc).isEmpty)
    }
}

final class SpotlightOpenCodeSearchTests: XCTestCase {
    private func snapshot(_ titles: [String]) -> OpenCodeSnapshot {
        OpenCodeSnapshot(
            writtenAt: Date(), sessions: Int64(titles.count), input: 0, output: 0, cost: 0,
            daily: [], models: [], tools: [], costDaily: [],
            sessionList: titles.map {
                OpenCodeSnapshot.SessionRow(title: $0, input: 1200, output: 300,
                                            timeCreated: Date(timeIntervalSince1970: 1_768_478_400))
            },
            totalInput: 0, totalOutput: 0, totalCost: 0)
    }

    func testMatchesSessionTitlesAndCopiesTheTitle() {
        let hits = OpenCodeSearch.results(query: "refactor", snapshot: snapshot(["Refactor loader", "Fix typo"]))
        XCTAssertEqual(hits.map(\.title), ["Refactor loader"])
        XCTAssertEqual(hits[0].action, .copy("Refactor loader"))
    }

    func testNilSnapshotYieldsNothing() {
        XCTAssertTrue(OpenCodeSearch.results(query: "x", snapshot: nil).isEmpty)
    }

    func testSameTitleTwiceKeepsDistinctIDs() {
        let hits = OpenCodeSearch.results(query: "retry", snapshot: snapshot(["retry", "retry"]))
        XCTAssertEqual(Set(hits.map(\.id)).count, 2)
    }
}

final class SpotlightEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_768_478_400)
    private let utc = TimeZone(identifier: "UTC")!

    private var inputs: SpotlightInputs {
        SpotlightInputs(
            clip: ClipBoxSnapshot(writtenAt: now, items: [
                ClipItem(id: UUID(), date: now, kind: .text, preview: "node tips", detail: "", content: "node tips"),
            ]),
            devbox: DevBoxSnapshot(writtenAt: now,
                                   ports: [PortInfo(command: "node", host: "*", port: 3000)],
                                   containers: [], dockerState: .noContainers),
            opencode: nil,
            configuredClockIDs: [])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(SpotlightEngine.run(rawQuery: "  ", settings: SpotlightSettings(),
                                          inputs: inputs, now: now, reference: utc).isEmpty)
    }

    func testClipIsOffByDefaultSoItNeverAppears() {
        let sections = SpotlightEngine.run(rawQuery: "node", settings: SpotlightSettings(),
                                           inputs: inputs, now: now, reference: utc)
        XCTAssertEqual(sections.map(\.provider), [.port])
    }

    func testEnablingClipAddsItsSection() {
        var s = SpotlightSettings()
        s.clipEnabled = true
        let sections = SpotlightEngine.run(rawQuery: "node", settings: s,
                                           inputs: inputs, now: now, reference: utc)
        XCTAssertEqual(sections.map(\.provider), [.clip, .port])
    }

    func testPrefixNarrowsToOneProvider() {
        var s = SpotlightSettings()
        s.clipEnabled = true
        let sections = SpotlightEngine.run(rawQuery: "port node", settings: s,
                                           inputs: inputs, now: now, reference: utc)
        XCTAssertEqual(sections.map(\.provider), [.port])
    }

    /// Typing `clip ` while clip is switched off must not quietly search it
    /// anyway: the toggle is the privacy control.
    func testScopingToADisabledProviderReturnsNothing() {
        let sections = SpotlightEngine.run(rawQuery: "clip node", settings: SpotlightSettings(),
                                           inputs: inputs, now: now, reference: utc)
        XCTAssertTrue(sections.isEmpty)
    }

    func testPrefixAloneReturnsNothingUntilThereIsText() {
        XCTAssertTrue(SpotlightEngine.run(rawQuery: "port ", settings: SpotlightSettings(),
                                          inputs: inputs, now: now, reference: utc).isEmpty)
    }
}
