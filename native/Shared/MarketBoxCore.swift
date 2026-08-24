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

// MARK: - Currency conversion

enum MarketConverter {
    /// One troy ounce in grams — the GOLD row is priced per gram.
    static let gramsPerTroyOunce = 31.1035

    /// Converts a USD price into the display currency. Returns nil when the
    /// display needs the Toman anchor (IRT/IRR) and it is missing.
    static func perUSD(_ usd: Double, display: MarketCurrency, tmn: Double?) -> Double? {
        switch display {
        case .usd:
            return usd
        case .irt:
            guard let tmn else { return nil }
            return usd * tmn
        case .irr:
            guard let tmn else { return nil }
            return usd * tmn * 10
        }
    }

    /// Price of one unit of fiat `code` ("USD", "CAD", …) in the display
    /// currency. `fx` maps ISO → units per 1 USD (open.er-api shape).
    static func fiatPrice(code: String, display: MarketCurrency, tmn: Double?, fx: [String: Double]) -> Double? {
        let code = code.uppercased()
        switch display {
        case .usd:
            if code == "USD" { return 1.0 }
            guard let rate = fx[code], rate > 0 else { return nil }
            return 1.0 / rate
        case .irt, .irr:
            guard let tmn else { return nil }
            let usd = code == "USD" ? 1.0 : (fx[code].flatMap { $0 > 0 ? 1.0 / $0 : nil })
            guard let usd else { return nil }
            return display == .irt ? usd * tmn : usd * tmn * 10
        }
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

    var isEmpty: Bool { rows.isEmpty }

    /// "Unknown: XRPX · Gold unavailable · Crypto unavailable"; nil when fine.
    var note: String? {
        var parts: [String] = []
        if !unresolved.isEmpty {
            parts.append("Unknown: " + unresolved.joined(separator: ", "))
        }
        parts.append(contentsOf: omitted.map { $0 + " unavailable" })
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
    static func build(
        display: MarketCurrency,
        symbols: [String],
        quotesByID: [String: CryptoQuote],
        tmn: Double?,
        goldUSDPerGram: Double?,
        fx: [String: Double]?
    ) -> MarketBuild {
        var rows: [MarketRow] = []
        var unresolved: [String] = []
        var omitted: [String] = []

        for symbol in symbols {
            switch MarketSymbolResolver.kind(for: symbol) {
            case .crypto:
                guard
                    let id = MarketSymbolResolver.cryptoID(for: symbol),
                    let quote = quotesByID[id],
                    let priceUSD = quote.priceUSD,
                    let price = MarketConverter.perUSD(priceUSD, display: display, tmn: tmn)
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
                    let price = MarketConverter.perUSD(goldUSDPerGram, display: display, tmn: tmn)
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

        collapse(omitted: &omitted, rows: rows, symbols: symbols)

        return MarketBuild(rows: rows, unresolved: unresolved, omitted: omitted)
    }

    /// When every configured symbol of a kind failed, name the kind once
    /// ("Crypto", "Rates", "Gold") instead of listing each symbol.
    private static func collapse(omitted: inout [String], rows: [MarketRow], symbols: [String]) {
        let crypto = symbols.filter { MarketSymbolResolver.kind(for: $0) == .crypto }
        let fiat = symbols.filter { MarketSymbolResolver.kind(for: $0) == .fiat }
        let gold = symbols.contains { MarketSymbolResolver.kind(for: $0) == .gold }

        if !crypto.isEmpty, !rows.contains(where: { $0.kind == .crypto }) {
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