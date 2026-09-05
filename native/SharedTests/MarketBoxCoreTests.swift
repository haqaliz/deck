import XCTest

// Phase 3 tests: resolver, converter, builder (partial-failure policy) and
// formatter — the pure MarketBox core.

final class MarketSymbolResolverTests: XCTestCase {
    func testKnownCryptoResolvesToCoinGeckoID() {
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "BTC"), "bitcoin")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "ETH"), "ethereum")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "TON"), "the-open-network")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "USDT"), "tether")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "USDC"), "usd-coin")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "SOL"), "solana")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "PEPE"), "pepe")
        XCTAssertEqual(MarketSymbolResolver.cryptoID(for: "WBTC"), "wrapped-bitcoin")
    }

    /// Every pickable symbol must resolve — the picker list and the loader can
    /// never disagree.
    func testEveryPickableSymbolResolvesToAKind() {
        let symbols = MarketSymbolResolver.allPickableSymbols
        XCTAssertEqual(symbols.count, MarketSymbolResolver.cryptoIDs.count + MarketSymbolResolver.fiatISOs.count + 1)
        XCTAssertTrue(symbols.contains("GOLD"))
        XCTAssertTrue(symbols.contains("USD"))
        for symbol in symbols {
            XCTAssertNotNil(MarketSymbolResolver.kind(for: symbol), "\(symbol) must resolve")
        }
    }

    func testPickerLabels() {
        XCTAssertEqual(MarketSymbolResolver.pickerLabel(for: "BTC"), "BTC — Bitcoin")
        XCTAssertEqual(MarketSymbolResolver.pickerLabel(for: "USD"), "USD — US Dollar")
        XCTAssertEqual(MarketSymbolResolver.pickerLabel(for: "GOLD"), "GOLD — Gold")
        XCTAssertEqual(MarketSymbolResolver.pickerLabel(for: "XRPX"), "XRPX", "unknown falls back to the symbol")
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
        XCTAssertEqual(MarketConverter.perUSD(100, display: .usd, tmn: tmn, fx: nil), 100)
        XCTAssertEqual(MarketConverter.perUSD(100, display: .irt, tmn: tmn, fx: nil), 20_000_000)
        XCTAssertEqual(MarketConverter.perUSD(100, display: .irr, tmn: tmn, fx: nil), 200_000_000, "IRR is IRT × 10")
    }

    func testPerUSDInFiatDisplayCurrencies() {
        let fx = ["USD": 1.0, "CAD": 1.378517, "EUR": 0.92, "AED": 3.6725]
        XCTAssertEqual(MarketConverter.perUSD(100, display: .cad, tmn: nil, fx: fx) ?? 0, 137.8517, accuracy: 0.0001)
        XCTAssertEqual(MarketConverter.perUSD(100, display: .eur, tmn: nil, fx: fx) ?? 0, 92, accuracy: 0.0001)
        XCTAssertEqual(MarketConverter.perUSD(100, display: .aed, tmn: nil, fx: fx) ?? 0, 367.25, accuracy: 0.0001)
    }

    func testPerUSDFailsWithoutTheAnchorItNeeds() {
        XCTAssertNil(MarketConverter.perUSD(100, display: .irt, tmn: nil, fx: nil))
        XCTAssertNil(MarketConverter.perUSD(100, display: .irr, tmn: nil, fx: nil))
        XCTAssertNil(MarketConverter.perUSD(100, display: .cad, tmn: nil, fx: nil), "no FX rates, no CAD price")
        XCTAssertNil(MarketConverter.perUSD(100, display: .cad, tmn: nil, fx: ["USD": 1.0]), "no CAD rate, no CAD price")
    }

    func testUSDollarTickerInEachDisplayCurrency() {
        let fx = ["USD": 1.0, "CAD": 1.378517]
        XCTAssertEqual(MarketConverter.fiatPrice(code: "USD", display: .usd, tmn: tmn, fx: fx), 1.0)
        XCTAssertEqual(MarketConverter.fiatPrice(code: "USD", display: .irt, tmn: tmn, fx: fx), tmn)
        XCTAssertEqual(MarketConverter.fiatPrice(code: "USD", display: .irr, tmn: tmn, fx: fx), tmn * 10)
        XCTAssertEqual(MarketConverter.fiatPrice(code: "USD", display: .cad, tmn: tmn, fx: fx) ?? 0, 1.378517, accuracy: 0.0001, "a dollar costs 1.378 CAD")
    }

    func testCadTickerConvertsThroughTheRate() {
        let fx = ["USD": 1.0, "CAD": 1.378517]
        XCTAssertEqual(MarketConverter.fiatPrice(code: "CAD", display: .usd, tmn: tmn, fx: fx) ?? 0, 1.0 / 1.378517, accuracy: 0.000001)
        XCTAssertEqual(
            MarketConverter.fiatPrice(code: "CAD", display: .irt, tmn: tmn, fx: fx) ?? 0,
            tmn / 1.378517, accuracy: 0.001
        )
        XCTAssertEqual(
            MarketConverter.fiatPrice(code: "CAD", display: .cad, tmn: tmn, fx: fx) ?? 0,
            1.0, accuracy: 0.000001, "a Canadian dollar is 1 CAD in a CAD display"
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
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC", "USD", "CAD", "GOLD"]),
            quotesByID: quotes,
            tmn: tmn,
            goldUSDPerGram: 149.3,
            fx: ["USD": 1.0, "CAD": 1.378517]
        )
        XCTAssertEqual(build.rows.count, 4)
        XCTAssertEqual(build.rows[0].symbol, "BTC")
        XCTAssertEqual(build.rows[0].price, 77_850 * tmn, accuracy: 0.001)
        XCTAssertEqual(build.rows[0].dayChangePct, 0.85)
        XCTAssertEqual(build.rows[1].symbol, "USD")
        XCTAssertEqual(build.rows[1].price, tmn)
        XCTAssertNil(build.rows[1].dayChangePct, "fiat rows are price-only")
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

    func testBuildsInCadDisplayWithoutToman() {
        let build = MarketBuilder.build(
            display: .cad,
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC", "USD", "CAD", "GOLD"]),
            quotesByID: quotes,
            tmn: nil,
            goldUSDPerGram: 149.3,
            fx: ["USD": 1.0, "CAD": 1.378517]
        )
        XCTAssertEqual(build.rows.count, 4)
        XCTAssertEqual(build.rows[0].price, 77_850 * 1.378517, accuracy: 0.001)
        XCTAssertEqual(build.rows[1].price, 1.378517, accuracy: 0.0001, "a dollar costs 1.378 CAD")
        XCTAssertEqual(build.rows[2].price, 1.0, accuracy: 0.0001, "a CAD costs 1 CAD")
        XCTAssertEqual(build.rows[3].price, 149.3 * 1.378517, accuracy: 0.001)
        XCTAssertNil(build.note)
    }

    func testCadDisplayWithoutFxFailsEveryRow() {
        let build = MarketBuilder.build(
            display: .cad,
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC", "USD", "GOLD"]),
            quotesByID: quotes,
            tmn: tmn,
            goldUSDPerGram: 149.3,
            fx: nil
        )
        XCTAssertTrue(build.isEmpty)
        XCTAssertEqual(build.omitted, ["Crypto", "Rates", "Gold"])
    }

    func testUnknownSymbolIsSurfacedNotDropped() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC", "XRPX"]),
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
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC", "GOLD"]),
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
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC", "USD", "GOLD"]),
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
            tickers: MarketTickerMigration.tickers(fromSymbols: ["XRPX", "FOO"]),
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

    /// One crypto worked, so the kind is fine and the missing one is named.
    /// Since `marketbox-coin-lookup` it is named as **no data** rather than
    /// unavailable: the fetch plainly succeeded, so the source answering
    /// nothing about this id is a fact about the coin, not about the source.
    func testPartialCryptoMissNamesTheSymbolAsNoData() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC", "ETH"]),
            quotesByID: ["bitcoin": quotes["bitcoin"]!],
            tmn: nil,
            goldUSDPerGram: nil,
            fx: nil
        )
        XCTAssertEqual(build.rows.map(\.symbol), ["BTC"])
        XCTAssertEqual(build.noData, ["ETH"])
        XCTAssertTrue(build.omitted.isEmpty, "one crypto worked, so the kind is fine")
        XCTAssertEqual(build.note, "No data: ETH")
    }

    func testEmptyPriceOmitsTheRow() {
        let empty = quote("x", symbol: "x", name: "X", price: nil)
        let build = MarketBuilder.build(
            display: .usd,
            tickers: MarketTickerMigration.tickers(fromSymbols: ["BTC"]),
            quotesByID: ["bitcoin": empty],
            tmn: nil,
            goldUSDPerGram: nil,
            fx: nil
        )
        XCTAssertTrue(build.isEmpty)
        XCTAssertEqual(build.omitted, ["Crypto"])
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
// MARK: - Phase 2 of marketbox-coin-lookup

/// The builder stops resolving symbols through the curated table, and learns to
/// tell "the crypto source is down" from "this coin has no data".
final class MarketBuilderTickerTests: XCTestCase {
    private let quotes: [String: CryptoQuote] = [
        "bitcoin": CryptoQuote(id: "bitcoin", symbol: "btc", name: "Bitcoin", priceUSD: 77_850, priceChangePct24h: 0.85, sparkline: nil),
        "purple-pepe": CryptoQuote(id: "purple-pepe", symbol: "purpe", name: "PURPLE PEPE", priceUSD: 1.752e-05, priceChangePct24h: -3.0, sparkline: nil),
    ]

    private func ticker(_ symbol: String, _ coinID: String) -> MarketTicker {
        MarketTicker(symbol: symbol, name: "", coinID: coinID)
    }

    /// The C2 regression: a coin outside the curated 43 must price. Keyed on
    /// symbols, `MarketSymbolResolver.kind(for: "PURPE")` answers nil and the
    /// whole feature renders "Unknown: PURPE" with no price.
    func testACoinOutsideTheCuratedTablePrices() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: [ticker("PURPE", "purple-pepe")],
            quotesByID: quotes,
            tmn: nil, goldUSDPerGram: nil, fx: nil
        )
        XCTAssertEqual(build.rows.map(\.symbol), ["PURPE"])
        XCTAssertEqual(build.rows.first?.price, 1.752e-05)
        XCTAssertTrue(build.unresolved.isEmpty)
        XCTAssertNil(build.note)
    }

    /// State 1 of 3: no crypto tickers at all. Says nothing about crypto.
    func testNoCryptoTickersSaysNothingAboutCrypto() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: [ticker("USD", "")],
            quotesByID: [:],
            tmn: nil, goldUSDPerGram: nil, fx: ["USD": 1.0]
        )
        XCTAssertEqual(build.rows.map(\.symbol), ["USD"])
        XCTAssertNil(build.note, "a USD+GOLD user must not be told crypto is unavailable")
    }

    /// State 2 of 3: the fetch was attempted and failed.
    func testAFailedCryptoFetchReadsAsUnavailable() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: [ticker("BTC", "bitcoin")],
            quotesByID: nil,
            tmn: nil, goldUSDPerGram: nil, fx: nil
        )
        XCTAssertTrue(build.isEmpty)
        XCTAssertEqual(build.omitted, ["Crypto"])
        XCTAssertEqual(build.note, "Crypto unavailable")
    }

    /// State 3 of 3: the fetch succeeded and CoinGecko simply did not return
    /// this id — measured, it drops unknown ids silently with a 200.
    func testAnIDTheSourceDidNotReturnReadsAsNoData() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: [ticker("BTC", "bitcoin"), ticker("DEAD", "dead-coin")],
            quotesByID: quotes,
            tmn: nil, goldUSDPerGram: nil, fx: nil
        )
        XCTAssertEqual(build.rows.map(\.symbol), ["BTC"])
        XCTAssertEqual(build.noData, ["DEAD"])
        XCTAssertEqual(build.note, "No data: DEAD")
        XCTAssertFalse(build.isEmpty)
    }

    /// A retired id must not be folded into the "every crypto failed" collapse
    /// — the two sentences mean different things and have different fixes.
    func testNoDataIsNotCollapsedIntoCryptoUnavailable() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: [ticker("DEAD", "dead-coin")],
            quotesByID: quotes,
            tmn: nil, goldUSDPerGram: nil, fx: nil
        )
        XCTAssertEqual(build.noData, ["DEAD"])
        XCTAssertTrue(build.omitted.isEmpty)
        XCTAssertEqual(build.note, "No data: DEAD")
    }

    func testATickerWithNoKindIsStillUnknown() {
        let build = MarketBuilder.build(
            display: .usd,
            tickers: [ticker("XRPX", "")],
            quotesByID: quotes,
            tmn: nil, goldUSDPerGram: nil, fx: nil
        )
        XCTAssertEqual(build.unresolved, ["XRPX"])
        XCTAssertEqual(build.note, "Unknown: XRPX")
    }
}

