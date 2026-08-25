import XCTest

// The pure half of multi-repo ShipBox (PRD §3, §6): how runs from several
// repos become one list, how a row names its repo, and how a partial failure
// is worded. No network, no clock.

private func makeRun(
    _ repo: String,
    _ number: Int,
    at seconds: TimeInterval,
    status: ShipStatus = .success
) -> ShipRun {
    ShipRun(
        repo: repo,
        name: "CI",
        runNumber: number,
        branch: "main",
        status: status,
        createdAt: Date(timeIntervalSince1970: seconds),
        updatedAt: Date(timeIntervalSince1970: seconds + 60),
        htmlURL: "https://github.com/\(repo)/actions/runs/\(number)"
    )
}

final class ShipBoxMergeTests: XCTestCase {
    func testRunsFromSeveralReposInterleaveByCreationDate() {
        let merged = ShipBoxMerge.merge([
            [makeRun("a/deck", 2, at: 200), makeRun("a/deck", 1, at: 100)],
            [makeRun("a/cyclo", 9, at: 150)],
        ])
        XCTAssertEqual(merged.map(\.runNumber), [2, 9, 1])
    }

    /// Azure taught PRBox that creation date is the only key every source can
    /// promise; here it keeps two repos' runs in one honest order.
    func testNewestFirst() {
        let merged = ShipBoxMerge.merge([[makeRun("a/x", 1, at: 50)], [makeRun("a/y", 2, at: 500)]])
        XCTAssertEqual(merged.first?.repo, "a/y")
    }

    /// Two runs created in the same second must not reorder between ticks —
    /// a list that shuffles under a stable snapshot reads as a bug.
    func testTiesBreakStablyByTheOrderTheReposWereFetched() {
        let merged = ShipBoxMerge.merge([
            [makeRun("a/first", 1, at: 100)],
            [makeRun("b/second", 2, at: 100)],
        ])
        XCTAssertEqual(merged.map(\.repo), ["a/first", "b/second"])
    }

    func testAnEmptyFetchContributesNothing() {
        XCTAssertEqual(ShipBoxMerge.merge([[], [makeRun("a/x", 1, at: 10)], []]).count, 1)
    }
}

final class ShipBoxLabelTests: XCTestCase {
    func testTheOwnerIsDroppedWhenItIsJustNoise() {
        let labels = ShipBoxLabels.labels(for: ["haqaliz/deck", "haqaliz/cyclo"])
        XCTAssertEqual(labels["haqaliz/deck"], "deck")
        XCTAssertEqual(labels["haqaliz/cyclo"], "cyclo")
    }

    /// One rule per snapshot, never per row: if any two repos collide, every
    /// row shows its owner, so the list cannot mix two naming schemes.
    func testACollisionMakesEveryRowShowItsOwner() {
        let labels = ShipBoxLabels.labels(for: ["a/deck", "b/deck", "c/other"])
        XCTAssertEqual(labels["a/deck"], "a/deck")
        XCTAssertEqual(labels["b/deck"], "b/deck")
        XCTAssertEqual(labels["c/other"], "c/other", "the rule applies to the whole snapshot")
    }

    func testCollisionsAreCaseInsensitiveBecauseGitHubIs() {
        let labels = ShipBoxLabels.labels(for: ["a/Deck", "b/deck"])
        XCTAssertEqual(labels["a/Deck"], "a/Deck")
    }

    func testAMalformedRepoIsLeftExactlyAsConfigured() {
        XCTAssertEqual(ShipBoxLabels.labels(for: ["nostslash"])["nostslash"], "nostslash")
    }
}

final class ShipBoxNoteTests: XCTestCase {
    private func failure(_ repo: String, _ outcome: FetchOutcome) -> ShipBoxNote.Failure {
        ShipBoxNote.Failure(repo: repo, outcome: outcome)
    }

    func testNoFailuresReadsAsNothingAtAll() {
        XCTAssertNil(ShipBoxNote.compose(failures: [], mode: .staticList))
    }

    func testOneFailureNamesTheRepoAndTheReason() {
        let note = ShipBoxNote.compose(failures: [failure("a/cyclo", .authOrTarget)], mode: .staticList)
        XCTAssertEqual(note, "cyclo: check repo + token")
    }

    /// Several repos down for one reason is one fact, not three — the rule
    /// PRChip.text already applies to GitHub + Azure.
    func testFailuresSharingAReasonCollapseIntoOneSentence() {
        let note = ShipBoxNote.compose(
            failures: [failure("a/cyclo", .unreachable), failure("a/pong", .unreachable), failure("a/x", .unreachable)],
            mode: .staticList
        )
        XCTAssertEqual(note, "cyclo + 2 more: can't reach GitHub")
    }

    /// Two different reasons cannot both fit, so name one rather than imply
    /// they share a cause.
    func testMixedReasonsNameTheFirstAndCountTheRest() {
        let note = ShipBoxNote.compose(
            failures: [failure("a/cyclo", .authOrTarget), failure("a/pong", .unreachable)],
            mode: .staticList
        )
        XCTAssertEqual(note, "cyclo: check repo + token +1 more")
    }

    /// In dynamic mode there is no repo field to check, so the wording must
    /// not send the user looking for one (PRD C3).
    func testDynamicModeBlamesTheTokenNotAMissingRepoField() {
        let note = ShipBoxNote.compose(failures: [failure("a/cyclo", .authOrTarget)], mode: .dynamic)
        XCTAssertEqual(note, "cyclo: check your token")
    }
}

final class ShipBoxSnapshotDecodeTests: XCTestCase {
    /// A v1.27 snapshot must still render. `ShipBoxSnapshotStore.load()`
    /// returns nil on a decode error, and nil means the face says "No build
    /// data" — a blank widget on the first launch after an upgrade.
    func testAPreMultiRepoSnapshotStillDecodes() throws {
        let json = """
        {"writtenAt":768000000,"repo":"haqaliz/deck","runs":[
          {"name":"Deck","runNumber":15,"branch":"master","status":"success",
           "createdAt":768000000,"updatedAt":768000060,"htmlURL":"https://x/1"}]}
        """
        let s = try JSONDecoder().decode(ShipBoxSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.repos, ["haqaliz/deck"])
        XCTAssertEqual(s.runs.count, 1)
        XCTAssertEqual(s.runs.first?.repo, "haqaliz/deck", "a legacy run belongs to the only repo there was")
        XCTAssertNil(s.note)
    }

    func testTheCurrentShapeRoundTrips() throws {
        let snapshot = ShipBoxSnapshot(
            writtenAt: Date(timeIntervalSince1970: 100),
            repos: ["a/x", "a/y"],
            runs: [makeRun("a/x", 1, at: 90)],
            note: "y: can't reach GitHub"
        )
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(ShipBoxSnapshot.self, from: data), snapshot)
    }
}
