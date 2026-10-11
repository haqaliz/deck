import XCTest

// When a remote search may be sent, and what the panel shows meanwhile. Pure:
// every time is passed in, so none of it needs a clock or a network. The rules
// exist because Deck already trips public rate limits (CoinGecko 429s, GitHub's
// 30 searches a minute, Yahoo bursts) and a search-as-you-type box would trip
// them for the agent too.

final class RemoteSearchQueryTests: XCTestCase {
    func testNormaliseTrimsCollapsesAndFolds() {
        XCTAssertEqual(RemoteSearchPolicy.normalise("  Login   BUG \n"), "login bug")
        XCTAssertEqual(RemoteSearchPolicy.normalise("São  Paulo"), "sao paulo")
    }

    func testNothingIsSentBelowTwoCharacters() {
        XCTAssertFalse(RemoteSearchPolicy.shouldSearch(""))
        XCTAssertFalse(RemoteSearchPolicy.shouldSearch("   "))
        XCTAssertFalse(RemoteSearchPolicy.shouldSearch("a"))
        XCTAssertFalse(RemoteSearchPolicy.shouldSearch(" a "))
        XCTAssertTrue(RemoteSearchPolicy.shouldSearch("ab"))
        XCTAssertTrue(RemoteSearchPolicy.shouldSearch("42"))
    }

    /// Whitespace inside is not a character of the query.
    func testLengthIsCountedAfterNormalising() {
        XCTAssertFalse(RemoteSearchPolicy.shouldSearch("a    "))
    }
}

final class RemoteSearchTimingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testDebounceWaitsAfterTheLastKeystroke() {
        XCTAssertEqual(
            RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: nil, blockedUntil: nil),
            t0.addingTimeInterval(0.3))
    }

    func testTheFloorHoldsASendThatFollowsAnotherTooClosely() {
        let sent = t0.addingTimeInterval(0.1)
        // debounce would allow t0+0.3, but the floor says sent+0.5
        XCTAssertEqual(
            RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: sent, blockedUntil: nil),
            sent.addingTimeInterval(0.5))
    }

    func testAnOldSendDoesNotDelayAnything() {
        let sent = t0.addingTimeInterval(-60)
        XCTAssertEqual(
            RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: sent, blockedUntil: nil),
            t0.addingTimeInterval(0.3))
    }

    /// A 429 blocks sends until its retry window passes, whatever the debounce says.
    func testARateLimitBlocksUntilItsWindowPasses() {
        let until = t0.addingTimeInterval(55)
        XCTAssertEqual(
            RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: nil, blockedUntil: until),
            until)
    }

    func testAPassedRateLimitIsIgnored() {
        XCTAssertEqual(
            RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: nil, blockedUntil: t0.addingTimeInterval(-5)),
            t0.addingTimeInterval(0.3))
    }

    func testTypingAgainMovesTheSendLater() {
        let first = RemoteSearchPolicy.sendTime(typedAt: t0, lastSent: nil, blockedUntil: nil)
        let second = RemoteSearchPolicy.sendTime(typedAt: t0.addingTimeInterval(0.2), lastSent: nil, blockedUntil: nil)
        XCTAssertGreaterThan(second, first)
    }
}

final class RemoteSearchCacheTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testAHitWithinTheTTLAndAMissAfter() {
        var cache = RemoteSearchCache<[String]>()
        cache.put(["a"], source: "task", query: "Login Bug", at: t0)
        XCTAssertEqual(cache.get(source: "task", query: "login  bug", at: t0.addingTimeInterval(59)), ["a"])
        XCTAssertNil(cache.get(source: "task", query: "login bug", at: t0.addingTimeInterval(61)))
    }

    func testSourcesDoNotShareEntries() {
        var cache = RemoteSearchCache<[String]>()
        cache.put(["a"], source: "task", query: "x1", at: t0)
        XCTAssertNil(cache.get(source: "pr", query: "x1", at: t0))
    }

    /// "No results" is an answer worth remembering: retyping the same dead
    /// query must not hit the network again.
    func testAnEmptyAnswerIsCachedToo() {
        var cache = RemoteSearchCache<[String]>()
        cache.put([], source: "task", query: "zzz", at: t0)
        XCTAssertEqual(cache.get(source: "task", query: "zzz", at: t0), [])
    }

    func testTheOldestEntryIsDroppedAtTheLimit() {
        var cache = RemoteSearchCache<Int>(limit: 3)
        for i in 1...4 { cache.put(i, source: "s", query: "q\(i)", at: t0.addingTimeInterval(Double(i))) }
        XCTAssertNil(cache.get(source: "s", query: "q1", at: t0.addingTimeInterval(5)))
        XCTAssertEqual(cache.get(source: "s", query: "q4", at: t0.addingTimeInterval(5)), 4)
        XCTAssertEqual(cache.count, 3)
    }

    func testInvalidateDropsOneSourceOnly() {
        var cache = RemoteSearchCache<Int>()
        cache.put(1, source: "task", query: "ab", at: t0)
        cache.put(2, source: "pr", query: "ab", at: t0)
        cache.invalidate(source: "task")
        XCTAssertNil(cache.get(source: "task", query: "ab", at: t0))
        XCTAssertEqual(cache.get(source: "pr", query: "ab", at: t0), 2)
    }
}

