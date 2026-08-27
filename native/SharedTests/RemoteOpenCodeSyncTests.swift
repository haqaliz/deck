import XCTest

// RemoteOpenCodeSync: the pure incremental-sync core — state codec, per-session
// plan, page merge with capability detection, eviction, and the dual-shape
// message decode. Transport (the GETs) stays in RemoteOpenCodeLoader; every
// decision here is testable without a server (PRD §3).

private let now = Date(timeIntervalSince1970: 1_785_000_000_000 / 1000)
private let nowMs = now.timeIntervalSince1970 * 1000
private let dayMs = 86_400_000.0

private func session(
    id: String, created: Double, updated: Double,
    cost: Double? = nil, input: Double = 0, output: Double = 0
) -> RemoteOpenCodeAggregator.RemoteSession {
    RemoteOpenCodeAggregator.RemoteSession(
        id: id,
        time: .init(created: created, updated: updated),
        cost: cost,
        tokens: .init(input: input, output: output, cache: .init(read: 0, write: 0)),
        model: .init(id: "m", providerID: nil, variant: nil)
    )
}

private func message(
    id: String, sessionID: String, created: Double, input: Double = 0, output: Double = 0
) -> RemoteOpenCodeAggregator.RemoteMessage {
    RemoteOpenCodeAggregator.RemoteMessage(
        id: id,
        sessionID: sessionID,
        role: "assistant",
        time: .init(created: created),
        modelID: "m",
        providerID: nil,
        cost: 0,
        tokens: .init(input: input, output: output, cache: .init(read: 0, write: 0))
    )
}

private func state(
    server: String = "http://nuc:4096",
    mode: RemoteOpenCodeSync.Mode = .incremental,
    sessions: [String: RemoteOpenCodeSync.SessionCursor] = [:],
    messages: [RemoteOpenCodeAggregator.RemoteMessage] = []
) -> RemoteOpenCodeSync.State {
    RemoteOpenCodeSync.State(
        version: RemoteOpenCodeSync.currentVersion,
        server: server,
        mode: mode,
        sessions: sessions,
        messages: messages
    )
}

private func cursor(watermark: Double, lastUpdated: Double) -> RemoteOpenCodeSync.SessionCursor {
    .init(watermark: watermark, lastUpdated: lastUpdated)
}

// MARK: - State codec

final class RemoteOpenCodeSyncStateCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let original = state(
            sessions: ["a": cursor(watermark: 1_784_900_000_000, lastUpdated: 1_784_900_000_000)],
            messages: [message(id: "m1", sessionID: "a", created: 1_784_900_000_000)]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteOpenCodeSync.State.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.version, RemoteOpenCodeSync.currentVersion)
    }

    func testWrongVersionReadsAsAbsent() {
        let data = Data(#"{"version":99,"server":"http://x","mode":"incremental","sessions":{},"messages":[]}"#.utf8)
        let decoded = try? JSONDecoder().decode(RemoteOpenCodeSync.State.self, from: data)
        XCTAssertNotNil(decoded, "decode itself must not fail on a future version")
        XCTAssertNil(RemoteOpenCodeSync.validated(decoded, for: "http://x"), "a future version is treated as absent")
    }

    func testCorruptDataReadsAsAbsent() {
        let data = Data("not json".utf8)
        let decoded = try? JSONDecoder().decode(RemoteOpenCodeSync.State.self, from: data)
        XCTAssertNil(decoded)
    }

    func testServerMismatchReadsAsAbsent() {
        let existing = state(server: "http://old:4096")
        XCTAssertNil(RemoteOpenCodeSync.validated(existing, for: "http://new:4096"))
        XCTAssertEqual(RemoteOpenCodeSync.validated(existing, for: "http://old:4096"), existing)
    }
}

// MARK: - Plan

final class RemoteOpenCodeSyncPlanTests: XCTestCase {
    private func activeSession(updated: Double) -> RemoteOpenCodeAggregator.RemoteSession {
        session(id: "a", created: nowMs - 2 * dayMs, updated: updated)
    }

    func testIdleSessionSkips() {
        let updated = nowMs - 60_000
        let sessions = [activeSession(updated: updated)]
        let s = state(sessions: ["a": cursor(watermark: 0, lastUpdated: updated)])
        XCTAssertEqual(RemoteOpenCodeSync.plan(state: s, sessions: sessions, now: now), ["a": .skip])
    }

    func testChangedSessionPages() {
        let sessions = [activeSession(updated: nowMs - 60_000)]
        let s = state(sessions: ["a": cursor(watermark: 0, lastUpdated: nowMs - 120_000)])
        XCTAssertEqual(RemoteOpenCodeSync.plan(state: s, sessions: sessions, now: now), ["a": .page])
    }

    func testUnknownSessionFullFetches() {
        let sessions = [activeSession(updated: nowMs - 1000)]
        XCTAssertEqual(RemoteOpenCodeSync.plan(state: state(), sessions: sessions, now: now), ["a": .fullFetch])
    }

