import XCTest

// The five sources added after work items: builds (ShipBox), commits (GitBox),
// calendar events (CalBox), markets (MarketBox) and pull requests (PRBox).

final class SpotlightSourcesModelTests: XCTestCase {
    func testPrefixesScopeToTheirSource() {
        let cases: [(String, SearchProviderID)] = [
            ("run deploy", .run), ("pr login", .pr), ("commit fix", .commit),
            ("cal standup", .event), ("mkt bitcoin", .market),
        ]
        for (raw, source) in cases {
            let q = SpotlightQuery.parse(raw)
            XCTAssertEqual(q.scope, source, raw)
            XCTAssertFalse(q.isEmpty, raw)
        }
    }

    /// Only a prefix asks a service about what was typed. An unscoped query
    /// must not reach GitHub (the PRBox agent's 30/min search budget),
    /// CoinGecko/Yahoo (one shared IP quota) or every repo's `git log`.
    func testNetworkAndSubprocessSourcesNeedAPrefix() {
        XCTAssertEqual(SearchProviderID.allCases.filter(\.requiresPrefix), [.pr, .commit, .market])
    }

    func testWorkItemsAndInstantSourcesDoNot() {
        for source in SearchProviderID.instantCases { XCTAssertFalse(source.requiresPrefix, "\(source)") }
        XCTAssertFalse(SearchProviderID.task.requiresPrefix)
        XCTAssertFalse(SearchProviderID.event.requiresPrefix)
    }

    func testNoPrefixCollidesWithAWorkItemType() {
        let sourcePrefixes = SearchProviderID.allCases.filter { $0 != .task }.map(\.rawValue)
        for kind in WorkItemKind.allCases {
            for p in kind.prefixes { XCTAssertFalse(sourcePrefixes.contains(p), p) }
        }
        XCTAssertEqual(sourcePrefixes.count, Set(sourcePrefixes).count)
    }

    func testEverySourceIsNamedForTheSettingsTab() {
        let titles = SearchProviderID.allCases.map(\.settingsTitle)
        XCTAssertEqual(titles.count, Set(titles).count, "two sources share a settings title")
        XCTAssertEqual(SearchProviderID.run.settingsTitle, "Builds")
        XCTAssertEqual(SearchProviderID.pr.settingsTitle, "Pull requests")
        XCTAssertEqual(SearchProviderID.commit.settingsTitle, "Commits")
        XCTAssertEqual(SearchProviderID.event.settingsTitle, "Calendar events")
        XCTAssertEqual(SearchProviderID.market.settingsTitle, "Markets")
    }

    /// Where the user decides, the wording must say who receives what is typed.
    func testSourcesThatSendTextSayWhereItGoes() {
        XCTAssertTrue(SearchProviderID.pr.exampleSummary.contains("GitHub"))
        XCTAssertTrue(SearchProviderID.pr.exampleSummary.contains("Azure DevOps"))
        XCTAssertTrue(SearchProviderID.market.exampleSummary.contains("CoinGecko"))
        XCTAssertTrue(SearchProviderID.market.exampleSummary.contains("Yahoo"))
        XCTAssertFalse(SearchProviderID.commit.exampleSummary.contains("sent to"), "commits never leave the Mac")
        XCTAssertFalse(SearchProviderID.event.exampleSummary.contains("sent to"), "events never leave the Mac")
    }

    func testPrefixOnlySourcesTellTheUserToUseThePrefix() {
        for source in SearchProviderID.allCases where source.requiresPrefix {
            XCTAssertTrue(source.exampleSummary.contains("\(source.rawValue) "),
                          "\(source) does not say it needs its prefix")
        }
    }

    func testTheInstantEngineAnswersOnlyForInstantSources() {
        let inputs = SpotlightInputs(clip: nil, devbox: nil, opencode: nil, configuredClockIDs: [], shipbox: nil)
        for raw in ["pr login", "commit fix", "cal standup", "mkt btc", "bug login"] {
            XCTAssertTrue(SpotlightEngine.run(rawQuery: raw, settings: SpotlightSettings(), inputs: inputs,
                                              now: Date(), reference: .current).isEmpty, raw)
        }
    }
}

