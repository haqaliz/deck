import XCTest

// Phase 3 tests: resolver, converter, builder (partial-failure policy) and
// formatter — the pure MarketBox core.

final class MarketSymbolResolverTests: XCTestCase {
    func testKnownCryptoResolvesToCoinGeckoID() {
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "BTC"), "bitcoin")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "ETH"), "ethereum")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "TON"), "the-open-network")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "USDT"), "tether")
    }

    func testSymbolsAreCaseInsensitive() {
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "btc"), "bitcoin")
        XCTAssertEqual(MarketSymbolResolver.kind(for: "btc"), .crypto)
        XCTAssertEqual(MarketSymbolResolver.kind(for: "gold"), .gold)
        XCTAssertEqual(MarketSymbolResolver.kind(for: "usd"), .fiat)
    }

    func testKinds() {
        XCTAssertEqual(MarketSymbolResolver.kind(for: "BTC"), .crypto)
        XCTAssertEqual(MarketSymbolResolver.kind(for: "GOLD"), .gold)
        XCTAssertEqual(MarketSymbolResolver.kind(for: "CAD"), .fiat)
        XCTAssertNil(MarketSymbolResolver.kind(for: "XRPX"))
    }

    func testNormalizedSymbolsTrimDedupeAndOrder() {
        XCTAssertEqual(
            MarketSymbolResolver.normalizedSymbols(from: "BTC, btc, USD, GOLD , x"),
            ["BTC", "USD", "GOLD", "X"]
        )
        XCTAssertEqual(MarketSymbolResolver.normalizedSymbols(from: ""), [])
        XCTAssertEqual(MarketSymbolResolver.normalizedSymbols(from: " , , "), [])
    }
}

final class MarketConverterTests: XCTestCase {
    private let tmn = 200_000.0

    func testPerUSDInEachDisplayCurrency() {
        XCTAssertEqual(MarketConverter.perUSD(100, display: .usd, tmn: tmn), 100)
        XCTAssertEqual(MarketConverter.perUSD(100, display: .irt, tmn: tmn), 20_000_000)
        XCTAssertEqual(MarketConverter.perUSD(100, display: .irr, tmn: tmn), 200_000_000, "IRR is IRT × 10")
    }

    func testPerUSDFailsWithoutTomanAnchorForIranianCurrencies() {
        XCTAssertNil(MarketConverter.perUSD(100, display: .irt, tmn: nil))
        XCTAssertNil(MarketConverter.perUSD(100, display: .irr, tmn: nil))
    }

    func testUSDollarTickerInEachDisplayCurrency() {
        let fx = ["USD": 1.0]
        XCTAssertEqual(MarketConverter.fiatPrice(code: "USD", display: .usd, tmn: tmn, fx: fx), 1.0)
        XCTAssertEqual(MarketConverter.fiatPrice(code: "USD", display: .irt, tmn: tmn, fx: fx), tmn)
        XCTAssertEqual(MarketConverter.fiatPrice(code: "USD", display: .irr, tmn: tmn, fx: fx), tmn * 10)
    }

    func testCadTickerConvertsThroughTheRate() {
        let fx = ["USD": 1.0, "CAD": 1.378517]
        XCTAssertEqual(MarketConverter.fiatPrice(code: "CAD", display: .usd, tmn: tmn, fx: fx) ?? 0, 1.0 / 1.378517, accuracy: 0.000001)
        XCTAssertEqual(
            MarketConverter.fiatPrice(code: "CAD", display: .irt, tmn: tmn, fx: fx) ?? 0,
            tmn / 1.378517, accuracy: 0.001
        )
    }

    func testMissingRateFailsTheRow() {
        XCTAssertNil(MarketConverter.fiatPrice(code: "CAD", display: .usd, tmn: tmn, fx: ["USD": 1.0]))
        XCTAssertNil(MarketConverter.fiatPrice(code: "CAD", display: .irt, tmn: tmn, fx: [:]))
    }

    func testGoldPerGram() {
        XCTAssertEqual(
            MarketConverter.goldPerGram(usdPerOunce: 4_635.6),
            4_635.6 / MarketConverter.gramsPerTroyOunce, accuracy: 0.0001
        )
    }
}

