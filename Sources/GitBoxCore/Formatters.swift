import Foundation

public enum GitFormatters {
    /// Last path component of a repo path.
    public static func shortName(path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? path
    }

    /// Commit counts as a plain number with thousands grouping.
    public static func commitCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}
