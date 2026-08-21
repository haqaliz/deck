import XCTest

// TaskBox pure logic: model + tolerant decode, due resolution, buckets, sort,
// formatting. Every test injects `now` and a Calendar — none reads the clock.

// MARK: - Model + tolerant decode

final class TaskItemDecodeTests: XCTestCase {
    private func roundTrip(_ item: TaskItem) throws -> TaskItem {
        let data = try JSONEncoder().encode(item)
        return try JSONDecoder().decode(TaskItem.self, from: data)
    }

    private func sample(
        id: String = "123",
        dueDate: Date? = Date(timeIntervalSince1970: 1_770_000_000),
        dueSource: DueSource = .explicit
    ) -> TaskItem {
        TaskItem(
            id: id,
            title: "Widget alignment spike",
            state: "Active",
            itemType: "Bug",
            url: "https://dev.azure.com/org/proj/_workitems/edit/123",
            provider: .azureDevOps,
            dueDate: dueDate,
            dueSource: dueSource,
            changedAt: Date(timeIntervalSince1970: 1_769_000_000)
        )
    }

    func testRoundTripsAllFields() throws {
        let item = sample()
        XCTAssertEqual(try roundTrip(item), item)
    }

    func testRoundTripsUndatedItem() throws {
        let item = sample(dueDate: nil, dueSource: .unset)
        let decoded = try roundTrip(item)
        XCTAssertNil(decoded.dueDate)
        XCTAssertEqual(decoded.dueSource, .unset)
    }

