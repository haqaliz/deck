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
    /// Azure DevOps work items. Remote: answered over the network by the host
    /// app, never by `SpotlightEngine`.
    case task

    /// Answered over the network, so it goes through `RemoteSearchPolicy`
    /// (debounce, floor, cache) instead of running on every keystroke.
    var isRemote: Bool { self == .task }

    /// The sources `SpotlightEngine` can answer synchronously from snapshots.
    static var localCases: [SearchProviderID] { allCases.filter { !$0.isRemote } }

    /// The toggle's label in the Spotlight settings tab.
    var settingsTitle: String {
        switch self {
        case .clip: "Clipboard"
        case .port: "Ports and containers"
        case .time: "World clocks"
        case .oc: "OpenCode sessions"
        case .task: "Tasks"
        }
    }

    /// A search to try, shown under the toggle. Must scope to this source and
    /// have something to look for — pinned by `SpotlightExampleTests`.
    var exampleQuery: String {
        switch self {
        case .clip: "clip invoice"
        case .port: "port 3000"
        case .time: "time tokyo"
        case .oc: "oc refactor"
        case .task: "task login bug"
        }
    }

    /// What that search finds, and what Enter does with it.
    var exampleSummary: String {
        switch self {
        case .clip:
            "Finds text you copied earlier, from ClipBox history. Enter copies it back."
        case .port:
            "Finds a listening port by number or process, or a Docker container by name or image. Enter copies the port or container name."
        case .time:
            "Shows the current time in a city, with its day and offset from you. Enter copies the time."
        case .oc:
            "Finds recent OpenCode sessions by title. Enter copies the title."
        case .task:
            "Finds Azure DevOps work items of any age by title, tag or id. Enter opens one. What you type is sent to dev.azure.com using the account TaskBox uses."
        }
    }

    var sectionTitle: String {
        switch self {
        case .clip: "Clipboard"
        case .port: "Dev"
        case .time: "Clocks"
        case .oc: "OpenCode sessions"
        case .task: "Tasks"
        }
    }
}

/// What Enter does with a result. One case in this slice; later providers add
/// open-URL (through `DeckLink.webURL`) without changing the panel's shape.
enum SpotlightAction: Equatable {
    case copy(String)
    /// Opens a link in the browser. Built only from a URL that passed
    /// `DeckLink.webURL`, because remote data decides it.
    case open(URL)

    /// What Cmd-Return copies: the text itself, or a link's address.
    var copyText: String {
        switch self {
        case .copy(let text): text
        case .open(let url): url.absoluteString
        }
    }
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
