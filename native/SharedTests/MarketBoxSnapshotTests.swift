import XCTest

// Phase 1 tests: MarketBoxSettings tolerant decode and the snapshot round-trip.

private func decode<T: Decodable>(_ json: String, as _: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

final class MarketBoxSettingsDecodeTests: XCTestCase {
    func testEmptyFixtureDecodesAllDefaults() throws {
        let s = try decode(#"{}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s, MarketBoxSettings())
        XCTAssertEqual(s.tickers, ["BTC", "ETH", "USD", "GOLD"])
        XCTAssertEqual(s.displayCurrency, .usd)
        XCTAssertEqual(s.tickerCount, 8)
        XCTAssertTrue(s.showDayChange)
    }

    func testPartialFixtureKeepsDefaults() throws {
        let s = try decode(#"{"tickers":["BTC","CAD"],"displayCurrency":"irt","tickerCount":5}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.tickers, ["BTC", "CAD"])
        XCTAssertEqual(s.displayCurrency, .irt)
        XCTAssertEqual(s.tickerCount, 5)
        XCTAssertEqual(s.upColor, RGBA.systemGreen, "absent colors keep defaults")
        XCTAssertEqual(s.downColor, RGBA.systemRed)
    }

    /// The widget shipped with a comma-separated free-text field; a file that
    /// predates the picker keeps its list.
    func testLegacySymbolsStringMigratesToTickers() throws {
        let s = try decode(#"{"symbols":"btc, ETH, GOLD , ,x"}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.tickers, ["BTC", "ETH", "GOLD", "X"])
    }

    /// Hand-edited files must not duplicate, over-cap, or lowercase the list.
    func testTickersAreNormalized() throws {
        let many = ["btc", "BTC", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        let s = try decode(#"{"tickers": \#(manyJSON(many))}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.tickers.count, MarketBoxSettings.maxCount)
        XCTAssertEqual(s.tickers.first, "BTC")
        XCTAssertFalse(s.tickers.contains("btc"), "duplicates collapse")
    }

    /// A hand-edited file must not push more rows into the face than it can
    /// lay out, and a zero must not hide the list entirely.
    func testTickerCountIsClamped() throws {
        let high = try decode(#"{"tickerCount":99}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(high.tickerCount, MarketBoxSettings.maxCount)
        let low = try decode(#"{"tickerCount":0}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(low.tickerCount, 1)
    }

    func testUnknownFutureFieldIsIgnored() throws {
        let s = try decode(#"{"tickers":["ETH"],"somethingNew":true}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.tickers, ["ETH"])
    }

    /// A currency this build doesn't know (written by a newer build) falls back
    /// to USD rather than failing the whole section.
    func testUnknownDisplayCurrencyFallsBackToUsd() throws {
        let s = try decode(#"{"displayCurrency":"xxx"}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.displayCurrency, .usd)
    }

    /// The one-way migration: encoding writes only the current shape. Both
    /// older shapes — the `symbols` free-text string and the `tickers` symbol
    /// array — are read on the way in and dropped on the way out.
    func testEncodeDropsBothLegacyTickerKeys() throws {
        let s = try decode(#"{"symbols":"BTC, ETH"}"#, as: MarketBoxSettings.self)
        let data = try JSONEncoder().encode(s)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"tickerList\""))
        XCTAssertFalse(json.contains("\"tickers\""))
        XCTAssertFalse(json.contains("\"symbols\""))
    }

    func testDeckSettingsWithoutMarketBoxSectionStillLoads() throws {
        let s = try decode(#"{"shipbox":{"repo":"a/b"}}"#, as: DeckSettings.self)
        XCTAssertEqual(s.shipbox.repos, ["a/b"])
        XCTAssertEqual(s.marketbox, MarketBoxSettings())
    }

    private func manyJSON(_ symbols: [String]) -> String {
        "[" + symbols.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}

final class MarketBoxSnapshotTests: XCTestCase {
    func testRoundTripPreservesAllFields() throws {
        let snapshot = MarketSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            displayCurrency: .irt,
            rows: [
                MarketRow(symbol: "BTC", name: "Bitcoin", kind: .crypto, price: 15_500_000_000, dayChangePct: 1.02, sparkline: [1, 2, 3]),
                MarketRow(symbol: "USD", name: "", kind: .fiat, price: 201_352, dayChangePct: nil, sparkline: nil),
                MarketRow(symbol: "GOLD", name: "Gold", kind: .gold, price: 6_475, dayChangePct: nil, sparkline: nil),
            ],
            note: "Unknown: XRPX"
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MarketSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.displayCurrency.label, "IRT")
    }

    func testRoundTripWithNoNoteAndEmptyRows() throws {
        let snapshot = MarketSnapshot(writtenAt: .now, displayCurrency: .usd, rows: [], note: nil)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MarketSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertNil(decoded.note)
    }

    func testStorePointsAtMarketboxJson() {
        XCTAssertEqual(MarketSnapshotStore.fileURL.lastPathComponent, "marketbox.json")
    }
}
