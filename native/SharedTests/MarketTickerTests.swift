import XCTest

/// Phase 1 of `marketbox-coin-lookup`: settings stop holding a bare symbol and
/// start holding the CoinGecko id, so the picker becomes the only thing that
/// resolves and the widget stops being capped at the curated 43.
///
/// The migration must never lose someone's list — a symbol the curated table
/// does not know survives with an empty `coinID` and still renders as
/// `Unknown: X`, exactly as it does today.
final class MarketTickerTests: XCTestCase {

    // MARK: - The model

    func testKindIsDerivedFromTheCoinIDNotStored() {
        XCTAssertEqual(MarketTicker(symbol: "BTC", name: "Bitcoin", coinID: "bitcoin").kind, .crypto)
        XCTAssertEqual(MarketTicker(symbol: "GOLD", name: "Gold", coinID: "").kind, .gold)
        XCTAssertEqual(MarketTicker(symbol: "USD", name: "US Dollar", coinID: "").kind, .fiat)
    }

    func testACoinOutsideTheCuratedTableIsStillCrypto() {
        // The whole point: PURPE is not in `cryptoIDs`, and must not read as
        // "unknown" the way `MarketSymbolResolver.kind(for:)` would answer.
        let ticker = MarketTicker(symbol: "PURPE", name: "PURPLE PEPE", coinID: "purple-pepe")
        XCTAssertEqual(ticker.kind, .crypto)
    }

    // MARK: - Migration from the shipped shapes

    func testMigratesCuratedSymbolsToIDsAndNames() {
        let tickers = MarketTickerMigration.tickers(fromSymbols: ["BTC", "ETH"])
        XCTAssertEqual(tickers.map(\.symbol), ["BTC", "ETH"])
        XCTAssertEqual(tickers.map(\.coinID), ["bitcoin", "ethereum"])
        XCTAssertEqual(tickers.map(\.name), ["Bitcoin", "Ethereum"])
    }

    func testMigratesFiatAndGoldWithNoCoinID() {
        let tickers = MarketTickerMigration.tickers(fromSymbols: ["USD", "GOLD"])
        XCTAssertEqual(tickers.map(\.coinID), ["", ""])
        XCTAssertEqual(tickers.map(\.kind), [.fiat, .gold])
        XCTAssertEqual(tickers.map(\.name), ["US Dollar", "Gold"])
    }

    func testAnUnknownSymbolSurvivesTheMigrationWithNoID() {
        // From the free-text era. Losing it silently would be worse than
        // carrying it as unresolvable.
        let tickers = MarketTickerMigration.tickers(fromSymbols: ["XRPX"])
        XCTAssertEqual(tickers.map(\.symbol), ["XRPX"])
        XCTAssertEqual(tickers.first?.coinID, "")
        XCTAssertNil(tickers.first?.kind)
    }

    // MARK: - Decode: four steps, in order

    private func decode(_ json: String) throws -> MarketBoxSettings {
        try JSONDecoder().decode(MarketBoxSettings.self, from: Data(json.utf8))
    }

    func testTickerListWinsOverTheLegacyArray() throws {
        let s = try decode("""
        {"tickerList":[{"symbol":"SUI","name":"Sui","coinID":"sui"}],
         "tickers":["BTC","ETH"]}
        """)
        XCTAssertEqual(s.tickerList.map(\.symbol), ["SUI"])
    }

