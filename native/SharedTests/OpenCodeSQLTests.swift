import XCTest
import SQLite3

// Fresh suite: runs the five real OpenCodeReader SQL queries against an
// in-memory fixture DB mirroring the opencode schema (session/part tables).
// Timestamps are relative to now (strftime('%s','now') in the SQL), so the
// today/14-day windows are stable across runs.

final class OpenCodeSQLTests: XCTestCase {
    private func makeFixtureDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db else { return nil }
        exec(db, "CREATE TABLE session (time_created INTEGER, tokens_input INTEGER, tokens_output INTEGER, cost REAL, model TEXT)")
        exec(db, "CREATE TABLE part (data TEXT)")

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let hour: Int64 = 3_600_000
        let day: Int64 = 86_400_000
        let a = #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#
        let b = #"{"id":"qwen/qwen3.8-max","providerID":"openrouter","variant":"xhigh"}"#
        let c = "plain/model-c"
        let d = "old/model-d"

        // today (last 24h): 2 sessions — model A (1.0) + model B (0.5)
        insertSession(db, time: nowMs - hour, input: 100, output: 50, cost: 1.0, model: a)
        insertSession(db, time: nowMs - 2 * hour, input: 40, output: 10, cost: 0.5, model: b)
        // yesterday: model A (2.0)
        insertSession(db, time: nowMs - day - hour, input: 200, output: 100, cost: 2.0, model: a)
        // 10 days ago: model C (3.0) — inside the 14-day window
        insertSession(db, time: nowMs - 10 * day, input: 300, output: 150, cost: 3.0, model: c)
        // 20 days ago: model D (9.0) — outside the window, affects totals only
        insertSession(db, time: nowMs - 20 * day, input: 400, output: 200, cost: 9.0, model: d)

        // tool parts: bash x2, read x1, one non-tool message
        insertPart(db, json: #"{"type":"tool","tool":"bash"}"#)
        insertPart(db, json: #"{"type":"tool","tool":"bash"}"#)
        insertPart(db, json: #"{"type":"tool","tool":"read"}"#)
        insertPart(db, json: #"{"type":"message","content":"hi"}"#)

        return db
    }

    private func exec(_ db: OpaquePointer, _ sql: String) {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK, "prepare: \(sql)")
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE, "step: \(sql)")
    }

    private func insertSession(_ db: OpaquePointer, time: Int64, input: Int64, output: Int64, cost: Double, model: String) {
        let sql = "INSERT INTO session (time_created, tokens_input, tokens_output, cost, model) VALUES (\(time), \(input), \(output), \(cost), '\(model)')"
        exec(db, sql)
    }

    private func insertPart(_ db: OpaquePointer, json: String) {
        let sql = "INSERT INTO part (data) VALUES ('\(json)')"
        exec(db, sql)
    }

    private func utcDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func testLoadParsesTodayAndTotals() throws {
        let db = try XCTUnwrap(makeFixtureDB())
        defer { sqlite3_close(db) }

        let snapshot = try XCTUnwrap(OpenCodeReader.load(from: db))
        XCTAssertEqual(snapshot.sessions, 2)
        XCTAssertEqual(snapshot.input, 140)
        XCTAssertEqual(snapshot.output, 60)
        XCTAssertEqual(snapshot.cost, 1.5, accuracy: 0.0001)
        // totals span the whole table, including the 20-day-old row
        XCTAssertEqual(snapshot.totalInput, 1040)
        XCTAssertEqual(snapshot.totalOutput, 510)
        XCTAssertEqual(snapshot.totalCost, 15.5, accuracy: 0.0001)
    }

    func testLoadParsesDailyWindow() throws {
        let db = try XCTUnwrap(makeFixtureDB())
        defer { sqlite3_close(db) }

        let snapshot = try XCTUnwrap(OpenCodeReader.load(from: db))
        let now = Date()
        let days = snapshot.daily.map(\.day)
        XCTAssertEqual(days, [utcDay(now.addingTimeInterval(-10 * 86400)), utcDay(now.addingTimeInterval(-86400)), utcDay(now)])
        XCTAssertEqual(snapshot.daily.last?.input, 140)
        XCTAssertEqual(snapshot.daily.last?.output, 60)
    }

    func testLoadParsesTopModelsByCost() throws {
        // modelsSQL has no time window: all-time top 3 by cost — the 20-day-old
        // model D (9.0) leads, then the two 3.0-cost models in SQLite order.
        let db = try XCTUnwrap(makeFixtureDB())
        defer { sqlite3_close(db) }

        let snapshot = try XCTUnwrap(OpenCodeReader.load(from: db))
        XCTAssertEqual(snapshot.models.count, 3)
        XCTAssertEqual(snapshot.models[0].model, "old/model-d")
        XCTAssertEqual(snapshot.models[0].cost, 9.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.models[0].input, 400)
        let remaining = snapshot.models.dropFirst().map(\.model)
        XCTAssertEqual(Set(remaining), [
            #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#,
            "plain/model-c",
        ])
    }

    func testLoadParsesToolCountsFromJSON() throws {
        let db = try XCTUnwrap(makeFixtureDB())
        defer { sqlite3_close(db) }

        let snapshot = try XCTUnwrap(OpenCodeReader.load(from: db))
        XCTAssertEqual(snapshot.tools, [
            OpenCodeSnapshot.ToolCount(tool: "bash", count: 2),
            OpenCodeSnapshot.ToolCount(tool: "read", count: 1),
        ])
    }

    func testLoadParsesCostPerDay() throws {
        let db = try XCTUnwrap(makeFixtureDB())
        defer { sqlite3_close(db) }

        let snapshot = try XCTUnwrap(OpenCodeReader.load(from: db))
        let a = #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#
        let today = snapshot.costDaily.filter { $0.day == utcDay(Date()) }
        XCTAssertEqual(today.count, 2)
        XCTAssertEqual(today.first { $0.model == a }?.cost ?? 0, 1.0, accuracy: 0.0001)
    }

    func testEmptyDBReturnsNil() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertNil(OpenCodeReader.load(from: db!))
    }

    func testDBWithOnlyOldRowsReturnsNil() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        exec(db!, "CREATE TABLE session (time_created INTEGER, tokens_input INTEGER, tokens_output INTEGER, cost REAL, model TEXT)")
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        insertSession(db!, time: nowMs - 30 * 86_400_000, input: 1, output: 1, cost: 0.1, model: "m")
        XCTAssertNil(OpenCodeReader.load(from: db!))
    }
}
