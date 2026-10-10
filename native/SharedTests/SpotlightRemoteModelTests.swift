import XCTest

// The shell's types learn about a remote source without changing anything a
// local source does.

final class SpotlightRemoteModelTests: XCTestCase {
    func testTaskIsAppendedAfterTheLocalSources() {
        XCTAssertEqual(SearchProviderID.allCases, [.clip, .port, .time, .oc, .task])
    }

    func testOnlyTaskIsRemote() {
        XCTAssertEqual(SearchProviderID.allCases.filter(\.isRemote), [.task])
        XCTAssertEqual(SearchProviderID.localCases, [.clip, .port, .time, .oc])
    }

    func testTheTaskPrefixScopes() {
        XCTAssertEqual(SpotlightQuery.parse("task login bug").scope, .task)
        XCTAssertEqual(SpotlightQuery.parse("task login bug").text, "login bug")
        // Still only once followed by a space, like every prefix.
        XCTAssertNil(SpotlightQuery.parse("task").scope)
        XCTAssertNil(SpotlightQuery.parse("tasks login").scope)
    }

    func testTheLocalEngineNeverAnswersForARemoteSource() {
        let inputs = SpotlightInputs(clip: nil, devbox: nil, opencode: nil, configuredClockIDs: [])
        let scoped = SpotlightEngine.run(rawQuery: "task login", settings: SpotlightSettings(),
                                         inputs: inputs, now: Date(), reference: .current)
        XCTAssertTrue(scoped.isEmpty)
        // And an unscoped query never grows a Tasks section from the local path.
        let open = SpotlightEngine.run(rawQuery: "login", settings: SpotlightSettings(),
                                       inputs: inputs, now: Date(), reference: .current)
        XCTAssertFalse(open.contains { $0.provider == .task })
    }

    func testTasksAreOnByDefaultAndTolerantlyDecoded() throws {
        XCTAssertTrue(SpotlightSettings().taskEnabled)
        XCTAssertTrue(SpotlightSettings().isEnabled(.task))
        let old = try JSONDecoder().decode(SpotlightSettings.self, from: Data(#"{"clipEnabled":true}"#.utf8))
        XCTAssertTrue(old.taskEnabled)
        XCTAssertTrue(old.clipEnabled, "an existing setting survives")
        var s = SpotlightSettings(); s.taskEnabled = false
        XCTAssertEqual(try JSONDecoder().decode(SpotlightSettings.self, from: JSONEncoder().encode(s)), s)
    }

    func testTheTaskSourceHasItsSettingsWording() {
        XCTAssertEqual(SearchProviderID.task.settingsTitle, "Tasks")
        XCTAssertTrue(SearchProviderID.task.exampleSummary.contains("dev.azure.com"),
                      "the privacy sentence must be where the user decides")
    }

    func testActionsKnowWhatToCopy() throws {
        let url = try XCTUnwrap(URL(string: "https://dev.azure.com/o/p/_workitems/edit/7"))
        XCTAssertEqual(SpotlightAction.copy("x").copyText, "x")
        XCTAssertEqual(SpotlightAction.open(url).copyText, url.absoluteString)
    }
}

final class TaskSearchResultsTests: XCTestCase {
    private func task(_ id: String, _ title: String, state: String = "Active", type: String = "Bug",
                      project: String? = "Web", tags: [String] = [],
                      url: String? = nil) -> TaskItem {
        TaskItem(id: id, title: title, state: state, itemType: type,
                 url: url ?? "https://dev.azure.com/Contoso/Web/_workitems/edit/\(id)",
                 provider: .azureDevOps, changedAt: nil, project: project, tags: tags)
    }

    func testARowOpensTheWorkItem() throws {
        let hits = TaskSearch.results(from: [task("1234", "Login fails")], query: "login")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].provider, .task)
        XCTAssertEqual(hits[0].action, .open(try XCTUnwrap(URL(string: "https://dev.azure.com/Contoso/Web/_workitems/edit/1234"))))
    }

    func testTheSubtitleSaysWhatItIs() {
        let hit = TaskSearch.results(from: [task("1234", "Login fails", tags: ["auth", "p1"])], query: "login")[0]
        XCTAssertEqual(hit.subtitle, "Bug · Active · Web · #1234 · auth, p1")
    }

    func testMissingPartsAreLeftOutNotPrintedEmpty() {
        let hit = TaskSearch.results(from: [task("9", "Plain", state: "", type: "", project: nil)], query: "plain")[0]
        XCTAssertEqual(hit.subtitle, "#9")
    }

    /// The project is part of the identity: two projects can each have an
    /// item 12, and one id would collapse both rows (CLAUDE.md).
    func testTheProjectIsPartOfTheID() {
        let hits = TaskSearch.results(from: [task("12", "Same", project: "A"), task("12", "Same", project: "B")],
                                      query: "same")
        XCTAssertEqual(Set(hits.map(\.id)).count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.id.hasPrefix("task:") })
    }

    /// Azure decided these match. A local matcher that disagrees about partial
    /// words must not drop them.
    func testNothingAzureReturnedIsFilteredOut() {
        let hits = TaskSearch.results(from: [task("5", "Zzzz unrelated title", tags: [])], query: "login")
        XCTAssertEqual(hits.count, 1)
    }

    func testAnExactIDRanksFirst() {
        let hits = SpotlightRanking.sorted(TaskSearch.results(
            from: [task("100", "Mentions 4521 in the title"), task("4521", "Something else")], query: "4521"))
        XCTAssertEqual(hits.first?.title, "Something else")
    }

    func testTitleMatchesOutrankTagOnlyMatches() {
        let hits = SpotlightRanking.sorted(TaskSearch.results(
            from: [task("1", "Unrelated", tags: ["login"]), task("2", "Login page")], query: "login"))
        XCTAssertEqual(hits.first?.id.hasSuffix(":2"), true)
    }

    /// The URL comes from remote data: anything that is not http(s) with a
    /// host is not offered as openable.
    func testAnUnsafeURLIsNeverOpenable() {
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "ftp://x/y", "", "not a url", "https://"] {
            let hit = TaskSearch.results(from: [task("3", "Row", url: bad)], query: "row")[0]
            if case .open = hit.action { XCTFail("\(bad) became an open action") }
            XCTAssertEqual(hit.action, .copy("3"), bad)
        }
    }
}
