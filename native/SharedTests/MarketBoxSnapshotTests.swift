import XCTest

// Phase 1 tests: MarketBoxSettings tolerant decode and the snapshot round-trip.

private func decode<T: Decodable>(_ json: String, as _: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

final class MarketBoxSettingsDecodeTests: XCTestCase {
    func testEmptyFixtureDecodesAllDefaults() throws {
        let s = try decode(#"{}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s, MarketBoxSettings())
        XCTAssertEqual(s.symbols, "BTC, ETH, USD, GOLD")
        XCTAssertEqual(s.displayCurrency, .usd)
        XCTAssertEqual(s.tickerCount, 8)
        XCTAssertTrue(s.showDayChange)
        XCTAssertTrue(s.showSparklines)
    }

    func testPartialFixtureKeepsDefaults() throws {
        let s = try decode(#"{"symbols":"BTC","displayCurrency":"irt","tickerCount":5}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.symbols, "BTC")
        XCTAssertEqual(s.displayCurrency, .irt)
        XCTAssertEqual(s.tickerCount, 5)
        XCTAssertEqual(s.upColor, RGBA(.green), "absent colors keep defaults")
        XCTAssertEqual(s.downColor, RGBA(.red))
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
        let s = try decode(#"{"symbols":"ETH","somethingNew":true}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.symbols, "ETH")
    }

    /// A currency this build doesn't know (written by a newer build) falls back
    /// to USD rather than failing the whole section.
    func testUnknownDisplayCurrencyFallsBackToUsd() throws {
        let s = try decode(#"{"displayCurrency":"eur"}"#, as: MarketBoxSettings.self)
        XCTAssertEqual(s.displayCurrency, .usd)
    }

    func testDeckSettingsWithoutMarketBoxSectionStillLoads() throws {
        let s = try decode(#"{"shipbox":{"repo":"a/b"}}"#, as: DeckSettings.self)
        XCTAssertEqual(s.shipbox.repo, "a/b")
        XCTAssertEqual(s.marketbox, MarketBoxSettings())
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
