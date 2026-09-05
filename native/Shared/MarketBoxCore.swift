import Foundation

// MARK: - MarketBox core (pure)
//
// Everything that decides what a MarketBox row is — symbol resolution, currency
// conversion, row building with the partial-failure policy, and price
// formatting — is pure and unit-tested. The loader in MarketBoxSnapshot.swift
// is a thin shell over these.

// MARK: - Symbol resolution

enum MarketSymbolResolver {
    /// Curated crypto symbol → CoinGecko id. A symbol outside the map is
    /// surfaced as "Unknown", never silently dropped. This map is also the
    /// settings picker's source, so the two can never disagree.
    static let cryptoIDs: [String: String] = [
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "TON": "the-open-network",
        "USDT": "tether",
        "USDC": "usd-coin",
        "SOL": "solana",
        "XRP": "ripple",
        "DOGE": "dogecoin",
        "ADA": "cardano",
        "BNB": "binancecoin",
        "LTC": "litecoin",
        "DOT": "polkadot",
        "AVAX": "avalanche-2",
        "LINK": "chainlink",
        "TRX": "tron",
        "BCH": "bitcoin-cash",
        "SHIB": "shiba-inu",
        "PEPE": "pepe",
        "WIF": "dogwifcoin",
        "BONK": "bonk",
        "NEAR": "near",
        "APT": "aptos",
        "ARB": "arbitrum",
        "OP": "optimism",
        "SUI": "sui",
        "SEI": "sei-network",
        "TIA": "celestia",
        "INJ": "injective-protocol",
        "FIL": "filecoin",
        "ATOM": "cosmos",
        "UNI": "uniswap",
        "AAVE": "aave",
        "MKR": "maker",
        "DAI": "dai",
        "XLM": "stellar",
        "ETC": "ethereum-classic",
        "VET": "vechain",
        "ALGO": "algorand",
        "ICP": "internet-computer",
        "HBAR": "hedera-hashgraph",
        "CRO": "crypto-com-chain",
        "JUP": "jupiter-exchange-solana",
        "WBTC": "wrapped-bitcoin",
    ]

    /// Display names for the settings picker; crypto names are friendly,
    /// not CoinGecko's exact strings.
    static let cryptoNames: [String: String] = [
        "BTC": "Bitcoin", "ETH": "Ethereum", "TON": "Toncoin",
        "USDT": "Tether", "USDC": "USD Coin", "SOL": "Solana",
        "XRP": "XRP", "DOGE": "Dogecoin", "ADA": "Cardano",
        "BNB": "BNB", "LTC": "Litecoin", "DOT": "Polkadot",
        "AVAX": "Avalanche", "LINK": "Chainlink", "TRX": "TRON",
        "BCH": "Bitcoin Cash", "SHIB": "Shiba Inu", "PEPE": "Pepe",
        "WIF": "dogwifcoin", "BONK": "Bonk", "NEAR": "NEAR Protocol",
        "APT": "Aptos", "ARB": "Arbitrum", "OP": "Optimism",
        "SUI": "Sui", "SEI": "Sei", "TIA": "Celestia",
        "INJ": "Injective", "FIL": "Filecoin", "ATOM": "Cosmos",
        "UNI": "Uniswap", "AAVE": "Aave", "MKR": "Maker",
        "DAI": "Dai", "XLM": "Stellar", "ETC": "Ethereum Classic",
        "VET": "VeChain", "ALGO": "Algorand", "ICP": "Internet Computer",
        "HBAR": "Hedera", "CRO": "Cronos", "JUP": "Jupiter",
        "WBTC": "Wrapped Bitcoin",
    ]

    /// Curated fiat ISO allowlist — these resolve to the `fiat` kind and are
    /// priced from the open.er-api rate set.
    static let fiatISOs: Set<String> = [
        "USD", "CAD", "EUR", "GBP", "AUD", "JPY", "CHF", "CNY", "AED", "TRY",
    ]

    static let fiatNames: [String: String] = [
        "USD": "US Dollar", "CAD": "Canadian Dollar", "EUR": "Euro",
        "GBP": "British Pound", "AUD": "Australian Dollar", "JPY": "Japanese Yen",
        "CHF": "Swiss Franc", "CNY": "Chinese Yuan", "AED": "UAE Dirham",
        "TRY": "Turkish Lira",
    ]

    /// `GOLD` means 1 gram of gold (spot per troy ounce ÷ 31.1035).
    static let goldSymbol = "GOLD"

    /// Every symbol the settings picker offers, in display order: crypto,
    /// then GOLD, then the fiat codes.
    static var allPickableSymbols: [String] {
        Array(cryptoIDs.keys).sorted() + [goldSymbol] + Array(fiatISOs).sorted()
    }