/// What the loader asks for, decided without touching the network.
final class MarketFetchPlanTests: XCTestCase {
    private func ticker(_ symbol: String, _ coinID: String) -> MarketTicker {
        MarketTicker(symbol: symbol, name: "", coinID: coinID)
    }

    /// Measured 2026-09-05: `coins/markets?ids=` with an empty list answers
    /// **200 with the top 100 coins (83.6 KB)** — not an error, not an empty
    /// list. It would render as the user's list, so the request must never be
    /// built.
    func testNoCryptoTickersAsksForNothing() {
        let ids = MarketFetchPlan.cryptoIDs(for: [ticker("USD", ""), ticker("GOLD", "")])
        XCTAssertTrue(ids.isEmpty)
    }

    func testABlankCoinIDNeverReachesTheQuery() {
        let ids = MarketFetchPlan.cryptoIDs(for: [ticker("BTC", "bitcoin"), ticker("ODD", "   ")])
        XCTAssertEqual(ids, ["bitcoin"])
    }

    func testIDsAreDedupedAndOrdered() {
        let ids = MarketFetchPlan.cryptoIDs(for: [
            ticker("BTC", "bitcoin"), ticker("ETH", "ethereum"), ticker("BTC2", "bitcoin"),
        ])
        XCTAssertEqual(ids, ["bitcoin", "ethereum"])
    }
}

