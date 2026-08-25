import Foundation

// MARK: - ShipBox snapshot
//
// GitHub Actions runs are a network fetch — the widget sandbox has no network
// entitlement — so the host agent fetches run status every 60s and writes this
// snapshot into the container. The ShipBox widget renders it; no token is ever
// defaulted or sent anywhere but api.github.com over TLS.

struct ShipBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    /// The "owner/repo" targets this snapshot was built from, in display
    /// order — the configured list in static mode, the discovered one in
    /// dynamic mode. A repo that failed this tick is still listed; its runs
    /// are simply absent and `note` says why.
    var runs: [ShipRun]
    var repos: [String]
    /// One line naming the repos that failed while others succeeded, or nil.
    /// Partial failure is reported here rather than through `FetchStatus`,
    /// which has one key for the whole widget (PRD §6).
    var note: String?

    init(writtenAt: Date, repos: [String], runs: [ShipRun], note: String? = nil) {
        self.writtenAt = writtenAt
        self.repos = repos
        self.runs = runs
        self.note = note
    }

    /// Tolerant: a snapshot written before multi-repo carries a single `repo`
    /// string and runs with no repo of their own. Without this the first tick
    /// after an upgrade fails to decode, `load()` returns nil, and the face
    /// says "No build data" for a widget that has perfectly good data on disk.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writtenAt = try c.decode(Date.self, forKey: .writtenAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        let legacyRepo = try c.decodeIfPresent(String.self, forKey: .legacyRepo)
        if let decoded = try c.decodeIfPresent([String].self, forKey: .repos) {
            repos = decoded
        } else if let legacyRepo, !legacyRepo.isEmpty {
            repos = [legacyRepo]
        } else {
            repos = []
        }
        let decodedRuns = try c.decodeIfPresent([ShipRun].self, forKey: .runs) ?? []
        // A legacy run belongs to the only repo there was.
        runs = decodedRuns.map { run in
            guard run.repo.isEmpty, let legacyRepo else { return run }
            var tagged = run
            tagged.repo = legacyRepo
            return tagged
        }
    }

    /// Writes only the current shape; the legacy `repo` key is read on the way
    /// in and dropped on the way out.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(writtenAt, forKey: .writtenAt)
        try c.encode(runs, forKey: .runs)
        try c.encode(repos, forKey: .repos)
        try c.encodeIfPresent(note, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey {
        case writtenAt, runs, repos, note
        case legacyRepo = "repo"
    }
}

enum ShipStatus: String, Codable, Equatable {
    case queued
    case running
    case success
    case failure
    case neutral

    /// GitHub run status/conclusion pair → Deck status.
    static func map(status: String?, conclusion: String?) -> ShipStatus {
        switch (status, conclusion) {
        case ("queued", _), ("waiting", _), ("requested", _), ("pending", _):
            return .queued
        case ("in_progress", _):
            return .running
        case ("completed", "success"):
            return .success
        case ("completed", "failure"), ("completed", "timed_out"),
             ("completed", "action_required"), ("completed", "stale"):
            return .failure
        default:
            return .neutral
        }
    }
}

struct ShipRun: Codable, Equatable {
    /// "owner/repo" this run belongs to. Empty only when decoded from a
    /// pre-multi-repo snapshot that had no per-run repo.
    var repo: String = ""
    var name: String
    var runNumber: Int
    var branch: String
    var status: ShipStatus
    var createdAt: Date
    var updatedAt: Date
    var htmlURL: String

    init(
        repo: String = "",
        name: String,
        runNumber: Int,
        branch: String,
        status: ShipStatus,
        createdAt: Date,
        updatedAt: Date,
        htmlURL: String
    ) {
        self.repo = repo
        self.name = name
        self.runNumber = runNumber
        self.branch = branch
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.htmlURL = htmlURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? ""
        name = try c.decode(String.self, forKey: .name)
        runNumber = try c.decode(Int.self, forKey: .runNumber)
        branch = try c.decode(String.self, forKey: .branch)
        status = try c.decode(ShipStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        htmlURL = try c.decode(String.self, forKey: .htmlURL)
    }
}

enum ShipBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("shipbox.json")
    }

    static func load() -> ShipBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ShipBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: ShipBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}

// MARK: - Merging, labelling and wording (pure)

enum ShipBoxMerge {
    /// One list from many repos, newest first.
    ///
    /// Creation date is the key every source can promise (the rule PRBox
    /// arrived at for GitHub + Azure); ties keep the order the repos were
    /// fetched in, so a stable snapshot never reshuffles between ticks.
    static func merge(_ perRepo: [[ShipRun]]) -> [ShipRun] {
        perRepo
            .enumerated()
            .flatMap { index, runs in runs.map { (index, $0) } }
            .sorted { lhs, rhs in
                if lhs.1.createdAt != rhs.1.createdAt { return lhs.1.createdAt > rhs.1.createdAt }
                return lhs.0 < rhs.0
            }
            .map(\.1)
    }
}