    /// "BTC → Bitcoin", "USD → US Dollar", "GOLD → Gold"; falls back to the
    /// symbol itself when there is no name.
    static func pickerLabel(for symbol: String) -> String {
        let s = symbol.uppercased()
        let name: String
        switch kind(for: s) {
        case .crypto: name = cryptoNames[s] ?? ""
        case .fiat: name = fiatNames[s] ?? ""
        case .gold: name = "Gold"
        case nil: name = ""
        }
        return name.isEmpty ? s : "\(s) — \(name)"
    }

    static func cryptoID(for symbol: String) -> String? {
        cryptoIDs[symbol.uppercased()]
    }

    static func kind(for symbol: String) -> MarketKind? {
        let s = symbol.uppercased()
        if cryptoIDs[s] != nil { return .crypto }
        if s == goldSymbol { return .gold }
        if fiatISOs.contains(s) { return .fiat }
        return nil
    }

    /// Human name for non-crypto kinds; crypto names come from CoinGecko.
    static func name(for symbol: String) -> String {
        switch kind(for: symbol) {
        case .gold: return "Gold"
        case .fiat: return fiatNames[symbol.uppercased()] ?? ""
        case .crypto, nil: return ""
        }
    }

    /// "BTC, btc, USD, GOLD , x" → ["BTC", "USD", "GOLD", "X"] — uppercased,
    /// trimmed, deduped (case-insensitively), in order.
    static func normalizedSymbols(from raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
            .reduce(into: []) { result, symbol in
                if !result.contains(symbol) { result.append(symbol) }
            }
    }
}

// MARK: - Configured tickers

/// One configured row: the CoinGecko id is what the agent fetches, the symbol
/// is what the face draws, and the name is cached so the settings list still
/// reads right with no network.
///
/// `kind` is **derived, never stored**, so the two can never disagree.
struct MarketTicker: Codable, Equatable {
    /// Uppercased for display: "BTC".
    var symbol: String
    /// "Bitcoin" — cached at pick time for offline display.
    var name: String
    /// The CoinGecko id ("bitcoin"). Empty for fiat and gold, which are not
    /// CoinGecko rows at all.
    var coinID: String
    /// `market_cap_rank` at pick time. Kept because it records what was
    /// chosen; not rendered in the list, because a stored rank goes stale.
    var rank: Int?

    init(symbol: String, name: String, coinID: String, rank: Int? = nil) {
        self.symbol = symbol
        self.name = name
        self.coinID = coinID
        self.rank = rank
    }

    private enum CodingKeys: String, CodingKey {
        case symbol, name, coinID, rank
    }

    /// Tolerant on purpose: a throw in here reaches
    /// `MarketBoxSettings.init(from:)` and then `DeckSettings.load()`, which
    /// falls back to a blank `DeckSettings()` on any decode error — one
    /// hand-edited entry would reset every setting in the file. An entry with
    /// no symbol survives decoding and is dropped by `normalized`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        coinID = try c.decodeIfPresent(String.self, forKey: .coinID) ?? ""
        rank = try c.decodeIfPresent(Int.self, forKey: .rank)
    }

    /// Crypto is "has an id"; the curated table is not consulted, which is the
    /// whole point — a coin outside it must still price.
    var kind: MarketKind? {
        if !coinID.isEmpty { return .crypto }
        let s = symbol.uppercased()
        if s == MarketSymbolResolver.goldSymbol { return .gold }
        if MarketSymbolResolver.fiatISOs.contains(s) { return .fiat }
        return nil
    }
}

/// The curated map's remaining job: turning the symbols older files stored into
/// tickers. It is no longer consulted at fetch time.
enum MarketTickerMigration {
    static let defaults: [MarketTicker] = tickers(fromSymbols: ["BTC", "ETH", "USD", "GOLD"])

    /// A symbol the table does not know survives with an empty `coinID` — it
    /// still renders as `Unknown: X`, which is what it did before. Losing it
    /// silently would be worse than carrying it unresolvable.
    static func tickers(fromSymbols symbols: [String]) -> [MarketTicker] {
        symbols.map { raw in
            let symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return MarketTicker(
                symbol: symbol,
                name: MarketSymbolResolver.cryptoNames[symbol]
                    ?? MarketSymbolResolver.name(for: symbol),
                coinID: MarketSymbolResolver.cryptoIDs[symbol] ?? ""
            )
        }
    }
}

// MARK: - Currency conversion

enum MarketConverter {
    /// One troy ounce in grams — the GOLD row is priced per gram.
    static let gramsPerTroyOunce = 31.1035

