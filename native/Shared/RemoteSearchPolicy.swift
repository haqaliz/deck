import Foundation

// MARK: - Remote search policy
//
// When a network-backed Spotlight source may send a request, and what the
// panel shows while it waits. Pure: every time is passed in, so none of it
// needs a clock, a socket or the panel.
//
// The rules exist because Deck already trips public rate limits — CoinGecko
// answered 429 with `retry-after: 55` after six requests in two minutes,
// GitHub search allows 30 a minute, Yahoo throttles a burst (CLAUDE.md) — and
// a search-as-you-type box would trip them for the *agent* too, blanking a
// widget while the user was merely looking something up. It is the same shape
// as `CoinSearchPolicy`, generalised so each later source reuses it.

enum RemoteSearchPolicy {
    /// Under this, a query is too broad to be worth a request.
    static let minimumLength = 2
    /// Quiet time after the last keystroke before anything is sent.
    static let debounce: TimeInterval = 0.3
    /// Minimum gap between two requests to the same source.
    static let sourceFloor: TimeInterval = 0.5
    static let cacheTTL: TimeInterval = 60
    static let cacheLimit = 50
    /// Past CoinGecko's measured `retry-after: 55`; a shorter back-off only
    /// earns another 429.
    static let rateLimitBackoff: TimeInterval = 60

    /// Trimmed, whitespace collapsed, case- and diacritic-folded: the form a
    /// query is compared and cached in.
    static func normalise(_ query: String) -> String {
        query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func shouldSearch(_ text: String) -> Bool {
        normalise(text).count >= minimumLength
    }

    /// The earliest moment a request may go out: after the debounce, after the
    /// per-source floor, and not before a rate limit's window has passed.
    /// A window already in the past is simply outvoted by the others.
    static func sendTime(typedAt: Date, lastSent: Date?, blockedUntil: Date?) -> Date {
        var time = typedAt.addingTimeInterval(debounce)
        if let lastSent { time = max(time, lastSent.addingTimeInterval(sourceFloor)) }
        if let blockedUntil { time = max(time, blockedUntil) }
        return time
    }
}

// MARK: - Cache

/// Per-source, per-query answers for a minute. An empty answer is cached too:
/// retyping a dead query must not hit the network again.
struct RemoteSearchCache<Value> {
    private struct Key: Hashable {
        let source: String
        let query: String
    }

    private var entries: [Key: (value: Value, at: Date)] = [:]
    private let limit: Int
    private let ttl: TimeInterval

    init(limit: Int = RemoteSearchPolicy.cacheLimit, ttl: TimeInterval = RemoteSearchPolicy.cacheTTL) {
        self.limit = limit
        self.ttl = ttl
    }

    var count: Int { entries.count }

    func get(source: String, query: String, at now: Date) -> Value? {
        let key = Key(source: source, query: RemoteSearchPolicy.normalise(query))
        guard let entry = entries[key], now.timeIntervalSince(entry.at) <= ttl else { return nil }
        return entry.value
    }

    mutating func put(_ value: Value, source: String, query: String, at now: Date) {
        entries[Key(source: source, query: RemoteSearchPolicy.normalise(query))] = (value, now)
        while entries.count > limit, let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    mutating func invalidate(source: String) {
        entries = entries.filter { $0.key.source != source }
    }
}

// MARK: - Stale-answer guard

/// A late answer to an old query must never replace a newer one. Each query
/// takes the next generation; only the latest is accepted.
struct SearchGeneration {
    private var current = 0

    mutating func next() -> Int {
        current += 1
        return current
    }

    func accepts(_ generation: Int) -> Bool { generation == current }

    /// Drops whatever is outstanding (Esc, panel hidden).
    mutating func cancel() { current += 1 }
}

// MARK: - Failure and state

/// Why one remote section has nothing to show. Scoped to a section: the others
/// are unaffected.
enum RemoteSearchFailure: Equatable {
    case notConfigured
    case credentialsUnavailable
    case authOrTarget
    case rateLimited
    case unreachable
    case badResponse
    case queryRejected
    /// macOS has not allowed Deck to read calendars.
    case calendarAccess
    /// GitBox has no repository paths, so there is nothing to search.
    case noRepositories

    /// One line, so a section never grows to explain itself.
    var message: String {
        switch self {
        case .notConfigured: "Choose an account for this in Credentials."
        // Deliberately not "not configured": the token is pasted, the keychain
        // is the problem, and sending the user to the token field is wrong.
        case .credentialsUnavailable: "Can't read the saved token. Unlock your keychain and reopen Deck."
        case .authOrTarget: "The token or project was refused. Check them in Credentials."
        case .rateLimited: "Rate limited. Try again in a minute."
        case .unreachable: "Couldn't reach the service."
        case .badResponse: "Got an answer Deck couldn't read."
        case .queryRejected: "The service rejected that search."
        case .calendarAccess: "Deck can't read your calendars. Allow it in System Settings → Privacy → Calendars."
        case .noRepositories: "No repositories to search. Add some in the GitBox settings."
        }
    }

    /// Only a rate limit holds the next send back; everything else is retried
    /// on the next query.
    var blocksFurtherSends: Bool { self == .rateLimited }

    /// `FetchClassifier` folds 429 into "unreachable" because for a widget
    /// both mean "wait". Here the distinction matters — it blocks sends — so a
    /// 429 is picked out first.
    init(error: Error) {
        if let own = error as? SearchSourceFailure {
            self = own.failure
            return
        }
        if case AzureDevOpsError.serverError(429) = error {
            self = .rateLimited
            return
        }
        if case HostGitHubLoader.GitHubError.serverError(429) = error {
            self = .rateLimited
            return
        }
        switch error {
        case AzureDevOpsError.invalidQuery, AzureDevOpsError.queryRejected:
            self = .queryRejected
        default:
            switch FetchClassifier.outcome(for: error) {
            case .notConfigured: self = .notConfigured
            case .credentialsUnavailable: self = .credentialsUnavailable
            case .authOrTarget: self = .authOrTarget
            case .unreachable: self = .unreachable
            case .queryRejected: self = .queryRejected
            case .badResponse, .ok: self = .badResponse
            }
        }
    }
}

/// Thrown by a source that knows exactly why it has nothing to show, so the
/// panel reports that reason instead of reclassifying a generic error.
struct SearchSourceFailure: Error, Equatable {
    let failure: RemoteSearchFailure
    init(_ failure: RemoteSearchFailure) { self.failure = failure }
}

/// What one remote section shows.
enum RemoteSearchState<Value: Equatable>: Equatable {
    case idle
    case searching
    case results(Value)
    case empty
    case failed(RemoteSearchFailure)

    /// The status line under the section title, or `nil` when rows speak for
    /// themselves. "No … found" says what happened to *this search* and no
    /// more: a misspelt term and a real miss look the same.
    func line(noun: String) -> String? {
        switch self {
        case .idle, .results: nil
        case .searching: "Searching…"
        case .empty: "No \(noun) found"
        case .failed(let failure): failure.message
        }
    }
}