    func testNoStateFullFetchesEverythingActive() {
        let sessions = [activeSession(updated: nowMs - 1000)]
        XCTAssertEqual(RemoteOpenCodeSync.plan(state: nil, sessions: sessions, now: now), ["a": .fullFetch])
    }

    func testInactiveSessionSkipsEvenWhenChanged() {
        let stale = session(id: "a", created: nowMs - 20 * dayMs, updated: nowMs - 20 * dayMs)
        XCTAssertEqual(RemoteOpenCodeSync.plan(state: state(), sessions: [stale], now: now), ["a": .skip])
    }

    func testFullFetchModePlansFullFetchForActiveOnly() {
        let stale = session(id: "b", created: nowMs - 20 * dayMs, updated: nowMs - 20 * dayMs)
        let s = state(mode: .fullFetch)
        let plans = RemoteOpenCodeSync.plan(state: s, sessions: [activeSession(updated: nowMs - 1000), stale], now: now)
        XCTAssertEqual(plans["a"], .fullFetch)
        XCTAssertEqual(plans["b"], .skip)
    }

    func testSinglePageModePlansPage() {
        let s = state(mode: .singlePage, sessions: ["a": cursor(watermark: 0, lastUpdated: nowMs - 120_000)])
        let plans = RemoteOpenCodeSync.plan(state: s, sessions: [activeSession(updated: nowMs - 60_000)], now: now)
        XCTAssertEqual(plans["a"], .page)
    }
}

// MARK: - Merge

final class RemoteOpenCodeSyncMergeTests: XCTestCase {
    private let sid = "a"

    func testMergesNewMessagesAndAdvancesWatermark() {
        let archive = [message(id: "m1", sessionID: sid, created: 100)]
        let page = [message(id: "m2", sessionID: sid, created: 200), message(id: "m3", sessionID: sid, created: 150)]
        let s = state(sessions: [sid: cursor(watermark: 100, lastUpdated: 123)], messages: archive)

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: nil, hasNextCursor: false)

        XCTAssertEqual(result.state.messages.map(\.id), ["m1", "m2", "m3"])
        XCTAssertEqual(result.state.sessions[sid]?.watermark, 200)
        XCTAssertEqual(result.state.sessions[sid]?.lastUpdated, 456)
        XCTAssertFalse(result.needMore)
    }

    func testDedupesById() {
        let page = [message(id: "m1", sessionID: sid, created: 100), message(id: "m2", sessionID: sid, created: 200)]
        let s = state(sessions: [sid: cursor(watermark: 200, lastUpdated: 123)], messages: page)

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: nil, hasNextCursor: false)

        XCTAssertEqual(result.state.messages.map(\.id), ["m1", "m2"])
        XCTAssertEqual(result.state.messages.count, 2)
    }

    func testNeedMoreOnlyWhenPageHasNewerMessagesAndNextCursor() {
        let page = [message(id: "m2", sessionID: sid, created: 200)]
        let s = state(sessions: [sid: cursor(watermark: 100, lastUpdated: 123)])

        XCTAssertTrue(RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: nil, hasNextCursor: true).needMore)
        XCTAssertFalse(RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: nil, hasNextCursor: false).needMore)
    }

    func testPageEntirelyBelowWatermarkMergesNothingButAdvancesLastUpdated() {
        let page = [message(id: "m1", sessionID: sid, created: 100)]
        let s = state(sessions: [sid: cursor(watermark: 200, lastUpdated: 123)], messages: [message(id: "m1", sessionID: sid, created: 100)])

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: nil, hasNextCursor: true)

        XCTAssertEqual(result.state.messages.count, 1, "no new messages merged")
        XCTAssertEqual(result.state.sessions[sid]?.lastUpdated, 456)
        XCTAssertFalse(result.needMore, "a page fully below the watermark means caught up")
    }

