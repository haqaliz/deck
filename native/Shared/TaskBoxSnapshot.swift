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

enum TaskProvider: String, Codable, Equatable {
    case azureDevOps
    /// A provider written by a newer agent that this build doesn't know.
    /// Present so one unknown string can't throw away the whole task list.
    case unknown
}

/// Which field supplied `TaskItem.dueDate`. Azure DevOps has no universal due
/// date, so the resolution chain is recorded rather than lost.
enum DueSource: String, Codable, Equatable {
    /// Microsoft.VSTS.Scheduling.DueDate
    case explicit
    /// Microsoft.VSTS.Scheduling.TargetDate
    case target
    /// The iteration path's finishDate.
    case iteration
    /// No date could be resolved. (Named `unset` rather than `none` so it
    /// never collides with `Optional.none` at a call site.)
    case unset
}

/// How urgent a task is, once a due date has been resolved. Drives the row dot
/// colour and the header counts.
enum DueBucket: Equatable {
    case overdue
    case today
    case soon
    case later
    case undated
}

struct TaskItem: Codable, Equatable {
    var id: String
    var title: String
    var state: String
    var itemType: String
    var url: String
    var provider: TaskProvider
    var dueDate: Date?
    var dueSource: DueSource
    var changedAt: Date?

    init(
        id: String,
        title: String,
        state: String,
        itemType: String,
        url: String,
        provider: TaskProvider,
        dueDate: Date?,
        dueSource: DueSource,
        changedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.itemType = itemType
        self.url = url
        self.provider = provider
        self.dueDate = dueDate
        self.dueSource = dueSource
        self.changedAt = changedAt
    }

    /// Tolerant on the two enums only: an unknown provider or due source reads
    /// as `.unknown` / `.unset` so a snapshot from a newer agent still renders.
    /// `id` and `title` stay required — an item without them is not a task.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        let rawProvider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        provider = TaskProvider(rawValue: rawProvider) ?? .unknown
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        let rawDueSource = try c.decodeIfPresent(String.self, forKey: .dueSource) ?? ""
        dueSource = DueSource(rawValue: rawDueSource) ?? .unset
        changedAt = try c.decodeIfPresent(Date.self, forKey: .changedAt)
    }
}

struct TaskBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    /// "{project}", or "{org} / {project}" when they differ. Rendered by the
    /// face, so the header names what the data *is* rather than what settings
    /// say it will be after the next tick.
    var scope: String
    /// Pre-sorted by `TaskFormatting.sorted` — the widget renders, it does not
    /// decide.
    var tasks: [TaskItem]
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

// MARK: - Due resolution / bucketing / formatting (pure, used by the widget face)

enum TaskFormatting {
    /// Azure DevOps has no universal due date, so the face resolves one from a
    /// chain and records which link supplied it: an explicit DueDate, else a
    /// TargetDate, else the end of the item's iteration, else nothing.
    ///
    /// `iterationEnds` is looked up by the raw `System.IterationPath` string —
    /// backslash-separated, matched exactly. The map is empty whenever the
    /// best-effort iterations call failed, and items simply fall through to
    /// undated.
    static func resolveDue(
        dueDate: Date?,
        targetDate: Date?,
        iterationPath: String?,
        iterationEnds: [String: Date]
    ) -> (date: Date?, source: DueSource) {
        if let dueDate { return (dueDate, .explicit) }
        if let targetDate { return (targetDate, .target) }
        if let iterationPath, let end = iterationEnds[iterationPath] {
            return (end, .iteration)
        }
        return (nil, .unset)
    }

    /// How urgent a task is. Day-granular on purpose: "overdue" means a whole
    /// day has passed, not that 24 hours have elapsed, so a task due at 09:00
    /// today still reads as due today at 17:00.
    static func bucket(
        due: Date?,
        now: Date,
        calendar: Calendar,
        soonWindowDays: Int
    ) -> DueBucket {
        guard let due else { return .undated }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        guard let days = calendar.dateComponents([.day], from: today, to: dueDay).day else {
            return .undated
        }
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        return days <= soonWindowDays ? .soon : .later
    }

    /// Face order: soonest first, undated last, ties broken by most recently
    /// touched. Deterministic and total — the comparator never depends on the
    /// input order, so two identical ticks produce an identical list rather
    /// than reshuffling under the user.
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                break
            }
            // Same due date, or both undated: most recently changed first.
            let lc = lhs.changedAt ?? .distantPast
            let rc = rhs.changedAt ?? .distantPast
            if lc != rc { return lc > rc }
            // Last resort so the order is total even for identical keys.
            return lhs.id < rhs.id
        }
    }

    /// Row trailing text: "-2d" / "today" / "+3d" / "—". Day-granular, and
    /// clamped so a task due years out can't widen the column.
    static func relativeDay(due: Date?, now: Date, calendar: Calendar) -> String {
        guard let due else { return "\u{2014}" }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        guard let days = calendar.dateComponents([.day], from: today, to: dueDay).day else {
            return "\u{2014}"
        }
        if days == 0 { return "today" }
        let clamped = max(-99, min(99, days))
        return clamped < 0 ? "\(clamped)d" : "+\(clamped)d"
    }

    struct Counts: Equatable {
        var overdue = 0
        var today = 0
        var soon = 0
        var later = 0
        var undated = 0

        /// What the header means by "due": today plus everything inside the
        /// window. Overdue is counted separately — it is a different question.
        var dueSoon: Int { today + soon }
        var total: Int { overdue + today + soon + later + undated }
    }

    static func counts(
        tasks: [TaskItem],
        now: Date,
        calendar: Calendar,
        soonWindowDays: Int
    ) -> Counts {
        var counts = Counts()
        for task in tasks {
            switch bucket(due: task.dueDate, now: now, calendar: calendar, soonWindowDays: soonWindowDays) {
            case .overdue: counts.overdue += 1
            case .today: counts.today += 1
            case .soon: counts.soon += 1
            case .later: counts.later += 1
            case .undated: counts.undated += 1
            }
        }
        return counts
    }

    /// Header line: "3 overdue \u{00B7} 7 due \u{2264}7d". Zero parts are skipped, and the
    /// window is interpolated from the setting rather than hardcoded.
    ///
    /// When nothing is overdue or due, it falls back to "N open" — the honest
    /// face for an org that populates no scheduling field at all, where a row
    /// of zeroes would read as broken rather than as calm.
    static func countsLine(
        tasks: [TaskItem],
        now: Date,
        calendar: Calendar,
        soonWindowDays: Int
    ) -> String {
        let counts = counts(tasks: tasks, now: now, calendar: calendar, soonWindowDays: soonWindowDays)
        var parts: [String] = []
        if counts.overdue > 0 { parts.append("\(counts.overdue) overdue") }
        if counts.dueSoon > 0 { parts.append("\(counts.dueSoon) due \u{2264}\(soonWindowDays)d") }
        guard !parts.isEmpty else { return "\(counts.total) open" }
        return parts.joined(separator: " \u{00B7} ")
    }
}
