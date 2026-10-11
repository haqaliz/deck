import XCTest

// Commits: `git log --grep` across the repositories GitBox scans, of any age.
// The typed text becomes arguments to a subprocess, which is the dangerous
// direction: there is no shell (arguments are an array), but git itself would
// happily treat `--output=/tmp/x` or `--upload-pack=…` as an option if typed
// text ever became an argument of its own.

final class CommitSearchArgumentsTests: XCTestCase {
    private let allowedFixed: Set<String> = ["git", "-C", "log", "--all", "-i", "-F", "--all-match", "-n", "--"]

    func testAPlainSearchBuildsTheExpectedCommand() {
        let args = GitCommitSearch.arguments(repoPath: "/Users/a/dev/deck", tokens: ["fix", "login"], limit: 8)
        XCTAssertEqual(args.prefix(4), ["git", "-C", "/Users/a/dev/deck", "log"])
        XCTAssertTrue(args.contains("--grep=fix"))
        XCTAssertTrue(args.contains("--grep=login"))
        XCTAssertTrue(args.contains("--all"), "any branch, any age")
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("-F"), "fixed strings: typed text is never a regex")
        XCTAssertTrue(args.contains("--all-match"), "every word must match")
        XCTAssertEqual(args.last, "--", "nothing after the options can be read as a revision or option")
    }

    func testTheLimitIsPassedAsItsOwnPair() {
        let args = GitCommitSearch.arguments(repoPath: "/r", tokens: ["x1"], limit: 8)
        let i = try! XCTUnwrap(args.firstIndex(of: "-n"))
        XCTAssertEqual(args[i + 1], "8")
    }

    /// The point of the file: whatever is typed, it only ever appears inside a
    /// `--grep=` argument, never as an argument of its own.
    func testHostileTextCanOnlyAppearInsideAGrepArgument() {
        let hostile = [
            "--output=/tmp/pwn", "-S foo", "--upload-pack=touch /tmp/x", "--exec=sh", "-n 1",
            "$(rm -rf ~)", "; ls", "`id`", "&& echo hi", "\n--exec=sh", "--", "-", "--all-match",
            "--format=%H", "--git-dir=/etc", "--work-tree=/", "-C /etc",
        ]
        for text in hostile {
            let tokens = GitCommitSearch.tokens(for: text)
            let args = GitCommitSearch.arguments(repoPath: "/r", tokens: tokens, limit: 8)
            let free = args.filter { arg in
                !allowedFixed.contains(arg) && !arg.hasPrefix("--grep=") && arg != "/r"
                    && !arg.hasPrefix("--format=") && Int(arg) == nil
            }
            XCTAssertTrue(free.isEmpty, "\(text) leaked arguments: \(free)")
            // …and there is exactly one `--format=` (ours), never a typed one.
            XCTAssertEqual(args.filter { $0.hasPrefix("--format=") }.count, 1, text)
            XCTAssertEqual(args.filter { $0 == "-n" }.count, 1, text)
            XCTAssertEqual(args.filter { $0 == "-C" }.count, 1, text)
        }
    }

    func testTheRepoPathIsAlwaysTheValueOfDashC() {
        let args = GitCommitSearch.arguments(repoPath: "--upload-pack=x", tokens: ["ab"], limit: 3)
        XCTAssertEqual(args[1], "-C")
        XCTAssertEqual(args[2], "--upload-pack=x", "consumed as -C's value, not parsed as an option")
    }

    func testTokensSplitOnWhitespaceAndAreCapped() {
        XCTAssertEqual(GitCommitSearch.tokens(for: "  fix   login\tbug "), ["fix", "login", "bug"])
        XCTAssertEqual(GitCommitSearch.tokens(for: "a b c d e f g h").count, GitCommitSearch.maxTokens)
        XCTAssertEqual(GitCommitSearch.tokens(for: String(repeating: "x", count: 500)).first?.count,
                       GitCommitSearch.maxTokenLength)
    }

    func testControlCharactersNeverReachAnArgument() {
        let tokens = GitCommitSearch.tokens(for: "fix\u{0}login\u{7}\u{1F}x")
        for t in tokens { XCTAssertFalse(t.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }, t) }
    }

    func testTooLittleToSearchBuildsNoTokens() {
        XCTAssertTrue(GitCommitSearch.tokens(for: "").isEmpty)
        XCTAssertTrue(GitCommitSearch.tokens(for: "  a ").isEmpty)
    }
}

