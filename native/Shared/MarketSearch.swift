import Foundation

// MARK: - Market search (MarketBox)
//
// The live coin (CoinGecko) and stock (Yahoo) lookups MarketBox's picker already
// uses, reached from the panel with the `mkt ` prefix. Both are keyless and
// share one public-IP budget with the agent (CLAUDE.md), so:
//
//   - only a prefix sends anything (`SearchProviderID.requiresPrefix`),
//   - pacing is `CoinSearchPolicy`'s (0.6s debounce, 2s floor), not the generic
//     0.3s/0.5s,
//   - the loaders are the existing host-only ones, and Yahoo's must never be
//     given a User-Agent (a browser UA earned a host-wide 429 ban),
//   - a CoinGecko 429 backs CoinGecko off on its own while Yahoo keeps
//     answering.

enum MarketSearch {
    static let maxQueryLength = 50

    /// Control characters out, whitespace collapsed, capped: what is sent.
    static func sanitise(_ text: String) -> String {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : $0
        }))
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(maxQueryLength)).trimmingCharacters(in: .whitespaces)
    }

    /// Unreserved characters only: everything else, including `/ ? # % ^ \` and
    /// space, is percent-encoded, so nothing in an id can add a path segment, a
    /// query or a fragment.
    private static let segmentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func segment(_ raw: String) -> String? {
        guard !raw.isEmpty, raw != ".", raw != ".." else { return nil }  // dot segments are resolved by servers
        return raw.addingPercentEncoding(withAllowedCharacters: segmentAllowed)
    }

    static func coinURL(id: String) -> URL? {
        segment(id).flatMap { URL(string: "https://www.coingecko.com/en/coins/\($0)") }
    }

    static func stockURL(symbol: String) -> URL? {
        segment(symbol).flatMap { URL(string: "https://finance.yahoo.com/quote/\($0)") }
    }

    static func results(coins: [CoinSearchHit], stocks: [StockSearchHit]) -> [SearchResult] {
        // Server order is kept (market-cap order for coins). Scores interleave the
        // two kinds by position so the best stock is not buried under every coin.
        let coinRows = coins.enumerated().compactMap { index, coin -> SearchResult? in
            guard let url = coinURL(id: coin.coinID) else { return nil }
            let name = coin.name.isEmpty ? coin.symbol : coin.name
            return SearchResult(
                id: "market:coin:\(coin.coinID)",
                provider: .market,
                title: coin.symbol.isEmpty ? name : "\(name) (\(coin.symbol))",
                subtitle: coin.rank.map { "Coin · Rank #\($0)" } ?? "Coin",
                score: 1000 - index * 10,
                action: .open(url))
        }
        let stockRows = stocks.enumerated().compactMap { index, stock -> SearchResult? in
            guard let url = stockURL(symbol: stock.symbol) else { return nil }
            let name = stock.name.isEmpty ? stock.symbol : stock.name
            return SearchResult(
                id: "market:stock:\(stock.symbol)",
                provider: .market,
                title: "\(name) (\(stock.symbol))",
                subtitle: (["Stock", stock.exchange, stock.type]).filter { !$0.isEmpty }.joined(separator: " · "),
                score: 1000 - index * 10 - 5,
                action: .open(url))
        }
        return coinRows + stockRows
    }

    /// Two independent lookups. A failure on one side still shows the other; only
    /// both failing is a failure. `nil` means that side was deliberately skipped
    /// (CoinGecko backing off after a 429) — not an error.
    static func combine(
        coins: Result<[CoinSearchHit], Error>?,
        stocks: Result<[StockSearchHit], Error>?
    ) throws -> (coins: [CoinSearchHit], stocks: [StockSearchHit]) {
        var coinHits: [CoinSearchHit] = []
        var stockHits: [StockSearchHit] = []
        var firstError: Error?
        var answered = false

        switch coins {
        case .success(let hits)?: coinHits = hits; answered = true
        case .failure(let error)?: firstError = firstError ?? error
        case nil: break
        }
        switch stocks {
        case .success(let hits)?: stockHits = hits; answered = true
        case .failure(let error)?: firstError = firstError ?? error
        case nil: break
        }
        if answered { return (coinHits, stockHits) }
        // Nothing answered. Skipping is only ever a back-off, so say that.
        throw firstError ?? SearchSourceFailure(.rateLimited)
    }
}

// MARK: - Per-source pacing

extension SearchProviderID {
    /// The existing picker's pacing for markets (CoinGecko answered 429 with
    /// `retry-after: 55` after six requests in two minutes); the generic pacing
    /// for everything else.
    var timing: (debounce: TimeInterval, floor: TimeInterval) {
        self == .market
            ? (CoinSearchPolicy.debounce, CoinSearchPolicy.floor)
            : (RemoteSearchPolicy.debounce, RemoteSearchPolicy.sourceFloor)
    }
}
