import XCTest

/// Phase 1 of `marketbox-stock-search`: the stock picker's data source.
///
/// Probed live 2026-09-15 (`docs/planning/marketbox-stock-search/probe.md`):
/// Yahoo's `/v1/finance/search` is keyless, ~2.5 KB with `newsCount=0`, and a
/// clean 200-with-`count:0` for unknown queries. Its results mix types and
/// exchanges — `q=apple` returns two FUTURE rows and a Toronto listing before
/// the ETF — so the parser drops everything outside EQUITY/INDEX/ETF and the
/// row labels the rest (the interview decision).
private final class StockSearchFixtures {
    static var apple: Data {
        let url = Bundle(for: StockSearchFixtures.self)
            .url(forResource: "yahoo_search_apple", withExtension: "json")!
        return try! Data(contentsOf: url)
    }
}

final class StockSearchParserTests: XCTestCase {

    func testParsesTheLiveFixture() throws {
        let hits = try XCTUnwrap(StockSearchParser.parse(StockSearchFixtures.apple))
        XCTAssertEqual(hits.count, 5)
        XCTAssertEqual(hits.first?.symbol, "AAPL")
        XCTAssertEqual(hits.first?.name, "Apple Inc.")
        XCTAssertEqual(hits.first?.exchange, "NASDAQ")
        XCTAssertEqual(hits.first?.type, "Equity")
    }

    /// The interview decision: FUTURE (and any non EQUITY/INDEX/ETF) rows are
    /// noise and are dropped; the fixture carries two of them before AAPL.
    func testFutureRowsAreDropped() throws {
        let hits = try XCTUnwrap(StockSearchParser.parse(StockSearchFixtures.apple))
        XCTAssertTrue(hits.allSatisfy { !$0.symbol.contains("=") })
        XCTAssertTrue(hits.allSatisfy { !$0.symbol.hasSuffix("F") })
    }

    /// An ETF (AAPX) survives the filter — ETFs are searchable per the
    /// interview — and a REIT that Yahoo returns for the query is kept,
    /// because it *is* an equity and the exchange label makes it honest.
    func testEtfsAndOtherEquitiesSurvive() throws {
        let hits = try XCTUnwrap(StockSearchParser.parse(StockSearchFixtures.apple))
        let symbols = hits.map(\.symbol)
        XCTAssertTrue(symbols.contains("AAPX"))
        XCTAssertTrue(symbols.contains("APLE"))
    }

    /// `/search` is already score-ordered. Server order is preserved rather
    /// than re-sorted — their ordering is not a documented guarantee, so
    /// re-deriving one would be inventing it (the `CoinSearchParser` rule).
    func testServerOrderIsPreserved() throws {
        let hits = try XCTUnwrap(StockSearchParser.parse(StockSearchFixtures.apple))
        XCTAssertEqual(hits.map(\.symbol), ["AAPL", "APLE", "AAPL.TO", "AAPX", "APC.DE"])
    }

    /// A foreign listing (AAPL.TO, Toronto) survives, labelled by its
    /// exchange — "filter the noise, label the rest" means exactly this.
    func testForeignListingsAreKeptAndLabelled() throws {
        let hits = try XCTUnwrap(StockSearchParser.parse(StockSearchFixtures.apple))
        let to = try XCTUnwrap(hits.first { $0.symbol == "AAPL.TO" })
        XCTAssertEqual(to.exchange, "Toronto")
        XCTAssertEqual(to.type, "Equity")
    }