/// Phase 3 of `marketbox-coin-lookup`. `%.4f` below 1.0 printed `$0.0000` for
/// three symbols **already in the shipped curated list** — measured live on
/// 2026-09-05 — so a 50% move rendered identically to no move. Widening the
/// catalogue to 19,594 coins makes sub-cent the norm rather than the edge.
final class MarketSubCentPriceTests: XCTestCase {
    private func usd(_ v: Double) -> String { MarketPriceFormatter.price(v, currency: .usd) }

    func testTheThreeShippedTickersThatRenderedAsZero() {
        XCTAssertEqual(usd(5.47e-06), "$0.00000547", "SHIB")
        XCTAssertEqual(usd(3.57e-06), "$0.00000357", "PEPE")
        XCTAssertEqual(usd(3.27e-06), "$0.00000327", "BONK")
    }

    func testThreeSignificantDigitsWithNoTrailingZeros() {
        XCTAssertEqual(usd(1.752e-05), "$0.0000175")
        XCTAssertEqual(usd(0.005), "$0.005")
    }

    func testVerySmallPricesGoExponentialRatherThanPrintingZeros() {
        // Thirteen leading zeros do not fit a widget row.
        XCTAssertEqual(usd(5.5e-11), "$5.5e-11")
    }

    func testTheBoundariesHoldOnBothSides() {
        XCTAssertEqual(usd(0.01), "$0.0100", "the >= 0.01 branch is untouched")
        XCTAssertEqual(usd(1e-9), "$0.000000001")
    }

    func testZeroIsNotExponential() {
        XCTAssertEqual(usd(0), "$0.00")
    }

    func testLargeValuesAreUnchanged() {
        XCTAssertEqual(usd(77_850), "$77,850")
        XCTAssertEqual(usd(1.757e+09), "$1.8B")
        XCTAssertEqual(usd(2_468), "$2,468")
        XCTAssertEqual(usd(1.75), "$1.75")
    }

    func testTheCurrencyPrefixStillOnlyAppliesToUsd() {
        XCTAssertEqual(MarketPriceFormatter.price(5.47e-06, currency: .irt), "0.00000547")
    }
}
