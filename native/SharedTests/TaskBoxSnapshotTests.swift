import XCTest

// TaskBox pure logic: model + tolerant decode, state grouping, sorting.
// There is deliberately no due-date concept here: Azure DevOps populates no
// dependable due field for this org, and the sprint-end fallback made every
// item in a sprint show the same meaningless date.

// MARK: - Model + tolerant decode

final class TaskItemDecodeTests: XCTestCase {
    private func roundTrip(_ item: TaskItem) throws -> TaskItem {
        let data = try JSONEncoder().encode(item)
        return try JSONDecoder().decode(TaskItem.self, from: data)
    }

    private func sample(id: String = "7444") -> TaskItem {
        TaskItem(
            id: id,
            title: "Use feed API in all Providers",
            state: "Committed",
            itemType: "Product Backlog Item",
            url: "https://dev.azure.com/org/proj/_workitems/edit/7444",
            provider: .azureDevOps,
            changedAt: Date(timeIntervalSince1970: 1_769_000_000)
        )
    }

    func testRoundTripsAllFields() throws {
        let item = sample()
        XCTAssertEqual(try roundTrip(item), item)
    }

    /// A snapshot written by a future agent that ships a second provider must
    /// still decode on this build — one unknown string must not throw away the
    /// whole task list.
    func testUnknownProviderDecodesAsUnknown() throws {
        let json = #"{"id":"1","title":"T","state":"Active","itemType":"Bug","url":"","provider":"jira"}"#
        let item = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.provider, .unknown)
    }

    func testMissingIdIsFatalToTheItem() {
        let json = #"{"title":"T","state":"Active","itemType":"Bug","url":"","provider":"azureDevOps"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8)))
    }
}

final class TaskBoxSnapshotDecodeTests: XCTestCase {
    func testRoundTripsSnapshot() throws {
        let snapshot = TaskBoxSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_770_000_000),
            scope: "ForesightManifold",
            totalCount: 25,
            sprint: "Sprint 57",
            tasks: []
        )
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(TaskBoxSnapshot.self, from: data), snapshot)
    }

    /// The header count is the uncapped WIQL total, so it can legitimately
    /// exceed the number of rows the snapshot carries.
    func testTotalCountMayExceedTheStoredTaskCount() throws {
        let snapshot = TaskBoxSnapshot(
            writtenAt: Date(), scope: "P", totalCount: 210, sprint: nil, tasks: []
        )
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(TaskBoxSnapshot.self, from: data).totalCount, 210)
    }

    func testAbsentSprintDecodesAsNil() throws {
        let json = #"{"writtenAt":0,"scope":"P","totalCount":0,"tasks":[]}"#
        XCTAssertNil(try JSONDecoder().decode(TaskBoxSnapshot.self, from: Data(json.utf8)).sprint)
    }
}

// MARK: - State grouping
//
// Azure DevOps mixes two vocabularies on one board: Tasks move To Do →
// In Progress → Done, while PBIs/Bugs/Features move New → Approved →
// Committed → Done. The widget shows one lifecycle, and which raw state feeds
// which group is editable in settings — process templates get customised.

final class TaskStateMappingTests: XCTestCase {
    private let mapping = TaskStateMapping()

    private func lane(_ state: String, _ mapping: TaskStateMapping? = nil) -> TaskLane {
        (mapping ?? self.mapping).lane(for: state)
    }

    func testDefaultsCoverTheTaskVocabulary() {
        XCTAssertEqual(lane("To Do"), .todo)
        XCTAssertEqual(lane("In Progress"), .inProgress)
    }

    func testDefaultsCoverTheBacklogVocabulary() {
        XCTAssertEqual(lane("New"), .todo)
        XCTAssertEqual(lane("Approved"), .todo)
        XCTAssertEqual(lane("Committed"), .inProgress)
    }

    func testDefaultsCoverTestingSynonyms() {
        XCTAssertEqual(lane("Testing"), .testing)
        XCTAssertEqual(lane("QA"), .testing)
    }

    /// The WIQL excludes Done/Closed/Removed but not every completion state a
    /// process template can use, so finished items really can arrive — and
    /// those are the rows that earn a checkmark.
    func testDefaultsCoverCompletionStates() {
        XCTAssertEqual(lane("Done"), .done)
        XCTAssertEqual(lane("Closed"), .done)
        XCTAssertEqual(lane("Resolved"), .done)
        XCTAssertEqual(lane("Completed"), .done)
    }

    /// Done is checked before the other lanes so a template that reuses a word
    /// can't strand a finished item in an open lane.
    func testDoneWinsOverTheOtherLanes() {
        let custom = TaskStateMapping(todo: "Shipped", inProgress: "", testing: "", done: "Shipped")
        XCTAssertEqual(lane("Shipped", custom), .done)
    }

    /// Board columns and states differ in casing and spacing across templates.
    func testMatchingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(lane("  in progress  "), .inProgress)
        XCTAssertEqual(lane("TO DO"), .todo)
    }

    /// An unrecognised state must still be counted, under "other" — silently
    /// dropping it would make the legend disagree with the total.
    func testUnrecognisedStateFallsToOther() {
        XCTAssertEqual(lane("Blocked"), .other)
    }

    func testEmptyStateFallsToOther() {
        XCTAssertEqual(lane(""), .other)
    }

    func testMappingIsEditable() {
        let custom = TaskStateMapping(
            todo: "Icebox, Backlog", inProgress: "Cooking", testing: "Verify", done: "Shipped"
        )
        XCTAssertEqual(lane("Backlog", custom), .todo)
        XCTAssertEqual(lane("Cooking", custom), .inProgress)
        XCTAssertEqual(lane("Verify", custom), .testing)
        XCTAssertEqual(lane("Shipped", custom), .done)
        // The defaults are replaced, not merged.
        XCTAssertEqual(lane("Committed", custom), .other)
    }

    func testBlankMappingEntriesAreIgnoredRatherThanMatchingEverything() {
        let custom = TaskStateMapping(todo: "A, , ,B", inProgress: "", testing: "", done: "")
        XCTAssertEqual(lane("A", custom), .todo)
        XCTAssertEqual(lane("B", custom), .todo)
        XCTAssertEqual(lane("", custom), .other, "an empty entry must not swallow empty states")
        XCTAssertEqual(lane("Committed", custom), .other)
    }

    func testAStateListedTwiceResolvesToTheFirstGroup() {
        let custom = TaskStateMapping(todo: "Review", inProgress: "Review", testing: "", done: "")
        XCTAssertEqual(lane("Review", custom), .todo)
    }
}