    /// Indices are searchable (`q=^GSPC`), and the leading caret is part of
    /// the raw Yahoo symbol the loader fetches — kept verbatim.
    func testIndexRowsAreKept() throws {
        let json = #"""
        {"quotes":[{"exchange":"SNP","shortname":"S&P 500","quoteType":"INDEX",
        "symbol":"^GSPC","typeDisp":"Index","longname":"S&P 500","exchDisp":"SNP"}]}
        """#
        let hits = try XCTUnwrap(StockSearchParser.parse(Data(json.utf8)))
        XCTAssertEqual(hits.map(\.symbol), ["^GSPC"])
        XCTAssertEqual(hits.first?.type, "Index")
    }

    func testNamePrefersLongnameOverShortname() throws {
        let json = #"""
        {"quotes":[{"exchange":"NMS","shortname":"Short","quoteType":"EQUITY",
        "symbol":"X","typeDisp":"Equity","longname":"Long Name","exchDisp":"NASDAQ"}]}
        """#
        let hits = try XCTUnwrap(StockSearchParser.parse(Data(json.utf8)))
        XCTAssertEqual(hits.first?.name, "Long Name")
    }

    func testAnEntryWithoutASymbolIsDropped() throws {
        let json = #"""
        {"quotes":[{"exchange":"NMS","shortname":"No Symbol","quoteType":"EQUITY",
        "typeDisp":"Equity","exchDisp":"NASDAQ"},{"exchange":"NMS","shortname":"Ok",
        "quoteType":"EQUITY","symbol":"OK","typeDisp":"Equity","exchDisp":"NASDAQ"}]}
        """#
        let hits = try XCTUnwrap(StockSearchParser.parse(Data(json.utf8)))
        XCTAssertEqual(hits.map(\.symbol), ["OK"])
    }

    func testNoMatchesIsAnEmptyListNotAFailure() throws {
        let hits = try XCTUnwrap(StockSearchParser.parse(Data(#"{"quotes":[]}"#.utf8)))
        XCTAssertTrue(hits.isEmpty)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(StockSearchParser.parse(Data("not json".utf8)))
    }

    func testAHitConvertsToATicker() throws {
        let hits = try XCTUnwrap(StockSearchParser.parse(StockSearchFixtures.apple))
        let ticker = try XCTUnwrap(hits.first).ticker
        XCTAssertEqual(ticker.symbol, "AAPL")
        XCTAssertEqual(ticker.stockSymbol, "AAPL")
        XCTAssertEqual(ticker.name, "Apple Inc.")
        XCTAssertEqual(ticker.kind, .stock)
    }
}

/// Phase 2. The loader itself is thin — the parser and policy carry the
/// behaviour — but three of its decisions are worth pinning.
final class HostStockSearchLoaderTests: XCTestCase {

    func testTheURLIsBuiltWithTheSearchParameters() throws {
        let url = try XCTUnwrap(HostStockSearchLoader.url(for: "apple"))
        XCTAssertEqual(
            url.absoluteString,
            "https://query1.finance.yahoo.com/v1/finance/search?q=apple&quotesCount=8&newsCount=0&listsCount=0")
    }

    func testTheQueryIsPercentEncoded() throws {
        let url = try XCTUnwrap(HostStockSearchLoader.url(for: "purple pepe"))
        XCTAssertEqual(url.absoluteString, "https://query1.finance.yahoo.com/v1/finance/search?q=purple%20pepe&quotesCount=8&newsCount=0&listsCount=0")
    }

    func testAnAmpersandCannotInjectAQueryParameter() throws {
        let url = try XCTUnwrap(HostStockSearchLoader.url(for: "a&b=c"))
        XCTAssertFalse(url.absoluteString.contains("&b=c"))
    }

    /// The probe's load-bearing rule: a browser UA earns a host-wide,
    /// minutes-long 429 ban (the chart loader on the same host included),
    /// while `URLSession`'s default UA sails through — and the stock loader
    /// already ships that default. Pinning the absence, not the value, so a
    /// future "helpful" header change fails here.
    func testTheRequestSetsNoUserAgent() throws {
        let request = HostStockSearchLoader.request(for: "apple")
        XCTAssertNil(request?.value(forHTTPHeaderField: "User-Agent"))
    }

    /// 429 is its own outcome, not a server error: it is the one failure the
    /// user can fix by waiting, and the picker says so instead of looking
    /// broken (the `HostCoinSearchLoader` rule).
    func testRateLimitingIsItsOwnOutcome() {
        XCTAssertEqual(HostStockSearchLoader.classify(status: 429), .rateLimited)
        XCTAssertEqual(HostStockSearchLoader.classify(status: 200), .ok)
        XCTAssertEqual(HostStockSearchLoader.classify(status: 500), .serverError(500))
        XCTAssertEqual(HostStockSearchLoader.classify(status: 404), .serverError(404))
    }
}