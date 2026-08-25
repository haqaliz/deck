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
        case serverError(Int)
        case transport(String)
        case invalidPayload
    }

    /// Fetches the most recent Actions runs for `repo` ("owner/repo").
    static func fetch(repo: String, token: String) async throws -> ShipBoxSnapshot {
        let url = try makeURL(repo: repo)

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
        guard let parsed = RunParser.parse(data) else {
            throw GitHubError.invalidPayload
        }
        return ShipBoxSnapshot(
            writtenAt: Date(),
            repos: [repo],
            runs: parsed.runs.map { run in
                var tagged = run
                tagged.repo = repo
                return tagged
            }
        )
    }

    private static func makeURL(repo: String) throws -> URL {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let encoded, encoded.contains("/") else { throw GitHubError.invalidRepo }
        guard let url = URL(string: "https://api.github.com/repos/\(encoded)/actions/runs?per_page=10") else {
            throw GitHubError.invalidRepo
        }
        return url
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
