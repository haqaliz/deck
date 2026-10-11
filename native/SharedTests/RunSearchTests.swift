import XCTest

// Builds: GitHub Actions runs from the snapshot ShipBox already holds. Instant
// and local — a live query would cost ~11 KB per run per repo per search.

final class RunSearchTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_768_478_400)

    private func run(_ number: Int, _ name: String = "CI", repo: String = "acme/deck", branch: String = "main",
                     status: ShipStatus = .success,
                     url: String = "https://github.com/acme/deck/actions/runs/1") -> ShipRun {
        ShipRun(repo: repo, name: name, runNumber: number, branch: branch, status: status,
                createdAt: t, updatedAt: t, htmlURL: url)
    }

    private func snapshot(_ runs: [ShipRun]) -> ShipBoxSnapshot {
        ShipBoxSnapshot(writtenAt: t, repos: ["acme/deck"], runs: runs)
    }

    func testFindsByWorkflowBranchRepoAndNumber() {
        let snap = snapshot([run(41, "Deploy", branch: "release/2.0"), run(42, "CI", repo: "acme/api")])
        XCTAssertEqual(RunSearch.results(query: "deploy", snapshot: snap).map(\.title), ["Deploy #41"])
        XCTAssertEqual(RunSearch.results(query: "release", snapshot: snap).count, 1)
        XCTAssertEqual(RunSearch.results(query: "acme/api", snapshot: snap).map(\.title), ["CI #42"])
        XCTAssertEqual(RunSearch.results(query: "42", snapshot: snap).map(\.title), ["CI #42"])
    }

    func testAnExactRunNumberOutranksAMention() {
        let snap = snapshot([run(142, "Nightly 41 sweep"), run(41, "CI")])
        let sorted = SpotlightRanking.sorted(RunSearch.results(query: "41", snapshot: snap))
        XCTAssertEqual(sorted.first?.title, "CI #41")
    }

    func testTheSubtitleSaysWhereAndHowItWent() {
        let hit = RunSearch.results(query: "ci", snapshot: snapshot([run(7, status: .failure)]))[0]
        XCTAssertEqual(hit.subtitle, "acme/deck · main · Failed")
    }

    func testEveryStatusHasWords() {
        for status in [ShipStatus.queued, .running, .success, .failure, .neutral] {
            XCTAssertFalse(RunSearch.statusWord(status).isEmpty)
        }
        XCTAssertEqual(RunSearch.statusWord(.success), "Passed")
    }

    func testEnterOpensTheRunAndAnUnsafeURLIsCopyOnly() throws {
        let ok = RunSearch.results(query: "ci", snapshot: snapshot([run(1)]))[0]
        XCTAssertEqual(ok.action, .open(try XCTUnwrap(URL(string: "https://github.com/acme/deck/actions/runs/1"))))
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "", "https://"] {
            let hit = RunSearch.results(query: "ci", snapshot: snapshot([run(1, url: bad)]))[0]
            XCTAssertEqual(hit.action, .copy("#1"), bad)
        }
    }

    /// Run numbers repeat across workflows and repos; one id would collapse rows.
    func testIDsAreDistinct() {
        let snap = snapshot([run(5, "CI"), run(5, "Deploy"), run(5, "CI", repo: "acme/api")])
        let hits = RunSearch.results(query: "5", snapshot: snap)
        XCTAssertEqual(Set(hits.map(\.id)).count, 3)
    }

    func testNoSnapshotMeansNothing() {
        XCTAssertTrue(RunSearch.results(query: "ci", snapshot: nil).isEmpty)
    }

    func testTheEngineAnswersForRunsInstantlyAndUnscoped() {
        let inputs = SpotlightInputs(clip: nil, devbox: nil, opencode: nil, configuredClockIDs: [],
                                     shipbox: snapshot([run(9, "Deploy")]))
        let scoped = SpotlightEngine.run(rawQuery: "run deploy", settings: SpotlightSettings(),
                                         inputs: inputs, now: t, reference: .current)
        XCTAssertEqual(scoped.map(\.provider), [.run])
        let open = SpotlightEngine.run(rawQuery: "deploy", settings: SpotlightSettings(),
                                       inputs: inputs, now: t, reference: .current)
        XCTAssertEqual(open.map(\.provider), [.run])
    }

    func testADisabledBuildsSourceIsNeverSearched() {
        var s = SpotlightSettings(); s.runEnabled = false
        let inputs = SpotlightInputs(clip: nil, devbox: nil, opencode: nil, configuredClockIDs: [],
                                     shipbox: snapshot([run(9, "Deploy")]))
        XCTAssertTrue(SpotlightEngine.run(rawQuery: "run deploy", settings: s, inputs: inputs,
                                          now: t, reference: .current).isEmpty)
    }
}