    /// Converts a USD price into the display currency. Returns nil when the
    /// display needs an anchor that is missing: Toman (IRT/IRR) needs the
    /// Wallex rate, CAD/EUR/AED need their open.er-api rate.
    static func perUSD(_ usd: Double, display: MarketCurrency, tmn: Double?, fx: [String: Double]?) -> Double? {
        switch display {
        case .usd:
            return usd
        case .irt:
            guard let tmn else { return nil }
            return usd * tmn
        case .irr:
            guard let tmn else { return nil }
            return usd * tmn * 10
        case .cad, .eur, .aed:
            guard let rate = fx?[display.rawValue.uppercased()], rate > 0 else { return nil }
            return usd * rate
        }
    }

    /// Price of one unit of fiat `code` ("USD", "CAD", …) in the display
    /// currency. `fx` maps ISO → units per 1 USD (open.er-api shape).
    static func fiatPrice(code: String, display: MarketCurrency, tmn: Double?, fx: [String: Double]?) -> Double? {
        let code = code.uppercased()
        // 1 unit of `code` expressed in USD.
        let usdValue: Double
        if code == "USD" {
            usdValue = 1
        } else if let rate = fx?[code], rate > 0 {
            usdValue = 1.0 / rate
        } else {
            return nil
        }
        return perUSD(usdValue, display: display, tmn: tmn, fx: fx)
    }

    /// USD per troy ounce → USD per gram.
    static func goldPerGram(usdPerOunce: Double) -> Double {
        usdPerOunce / gramsPerTroyOunce
    }
}

// MARK: - Row building (the partial-failure policy lives here)

/// Result of a build: the rows to render, the symbols the source couldn't
/// price, and the symbols that resolve to no known kind.
struct MarketBuild: Equatable {
    var rows: [MarketRow]
    var unresolved: [String]
    var omitted: [String]
    /// Tickers the source answered about by saying nothing: the fetch
    /// succeeded and the id was not in the response. Measured 2026-09-05 —
    /// CoinGecko drops unknown ids silently with a 200, so this is the only
    /// evidence there is. Distinct from `omitted`, because "the source is
    /// down" and "this coin has no data" have different fixes.
    var noData: [String] = []

    var isEmpty: Bool { rows.isEmpty }

