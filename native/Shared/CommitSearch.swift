import Foundation

// MARK: - Commit search (GitBox)
//
// `git log --grep` across the repositories GitBox scans, of any age, on any
// branch. Local only: nothing is sent anywhere. Deferred rather than instant
// because it is a subprocess per repository.
//
// Typed text becomes arguments to a subprocess. There is no shell (the
// arguments are an array), but git treats `--output=…` and `--upload-pack=…` as
// options if typed text ever became an argument of its own. So every typed word
// is wrapped as `--grep=<word>` — one argument that cannot begin with a dash —
// and `CommitSearchTests` proves nothing else can leak.

struct GitCommitHit: Equatable {
    var hash: String
    var author: String
    var date: Date
    var subject: String

    var shortHash: String { String(hash.prefix(7)) }
}

enum GitCommitSearch {
    static let maxTokens = 5
    static let maxTokenLength = 100
    static let perRepoLimit = 8
    static let totalLimit = 25
    /// Field separator in `--format`: ASCII unit separator, which does not
    /// occur in a commit subject.
    static let fieldSeparator = "\u{1F}"

    /// Control characters out, split on whitespace, capped. Empty when there is
    /// too little to search for — and an empty list must never be run, because
    /// `git log` with no `--grep` lists every commit.
    static func tokens(for text: String) -> [String] {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : $0
        }))
        let words = cleaned.split(whereSeparator: { $0.isWhitespace })
            .prefix(maxTokens)
            .map { String($0.prefix(maxTokenLength)) }
        guard RemoteSearchPolicy.shouldSearch(words.joined(separator: " ")) else { return [] }
        return words
    }

    static func canRun(tokens: [String]) -> Bool { !tokens.isEmpty }

    /// The whole command, first element `git`. `-C <path>` consumes the repo
    /// path as its value even if it begins with a dash; each word is its own
    /// `--grep=` argument; `--all-match` makes them AND; `-F` makes them fixed
    /// strings, so typed text is never a regex; the trailing `--` ends options.
    static func arguments(repoPath: String, tokens: [String], limit: Int) -> [String] {
        var args = ["git", "-C", repoPath, "log", "--all", "-i", "-F", "--all-match"]
        args += tokens.map { "--grep=\($0)" }
        args += ["-n", String(limit), "--format=%H%x1f%an%x1f%ct%x1f%s", "--"]
        return args
    }

    /// Repositories' hits as panel results, newest first, capped overall.
    static func results(from rows: [(name: String, path: String, hits: [GitCommitHit])]) -> [SearchResult] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let all = rows.flatMap { row in
            row.hits.map { hit in
                SearchResult(
                    // The same commit is reachable from two clones.
                    id: "commit:\(row.path):\(hit.hash)",
                    provider: .commit,
                    title: hit.subject,
                    subtitle: [row.name, hit.shortHash, hit.author, formatter.string(from: hit.date)]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                    // Recency is the ranking: git already decided these match.
                    score: Int(hit.date.timeIntervalSince1970),
                    action: .copy(hit.shortHash)
                )
            }
        }
        return Array(SpotlightRanking.sorted(all).prefix(totalLimit))
    }
}

enum GitCommitParser {
    /// Lines of `hash \x1f author \x1f unix-time \x1f subject`. Anything that
    /// does not fit is skipped rather than failing the search.
    static func parse(_ raw: String) -> [GitCommitHit] {
        raw.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: Character(GitCommitSearch.fieldSeparator),
                                    maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4,
                  fields[0].count >= 7,
                  let seconds = TimeInterval(fields[2]),
                  !fields[3].isEmpty
            else { return nil }
            return GitCommitHit(
                hash: String(fields[0]),
                author: String(fields[1]),
                date: Date(timeIntervalSince1970: seconds),
                subject: String(fields[3]))
        }
    }
}

// MARK: - Running it (host/agent only — unsandboxed)

enum HostGitCommitSearch {
    /// Longest one repository may take before it is abandoned.
    static let timeout: TimeInterval = 5
    /// Repositories searched at once; a large scan root can hold dozens.
    static let concurrency = 6

    static func search(
        repos: [URL], tokens: [String]
    ) async -> [(name: String, path: String, hits: [GitCommitHit])] {
        guard GitCommitSearch.canRun(tokens: tokens) else { return [] }
        var rows: [(name: String, path: String, hits: [GitCommitHit])] = []
        var index = 0
        while index < repos.count, !Task.isCancelled {
            let chunk = repos[index..<min(index + concurrency, repos.count)]
            index += concurrency
            await withTaskGroup(of: (String, String, [GitCommitHit]).self) { group in
                for repo in chunk {
                    group.addTask {
                        let hits = await run(repo: repo, tokens: tokens)
                        return (HostGitBoxSampler.shortName(path: repo.path), repo.path, hits)
                    }
                }
                for await (name, path, hits) in group where !hits.isEmpty {
                    rows.append((name, path, hits))
                }
            }
        }
        return rows
    }

    private static func run(repo: URL, tokens: [String]) async -> [GitCommitHit] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(repo: repo, tokens: tokens))
            }
        }
    }

    private static func runBlocking(repo: URL, tokens: [String]) -> [GitCommitHit] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = GitCommitSearch.arguments(
            repoPath: repo.path, tokens: tokens, limit: GitCommitSearch.perRepoLimit)
        var environment = ProcessInfo.processInfo.environment
        // Never prompt, never take the index lock: this is a read on a repo the
        // user may be committing to.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = nil
        do { try process.run() } catch { return [] }

        // A repository on a stalled network volume must not hold the search.
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        // Read before waiting: waiting first can deadlock once the pipe fills.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [] }
        return GitCommitParser.parse(text)
    }
}