final class MarketBuilderTests: XCTestCase {
    private let tmn = 200_000.0

    private func quote(_ id: String, symbol: String, name: String, price: Double? = 100, change: Double? = 1.5, sparkline: [Double]? = [1, 2, 3]) -> CryptoQuote {
        CryptoQuote(id: id, symbol: symbol, name: name, priceUSD: price, priceChangePct24h: change, sparkline: sparkline)
    }

    private let quotes: [String: CryptoQuote] = [
        "bitcoin": CryptoQuote(id: "bitcoin", symbol: "btc", name: "Bitcoin", priceUSD: 77_850, priceChangePct24h: 0.85, sparkline: [1, 2, 3]),
        "ethereum": CryptoQuote(id: "ethereum", symbol: "eth", name: "Ethereum", priceUSD: 2_468, priceChangePct24h: 1.66, sparkline: [4, 5, 6]),
    ]

    func testBuildsAllKindsInIrt() {
        let build = MarketBuilder.build(
            display: .irt,
            symbols: ["BTC", "USD", "CAD", "GOLD"],
            quotesByID: quotes,
            tmn: tmn,
            goldUSDPerGram: 149.3,
            fx: ["USD": 1.0, "CAD": 1.378517]
        )
        XCTAssertEqual(build.rows.count, 4)
        XCTAssertEqual(build.rows[0].symbol, "BTC")
        XCTAssertEqual(build.rows[0].price, 77_850 * tmn, accuracy: 0.001)
        XCTAssertEqual(build.rows[0].dayChangePct, 0.85)
        XCTAssertEqual(build.rows[0].sparkline, [1, 2, 3])
        XCTAssertEqual(build.rows[1].symbol, "USD")
        XCTAssertEqual(build.rows[1].price, tmn)
        XCTAssertNil(build.rows[1].dayChangePct, "fiat rows are price-only")
        XCTAssertNil(build.rows[1].sparkline)
        XCTAssertEqual(build.rows[2].symbol, "CAD")
        XCTAssertEqual(build.rows[2].price, tmn / 1.378517, accuracy: 0.001)
        XCTAssertEqual(build.rows[3].symbol, "GOLD")
        XCTAssertEqual(build.rows[3].price, 149.3 * tmn, accuracy: 0.001)
        XCTAssertEqual(build.rows[3].name, "Gold")
        XCTAssertTrue(build.unresolved.isEmpty)
        XCTAssertTrue(build.omitted.isEmpty)
        XCTAssertNil(build.note)
        XCTAssertFalse(build.isEmpty)
    }

    func testUnknownSymbolIsSurfacedNotDropped() {
        let build = MarketBuilder.build(
            display: .usd,
            symbols: ["BTC", "XRPX"],
            quotesByID: quotes,
            tmn: nil,
            goldUSDPerGram: nil,
            fx: nil
        )
        XCTAssertEqual(build.rows.count, 1)
        XCTAssertEqual(build.unresolved, ["XRPX"])
        XCTAssertEqual(build.note, "Unknown: XRPX")
        XCTAssertFalse(build.isEmpty)
    }

    func testMissingGoldOmitsOnlyGold() {
        let build = MarketBuilder.build(
            display: .usd,
            symbols: ["BTC", "GOLD"],
            quotesByID: quotes,
            tmn: nil,
            goldUSDPerGram: nil,
            fx: nil
        )
        XCTAssertEqual(build.rows.map(\.symbol), ["BTC"])
        XCTAssertEqual(build.omitted, ["Gold"])
        XCTAssertEqual(build.note, "Gold unavailable")
        XCTAssertFalse(build.isEmpty)
    }

    func testMissingTomanAnchorFailsEveryRowInIrt() {
        let build = MarketBuilder.build(
            display: .irt,
            symbols: ["BTC", "USD", "GOLD"],
            quotesByID: quotes,
            tmn: nil,
            goldUSDPerGram: 149.3,
            fx: ["USD": 1.0]
        )
        XCTAssertTrue(build.isEmpty, "no row can be priced without the anchor")
        XCTAssertEqual(build.omitted, ["Crypto", "Rates", "Gold"], "kinds collapse to names")
        XCTAssertEqual(build.note, "Crypto unavailable · Rates unavailable · Gold unavailable")
    }

