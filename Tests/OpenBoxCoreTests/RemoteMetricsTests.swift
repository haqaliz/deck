import XCTest
@testable import OpenBoxCore

final class RemoteMetricsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let model = "opencode-go/deepseek-v4-flash-max"

    private func ms(_ secondsAgo: TimeInterval) -> Double {
        now.timeIntervalSince1970 * 1000 - secondsAgo * 1000
    }

    private func session(_ id: String, updatedSecondsAgo: TimeInterval) -> RemoteSession {
        RemoteSession(id: id, time: RemoteTime(created: 0, updated: ms(updatedSecondsAgo)))
    }

    private func message(
        _ id: String,
        sessionID: String,
        secondsAgo: TimeInterval,
        role: String = "assistant",
        input: Double = 0,
        output: Double = 0,
        cacheRead: Double = 0,
        cacheWrite: Double = 0,
        cost: Double = 0
    ) -> RemoteMessage {
        RemoteMessage(
            id: id,
            sessionID: sessionID,
            role: role,
            time: RemoteMessageTime(created: ms(secondsAgo)),
            modelID: "deepseek-v4-flash-max",
            providerID: "opencode-go",
            cost: cost,
            tokens: RemoteTokens(
                input: input,
                output: output,
                cache: RemoteCache(read: cacheRead, write: cacheWrite)
            )
        )
    }

    private func aggregate(_ sessions: [RemoteSession], _ messages: [RemoteMessage]) -> OpenCodeMetrics {
        RemoteMetrics.aggregate(sessions: sessions, messages: messages, now: now)
    }

    func testAggregatesTodayWindowAndBucketsByUTC() {
        let sessions = [session("s1", updatedSecondsAgo: 60)]
        let messages = [
            message("m1", sessionID: "s1", secondsAgo: 3_600, input: 100, output: 50, cost: 0.02),
            message("m2", sessionID: "s1", secondsAgo: 86_400 * 2, input: 1_000, output: 200, cost: 0.1),
            message("m3", sessionID: "s1", secondsAgo: 86_400 * 5, input: 10, output: 5, cost: 0.001),
        ]
        let metrics = aggregate(sessions, messages)

        XCTAssertEqual(metrics.todayInput, 100)
        XCTAssertEqual(metrics.todayOutput, 50)
        XCTAssertEqual(metrics.todayCost, 0.02, accuracy: 0.0001)
        XCTAssertEqual(metrics.todaySessions, 1)

        XCTAssertEqual(metrics.input, 1110)
        XCTAssertEqual(metrics.output, 255)
        XCTAssertEqual(metrics.cost, 0.121, accuracy: 0.0001)
        XCTAssertEqual(metrics.sessions, 1)
        XCTAssertEqual(metrics.daily.count, 3)
        XCTAssertEqual(metrics.models.count, 1)
        XCTAssertEqual(metrics.models.first?.cost ?? 0, 0.121, accuracy: 0.0001)
    }

    func testExcludesSessionsNotUpdatedWithinFourteenDays() {
        let sessions = [
            session("s1", updatedSecondsAgo: 60),
            session("s2", updatedSecondsAgo: 86_400 * 15),
        ]
        let messages = [
            message("m1", sessionID: "s1", secondsAgo: 3_600, input: 100, cost: 0.01),
            message("m2", sessionID: "s2", secondsAgo: 3_600, input: 999, cost: 9.99),
        ]
        let metrics = aggregate(sessions, messages)

        XCTAssertEqual(metrics.input, 100)
        XCTAssertEqual(metrics.todayInput, 100)
        XCTAssertEqual(metrics.sessions, 1)
    }

    func testExcludesMessagesOlderThanThirteenDays() {
        let sessions = [session("s1", updatedSecondsAgo: 60)]
        let messages = [
            message("m1", sessionID: "s1", secondsAgo: 86_400 * 20, input: 777, cost: 7.77),
        ]
        let metrics = aggregate(sessions, messages)

        XCTAssertEqual(metrics.input, 0)
        XCTAssertEqual(metrics.daily.count, 0)
        XCTAssertEqual(metrics.sessions, 0)
    }

    func testTodayBoundaryUsesTwentyFourHours() {
        let sessions = [session("s1", updatedSecondsAgo: 60)]
        let inToday = message("m1", sessionID: "s1", secondsAgo: 86_400 - 60, input: 5)
        let outToday = message("m2", sessionID: "s1", secondsAgo: 86_400 + 60, input: 7)

        let inside = aggregate(sessions, [inToday])
        XCTAssertEqual(inside.todayInput, 5)

        let outside = aggregate(sessions, [outToday])
        XCTAssertEqual(outside.todayInput, 0)
        XCTAssertEqual(outside.input, 7)
    }

    func testIgnoresUserMessagesAndSumsCache() {
        let sessions = [session("s1", updatedSecondsAgo: 60)]
        let messages = [
            message("m1", sessionID: "s1", secondsAgo: 60, role: "user", input: 100, output: 100, cost: 0.5),
            message("m2", sessionID: "s1", secondsAgo: 60, input: 10, output: 20, cacheRead: 30, cacheWrite: 40, cost: 0.05),
        ]
        let metrics = aggregate(sessions, messages)

        XCTAssertEqual(metrics.input, 10)
        XCTAssertEqual(metrics.output, 20)
        XCTAssertEqual(metrics.cacheRead, 30)
        XCTAssertEqual(metrics.cacheWrite, 40)
        XCTAssertEqual(metrics.cost, 0.05, accuracy: 0.0001)
        XCTAssertEqual(metrics.messages, 1)
    }

    func testModelsTopThreeByCostWithParsedNames() {
        let sessions = [session("s1", updatedSecondsAgo: 60)]
        let models = [
            "opencode-go/deepseek-v4-flash-max",
            "opencode-go/deepseek-v4-flash",
            "opencode-go/deepseek-v4",
            "opencode-go/deepseek-v4-flash-max",
        ]
        let messages = models.enumerated().map { index, model in
            let parts = model.split(separator: "/")
            return message(
                "m\(index)",
                sessionID: "s1",
                secondsAgo: 3_600,
                input: 1,
                cost: Double(index) / 10
            ).withModel(provider: String(parts[0]), id: String(parts[1]))
        }
        let metrics = aggregate(sessions, messages)

        XCTAssertEqual(metrics.models.count, 3)
        XCTAssertEqual(metrics.models.first?.cost ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(metrics.models.first?.model, "opencode-go/deepseek-v4-flash-max")
        XCTAssertEqual(metrics.models.first?.provider, "opencode-go")
        XCTAssertEqual(metrics.models.first?.modelID, "deepseek-v4")
        XCTAssertEqual(metrics.models.first?.variant, "flash max")
        XCTAssertEqual(metrics.models.map(\.model), [
            "opencode-go/deepseek-v4-flash-max",
            "opencode-go/deepseek-v4",
            "opencode-go/deepseek-v4-flash",
        ])
    }

    func testEmptyInputYieldsZeroedMetrics() {
        let metrics = aggregate([], [])
        XCTAssertEqual(metrics, OpenCodeMetrics())
    }
}

private extension RemoteMessage {
    func withModel(provider: String, id: String) -> RemoteMessage {
        RemoteMessage(
            id: id,
            sessionID: sessionID,
            role: role,
            time: time,
            modelID: id,
            providerID: provider,
            cost: cost,
            tokens: tokens
        )
    }
}
