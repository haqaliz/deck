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
    /// Which Azure project this row came from, when one account covers several.
    /// nil for a row written before the list existed, and for a provider with
    /// no such concept.
    var project: String?
    /// Which Azure **organization** this row came from, when the slot is bound
    /// to several accounts (a PAT is organization-scoped, so one account is one
    /// org). nil for a row written before the field existed, for a provider
    /// with no such concept, and for a single-org slot — where it would only
    /// repeat the header.
    var organization: String?
    /// Azure's `System.Tags`, split. Only Spotlight search asks for them; the
    /// widget never shows them. Empty for a row written before they existed.
    var tags: [String]

    init(
        id: String, title: String, state: String, itemType: String,
        url: String, provider: TaskProvider, changedAt: Date?,
        project: String? = nil, organization: String? = nil, tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.itemType = itemType
        self.url = url
        self.provider = provider
        self.changedAt = changedAt
        self.project = project
        self.organization = organization
        self.tags = tags
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
        project = try c.decodeIfPresent(String.self, forKey: .project)
        organization = try c.decodeIfPresent(String.self, forKey: .organization)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
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
    /// Which projects could not be read this tick, when the others could.
    /// nil when everything worked — a fetch that reaches none of its projects
    /// throws instead, so the last good snapshot stands.
    var note: String?
    /// At least one project matched more than the WIQL cap, so `totalCount`
    /// means "at least". The call is sent with `$top`, and Azure reports no
    /// total alongside it.
    var totalIsLowerBound = false
    /// Written from the user's own condition rather than the built-in filter.
    /// The face words itself from this, not from settings, so the wording
    /// always describes the data it sits over — an edit doesn't relabel the
    /// old rows before the next tick replaces them.
    var isCustomQuery = false

    init(
        writtenAt: Date, scope: String, totalCount: Int, sprint: String?,
        tasks: [TaskItem], note: String? = nil,
        totalIsLowerBound: Bool = false, isCustomQuery: Bool = false
    ) {
        self.writtenAt = writtenAt
        self.scope = scope
        self.totalCount = totalCount
        self.sprint = sprint
        self.tasks = tasks
        self.note = note
        self.totalIsLowerBound = totalIsLowerBound
        self.isCustomQuery = isCustomQuery
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writtenAt = try c.decode(Date.self, forKey: .writtenAt)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? ""
        totalCount = try c.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
        sprint = try c.decodeIfPresent(String.self, forKey: .sprint)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
        totalIsLowerBound = try c.decodeIfPresent(Bool.self, forKey: .totalIsLowerBound) ?? false
        isCustomQuery = try c.decodeIfPresent(Bool.self, forKey: .isCustomQuery) ?? false
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
    /// Finished. The WIQL excludes Done/Closed/Removed, but not every
    /// completion state a process template can invent, so these do turn up.
    case done
    /// Anything the mapping doesn't recognise. Counted rather than dropped, so
    /// the legend always reconciles with the rows it describes.
    case other

    var label: String {
        switch self {
        case .todo: "TO DO"
        case .inProgress: "IN PROGRESS"
        case .testing: "TESTING"
        case .done: "DONE"
        case .other: "OTHER"
        }
    }

    /// Whether a row earns a checkmark. Everything else leaves the slot blank,
    /// so the work item numbers stay in one column.
    var isComplete: Bool { self == .done }
}

/// Which raw states feed which lane. Editable in settings because process
/// templates get customised and board columns get renamed — that should be a
/// text edit, not a new build.
struct TaskStateMapping: Codable, Equatable {
    var todo: String
    var inProgress: String
    var testing: String
    var done: String

    init(
        todo: String = "New, Approved, To Do, Open, Proposed",
        inProgress: String = "Committed, In Progress, Doing, Active, Started",
        testing: String = "Testing, In Test, QA, In Review, Review",
        done: String = "Done, Closed, Resolved, Completed"
    ) {
        self.todo = todo
        self.inProgress = inProgress
        self.testing = testing
        self.done = done
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
        done = try c.decodeIfPresent(String.self, forKey: .done) ?? defaults.done
    }

    /// Comma-separated, trimmed, case-insensitive. Blank entries are dropped so
    /// a trailing comma can't create a rule that matches the empty state.
    static func terms(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// First lane wins, so a state listed in two fields resolves predictably
    /// rather than by dictionary order. Done is tested first: a template that
    /// reuses a word must not strand a finished item in an open lane.
    func lane(for state: String) -> TaskLane {
        let needle = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return .other }
        if Self.terms(done).contains(needle) { return .done }
        if Self.terms(todo).contains(needle) { return .todo }
        if Self.terms(inProgress).contains(needle) { return .inProgress }
        if Self.terms(testing).contains(needle) { return .testing }
        return .other
    }
}

// MARK: - Formatting (pure, used by the widget face)

enum TaskFormatting {
    /// Where a task row points, or nil when the provider gave no usable URL.
    /// Azure DevOps work items always carry one; a future provider might not.
    static func destination(for item: TaskItem) -> URL? {
        DeckLink.webURL(from: item.url)
    }

    /// Face order: most recently touched first, undated last. Deterministic and
    /// total — the comparator never depends on input order, so two identical
    /// ticks produce an identical list rather than reshuffling under the user.
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            let lc = lhs.changedAt ?? .distantPast
            let rc = rhs.changedAt ?? .distantPast
            if lc != rc { return lc > rc }
            // Two organizations can each own a work item #123, so the org breaks
            // the tie before the id — the order stays total and stable across
            // ticks when a slot is bound to several accounts.
            let lo = lhs.organization ?? ""
            let ro = rhs.organization ?? ""
            if lo != ro { return lo < ro }
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
        totalLine(totalCount: totalCount, lowerBound: false, custom: false)
    }

    /// "open" is only true of the built-in filter — a custom condition can
    /// match closed items — so a custom query counts "items".
    static func totalLine(totalCount: Int, lowerBound: Bool, custom: Bool) -> String {
        "\(totalCount)\(lowerBound ? "+" : "") \(custom ? "items" : "open")"
    }

    /// The fetch worked and matched nothing. "Nothing assigned" is only true of
    /// the built-in filter.
    static func emptyLine(custom: Bool) -> String {
        custom ? "No matches" : "Nothing assigned"
    }

    /// Whether the rows span more than one organization — which is what turns a
    /// row's project label into `org/project`, so two orgs with a
    /// same-named project stay distinguishable.
    static func spansMultipleOrgs(_ tasks: [TaskItem]) -> Bool {
        Set(tasks.compactMap(\.organization)).count > 1
    }

    /// `project`, or `org/project` when the rows span more than one org. nil
    /// when the row names no project.
    static func projectLabel(_ item: TaskItem, multipleOrgs: Bool) -> String? {
        guard let project = item.project, !project.isEmpty else { return nil }
        guard multipleOrgs, let org = item.organization, !org.isEmpty else { return project }
        return "\(org)/\(project)"
    }
}

