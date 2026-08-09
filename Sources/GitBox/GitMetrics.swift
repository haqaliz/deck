import Foundation
import GitBoxCore

// MARK: - Git activity
//
// Repo discovery walks configured paths for `.git` (file or dir — covers
// worktrees and submodules) up to the configured depth. Per-repo commit days
// come from `git log` with `--date=format-local`, which renders each commit's
// author date as the machine's local calendar day.

enum GitMetricsLoader {
    /// Repos found under the configured paths (default `~/dev` when empty),
    /// each path scanned up to `depth` nested levels.
    static func discoverRepos(paths: [String], depth: Int) -> [URL] {
        let roots = paths.isEmpty ? [defaultRoot] : paths
        var repos: [URL] = []
        for root in roots {
            let url = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            scan(url, depth: depth, into: &repos)
        }
        return repos
    }

    /// Per-repo today counts + aggregate per-day counts from `git log`.
    static func sample(repos: [URL], today: String) -> (repos: [RepoCommits], dayCounts: [String: Int]) {
        var dayCounts: [String: Int] = [:]
        var perRepo: [RepoCommits] = []
        for repo in repos {
            guard let raw = gitLogDays(repo) else { continue }
            let counts = GitLogParser.dayCounts(from: raw)
            for (day, count) in counts {
                dayCounts[day, default: 0] += count
            }
            perRepo.append(RepoCommits(
                shortName: GitFormatters.shortName(path: repo.path),
                path: repo.path,
                todayCount: counts[today] ?? 0
            ))
        }
        return (perRepo, dayCounts)
    }

    private static let defaultRoot = "~/dev"

    /// Records `url` when it is a repo; otherwise descends until `depth` is
    /// exhausted. A repo's own subtree is not descended into.
    private static func scan(_ url: URL, depth: Int, into repos: inout [URL]) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        if children.contains(where: { $0.lastPathComponent == ".git" }) {
            repos.append(url)
            return
        }
        guard depth > 0 else { return }
        for child in children {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            scan(child, depth: depth - 1, into: &repos)
        }
    }

    /// `yyyy-MM-dd` author-date lines for the last 15 days; nil on failure.
    private static func gitLogDays(_ repo: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git", "-C", repo.path,
            "log", "--pretty=%ad",
            "--date=format-local:%Y-%m-%d",
            "--since=15.days.ago",
        ]
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )
    }
}
