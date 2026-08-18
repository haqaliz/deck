import XCTest

// PsParser: right-anchored ps row parsing (PRD §3.2). %cpu/%mem are the last
// two whitespace tokens because comm= is a full path that may contain spaces.

final class PsParserTests: XCTestCase {
    func testParsesRowsIntoTopProcesses() {
        let raw = """
        /usr/libexec/kernel_task 0.5 0.1
        /Applications/Safari.app/Contents/MacOS/Safari 12.0 3.4
        """
        XCTAssertEqual(PsParser.parse(raw), [
            TopProcess(name: "Safari", cpuPercent: 12.0, memPercent: 3.4),
            TopProcess(name: "kernel_task", cpuPercent: 0.5, memPercent: 0.1),
        ])
    }

    func testPathWithSpacesParsesRightAnchored() {
        let raw = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome 1.5 2.0"
        XCTAssertEqual(PsParser.parse(raw), [
            TopProcess(name: "Google Chrome", cpuPercent: 1.5, memPercent: 2.0),
        ])
    }

    func testMultiSpaceColumns() {
        let raw = "kernel_task      0.5      0.1"
        XCTAssertEqual(PsParser.parse(raw), [
            TopProcess(name: "kernel_task", cpuPercent: 0.5, memPercent: 0.1),
        ])
    }

    func testSortsByCpuDescending() {
        let raw = "a 1.0 0.1\nb 3.0 0.2\nc 2.0 0.3"
        XCTAssertEqual(PsParser.parse(raw), [
            TopProcess(name: "b", cpuPercent: 3.0, memPercent: 0.2),
            TopProcess(name: "c", cpuPercent: 2.0, memPercent: 0.3),
            TopProcess(name: "a", cpuPercent: 1.0, memPercent: 0.1),
        ])
    }

    func testUnparseableCpuOrMemBecomesZero() {
        let raw = "weird x 1.0\nweird2 1.0 y"
        let result = PsParser.parse(raw)
        XCTAssertEqual(result, [
            TopProcess(name: "weird2", cpuPercent: 1.0, memPercent: 0),
            TopProcess(name: "weird", cpuPercent: 0, memPercent: 1.0),
        ])
    }

    func testSkipsRowsWithFewerThanThreeTokens() {
        XCTAssertEqual(PsParser.parse("onlytwo 1.0\nsingle\n"), [])
    }

    func testEmptyInputYieldsNoRows() {
        XCTAssertEqual(PsParser.parse(""), [])
        XCTAssertEqual(PsParser.parse("\n\n"), [])
    }

    func testJoinedPathPreservesInternalSpaces() {
        let raw = "/a  b 1 2"
        XCTAssertEqual(PsParser.parse(raw), [
            TopProcess(name: "a b", cpuPercent: 1, memPercent: 2),
        ])
    }
}

final class ProcessMaxAgeTests: XCTestCase {
    func testDefaultFifteenSecondIntervalGivesThirtySecondWindow() {
        XCTAssertEqual(ProcessSnapshot.maxAgeSeconds(for: 15), 30)
    }

    func testThirtySecondIntervalDoublesWindow() {
        XCTAssertEqual(ProcessSnapshot.maxAgeSeconds(for: 30), 60)
    }

    func testSixtySecondIntervalGivesTwoMinuteWindow() {
        XCTAssertEqual(ProcessSnapshot.maxAgeSeconds(for: 60), 120)
    }

    func testFastIntervalsFloorAtThirtySeconds() {
        XCTAssertEqual(ProcessSnapshot.maxAgeSeconds(for: 5), 30)
        XCTAssertEqual(ProcessSnapshot.maxAgeSeconds(for: 10), 30)
    }

    func testGuardIsMonotonicWithInterval() {
        var previous = 0.0
        for interval in 1...60 {
            let next = ProcessSnapshot.maxAgeSeconds(for: interval)
            XCTAssertGreaterThanOrEqual(next, previous)
            previous = next
        }
    }
}
