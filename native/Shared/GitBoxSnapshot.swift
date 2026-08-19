import Foundation

// MARK: - GitBox snapshot
//
// git log is a subprocess — blocked in the sandboxed widget — so the host
// agent scans repos, runs git log, and writes this snapshot into the
// container. The GitBox widget renders it.

struct GitBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    var todayCount: Int
    var streak: Int
    /// Last 15 calendar days, oldest first.
    var days: [DayCount]
    /// Repos with commits in the window, sorted by today's count desc.
    var repos: [RepoInfo]

    struct DayCount: Codable, Equatable {
        let day: String
        let count: Int
    }

    struct RepoInfo: Codable, Equatable {
        let shortName: String
        let path: String
        let todayCount: Int
    }
}

enum GitBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("gitbox.json")
    }

    static func load() -> GitBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(GitBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: GitBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}

/// Runs git discovery/log — host/agent only (unsandboxed).
enum HostGitBoxSampler {
    /// Full snapshot for the given settings; nil when nothing can be read.
    static func snapshot(paths: [String], scanDepth: Int) -> GitBoxSnapshot? {
        let repos = discoverRepos(paths: paths, depth: scanDepth)
        guard !repos.isEmpty else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = calendar.startOfDay(for: Date())
        let todayLabel = dayLabel(today, calendar: calendar)

        let sample = sample(repos: repos, today: todayLabel)
        let window = daysBack(15, today: Date(), calendar: calendar)
        let counts = Dictionary(uniqueKeysWithValues: sample.dayCounts.map { ($0.day, $0.count) })

        let sortedRepos = sample.repos
            .sorted {
                if $0.todayCount != $1.todayCount { return $0.todayCount > $1.todayCount }
                return $0.shortName < $1.shortName
            }

        return GitBoxSnapshot(
            writtenAt: Date(),
            todayCount: counts[todayLabel] ?? 0,
            streak: streak(counts: counts, window: window),
            days: window.compactMap { day in
                GitBoxSnapshot.DayCount(day: day, count: counts[day] ?? 0)
            },
            repos: sortedRepos.map {
                GitBoxSnapshot.RepoInfo(
                    shortName: shortName(path: $0.path),
                    path: $0.path,
                    todayCount: $0.todayCount
                )
            }
        )
    }

    // MARK: - Repo discovery (ported from the window GitBox)

    private static func discoverRepos(paths: [String], depth: Int) -> [URL] {
        // No default scan root: the user configures repo paths explicitly.
        var repos: [URL] = []
        for root in paths {
            let url = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            scan(url, depth: depth, into: &repos)
        }
        return repos
    }

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

    private static func sample(
        repos: [URL],
        today: String
    ) -> (repos: [GitBoxSnapshot.RepoInfo], dayCounts: [(day: String, count: Int)]) {
        var dayCounts: [String: Int] = [:]
        var perRepo: [GitBoxSnapshot.RepoInfo] = []
        for repo in repos {
            guard let raw = gitLogDays(repo) else { continue }
            let counts = GitLogParser.dayCounts(from: raw)
            for (day, count) in counts {
                dayCounts[day, default: 0] += count
            }
            perRepo.append(GitBoxSnapshot.RepoInfo(
                shortName: shortName(path: repo.path),
                path: repo.path,
                todayCount: counts[today] ?? 0
            ))
        }
        return (perRepo, dayCounts.map { (day: $0.key, count: $0.value) })
    }

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
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    // MARK: - Math/formatting (ported from GitBoxCore; internal for tests)

    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    static func daysBack(_ n: Int, today: Date, calendar: Calendar) -> [String] {
        guard n > 0 else { return [] }
        return (0..<n).map { offset in
            let date = calendar.date(byAdding: .day, value: -(n - 1 - offset), to: today) ?? today
            return dayLabel(date, calendar: calendar)
        }
    }

    static func streak(counts: [String: Int], window: [String]) -> Int {
        var index = window.count - 1
        guard index >= 0 else { return 0 }
        if (counts[window[index]] ?? 0) == 0 {
            index -= 1
        }
        var run = 0
        while index >= 0 {
            guard (counts[window[index]] ?? 0) > 0 else { break }
            run += 1
            index -= 1
        }
        return run
    }

    static func shortName(path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? path
    }
}

enum GitLogParser {
    static func dayCounts(from raw: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in raw.split(separator: "\n") {
            let day = String(line)
            guard isDayLabel(day) else { continue }
            counts[day, default: 0] += 1
        }
        return counts
    }

    private static func isDayLabel(_ day: String) -> Bool {
        guard day.count == 10, day[day.index(day.startIndex, offsetBy: 4)] == "-",
              day[day.index(day.startIndex, offsetBy: 7)] == "-",
              day.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
        guard let date = formatter.date(from: day) else { return false }
        return formatter.string(from: date) == day
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
