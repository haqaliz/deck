import Foundation

// MARK: - The stock picker's data source
//
// Probed live 2026-09-15 (`docs/planning/marketbox-stock-search/probe.md`):
// Yahoo's `/v1/finance/search` is keyless, ~2.5 KB with `newsCount=0`, and a
// clean 200-with-`count:0` for unknown queries. Its `quotes` list mixes types
// and exchanges — `q=apple` carries two FUTURE rows and a Toronto listing —
// so the parser keeps only the kinds a pick can be and the picker labels the
// rest, so a pick is never blind.

/// One search result. Distinct from `MarketTicker` for the same reason as
/// `CoinSearchHit`: a hit carries the fresh disambiguators (exchange, type)
/// the ticker does not.
struct StockSearchHit: Equatable {
    /// The raw Yahoo symbol — both fetch and display. `^GSPC` and `BRK-B` are
    /// the loader's symbols; there is no normalisation table to drift from
    /// what gets fetched.
    var symbol: String
    /// `longname` preferred, `shortname` fallback — cached at pick time for
    /// offline display.
    var name: String
    /// `exchDisp` ("NASDAQ", "Toronto") — the leading slot in the picker.
    var exchange: String
    /// `typeDisp` ("Equity", "ETF", "Index") — the secondary label.
    var type: String

    /// What gets stored when the user picks this row. `symbol` and
    /// `stockSymbol` are the same string on purpose: the loader fetches
    /// exactly what the search returned.
    var ticker: MarketTicker {
        MarketTicker(symbol: symbol, name: name, coinID: "", stockSymbol: symbol)
    }
}

enum StockSearchParser {
    /// The quote kinds a pick can be: equities, US indices and ETFs (the
    /// interview decision). Anything else — FUTURE, MUTUALFUND, CRYPTOCURRENCY
    /// — is noise and is dropped before it can render.
    static let keepTypes: Set<String> = ["EQUITY", "INDEX", "ETF"]

    static func parse(_ data: Data) -> [StockSearchHit]? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let quotes = object["quotes"] as? [[String: Any]]
        else { return nil }

        return quotes.compactMap { entry in
            guard
                let symbol = entry["symbol"] as? String, !symbol.isEmpty,
                let quoteType = entry["quoteType"] as? String,
                keepTypes.contains(quoteType.uppercased())
            else { return nil }
            let name = (entry["longname"] as? String) ?? (entry["shortname"] as? String) ?? ""
            return StockSearchHit(
                symbol: symbol,
                name: name,
                exchange: (entry["exchDisp"] as? String) ?? "",
                type: (entry["typeDisp"] as? String) ?? ""
            )
        }
    }
}

/// Host-app only. **Never** call this from `DeckAgent` or the widget
/// extension: it exists to serve a settings picker on user interaction, and
/// putting it on any refresh path would spend Yahoo's rate-limit budget on
/// the chart loader that prices stock rows (the `HostCoinSearchLoader` rule,
/// and the probe's host-wide-ban worst case).
enum HostStockSearchLoader {
    /// Rows per query. The probe used 3–8; 8 keeps the sheet useful without
    /// padding the payload.
    static let quotesCount = 8

    static func url(for query: String) -> URL? {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: String(quotesCount)),
            // The payload is ~2.5 KB with the news list suppressed; without
            // these the response bundles news rows nobody renders.
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "listsCount", value: "0"),
        ]
        return components?.url
    }

    /// Built separately so the no-User-Agent rule is testable: a browser UA
    /// earns the host-wide 429 ban the probe measured, `URLSession`'s default
    /// sails through. Never "helpfully" add one here.
    static func request(for query: String) -> URLRequest? {
        guard let url = url(for: query) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        return request
    }

    static func classify(status: Int) -> CoinSearchOutcome {
        switch status {
        case 200: return .ok
        case 429: return .rateLimited
        default: return .serverError(status)
        }
    }

    /// One `GET /search`. The caller owns the debounce, the floor and the
    /// cache (`CoinSearchPolicy`); this just performs the request.
    static func search(query: String) async throws -> [StockSearchHit] {
        guard let request = request(for: query) else { throw CoinSearchFailure.badResponse }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CoinSearchFailure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw CoinSearchFailure.badResponse }
        switch classify(status: http.statusCode) {
        case .rateLimited: throw CoinSearchFailure.rateLimited
        case .serverError: throw CoinSearchFailure.badResponse
        case .ok: break
        }
        guard let hits = StockSearchParser.parse(data) else { throw CoinSearchFailure.badResponse }
        return hits
    }
}