import XCTest

// Markets: the live coin (CoinGecko) and stock (Yahoo) lookups MarketBox's
// picker already uses, reached from the panel with the `mkt ` prefix. Both are
// keyless and share one public-IP budget with the agent (CLAUDE.md), so the
// pacing is the existing `CoinSearchPolicy`'s, not the generic one.

final class SearchTimingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testMarketsUseTheExistingCoinSearchPacing() {
        XCTAssertEqual(SearchProviderID.market.timing.debounce, CoinSearchPolicy.debounce)
        XCTAssertEqual(SearchProviderID.market.timing.floor, CoinSearchPolicy.floor)
        XCTAssertGreaterThan(SearchProviderID.market.timing.floor, RemoteSearchPolicy.sourceFloor)
    }

    func testEverythingElseUsesTheGenericPacing() {
        for s in SearchProviderID.allCases where s != .market {
            XCTAssertEqual(s.timing.debounce, RemoteSearchPolicy.debounce, "\(s)")
            XCTAssertEqual(s.timing.floor, RemoteSearchPolicy.sourceFloor, "\(s)")
        }
    }

    func testSendTimeHonoursAPerSourceDebounceAndFloor() {
        XCTAssertEqual(
            RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: nil, blockedUntil: nil, debounce: 0.6, floor: 2.0),
            t0.addingTimeInterval(0.6))
        let sent = t0.addingTimeInterval(0.1)
        XCTAssertEqual(
            RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: sent, blockedUntil: nil, debounce: 0.6, floor: 2.0),
            sent.addingTimeInterval(2.0))
    }

    func testTheDefaultsAreUnchanged() {
        XCTAssertEqual(RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: nil, blockedUntil: nil),
                       t0.addingTimeInterval(0.3))
    }
}

