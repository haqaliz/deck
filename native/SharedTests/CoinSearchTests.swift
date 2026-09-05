import XCTest

/// Phase 4 of `marketbox-coin-lookup`: the coin picker's data source.
///
/// `/coins/list` — the endpoint the ROADMAP named — was rejected after a live
/// probe: 1.24 MB, 19,594 coins, no rank, and 2,396 of 15,090 symbols map to
/// more than one coin (`BTC` is 11 of them). `/search` is 10.5 KB, already
/// ordered by market cap, and carries the rank that makes a choice possible.
private final class CoinSearchFixtures {
    static var pepe: Data {
        let url = Bundle(for: CoinSearchFixtures.self)
            .url(forResource: "coingecko_search_pepe", withExtension: "json")!
        return try! Data(contentsOf: url)
    }
}

final class CoinSearchParserTests: XCTestCase {

    func testParsesTheLiveFixture() throws {
        let hits = try XCTUnwrap(CoinSearchParser.parse(CoinSearchFixtures.pepe))
        XCTAssertEqual(hits.count, 6)
        XCTAssertEqual(hits.first?.symbol, "PEPE")
        XCTAssertEqual(hits.first?.coinID, "pepe")
        XCTAssertEqual(hits.first?.name, "Pepe")
        XCTAssertEqual(hits.first?.rank, 56)
    }

    /// `/search` is already ordered by market cap. The parser preserves server
    /// order rather than re-sorting: their ordering is not a documented
    /// guarantee, so re-deriving it would be inventing one.
    func testServerOrderIsPreserved() throws {
        let hits = try XCTUnwrap(CoinSearchParser.parse(CoinSearchFixtures.pepe))
        XCTAssertEqual(hits.map(\.coinID),
                       ["pepe", "ape-and-pepe", "pepecoin-2", "pepecoin-network", "pepefork", "purple-pepe"])
    }

    func testARankedNullCoinStillParses() throws {
        let hits = try XCTUnwrap(CoinSearchParser.parse(CoinSearchFixtures.pepe))
        XCTAssertEqual(hits.last?.symbol, "PURPE")
        XCTAssertNil(hits.last?.rank)
    }

    func testSymbolsAreUppercasedForDisplay() throws {
        let hits = try XCTUnwrap(CoinSearchParser.parse(CoinSearchFixtures.pepe))
        XCTAssertTrue(hits.allSatisfy { $0.symbol == $0.symbol.uppercased() })
    }

    func testNonCoinSectionsAreIgnored() throws {
        // The payload also carries exchanges and nfts; a match there is not a
        // ticker and must never become one.
        let hits = try XCTUnwrap(CoinSearchParser.parse(CoinSearchFixtures.pepe))
        XCTAssertTrue(hits.allSatisfy { !$0.coinID.isEmpty })
        XCTAssertEqual(hits.count, 6)
    }

    func testAnEntryWithoutAnIDIsDropped() throws {
        let json = #"{"coins":[{"symbol":"X","name":"X"},{"id":"ok","symbol":"OK","name":"Ok"}]}"#
        let hits = try XCTUnwrap(CoinSearchParser.parse(Data(json.utf8)))
        XCTAssertEqual(hits.map(\.coinID), ["ok"])
    }

    func testNoMatchesIsAnEmptyListNotAFailure() throws {
        let hits = try XCTUnwrap(CoinSearchParser.parse(Data(#"{"coins":[]}"#.utf8)))
        XCTAssertTrue(hits.isEmpty)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(CoinSearchParser.parse(Data("not json".utf8)))
    }

    func testAHitConvertsToATicker() throws {
        let hits = try XCTUnwrap(CoinSearchParser.parse(CoinSearchFixtures.pepe))
        let ticker = try XCTUnwrap(hits.first).ticker
        XCTAssertEqual(ticker.symbol, "PEPE")
        XCTAssertEqual(ticker.coinID, "pepe")
        XCTAssertEqual(ticker.name, "Pepe")
        XCTAssertEqual(ticker.kind, .crypto)
    }
}

/// The picker shares one public IP budget with the agent, which spends up to
/// four calls per 60s tick. Six requests in ~2 minutes returned **429 with
/// `retry-after: 55`** during the probe, so these rules are what stop a
/// keystroke burst from blanking the widget.
final class CoinSearchPolicyTests: XCTestCase {

    func testAQueryShorterThanTwoCharactersNeverAsks() {
        XCTAssertFalse(CoinSearchPolicy.shouldSearch(query: "p", lastRequest: nil, now: .init()))
        XCTAssertFalse(CoinSearchPolicy.shouldSearch(query: " ", lastRequest: nil, now: .init()))
    }

    func testATwoCharacterQueryAsks() {
        XCTAssertTrue(CoinSearchPolicy.shouldSearch(query: "pe", lastRequest: nil, now: .init()))
    }

    func testASecondRequestInsideTheFloorIsRefused() {
        let now = Date()
        XCTAssertFalse(CoinSearchPolicy.shouldSearch(
            query: "pepe", lastRequest: now.addingTimeInterval(-1), now: now))
    }

    func testAfterTheFloorItAsksAgain() {
        let now = Date()
        XCTAssertTrue(CoinSearchPolicy.shouldSearch(
            query: "pepe", lastRequest: now.addingTimeInterval(-2.5), now: now))
    }

    func testQueriesAreNormalizedSoTheCacheHits() {
        XCTAssertEqual(CoinSearchPolicy.cacheKey(for: "  PePe "), CoinSearchPolicy.cacheKey(for: "pepe"))
    }

    func testTheDebounceIsLongEnoughToCollapseTyping() {
        // Four keystrokes at typing speed must become one request.
        XCTAssertGreaterThanOrEqual(CoinSearchPolicy.debounce, 0.5)
    }
}
