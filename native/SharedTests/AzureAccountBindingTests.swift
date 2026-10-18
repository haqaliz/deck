import XCTest

/// The Azure slot now binds several accounts (one org each). Three things are
/// pinned here because getting any wrong is silent: the normalisation every
/// call site funnels through, the on-disk migration from the pre-list
/// `accountID` string, and the fact that a hand-written encoder must not drop a
/// field (the CLAUDE.md hand-written-`CodingKeys` trap).
final class AzureAccountBindingTests: XCTestCase {

    // MARK: - Normalisation

    func testTrimsAndDropsEmpties() {
        XCTAssertEqual(
            AzureAccountBinding.normalise(["  a1 ", "", "   ", "a2"]),
            ["a1", "a2"]
        )
    }

    func testDeduplicatesCaseInsensitivelyKeepingTheFirstSpelling() {
        XCTAssertEqual(
            AzureAccountBinding.normalise(["A1", "a1", "A1"]),
            ["A1"]
        )
    }

    func testPreservesOrder() {
        XCTAssertEqual(AzureAccountBinding.normalise(["b", "a", "c"]), ["b", "a", "c"])
    }

    func testCapsAtFour() {
        XCTAssertEqual(
            AzureAccountBinding.normalise(["a", "b", "c", "d", "e"]),
            ["a", "b", "c", "d"]
        )
        XCTAssertEqual(AzureAccountBinding.maxAccounts, 4)
    }

    func testEmptyInputYieldsEmptyList() {
        XCTAssertEqual(AzureAccountBinding.normalise([]), [])
        XCTAssertEqual(AzureAccountBinding.normalise(["", "  "]), [])
    }

    // MARK: - Editing one of the slots

    func testTypingSurvives() {
        XCTAssertEqual(
            AzureAccountBinding.setSlot(0, in: ["a1"], to: "a1x"),
            ["a1x"]
        )
    }

    func testWritingPastTheEndPads() {
        XCTAssertEqual(AzureAccountBinding.setSlot(2, in: ["A"], to: "C"), ["A", "", "C"])
    }

    func testClearingAMiddleSlotKeepsTheOnesAfterItInPlace() {
        XCTAssertEqual(AzureAccountBinding.setSlot(0, in: ["A", "B"], to: ""), ["", "B"])
    }

    func testClearingTheLastSlotShrinksTheList() {
        XCTAssertEqual(AzureAccountBinding.setSlot(1, in: ["A", "B"], to: ""), ["A"])
        XCTAssertEqual(AzureAccountBinding.setSlot(0, in: ["A"], to: ""), [])
    }

    func testASlotBeyondTheCapIsIgnored() {
        let four = ["a", "b", "c", "d"]
        XCTAssertEqual(AzureAccountBinding.setSlot(4, in: four, to: "e"), four)
    }

    // MARK: - TaskBoxSettings migration

    private func taskBox(_ json: String) throws -> TaskBoxSettings {
        try JSONDecoder().decode(TaskBoxSettings.self, from: Data(json.utf8))
    }

