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
}
