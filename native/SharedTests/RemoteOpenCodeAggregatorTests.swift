import XCTest

// RemoteOpenCodeAggregator: session- and message-mode aggregation extracted
// from RemoteOpenCodeLoader (PRD §3.1). Fixture timestamps are fixed epoch-ms;
// expected UTC day strings computed independently (2026-07-25 / 2026-07-15).

private let now = Date(timeIntervalSince1970: 1_785_000_000_000 / 1000)
private let aToday = 1_784_980_000_000.0 // 2026-07-25 11:46:40 UTC
private let bRecent = 1_784_100_000_000.0 // 2026-07-15 07:20:00 UTC
private let bUpdated = 1_784_900_000_000.0 // active (>= sessionCutoff)
private let cStale = 1_783_000_000_000.0 // updated < sessionCutoff

private func session(
    id: String, created: Double, updated: Double,
    cost: Double? = nil, input: Double = 0, output: Double = 0,
    provider: String? = nil, modelID: String = "m"
) -> RemoteOpenCodeAggregator.RemoteSession {
    RemoteOpenCodeAggregator.RemoteSession(
        id: id,
        time: .init(created: created, updated: updated),
        cost: cost,
        tokens: .init(input: input, output: output, cache: .init(read: 0, write: 0)),
        model: .init(id: modelID, providerID: provider, variant: nil)
    )
}

private func message(
    id: String, sessionID: String, role: String, created: Double,
    cost: Double? = nil, input: Double = 0, output: Double = 0,
    provider: String? = nil, modelID: String? = nil
) -> RemoteOpenCodeAggregator.RemoteMessage {
    RemoteOpenCodeAggregator.RemoteMessage(
        id: id,
        sessionID: sessionID,
        role: role,
        time: .init(created: created),
        modelID: modelID,
        providerID: provider,
        cost: cost,
        tokens: .init(input: input, output: output, cache: .init(read: 0, write: 0))
    )
}

final class RemoteSessionAggregationTests: XCTestCase {
    func testAggregatesActiveSessions() {
        let a = session(id: "a", created: aToday, updated: aToday, cost: 0.123456, input: 1000, output: 2000, provider: "anthropic", modelID: "claude-3-5-sonnet")
        let b = session(id: "b", created: bRecent, updated: bUpdated, cost: 0.05, input: 500, output: 100, modelID: "deepseek")
        let stale = session(id: "c", created: cStale, updated: cStale, cost: 10, input: 1, output: 1)

        let result = RemoteOpenCodeAggregator.aggregate(sessions: [a, b, stale], now: now)

        XCTAssertEqual(result.sessions, 1)
        XCTAssertEqual(result.input, 1000)
        XCTAssertEqual(result.output, 2000)
        XCTAssertEqual(result.cost, 0.1235)
        XCTAssertEqual(result.totalInput, 1500)
        XCTAssertEqual(result.totalOutput, 2100)
        XCTAssertEqual(result.totalCost, 0.1735)
        XCTAssertEqual(result.daily, [
            OpenCodeSnapshot.Day(day: "2026-07-15", input: 500, output: 100),
            OpenCodeSnapshot.Day(day: "2026-07-25", input: 1000, output: 2000),
        ])
        XCTAssertEqual(result.models, [
            OpenCodeSnapshot.Model(model: "anthropic/claude-3-5-sonnet", cost: 0.1235, input: 1000, output: 2000),
            OpenCodeSnapshot.Model(model: "local/deepseek", cost: 0.05, input: 500, output: 100),
        ])
        XCTAssertEqual(result.costDaily, [
            OpenCodeSnapshot.CostDay(day: "2026-07-15", model: "local/deepseek", cost: 0.05),
            OpenCodeSnapshot.CostDay(day: "2026-07-25", model: "anthropic/claude-3-5-sonnet", cost: 0.1235),
        ])
        XCTAssertEqual(result.tools, [])
        XCTAssertEqual(result.sessionList, [])
    }

    func testStaleSessionsOnlyYieldsZeros() {
        let stale = session(id: "c", created: cStale, updated: cStale, cost: 10, input: 1, output: 1)
        let result = RemoteOpenCodeAggregator.aggregate(sessions: [stale], now: now)
        XCTAssertEqual(result.sessions, 0)
        XCTAssertEqual(result.input, 0)
        XCTAssertEqual(result.output, 0)
        XCTAssertEqual(result.cost, 0)
        XCTAssertEqual(result.totalCost, 0)
        XCTAssertEqual(result.daily, [])
        XCTAssertEqual(result.models, [])
        XCTAssertEqual(result.costDaily, [])
    }