final class SearchGenerationTests: XCTestCase {
    func testOnlyTheLatestGenerationIsAccepted() {
        var gen = SearchGeneration()
        let first = gen.next()
        let second = gen.next()
        XCTAssertFalse(gen.accepts(first), "a late answer to an old query must be dropped")
        XCTAssertTrue(gen.accepts(second))
    }

    func testCancellingInvalidatesTheOutstandingRequest() {
        var gen = SearchGeneration()
        let pending = gen.next()
        gen.cancel()
        XCTAssertFalse(gen.accepts(pending))
    }
}

final class RemoteSearchFailureTests: XCTestCase {
    func testStatusesMapToTheirOwnWording() {
        XCTAssertEqual(RemoteSearchFailure(error: AzureDevOpsError.serverError(401)), .authOrTarget)
        XCTAssertEqual(RemoteSearchFailure(error: AzureDevOpsError.serverError(203)), .authOrTarget)
        XCTAssertEqual(RemoteSearchFailure(error: AzureDevOpsError.serverError(503)), .unreachable)
        XCTAssertEqual(RemoteSearchFailure(error: AzureDevOpsError.transport("offline")), .unreachable)
        XCTAssertEqual(RemoteSearchFailure(error: AzureDevOpsError.invalidPayload), .badResponse)
    }

    /// The shared classifier folds 429 into "unreachable"; here it must stay
    /// distinct, because it blocks further sends.
    func testARateLimitIsNotFoldedIntoUnreachable() {
        XCTAssertEqual(RemoteSearchFailure(error: AzureDevOpsError.serverError(429)), .rateLimited)
    }

    func testEveryFailureHasAShortSentence() {
        let all: [RemoteSearchFailure] = [
            .notConfigured, .credentialsUnavailable, .authOrTarget,
            .rateLimited, .unreachable, .badResponse, .queryRejected,
        ]
        for failure in all {
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertLessThan(failure.message.count, 90, "\(failure) is not one line")
        }
    }

    /// A locked keychain is not "you have not set a token up".
    func testALockedKeychainIsNotWordedAsNotConfigured() {
        XCTAssertNotEqual(RemoteSearchFailure.credentialsUnavailable.message,
                          RemoteSearchFailure.notConfigured.message)
        XCTAssertTrue(RemoteSearchFailure.notConfigured.message.contains("Credentials"))
    }

    func testOnlyARateLimitBlocksFurtherSends() {
        XCTAssertTrue(RemoteSearchFailure.rateLimited.blocksFurtherSends)
        XCTAssertFalse(RemoteSearchFailure.unreachable.blocksFurtherSends)
        XCTAssertFalse(RemoteSearchFailure.authOrTarget.blocksFurtherSends)
    }

    func testRateLimitBackoffDefaultIsLongEnoughForTheMeasuredWindow() {
        // CLAUDE.md: CoinGecko answered retry-after 55; a shorter back-off just
        // earns another 429.
        XCTAssertGreaterThanOrEqual(RemoteSearchPolicy.rateLimitBackoff, 55)
    }
}

final class RemoteSearchStateTests: XCTestCase {
    func testDisplayText() {
        typealias S = RemoteSearchState<[String]>
        XCTAssertNil(S.idle.line(noun: "tasks"))
        XCTAssertEqual(S.searching.line(noun: "tasks"), "Searching…")
        XCTAssertEqual(S.empty.line(noun: "tasks"), "No tasks found")
        XCTAssertNil(S.results(["a"]).line(noun: "tasks"))
        XCTAssertEqual(S.failed(.rateLimited).line(noun: "tasks"), RemoteSearchFailure.rateLimited.message)
    }

    func testEmptyIsNotWordedAsAnAnswerAboutTheWholeAccount() {
        // "No tasks found" says what happened to this search, nothing more.
        XCTAssertFalse(RemoteSearchState<[String]>.empty.line(noun: "tasks")!.lowercased().contains("no such"))
    }
}
