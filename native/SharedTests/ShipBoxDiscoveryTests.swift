import XCTest

// Dynamic mode's two pure decisions (PRD §5): reading the repo inventory, and
// choosing which repos to fetch in full.
//
// The fixture `github_repos.json` is a trimmed copy of a real
// `/user/repos?sort=pushed&per_page=100&affiliation=owner` response.

private func fixture(_ name: String) throws -> Data {
    let url = Bundle(for: RepoInventoryParserTests.self).url(forResource: name, withExtension: "json")
    return try Data(contentsOf: try XCTUnwrap(url, "missing fixture \(name).json"))
}

final class RepoInventoryParserTests: XCTestCase {
    func testParsesTheLiveFixtureInPushedOrder() throws {
        let repos = try XCTUnwrap(RepoInventoryParser.parse(fixture("github_repos")))
        XCTAssertEqual(repos.first, "haqaliz/belay")
        XCTAssertEqual(repos.count, 6)
    }

    /// The API is asked for `sort=pushed`, so its order is the answer — the
    /// parser must not impose one of its own.
    func testTheAPIOrderIsPreserved() {
        let data = Data(#"[{"full_name":"z/last"},{"full_name":"a/first"}]"#.utf8)
        XCTAssertEqual(RepoInventoryParser.parse(data), ["z/last", "a/first"])
    }

    /// An archived repo is read-only: it cannot produce a new run, so spending
    /// one of the candidate slots probing it is pure waste.
    func testArchivedReposAreSkipped() {
        let data = Data(#"[{"full_name":"a/live"},{"full_name":"a/old","archived":true}]"#.utf8)
        XCTAssertEqual(RepoInventoryParser.parse(data), ["a/live"])
    }

    func testEntriesWithoutANameAreSkippedRatherThanFailingTheWholeList() {
        let data = Data(#"[{"nope":1},{"full_name":"a/ok"}]"#.utf8)
        XCTAssertEqual(RepoInventoryParser.parse(data), ["a/ok"])
    }

    func testAnEmptyListIsAnAnswerNotAFailure() {
        XCTAssertEqual(RepoInventoryParser.parse(Data("[]".utf8)), [])
    }

    func testGarbageIsNil() {
        XCTAssertNil(RepoInventoryParser.parse(Data(#"{"message":"Bad credentials"}"#.utf8)))
    }
}

final class DynamicRepoSelectorTests: XCTestCase {
    private let inventory = ["a/1", "a/2", "a/3", "a/4", "a/5", "a/6", "a/7", "a/8", "a/9", "a/10"]

    /// Nothing in a repo object says whether it has Actions (probe P3), so a
    /// buffer of three is probed beyond what is wanted — on real data the
    /// first repo without runs was the 7th by push date.
    func testCandidatesAreTheWantedCountPlusABufferOfThree() {
        XCTAssertEqual(DynamicRepoSelector.candidates(inventory: inventory, maxCount: 3).count, 6)
    }

    /// Eight is the ceiling: the whole point of the buffer is to stay inside
    /// one 60s tick.
    func testCandidatesAreCappedAtEight() {
        XCTAssertEqual(DynamicRepoSelector.candidates(inventory: inventory, maxCount: 5).count, 8)
    }

    func testCandidatesCannotExceedTheInventory() {
        XCTAssertEqual(DynamicRepoSelector.candidates(inventory: ["a/1"], maxCount: 5), ["a/1"])
    }

    func testWinnersAreTheFirstReposThatActuallyHaveRuns() {
        let picked = DynamicRepoSelector.select(
            probed: [("a/1", false), ("a/2", true), ("a/3", false), ("a/4", true), ("a/5", true)],
            maxCount: 2
        )
        XCTAssertEqual(picked, ["a/2", "a/4"])
    }

    /// A probe that failed is not evidence the repo is empty, but it is not
    /// evidence it is worth a full fetch either — it drops out of this tick
    /// and gets another chance on the next one.
    func testAFailedProbeCountsAsNoRuns() {
        XCTAssertEqual(DynamicRepoSelector.select(probed: [("a/1", false), ("a/2", true)], maxCount: 2), ["a/2"])
    }

    func testFewerWinnersThanWantedIsFine() {
        XCTAssertEqual(DynamicRepoSelector.select(probed: [("a/1", true)], maxCount: 3), ["a/1"])
    }

    func testNoWinnersIsAnEmptyList() {
        XCTAssertEqual(DynamicRepoSelector.select(probed: [("a/1", false)], maxCount: 3), [])
    }
}
