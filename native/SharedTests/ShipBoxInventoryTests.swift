import XCTest

// ShipBox inventory pagination + caching (PRD §3): parsing GitHub's `Link`
// header (same-origin only — the request carries the user's token), and the
// capped serial page walk that turns pages into one pushed-ordered list.
//
// This account has 31 repos and no `Link` header, so these are the only
// verification pagination gets (PRD §7) — the live tick must simply make no
// extra requests.

final class LinkHeaderParserTests: XCTestCase {
    func testParsesTheNextLinkFromASingleLinkHeader() {
        let header = #"<https://api.github.com/user/repos?page=2&per_page=100&sort=pushed>; rel="next""#
        XCTAssertEqual(
            LinkHeaderParser.next(from: header)?.absoluteString,
            "https://api.github.com/user/repos?page=2&per_page=100&sort=pushed"
        )
    }

    /// GitHub's real headers carry `last` (and often `first`) alongside
    /// `next`; the parser must find the right segment, not the first one.
    func testParsesNextWhenItSitsAmongOtherRels() {
        let header = #"<https://api.github.com/user/repos?page=1>; rel="first", <https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=4>; rel="last""#
        XCTAssertEqual(
            LinkHeaderParser.next(from: header)?.absoluteString,
            "https://api.github.com/user/repos?page=2"
        )
    }

    /// A single page has no `Link` header at all — that is the stop signal,
    /// not an error.
    func testNoNextLinkIsNil() {
        XCTAssertNil(LinkHeaderParser.next(from: ""))
        XCTAssertNil(LinkHeaderParser.next(from: nil))
    }

    func testALastLinkAloneIsNil() {
        let header = #"<https://api.github.com/user/repos?page=3>; rel="last""#
        XCTAssertNil(LinkHeaderParser.next(from: header))
    }