final class CommitSearchParsingTests: XCTestCase {
    private let sep = "\u{1F}"

    func testParsesWellFormedLines() throws {
        let raw = "abc1234567890def\(sep)Ada\(sep)1768478400\(sep)fix login redirect\n"
            + "fff0000111122223\(sep)Bob\(sep)1700000000\(sep)revert: migration\n"
        let hits = GitCommitParser.parse(raw)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].hash, "abc1234567890def")
        XCTAssertEqual(hits[0].shortHash, "abc1234")
        XCTAssertEqual(hits[0].author, "Ada")
        XCTAssertEqual(hits[0].subject, "fix login redirect")
        XCTAssertEqual(hits[0].date, Date(timeIntervalSince1970: 1_768_478_400))
    }

    func testMalformedLinesAreSkippedNotFatal() {
        let raw = "garbage\n\n\(sep)\(sep)\(sep)\nabc1234567890def\(sep)Ada\(sep)notadate\(sep)subject\n"
            + "abc1234567890def\(sep)Ada\(sep)1768478400\(sep)\nok00000000000000\(sep)Cy\(sep)1\(sep)fine\n"
        XCTAssertEqual(GitCommitParser.parse(raw).map(\.subject), ["fine"])
    }

    func testASubjectMayContainSpacesAndPunctuation() {
        let raw = "abc1234567890def\(sep)Ada\(sep)1\(sep)fix(auth): don't loop — see #12\n"
        XCTAssertEqual(GitCommitParser.parse(raw).first?.subject, "fix(auth): don't loop — see #12")
    }

    func testEmptyOutputIsNoHits() {
        XCTAssertTrue(GitCommitParser.parse("").isEmpty)
    }
}

final class CommitSearchResultsTests: XCTestCase {
    private func hit(_ subject: String, hash: String = "abc1234567890def", t: TimeInterval) -> GitCommitHit {
        GitCommitHit(hash: hash, author: "Ada", date: Date(timeIntervalSince1970: t), subject: subject)
    }

    func testEnterCopiesTheShortHash() {
        let r = GitCommitSearch.results(from: [("deck", "/dev/deck", [hit("fix login", t: 100)])])[0]
        XCTAssertEqual(r.provider, .commit)
        XCTAssertEqual(r.title, "fix login")
        XCTAssertEqual(r.action, .copy("abc1234"))
        XCTAssertTrue(r.subtitle.hasPrefix("deck · abc1234 · Ada"))
    }

    func testNewestFirstAcrossRepositories() {
        let rows: [(String, String, [GitCommitHit])] = [
            ("old", "/dev/old", [hit("older", hash: "1111111aaaaaaaa", t: 100)]),
            ("new", "/dev/new", [hit("newer", hash: "2222222bbbbbbbb", t: 900)]),
        ]
        let sorted = SpotlightRanking.sorted(GitCommitSearch.results(from: rows))
        XCTAssertEqual(sorted.map(\.title), ["newer", "older"])
    }

    /// The same commit is reachable from two clones; a repo path is part of the identity.
    func testIDsIncludeTheRepositoryPath() {
        let h = hit("same", t: 5)
        let rows: [(String, String, [GitCommitHit])] = [("a", "/dev/a", [h]), ("a", "/work/a", [h])]
        XCTAssertEqual(Set(GitCommitSearch.results(from: rows).map(\.id)).count, 2)
    }

