import Foundation

// MARK: - Remote opencode incremental sync (pure)
//
// The paging/merge/evict decisions behind OpenBox remote mode's incremental
// fetch (PRD docs/planning/openbox-remote-incremental-sync/prd.md). Transport
// stays in RemoteOpenCodeLoader; every function here is testable without a
// server. The state is an agent-only sidecar (opencode-cursor.json) — the
// widget-facing snapshot never sees it.

enum RemoteOpenCodeSync {
    static let currentVersion = 1
    static let pageLimit = 100

    private static let daySeconds = 86_400.0
    private static let sessionWindow: TimeInterval = 14 * daySeconds
    private static let messageWindow: TimeInterval = 13 * daySeconds

    enum Mode: String, Codable, Equatable {
        case incremental
        case fullFetch
        case singlePage
    }

    struct SessionCursor: Codable, Equatable {
        /// Newest message `created` (epoch ms) already in the archive.
        var watermark: Double
        /// The session's `time.updated` at the last fetch — the idle signal.
        var lastUpdated: Double
    }

    struct State: Codable, Equatable {
        var version: Int
        var server: String
        var mode: Mode
        var sessions: [String: SessionCursor]
        var messages: [RemoteOpenCodeAggregator.RemoteMessage]

        static func new(server: String) -> State {
            State(version: currentVersion, server: server, mode: .incremental, sessions: [:], messages: [])
        }
    }

    enum Plan: Equatable {
        case skip
        case page
        case fullFetch
    }

    // MARK: - State validation

    /// A state belongs to exactly one server (and one schema version); anything
    /// else reads as absent → full resync, self-healing.
    static func validated(_ state: State?, for server: String) -> State? {
        guard let state, state.version == currentVersion, state.server == server else { return nil }
        return state
    }

    // MARK: - Plan

    static func plan(state: State?, sessions: [RemoteOpenCodeAggregator.RemoteSession], now: Date) -> [String: Plan] {
        let nowMilliseconds = now.timeIntervalSince1970 * 1000
        let sessionCutoff = nowMilliseconds - sessionWindow * 1000
        var plans: [String: Plan] = [:]

        for session in sessions {
            guard session.time.updated >= sessionCutoff else {
                plans[session.id] = .skip
                continue
            }
            if state?.mode == .fullFetch {
                plans[session.id] = .fullFetch
            } else if state?.sessions[session.id] == nil {
                // No cursor yet (first tick, or a brand-new session): one full
                // fetch beats walking the whole history at pageLimit per request.
                plans[session.id] = .fullFetch
            } else if state?.sessions[session.id]?.lastUpdated == session.time.updated {
                plans[session.id] = .skip
            } else {
                plans[session.id] = .page
            }
        }
        return plans
    }

    // MARK: - Merge

    /// Merges one fetched page into the state and says whether the loader must
    /// follow the next `before` cursor. Capability fallbacks are detected here,
    /// not probed: a **limited** page larger than `pageLimit` means the server
    /// ignored `limit` (→ full fetch, like today); a page identical to the
    /// previous page means it ignored `before` (→ one bounded page per tick,
    /// the <pageLimit-messages-in-60s gap is accepted and documented in the
    /// PRD). `pageWasLimited` is false for deliberate full fetches (first tick,
    /// new session, `.fullFetch` mode) — a big history must not read as a
    /// capability failure.
    static func merge(
        state: State,
        sessionID: String,
        updated: Double,
        page: [RemoteOpenCodeAggregator.RemoteMessage],
        pageWasLimited: Bool,
        previousPageIDs: Set<String>?,
        hasNextCursor: Bool
    ) -> (state: State, needMore: Bool) {
        var state = state

        if pageWasLimited && page.count > pageLimit {
            state.mode = .fullFetch
        } else if let previous = previousPageIDs, !previous.isEmpty, Set(page.map(\.id)) == previous {
            state.mode = .singlePage
        }

        let oldWatermark = state.sessions[sessionID]?.watermark ?? 0
        let existingIDs = Set(state.messages.map(\.id))
        let newMessages = page.filter { !existingIDs.contains($0.id) }

        var cursor = state.sessions[sessionID] ?? SessionCursor(watermark: 0, lastUpdated: 0)
        cursor.watermark = max(cursor.watermark, page.map(\.time.created).max() ?? 0)
        cursor.lastUpdated = updated
        state.sessions[sessionID] = cursor

        state.messages.append(contentsOf: newMessages)

        // Page newest-first: keep following `before` while the page still
        // contained messages newer than what we already had — everything older
        // than the old watermark is, by ordering, already in the archive.
        // Unlimited pages (deliberate full fetches) never ask for more.
        let needMore = pageWasLimited
            && state.mode == .incremental
            && hasNextCursor
            && page.contains { $0.time.created > oldWatermark }
        return (state, needMore: needMore)
    }

    // MARK: - Prune

    static func prune(state: State, sessionIDs: Set<String>, now: Date) -> State {
        var state = state
        let nowMilliseconds = now.timeIntervalSince1970 * 1000
        state.messages.removeAll { $0.time.created < nowMilliseconds - messageWindow * 1000 }
        state.sessions = state.sessions.filter { entry in
            sessionIDs.contains(entry.key) || entry.value.lastUpdated >= nowMilliseconds - sessionWindow * 1000
        }
        return state
    }

    // MARK: - Message decode (both server shapes)

    struct MessageEnvelope: Codable {
        let info: RemoteOpenCodeAggregator.RemoteMessage
    }

    /// `/session/{id}/message` comes in two shapes across opencode versions:
    /// `[{info, parts}]` envelopes (what the loader was built against) and flat
    /// `[{...info, parts}]` arrays (current servers). Envelope first — the
    /// working path — then flat; `parts` is never decoded.
    static func decodeMessages(_ data: Data) throws -> [RemoteOpenCodeAggregator.RemoteMessage] {
        let decoder = JSONDecoder()
        if let envelopes = try? decoder.decode([MessageEnvelope].self, from: data) {
            return envelopes.map(\.info)
        }
        return try decoder.decode([RemoteOpenCodeAggregator.RemoteMessage].self, from: data)
    }
}

// MARK: - Sidecar store (agent-only; the widget extension never reads it)

enum OpenCodeSyncStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("opencode-cursor.json")
    }

    static func load() -> RemoteOpenCodeSync.State? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let state = try? JSONDecoder().decode(RemoteOpenCodeSync.State.self, from: data) else { return nil }
        // A future schema version reads as absent (self-healing full resync).
        return state.version == RemoteOpenCodeSync.currentVersion ? state : nil
    }

    static func save(_ state: RemoteOpenCodeSync.State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}