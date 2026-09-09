import XCTest

// Phase 2 tests: the four MarketBox parsers against live-captured fixtures.

private final class MarketBoxFixtures {
    private static func data(_ name: String) -> Data {
        let url = Bundle(for: MarketBoxFixtures.self).url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    static let coinGeckoMarkets = data("coinGeckoMarkets")
    static let wallexMarkets = data("wallexMarkets")
    static let goldXau = data("goldXau")
    static let erApiLatest = data("erApiLatest")
    static let yahooAAPL = data("yahoo_chart_aapl")
    static let yahooGSPC = data("yahoo_chart_gspc")
    static let yahooUnknown = data("yahoo_chart_unknown")
}

final class CoinGeckoMarketsParserTests: XCTestCase {
    func testParsesLiveFixture() {
        let quotes = CoinGeckoMarketsParser.parse(MarketBoxFixtures.coinGeckoMarkets)
        XCTAssertNotNil(quotes)
        XCTAssertEqual(quotes?.count, 2)
        let bitcoin = quotes?.first
        XCTAssertEqual(bitcoin?.id, "bitcoin")
        XCTAssertEqual(bitcoin?.symbol, "btc")
        XCTAssertEqual(bitcoin?.name, "Bitcoin")
        XCTAssertNotNil(bitcoin?.priceUSD)
        XCTAssertGreaterThan(bitcoin?.priceUSD ?? 0, 50_000)
        XCTAssertNotNil(bitcoin?.priceChangePct24h)
        XCTAssertNotNil(bitcoin?.sparkline)
        XCTAssertEqual(bitcoin?.sparkline?.count, 167, "full 7-day hourly series")
    }

    func testMissingOptionalFieldsParseAsNil() {
        let json = #"[{"id":"x","symbol":"x","name":"X"}]"#
        let quotes = CoinGeckoMarketsParser.parse(json.data(using: .utf8)!)
        XCTAssertNotNil(quotes)
        XCTAssertEqual(quotes?.count, 1)
        XCTAssertNil(quotes?.first?.priceUSD)
        XCTAssertNil(quotes?.first?.priceChangePct24h)
        XCTAssertNil(quotes?.first?.sparkline)
    }

