import Foundation

// MARK: - PRBox snapshot
//
// Pull requests are a network fetch — the widget sandbox has no network
// entitlement — so the host agent fetches them every 60s and writes this
// snapshot into the container. The PRBox widget renders it; tokens are sent
// only to api.github.com and dev.azure.com over TLS, and none is ever
// defaulted.
//
// The model is provider-agnostic in the same way `TaskItem` is: `id` is a
// String so a provider with non-numeric keys fits, and `provider` names the
// source, so GitLab or Bitbucket extend the enum rather than migrating the
// store.
//
// There is no "last updated" concept, on purpose. The Azure DevOps PR payload
// carries no update timestamp at all — only `creationDate` — so sorting GitHub
// by `updated_at` and Azure by creation would mean one list ordered by two
// different facts, sinking a freshly-pushed Azure PR below a stale GitHub one.
// Creation date is the key both providers can actually promise.

enum PRProvider: String, Codable, Equatable {
    case github
    case azureDevOps
    /// A provider written by a newer agent that this build doesn't know.
    /// Present so one unknown string can't throw away the whole queue.
    case unknown
}

/// Why you are looking at this pull request. Strict on decode — see
/// `PullRequestItem.init(from:)`.
enum PRRole: String, Codable, Equatable {
    case authored
    case reviewing
}

struct PullRequestItem: Codable, Equatable {
    /// "github:owner/repo#41" — a String so a provider with non-numeric ids
    /// fits without reshaping the store.
    var id: String
    var number: Int
    var title: String
    /// Short repository name ("deck", "manifold"), not "owner/repo": the row
    /// truncates the repo before the title, and the owner is rarely the part
    /// that identifies the PR at a glance.
    var repo: String
    var role: PRRole
    var provider: PRProvider
    var isDraft: Bool
    var createdAt: Date
    var url: String

    init(
        id: String, number: Int, title: String, repo: String, role: PRRole,
        provider: PRProvider, isDraft: Bool, createdAt: Date, url: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.repo = repo
        self.role = role
        self.provider = provider
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.url = url
    }

    /// Tolerant on `provider` only. `id`, `number`, `title` and `role` stay
    /// required:
    ///
    /// - a row without an id or title is not a pull request, and a blank line
    ///   reads as a rendering bug rather than as missing data;
    /// - `role` has no honest default — calling an unknown role `.authored`
    ///   inflates the MINE count and `.reviewing` inflates the review queue.
    ///   Both are wrong numbers, which is worse than one absent row.
    ///
    /// `PRBoxSnapshot` drops rows that fail this, so being strict here costs
    /// one row rather than the list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        role = try c.decode(PRRole.self, forKey: .role)
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? ""
        let rawProvider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        provider = PRProvider(rawValue: rawProvider) ?? .unknown
        isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}

struct PRBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    /// Open pull requests you authored — the header number, which can exceed
    /// `pullRequests.count` when the row cap trims the stored rows.
    var authoredCount: Int
    /// Open pull requests awaiting your review, same relationship.
    var reviewingCount: Int
    /// True when the count saturated the fetch ceiling and is a floor rather
    /// than a total. Azure DevOps reports no total for a PR query — the
    /// response carries `count` (rows returned) and nothing else — so a large
    /// enough queue can only be reported as "100+". GitHub's search
    /// `total_count` is independent of `per_page`, so its half is never capped.
    var authoredCapped: Bool
    var reviewingCapped: Bool
    /// Pre-sorted and pre-deduped by `PRFormatting` — the widget renders, it
    /// does not decide.
    var pullRequests: [PullRequestItem]

    init(
        writtenAt: Date, authoredCount: Int, reviewingCount: Int,
        authoredCapped: Bool, reviewingCapped: Bool, pullRequests: [PullRequestItem]
    ) {
        self.writtenAt = writtenAt
        self.authoredCount = authoredCount
        self.reviewingCount = reviewingCount
        self.authoredCapped = authoredCapped
        self.reviewingCapped = reviewingCapped
        self.pullRequests = pullRequests
    }

    /// Lossy on the row array: a row this build cannot decode is skipped and
    /// the rest render. A snapshot written before the capped flags existed
    /// reports uncapped counts, which is exactly what it meant.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writtenAt = try c.decode(Date.self, forKey: .writtenAt)
        authoredCount = try c.decodeIfPresent(Int.self, forKey: .authoredCount) ?? 0
        reviewingCount = try c.decodeIfPresent(Int.self, forKey: .reviewingCount) ?? 0
        authoredCapped = try c.decodeIfPresent(Bool.self, forKey: .authoredCapped) ?? false
        reviewingCapped = try c.decodeIfPresent(Bool.self, forKey: .reviewingCapped) ?? false
        var rows: [PullRequestItem] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .pullRequests) {
            while !list.isAtEnd {
                // A failed row still has to be consumed, or the loop never
                // advances past it.
                if let row = try? list.decode(PullRequestItem.self) {
                    rows.append(row)
                } else {
                    _ = try? list.decode(AnyRow.self)
                }
            }
        }
        pullRequests = rows
    }

    /// Consumes one array element whatever its shape, so a malformed row can be
    /// skipped without stalling the decoder.
    private struct AnyRow: Decodable {
        init(from decoder: Decoder) throws {
            _ = try decoder.singleValueContainer()
        }
    }
}

// MARK: - Formatting (pure)
//
// Everything the widget must not decide for itself.

enum PRFormatting {
    /// Newest first by creation date. Ties break on (provider, repo, number) so
    /// the order is identical between ticks — an order that reshuffles on its
    /// own looks like data changing when nothing did.
    static func sorted(_ items: [PullRequestItem]) -> [PullRequestItem] {
        items.sorted { a, b in
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            if a.provider.rawValue != b.provider.rawValue {
                return a.provider.rawValue < b.provider.rawValue
            }
            if a.repo != b.repo { return a.repo < b.repo }
            return a.number < b.number
        }
    }

    /// One row per pull request, keyed by (provider, repo, number).
    ///
    /// Azure DevOps lets you be a reviewer on your own pull request and the
    /// unvoted filter keeps it, so the same PR really does arrive from both
    /// role queries. `.authored` wins: you cannot review your own PR, so
    /// showing it in the review queue would be a task you can't act on.
    static func deduped(_ items: [PullRequestItem]) -> [PullRequestItem] {
        struct Key: Hashable {
            let provider: PRProvider
            let repo: String
            let number: Int
        }

        var byKey: [Key: PullRequestItem] = [:]
        var order: [Key] = []
        for item in items {
            let key = Key(provider: item.provider, repo: item.repo, number: item.number)
            if let existing = byKey[key] {
                if existing.role == .reviewing && item.role == .authored {
                    byKey[key] = item
                }
            } else {
                byKey[key] = item
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
    }

    /// "0m" / "59m" / "3h" / "10d" — suffix-less on purpose.
    /// `OpenBoxCore.relativeTime` says "2h ago", which is right inside a
    /// sentence and noise in a right-aligned column.
    ///
    /// Clamped at zero: the API host's clock can run ahead of this machine's,
    /// and "-1m" would read as a bug.
    static func age(from date: Date, to now: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(date)))
        switch seconds {
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    /// "3", or "100+" when the number is a floor rather than a total.
    static func countLabel(_ count: Int, capped: Bool) -> String {
        capped ? "\(count)+" : "\(count)"
    }
}

// MARK: - Store

enum PRBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("prbox.json")
    }

    static func load() -> PRBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PRBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: PRBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}