    func testTheTotalIsCapped() {
        let many = (0..<100).map { hit("c\($0)", hash: String(format: "%015x", $0), t: Double($0)) }
        XCTAssertLessThanOrEqual(GitCommitSearch.results(from: [("r", "/r", many)]).count, GitCommitSearch.totalLimit)
    }
}

/// The real runner against a real repository, so the subprocess path (read
/// before wait, environment, parsing real `git` output) is exercised, not just
/// the argument list.
///
/// Hermetic: the repository is built with the user's and system git config
/// switched off (a global `commit.gpgsign` or hook made each setup commit take
/// ~0.7s), and built once for the whole class.
final class CommitSearchIntegrationTests: XCTestCase {
    private static let hermetic = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
                                   "GIT_CONFIG_NOSYSTEM": "1"]
    private static var dir: URL!
    private var dir: URL { Self.dir }

    override class func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("deck-commit-search-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        run("init", "-q", "-b", "main")
        run("config", "user.email", "t@example.com")
        run("config", "user.name", "Tess")
        commit("fix login redirect", "2020-01-02T10:00:00")
        commit("unrelated cleanup", "2021-03-04T10:00:00")
        commit("Revert \"fix login redirect\"", "2022-05-06T10:00:00")
        // A commit only on another branch: `--all` must still find it.
        run("checkout", "-q", "-b", "side")
        commit("fix login on the side branch", "2023-07-08T10:00:00")
        run("checkout", "-q", "main")
    }

    override class func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    @discardableResult
    private static func run(_ args: String..., extraEnv: [String: String] = [:]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        p.environment = ProcessInfo.processInfo.environment
            .merging(hermetic) { $1 }.merging(extraEnv) { $1 }
        p.standardOutput = nil; p.standardError = nil
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    private static func commit(_ message: String, _ date: String) {
        try? "x\(UUID().uuidString)".write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        run("add", "f.txt")
        run("commit", "-q", "-m", message, extraEnv: ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date])
    }

    func testTheFixtureRepositoryWasBuilt() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path))
    }

    private func search(_ text: String) async -> [GitCommitHit] {
        let rows = await HostGitCommitSearch.search(repos: [dir], tokens: GitCommitSearch.tokens(for: text))
        return rows.flatMap(\.hits)
    }

    func testFindsCommitsOfAnyAgeOnAnyBranchNewestFirst() async {
        let subjects = await search("login").map(\.subject)
        XCTAssertEqual(subjects, ["fix login on the side branch", "Revert \"fix login redirect\"", "fix login redirect"])
    }

    func testEveryWordMustMatchAndCaseIsIgnored() async {
        let hits = await search("FIX redirect")
        XCTAssertEqual(Set(hits.map(\.subject)), ["fix login redirect", "Revert \"fix login redirect\""])
    }

    func testTextIsLiteralNotARegex() async {
        let hits = await search("fix.*redirect")
        XCTAssertTrue(hits.isEmpty, "'.*' must be matched literally, not as a pattern")
    }

    func testNoMatchIsAnEmptyAnswerNotAnError() async {
        let none = await search("zzzznope")
        XCTAssertTrue(none.isEmpty)
    }

    /// The real proof for the dangerous direction: git would write this file if
    /// the text ever became its own argument.
    func testAnOptionShapedQueryDoesNotRunAsAnOption() async throws {
        let victim = FileManager.default.temporaryDirectory.appendingPathComponent("deck-pwn-\(UUID().uuidString)")
        for text in ["--output=\(victim.path)", "--output=\(victim.path) login"] {
            _ = await search(text)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: victim.path), "git wrote the file: an option leaked")
    }

    func testAMissingRepositoryIsSkippedNotFatal() async {
        let gone = dir.appendingPathComponent("does-not-exist")
        let rows = await HostGitCommitSearch.search(repos: [gone, dir], tokens: ["login"])
        XCTAssertEqual(rows.count, 1)
    }

    func testNoTokensRunsNothing() async {
        let rows = await HostGitCommitSearch.search(repos: [dir], tokens: [])
        XCTAssertTrue(rows.isEmpty, "an empty grep would list every commit")
    }
}
