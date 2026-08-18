import XCTest

// Battery formatters + math moved to Shared/BatteryCore.swift (pure core —
// the IOKit loader stays in DeckWidgets, LiveBoxDiskCore precedent).

final class BatteryFormattersTests: XCTestCase {
    func testFormatPercent() {
        XCTAssertEqual(BatteryFormatters.formatPercent(71), "71%")
        XCTAssertEqual(BatteryFormatters.formatPercent(0), "0%")
        XCTAssertEqual(BatteryFormatters.formatPercent(100), "100%")
    }

    func testFormatTime() {
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: nil), "—")
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 0), "0m")
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 45), "45m")
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 60), "1h 0m")
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 395), "6h 35m")
        XCTAssertEqual(BatteryFormatters.formatTime(minutes: 600), "10h 0m")
    }

    func testFormatStateChargedOnACIsACPower() {
        XCTAssertEqual(
            BatteryFormatters.formatState(isCharging: true, isCharged: true, powerSource: .ac),
            "AC Power"
        )
        XCTAssertEqual(
            BatteryFormatters.formatState(isCharging: false, isCharged: true, powerSource: .ac),
            "AC Power"
        )
    }

    func testFormatStateFull() {
        XCTAssertEqual(
            BatteryFormatters.formatState(isCharging: false, isCharged: true, powerSource: .battery),
            "Full"
        )
    }

    func testFormatStateCharging() {
        XCTAssertEqual(
            BatteryFormatters.formatState(isCharging: true, isCharged: false, powerSource: .battery),
            "Charging"
        )
        XCTAssertEqual(
            BatteryFormatters.formatState(isCharging: true, isCharged: false, powerSource: .ac),
            "Charging"
        )
    }

    func testFormatStateDischarging() {
        XCTAssertEqual(
            BatteryFormatters.formatState(isCharging: false, isCharged: false, powerSource: .battery),
            "Discharging"
        )
        XCTAssertEqual(
            BatteryFormatters.formatState(isCharging: false, isCharged: false, powerSource: .ac),
            "Discharging"
        )
    }
}

final class BatteryMathTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(BatteryMath.percent(current: 50, maxCapacity: 100), 50)
        XCTAssertEqual(BatteryMath.percent(current: 0, maxCapacity: 100), 0)
    }

    func testPercentClampsToRange() {
        XCTAssertEqual(BatteryMath.percent(current: 150, maxCapacity: 100), 100)
        XCTAssertEqual(BatteryMath.percent(current: -5, maxCapacity: 100), 0)
    }

    func testPercentNilWhenMaxCapacityInvalid() {
        XCTAssertNil(BatteryMath.percent(current: 100, maxCapacity: 0))
        XCTAssertNil(BatteryMath.percent(current: 100, maxCapacity: -1))
    }

    func testTimeMinutes() {
        XCTAssertNil(BatteryMath.timeMinutes(seconds: 0))
        XCTAssertNil(BatteryMath.timeMinutes(seconds: -5))
        XCTAssertEqual(BatteryMath.timeMinutes(seconds: 60), 1)
        XCTAssertEqual(BatteryMath.timeMinutes(seconds: 90), 2)
        XCTAssertEqual(BatteryMath.timeMinutes(seconds: 30), 1)
        XCTAssertEqual(BatteryMath.timeMinutes(seconds: 1), 0)
    }
}
