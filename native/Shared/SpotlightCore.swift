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
        case .task: "Work items"
        }
    }

    /// The headline example, shown under the toggle. The first of `examples`.
    var exampleQuery: String { examples[0].query }

    /// Every example for the source's "More examples" page. Each must scope to
    /// this source and have something to look for — pinned by
    /// `SearchExamplesTests`, so a copy edit cannot leave a dead example on screen.
    var examples: [SearchExample] {
        switch self {
        case .clip: [
            SearchExample("clip invoice", "Text you copied that mentions “invoice”. Enter copies it back."),
            SearchExample("clip https", "Links you copied recently."),
            SearchExample("clip 192.168", "An address or number you copied earlier."),
        ]
        case .port: [
            SearchExample("port 3000", "Whatever is listening on port 3000. Enter copies the port."),
            SearchExample("port node", "Every listening port owned by a node process."),
            SearchExample("port redis", "A Docker container by name or image, and any redis process. Enter copies the container name."),
            SearchExample("port postgres", "Postgres, whether it runs as a process or a container."),
        ]
        case .time: [
            SearchExample("time tokyo", "The time in Tokyo, its day and its offset from you. Enter copies the time."),
            SearchExample("time new york", "The time in New York."),
            SearchExample("time london", "The time in London."),
            SearchExample("time sydney", "The time in Sydney, and whether it is already tomorrow there."),
        ]
        case .oc: [
            SearchExample("oc refactor", "Recent OpenCode sessions with “refactor” in the title. Enter copies the title."),
            SearchExample("oc fix", "Sessions about a fix."),
            SearchExample("oc test", "Sessions about tests."),
        ]
        case .task: [
            SearchExample("bug login", "Bugs whose title or tags mention “login”, of any age or state. Enter opens the work item."),
            SearchExample("pbi checkout", "Backlog items — a PBI, User Story or Requirement, whatever your process calls them. “backlog” and “story” work too."),
            SearchExample("epic payments", "Epics about payments."),
            SearchExample("feature search", "Features about search."),
            SearchExample("task 4521", "Tasks only. A number also looks up the work item with that id."),
            SearchExample("wi release-blocker", "Any type of work item with that tag, or “release-blocker” in the title. “wi” means every type."),
            SearchExample("login", "No prefix: every source answers, and work items of every type appear under their own heading."),
        ]
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
            "Finds Azure DevOps work items of any age by title, tag or id. Start with bug, pbi, epic, feature or task to narrow by type. Enter opens one. What you type is sent to dev.azure.com using the account TaskBox uses."
        }
    }

    var sectionTitle: String {
        switch self {
        case .clip: "Clipboard"
        case .port: "Dev"
        case .time: "Clocks"
        case .oc: "OpenCode sessions"
        case .task: "Work items"
        }
    }
}

/// One example search and what it finds.
struct SearchExample: Equatable {
    let query: String
    let summary: String

    init(_ query: String, _ summary: String) {
        self.query = query
        self.summary = summary
    }
}

/// Which kind of Azure DevOps work item a query is limited to.
///
/// A backlog item is a Product Backlog Item in Scrum, a User Story in Agile and
/// a Requirement in CMMI, so the filter names a work item **category** rather
/// than a type name only one process template has. The category is a fixed
/// table entry — typed text never reaches it.
enum WorkItemKind: String, CaseIterable, Equatable {
    case any, bug, backlog, epic, feature, task

    /// What the user types first. `wi` is every type.
    var prefixes: [String] {
        switch self {
        case .any: ["wi"]
        case .bug: ["bug"]
        case .backlog: ["pbi", "backlog", "story"]
        case .epic: ["epic"]
        case .feature: ["feature"]
        case .task: ["task"]
        }
    }

    /// WIQL category reference name, or `nil` for "any type".
    var category: String? {
        switch self {
        case .any: nil
        case .bug: "Microsoft.BugCategory"
        case .backlog: "Microsoft.RequirementCategory"
        case .epic: "Microsoft.EpicCategory"
        case .feature: "Microsoft.FeatureCategory"
        case .task: "Microsoft.TaskCategory"
        }
    }

    init?(prefix: String) {
        guard let kind = Self.allCases.first(where: { $0.prefixes.contains(prefix) }) else { return nil }
        self = kind
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
    /// Set for work-item queries (`bug login`, `wi login`); `nil` otherwise.
    var workItemKind: WorkItemKind? = nil

    var isEmpty: Bool { text.isEmpty }

    /// A prefix scopes only as the first token **and only once followed by
    /// whitespace**: while the user is still typing "clip" it could be the
    /// start of "clipboard", and scoping early would hide every other source.
    static func parse(_ raw: String) -> SpotlightQuery {
        let leading = String(raw.drop(while: { $0.isWhitespace }))
        if let split = leading.firstIndex(where: { $0.isWhitespace }) {
            let token = leading[..<split].lowercased()
            let rest = leading[split...].trimmingCharacters(in: .whitespacesAndNewlines)
            // A work-item type is a prefix for the work-item source, and is
            // checked first: `task` used to scope to every type and now means
            // the Task type alone.
            if let kind = WorkItemKind(prefix: token) {
                return SpotlightQuery(scope: .task, text: rest, workItemKind: kind)
            }
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
