import XCTest
@testable import BatBoxCore

final class FormatterTests: XCTestCase {
    func testFormatPercent() {
        XCTAssertEqual(BatteryFormatters.formatPercent(71), "71%")
        XCTAssertEqual(BatteryFormatters.formatPercent(0), "0%")
        XCTAssertEqual(BatteryFormatters.formatPercent(100), "100%")
    }

    func testFormatTimeHoursAndMinutes() {
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 394), "6h 34m")
    }

    func testFormatTimeMinutesOnly() {
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 45), "45m")
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 59), "59m")
    }

    func testFormatTimeHourBoundary() {
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 60), "1h 0m")
    }

    func testFormatTimeNilIsDash() {
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: nil), "—")
    }

    func testFormatCycles() {
        XCTAssertEqual(BatteryFormatters.formatCycles(107), "107")
        XCTAssertEqual(BatteryFormatters.formatCycles(0), "0")
    }

    func testFormatCyclesNilIsDash() {
        XCTAssertEqual(BatteryFormatters.formatCycles(nil), "—")
    }

    func testFormatStateDischarging() {
        XCTAssertEqual(BatteryFormatters.formatState(isCharging: false, isCharged: false, powerSource: .battery), "Discharging")
    }

    func testFormatStateCharging() {
        XCTAssertEqual(BatteryFormatters.formatState(isCharging: true, isCharged: false, powerSource: .battery), "Charging")
    }

    func testFormatStateFull() {
        XCTAssertEqual(BatteryFormatters.formatState(isCharging: false, isCharged: true, powerSource: .battery), "Full")
    }

    func testFormatStateAcPower() {
        XCTAssertEqual(BatteryFormatters.formatState(isCharging: false, isCharged: true, powerSource: .ac), "AC Power")
    }
}
