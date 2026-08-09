import XCTest
@testable import BatBoxCore

final class IOregParserTests: XCTestCase {
    func testParseCycleCount() {
        let out = "\"CycleCount\" = 107\n\"MaxCapacity\" = 100\n"
        XCTAssertEqual(IOregParser.cycleCount(from: out), 107)
    }

    func testParseCycleCountZero() {
        let out = "\"CycleCount\" = 0\n"
        XCTAssertEqual(IOregParser.cycleCount(from: out), 0)
    }

    func testParseMissingCycleCountIsNil() {
        XCTAssertNil(IOregParser.cycleCount(from: "\"MaxCapacity\" = 100\n"))
    }

    func testParseGarbageIsNil() {
        XCTAssertNil(IOregParser.cycleCount(from: "not ioreg output"))
        XCTAssertNil(IOregParser.cycleCount(from: "\"CycleCount\" = abc\n"))
        XCTAssertNil(IOregParser.cycleCount(from: ""))
    }
}
