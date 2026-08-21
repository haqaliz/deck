import Foundation

// MARK: - TaskBox snapshot
//
// Work items are a network fetch — the widget sandbox has no network
// entitlement — so the host agent fetches them every 60s and writes this
// snapshot into the container. The TaskBox widget renders it; no token is ever
// defaulted or sent anywhere but dev.azure.com over TLS.
//
// The model is deliberately provider-agnostic: `id` is a String (so Jira's
// "PROJ-1" fits without a reshape) and `provider` names the source, so GitHub
// Issues / Linear / Reminders extend the enum rather than migrating the store.
//
// There is no due-date concept, on purpose. Azure DevOps has no dependable due
// field: DueDate and TargetDate are sparse, and falling back to the sprint end
// gave every item in a sprint the same date, which looked like information and
// wasn't. Progress through the board is the real signal.

enum TaskProvider: String, Codable, Equatable {
    case azureDevOps
    /// A provider written by a newer agent that this build doesn't know.
    /// Present so one unknown string can't throw away the whole task list.
    case unknown
}

struct TaskItem: Codable, Equatable {
    var id: String
    var title: String
    /// Raw provider state ("To Do", "Committed", "In Progress"). Kept raw and
    /// mapped at render time, so a renamed process state is a settings edit
    /// rather than a rebuild.
    var state: String
    var itemType: String
    var url: String
    var provider: TaskProvider
    var changedAt: Date?

    init(
        id: String, title: String, state: String, itemType: String,
        url: String, provider: TaskProvider, changedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.itemType = itemType
        self.url = url
        self.provider = provider
        self.changedAt = changedAt
    }

    /// Tolerant on `provider` only: an unknown one reads as `.unknown` so a
    /// snapshot from a newer agent still renders. `id` and `title` stay
    /// required — an item without them is not a task.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        let rawProvider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        provider = TaskProvider(rawValue: rawProvider) ?? .unknown
        changedAt = try c.decodeIfPresent(Date.self, forKey: .changedAt)
    }
}

struct TaskBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    /// "{project}", or "{org} / {project}" when they differ.
    var scope: String
    /// Every open item assigned to the user — uncapped, so it can exceed
    /// `tasks.count` when the fetch limit trims the stored rows.
    var totalCount: Int
    /// Current sprint name, e.g. "Sprint 57". nil when the team has no current
    /// iteration or the call failed.
    var sprint: String?
    /// Pre-sorted by `TaskFormatting.sorted` — the widget renders, it does not
    /// decide.
    var tasks: [TaskItem]

    init(writtenAt: Date, scope: String, totalCount: Int, sprint: String?, tasks: [TaskItem]) {
        self.writtenAt = writtenAt
        self.scope = scope
        self.totalCount = totalCount
        self.sprint = sprint
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writtenAt = try c.decode(Date.self, forKey: .writtenAt)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? ""
        totalCount = try c.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
        sprint = try c.decodeIfPresent(String.self, forKey: .sprint)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
    }
}

enum TaskBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("taskbox.json")
    }

    static func load() -> TaskBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(TaskBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: TaskBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}

// MARK: - Lanes
//
// Azure DevOps runs two vocabularies on one board: Tasks move
// To Do → In Progress → Done, while PBIs / Bugs / Features move
// New → Approved → Committed → Done. The widget shows one lifecycle.

enum TaskLane: String, Codable, CaseIterable, Equatable {
    case todo
    case inProgress
    case testing
    /// Anything the mapping doesn't recognise. Counted rather than dropped, so
    /// the legend always reconciles with the rows it describes.
    case other

    var label: String {
        switch self {
        case .todo: "TO DO"
        case .inProgress: "IN PROGRESS"
        case .testing: "TESTING"
        case .other: "OTHER"
        }
    }
}

/// Which raw states feed which lane. Editable in settings because process
/// templates get customised and board columns get renamed — that should be a
/// text edit, not a new build.
struct TaskStateMapping: Codable, Equatable {
    var todo: String
    var inProgress: String
    var testing: String

    init(
        todo: String = "New, Approved, To Do, Open, Proposed",
        inProgress: String = "Committed, In Progress, Doing, Active, Started",
        testing: String = "Testing, In Test, QA, In Review, Review"
    ) {
        self.todo = todo
        self.inProgress = inProgress
        self.testing = testing
    }

    /// Tolerant per field: a mapping written by an older build, or one the user
    /// has only partly customised, keeps the defaults for the lanes it doesn't
    /// mention. Falling back to an empty string instead would silently send
    /// every state to "other".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TaskStateMapping()
        todo = try c.decodeIfPresent(String.self, forKey: .todo) ?? defaults.todo
        inProgress = try c.decodeIfPresent(String.self, forKey: .inProgress) ?? defaults.inProgress
        testing = try c.decodeIfPresent(String.self, forKey: .testing) ?? defaults.testing
    }

    /// Comma-separated, trimmed, case-insensitive. Blank entries are dropped so
    /// a trailing comma can't create a rule that matches the empty state.
    static func terms(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// First lane wins, so a state listed in two fields resolves predictably
    /// rather than by dictionary order.
    func lane(for state: String) -> TaskLane {
        let needle = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return .other }
        if Self.terms(todo).contains(needle) { return .todo }
        if Self.terms(inProgress).contains(needle) { return .inProgress }
        if Self.terms(testing).contains(needle) { return .testing }
        return .other
    }
}

// MARK: - Formatting (pure, used by the widget face)

enum TaskFormatting {
    /// Face order: most recently touched first, undated last. Deterministic and
    /// total — the comparator never depends on input order, so two identical
    /// ticks produce an identical list rather than reshuffling under the user.
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            let lc = lhs.changedAt ?? .distantPast
            let rc = rhs.changedAt ?? .distantPast
            if lc != rc { return lc > rc }
            // Last resort so the order is total even for identical keys.
            return lhs.id < rhs.id
        }
    }

    /// Every lane present, including zeroes, so the legend keeps a stable width
    /// instead of reflowing as work moves between columns.
    static func laneCounts(tasks: [TaskItem], mapping: TaskStateMapping) -> [TaskLane: Int] {
        var counts: [TaskLane: Int] = Dictionary(uniqueKeysWithValues: TaskLane.allCases.map { ($0, 0) })
        for task in tasks {
            counts[mapping.lane(for: task.state), default: 0] += 1
        }
        return counts
    }

    /// Header, left: how much is on your plate.
    static func totalLine(totalCount: Int) -> String {
        "\(totalCount) open"
    }
}