    /// "Unknown: XRPX · No data: DEAD · Gold unavailable"; nil when fine.
    var note: String? {
        var parts: [String] = []
        if !unresolved.isEmpty {
            parts.append("Unknown: " + unresolved.joined(separator: ", "))
        }
        if !noData.isEmpty {
            parts.append("No data: " + noData.joined(separator: ", "))
        }
        parts.append(contentsOf: omitted.map { $0 + " unavailable" })
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// What the loader will ask the network for, decided purely.
enum MarketFetchPlan {
    /// The CoinGecko ids to price, deduped, in order, blanks dropped.
    ///
    /// **Never build a request from an empty list.** Measured 2026-09-05:
    /// `coins/markets?ids=` with no ids answers 200 with the top 100 coins
    /// (83.6 KB), which would render as though it were the user's list.
    static func cryptoIDs(for tickers: [MarketTicker]) -> [String] {
        var kept: [String] = []
        var seen: Set<String> = []
        for ticker in tickers {
            let id = ticker.coinID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            kept.append(id)
        }
        return kept
    }
}

enum MarketBuilder {
    /// Builds the rows for the configured `symbols` in `display`, given the
    /// parsed sources (nil = that source is unavailable this tick).
    ///
    /// Policy (PRD §3): a source that fails contributes no rows, but the rows
    /// that could be built are still returned — the widget renders a partial
    /// list with a note rather than blanking. `isEmpty` tells the caller
    /// whether to record a failure instead.
    /// `quotesByID` has three states, and conflating two of them tells a user
    /// who owns only USD and GOLD that crypto is unavailable:
    /// `[:]` = no crypto tickers, nothing was asked · `nil` = the fetch was
    /// attempted and failed · populated = the fetch succeeded.
    static func build(
        display: MarketCurrency,
        tickers: [MarketTicker],
        quotesByID: [String: CryptoQuote]?,
        tmn: Double?,
        goldUSDPerGram: Double?,
        fx: [String: Double]?
    ) -> MarketBuild {
        var rows: [MarketRow] = []
        var unresolved: [String] = []
        var omitted: [String] = []
        var noData: [String] = []

        for ticker in tickers {
            let symbol = ticker.symbol
            switch ticker.kind {
            case .crypto:
                guard let quotesByID else {
                    // The fetch failed outright.
                    omitted.append(symbol)
                    continue
                }
                guard let quote = quotesByID[ticker.coinID] else {
                    // It succeeded and said nothing about this id.
                    noData.append(symbol)
                    continue
                }
                guard
                    let priceUSD = quote.priceUSD,
                    let price = MarketConverter.perUSD(priceUSD, display: display, tmn: tmn, fx: fx)
                else {
                    omitted.append(symbol)
                    continue
                }
                rows.append(MarketRow(
                    symbol: symbol,
                    name: quote.name,
                    kind: .crypto,
                    price: price,
                    dayChangePct: quote.priceChangePct24h,
                    sparkline: quote.sparkline
                ))

            case .fiat:
                guard
                    let fx,
                    let price = MarketConverter.fiatPrice(code: symbol, display: display, tmn: tmn, fx: fx)
                else {
                    omitted.append(symbol)
                    continue
                }
                rows.append(MarketRow(
                    symbol: symbol,
                    name: MarketSymbolResolver.name(for: symbol),
                    kind: .fiat,
                    price: price,
                    dayChangePct: nil,
                    sparkline: nil
                ))

            case .gold:
                guard
                    let goldUSDPerGram,
                    let price = MarketConverter.perUSD(goldUSDPerGram, display: display, tmn: tmn, fx: fx)
                else {
                    omitted.append(MarketSymbolResolver.goldSymbol)
                    continue
                }
                rows.append(MarketRow(
                    symbol: symbol,
                    name: "Gold",
                    kind: .gold,
                    price: price,
                    dayChangePct: nil,
                    sparkline: nil
                ))

            case nil:
                unresolved.append(symbol)
            }
        }

        collapse(omitted: &omitted, rows: rows, symbols: tickers.map(\.symbol), kinds: tickers.map(\.kind))

        return MarketBuild(rows: rows, unresolved: unresolved, omitted: omitted, noData: noData)
    }

    /// When every configured symbol of a kind failed, name the kind once
    /// ("Crypto", "Rates", "Gold") instead of listing each symbol.
    private static func collapse(omitted: inout [String], rows: [MarketRow], symbols: [String], kinds: [MarketKind?]) {
        let pairs = zip(symbols, kinds)
        let crypto = pairs.filter { $0.1 == .crypto }.map(\.0)
        let fiat = pairs.filter { $0.1 == .fiat }.map(\.0)
        let gold = kinds.contains { $0 == .gold }

        // Guarded on there actually being an omitted crypto symbol: a crypto
        // ticker can now fail into `noData` instead, and collapsing on
        // "no crypto rows" alone would claim the source was unavailable when
        // it answered fine and simply had nothing for that coin.
        if !crypto.isEmpty,
           !rows.contains(where: { $0.kind == .crypto }),
           omitted.contains(where: { crypto.contains($0) }) {
            omitted.removeAll { crypto.contains($0) }
            omitted.append("Crypto")
        }
        if !fiat.isEmpty, !rows.contains(where: { $0.kind == .fiat }) {
            omitted.removeAll { fiat.contains($0) }
            omitted.append("Rates")
        }
        if gold, !rows.contains(where: { $0.kind == .gold }) {
            omitted.removeAll { $0 == MarketSymbolResolver.goldSymbol }
            omitted.append("Gold")
        }
    }
}

// MARK: - Price formatting

enum MarketPriceFormatter {
    /// Abbreviates large magnitudes so a Toman price in the billions stays
    /// glanceable: 77,850 → "$77,850"; 15,570,000,000 → "15.6B" (IRT gets no
    /// symbol — the header carries the currency label).
    static func price(_ value: Double, currency: MarketCurrency) -> String {
        let prefix = currency == .usd ? "$" : ""
        switch abs(value) {
        case 1_000_000_000...:
            return prefix + String(format: "%.1fB", value / 1_000_000_000)
        case 1_000_000...:
            return prefix + String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return prefix + grouped(Int(value.rounded()))
        case 1..<1_000:
            return prefix + String(format: "%.2f", value)
        default:
            return prefix + String(format: "%.4f", value)
        }
    }

    /// "+1.0%" / "-2.4%" / "0.0%"; nil when there is no change (fiat/gold rows).
    static func change(_ pct: Double?) -> String? {
        guard let pct else { return nil }
        if pct > 0 { return String(format: "+%.1f%%", pct) }
        return String(format: "%.1f%%", pct)
    }

    /// Locale-independent thousands grouping: 77850 → "77,850".
    private static func grouped(_ value: Int) -> String {
        let digits = String(value)
        var out = ""
        for (index, char) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { out.append(",") }
            out.append(char)
        }
        return String(out.reversed())
    }
}