final class SpotlightSourcesSettingsTests: XCTestCase {
    func testDefaults() {
        let s = SpotlightSettings()
        XCTAssertTrue(s.runEnabled)
        XCTAssertTrue(s.prEnabled)
        XCTAssertTrue(s.commitEnabled)
        XCTAssertTrue(s.marketEnabled)
        XCTAssertFalse(s.eventEnabled, "calendar titles on screen while sharing: opt-in, like the clipboard")
    }

    func testIsEnabledFollowsEachFlag() {
        var s = SpotlightSettings()
        s.eventEnabled = true; s.prEnabled = false
        XCTAssertTrue(s.isEnabled(.event))
        XCTAssertFalse(s.isEnabled(.pr))
        XCTAssertTrue(s.isEnabled(.run))
    }

    func testAnOldSettingsFileKeepsEverythingAndGetsDefaults() throws {
        let old = #"{"clipEnabled":true,"taskEnabled":false,"shortcutKeyCode":40,"shortcutModifiers":6144}"#
        let s = try JSONDecoder().decode(SpotlightSettings.self, from: Data(old.utf8))
        XCTAssertTrue(s.clipEnabled)
        XCTAssertFalse(s.taskEnabled)
        XCTAssertEqual(s.shortcutKeyCode, 40)
        XCTAssertTrue(s.prEnabled)
        XCTAssertFalse(s.eventEnabled)
    }

    func testRoundTrip() throws {
        var s = SpotlightSettings()
        s.eventEnabled = true; s.commitEnabled = false; s.marketEnabled = false
        XCTAssertEqual(try JSONDecoder().decode(SpotlightSettings.self, from: JSONEncoder().encode(s)), s)
    }
}

final class SpotlightSourcesFailureTests: XCTestCase {
    func testNewFailuresAreOneShortLine() {
        for failure in [RemoteSearchFailure.calendarAccess, .noRepositories] {
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertLessThan(failure.message.count, 100, "\(failure)")
            XCTAssertFalse(failure.blocksFurtherSends)
        }
    }

    func testTheyPointAtTheFix() {
        XCTAssertTrue(RemoteSearchFailure.calendarAccess.message.contains("Calendars"))
        XCTAssertTrue(RemoteSearchFailure.noRepositories.message.contains("GitBox"))
    }
}

final class SearchSourceFailureTests: XCTestCase {
    /// A source that knows exactly why it has nothing says so, rather than
    /// being reclassified from a generic error.
    func testASourceCanReportItsOwnFailure() {
        XCTAssertEqual(RemoteSearchFailure(error: SearchSourceFailure(.calendarAccess)), .calendarAccess)
        XCTAssertEqual(RemoteSearchFailure(error: SearchSourceFailure(.noRepositories)), .noRepositories)
        XCTAssertEqual(RemoteSearchFailure(error: SearchSourceFailure(.notConfigured)), .notConfigured)
    }

    func testGitHubErrorsMapThroughTheSharedClassifier() {
        XCTAssertEqual(RemoteSearchFailure(error: HostGitHubLoader.GitHubError.serverError(401)), .authOrTarget)
        XCTAssertEqual(RemoteSearchFailure(error: HostGitHubLoader.GitHubError.transport("x")), .unreachable)
        XCTAssertEqual(RemoteSearchFailure(error: HostGitHubLoader.GitHubError.invalidPayload), .badResponse)
    }

    /// GitHub says rate limit with 403 or 429; only 429 is mapped by the shared
    /// classifier, and the search layer must not turn a real 403 (bad scope)
    /// into a back-off.
    func testAGitHub429BlocksFurtherSendsAnd403DoesNot() {
        XCTAssertEqual(RemoteSearchFailure(error: HostGitHubLoader.GitHubError.serverError(429)), .rateLimited)
        XCTAssertNotEqual(RemoteSearchFailure(error: HostGitHubLoader.GitHubError.serverError(403)), .rateLimited)
    }

    func testEverySourceHasAPluralNoun() {
        for source in SearchProviderID.allCases { XCTAssertFalse(source.noun.isEmpty, "\(source)") }
        XCTAssertEqual(SearchProviderID.task.noun, "work items")
        XCTAssertEqual(SearchProviderID.pr.noun, "pull requests")
        XCTAssertEqual(RemoteSearchState<[String]>.empty.line(noun: SearchProviderID.commit.noun), "No commits found")
    }
}
