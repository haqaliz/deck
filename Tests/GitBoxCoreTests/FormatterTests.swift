import XCTest
@testable import GitBoxCore

final class GitFormatterTests: XCTestCase {
    func testShortNameLastComponent() {
        XCTAssertEqual(GitFormatters.shortName(path: "/Users/aliz/dev/at/deck"), "deck")
        XCTAssertEqual(GitFormatters.shortName(path: "/a/b/repo"), "repo")
    }

    func testShortNameStripsTrailingSlash() {
        XCTAssertEqual(GitFormatters.shortName(path: "/a/b/repo/"), "repo")
    }

    func testShortNameSingleComponent() {
        XCTAssertEqual(GitFormatters.shortName(path: "repo"), "repo")
        XCTAssertEqual(GitFormatters.shortName(path: "/repo"), "repo")
    }

    func testCommitCountSmall() {
        XCTAssertEqual(GitFormatters.commitCount(0), "0")
        XCTAssertEqual(GitFormatters.commitCount(5), "5")
    }

    func testCommitCountGroupsThousands() {
        XCTAssertEqual(GitFormatters.commitCount(1234), "1,234")
    }

    func testDisambiguatedNamesUniqueStaysShort() {
        let repos = [
            RepoCommits(shortName: "deck", path: "/Users/aliz/dev/at/deck", todayCount: 3),
            RepoCommits(shortName: "manifold", path: "/Users/aliz/dev/manifold/manifold", todayCount: 1),
        ]
        XCTAssertEqual(GitFormatters.disambiguatedNames(repos: repos), ["deck", "manifold"])
    }

    func testDisambiguatedNamesRepeatsGetTwoLevelName() {
        let repos = [
            RepoCommits(shortName: "deck", path: "/Users/aliz/dev/at/deck", todayCount: 3),
            RepoCommits(shortName: "deck", path: "/Users/aliz/dev/manifold/deck", todayCount: 1),
        ]
        XCTAssertEqual(GitFormatters.disambiguatedNames(repos: repos), ["at/deck", "manifold/deck"])
    }

    func testDisambiguatedNamesEmpty() {
        XCTAssertEqual(GitFormatters.disambiguatedNames(repos: []), [])
    }
}