// MARK: - Merging several accounts (pure)
//
// A PAT is organization-scoped, so multi-org is a slot bound to several
// accounts. Each account fetches exactly as it did alone; this is the one place
// their snapshots become the one face, so the agent and the host app can never
// drift.

enum TaskBoxMerge {
    /// One snapshot from the bound accounts' own snapshots.
    ///
    /// - Parameters:
    ///   - parts: one per account that answered, in binding order.
    ///   - organizations: the distinct organizations the slot is bound to, for
    ///     the header wording. Counted over the accounts that resolved, so a
    ///     failed account does not inflate it.
    ///   - targetCount: projects across every resolved account, which decides
    ///     whether a sprint can be shown at all.
    ///   - failures: the bound accounts that did not contribute.
    static func merged(
        _ parts: [TaskBoxSnapshot],
        organizations: [String],
        targetCount: Int,
        failures: [AzureAccountFailure]
    ) -> TaskBoxSnapshot {
        let distinctOrgs = distinct(organizations.filter { !$0.isEmpty })

        return TaskBoxSnapshot(
            writtenAt: Date(),
            scope: scope(parts: parts, distinctOrgs: distinctOrgs, targetCount: targetCount),
            totalCount: parts.reduce(0) { $0 + $1.totalCount },
            // A sprint belongs to one project and one team, so it is offered
            // only when the whole slot is a single target.
            sprint: targetCount == 1 ? parts.first?.sprint : nil,
            tasks: TaskFormatting.sorted(parts.flatMap(\.tasks)),
            note: note(parts: parts, failures: failures),
            totalIsLowerBound: parts.contains { $0.totalIsLowerBound },
            isCustomQuery: parts.first?.isCustomQuery ?? false
        )
    }

    /// One project keeps today's wording exactly; several projects in one org
    /// show the organization; several orgs show the count, because naming one
    /// would be a lie about the rest and naming all of them would overflow.
    static func scope(
        parts: [TaskBoxSnapshot], distinctOrgs: [String], targetCount: Int
    ) -> String {
        if targetCount == 1 { return parts.first?.scope ?? distinctOrgs.first ?? "" }
        if distinctOrgs.count == 1 { return distinctOrgs[0] }
        return "\(distinctOrgs.count) orgs"
    }

    /// Each account's own per-project note, plus a line naming the accounts that
    /// did not contribute at all — so a bound account is never silently absent.
    static func note(
        parts: [TaskBoxSnapshot], failures: [AzureAccountFailure]
    ) -> String? {
        var lines = parts.compactMap(\.note)
        if let line = AzureProjectNote.compose(
            failures: failures.map { .init(project: $0.name, outcome: $0.outcome) },
            source: .taskbox
        ) {
            lines.append(line)
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    private static func distinct(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }
}