    /// A snapshot written by a future agent that ships a second provider must
    /// still decode on this build — one unknown string must not throw away the
    /// whole task list.
    func testUnknownProviderDecodesAsUnknown() throws {
        let json = """
        {"id":"1","title":"T","state":"Active","itemType":"Bug","url":"",
         "provider":"jira","dueSource":"unset"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(TaskItem.self, from: json)
        XCTAssertEqual(item.provider, .unknown)
    }

    func testUnknownDueSourceDecodesAsUnset() throws {
        let json = """
        {"id":"1","title":"T","state":"Active","itemType":"Bug","url":"",
         "provider":"azureDevOps","dueSource":"quantum"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(TaskItem.self, from: json)
        XCTAssertEqual(item.dueSource, .unset)
    }

    func testMissingIdIsFatalToTheItem() {
        let json = """
        {"title":"T","state":"Active","itemType":"Bug","url":"",
         "provider":"azureDevOps","dueSource":"unset"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(TaskItem.self, from: json))
    }
}

final class TaskBoxSnapshotDecodeTests: XCTestCase {
    func testRoundTripsSnapshot() throws {
        let snapshot = TaskBoxSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_770_000_000),
            scope: "Manifold",
            tasks: []
        )
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(TaskBoxSnapshot.self, from: data), snapshot)
    }

    /// "Nothing assigned" is a real answer, so an empty task list must survive
    /// the round trip as an empty array rather than a nil.
    func testEmptyTaskListSurvives() throws {
        let snapshot = TaskBoxSnapshot(writtenAt: Date(), scope: "P", tasks: [])
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(TaskBoxSnapshot.self, from: data).tasks, [])
    }
}

// MARK: - Due resolution
//
// Azure DevOps has no universal due date: DueDate exists only on some work-item
// types, TargetDate on others, and the iteration path is a string that must be
// looked up in the sprint calendar. The chain is DueDate → TargetDate →
// iteration end → nothing, and which one won is recorded.

final class DueResolutionTests: XCTestCase {
    private let due = Date(timeIntervalSince1970: 1_700_000_000)
    private let target = Date(timeIntervalSince1970: 1_710_000_000)
    private let sprintEnd = Date(timeIntervalSince1970: 1_720_000_000)
    private var ends: [String: Date] { ["Manifold\\Sprint 42": sprintEnd] }

    func testExplicitDueDateWins() {
        let resolved = TaskFormatting.resolveDue(
            dueDate: due, targetDate: target,
            iterationPath: "Manifold\\Sprint 42", iterationEnds: ends
        )
        XCTAssertEqual(resolved.date, due)
        XCTAssertEqual(resolved.source, .explicit)
    }

    func testTargetDateWinsWhenDueDateAbsent() {
        let resolved = TaskFormatting.resolveDue(
            dueDate: nil, targetDate: target,
            iterationPath: "Manifold\\Sprint 42", iterationEnds: ends
        )
        XCTAssertEqual(resolved.date, target)
        XCTAssertEqual(resolved.source, .target)
    }

    func testIterationEndWinsWhenBothDateFieldsAbsent() {
        let resolved = TaskFormatting.resolveDue(
            dueDate: nil, targetDate: nil,
            iterationPath: "Manifold\\Sprint 42", iterationEnds: ends
        )
        XCTAssertEqual(resolved.date, sprintEnd)
        XCTAssertEqual(resolved.source, .iteration)
    }

    func testUnsetWhenNothingResolves() {
        let resolved = TaskFormatting.resolveDue(
            dueDate: nil, targetDate: nil, iterationPath: nil, iterationEnds: ends
        )
        XCTAssertNil(resolved.date)
        XCTAssertEqual(resolved.source, .unset)
    }

    /// The sprint calendar is fetched best-effort; when that call fails the map
    /// is empty and items must fall through to undated, not crash or invent.
    func testUnsetWhenIterationPathIsNotInTheCalendar() {
        let resolved = TaskFormatting.resolveDue(
            dueDate: nil, targetDate: nil,
            iterationPath: "Manifold\\Sprint 99", iterationEnds: ends
        )
        XCTAssertNil(resolved.date)
        XCTAssertEqual(resolved.source, .unset)
    }

    /// Iteration paths are backslash-separated and must match System.IterationPath
    /// byte for byte — no normalising, no separator translation.
    func testIterationLookupIsExactOnBackslashPaths() {
        let resolved = TaskFormatting.resolveDue(
            dueDate: nil, targetDate: nil,
            iterationPath: "Manifold/Sprint 42", iterationEnds: ends
        )
        XCTAssertNil(resolved.date, "a forward-slash path must not match a backslash key")
    }
}

// MARK: - Due buckets
//
// Bucketing is DAY-granular, not 24-hour: a task due at 09:00 today is still
// "today" at 12:00, not overdue. Everything below runs in a fixed UTC Gregorian
// calendar against an injected `now` so it can't drift with the machine.

final class DueBucketTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-08-22 12:00 UTC
    private var now: Date { date(2026, 8, 22, 12, 0) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func bucket(_ due: Date?, window: Int = 7) -> DueBucket {
        TaskFormatting.bucket(due: due, now: now, calendar: calendar, soonWindowDays: window)
    }

    func testUndatedWhenNoDueDate() {
        XCTAssertEqual(bucket(nil), .undated)
    }

    func testYesterdayEndOfDayIsOverdue() {
        XCTAssertEqual(bucket(date(2026, 8, 21, 23, 59)), .overdue)
    }

    /// The day-granular guarantee: earlier *today* is not overdue.
    func testEarlierTodayIsTodayNotOverdue() {
        XCTAssertEqual(bucket(date(2026, 8, 22, 9, 0)), .today)
    }

    func testStartOfTodayIsToday() {
        XCTAssertEqual(bucket(date(2026, 8, 22, 0, 1)), .today)
    }

    func testEndOfTodayIsToday() {
        XCTAssertEqual(bucket(date(2026, 8, 22, 23, 59)), .today)
    }

    func testTomorrowIsSoon() {
        XCTAssertEqual(bucket(date(2026, 8, 23, 0, 1)), .soon)
    }

    func testLastDayOfWindowIsSoon() {
        XCTAssertEqual(bucket(date(2026, 8, 29)), .soon, "day 7 of a 7-day window is still soon")
    }

    func testDayAfterWindowIsLater() {
        XCTAssertEqual(bucket(date(2026, 8, 30)), .later, "day 8 of a 7-day window is later")
    }

    func testWindowIsHonouredAtANonDefaultSetting() {
        XCTAssertEqual(bucket(date(2026, 8, 23), window: 1), .soon)
        XCTAssertEqual(bucket(date(2026, 8, 24), window: 1), .later)
    }

    /// Crossing a month boundary must not confuse the day arithmetic.
    func testWindowSpansAMonthBoundary() {
        XCTAssertEqual(bucket(date(2026, 9, 1), window: 14), .soon)
    }
}

// MARK: - Sort

final class TaskSortTests: XCTestCase {
    private func task(_ id: String, due: Date?, changed: Date? = nil) -> TaskItem {
        TaskItem(
            id: id, title: "Task \(id)", state: "Active", itemType: "Task",
            url: "", provider: .azureDevOps,
            dueDate: due, dueSource: due == nil ? .unset : .explicit,
            changedAt: changed
        )
    }

    private func day(_ d: Int) -> Date { Date(timeIntervalSince1970: Double(d) * 86_400) }

    func testSortsByDueDateAscending() {
        let sorted = TaskFormatting.sorted([
            task("c", due: day(30)), task("a", due: day(10)), task("b", due: day(20)),
        ])
        XCTAssertEqual(sorted.map(\.id), ["a", "b", "c"])
    }

    func testUndatedTasksSortLast() {
        let sorted = TaskFormatting.sorted([
            task("undated", due: nil), task("dated", due: day(30)),
        ])
        XCTAssertEqual(sorted.map(\.id), ["dated", "undated"])
    }

    func testEqualDueDatesBreakTieOnMostRecentlyChanged() {
        let sorted = TaskFormatting.sorted([
            task("stale", due: day(10), changed: day(1)),
            task("fresh", due: day(10), changed: day(5)),
        ])
        XCTAssertEqual(sorted.map(\.id), ["fresh", "stale"])
    }

    func testUndatedTasksAlsoBreakTieOnMostRecentlyChanged() {
        let sorted = TaskFormatting.sorted([
            task("stale", due: nil, changed: day(1)),
            task("fresh", due: nil, changed: day(5)),
        ])
        XCTAssertEqual(sorted.map(\.id), ["fresh", "stale"])
    }

    /// The order must not depend on the input order. A comparator that wobbles
    /// would reshuffle the face between two identical ticks and defeat the
    /// agent's unchanged-snapshot comparison.
    func testSortIsTotalRegardlessOfInputOrder() {
        let tasks = [
            task("a", due: day(10), changed: day(3)),
            task("b", due: day(20), changed: day(2)),
            task("c", due: nil, changed: day(9)),
            task("d", due: day(10), changed: day(1)),
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

// MARK: - Formatting

final class TaskFormattingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date { date(2026, 8, 22, 12, 0) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func relative(_ due: Date?) -> String {
        TaskFormatting.relativeDay(due: due, now: now, calendar: calendar)
    }

    func testRelativeDayForOverdue() {
        XCTAssertEqual(relative(date(2026, 8, 20)), "-2d")
        XCTAssertEqual(relative(date(2026, 8, 21)), "-1d")
    }

    func testRelativeDayForToday() {
        XCTAssertEqual(relative(date(2026, 8, 22, 9, 0)), "today")
    }

    func testRelativeDayForFuture() {
        XCTAssertEqual(relative(date(2026, 8, 23)), "+1d")
        XCTAssertEqual(relative(date(2026, 8, 25)), "+3d")
    }

    func testRelativeDayForUndated() {
        XCTAssertEqual(relative(nil), "—")
    }

    /// The trailing column is fixed width; a task due in three years must not
    /// blow the row out.
    func testRelativeDayClampsAtNinetyNineDays() {
        XCTAssertEqual(relative(date(2029, 8, 22)), "+99d")
        XCTAssertEqual(relative(date(2023, 8, 22)), "-99d")
    }

    // MARK: counts

    private func task(due: Date?) -> TaskItem {
        TaskItem(
            id: "1", title: "T", state: "Active", itemType: "Task", url: "",
            provider: .azureDevOps, dueDate: due,
            dueSource: due == nil ? .unset : .explicit, changedAt: nil
        )
    }

    private func countsLine(_ tasks: [TaskItem], window: Int = 7) -> String {
        TaskFormatting.countsLine(
            tasks: tasks, now: now, calendar: calendar, soonWindowDays: window
        )
    }

    func testCountsLineShowsOverdueAndDueSoon() {
        let tasks = [
            task(due: date(2026, 8, 20)), task(due: date(2026, 8, 21)),
            task(due: date(2026, 8, 22)), task(due: date(2026, 8, 25)),
            task(due: date(2026, 12, 1)),
        ]
        XCTAssertEqual(countsLine(tasks), "2 overdue · 2 due ≤7d")
    }

    func testCountsLineSkipsOverdueWhenZero() {
        XCTAssertEqual(countsLine([task(due: date(2026, 8, 25))]), "1 due ≤7d")
    }

    func testCountsLineSkipsDueSoonWhenZero() {
        XCTAssertEqual(countsLine([task(due: date(2026, 8, 20))]), "1 overdue")
    }

    /// The window comes from the setting, not a hardcoded 7.
    func testCountsLineInterpolatesANonDefaultWindow() {
        XCTAssertEqual(countsLine([task(due: date(2026, 8, 25))], window: 30), "1 due ≤30d")
    }

    /// The designed answer to "this org populates no date field": TaskBox
    /// degrades to a useful assigned-work list rather than claiming zero of
    /// everything.
    func testCountsLineFallsBackToOpenCountWhenNothingIsDue() {
        let tasks = [task(due: nil), task(due: nil), task(due: date(2026, 12, 1))]
        XCTAssertEqual(countsLine(tasks), "3 open")
    }

    func testCountsLineForNoTasks() {
        XCTAssertEqual(countsLine([]), "0 open")
    }

    func testCountsBreakDownEveryBucket() {
        let tasks = [
            task(due: date(2026, 8, 20)), task(due: date(2026, 8, 22)),
            task(due: date(2026, 8, 25)), task(due: date(2026, 12, 1)),
            task(due: nil),
        ]
        let counts = TaskFormatting.counts(
            tasks: tasks, now: now, calendar: calendar, soonWindowDays: 7
        )
        XCTAssertEqual(counts.overdue, 1)
        XCTAssertEqual(counts.today, 1)
        XCTAssertEqual(counts.soon, 1)
        XCTAssertEqual(counts.later, 1)
        XCTAssertEqual(counts.undated, 1)
    }
}
