import XCTest

// The user's TaskBox condition. Deck owns everything around it, and wrapping
// it in parentheses is not enough to keep it there: an unbalanced `)` escapes
// the wrapper and the project clause with it (probe P9: 7559 items from the
// whole organization instead of one project's). These pin what may be sent.

final class WiqlClauseValidationTests: XCTestCase {
    private func problem(_ condition: String) -> WiqlClause.Problem? {
        WiqlClause.validate(condition)
    }

    // MARK: accepted

    func testTheBuiltInConditionIsValid() {
        XCTAssertNil(problem(WiqlClause.builtInCondition))
    }

    func testEmptyIsValidAndMeansTheBuiltIn() {
        XCTAssertNil(problem(""))
        XCTAssertNil(problem("   \n "))
    }

    func testAParenthesisInsideALiteralIsNotStructure() {
        // Probe P13: legitimate, 200 with 4 rows.
        XCTAssertNil(problem("[System.Title] CONTAINS 'a)'"))
        XCTAssertNil(problem("[System.Title] CONTAINS '(('"))
    }

    func testADoubledQuoteIsAnEscapeNotAnEnd() {
        // Probe P14: `''` is WIQL's quote escape.
        XCTAssertNil(problem("[System.Title] CONTAINS 'it''s (open'"))
    }

    func testMacrosAndArithmeticAreFine() {
        // Probe P15.
        XCTAssertNil(problem("[System.CreatedBy] = @Me AND [System.ChangedDate] >= @Today - 30"))
    }

    func testReservedWordsInsideLiteralsOrFieldNamesAreFine() {
        XCTAssertNil(problem("[System.Title] CONTAINS 'order by'"))
        XCTAssertNil(problem("[System.Title] CONTAINS 'select from'"))
        XCTAssertNil(problem("[Custom.FromDate] > @Today"))
        XCTAssertNil(problem("[Custom.Mode] = 'x'"))
    }

    func testReservedWordsAsPartOfALongerWordAreFine() {
        XCTAssertNil(problem("[System.Title] = 'x' AND [System.Tags] CONTAINS 'y' ORDERLY"))
            // Not valid WIQL, but not ours to reject: the server will say so.
    }

    func testNestedBalancedParenthesesAreFine() {
        XCTAssertNil(problem("([System.State] = 'Active' OR ([System.State] = 'New' AND [System.Id] > 1))"))
    }

    // MARK: rejected

    func testAClosingParenthesisThatEscapesTheWrapperIsRejected() {
        // Probe P9: balanced overall, but it dips below zero and closes our `(`.
        XCTAssertEqual(
            problem("[System.State] = 'Active') OR ([System.Id] > 0"),
            .unbalancedParentheses
        )
    }

    func testAnUnclosedParenthesisIsRejected() {
        XCTAssertEqual(problem("([System.State] = 'Active'"), .unbalancedParentheses)
    }

    func testAnUnterminatedLiteralIsRejected() {
        XCTAssertEqual(problem("[System.State] = 'Active"), .unterminatedLiteral)
    }

    func testAnUnterminatedFieldIsRejected() {
        XCTAssertEqual(problem("[System.State = 'Active'"), .unterminatedField)
    }

    func testOrderByIsRejectedBecauseDeckAddsIt() {
        // Probe P12: the server would answer 400 anyway; say why first.
        XCTAssertEqual(problem("[System.Id] > 0 order by [System.Id]"), .reservedKeyword("ORDER BY"))
    }

    func testTheOtherReservedWordsAreRejected() {
        XCTAssertEqual(problem("[System.Id] > 0 ASOF '2026-01-01'"), .reservedKeyword("ASOF"))
        XCTAssertEqual(problem("[System.Id] > 0 MODE (MayContain)"), .reservedKeyword("MODE"))
        XCTAssertEqual(problem("SELECT [System.Id]"), .reservedKeyword("SELECT"))
        XCTAssertEqual(problem("[System.Id] IN (SELECT x FROM y)"), .reservedKeyword("SELECT"))
        XCTAssertEqual(problem("[System.Id] > 0 from WorkItems"), .reservedKeyword("FROM"))
    }

    func testAnOverlongConditionIsRejected() {
        let long = String(repeating: "a", count: WiqlClause.maxLength + 1)
        XCTAssertEqual(problem(long), .tooLong)
        XCTAssertNil(problem(String(repeating: "a", count: WiqlClause.maxLength)))
    }

    func testEveryProblemHasACaption() {
        let all: [WiqlClause.Problem] = [
            .unbalancedParentheses, .unterminatedLiteral, .unterminatedField,
            .reservedKeyword("ORDER BY"), .tooLong,
        ]
        for problem in all { XCTAssertFalse(problem.message.isEmpty, "\(problem)") }
        XCTAssertTrue(WiqlClause.Problem.reservedKeyword("ORDER BY").message.contains("ORDER BY"))
    }
}

final class WiqlClauseCompositionTests: XCTestCase {
    func testTheProjectClauseAndOrderStayOutsideTheCondition() {
        XCTAssertEqual(
            WiqlClause.query(for: "[System.State] = 'Active'"),
            "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
                + "AND ([System.State] = 'Active') ORDER BY [System.ChangedDate] DESC"
        )
    }

    func testAnEmptyConditionComposesTheBuiltInQuery() {
        let expected = WiqlClause.query(for: WiqlClause.builtInCondition)
        XCTAssertEqual(WiqlClause.query(for: ""), expected)
        XCTAssertEqual(WiqlClause.query(for: "  \n"), expected)
    }

    func testTheBuiltInConditionIsTodaysFilter() {
        // Unchanged from the fixed query it replaces.
        XCTAssertEqual(
            WiqlClause.builtInCondition,
            "[System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed', 'Removed', 'Done')"
        )
    }

    func testTheConditionIsTrimmed() {
        XCTAssertEqual(
            WiqlClause.query(for: "  [System.Id] > 0 \n"),
            WiqlClause.query(for: "[System.Id] > 0")
        )
    }

    func testCustomMeansANonBlankCondition() {
        XCTAssertFalse(WiqlClause.isCustom(""))
        XCTAssertFalse(WiqlClause.isCustom(" \n\t"))
        XCTAssertTrue(WiqlClause.isCustom("[System.Id] > 0"))
    }
}
