import Foundation

// MARK: - MarketBox snapshot
//
// MarketBox is agent-pumped: the host agent fetches live prices (crypto via
// CoinGecko, gold via gold-api, the free-market Toman rate via Wallex, fiat
// cross-rates via open.er-api) every 60s, converts them to the configured
// display currency (USD / IRR / IRT) and writes this snapshot into the
// container. The widget renders it. Prices are stored already converted, and
// the snapshot records which display currency they were converted for, so a
// mid-tick settings change can never mislabel a row.

/// The one display currency every row is priced in.
enum MarketCurrency: String, Codable, CaseIterable, Equatable {
    case usd, irr, irt

    /// Header label, e.g. "IRT". IRR and IRT share no symbol; the label is the
    /// only unambiguous signal.
    var label: String { rawValue.uppercased() }
}

/// How a configured symbol is sourced. Crypto rows carry a day change and a
/// sparkline; fiat and gold rows are price-only in v1.
enum MarketKind: String, Codable, Equatable {
    case crypto, fiat, gold
}

/// One priced row on the face, in the configured display currency.
struct MarketRow: Codable, Equatable {
    /// The configured symbol as typed (uppercased), e.g. "BTC", "USD", "GOLD".
    var symbol: String
    /// Human name from the source, e.g. "Bitcoin"; empty when unknown.
    var name: String
    var kind: MarketKind
    /// Price in `MarketSnapshot.displayCurrency`.
    var price: Double
    /// 24h percent change — crypto only; nil for fiat/gold.
    var dayChangePct: Double?
    /// 7-day sparkline — crypto only; nil when the source lacks it or the
    /// display size does not show it.
    var sparkline: [Double]?
}

struct MarketSnapshot: Codable, Equatable {
    var writtenAt: Date
    /// The currency `rows` were converted into. The widget shows this in the
    /// header rather than the live setting, so a picker change mid-tick cannot
    /// mislabel the data.
    var displayCurrency: MarketCurrency
    var rows: [MarketRow]
    /// Short secondary line under the list: unresolved symbols ("Unknown: XRPX")
    /// and omitted sources ("Gold unavailable"). Nil when all is well.
    var note: String?
}

enum MarketSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("marketbox.json")
    }

    static func load() -> MarketSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MarketSnapshot.self, from: data)
    }

    static func save(_ snapshot: MarketSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}
