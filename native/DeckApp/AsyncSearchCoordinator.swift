import Foundation

// MARK: - Deferred sources
//
// Every source that cannot answer on each keystroke — the network ones, `git
// log`, EventKit — runs through here. One `SourceRunner` per source, so each
// has its own debounce, floor, cache, generation and rate-limit back-off: a
// slow or failed source never delays or blanks another. Every rule about
// *when* to send is `RemoteSearchPolicy`'s; this only applies it.
//
// Host-app only and on user interaction. None of it is reachable from the
// agent, so a search cannot spend the agent's rate-limit budget.

struct AsyncSearchRequest {
    let text: String
    /// Work-item queries only.
    let kind: WorkItemKind?

    /// Searches for different types are different searches.
    var cacheKey: String { kind.map { "\($0.rawValue):" } ?? "" }
}

@MainActor
protocol AsyncSearchSource: AnyObject {
    var provider: SearchProviderID { get }
    /// A new panel session: forget anything resolved last time (an account, a
    /// token), so a credential pasted a moment ago is seen.
    func beginSession()
    /// Throws `SearchSourceFailure` when it knows why it has nothing; any other
    /// error is classified by `RemoteSearchFailure(error:)`.
    func search(_ request: AsyncSearchRequest) async throws -> [SearchResult]
}

@MainActor
final class SourceRunner {
    typealias State = RemoteSearchState<[SearchResult]>

    let source: AsyncSearchSource
    var onState: (SearchProviderID, State) -> Void = { _, _ in }

    private var generation = SearchGeneration()
    private var cache = RemoteSearchCache<[SearchResult]>()
    private var lastSent: Date?
    private var blockedUntil: Date?
    private var inFlight: Task<Void, Never>?

    init(source: AsyncSearchSource) {
        self.source = source
    }

    private var key: String { source.provider.rawValue }

    func cancel() {
        generation.cancel()
        inFlight?.cancel()
        inFlight = nil
    }

    func idle() {
        cancel()
        onState(source.provider, .idle)
    }

    func update(_ request: AsyncSearchRequest) {
        cancel()
        guard RemoteSearchPolicy.shouldSearch(request.text) else {
            onState(source.provider, .idle)
            return
        }

        let now = Date()
        let cacheKey = key + ":" + request.cacheKey
        if let cached = cache.get(source: cacheKey, query: request.text, at: now) {
            onState(source.provider, cached.isEmpty ? .empty : .results(cached))
            return
        }
        // No point showing "Searching…" for the minute a 429 asked us to wait.
        if let blockedUntil, blockedUntil > now {
            onState(source.provider, .failed(.rateLimited))
            return
        }

        onState(source.provider, .searching)
        let ticket = generation.next()
        let sendAt = RemoteSearchPolicy.sendTime(typedAt: now, lastSent: lastSent, blockedUntil: blockedUntil)
        inFlight = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, sendAt.timeIntervalSinceNow)))
            await self?.run(request, cacheKey: cacheKey, ticket: ticket)
        }
    }

    private func run(_ request: AsyncSearchRequest, cacheKey: String, ticket: Int) async {
        guard !Task.isCancelled, generation.accepts(ticket) else { return }
        lastSent = Date()
        do {
            let results = try await source.search(request)
            // A late answer to an old query must never replace a newer one.
            guard !Task.isCancelled, generation.accepts(ticket) else { return }
            cache.put(results, source: cacheKey, query: request.text, at: Date())
            onState(source.provider, results.isEmpty ? .empty : .results(results))
        } catch {
            guard !Task.isCancelled, generation.accepts(ticket), !Self.isCancellation(error) else { return }
            let failure = RemoteSearchFailure(error: error)
            if failure.blocksFurtherSends {
                blockedUntil = Date().addingTimeInterval(RemoteSearchPolicy.rateLimitBackoff)
            }
            onState(source.provider, .failed(failure))
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        if case AzureDevOpsError.transport(let message) = error, message.lowercased().contains("cancel") {
            return true
        }
        if case HostGitHubLoader.GitHubError.transport(let message) = error, message.lowercased().contains("cancel") {
            return true
        }
        return false
    }
}

@MainActor
final class AsyncSearchCoordinator {
    var onState: (SearchProviderID, SourceRunner.State) -> Void = { _, _ in }

    private var runners: [SearchProviderID: SourceRunner] = [:]

    func register(_ source: AsyncSearchSource) {
        let runner = SourceRunner(source: source)
        runner.onState = { [weak self] provider, state in self?.onState(provider, state) }
        runners[source.provider] = runner
    }

    func beginSession() {
        runners.values.forEach { $0.source.beginSession() }
    }

    func cancelAll() {
        for (provider, runner) in runners {
            runner.idle()
            _ = provider
        }
    }

    /// Which sources a query reaches: enabled ones, scoped to it when it has a
    /// prefix, and — without a prefix — only those that do not require one.
    static func sources(for query: SpotlightQuery, settings: SpotlightSettings) -> [SearchProviderID] {
        SearchProviderID.deferredCases.filter { provider in
            settings.isEnabled(provider)
                && (query.scope == provider || (query.scope == nil && !provider.requiresPrefix))
        }
    }

    func update(query: SpotlightQuery, settings: SpotlightSettings) {
        let wanted = Set(Self.sources(for: query, settings: settings))
        for (provider, runner) in runners {
            if wanted.contains(provider) {
                runner.update(AsyncSearchRequest(text: query.text, kind: query.workItemKind))
            } else {
                runner.idle()
            }
        }
    }
}

// MARK: - Work items

/// Azure DevOps work items, through the account TaskBox uses.
@MainActor
final class WorkItemSearchSource: AsyncSearchSource {
    let provider = SearchProviderID.task
    private var gate: CredentialGate?

    func beginSession() { gate = nil }

    func search(_ request: AsyncSearchRequest) async throws -> [SearchResult] {
        let credential: ResolvedCredential
        switch await resolveGate() {
        case .fetch(let resolved): credential = resolved
        case .off, .notConfigured: throw SearchSourceFailure(.notConfigured)
        case .unavailable: throw SearchSourceFailure(.credentialsUnavailable)
        }
        let tasks = try await HostAzureDevOpsLoader.search(
            organization: credential.organization,
            projects: credential.projects,
            token: credential.token,
            text: request.text,
            kind: request.kind)
        return TaskSearch.results(from: tasks, query: request.text)
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
}

// MARK: - Commits

/// `git log --grep` over the repositories GitBox scans. Local: nothing is sent
/// anywhere.
@MainActor
final class CommitSearchSource: AsyncSearchSource {
    let provider = SearchProviderID.commit
    private var repos: [URL]?

    func beginSession() { repos = nil }

    func search(_ request: AsyncSearchRequest) async throws -> [SearchResult] {
        let tokens = GitCommitSearch.tokens(for: request.text)
        guard GitCommitSearch.canRun(tokens: tokens) else { return [] }

        let repos = await discoverRepos()
        guard !repos.isEmpty else { throw SearchSourceFailure(.noRepositories) }
        let rows = await HostGitCommitSearch.search(repos: repos, tokens: tokens)
        return GitCommitSearch.results(from: rows)
    }

    /// Reads the settings and walks the scan roots off the main actor, once per
    /// panel session: a directory walk is cheap but not free.
    private func discoverRepos() async -> [URL] {
        if let repos { return repos }
        let found = await Task.detached { () -> [URL] in
            let settings = DeckSettings.load().gitbox
            return HostGitBoxSampler.discoverRepos(paths: settings.repoPaths, depth: settings.scanDepth)
        }.value
        repos = found
        return found
    }
}
