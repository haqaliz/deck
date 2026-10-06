import XCTest

// The three Query presets and the team literal. A preset is text the user
// pastes into the draft, so validation is the contract: whatever a preset
// produces must be sendable as-is, and "Assigned to me" must be the built-in
// filter exactly (PRD §10.3), so the two can never drift apart.

final class WiqlPresetTests: XCTestCase {
    private let team = WiqlTeamContext(project: "ForesightManifold", team: "ForesightManifold Team")

    // MARK: titles

    func testEveryPresetHasATitle() {
        for preset in WiqlPreset.allCases {
            XCTAssertFalse(preset.title.isEmpty, "\(preset)")
        }
    }

    func testTitlesAreDistinct() {
        XCTAssertEqual(Set(WiqlPreset.allCases.map(\.title)).count, WiqlPreset.allCases.count)
    }

    // MARK: validity

    func testEveryPresetValidatesWithoutATeam() {
        for preset in WiqlPreset.allCases {
            XCTAssertNil(WiqlClause.validate(preset.condition(team: nil)), "\(preset)")
        }
    }

    func testEveryPresetValidatesWithATeam() {
        for preset in WiqlPreset.allCases {
            XCTAssertNil(WiqlClause.validate(preset.condition(team: team)), "\(preset)")
        }
    }

    // MARK: assigned to me is the built-in

    func testAssignedToMeIsTheBuiltInConditionExactly() {
        XCTAssertEqual(WiqlPreset.assignedToMe.condition(team: nil), WiqlClause.builtInCondition)
    }

    func testTheBuiltInConditionIsAssignedToMeOverTheOpenStates() {
        XCTAssertEqual(
            WiqlClause.builtInCondition,
            "[System.AssignedTo] = @Me AND " + WiqlClause.openStates
        )
    }

    // MARK: created by me

    func testCreatedByMe() {
        XCTAssertEqual(
            WiqlPreset.createdByMe.condition(team: nil),
            "[System.CreatedBy] = @Me AND " + WiqlClause.openStates
        )
    }

    // MARK: current sprint

    func testCurrentSprintWithoutATeam() {
        XCTAssertEqual(
            WiqlPreset.currentSprint.condition(team: nil),
            "[System.IterationPath] = @CurrentIteration AND " + WiqlClause.openStates
        )
    }

    func testCurrentSprintWithATeamCarriesTheLiteral() {
        // Probe P17/P21: name, brackets, spaces intact.
        XCTAssertEqual(
            WiqlPreset.currentSprint.condition(team: team),
            "[System.IterationPath] = @CurrentIteration('[ForesightManifold]\\ForesightManifold Team')"
                + " AND " + WiqlClause.openStates
        )
    }

    func testTheTeamOnlyTouchesTheCurrentSprintPreset() {
        XCTAssertEqual(WiqlPreset.assignedToMe.condition(team: team), WiqlClause.builtInCondition)
        XCTAssertEqual(
            WiqlPreset.createdByMe.condition(team: team),
            "[System.CreatedBy] = @Me AND " + WiqlClause.openStates
        )
    }

    // MARK: the literal

    func testLiteralKeepsTheBracketsAndTheBackslash() {
        XCTAssertEqual(team.literal, "[ForesightManifold]\\ForesightManifold Team")
    }

    func testLiteralEscapesAQuoteInsideAName() {
        // WIQL's literal escape, like `''` in probe P14.
        let context = WiqlTeamContext(project: "P", team: "Ali's Team")
        XCTAssertEqual(context.literal, "[P]\\Ali''s Team")
    }

    func testATeamNameWithAQuoteStillValidates() {
        let context = WiqlTeamContext(project: "P", team: "Ali's Team")
        XCTAssertNil(WiqlClause.validate(WiqlPreset.currentSprint.condition(team: context)))
    }

    // MARK: composition

    func testEveryPresetComposesWithTheProjectClauseOutside() {
        for preset in WiqlPreset.allCases {
            for context in [nil, team] as [WiqlTeamContext?] {
                let condition = preset.condition(team: context)
                let composed = WiqlClause.query(for: condition)
                XCTAssertTrue(
                    composed.hasPrefix("SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND ("),
                    "\(preset)"
                )
                XCTAssertTrue(composed.hasSuffix(") ORDER BY [System.ChangedDate] DESC"), "\(preset)")
                XCTAssertTrue(composed.contains(condition), "\(preset)")
            }
        }
    }
}