    func testMalformedInputIsNil() {
        XCTAssertNil(LinkHeaderParser.next(from: #"not-a-link; rel="next""#))
        XCTAssertNil(LinkHeaderParser.next(from: #"<>; rel="next""#))
        XCTAssertNil(LinkHeaderParser.next(from: #"<https://api.github.com/user/repos>; rel="""#))
    }

    /// The header is data from the network and the request carries the user's
    /// token: a link to any other host must never be followed (the
    /// `DeckURLForwarding` host-filter precedent).
    func testALinkToAnotherHostIsNil() {
        let header = #"<https://evil.example.com/user/repos?page=2>; rel="next""#
        XCTAssertNil(LinkHeaderParser.next(from: header))
    }

    func testARelativeLinkIsNil() {
        let header = #"</user/repos?page=2>; rel="next""#
        XCTAssertNil(LinkHeaderParser.next(from: header))
    }
}

final class InventoryPaginatorTests: XCTestCase {
    private let page1 = URL(string: "https://api.github.com/user/repos?page=1")!
    private let page2 = URL(string: "https://api.github.com/user/repos?page=2")!
    private let page3 = URL(string: "https://api.github.com/user/repos?page=3")!

    func testCollectsPagesUntilTheNextLinkStops() async throws {
        var calls: [URL] = []
        let repos = try await InventoryPaginator.allPages(startingAt: page1, maxPages: 5) { url in
            calls.append(url)
            switch url {
            case page1: return (["a/1", "a/2"], page2)
            case page2: return (["a/3"], nil)
            default: XCTFail("walked past the end"); return ([], nil)
            }
        }
        XCTAssertEqual(repos, ["a/1", "a/2", "a/3"])
        XCTAssertEqual(calls, [page1, page2])
    }

    /// The cap is a safety bound for giant accounts, not a product limit
    /// (PRD C2): the walk stops, with what it has, rather than stalling the
    /// settings window.
    func testStopsAtThePageCap() async throws {
        var calls = 0
        let repos = try await InventoryPaginator.allPages(startingAt: page1, maxPages: 2) { _ in
            calls += 1
            return (["a/\(calls)"], page2)
        }
        XCTAssertEqual(repos, ["a/1", "a/2"])
        XCTAssertEqual(calls, 2)
    }

    /// Pushed order is global across pages: page 1's repos stay ahead of page
    /// 2's in the merged list, so the dynamic candidate rule (take the front)
    /// stays valid over a paginated inventory.
    func testPagesAppendInOrder() async throws {
        let repos = try await InventoryPaginator.allPages(startingAt: page1, maxPages: 5) { url in
            url == page1 ? (["z/newest"], page2) : (["a/older"], nil)
        }
        XCTAssertEqual(repos, ["z/newest", "a/older"])
    }

    func testASinglePageStopsImmediately() async throws {
        let repos = try await InventoryPaginator.allPages(startingAt: page1, maxPages: 5) { _ in
            (["a/1"], nil)
        }
        XCTAssertEqual(repos, ["a/1"])
    }

    func testAThrowingPageFailsTheWalk() async {
        do {
            _ = try await InventoryPaginator.allPages(startingAt: page1, maxPages: 5) { _ in
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("expected the page error to propagate")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }
}

// MARK: - The cross-tick cache (PRD §3.2)

final class InventoryCachePolicyTests: XCTestCase {
    private func decision(age: TimeInterval, accountMatches: Bool = true, affiliationMatches: Bool = true) -> InventoryCachePolicy.Decision {
        InventoryCachePolicy.decision(
            age: age,
            accountMatches: accountMatches,
            affiliationMatches: affiliationMatches
        )
    }

    func testAFreshMatchingCacheIsUsed() {
        XCTAssertEqual(decision(age: 0), .useCache)
        XCTAssertEqual(decision(age: 599), .useCache)
    }

    /// The interview decision: the inventory refreshes at most every 10
    /// minutes, the multi-repo PRD's "every ~10 ticks".
    func testTheRefreshBoundaryIsTenMinutes() {
        XCTAssertEqual(decision(age: 600), .refresh)
    }

    func testAnOlderCacheRefreshes() {
        XCTAssertEqual(decision(age: 601), .refresh)
        XCTAssertEqual(decision(age: 3600), .refresh)
    }

    /// A fetchedAt in the future (clock change) must not freeze the cache
    /// fresh forever (PRD C4).
    func testAFutureFetchedAtReadsAsStale() {
        XCTAssertEqual(decision(age: -1), .refresh)
    }

    /// The inventory is per-token: account B must never be served account A's
    /// repo list, even for one tick.
    func testAnotherAccountsCacheReadsAsMissing() {
        XCTAssertEqual(decision(age: 5, accountMatches: false), .refresh)
    }

    /// Dynamic discovery asks `affiliation=owner` while the picker asks the
    /// default; a picker-warmed record must never feed owner-only discovery
    /// (PRD C4).
    func testAnotherAffiliationsCacheReadsAsMissing() {
        XCTAssertEqual(decision(age: 5, affiliationMatches: false), .refresh)
    }
}

final class InventoryCacheStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InventoryCacheStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func record(version: Int = ShipBoxInventoryCache.currentVersion) -> ShipBoxInventoryCache {
        ShipBoxInventoryCache(
            version: version,
            accountID: "account-1",
            affiliation: "owner",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            repos: ["haqaliz/deck", "haqaliz/belay"]
        )
    }

    func testSaveThenLoadReturnsTheRecord() throws {
        let url = dir.appendingPathComponent("shipbox-inventory.json")
        InventoryCacheStore.save(record(), to: url)
        XCTAssertEqual(InventoryCacheStore.load(from: url), record())
    }

    func testLoadIsNilForAMissingFile() {
        XCTAssertNil(InventoryCacheStore.load(from: dir.appendingPathComponent("nope.json")))
    }

    func testLoadIsNilForCorruptJSON() throws {
        let url = dir.appendingPathComponent("corrupt.json")
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(InventoryCacheStore.load(from: url))
    }

    /// A future schema version reads as absent, so the loader self-heals with
    /// a live fetch rather than trusting a shape it cannot vouch for (the
    /// `OpenCodeSyncStore` precedent).
    func testLoadIsNilForAFutureVersion() throws {
        let url = dir.appendingPathComponent("future.json")
        let data = try JSONEncoder().encode(record(version: ShipBoxInventoryCache.currentVersion + 1))
        try data.write(to: url)
        XCTAssertNil(InventoryCacheStore.load(from: url))
    }
}