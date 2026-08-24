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

// MARK: - MarketBox parsers (host/agent only — unsandboxed)
//
// Contract notes (verified against live payloads on 2026-08-24):
// - CoinGecko /coins/markets returns an array; current_price,
//   price_change_percentage_24h and sparkline_in_7d.price can be absent, and
//   every numeric field is a JSON number.
// - Wallex /v1/markets nests each pair under result.symbols; USDTTMN.stats
//   carries lastPrice as a decimal String and 24h_ch as a number.
// - gold-api /price/XAU returns a single object; price is USD per troy ounce.
// - open.er-api /latest/USD returns rates keyed by ISO code (Doubles).

/// A parsed CoinGecko quote, in USD.
struct CryptoQuote: Equatable {
    var id: String
    var symbol: String
    var name: String
    var priceUSD: Double?
    var priceChangePct24h: Double?
    var sparkline: [Double]?
}

/// The parsed Wallex free-market Toman anchor.
struct WallexRate: Equatable {
    /// Toman per USDT (≈ Toman per USD, peg error is small).
    var tomanPerUSDT: Double?
    /// 24h percent change of that rate (nice-to-have, unused in v1).
    var change24h: Double?
}

enum CoinGeckoMarketsParser {
    static func parse(_ data: Data) -> [CryptoQuote]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return list.map { entry in
            CryptoQuote(
                id: (entry["id"] as? String) ?? "",
                symbol: (entry["symbol"] as? String) ?? "",
                name: (entry["name"] as? String) ?? "",
                priceUSD: (entry["current_price"] as? NSNumber)?.doubleValue,
                priceChangePct24h: (entry["price_change_percentage_24h"] as? NSNumber)?.doubleValue,
                sparkline: sparkline(from: entry)
            )
        }
    }

    /// Empty or absent sparkline is nil, never an empty array, so the widget
    /// treats "no history" the same everywhere.
    private static func sparkline(from entry: [String: Any]) -> [Double]? {
        guard
            let spark = entry["sparkline_in_7d"] as? [String: Any],
            let prices = spark["price"] as? [Any]
        else { return nil }
        let values = prices.compactMap { ($0 as? NSNumber)?.doubleValue }
        return values.isEmpty ? nil : values
    }
}

enum WallexParser {
    static func parse(_ data: Data) -> WallexRate? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let symbols = result["symbols"] as? [String: Any],
            let usdt = symbols["USDTTMN"] as? [String: Any],
            let stats = usdt["stats"] as? [String: Any]
        else { return nil }
        let toman = (stats["lastPrice"] as? String).flatMap(Double.init)
        let change = (stats["24h_ch"] as? NSNumber)?.doubleValue
        return WallexRate(tomanPerUSDT: toman, change24h: change)
    }
}

enum GoldParser {
    /// USD per troy ounce; the caller divides by 31.1035 for the per-gram price.
    static func parse(_ data: Data) -> Double? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let price = json["price"] as? NSNumber
        else { return nil }
        return price.doubleValue
    }
}

enum FXRatesParser {
    /// Currency code → units per 1 USD (open.er-api `latest/USD` shape).
    static func parse(_ data: Data) -> [String: Double]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rates = json["rates"] as? [String: Any]
        else { return nil }
        var out: [String: Double] = [:]
        for (key, value) in rates {
            if let number = value as? NSNumber {
                out[key] = number.doubleValue
            }
        }
        return out.isEmpty ? nil : out
    }
}