enum ShipBoxLabels {
    /// "owner/repo" → what a row calls it.
    ///
    /// The owner is noise when every repo shares one, so it is dropped — but
    /// only while the short names stay unique. One collision and *every* row
    /// shows its owner, because a list that mixes "deck" and "b/deck" reads as
    /// two naming schemes rather than one disambiguation.
    static func labels(for repos: [String]) -> [String: String] {
        let shortNames = repos.map { repo -> String in
            guard let slash = repo.lastIndex(of: "/") else { return repo }
            return String(repo[repo.index(after: slash)...])
        }
        var counts: [String: Int] = [:]
        for name in shortNames { counts[name.lowercased(), default: 0] += 1 }
        let collides = counts.values.contains { $0 > 1 }
        return Dictionary(
            zip(repos, collides ? repos : shortNames),
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// The wording ShipBox uses for a *partial* failure — some repos answered,
/// others didn't. A total failure goes through `FetchStatus` as before.
enum ShipBoxNote {
    struct Failure: Equatable {
        var repo: String
        var outcome: FetchOutcome
    }

    /// Composed by the rule `PRChip.text` already applies to two providers:
    /// one failure names itself, several sharing a reason collapse into one
    /// sentence, and mixed reasons name the first rather than implying a
    /// shared cause.
    static func compose(failures: [Failure], mode: ShipBoxRepoMode) -> String? {
        guard let first = failures.first else { return nil }
        guard let reason = ShipBoxCopy.composableLine(outcome: first.outcome, mode: mode) else { return nil }
        let labels = ShipBoxLabels.labels(for: failures.map(\.repo))
        let name = labels[first.repo] ?? first.repo
        let others = failures.count - 1
        guard others > 0 else { return "\(name): \(reason)" }
        if failures.allSatisfy({ $0.outcome == first.outcome }) {
            return "\(name) + \(others) more: \(reason)"
        }
        return "\(name): \(reason) +\(others) more"
    }
}

/// ShipBox's failure copy, which depends on the repo mode as well as the
/// outcome.
///
/// `FetchStatusCopy` is keyed by `FetchSource` alone, so `.shipbox` always
/// reads "Check repo + token" — and in dynamic mode there is no repo field to
/// check. Sending someone to a control their tab does not have is the same
/// class of lie the fetch-status work existed to remove, so the wording is
/// substituted here rather than by adding a `FetchSource` case: both sub-tabs
/// share one fetch, and per-source keys exist to give each *tab* its own
/// sentence.
enum ShipBoxCopy {
    static func line(outcome: FetchOutcome, mode: ShipBoxRepoMode) -> String? {
        guard mode == .dynamic else { return FetchStatusCopy.line(source: .shipbox, outcome: outcome) }
        switch outcome {
        case .notConfigured: return "Add a token in settings"
        case .authOrTarget: return "Check your token"
        default: return FetchStatusCopy.line(source: .shipbox, outcome: outcome)
        }
    }

    /// The same line, lowercased at the front so it can sit after "repo: ".
    /// Only the first character changes, so "GitHub" survives intact.
    static func composableLine(outcome: FetchOutcome, mode: ShipBoxRepoMode) -> String? {
        guard let line = line(outcome: outcome, mode: mode), let first = line.first else { return nil }
        return line.replacingCharacters(in: line.startIndex...line.startIndex, with: first.lowercased())
    }
}

// MARK: - GitHub Actions fetch (host/agent only — unsandboxed)

enum HostGitHubLoader {
    enum GitHubError: Error {
        case invalidRepo
        case notConfigured
        case serverError(Int)
        case transport(String)
        case invalidPayload
    }

    /// Fetches Actions runs for every repo ShipBox is watching and merges
    /// them into one snapshot.
    ///
    /// Partial-failure policy (PRD §6), the same one `HostMarketLoader` applies
    /// to its four providers: each repo is fetched best-effort, a repo that
    /// fails contributes no runs but is named in `note`, and the fetch only
    /// throws when **no** repo produced runs and at least one errored. Every
    /// repo answering with zero runs is a success, not a failure — that is a
    /// user with CI they haven't run yet, not a broken widget.
    static func fetch(settings: ShipBoxSettings) async throws -> ShipBoxSnapshot {
        let token = settings.token
        guard !token.isEmpty else { throw GitHubError.notConfigured }

        let repos: [String]
        switch settings.repoMode {
        case .staticList:
            repos = settings.repos
        case .dynamic:
            // An inventory failure is *its own* error, never "not configured":
            // telling someone to add a repo when their token was revoked sends
            // them to the wrong field entirely (PRD C1).
            repos = try await discover(maxCount: settings.maxRepoCount, token: token)
        }
        guard !repos.isEmpty else { throw GitHubError.notConfigured }

        let perPage = min(max(settings.runCount, 2), 8)
        let results = try await inParallel(repos) { repo in
            try await runs(repo: repo, token: token, perPage: perPage)
        }

        var perRepoRuns: [[ShipRun]] = []
        var failures: [ShipBoxNote.Failure] = []
        var firstError: Error?
        for (repo, result) in zip(repos, results) {
            switch result {
            case .success(let runs):
                perRepoRuns.append(runs)
            case .failure(let error):
                perRepoRuns.append([])
                failures.append(.init(repo: repo, outcome: FetchClassifier.outcome(for: error)))
                firstError = firstError ?? error
            }
        }

        let merged = ShipBoxMerge.merge(perRepoRuns)
        // Nothing came back and something broke: report the failure and let the
        // last-good snapshot stand rather than overwriting it with emptiness.
        if merged.isEmpty, let firstError { throw firstError }

        return ShipBoxSnapshot(
            writtenAt: Date(),
            repos: repos,
            runs: merged,
            note: ShipBoxNote.compose(failures: failures, mode: settings.repoMode)
        )
    }

    /// Dynamic mode: the repos pushed to most recently that have any runs.
    ///
    /// Two waves, because a run object embeds the whole repository object at
    /// ~11 KB per run (probe P5): wave 1 asks each candidate for a single run
    /// purely to learn whether it has CI, wave 2 fetches in full only the
    /// winners. Fetching every candidate in full would cost roughly twice the
    /// bandwidth for the same eight rows.
    private static func discover(maxCount: Int, token: String) async throws -> [String] {
        let inventory = try await inventory(token: token)
        let candidates = DynamicRepoSelector.candidates(inventory: inventory, maxCount: maxCount)
        guard !candidates.isEmpty else { return [] }
        let probes = try await inParallel(candidates) { repo in
            try await runs(repo: repo, token: token, perPage: 1)
        }
        let probed = zip(candidates, probes).map { repo, result in
            (repo: repo, hasRuns: !((try? result.get()) ?? []).isEmpty)
        }
        return DynamicRepoSelector.select(probed: probed, maxCount: maxCount)
    }

    private static func inventory(token: String) async throws -> [String] {
        guard let url = URL(string: "https://api.github.com/user/repos?sort=pushed&per_page=100&affiliation=owner") else {
            throw GitHubError.invalidRepo
        }
        guard let parsed = RepoInventoryParser.parse(try await get(url, token: token)) else {
            throw GitHubError.invalidPayload
        }
        return parsed
    }

    private static func runs(repo: String, token: String, perPage: Int) async throws -> [ShipRun] {
        let data = try await get(try makeURL(repo: repo, perPage: perPage), token: token)
        guard let parsed = RunParser.parse(data) else { throw GitHubError.invalidPayload }
        return parsed.runs.map { run in
            var tagged = run
            tagged.repo = repo
            return tagged
        }
    }

    /// Runs one request per element concurrently, in input order.
    ///
    /// The codebase's first concurrent fetch, and it is not a flourish: five
    /// repos fetched serially measured 9.4s, and the 10s per-request timeout
    /// puts the serial worst case past the 60s tick the agent runs on.
    /// Concurrently the same five took 2.1s.
    private static func inParallel<T>(
        _ repos: [String],
        _ work: @escaping (String) async throws -> T
    ) async throws -> [Result<T, Error>] {
        try await withThrowingTaskGroup(of: (Int, Result<T, Error>).self) { group in
            for (index, repo) in repos.enumerated() {
                group.addTask {
                    do { return (index, .success(try await work(repo))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var collected: [(Int, Result<T, Error>)] = []
            for try await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GitHubError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.transport("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            throw GitHubError.serverError(http.statusCode)
        }
        return data
    }

    private static func makeURL(repo: String, perPage: Int) throws -> URL {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let encoded, encoded.contains("/") else { throw GitHubError.invalidRepo }
        guard let url = URL(string: "https://api.github.com/repos/\(encoded)/actions/runs?per_page=\(perPage)") else {
            throw GitHubError.invalidRepo
        }
        return url
    }
}

// MARK: - Repo inventory (dynamic mode)

/// Reads `/user/repos`. The API is asked for `sort=pushed`, so its order is
/// the answer and the parser imposes none of its own.
enum RepoInventoryParser {
    static func parse(_ data: Data) -> [String]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return list.compactMap { entry in
            guard let name = entry["full_name"] as? String, !name.isEmpty else { return nil }
            // An archived repo is read-only and cannot produce a new run, so
            // probing it would spend a candidate slot for nothing.
            if (entry["archived"] as? Bool) == true { return nil }
            return name
        }
    }
}

/// Picks which discovered repos are worth a full fetch.
///
/// Nothing in a repo object says whether it has Actions (probe P3), so the
/// only way to know is to ask — cheaply, at `per_page=1`, for a few more repos
/// than are wanted, and then fetch in full only the ones that answered.
enum DynamicRepoSelector {
    /// Hard ceiling on probes per tick: the buffer exists to find repos with
    /// CI, not to walk the whole account.
    static let maxCandidates = 8

    static func candidates(inventory: [String], maxCount: Int) -> [String] {
        Array(inventory.prefix(min(maxCount + 3, maxCandidates)))
    }

    /// `probed` is in candidate order; `hasRuns == false` covers both "no runs"
    /// and "the probe failed" — neither is worth a full fetch this tick, and a
    /// failed probe gets another chance on the next one.
    static func select(probed: [(repo: String, hasRuns: Bool)], maxCount: Int) -> [String] {
        probed.filter(\.hasRuns).prefix(maxCount).map(\.repo)
    }
}

// MARK: - GitHub runs parser
//
// Contract notes: every field is a JSON string; conclusion is null while a run
// is not completed; dates are ISO8601 ("2026-08-14T10:00:00Z").

struct ParsedRuns: Equatable {
    var totalCount: Int
    var runs: [ShipRun]
}

enum RunParser {
    static func parse(_ data: Data) -> ParsedRuns? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let runsList = json["workflow_runs"] as? [[String: Any]]
        else { return nil }

        let total = (json["total_count"] as? NSNumber)?.intValue
            ?? Int(json["total_count"] as? String ?? "") ?? runsList.count

        return ParsedRuns(totalCount: total, runs: runsList.compactMap(run(from:)))
    }

    private static func run(from entry: [String: Any]) -> ShipRun? {
        guard let name = entry["name"] as? String else { return nil }
        let status = ShipStatus.map(
            status: entry["status"] as? String,
            conclusion: entry["conclusion"] as? String
        )
        return ShipRun(
            name: name,
            runNumber: intValue(entry["run_number"]) ?? 0,
            branch: (entry["head_branch"] as? String) ?? "",
            status: status,
            createdAt: dateValue(entry["created_at"]) ?? Date(timeIntervalSince1970: 0),
            updatedAt: dateValue(entry["updated_at"]) ?? Date(timeIntervalSince1970: 0),
            htmlURL: (entry["html_url"] as? String) ?? ""
        )
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String, !string.isEmpty { return Int(string) }
        return nil
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }
        return Self.dateFormatter.date(from: string)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - Formatting (used by the widget face)

enum RunFormatting {
    struct Totals: Equatable {
        var success = 0
        var failure = 0
        var running = 0
        var queued = 0
        var neutral = 0
    }

    static func totals(for runs: [ShipRun]) -> Totals {
        var totals = Totals()
        for run in runs {
            switch run.status {
            case .success: totals.success += 1
            case .failure: totals.failure += 1
            case .running: totals.running += 1
            case .queued: totals.queued += 1
            case .neutral: totals.neutral += 1
            }
        }
        return totals
    }

    /// "2 fail · 3 pass · 1 run" — neutral/queued skipped when zero.
    static func totalsLine(for runs: [ShipRun]) -> String {
        let totals = totals(for: runs)
        var parts: [String] = []
        if totals.failure > 0 { parts.append("\(totals.failure) fail") }
        if totals.success > 0 { parts.append("\(totals.success) pass") }
        if totals.running > 0 { parts.append("\(totals.running) run") }
        if totals.queued > 0 { parts.append("\(totals.queued) queued") }
        return parts.joined(separator: " · ")
    }

    /// "3m12s" / "0m45s" / "1h04m" for completed runs.
    static func duration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%dh%02dm", hours, minutes)
        }
        return "\(minutes)m\(secs)s"
    }

    /// Row trailing text: "main · 3m12s", "main · QUEUED", "feat/x · RUNNING".
    static func detail(for run: ShipRun) -> String {
        let branch = run.branch.isEmpty ? "—" : run.branch
        switch run.status {
        case .queued:
            return "\(branch) · QUEUED"
        case .running:
            return "\(branch) · RUNNING"
        case .success, .failure, .neutral:
            return "\(branch) · \(duration(from: run.createdAt, to: run.updatedAt))"
        }
    }
}
