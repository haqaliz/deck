import XCTest
@testable import OpenBoxCore

final class RemoteSessionMetricsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ms(_ secondsAgo: TimeInterval) -> Double {
        now.timeIntervalSince1970 * 1000 - secondsAgo * 1000
    }

    private func session(
        _ id: String,
        createdSecondsAgo: TimeInterval,
        updatedSecondsAgo: TimeInterval? = nil,
        input: Double = 0,
        output: Double = 0,
        cost: Double = 0,
        cacheRead: Double = 0,
        cacheWrite: Double = 0
    ) -> RemoteSession {
        RemoteSession(
            id: id,
            time: RemoteTime(
                created: ms(createdSecondsAgo),
                updated: ms(updatedSecondsAgo ?? createdSecondsAgo)
            ),
            cost: cost,
            tokens: RemoteTokens(
                input: input,
                output: output,
                cache: RemoteCache(read: cacheRead, write: cacheWrite)
            ),
            model: RemoteModel(id: "deepseek-v4-flash-max", providerID: "opencode-go", variant: nil)
        )
    }

    private func aggregate(_ sessions: [RemoteSession]) -> OpenCodeMetrics {
        RemoteMetrics.aggregate(sessions: sessions, now: now)
    }

    func testAggregatesSessionLevelUsageIntoBuckets() {
        let sessions = [
            session("s1", createdSecondsAgo: 3_600, input: 100, output: 50, cost: 0.02, cacheRead: 30),
            session("s2", createdSecondsAgo: 86_400 * 2, input: 1_000, output: 200, cost: 0.1),
            session("s3", createdSecondsAgo: 86_400 * 5, input: 10, output: 5, cost: 0.001),
        ]
        let metrics = aggregate(sessions)

        XCTAssertEqual(metrics.todayInput, 100)
        XCTAssertEqual(metrics.todayOutput, 50)
        XCTAssertEqual(metrics.todayCost, 0.02, accuracy: 0.0001)
        XCTAssertEqual(metrics.todaySessions, 1)
        XCTAssertEqual(metrics.input, 1110)
        XCTAssertEqual(metrics.output, 255)
        XCTAssertEqual(metrics.cost, 0.121, accuracy: 0.0001)
        XCTAssertEqual(metrics.cacheRead, 30)
        XCTAssertEqual(metrics.sessions, 3)
        XCTAssertEqual(metrics.daily.count, 3)
    }

    func testSessionModelsAggregateByModelKey() {
        let flashMax = RemoteModel(id: "deepseek-v4-flash", providerID: "opencode-go", variant: "max")
        let v4 = RemoteModel(id: "deepseek-v4", providerID: "opencode-go", variant: nil)
        let sessions = [
            RemoteSession(id: "s1", time: RemoteTime(created: ms(3_600), updated: ms(60)), cost: 0.3,
                          tokens: RemoteTokens(input: 3, output: 0, cache: RemoteCache(read: 0, write: 0)),
                          model: flashMax),
            RemoteSession(id: "s2", time: RemoteTime(created: ms(3_600), updated: ms(60)), cost: 0.2,
                          tokens: RemoteTokens(input: 2, output: 0, cache: RemoteCache(read: 0, write: 0)),
                          model: v4),
            RemoteSession(id: "s3", time: RemoteTime(created: ms(3_600), updated: ms(60)), cost: 0.1,
                          tokens: RemoteTokens(input: 1, output: 0, cache: RemoteCache(read: 0, write: 0)),
                          model: flashMax),
        ]
        let metrics = aggregate(sessions)

        XCTAssertEqual(metrics.models.count, 2)
        XCTAssertEqual(metrics.models.first?.cost ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(metrics.models.first?.modelID, "deepseek-v4-flash")
        XCTAssertEqual(metrics.models.first?.variant, "max")
        XCTAssertEqual(metrics.models.first?.provider, "opencode-go")
        XCTAssertEqual(metrics.models.last?.cost ?? 0, 0.2, accuracy: 0.0001)
    }

    func testExcludesStaleSessionsAndOldSessions() {
        let sessions = [
            session("s1", createdSecondsAgo: 3_600, input: 5),
            session("s2", createdSecondsAgo: 86_400 * 15, input: 999),
            session("s3", createdSecondsAgo: 86_400 * 20, updatedSecondsAgo: 60, input: 777),
        ]
        let metrics = aggregate(sessions)

        XCTAssertEqual(metrics.input, 5)
        XCTAssertEqual(metrics.sessions, 1)
        XCTAssertEqual(metrics.daily.count, 1)
    }

    func testEmptySessionsYieldsZeroedMetrics() {
        XCTAssertEqual(aggregate([]), OpenCodeMetrics())
    }

    func testSessionsWithoutUsageFieldsCountSessionsOnly() {
        let bare = RemoteSession(id: "s1", time: RemoteTime(created: ms(3_600), updated: ms(60)))
        let metrics = aggregate([bare])

        XCTAssertEqual(metrics.sessions, 1)
        XCTAssertEqual(metrics.todaySessions, 1)
        XCTAssertEqual(metrics.input, 0)
        XCTAssertEqual(metrics.daily.count, 1)
    }
}
