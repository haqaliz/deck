import XCTest

// Ported from the ShipBoxCore scratch package (f0c94c4) against the merged
// ShipBoxSnapshot/ShipStatus/RunParser/RunFormatting in Shared.

final class StatusMappingTests: XCTestCase {
    func testQueuedStates() {
        for status in ["queued", "waiting", "requested", "pending"] {
            XCTAssertEqual(ShipStatus.map(status: status, conclusion: nil), .queued, "status \(status)")
        }
    }

    func testRunning() {
        XCTAssertEqual(ShipStatus.map(status: "in_progress", conclusion: nil), .running)
    }

    func testCompletedSuccess() {
        XCTAssertEqual(ShipStatus.map(status: "completed", conclusion: "success"), .success)
    }

    func testCompletedFailures() {
        for conclusion in ["failure", "timed_out", "action_required", "stale"] {
            XCTAssertEqual(ShipStatus.map(status: "completed", conclusion: conclusion), .failure, "conclusion \(conclusion)")
        }
    }

    func testCompletedNeutral() {
        for conclusion in ["cancelled", "skipped", "neutral"] {
            XCTAssertEqual(ShipStatus.map(status: "completed", conclusion: conclusion), .neutral, "conclusion \(conclusion)")
        }
    }

    func testCompletedNullConclusion() {
        XCTAssertEqual(ShipStatus.map(status: "completed", conclusion: nil), .neutral)
    }

    func testUnknownStatusAndConclusionFallToNeutral() {
        XCTAssertEqual(ShipStatus.map(status: "weird", conclusion: "success"), .neutral)
        XCTAssertEqual(ShipStatus.map(status: "completed", conclusion: "bogus"), .neutral)
    }
}

final class RunParserTests: XCTestCase {
    func testParsesMixedRuns() throws {
        let fixture = """
        {
          "total_count": 2,
          "workflow_runs": [
            {
              "id": 123,
              "name": "CI",
              "run_number": 42,
              "head_branch": "main",
              "event": "push",
              "status": "completed",
              "conclusion": "success",
              "created_at": "2026-08-14T10:00:00Z",
              "updated_at": "2026-08-14T10:03:12Z",
              "html_url": "https://github.com/owner/repo/actions/runs/123"
            },
            {
              "id": 124,
              "name": "Deploy",
              "run_number": 7,
              "head_branch": "feat/x",
              "event": "push",
              "status": "in_progress",
              "conclusion": null,
              "created_at": "2026-08-14T10:05:00Z",
              "updated_at": "2026-08-14T10:05:00Z",
              "html_url": "https://github.com/owner/repo/actions/runs/124"
            }
          ]
        }
        """
        let parsed = RunParser.parse(Data(fixture.utf8))
        XCTAssertEqual(parsed?.totalCount, 2)
        let runs = try XCTUnwrap(parsed?.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].name, "CI")
        XCTAssertEqual(runs[0].runNumber, 42)
        XCTAssertEqual(runs[0].branch, "main")
        XCTAssertEqual(runs[0].status, .success)
        XCTAssertEqual(runs[0].htmlURL, "https://github.com/owner/repo/actions/runs/123")
        XCTAssertEqual(runs[1].status, .running)
    }

    func testEmptyRuns() {
        let fixture = #"{"total_count": 0, "workflow_runs": []}"#
        let parsed = RunParser.parse(Data(fixture.utf8))
        XCTAssertEqual(parsed?.totalCount, 0)
        XCTAssertEqual(parsed?.runs.count, 0)
    }

    func testMalformedPayloadReturnsNil() {
        XCTAssertNil(RunParser.parse(Data("not json".utf8)))
        XCTAssertNil(RunParser.parse(Data(#"{"total_count": 1}"#.utf8)))
    }

    func testUnknownFieldsTolerated() {
        let fixture = """
        {
          "total_count": 1,
          "workflow_runs": [
            {
              "id": 1,
              "name": "CI",
              "run_number": 1,
              "head_branch": "main",
              "status": "completed",
              "conclusion": "failure"
            }
          ]
        }
        """
        let runs = RunParser.parse(Data(fixture.utf8))?.runs ?? []
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].htmlURL, "")
        XCTAssertEqual(runs[0].createdAt, Date(timeIntervalSince1970: 0))
    }
}

final class RunFormattingTests: XCTestCase {
    func testDurationMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(192)
        XCTAssertEqual(RunFormatting.duration(from: start, to: end), "3m12s")
    }

    func testDurationUnderOneMinute() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(45)
        XCTAssertEqual(RunFormatting.duration(from: start, to: end), "0m45s")
    }

    func testDurationOverOneHour() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(3_864)
        XCTAssertEqual(RunFormatting.duration(from: start, to: end), "1h04m")
    }

    func testDurationZero() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RunFormatting.duration(from: start, to: start), "0m0s")
    }

    func testDetailTextForCompletedRun() {
        let run = ShipRun(
            name: "CI", runNumber: 42, branch: "main", status: .success,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_192),
            htmlURL: ""
        )
        XCTAssertEqual(RunFormatting.detail(for: run), "main · 3m12s")
    }

    func testDetailTextForRunningAndQueued() {
        let queued = ShipRun(name: "CI", runNumber: 1, branch: "main", status: .queued, createdAt: Date(), updatedAt: Date(), htmlURL: "")
        let running = ShipRun(name: "CI", runNumber: 2, branch: "feat/x", status: .running, createdAt: Date(), updatedAt: Date(), htmlURL: "")
        XCTAssertEqual(RunFormatting.detail(for: queued), "main · QUEUED")
        XCTAssertEqual(RunFormatting.detail(for: running), "feat/x · RUNNING")
    }

    func testTotalsLine() {
        let runs = [
            ShipRun(name: "a", runNumber: 1, branch: "b", status: .success, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
            ShipRun(name: "a", runNumber: 2, branch: "b", status: .failure, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
            ShipRun(name: "a", runNumber: 3, branch: "b", status: .failure, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
            ShipRun(name: "a", runNumber: 4, branch: "b", status: .running, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
            ShipRun(name: "a", runNumber: 5, branch: "b", status: .neutral, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
        ]
        XCTAssertEqual(RunFormatting.totalsLine(for: runs), "2 fail · 1 pass · 1 run")
    }

    func testTotalsLineAllGreen() {
        let runs = [
            ShipRun(name: "a", runNumber: 1, branch: "b", status: .success, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
            ShipRun(name: "a", runNumber: 2, branch: "b", status: .success, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
        ]
        XCTAssertEqual(RunFormatting.totalsLine(for: runs), "2 pass")
    }

    func testTotalsLineEmpty() {
        XCTAssertEqual(RunFormatting.totalsLine(for: []), "")
    }

    func testTotalsCounts() {
        let runs = [
            ShipRun(name: "a", runNumber: 1, branch: "b", status: .success, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
            ShipRun(name: "a", runNumber: 2, branch: "b", status: .failure, createdAt: Date(), updatedAt: Date(), htmlURL: ""),
        ]
        let totals = RunFormatting.totals(for: runs)
        XCTAssertEqual(totals.success, 1)
        XCTAssertEqual(totals.failure, 1)
        XCTAssertEqual(totals.running, 0)
        XCTAssertEqual(totals.queued, 0)
        XCTAssertEqual(totals.neutral, 0)
    }
}
