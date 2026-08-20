import XCTest

// Thermal pressure level mapping for the LiveBox thermal row
// (plan_20260820.md Phase 1). Takes a raw Int rather than a
// ProcessInfo.ThermalState so the mapping is testable without fabricating a
// ProcessInfo; the widget passes thermalState.rawValue.

final class LiveBoxThermalCoreTests: XCTestCase {
    func testLevelMapsKnownRawValues() {
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: 0), .nominal)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: 1), .fair)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: 2), .serious)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: 3), .critical)
    }

    /// A state beyond critical must not silently degrade to an untinted level.
    func testLevelClampsOutOfRangeRawValues() {
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: 4), .critical)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: 99), .critical)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: -1), .nominal)
    }

    /// Pins our Int contract to Foundation's actual raw values, so a change in
    /// ProcessInfo.ThermalState can't silently shift every level by one.
    func testLevelMatchesFoundationRawValues() {
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: ProcessInfo.ThermalState.nominal.rawValue), .nominal)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: ProcessInfo.ThermalState.fair.rawValue), .fair)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: ProcessInfo.ThermalState.serious.rawValue), .serious)
        XCTAssertEqual(LiveBoxThermalCore.level(rawValue: ProcessInfo.ThermalState.critical.rawValue), .critical)
    }

    func testLabelsAreUppercaseWords() {
        XCTAssertEqual(LiveBoxThermalCore.label(.nominal), "NOMINAL")
        XCTAssertEqual(LiveBoxThermalCore.label(.fair), "FAIR")
        XCTAssertEqual(LiveBoxThermalCore.label(.serious), "SERIOUS")
        XCTAssertEqual(LiveBoxThermalCore.label(.critical), "CRITICAL")
    }

    /// Nominal and fair are never tinted — the "idle values are never tinted"
    /// rule from netbox-threshold-coloring (prd.md §2).
    func testTierTintsOnlySeriousAndCritical() {
        XCTAssertEqual(LiveBoxThermalCore.tier(.nominal), .normal)
        XCTAssertEqual(LiveBoxThermalCore.tier(.fair), .normal)
        XCTAssertEqual(LiveBoxThermalCore.tier(.serious), .warn)
        XCTAssertEqual(LiveBoxThermalCore.tier(.critical), .alarm)
    }
}
