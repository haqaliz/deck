import Foundation
import SQLite3

// MARK: - OpenCode DB access (host side, unsandboxed)
//
// Runs the same queries as the window OpenBox widget against the opencode
// SQLite database and produces the snapshot the widget extension consumes.

enum OpenCodeReader {
    static var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
            .path
    }

    /// nil when the DB is unreachable (opencode not installed).
    static func load() -> OpenCodeSnapshot? {
        var dbPointer: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &dbPointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = dbPointer
        else {
            sqlite3_close(dbPointer)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        guard
            let today = rows(db, todaySQL).first,
            let todayInput = today.int64("input"),
            let todayOutput = today.int64("output")
        else { return nil }

        let totals = rows(db, totalsSQL).first

        let daily = rows(db, dailySQL).compactMap { row -> OpenCodeSnapshot.Day? in
            guard let day = row.string("day") else { return nil }
            return OpenCodeSnapshot.Day(
                day: day,
                input: row.int64("input") ?? 0,
                output: row.int64("output") ?? 0
            )
        }

        let models = rows(db, modelsSQL).compactMap { row -> OpenCodeSnapshot.Model? in
            guard let model = row.string("model") else { return nil }
            return OpenCodeSnapshot.Model(
                model: model,
                cost: row.double("cost") ?? 0,
                input: row.int64("input") ?? 0,
                output: row.int64("output") ?? 0
            )
        }

        return OpenCodeSnapshot(
            writtenAt: Date(),
            sessions: today.int64("sessions") ?? 0,
            input: todayInput,
            output: todayOutput,
            cost: today.double("cost") ?? 0,
            daily: daily,
            models: models,
            totalInput: totals?.int64("input") ?? 0,
            totalOutput: totals?.int64("output") ?? 0,
            totalCost: totals?.double("cost") ?? 0
        )
    }

    // MARK: - SQL (mirrors the window widget's OpenCodeQueries)

    private static let todaySQL = """
        SELECT COUNT(*) as sessions, SUM(tokens_input) as input, SUM(tokens_output) as output,
               ROUND(SUM(cost), 4) as cost
        FROM session
        WHERE time_created > (strftime('%s','now')*1000 - 86400000)
        """

    private static let totalsSQL = """
        SELECT SUM(tokens_input) as input, SUM(tokens_output) as output,
               ROUND(SUM(cost), 4) as cost
        FROM session
        """

    private static let dailySQL = """
        SELECT date(time_created/1000,'unixepoch') as day,
               SUM(tokens_input) as input, SUM(tokens_output) as output
        FROM session
        WHERE time_created > (strftime('%s','now','-13 days')*1000)
        GROUP BY day ORDER BY day
        """

    private static let modelsSQL = """
        SELECT model, COUNT(*) as sessions, SUM(tokens_input) as input,
               SUM(tokens_output) as output, ROUND(SUM(cost), 4) as cost
        FROM session WHERE model IS NOT NULL
        GROUP BY model ORDER BY cost DESC LIMIT 3
        """

    // MARK: - SQLite plumbing

    private static func rows(_ db: OpaquePointer, _ sql: String) -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var result: [[String: Any]] = []
        var rc = sqlite3_step(statement)
        while rc == SQLITE_ROW {
            var row: [String: Any] = [:]
            let count = sqlite3_column_count(statement)
            for i in 0..<count {
                guard let name = sqlite3_column_name(statement, i) else { continue }
                let column = String(cString: name)
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER:
                    row[column] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[column] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[column] = String(cString: text)
                    }
                default:
                    row[column] = NSNull()
                }
            }
            result.append(row)
            rc = sqlite3_step(statement)
        }
        return result
    }
}

private extension Dictionary where Key == String, Value == Any {
    func int64(_ key: String) -> Int64? {
        self[key] as? Int64 ?? (self[key] as? NSNumber)?.int64Value
    }

    func double(_ key: String) -> Double? {
        self[key] as? Double ?? (self[key] as? NSNumber)?.doubleValue
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }
}