func testCountOverLimitFlipsToFullFetchAndMergesEverything() {
        let page = (0..<RemoteOpenCodeSync.pageLimit + 1).map { message(id: "m\($0)", sessionID: sid, created: Double($0)) }
        let s = state(sessions: [sid: cursor(watermark: 0, lastUpdated: nowMs - 120_000)])

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: nowMs - 60_000, page: page, pageWasLimited: true, previousPageIDs: nil, hasNextCursor: true)

        XCTAssertEqual(result.state.mode, .fullFetch, "the server ignored limit — never probe again")
        XCTAssertEqual(result.state.messages.count, RemoteOpenCodeSync.pageLimit + 1)
        XCTAssertFalse(result.needMore)
    }

    func testUnlimitedFullPageDoesNotFlipMode() {
        // A deliberate full fetch (first tick, new session) of a big history
        // must not read as "the server ignored limit".
        let page = (0..<RemoteOpenCodeSync.pageLimit + 1).map { message(id: "m\($0)", sessionID: sid, created: Double($0)) }
        let s = state(sessions: [sid: cursor(watermark: 0, lastUpdated: nowMs - 120_000)])

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: nowMs - 60_000, page: page, pageWasLimited: false, previousPageIDs: nil, hasNextCursor: true)

        XCTAssertEqual(result.state.mode, .incremental)
        XCTAssertFalse(result.needMore, "unlimited pages never ask for more")
    }

    func testIdenticalPageFlipsToSinglePage() {
        let page = [message(id: "m1", sessionID: sid, created: 100)]
        let s = state(sessions: [sid: cursor(watermark: 0, lastUpdated: 123)])

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: ["m1"], hasNextCursor: true)

        XCTAssertEqual(result.state.mode, .singlePage, "the server ignored before — page once per tick")
        XCTAssertFalse(result.needMore)
    }

    func testIdenticalPageStillMergesGenuinelyNewMessages() {
        // The same page as before, but now containing one more message the
        // previous page lacked: not "identical" — normal incremental path.
        let page = [message(id: "m1", sessionID: sid, created: 100), message(id: "m2", sessionID: sid, created: 200)]
        let s = state(sessions: [sid: cursor(watermark: 0, lastUpdated: 123)])

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: ["m1"], hasNextCursor: true)

        XCTAssertEqual(result.state.mode, .incremental)
        XCTAssertEqual(result.state.messages.count, 2)
    }

    func testSinglePageModeNeverNeedsMore() {
        let page = [message(id: "m2", sessionID: sid, created: 200)]
        let s = state(mode: .singlePage, sessions: [sid: cursor(watermark: 100, lastUpdated: 123)])

        let result = RemoteOpenCodeSync.merge(state: s, sessionID: sid, updated: 456, page: page, pageWasLimited: true, previousPageIDs: nil, hasNextCursor: true)

        XCTAssertEqual(result.state.messages.map(\.id), ["m2"])
        XCTAssertFalse(result.needMore)
    }
}

// MARK: - Prune

final class RemoteOpenCodeSyncPruneTests: XCTestCase {
    func testEvictsMessagesOlderThanThirteenDays() {
        let old = message(id: "old", sessionID: "a", created: nowMs - 14 * dayMs)
        let fresh = message(id: "new", sessionID: "a", created: nowMs - 1 * dayMs)
        let s = state(messages: [old, fresh])

        let result = RemoteOpenCodeSync.prune(state: s, sessionIDs: ["a"], now: now)

        XCTAssertEqual(result.messages.map(\.id), ["new"])
    }

    func testDropsAbsentOldSessionEntriesKeepsRecentOnes() {
        let oldAbsent = "gone"
        let recentAbsent = "quiet" // not in the list but touched 5 days ago
        let present = "here"
        let s = state(sessions: [
            oldAbsent: cursor(watermark: 1, lastUpdated: nowMs - 15 * dayMs),
            recentAbsent: cursor(watermark: 1, lastUpdated: nowMs - 5 * dayMs),
            present: cursor(watermark: 1, lastUpdated: nowMs),
        ])

        let result = RemoteOpenCodeSync.prune(state: s, sessionIDs: [present], now: now)

        XCTAssertNil(result.sessions[oldAbsent])
        XCTAssertNotNil(result.sessions[recentAbsent])
        XCTAssertNotNil(result.sessions[present])
    }
}

// MARK: - Dual-shape decode

final class RemoteOpenCodeSyncDecodeTests: XCTestCase {
    private let envelope = #"[{"info":{"id":"m1","sessionID":"a","role":"assistant","time":{"created":1784900000000},"modelID":"deepseek-v4-flash","providerID":"opencode-go","cost":0.5,"tokens":{"input":1,"output":2,"cache":{"read":0,"write":0}},"extra":"ignored"},"parts":[]}]"#
    private let flat = #"[{"id":"m1","sessionID":"a","role":"assistant","time":{"created":1784900000000},"modelID":"deepseek-v4-flash","providerID":"opencode-go","cost":0.5,"tokens":{"input":1,"output":2,"cache":{"read":0,"write":0}},"parts":[]}]"#

    func testEnvelopeShapeDecodes() throws {
        let messages = try RemoteOpenCodeSync.decodeMessages(Data(envelope.utf8))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].id, "m1")
        XCTAssertEqual(messages[0].tokens?.input, 1)
    }

    func testFlatShapeDecodes() throws {
        let messages = try RemoteOpenCodeSync.decodeMessages(Data(flat.utf8))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].id, "m1")
        XCTAssertEqual(messages[0].providerID, "opencode-go")
    }

    func testBothShapesDecodeToTheSameValues() throws {
        XCTAssertEqual(
            try RemoteOpenCodeSync.decodeMessages(Data(envelope.utf8)),
            try RemoteOpenCodeSync.decodeMessages(Data(flat.utf8))
        )
    }

    func testEmptyArrayDecodesAsEmpty() throws {
        XCTAssertEqual(try RemoteOpenCodeSync.decodeMessages(Data("[]".utf8)), [])
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try RemoteOpenCodeSync.decodeMessages(Data("nope".utf8)))
    }
}