    func testAllUnknownSymbolsIsEmptyWithNoKindOmission() {
        let build = MarketBuilder.build(
            display: .usd,
            symbols: ["XRPX", "FOO"],
            quotesByID: [:],
            tmn: nil,
            goldUSDPerGram: nil,
            fx: nil
        )
        XCTAssertTrue(build.isEmpty)
        XCTAssertEqual(build.unresolved, ["XRPX", "FOO"])
        XCTAssertTrue(build.omitted.isEmpty)
        XCTAssertEqual(build.note, "Unknown: XRPX, FOO")
    }

    func testPartialCryptoFailureNamesTheSymbolNotTheKind() {
        let build = MarketBuilder.build(
            display: .usd,
            symbols: ["BTC", "ETH"],
            quotesByID: ["bitcoin": quotes["bitcoin"]!],
            tmn: nil,
            goldUSDPerGram: nil,
            fx: nil
        )
        XCTAssertEqual(build.rows.map(\.symbol), ["BTC"])
        XCTAssertEqual(build.omitted, ["ETH"], "one crypto worked, so the kind is fine")
    }

    func testEmptyPriceOmitsTheRow() {
        let empty = quote("x", symbol: "x", name: "X", price: nil)
        let build = MarketBuilder.build(
            display: .usd,
            symbols: ["BTC"],
            quotesByID: ["bitcoin": empty],
            tmn: nil,
            goldUSDPerGram: nil,
            fx: nil
        )
        XCTAssertTrue(build.isEmpty)
        XCTAssertEqual(build.omitted, ["Crypto"])
    }
}

final class MarketSparklineTests: XCTestCase {
    func testShortSeriesIsUntouched() {
        XCTAssertEqual(MarketSparkline.downsample([1, 2, 3], maxPoints: 30), [1, 2, 3])
    }

    func testLongSeriesReducesToMaxPoints() {
        let points = (0..<167).map { Double($0) }
        let reduced = MarketSparkline.downsample(points)
        XCTAssertEqual(reduced.count, 30)
        XCTAssertEqual(reduced.last, points.last, "the newest point survives")
        XCTAssertEqual(reduced.first, points.first)
    }

    func testMonotonicSeriesStaysMonotonic() {
        let points = (0..<167).map { Double($0) }
        let reduced = MarketSparkline.downsample(points)
        XCTAssertEqual(reduced, reduced.sorted())
    }
}

final class MarketPriceFormatterTests: XCTestCase {
    func testUsdPricesGetDollarPrefixAndTiers() {
        XCTAssertEqual(MarketPriceFormatter.price(77_850, currency: .usd), "$77,850")
        XCTAssertEqual(MarketPriceFormatter.price(2_468, currency: .usd), "$2,468")
        XCTAssertEqual(MarketPriceFormatter.price(246.87, currency: .usd), "$246.87")
        XCTAssertEqual(MarketPriceFormatter.price(1.38, currency: .usd), "$1.38")
        XCTAssertEqual(MarketPriceFormatter.price(0.9997, currency: .usd), "$0.9997")
    }

    func testIrtPricesAbbreviateWithoutSymbol() {
        XCTAssertEqual(MarketPriceFormatter.price(15_570_000_000, currency: .irt), "15.6B")
        XCTAssertEqual(MarketPriceFormatter.price(201_352, currency: .irt), "201,352")
    }

    func testIrrPricesAbbreviateAtMillion() {
        XCTAssertEqual(MarketPriceFormatter.price(1_523_203, currency: .irr), "1.5M")
    }

    func testChangeSigns() {
        XCTAssertEqual(MarketPriceFormatter.change(1.02), "+1.0%")
        XCTAssertEqual(MarketPriceFormatter.change(-2.4), "-2.4%")
        XCTAssertEqual(MarketPriceFormatter.change(0), "0.0%")
        XCTAssertNil(MarketPriceFormatter.change(nil), "no change for fiat/gold rows")
    }
}