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

final class ShipBoxFairMergeTests: XCTestCase {
    /// The point of the feature: a busy repo's history must not hide a quiet
    /// repo's latest run. With k repos, every repo's newest run sits in the
    /// first k positions.
    func testEveryReposNewestRunSitsInTheFirstRepoCountPositions() {
        let merged = ShipBoxMerge.fairMerge([
            [makeRun("a/busy", 3, at: 300), makeRun("a/busy", 2, at: 200), makeRun("a/busy", 1, at: 100)],
            [makeRun("b/quiet", 1, at: 150)],
            [makeRun("c/mid", 2, at: 250), makeRun("c/mid", 1, at: 50)],
        ])
        XCTAssertEqual(Set(merged.prefix(3).map(\.repo)), ["a/busy", "b/quiet", "c/mid"])
    }

    /// Round-robin, not quota: a busy repo's second-newest run never outranks
    /// a quiet repo's newest — once every repo has one slot, the second round
    /// begins.
    func testABusyReposSecondNewestDoesNotOutrankAQuietReposNewest() {
        let merged = ShipBoxMerge.fairMerge([
            [makeRun("a/busy", 2, at: 100), makeRun("a/busy", 1, at: 99)],
            [makeRun("b/quiet", 1, at: 98)],
        ])
        XCTAssertEqual(merged.map(\.repo), ["a/busy", "b/quiet", "a/busy"])
    }

    /// The first element stays the globally newest run, so the small face's
    /// link target and the "latest build" story do not change.
    func testTheFirstElementIsStillTheGloballyNewestRun() {
        let merged = ShipBoxMerge.fairMerge([
            [makeRun("a/x", 3, at: 300), makeRun("a/x", 2, at: 100)],
            [makeRun("b/y", 1, at: 250)],
            [makeRun("c/z", 1, at: 10)],
        ])
        XCTAssertEqual(merged.first?.repo, "a/x")
        XCTAssertEqual(merged.first?.runNumber, 3)
    }

    /// Within a round, the freshest runs come first — the top of the list
    /// still reads "what is newest right now".
    func testWithinARoundRunsOrderByCreationDate() {
        let merged = ShipBoxMerge.fairMerge([
            [makeRun("a/x", 1, at: 200)],
            [makeRun("b/y", 1, at: 300)],
            [makeRun("c/z", 1, at: 100)],
        ])
        XCTAssertEqual(merged.map(\.repo), ["b/y", "a/x", "c/z"])
    }

    /// A repo's own runs stay newest-first relative to each other.
    func testAReposOwnRunsStayNewestFirst() {
        let merged = ShipBoxMerge.fairMerge([
            [makeRun("a/x", 5, at: 500), makeRun("a/x", 4, at: 400), makeRun("a/x", 3, at: 300)],
            [makeRun("b/y", 1, at: 450)],
        ])
        XCTAssertEqual(merged.filter { $0.repo == "a/x" }.map(\.runNumber), [5, 4, 3])
    }

    /// Two runs created in the same second must not reorder between ticks —
    /// the same stability rule the existing merge pins; ties break by the
    /// order the repos were fetched.
    func testTiesBreakStablyByFetchOrder() {
        let first = ShipBoxMerge.fairMerge([
            [makeRun("a/first", 1, at: 100)],
            [makeRun("b/second", 2, at: 100)],
        ])
        XCTAssertEqual(first.map(\.repo), ["a/first", "b/second"])
        let second = ShipBoxMerge.fairMerge([
            [makeRun("a/first", 1, at: 100)],
            [makeRun("b/second", 2, at: 100)],
        ])
        XCTAssertEqual(first, second)
    }

    /// One repo is the current behavior: pure newest-first.
    func testOneRepoDegradesToTheCurrentMerge() {
        let runs = [makeRun("a/x", 3, at: 300), makeRun("a/x", 2, at: 200), makeRun("a/x", 1, at: 100)]
        XCTAssertEqual(ShipBoxMerge.fairMerge([runs]), runs)
    }

    /// No repos, or only empty fetches, contribute nothing.
    func testEmptyInputsContributeNothing() {
        XCTAssertTrue(ShipBoxMerge.fairMerge([]).isEmpty)
        XCTAssertTrue(ShipBoxMerge.fairMerge([[], [], []]).isEmpty)
    }

    /// Repos with fewer runs than the deepest round are skipped, not padded
    /// with placeholders.
    func testShortReposAreSkippedNotPadded() {
        let merged = ShipBoxMerge.fairMerge([
            [makeRun("a/x", 1, at: 100)],
            [makeRun("b/y", 3, at: 300), makeRun("b/y", 2, at: 200), makeRun("b/y", 1, at: 50)],
        ])
        XCTAssertEqual(merged.map(\.runNumber), [3, 1, 2, 1])
    }

    /// The page-sufficiency property: with every repo long enough, filling
    /// the first runCount positions needs at most ceil(runCount / repoCount)
    /// runs from any one repo — within today's per_page = max(runCount, 2).
    /// (The uneven case — short repos exhausting early — is bounded by
    /// runCount itself, which per_page already supplies.)
    func testFillingTheVisibleWindowConsumesAtMostCeilPerRepo() {
        let perRepo = (0..<5).map { index in
            (1...8).map { makeRun("r\(index)/repo", $0, at: TimeInterval($0 * 10 + index)) }
        }
        let merged = ShipBoxMerge.fairMerge(perRepo)
        let visible = Array(merged.prefix(8))
        let counts = Dictionary(grouping: visible, by: \.repo).mapValues(\.count)
        XCTAssertEqual(counts.values.max(), 2, "ceil(8/5) = 2 runs from any repo in the first 8")
        XCTAssertEqual(counts.count, 5, "all five repos are visible in the first 8")
    }
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