    func testNilTokensAndCostCountAsZero() {
        let bare = session(id: "d", created: aToday, updated: aToday)
        let result = RemoteOpenCodeAggregator.aggregate(sessions: [bare], now: now)
        XCTAssertEqual(result.totalInput, 0)
        XCTAssertEqual(result.totalCost, 0)
        XCTAssertEqual(result.models, [
            OpenCodeSnapshot.Model(model: "local/m", cost: 0, input: 0, output: 0),
        ])
    }
}

final class RemoteMessageAggregationTests: XCTestCase {
    private var sessions: [RemoteOpenCodeAggregator.RemoteSession] {
        [
            session(id: "s1", created: aToday, updated: bUpdated),
            session(id: "s2", created: cStale, updated: cStale),
        ]
    }

    func testAggregatesAssistantMessagesFromActiveSessions() {
        let m1 = message(id: "m1", sessionID: "s1", role: "assistant", created: aToday, cost: 0.123456, input: 1000, output: 2000, provider: "anthropic", modelID: "claude-3-5-sonnet")
        let m2 = message(id: "m2", sessionID: "s1", role: "assistant", created: bRecent, cost: 0.05, input: 500, output: 100, modelID: "deepseek")
        let userToday = message(id: "m3", sessionID: "s1", role: "user", created: aToday, cost: 1.0, input: 50, output: 25)
        let inactive = message(id: "m4", sessionID: "s2", role: "assistant", created: aToday, cost: 9, input: 99, output: 99)
        let outOfWindow = message(id: "m5", sessionID: "s1", role: "assistant", created: 1_783_800_000_000, cost: 8, input: 88, output: 88)

        let result = RemoteOpenCodeAggregator.aggregate(
            sessions: sessions,
            messages: [m1, m2, userToday, inactive, outOfWindow],
            now: now
        )

        XCTAssertEqual(result.sessions, 1)
        XCTAssertEqual(result.input, 1050)
        XCTAssertEqual(result.output, 2025)
        XCTAssertEqual(result.cost, 1.1235)
        XCTAssertEqual(result.totalInput, 1500)
        XCTAssertEqual(result.totalOutput, 2100)
        XCTAssertEqual(result.totalCost, 0.1735)
        XCTAssertEqual(result.daily, [
            OpenCodeSnapshot.Day(day: "2026-07-15", input: 500, output: 100),
            OpenCodeSnapshot.Day(day: "2026-07-25", input: 1000, output: 2000),
        ])
        XCTAssertEqual(result.models, [
            OpenCodeSnapshot.Model(model: "anthropic/claude-3-5-sonnet", cost: 0.1235, input: 1000, output: 2000),
            OpenCodeSnapshot.Model(model: "local/deepseek", cost: 0.05, input: 500, output: 100),
        ])
        XCTAssertEqual(result.costDaily, [
            OpenCodeSnapshot.CostDay(day: "2026-07-15", model: "local/deepseek", cost: 0.05),
            OpenCodeSnapshot.CostDay(day: "2026-07-25", model: "anthropic/claude-3-5-sonnet", cost: 0.1235),
        ])
    }

    func testNoAssistantMessagesYieldsZeros() {
        let userOnly = message(id: "u", sessionID: "s1", role: "user", created: aToday, cost: 1, input: 5, output: 5)
        let result = RemoteOpenCodeAggregator.aggregate(sessions: sessions, messages: [userOnly], now: now)
        XCTAssertEqual(result.sessions, 0)
        XCTAssertEqual(result.input, 5)
        XCTAssertEqual(result.output, 5)
        XCTAssertEqual(result.cost, 1)
        XCTAssertEqual(result.totalInput, 0)
        XCTAssertEqual(result.totalCost, 0)
    }
}

final class RemoteUTCDayStringTests: XCTestCase {
    func testBoundaryAtUtcMidnight() {
        XCTAssertEqual(RemoteOpenCodeAggregator.utcDayString(from: 1_784_937_599_999), "2026-07-24")
        XCTAssertEqual(RemoteOpenCodeAggregator.utcDayString(from: 1_784_937_600_000), "2026-07-25")
    }
}
