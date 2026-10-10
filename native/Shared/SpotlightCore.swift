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
    /// ShipBox: GitHub Actions runs. Instant — searched in the snapshot ShipBox
    /// already holds.
    case run
    /// Azure DevOps work items. Deferred: answered over the network by the host.
    case task
    /// PRBox: pull requests on GitHub and Azure DevOps. Deferred, network.
    case pr
    /// GitBox: commit messages of any age, via `git log`. Deferred (subprocess).
    case commit
    /// CalBox: calendar events within a year either side. Deferred (EventKit).
    /// Raw value is the prefix the user types.
    case event = "cal"
    /// MarketBox: live coin / stock lookup. Deferred, network, keyless.
    case market = "mkt"

    /// Answered asynchronously by the host through `RemoteSearchPolicy`
    /// (debounce, floor, cache, cancel) rather than on every keystroke by
    /// `SpotlightEngine`. Not all of these are remote: commits are a
    /// subprocess and calendar events are EventKit, but both are too slow to
    /// run per keystroke.
    var isDeferred: Bool {
        switch self {
        case .task, .pr, .commit, .event, .market: true
        case .clip, .port, .time, .oc, .run: false
        }
    }

    /// Only a typed prefix asks these anything. An unscoped query would
    /// otherwise send every word to GitHub (the PRBox agent's 30/min search
    /// budget), CoinGecko and Yahoo (one shared IP quota) and run `git log`
    /// in every repo. Work items allow it (shipped before this rule) and
    /// calendar events never leave the Mac.
    var requiresPrefix: Bool {
        switch self {
        case .pr, .commit, .market: true
        default: false
        }
    }

    /// The sources `SpotlightEngine` answers synchronously from snapshots.
    static var instantCases: [SearchProviderID] { allCases.filter { !$0.isDeferred } }
    static var deferredCases: [SearchProviderID] { allCases.filter(\.isDeferred) }

    /// The toggle's label in the Spotlight settings tab.
    var settingsTitle: String {
        switch self {
        case .clip: "Clipboard"
        case .port: "Ports and containers"
        case .time: "World clocks"
        case .oc: "OpenCode sessions"
        case .run: "Builds"
        case .task: "Work items"
        case .pr: "Pull requests"
        case .commit: "Commits"
        case .event: "Calendar events"
        case .market: "Markets"
        }
    }

    /// Plural noun for "No … found" under a section.
    var noun: String {
        switch self {
        case .clip: "clips"
        case .port: "ports or containers"
        case .time: "cities"
        case .oc: "sessions"
        case .run: "builds"
        case .task: "work items"
        case .pr: "pull requests"
        case .commit: "commits"
        case .event: "events"
        case .market: "markets"
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
        case .run: [
            SearchExample("run deploy", "Recent builds whose workflow name mentions “deploy”. Enter opens the run."),
            SearchExample("run main", "Recent builds on the main branch."),
            SearchExample("run 1234", "The build with run number 1234, if it is among the recent ones."),
            SearchExample("run deck", "Recent builds in a repository whose name contains “deck”."),
        ]
        case .pr: [
            SearchExample("pr login", "Pull requests you are involved in whose title or description mention “login”, open or not. Enter opens the pull request."),
            SearchExample("pr fix flaky test", "Every word must match, in any order."),
            SearchExample("pr 1234", "The pull request numbered 1234, if it is among your 100 most recently updated. Older ones are found by words, not by number."),
            SearchExample("pr refactor", "Pull requests about a refactor, on GitHub or Azure DevOps."),
        ]
        case .commit: [
            SearchExample("commit fix login", "Commits whose message mentions “fix login”, in every repository GitBox scans, of any age. Enter copies the short hash."),
            SearchExample("commit revert", "Reverts."),
            SearchExample("commit migration", "Commits about a migration."),
        ]
        case .event: [
            SearchExample("cal standup", "Calendar events with “standup” in the title, location or notes, up to a year back and ahead. Enter opens the meeting link, or copies the title."),
            SearchExample("cal dentist", "An appointment, past or upcoming."),
            SearchExample("cal 1:1", "One-to-one meetings."),
        ]
        case .market: [
            SearchExample("mkt bitcoin", "Coins named Bitcoin, by market-cap rank. Enter opens the coin page."),
            SearchExample("mkt eth", "Coins with “eth” in the name or symbol."),
            SearchExample("mkt tesla", "Stocks and ETFs matching Tesla. Enter opens the quote page."),
            SearchExample("mkt nasdaq", "Indices and funds matching Nasdaq."),
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
        case .run:
            "Finds recent GitHub Actions runs by workflow, branch, repository or run number, from the runs ShipBox already holds. Enter opens the run."
        case .pr:
            "Needs the pr prefix. Finds pull requests you are involved in, by title, description or number, on GitHub and Azure DevOps. Enter opens one. What you type is sent to GitHub and Azure DevOps using the PRBox accounts."
        case .commit:
            "Needs the commit prefix. Finds commits by message in every repository GitBox scans, of any age. Enter copies the short hash. Runs on this Mac; nothing is sent anywhere."
        case .event:
            "Finds calendar events by title, location or notes, up to a year back and ahead, in the calendars CalBox uses. Enter opens the meeting link or copies the title. Off by default: titles would show in the panel."
        case .market:
            "Needs the mkt prefix. Finds coins and stocks by name or symbol. Enter opens the page. What you type is sent to CoinGecko and Yahoo Finance."
        }
    }

    var sectionTitle: String {
        switch self {
        case .clip: "Clipboard"
        case .port: "Dev"
        case .time: "Clocks"
        case .oc: "OpenCode sessions"
        case .run: "Builds"
        case .task: "Work items"
        case .pr: "Pull requests"
        case .commit: "Commits"
        case .event: "Calendar"
        case .market: "Markets"
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
