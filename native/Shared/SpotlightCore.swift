import Foundation

// MARK: - Spotlight core
//
// What the floating search panel decides about *what to show*, with no AppKit
// in it: which provider a query is scoped to, how well a candidate matches,
// and how results are ordered and grouped. The panel is layout over this.

/// The searchable sources. The raw value is the typed prefix ("port 8080"),
/// and `allCases` order is the order sections appear in the panel.
enum SearchProviderID: String, CaseIterable, Codable, Equatable {
    case clip
    case port
    case time
    case oc

    var sectionTitle: String {
        switch self {
        case .clip: "Clipboard"
        case .port: "Dev"
        case .time: "Clocks"
        case .oc: "OpenCode sessions"
        }
    }
}

/// What Enter does with a result. One case in this slice; later providers add
/// open-URL (through `DeckLink.webURL`) without changing the panel's shape.
enum SpotlightAction: Equatable {
    case copy(String)
}

struct SearchResult: Equatable, Identifiable {
    /// Unique across providers, so a SwiftUI `ForEach` never collapses two rows.
    let id: String
    let provider: SearchProviderID
    let title: String
    let subtitle: String
    let score: Int
    let action: SpotlightAction
}

struct SearchSection: Equatable {
    let provider: SearchProviderID
    let results: [SearchResult]
}

// MARK: - Query

struct SpotlightQuery: Equatable {
    /// Set when the query began with a provider prefix and a separator.
    let scope: SearchProviderID?
    /// What to look for, trimmed, without the prefix.
    let text: String

    var isEmpty: Bool { text.isEmpty }

    /// A prefix scopes only as the first token **and only once followed by
    /// whitespace**: while the user is still typing "clip" it could be the
    /// start of "clipboard", and scoping early would hide every other source.
    static func parse(_ raw: String) -> SpotlightQuery {
        let leading = String(raw.drop(while: { $0.isWhitespace }))
        if let split = leading.firstIndex(where: { $0.isWhitespace }) {
            let token = leading[..<split].lowercased()
            if let scope = SearchProviderID(rawValue: token) {
                let rest = leading[split...].trimmingCharacters(in: .whitespacesAndNewlines)
                return SpotlightQuery(scope: scope, text: rest)
            }
        }
        return SpotlightQuery(
            scope: nil,
            text: leading.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Matching

enum SpotlightMatcher {
    /// Higher is better; `nil` is no match. Every whitespace-separated token of
    /// the query must match somewhere, so word order does not matter.
    static func score(query: String, in candidate: String) -> Int? {
        let tokens = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let haystack = fold(candidate)
        let words = haystack.split(whereSeparator: { $0.isWhitespace })

        var total = 0
        for token in tokens {
            if haystack == token {
                total += 300
            } else if haystack.hasPrefix(token) {
                total += 200
            } else if words.contains(where: { $0.hasPrefix(token) }) {
                total += 100
            } else if haystack.contains(token) {
                total += 50
            } else {
                return nil
            }
        }
        return total
    }

    private static func fold(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Ordering and grouping

enum SpotlightRanking {
    /// Score, then title, then id. The last two make the order deterministic,
    /// so rows do not shuffle between keystrokes that score the same.
    static func sorted(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.title != b.title { return a.title < b.title }
            return a.id < b.id
        }
    }

    /// Sections in `SearchProviderID.allCases` order, each ranked and capped.
    /// A provider with no results has no section at all.
    static func sections(from results: [SearchResult], perSectionLimit: Int) -> [SearchSection] {
        SearchProviderID.allCases.compactMap { provider in
            let mine = sorted(results.filter { $0.provider == provider })
            guard !mine.isEmpty else { return nil }
            return SearchSection(provider: provider, results: Array(mine.prefix(perSectionLimit)))
        }
    }
}
