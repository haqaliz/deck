import XCTest

// The panel's brain, with no AppKit in it: which provider a query is scoped
// to, and how well a candidate matches. Everything the panel decides about
// *what to show* is pinned here so the UI is only layout.

final class SpotlightQueryTests: XCTestCase {
    func testFreeTextHasNoScope() {
        let q = SpotlightQuery.parse("postgres")
        XCTAssertNil(q.scope)
        XCTAssertEqual(q.text, "postgres")
    }

    func testPrefixScopesToOneProvider() {
        XCTAssertEqual(SpotlightQuery.parse("clip foo").scope, .clip)
        XCTAssertEqual(SpotlightQuery.parse("port 8080").scope, .port)
        XCTAssertEqual(SpotlightQuery.parse("time tokyo").scope, .time)
        XCTAssertEqual(SpotlightQuery.parse("oc refactor").scope, .oc)
        XCTAssertEqual(SpotlightQuery.parse("clip foo").text, "foo")
    }

    func testPrefixIsCaseInsensitive() {
        let q = SpotlightQuery.parse("PORT 8080")
        XCTAssertEqual(q.scope, .port)
        XCTAssertEqual(q.text, "8080")
    }

    func testPrefixAloneWithSpaceIsScopedAndEmpty() {
        let q = SpotlightQuery.parse("clip ")
        XCTAssertEqual(q.scope, .clip)
        XCTAssertEqual(q.text, "")
    }

    /// Without the trailing space the user is still typing a word, and "clip"
    /// could be the start of "clipboard". It must not scope yet.
    func testPrefixWithoutSeparatorIsFreeText() {
        let q = SpotlightQuery.parse("clip")
        XCTAssertNil(q.scope)
        XCTAssertEqual(q.text, "clip")
    }

    func testUnknownPrefixStaysFreeText() {
        let q = SpotlightQuery.parse("wat foo")
        XCTAssertNil(q.scope)
        XCTAssertEqual(q.text, "wat foo")
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(SpotlightQuery.parse("   redis   ").text, "redis")
        XCTAssertEqual(SpotlightQuery.parse("port    8080  ").text, "8080")
    }

    func testBlankIsEmpty() {
        XCTAssertTrue(SpotlightQuery.parse("   ").isEmpty)
        XCTAssertTrue(SpotlightQuery.parse("").isEmpty)
        XCTAssertFalse(SpotlightQuery.parse("a").isEmpty)
    }

    /// "oc" alone with a trailing space is a scope, not text — but the scope
    /// word only counts as the *first* token.
    func testPrefixOnlyCountsAtTheStart() {
        let q = SpotlightQuery.parse("foo clip bar")
        XCTAssertNil(q.scope)
        XCTAssertEqual(q.text, "foo clip bar")
    }
}

/// The settings tab shows one example search per source. These pin that each
/// example actually does what the tab says — scoped to its own source, with
/// something to look for — so a copy edit cannot leave a dead example on screen.
final class SpotlightExampleTests: XCTestCase {
    func testEveryExampleScopesToItsOwnSource() {
        for provider in SearchProviderID.allCases {
            let q = SpotlightQuery.parse(provider.exampleQuery)
            XCTAssertEqual(q.scope, provider, "\(provider) example: \(provider.exampleQuery)")
            XCTAssertFalse(q.isEmpty, "\(provider) example has nothing to search for")
        }
    }

    func testEveryExampleHasWordingForTheSettingsTab() {
        for provider in SearchProviderID.allCases {
            XCTAssertFalse(provider.settingsTitle.isEmpty)
            XCTAssertFalse(provider.exampleSummary.isEmpty)
        }
    }

    /// The examples run against the real providers: the clock one must find a
    /// city without any configuration, since it is searched with no snapshot.
    func testTheClockExampleFindsSomethingOnAFreshInstall() {
        let q = SpotlightQuery.parse(SearchProviderID.time.exampleQuery)
        let hits = ClockSearch.results(query: q.text, configuredIDs: [], now: Date(), reference: .current)
        XCTAssertFalse(hits.isEmpty)
    }
}

final class SpotlightMatcherTests: XCTestCase {
    func testNoMatchIsNil() {
        XCTAssertNil(SpotlightMatcher.score(query: "xyz", in: "postgres"))
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertNil(SpotlightMatcher.score(query: "", in: "postgres"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(SpotlightMatcher.score(query: "POSTGRES", in: "postgres"))
        XCTAssertNotNil(SpotlightMatcher.score(query: "postgres", in: "PostgreSQL"))
    }

    func testDiacriticInsensitive() {
        XCTAssertNotNil(SpotlightMatcher.score(query: "sao paulo", in: "São Paulo"))
        XCTAssertNotNil(SpotlightMatcher.score(query: "são", in: "Sao Paulo"))
    }

    func testRankingExactThenPrefixThenWordPrefixThenSubstring() throws {
        let exact = try XCTUnwrap(SpotlightMatcher.score(query: "node", in: "node"))
        let prefix = try XCTUnwrap(SpotlightMatcher.score(query: "node", in: "nodemon"))
        let word = try XCTUnwrap(SpotlightMatcher.score(query: "node", in: "my node app"))
        let sub = try XCTUnwrap(SpotlightMatcher.score(query: "node", in: "subnode"))
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, word)
        XCTAssertGreaterThan(word, sub)
    }

    func testEveryTokenMustMatch() {
        XCTAssertNotNil(SpotlightMatcher.score(query: "new york", in: "New York"))
        XCTAssertNotNil(SpotlightMatcher.score(query: "york new", in: "New York"))
        XCTAssertNil(SpotlightMatcher.score(query: "new paris", in: "New York"))
    }

    func testNumbersMatchLiterally() {
        XCTAssertNotNil(SpotlightMatcher.score(query: "8080", in: "localhost:8080"))
        XCTAssertNil(SpotlightMatcher.score(query: "8080", in: "8081"))
    }
}

final class SpotlightRankingTests: XCTestCase {
    private func result(_ id: String, _ title: String, _ score: Int,
                        _ provider: SearchProviderID = .port) -> SearchResult {
        SearchResult(id: id, provider: provider, title: title, subtitle: "",
                     score: score, action: .copy(title))
    }

    func testSortsByScoreDescendingThenTitleThenIDForStability() {
        let sorted = SpotlightRanking.sorted([
            result("c", "beta", 100),
            result("a", "alpha", 100),
            result("z", "zeta", 200),
            result("b", "alpha", 100),
        ])
        XCTAssertEqual(sorted.map(\.id), ["z", "a", "b", "c"])
    }

    func testGroupsInProviderOrderAndCapsEachSection() {
        let all = (1...5).map { result("p\($0)", "p\($0)", 100 - $0, .port) }
            + (1...2).map { result("c\($0)", "c\($0)", 90 - $0, .clip) }
        let sections = SpotlightRanking.sections(from: all, perSectionLimit: 3)
        XCTAssertEqual(sections.map(\.provider), [.clip, .port, .time, .oc].filter { id in
            all.contains { $0.provider == id }
        })
        XCTAssertEqual(sections.first { $0.provider == .port }?.results.count, 3)
        XCTAssertEqual(sections.first { $0.provider == .clip }?.results.count, 2)
    }

    func testEmptySectionsAreOmitted() {
        let sections = SpotlightRanking.sections(from: [result("a", "a", 1, .oc)], perSectionLimit: 5)
        XCTAssertEqual(sections.map(\.provider), [.oc])
    }
}