    func testLegacyArrayMigratesWhenThereIsNoTickerList() throws {
        let s = try decode(#"{"tickers":["BTC","USD"]}"#)
        XCTAssertEqual(s.tickerList.map(\.symbol), ["BTC", "USD"])
        XCTAssertEqual(s.tickerList.map(\.coinID), ["bitcoin", ""])
    }

    func testLegacyFreeTextStringStillMigrates() throws {
        let s = try decode(#"{"symbols":"btc, eth"}"#)
        XCTAssertEqual(s.tickerList.map(\.symbol), ["BTC", "ETH"])
        XCTAssertEqual(s.tickerList.map(\.coinID), ["bitcoin", "ethereum"])
    }

    func testAFileWithNoTickerKeyAtAllKeepsTheDefaults() throws {
        let s = try decode("{}")
        XCTAssertEqual(s.tickerList.map(\.symbol), ["BTC", "ETH", "USD", "GOLD"])
    }

    // MARK: - List rules

    func testOneSymbolOneRow() {
        // The face draws `Text(row.symbol)` and nothing else, so two rows
        // reading "PEPE" would be indistinguishable. Identity is the coinID;
        // the symbol is what makes it unique in a list.
        let list = MarketBoxSettings.normalized([
            MarketTicker(symbol: "PEPE", name: "Pepe", coinID: "pepe"),
            MarketTicker(symbol: "PEPE", name: "PepeCoin", coinID: "pepecoin-2"),
        ])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.coinID, "pepe")
    }

    func testTheListIsCappedAtTwelve() {
        let many = (1...20).map { MarketTicker(symbol: "C\($0)", name: "", coinID: "c\($0)") }
        XCTAssertEqual(MarketBoxSettings.normalized(many).count, MarketBoxSettings.maxCount)
    }

    func testSymbolsAreUppercasedAndTrimmed() {
        let list = MarketBoxSettings.normalized([
            MarketTicker(symbol: " btc ", name: "Bitcoin", coinID: "bitcoin"),
        ])
        XCTAssertEqual(list.map(\.symbol), ["BTC"])
    }

    /// The list actually in the installed container on 2026-09-05 — mixed
    /// fiat, crypto and gold. A regression pin for the shape real upgrades
    /// will hit, not a new behaviour (the generic cases above cover the rule).
    func testTheInstalledListMigratesIntact() throws {
        let s = try decode(#"{"tickers":["CAD","ETH","USD","GOLD","AED"]}"#)
        XCTAssertEqual(s.tickerList.map(\.symbol), ["CAD", "ETH", "USD", "GOLD", "AED"])
        XCTAssertEqual(s.tickerList.map(\.coinID), ["", "ethereum", "", "", ""])
        XCTAssertEqual(s.tickerList.map(\.kind), [.fiat, .crypto, .fiat, .gold, .fiat])
    }

    // MARK: - Tolerance

    /// A hand-edited or newer-build entry must not throw: a throw inside
    /// `MarketBoxSettings.init(from:)` reaches `DeckSettings.load()`, which
    /// falls back to a blank `DeckSettings()` on any decode error and resets
    /// every setting in the file.
    func testATickerMissingItsNameDecodesRatherThanThrowing() throws {
        let s = try decode(#"{"tickerList":[{"symbol":"SUI","coinID":"sui"}]}"#)
        XCTAssertEqual(s.tickerList.map(\.symbol), ["SUI"])
        XCTAssertEqual(s.tickerList.first?.name, "")
    }

    func testATickerWithOnlyASymbolDecodesAsUnresolvable() throws {
        let s = try decode(#"{"tickerList":[{"symbol":"XRPX"}]}"#)
        XCTAssertEqual(s.tickerList.first?.coinID, "")
        XCTAssertNil(s.tickerList.first?.kind)
    }

    /// An entry with no symbol at all cannot be displayed or priced, so it is
    /// dropped rather than kept as a blank row.
    func testAnEntryWithNoSymbolIsDropped() throws {
        let s = try decode(#"{"tickerList":[{"coinID":"sui"},{"symbol":"BTC","coinID":"bitcoin"}]}"#)
        XCTAssertEqual(s.tickerList.map(\.symbol), ["BTC"])
    }

    // MARK: - Encoding

    /// `MarketBoxSettings` has a hand-written `encode(to:)` *and* hand-written
    /// `CodingKeys`. A missing case in either compiles, decodes as absent and
    /// never encodes — every ticker would vanish on the next keystroke.
    func testTickerListSurvivesARoundTrip() throws {
        var settings = MarketBoxSettings()
        settings.tickerList = [MarketTicker(symbol: "SUI", name: "Sui", coinID: "sui")]

        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(MarketBoxSettings.self, from: data)

        XCTAssertEqual(back.tickerList, settings.tickerList)
    }

    /// A downgrade must cost the MarketBox list alone. Writing the new list
    /// under the *old* key would make an older Deck throw inside
    /// `init(from:)`, and `DeckSettings.load()` falls back to a blank
    /// `DeckSettings()` on any decode error — resetting every setting.
    func testTheLegacyTickersKeyIsNotWritten() throws {
        var settings = MarketBoxSettings()
        settings.tickerList = [MarketTicker(symbol: "BTC", name: "Bitcoin", coinID: "bitcoin")]

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["tickerList"])
        XCTAssertNil(object["tickers"])
        XCTAssertNil(object["symbols"])
    }
}

/// Phase 1 of `marketbox-stocks`: a ticker can be a stock. Identity is the
/// Yahoo symbol (`^GSPC`); the display symbol (`SPX`) is what the face draws;
/// `kind` derives `.stock` from the Yahoo symbol, never stored.
final class MarketStockTickerTests: XCTestCase {

    // MARK: - The model

    func testStockKindDerivesFromTheStockSymbol() {
        let ticker = MarketTicker(symbol: "SPX", name: "S&P 500", coinID: "", stockSymbol: "^GSPC")
        XCTAssertEqual(ticker.kind, .stock)
    }

    func testCoinIDWinsOverStockSymbol() {
        // Defensive: a row carrying both must price as a coin, never as a
        // stock — one symbol, one row.
        let ticker = MarketTicker(symbol: "SOL", name: "Solana", coinID: "solana", stockSymbol: "SOL")
        XCTAssertEqual(ticker.kind, .crypto)
    }

    func testDisplaySymbolAndFetchSymbolAreSeparate() {
        let ticker = MarketTicker(symbol: "SPX", name: "S&P 500", coinID: "", stockSymbol: "^GSPC")
        XCTAssertEqual(ticker.symbol, "SPX")
        XCTAssertEqual(ticker.stockSymbol, "^GSPC")
    }

    func testACryptoTickerWithoutStockSymbolIsUnchanged() {
        XCTAssertEqual(MarketTicker(symbol: "BTC", name: "Bitcoin", coinID: "bitcoin").stockSymbol, "")
        XCTAssertEqual(MarketTicker(symbol: "BTC", name: "Bitcoin", coinID: "bitcoin").kind, .crypto)
    }

    // MARK: - Catalog

    func testStockCatalogHasNoDuplicateDisplaySymbols() {
        let symbols = MarketSymbolResolver.stockCatalog.map(\.displaySymbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "one display symbol, one row — a duplicate would be refused out loud at add time")
    }

    func testStockCatalogHasNoDuplicateYahooSymbols() {
        let symbols = MarketSymbolResolver.stockCatalog.map(\.yahooSymbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }

    func testStockCatalogDisplaySymbolsDoNotCollideWithCryptoMigrationTable() {
        // A stock whose display symbol collides with a coin would be refused
        // out loud by `MarketTickerList.adding` — correct behaviour, but the
        // catalog should not invite the confusion.
        let coins = Set(MarketSymbolResolver.cryptoIDs.keys)
        let stocks = MarketSymbolResolver.stockCatalog.map(\.displaySymbol)
        XCTAssertTrue(Set(stocks).isDisjoint(with: coins))
    }

    func testStockCatalogHasTheExpectedIndices() {
        let spx = MarketSymbolResolver.stockCatalog.first { $0.displaySymbol == "SPX" }
        XCTAssertEqual(spx?.yahooSymbol, "^GSPC")
        XCTAssertEqual(spx?.name, "S&P 500")
        let vix = MarketSymbolResolver.stockCatalog.first { $0.displaySymbol == "VIX" }
        XCTAssertEqual(vix?.yahooSymbol, "^VIX")
    }

    func testStockCatalogIsNonEmpty() {
        XCTAssertGreaterThan(MarketSymbolResolver.stockCatalog.count, 10)
    }

    // MARK: - Decode & encode

    func testStockSymbolSurvivesARoundTrip() throws {
        var settings = MarketBoxSettings()
        settings.tickerList = [MarketTicker(symbol: "SPX", name: "S&P 500", coinID: "", stockSymbol: "^GSPC")]

        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(MarketBoxSettings.self, from: data)

        XCTAssertEqual(back.tickerList, settings.tickerList)
        XCTAssertEqual(back.tickerList.first?.stockSymbol, "^GSPC")
    }

    func testAStockDecodesWhenTheKeyIsAbsent() throws {
        // A file written by an older Deck has no `stockSymbol`; it must decode
        // to an empty string, not throw (a throw resets every setting).
        let s = try JSONDecoder().decode(MarketBoxSettings.self, from: Data(#"{"tickerList":[{"symbol":"SPX","name":"S&P 500","coinID":""}]}"#.utf8))
        XCTAssertEqual(s.tickerList.first?.stockSymbol, "")
    }
}

/// Phase 6. The add/remove list replaces twelve numbered slots, which gave
/// display order for free — so ordering, the cap and the duplicate rule all
/// become explicit operations. Pure, so the view stays layout only.
final class MarketTickerListTests: XCTestCase {
    private func ticker(_ symbol: String, _ coinID: String = "") -> MarketTicker {
        MarketTicker(symbol: symbol, name: symbol, coinID: coinID)
    }

    // MARK: - Adding

    func testAddingAppendsToTheEnd() {
        let result = MarketTickerList.adding(ticker("SUI", "sui"), to: [ticker("BTC", "bitcoin")])
        XCTAssertEqual(result, .added([ticker("BTC", "bitcoin"), ticker("SUI", "sui")]))
    }

    /// One symbol, one row — the face draws `Text(row.symbol)` alone, so two
    /// PEPEs would be indistinguishable. Refused out loud, never dropped
    /// silently the way the old `normalized` would have.
    func testASecondCoinWithTheSameSymbolIsRefusedByName() {
        let existing = [MarketTicker(symbol: "PEPE", name: "Pepe", coinID: "pepe")]
        let other = MarketTicker(symbol: "PEPE", name: "PepeCoin", coinID: "pepecoin-2")
        XCTAssertEqual(MarketTickerList.adding(other, to: existing), .duplicate("PEPE"))
    }

    func testTheDuplicateCheckIgnoresCase() {
        let existing = [ticker("BTC", "bitcoin")]
        let lower = MarketTicker(symbol: "btc", name: "Bitcoin", coinID: "bitcoin")
        XCTAssertEqual(MarketTickerList.adding(lower, to: existing), .duplicate("BTC"))
    }

    func testAddingAtTheCapIsRefused() {
        let full = (1...MarketBoxSettings.maxCount).map { ticker("C\($0)", "c\($0)") }
        XCTAssertEqual(MarketTickerList.adding(ticker("SUI", "sui"), to: full), .full)
    }

    // MARK: - Ordering (order is display order)

    func testMovingUpSwapsWithThePreviousRow() {
        let list = [ticker("A"), ticker("B"), ticker("C")]
        XCTAssertEqual(MarketTickerList.moved(list, at: 2, by: -1).map(\.symbol), ["A", "C", "B"])
    }

    func testMovingDownSwapsWithTheNextRow() {
        let list = [ticker("A"), ticker("B"), ticker("C")]
        XCTAssertEqual(MarketTickerList.moved(list, at: 0, by: 1).map(\.symbol), ["B", "A", "C"])
    }

    func testMovingOffEitherEndIsANoOp() {
        let list = [ticker("A"), ticker("B")]
        XCTAssertEqual(MarketTickerList.moved(list, at: 0, by: -1).map(\.symbol), ["A", "B"])
        XCTAssertEqual(MarketTickerList.moved(list, at: 1, by: 1).map(\.symbol), ["A", "B"])
    }

    func testMovingAnOutOfRangeIndexIsANoOp() {
        let list = [ticker("A")]
        XCTAssertEqual(MarketTickerList.moved(list, at: 7, by: -1).map(\.symbol), ["A"])
    }

    // MARK: - Removing

    func testRemovingTakesTheRowOut() {
        let list = [ticker("A"), ticker("B")]
        XCTAssertEqual(MarketTickerList.removing(at: 0, from: list).map(\.symbol), ["B"])
    }

    /// Emptying the list is allowed — the loader throws `notConfigured` for it,
    /// which is the honest "nothing is set up" state, not a crash.
    func testTheListCanBeEmptied() {
        XCTAssertTrue(MarketTickerList.removing(at: 0, from: [ticker("A")]).isEmpty)
    }

    func testRemovingAnOutOfRangeIndexIsANoOp() {
        let list = [ticker("A")]
        XCTAssertEqual(MarketTickerList.removing(at: 9, from: list).map(\.symbol), ["A"])
    }
}
