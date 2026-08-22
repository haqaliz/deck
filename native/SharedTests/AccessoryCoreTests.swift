import XCTest

// Accessory battery pure logic. The IOKit read itself lives in the widget
// target (which cannot be compiled into a test bundle), so everything
// decision-making is here and fixture-free — the shapes come from a verified
// probe of a real connected device:
//
//   Name = "MX Master 3S", Current Capacity = 75, Max Capacity = 100,
//   Low Warn Level = 20, Accessory Category = "Mouse"

final class AccessoryCoreTests: XCTestCase {
    private func acc(
        _ name: String,
        _ percent: Double,
        warn: Int = 20,
        category: String = "Mouse"
    ) -> BatteryAccessory {
        BatteryAccessory(id: name, name: name, percent: percent, lowWarnLevel: warn, category: category)
    }

    // MARK: - tier

    /// The device reports its own warn level, so there is no global threshold
    /// setting to disagree with the manufacturer.
    func testNormalAboveTheDeviceWarnLevel() {
        XCTAssertEqual(AccessoryCore.tier(percent: 75, lowWarnLevel: 20), .normal)
        XCTAssertEqual(AccessoryCore.tier(percent: 21, lowWarnLevel: 20), .normal)
    }

    func testWarnAtOrBelowTheDeviceWarnLevel() {
        XCTAssertEqual(AccessoryCore.tier(percent: 20, lowWarnLevel: 20), .warn)
        XCTAssertEqual(AccessoryCore.tier(percent: 11, lowWarnLevel: 20), .warn)
    }

    /// Red at half the warn level — a second step so "getting low" and
    /// "about to die" are not the same colour.
    func testAlarmAtHalfTheWarnLevel() {
        XCTAssertEqual(AccessoryCore.tier(percent: 10, lowWarnLevel: 20), .alarm)
        XCTAssertEqual(AccessoryCore.tier(percent: 3, lowWarnLevel: 20), .alarm)
    }

    /// A device reporting no warn level still gets sane colouring rather than
    /// being permanently green.
    func testMissingWarnLevelFallsBackToTwenty() {
        XCTAssertEqual(AccessoryCore.tier(percent: 15, lowWarnLevel: 0), .warn)
        XCTAssertEqual(AccessoryCore.tier(percent: 5, lowWarnLevel: 0), .alarm)
        XCTAssertEqual(AccessoryCore.tier(percent: 50, lowWarnLevel: 0), .normal)
    }

    // MARK: - symbols

    func testCategoryMapsToSymbol() {
        XCTAssertEqual(AccessoryCore.symbol(for: "Mouse"), "magicmouse")
        XCTAssertEqual(AccessoryCore.symbol(for: "Keyboard"), "keyboard")
        XCTAssertEqual(AccessoryCore.symbol(for: "Headphones"), "headphones")
        XCTAssertEqual(AccessoryCore.symbol(for: "Trackpad"), "trackpad")
    }

    /// Categories are Apple's strings and will grow; an unknown one must not
    /// produce a blank icon slot.
    func testUnknownCategoryGetsAGenericSymbol() {
        XCTAssertFalse(AccessoryCore.symbol(for: "Toaster").isEmpty)
        XCTAssertFalse(AccessoryCore.symbol(for: "").isEmpty)
        XCTAssertEqual(AccessoryCore.symbol(for: "Toaster"), AccessoryCore.symbol(for: ""))
    }

    func testCategoryMatchIsCaseInsensitive() {
        XCTAssertEqual(AccessoryCore.symbol(for: "mouse"), AccessoryCore.symbol(for: "Mouse"))
    }

    // MARK: - ordering

    /// Lowest first, so when the row cap bites it is the dying accessory that
    /// survives, not an alphabetical accident.
    func testSortedPutsLowestBatteryFirst() {
        let sorted = AccessoryCore.sorted([acc("Keyboard", 88), acc("Mouse", 12), acc("Buds", 55)])
        XCTAssertEqual(sorted.map(\.name), ["Mouse", "Buds", "Keyboard"])
    }

    func testSortedIsStableOnTies() {
        let sorted = AccessoryCore.sorted([acc("A", 50), acc("B", 50), acc("C", 50)])
        XCTAssertEqual(sorted.map(\.name), ["A", "B", "C"])
    }

    func testSortedEmptyIsEmpty() {
        XCTAssertTrue(AccessoryCore.sorted([]).isEmpty)
    }

    // MARK: - small-face summary

    func testSummaryReportsCountAndLowest() {
        let s = AccessoryCore.summary([acc("Keyboard", 88), acc("Mouse", 12)])
        XCTAssertEqual(s, "2 ACCESSORIES · LOW 12%")
    }

    func testSummarySingularForOne() {
        XCTAssertEqual(AccessoryCore.summary([acc("Mouse", 75)]), "1 ACCESSORY · 75%")
    }

    /// Nothing connected must render nothing at all, not "0 ACCESSORIES".
    func testSummaryIsNilWhenEmpty() {
        XCTAssertNil(AccessoryCore.summary([]))
    }

    func testSummaryRoundsToWholePercent() {
        XCTAssertEqual(AccessoryCore.summary([acc("Mouse", 74.6)]), "1 ACCESSORY · 75%")
    }
}
