import Foundation

public enum GitFormatters {
    /// Last path component of a repo path.
    public static func shortName(path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? path
    }

    /// Display names for the given repos, in order. Names that repeat get the
    /// last two path components (e.g. `at/deck`) so each row stays unique.
    public static func disambiguatedNames(repos: [RepoCommits]) -> [String] {
        var frequency: [String: Int] = [:]
        for repo in repos {
            frequency[shortName(path: repo.path), default: 0] += 1
        }
        return repos.map { repo in
            let name = shortName(path: repo.path)
            guard frequency[name] ?? 0 > 1 else { return name }
            return twoLevelName(path: repo.path)
        }
    }

    private static func twoLevelName(path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let parts = trimmed.split(separator: "/")
        guard parts.count >= 2 else { return shortName(path: path) }
        return parts.suffix(2).joined(separator: "/")
    }

    /// Commit counts as a plain number with thousands grouping.
    public static func commitCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}
