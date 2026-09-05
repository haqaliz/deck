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
