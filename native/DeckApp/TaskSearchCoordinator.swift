import Foundation

/// Runs TaskBox search for the panel: debounce, cancellation, cache, rate-limit
/// back-off and credential resolution. Host-app only and on user interaction —
/// it is never driven from the agent, so a search cannot spend the agent's
/// budget. Every rule about *when* to send lives in `RemoteSearchPolicy`; this
/// only applies it.
@MainActor
final class TaskSearchCoordinator {
    typealias State = RemoteSearchState<[SearchResult]>

    var onState: (State) -> Void = { _ in }

    private let source = SearchProviderID.task.rawValue
    private var generation = SearchGeneration()
    private var cache = RemoteSearchCache<[SearchResult]>()
    private var lastSent: Date?
    private var blockedUntil: Date?
    private var inFlight: Task<Void, Never>?
    /// Resolved on the first remote query of a panel session, not when the
    /// panel opens — most openings never type a task search.
    private var gate: CredentialGate?

    /// A new panel session re-reads the account and keychain, so a token the
    /// user has just pasted is seen. The cache survives: it expires by itself.
    func beginSession() {
        gate = nil
    }

    func cancel() {
        generation.cancel()
        inFlight?.cancel()
        inFlight = nil
        onState(.idle)
    }

    /// Called on every query change with what follows the prefix. Searches for
    /// different types are different searches, so the type is part of the
    /// cache key.
    func update(text: String, kind: WorkItemKind?, enabled: Bool) {
        let cacheKey = "\(source):\(kind?.rawValue ?? "any")"
        generation.cancel()
        inFlight?.cancel()
        inFlight = nil

        guard enabled, RemoteSearchPolicy.shouldSearch(text) else {
            onState(.idle)
            return
        }

        let now = Date()
        if let cached = cache.get(source: cacheKey, query: text, at: now) {
            onState(cached.isEmpty ? .empty : .results(cached))
            return
        }
        // No point showing "Searching…" for the minute a 429 asked us to wait.
        if let blockedUntil, blockedUntil > now {
            onState(.failed(.rateLimited))
            return
        }

        onState(.searching)
        let ticket = generation.next()
        let sendAt = RemoteSearchPolicy.sendTime(typedAt: now, lastSent: lastSent, blockedUntil: blockedUntil)

        inFlight = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, sendAt.timeIntervalSinceNow)))
            await self?.run(text: text, kind: kind, cacheKey: cacheKey, ticket: ticket)
        }
    }

    private func run(text: String, kind: WorkItemKind?, cacheKey: String, ticket: Int) async {
        guard !Task.isCancelled, generation.accepts(ticket) else { return }

        let gate = await resolveGate()
        guard generation.accepts(ticket) else { return }
        let credential: ResolvedCredential
        switch gate {
        case .fetch(let resolved): credential = resolved
        case .off, .notConfigured:
            onState(.failed(.notConfigured)); return
        case .unavailable:
            onState(.failed(.credentialsUnavailable)); return
        }

        lastSent = Date()
        do {
            let tasks = try await HostAzureDevOpsLoader.search(
                organization: credential.organization,
                projects: credential.projects,
                token: credential.token,
                text: text,
                kind: kind)
            // A late answer to an old query must never replace a newer one.
            guard !Task.isCancelled, generation.accepts(ticket) else { return }
            let results = TaskSearch.results(from: tasks, query: text)
            cache.put(results, source: cacheKey, query: text, at: Date())
            onState(results.isEmpty ? .empty : .results(results))
        } catch {
            guard !Task.isCancelled, generation.accepts(ticket), !Self.isCancellation(error) else { return }
            let failure = RemoteSearchFailure(error: error)
            if failure.blocksFurtherSends {
                blockedUntil = Date().addingTimeInterval(RemoteSearchPolicy.rateLimitBackoff)
            }
            onState(.failed(failure))
        }
    }

    /// Settings and keychain are read off the main actor: the keychain can
    /// block, and the panel must stay responsive while it does.
    private func resolveGate() async -> CredentialGate {
        if let gate { return gate }
        let resolved = await Task.detached { () -> CredentialGate in
            var settings = DeckSettings.load()
            let unavailable = settings.hydrateAccountsFromKeychain()
            return settings.gate(.taskbox, unavailable: unavailable)
        }.value
        gate = resolved
        return resolved
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        if case AzureDevOpsError.transport(let message) = error, message.lowercased().contains("cancel") {
            return true
        }
        return false
    }
}
