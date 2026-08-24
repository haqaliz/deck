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
    case usd, irr, irt, cad, eur, aed

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

// MARK: - MarketBox fetch (host/agent only — unsandboxed)

enum MarketLoaderError: Error {
    /// The symbol list is empty — the fetch was skipped on purpose.
    case notConfigured
    /// Every configured symbol resolved to no known kind.
    case invalidSymbols
    case serverError(Int)
    case transport(String)
    case invalidPayload
}

enum HostMarketLoader {
    /// Fetches the configured symbols in the configured display currency.
    ///
    /// Partial-failure policy (PRD §3): each provider is fetched best-effort;
    /// a provider that fails contributes no rows, but the rows that could be
    /// priced still come back with a note. The fetch only throws when **no**
    /// row at all could be priced — the agent then records a classified
    /// outcome and the widget keeps its last-good snapshot.
    static func fetch(settings: MarketBoxSettings) async throws -> MarketSnapshot {
        // Settings normalize on decode (uppercase, dedupe, cap at maxCount).
        let symbols = settings.tickers
        guard !symbols.isEmpty else { throw MarketLoaderError.notConfigured }

        let display = settings.displayCurrency
        let needsCrypto = symbols.contains { MarketSymbolResolver.kind(for: $0) == .crypto }
        let needsGold = symbols.contains { MarketSymbolResolver.kind(for: $0) == .gold }
        let needsFiat = symbols.contains { MarketSymbolResolver.kind(for: $0) == .fiat }
        // IRT/IRR need the free-market Toman anchor; CAD/EUR/AED displays need
        // the open.er-api rate set (as do fiat tickers).
        let needsToman = display == .irt || display == .irr
        let needsFX = needsFiat || display == .cad || display == .eur || display == .aed

        // Fetch only what the tickers + display currency need, and remember the
        // first failure so the "no rows at all" case can be classified honestly.
        var firstError: Error?
        let crypto: [CryptoQuote]?
        if needsCrypto {
            do { crypto = try await fetchCrypto(symbols: symbols) }
            catch { crypto = nil; firstError = firstError ?? error }
        } else { crypto = nil }

        let goldUSDPerOunce: Double?
        if needsGold {
            do { goldUSDPerOunce = try await fetchGold() }
            catch { goldUSDPerOunce = nil; firstError = firstError ?? error }
        } else { goldUSDPerOunce = nil }

        let toman: Double?
        if needsToman {
            do { toman = try await fetchToman() }
            catch { toman = nil; firstError = firstError ?? error }
        } else { toman = nil }

        let fx: [String: Double]?
        if needsFiat {
            do { fx = try await fetchFX() }
            catch { fx = nil; firstError = firstError ?? error }
        } else { fx = nil }

        var quotesByID: [String: CryptoQuote] = [:]
        for quote in crypto ?? [] where !quote.id.isEmpty {
            quotesByID[quote.id] = quote
        }

        let build = MarketBuilder.build(
            display: display,
            symbols: symbols,
            quotesByID: quotesByID,
            tmn: toman,
            goldUSDPerGram: goldUSDPerOunce.map(MarketConverter.goldPerGram),
            fx: fx
        )

        guard !build.isEmpty else {
            // Every symbol failed to price: blame the first fetch failure, or
            // the symbols themselves when nothing even resolved.
            throw firstError ?? MarketLoaderError.invalidSymbols
        }

        return MarketSnapshot(
            writtenAt: Date(),
            displayCurrency: display,
            rows: build.rows,
            note: build.note
        )
    }

    private static func fetchCrypto(symbols: [String]) async throws -> [CryptoQuote] {
        let ids = symbols.compactMap { MarketSymbolResolver.cryptoID(for: $0) }
        let query = ids.joined(separator: ",")
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=\(query)&price_change_percentage=24h")!
        let data = try await get(url)
        guard let quotes = CoinGeckoMarketsParser.parse(data) else {
            throw MarketLoaderError.invalidPayload
        }
        return quotes
    }

    private static func fetchGold() async throws -> Double {
        let url = URL(string: "https://api.gold-api.com/price/XAU")!
        let data = try await get(url)
        guard let price = GoldParser.parse(data) else {
            throw MarketLoaderError.invalidPayload
        }
        return price
    }

    private static func fetchToman() async throws -> Double {
        let url = URL(string: "https://api.wallex.ir/v1/markets")!
        let data = try await get(url)
        guard let rate = WallexParser.parse(data), let toman = rate.tomanPerUSDT else {
            throw MarketLoaderError.invalidPayload
        }
        return toman
    }

    private static func fetchFX() async throws -> [String: Double] {
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let data = try await get(url)
        guard let rates = FXRatesParser.parse(data) else {
            throw MarketLoaderError.invalidPayload
        }
        return rates
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MarketLoaderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MarketLoaderError.transport("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            throw MarketLoaderError.serverError(http.statusCode)
        }
        return data
    }
}