    func testTaskBoxDecodesTheAccountIDsList() throws {
        let s = try taskBox(#"{"accountIDs":["a1","a2"]}"#)
        XCTAssertEqual(s.accountIDs, ["a1", "a2"])
    }

    func testTaskBoxDecodesALegacyAccountIDAsAOneElementList() throws {
        let s = try taskBox(#"{"accountID":"a1"}"#)
        XCTAssertEqual(s.accountIDs, ["a1"])
    }

    func testTaskBoxPluralWinsOverLegacy() throws {
        let s = try taskBox(#"{"accountID":"old","accountIDs":["new"]}"#)
        XCTAssertEqual(s.accountIDs, ["new"])
    }

    func testTaskBoxNeitherKeyYieldsEmpty() throws {
        let s = try taskBox(#"{}"#)
        XCTAssertEqual(s.accountIDs, [])
    }

    func testTaskBoxNormalisesOnDecode() throws {
        let s = try taskBox(#"{"accountIDs":[" a1 ","a1","","a2"]}"#)
        XCTAssertEqual(s.accountIDs, ["a1", "a2"])
    }

    func testTaskBoxEncodingWritesAccountIDsAndClearsTheLegacyKey() throws {
        var s = TaskBoxSettings()
        s.accountIDs = ["a1"]
        let text = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertTrue(text.contains("\"accountIDs\""))
        XCTAssertFalse(text.contains("\"accountID\":"), "the singular key must not be written")
    }

    func testTaskBoxRoundTripsEveryField() throws {
        var s = TaskBoxSettings()
        s.organization = "org"
        s.project = "proj"
        s.token = "tok"
        s.accountIDs = ["a1", "a2"]
        s.showLegend = false
        s.showList = false
        s.showProject = true
        s.taskCount = 9
        s.stateMapping = TaskStateMapping(todo: "A", inProgress: "B", testing: "C", done: "D")
        s.query = "[System.Id] > 0"
        s.team = "Team A"
        s.todoColor = RGBA.systemRed
        s.inProgressColor = RGBA.systemCyan
        s.testingColor = RGBA.systemGreen
        s.doneColor = RGBA.systemOrange
        s.otherColor = RGBA.systemPurple

        let decoded = try JSONDecoder().decode(
            TaskBoxSettings.self, from: try JSONEncoder().encode(s)
        )
        XCTAssertEqual(decoded, s, "a hand-written encode must not drop a field")
    }

    // MARK: - PRAzureSettings migration

    private func prAzure(_ json: String) throws -> PRAzureSettings {
        try JSONDecoder().decode(PRAzureSettings.self, from: Data(json.utf8))
    }

    func testPRAzureDecodesTheAccountIDsList() throws {
        let s = try prAzure(#"{"accountIDs":["a1","a2"]}"#)
        XCTAssertEqual(s.accountIDs, ["a1", "a2"])
    }

    func testPRAzureDecodesALegacyAccountIDAsAOneElementList() throws {
        let s = try prAzure(#"{"accountID":"a1"}"#)
        XCTAssertEqual(s.accountIDs, ["a1"])
    }

    func testPRAzureEncodingWritesAccountIDsAndClearsTheLegacyKey() throws {
        var s = PRAzureSettings()
        s.accountIDs = ["a1"]
        let text = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertTrue(text.contains("\"accountIDs\""))
        XCTAssertFalse(text.contains("\"accountID\":"), "the singular key must not be written")
    }

    func testPRAzureRoundTripsEveryField() throws {
        var s = PRAzureSettings()
        s.enabled = true
        s.accountIDs = ["a1"]
        s.organization = "org"
        s.project = "proj"
        s.token = "tok"
        s.showProject = true

        let decoded = try JSONDecoder().decode(
            PRAzureSettings.self, from: try JSONEncoder().encode(s)
        )
        XCTAssertEqual(decoded, s, "a hand-written encode must not drop a field")
    }

    // MARK: - DeckSettings accessors

    func testAccountIDsAccessorReadsAndWritesTheList() {
        var settings = DeckSettings()
        settings.setAccountIDs(["a1", "a2"], for: .taskbox)
        XCTAssertEqual(settings.accountIDs(for: .taskbox), ["a1", "a2"])
        XCTAssertEqual(settings.accountID(for: .taskbox), "a1", "the singular reads the first")
    }

    func testAccountIDsForASingleSlotReadsOneElement() {
        var settings = DeckSettings()
        settings.setAccountID("gh", for: .shipbox)
        XCTAssertEqual(settings.accountIDs(for: .shipbox), ["gh"])
    }

    func testUnsetSlotHasNoAccountIDs() {
        let settings = DeckSettings()
        XCTAssertEqual(settings.accountIDs(for: .taskbox), [])
        XCTAssertNil(settings.accountID(for: .taskbox))
    }
}