    func testEmptySparklineBecomesNilNotEmptyArray() {
        let json = #"[{"id":"x","symbol":"x","name":"X","sparkline_in_7d":{"price":[]}}]"#
        let quotes = CoinGeckoMarketsParser.parse(json.data(using: .utf8)!)
        XCTAssertNil(quotes?.first?.sparkline)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(CoinGeckoMarketsParser.parse(Data("not json".utf8)))
        XCTAssertNil(CoinGeckoMarketsParser.parse(Data(#"{"a":1}"#.utf8)))
    }
}

final class WallexParserTests: XCTestCase {
    func testParsesLiveFixture() {
        let rate = WallexParser.parse(MarketBoxFixtures.wallexMarkets)
        XCTAssertNotNil(rate)
        XCTAssertNotNil(rate?.tomanPerUSDT)
        XCTAssertGreaterThan(rate?.tomanPerUSDT ?? 0, 100_000)
        XCTAssertNotNil(rate?.change24h)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(WallexParser.parse(Data("not json".utf8)))
        XCTAssertNil(WallexParser.parse(Data(#"{"result":{}}"#.utf8)))
    }
}

final class GoldParserTests: XCTestCase {
    func testParsesLiveFixture() {
        let price = GoldParser.parse(MarketBoxFixtures.goldXau)
        XCTAssertNotNil(price)
        XCTAssertGreaterThan(price ?? 0, 1_000, "USD per troy ounce")
        XCTAssertLessThan(price ?? 0, 100_000)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(GoldParser.parse(Data("not json".utf8)))
        XCTAssertNil(GoldParser.parse(Data(#"{"x":1}"#.utf8)))
    }
}

final class FXRatesParserTests: XCTestCase {
    func testParsesLiveFixture() {
        let rates = FXRatesParser.parse(MarketBoxFixtures.erApiLatest)
        XCTAssertNotNil(rates)
        XCTAssertEqual(rates?.count, 166)
        XCTAssertEqual(rates?["CAD"] ?? 0, 1.378517, accuracy: 0.0001)
        XCTAssertEqual(rates?["IRR"] ?? 0, 1_523_203.229045, accuracy: 0.001)
        XCTAssertEqual(rates?["USD"] ?? 0, 1.0, accuracy: 0.0001)
    }

    func testNonNumericRatesAreDropped() {
        let json = #"{"rates":{"USD":1,"CAD":1.3,"BAD":"x"}}"#
        let rates = FXRatesParser.parse(json.data(using: .utf8)!)
        XCTAssertEqual(rates?.count, 2)
        XCTAssertNil(rates?["BAD"])
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(FXRatesParser.parse(Data("not json".utf8)))
        XCTAssertNil(FXRatesParser.parse(Data(#"{"rates":{}}"#.utf8)), "empty rates is no data")
    }
}

/// Phase 2 of `marketbox-stocks`: the Yahoo v8 chart parser. The payload has
/// three honest states — priced / `Not Found` (a real symbol that has no data)
/// / malformed — because "this symbol is unknown" and "the source is broken"
/// need different words on the face.
final class YahooChartParserTests: XCTestCase {
    func testParsesTheAAPLFixture() {
        guard case .quote(let quote) = YahooChartParser.parse(MarketBoxFixtures.yahooAAPL) else {
            return XCTFail("expected a quote")
        }
        XCTAssertEqual(quote.symbol, "AAPL")
        XCTAssertEqual(quote.name, "Apple Inc.")
        XCTAssertEqual(quote.priceUSD ?? 0, 316.22, accuracy: 0.001)
        XCTAssertEqual(quote.changePct ?? 0, -1.172, accuracy: 0.001)
    }

    func testParsesTheIndexFixture() {
        guard case .quote(let quote) = YahooChartParser.parse(MarketBoxFixtures.yahooGSPC) else {
            return XCTFail("expected a quote")
        }
        XCTAssertEqual(quote.symbol, "^GSPC")
        XCTAssertEqual(quote.name, "S&P 500")
        XCTAssertEqual(quote.priceUSD ?? 0, 7673.52, accuracy: 0.001)
        XCTAssertEqual(quote.changePct ?? 0, -0.584, accuracy: 0.001)
    }

    func testUnknownSymbolIsNoDataNotMalformed() {
        XCTAssertEqual(YahooChartParser.parse(MarketBoxFixtures.yahooUnknown), .noData)
    }

    func testGarbageIsMalformed() {
        XCTAssertEqual(YahooChartParser.parse(Data("not json".utf8)), .malformed)
        XCTAssertEqual(YahooChartParser.parse(Data(#"{"a":1}"#.utf8)), .malformed)
    }

    func testAChartErrorThatIsNotNotFoundIsMalformed() {
        let json = #"{"chart":{"result":null,"error":{"code":"Unauthorized","description":"x"}}}"#
        XCTAssertEqual(YahooChartParser.parse(json.data(using: .utf8)!), .malformed)
    }

    func testMissingPriceStillParsesAsAQuoteWithNilPrice() {
        let json = #"{"chart":{"result":[{"meta":{"symbol":"AAPL","longName":"Apple Inc."}}],"error":null}}"#
        guard case .quote(let quote) = YahooChartParser.parse(json.data(using: .utf8)!) else {
            return XCTFail("expected a quote")
        }
        XCTAssertNil(quote.priceUSD)
        XCTAssertNil(quote.changePct)
    }

    func testLongNameIsPreferredOverShortName() {
        let json = #"{"chart":{"result":[{"meta":{"symbol":"X","longName":"The Long Name","shortName":"X"}}],"error":null}}"#
        guard case .quote(let quote) = YahooChartParser.parse(json.data(using: .utf8)!) else {
            return XCTFail("expected a quote")
        }
        XCTAssertEqual(quote.name, "The Long Name")
    }
}