final class TaskLaneCountsTests: XCTestCase {
    private func task(_ state: String) -> TaskItem {
        TaskItem(id: "1", title: "T", state: state, itemType: "Task", url: "",
                 provider: .azureDevOps, changedAt: nil)
    }

    /// The shape actually returned by the dev org, post project-scoping.
    private var realistic: [TaskItem] {
        Array(repeating: task("New"), count: 7)
            + Array(repeating: task("To Do"), count: 12)
            + Array(repeating: task("Approved"), count: 3)
            + Array(repeating: task("Committed"), count: 2)
            + Array(repeating: task("In Progress"), count: 1)
    }

    func testCountsCollapseBothVocabularies() {
        let counts = TaskFormatting.laneCounts(tasks: realistic, mapping: TaskStateMapping())
        XCTAssertEqual(counts[.todo], 22)
        XCTAssertEqual(counts[.inProgress], 3)
        XCTAssertEqual(counts[.testing], 0)
        XCTAssertEqual(counts[.other], 0)
    }

    /// Every task lands in exactly one group, so the legend always reconciles
    /// with the number of rows it describes.
    func testEveryTaskIsCountedExactlyOnce() {
        let tasks = realistic + [task("Blocked"), task("Testing")]
        let counts = TaskFormatting.laneCounts(tasks: tasks, mapping: TaskStateMapping())
        XCTAssertEqual(TaskLane.allCases.reduce(0) { $0 + (counts[$1] ?? 0) }, tasks.count)
    }

    func testEmptyInputCountsZeroEverywhere() {
        let counts = TaskFormatting.laneCounts(tasks: [], mapping: TaskStateMapping())
        for group in TaskLane.allCases { XCTAssertEqual(counts[group], 0, "\(group)") }
    }

    /// Legend order is the lifecycle, not whatever the dictionary yields.
    func testLegendOrderFollowsTheLifecycle() {
        XCTAssertEqual(TaskLane.allCases, [.todo, .inProgress, .testing, .done, .other])
    }

    /// Only completed rows carry a glyph; everything else leaves the slot
    /// empty so the work item numbers stay in one column.
    func testOnlyDoneRowsAreMarkedComplete() {
        XCTAssertTrue(TaskLane.done.isComplete)
        for lane in TaskLane.allCases where lane != .done {
            XCTAssertFalse(lane.isComplete, "\(lane)")
        }
    }

    func testLabels() {
        XCTAssertEqual(TaskLane.todo.label, "TO DO")
        XCTAssertEqual(TaskLane.inProgress.label, "IN PROGRESS")
        XCTAssertEqual(TaskLane.testing.label, "TESTING")
        XCTAssertEqual(TaskLane.done.label, "DONE")
        XCTAssertEqual(TaskLane.other.label, "OTHER")
    }
}

// MARK: - Sort

final class TaskSortTests: XCTestCase {
    private func task(_ id: String, changed: Date?) -> TaskItem {
        TaskItem(id: id, title: "Task \(id)", state: "To Do", itemType: "Task",
                 url: "", provider: .azureDevOps, changedAt: changed)
    }

    private func day(_ d: Int) -> Date { Date(timeIntervalSince1970: Double(d) * 86_400) }

    func testMostRecentlyChangedFirst() {
        let sorted = TaskFormatting.sorted([
            task("old", changed: day(1)), task("new", changed: day(9)), task("mid", changed: day(5)),
        ])
        XCTAssertEqual(sorted.map(\.id), ["new", "mid", "old"])
    }

    func testItemsWithNoChangeDateSortLast() {
        let sorted = TaskFormatting.sorted([task("undated", changed: nil), task("dated", changed: day(1))])
        XCTAssertEqual(sorted.map(\.id), ["dated", "undated"])
    }

    /// A wobbling comparator would reshuffle the face between two identical
    /// ticks and defeat the agent's unchanged-snapshot comparison.
    func testSortIsTotalRegardlessOfInputOrder() {
        let tasks = [
            task("a", changed: day(3)), task("b", changed: day(3)),
            task("c", changed: nil), task("d", changed: day(1)),
        ]
        XCTAssertEqual(
            TaskFormatting.sorted(tasks).map(\.id),
            TaskFormatting.sorted(tasks.reversed()).map(\.id)
        )
    }

    func testEmptyInputSortsToEmpty() {
        XCTAssertEqual(TaskFormatting.sorted([]).map(\.id), [])
    }
}

// MARK: - Header

final class TaskHeaderTests: XCTestCase {
    func testTotalLineNamesTheOpenCount() {
        XCTAssertEqual(TaskFormatting.totalLine(totalCount: 25), "25 open")
    }

    func testTotalLineIsSingularForOne() {
        XCTAssertEqual(TaskFormatting.totalLine(totalCount: 1), "1 open")
    }

    func testTotalLineForNothingAssigned() {
        XCTAssertEqual(TaskFormatting.totalLine(totalCount: 0), "0 open")
    }
}