final class MarketSearchTests: XCTestCase {
    private let btc = CoinSearchHit(coinID: "bitcoin", symbol: "BTC", name: "Bitcoin", rank: 1)
    private let wbtc = CoinSearchHit(coinID: "wrapped-bitcoin", symbol: "WBTC", name: "Wrapped Bitcoin", rank: 14)
    private let aapl = StockSearchHit(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", type: "Equity")
    private let spx = StockSearchHit(symbol: "^GSPC", name: "S&P 500", exchange: "SNP", type: "Index")

    func testCoinsAndStocksBecomeRowsThatOpenTheirPage() throws {
        let rows = MarketSearch.results(coins: [btc], stocks: [aapl])
        let coin = try XCTUnwrap(rows.first { $0.id == "market:coin:bitcoin" })
        XCTAssertEqual(coin.title, "Bitcoin (BTC)")
        XCTAssertEqual(coin.subtitle, "Coin · Rank #1")
        XCTAssertEqual(coin.action, .open(try XCTUnwrap(URL(string: "https://www.coingecko.com/en/coins/bitcoin"))))
        let stock = try XCTUnwrap(rows.first { $0.id == "market:stock:AAPL" })
        XCTAssertEqual(stock.title, "Apple Inc. (AAPL)")
        XCTAssertEqual(stock.subtitle, "Stock · NASDAQ · Equity")
        XCTAssertEqual(stock.action, .open(try XCTUnwrap(URL(string: "https://finance.yahoo.com/quote/AAPL"))))
    }

    func testAnUnrankedCoinHasNoRankInTheSubtitle() {
        let hit = CoinSearchHit(coinID: "x", symbol: "X", name: "X Coin", rank: nil)
        XCTAssertEqual(MarketSearch.results(coins: [hit], stocks: [])[0].subtitle, "Coin")
    }

    func testServerOrderIsKeptWithinEachKind() {
        let coins = MarketSearch.results(coins: [btc, wbtc], stocks: [])
        XCTAssertEqual(SpotlightRanking.sorted(coins).map(\.id), ["market:coin:bitcoin", "market:coin:wrapped-bitcoin"])
    }

    func testKindsInterleaveByPositionNotByKind() {
        let rows = SpotlightRanking.sorted(MarketSearch.results(coins: [btc, wbtc], stocks: [aapl, spx]))
        XCTAssertEqual(rows.first?.id, "market:coin:bitcoin")
        XCTAssertEqual(rows.dropFirst().first?.id, "market:stock:AAPL", "the best stock is not buried under every coin")
    }

    /// A Yahoo symbol like `^GSPC` is a path segment; it must be encoded, and
    /// nothing in it may change the host or add a segment.
    func testPagesAreBuiltOnFixedHostsWithEncodedSegments() throws {
        let index = try XCTUnwrap(MarketSearch.stockURL(symbol: "^GSPC"))
        XCTAssertEqual(index.host, "finance.yahoo.com")
        XCTAssertEqual(index.absoluteString, "https://finance.yahoo.com/quote/%5EGSPC")

        for hostile in ["a/b", "../admin", "x?y=1", "x#frag", "a b", "evil.com/@x", "\\", "%2e%2e"] {
            let coin = try XCTUnwrap(MarketSearch.coinURL(id: hostile), hostile)
            XCTAssertEqual(coin.host, "www.coingecko.com", hostile)
            XCTAssertEqual(coin.pathComponents.count, 4, "\(hostile) added a path segment: \(coin)")  // "/", "en", "coins", id
            XCTAssertNil(coin.query, hostile)
            XCTAssertNil(coin.fragment, hostile)
            let stock = try XCTUnwrap(MarketSearch.stockURL(symbol: hostile), hostile)
            XCTAssertEqual(stock.host, "finance.yahoo.com", hostile)
            XCTAssertEqual(stock.pathComponents.count, 3, "\(hostile) added a path segment: \(stock)")  // "/", "quote", symbol
            XCTAssertNil(stock.query, hostile); XCTAssertNil(stock.fragment, hostile)
        }
        XCTAssertNil(MarketSearch.coinURL(id: ""))
        XCTAssertNil(MarketSearch.stockURL(symbol: ""))
    }

    func testARowWithoutAnIDOrSymbolIsDroppedNotOpened() {
        let rows = MarketSearch.results(coins: [CoinSearchHit(coinID: "", symbol: "X", name: "N", rank: 1)],
                                        stocks: [StockSearchHit(symbol: "", name: "N", exchange: "", type: "")])
        XCTAssertTrue(rows.isEmpty)
    }

    func testTheQueryIsSanitisedAndCappedBeforeItIsSent() {
        XCTAssertEqual(MarketSearch.sanitise("  bit\u{0}coin \n"), "bit coin")
        XCTAssertEqual(MarketSearch.sanitise(String(repeating: "x", count: 500)).count, MarketSearch.maxQueryLength)
    }

    // MARK: merging two independent sources

    func testOneSourceFailingStillShowsTheOther() throws {
        let merged = try MarketSearch.combine(coins: .failure(CoinSearchFailure.rateLimited), stocks: .success([aapl]))
        XCTAssertTrue(merged.coins.isEmpty)
        XCTAssertEqual(merged.stocks, [aapl])
    }

    func testBothFailingThrowsTheFirstReason() {
        XCTAssertThrowsError(try MarketSearch.combine(coins: .failure(CoinSearchFailure.rateLimited),
                                                      stocks: .failure(CoinSearchFailure.offline))) { error in
            XCTAssertEqual(RemoteSearchFailure(error: error), .rateLimited)
        }
    }

    func testASkippedSourceIsNotAFailure() throws {
        let merged = try MarketSearch.combine(coins: nil, stocks: .success([aapl]))
        XCTAssertEqual(merged.stocks, [aapl])
        XCTAssertThrowsError(try MarketSearch.combine(coins: nil, stocks: nil))
    }

    func testCoinSearchFailuresMapToTheirOwnWording() {
        XCTAssertEqual(RemoteSearchFailure(error: CoinSearchFailure.rateLimited), .rateLimited)
        XCTAssertEqual(RemoteSearchFailure(error: CoinSearchFailure.offline), .unreachable)
        XCTAssertEqual(RemoteSearchFailure(error: CoinSearchFailure.badResponse), .badResponse)
    }
}
