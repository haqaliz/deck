import Foundation

// MARK: - The coin picker's data source
//
// Probed live 2026-09-05 (`docs/planning/marketbox-coin-lookup/`):
//
// - `/coins/list` — the endpoint the ROADMAP named — is 1.24 MB, 19,594 coins,
//   `{id, symbol, name}` with no rank, and 2,396 of 15,090 distinct symbols
//   map to more than one coin (`BTC` is 11 of them, alphabetically led by
//   `batcat`). Picking by symbol over that list recreates exactly the
//   blind-typed-symbol problem the curated list was introduced to kill.
// - `/search?query=` is 10.5 KB for "pepe", already ordered by market cap, and
//   carries the `market_cap_rank` that makes a choice possible.

/// One search result. Distinct from `MarketTicker` because a hit carries a
/// *fresh* rank and a ticker carries a stale one; only `ticker` crosses over.
struct CoinSearchHit: Equatable {
    var coinID: String
    var symbol: String
    var name: String
    var rank: Int?

    /// What gets stored when the user picks this row.
    var ticker: MarketTicker {
        MarketTicker(symbol: symbol, name: name, coinID: coinID, rank: rank)
    }
}

enum CoinSearchParser {
    /// The payload also carries `exchanges`, `icos`, `categories` and `nfts`.
    /// Only `coins` can become a ticker.
    static func parse(_ data: Data) -> [CoinSearchHit]? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let coins = object["coins"] as? [[String: Any]]
        else { return nil }

        return coins.compactMap { entry in
            // Server order is preserved rather than re-sorted: `/search`
            // returns market-cap order in every probe, but that is not a
            // documented guarantee and re-deriving one would be inventing it.
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            return CoinSearchHit(
                coinID: id,
                symbol: ((entry["symbol"] as? String) ?? "").uppercased(),
                name: (entry["name"] as? String) ?? "",
                rank: (entry["market_cap_rank"] as? NSNumber)?.intValue
            )
        }
    }
}

/// What keeps the picker off the agent's quota.
///
/// The search runs in the **host app only**, on user interaction — never in
/// `DeckAgent`, never in the widget extension, never on a timeline. Both share
/// one public IP budget, and the agent already spends up to four calls per 60s
/// tick; six requests in ~2 minutes returned 429 with `retry-after: 55` during
/// the probe. A 429 degrades this picker and can never fail a tick.
enum CoinSearchPolicy {
    /// Seconds of quiet after the last keystroke before anything is sent, so a
    /// burst of typing collapses into one request.
    static let debounce: TimeInterval = 0.6
    /// Minimum seconds between two requests, whatever the user does.
    static let floor: TimeInterval = 2.0
    /// One character matches thousands of coins and tells the user nothing.
    static let minimumLength = 2

    static func cacheKey(for query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func shouldSearch(query: String, lastRequest: Date?, now: Date) -> Bool {
        guard cacheKey(for: query).count >= minimumLength else { return false }
        guard let lastRequest else { return true }
        return now.timeIntervalSince(lastRequest) >= floor
    }
}
