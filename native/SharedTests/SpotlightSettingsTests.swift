import XCTest

final class SpotlightSettingsTests: XCTestCase {
    func testDefaults() {
        let s = SpotlightSettings()
        XCTAssertEqual(s.shortcutKeyCode, 49)       // Space
        XCTAssertEqual(s.shortcutModifiers, 2048)   // Option
        XCTAssertFalse(s.keepInTrayOnly)
        XCTAssertFalse(s.openAtLogin)
        XCTAssertFalse(s.clipEnabled, "clipboard text in a floating panel must be opt-in")
        XCTAssertTrue(s.isEnabled(.port))
        XCTAssertTrue(s.isEnabled(.time))
        XCTAssertTrue(s.isEnabled(.oc))
        XCTAssertFalse(s.isEnabled(.clip))
    }

    func testRoundTrip() throws {
        var s = SpotlightSettings()
        s.shortcutKeyCode = 40
        s.shortcutModifiers = 256 | 512
        s.keepInTrayOnly = true
        s.clipEnabled = true
        let back = try JSONDecoder().decode(SpotlightSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let s = try JSONDecoder().decode(SpotlightSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(s, SpotlightSettings())
    }

    func testHandEditedShortcutFallsBackToTheDefault() throws {
        let bad = Data(#"{"shortcutKeyCode": 9999, "shortcutModifiers": 2048}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SpotlightSettings.self, from: bad).shortcutKeyCode, 49)
    }

    /// A bare key with no modifier would swallow ordinary typing system-wide.
    func testShortcutWithoutAModifierFallsBackToTheDefault() throws {
        let bad = Data(#"{"shortcutKeyCode": 49, "shortcutModifiers": 0}"#.utf8)
        let s = try JSONDecoder().decode(SpotlightSettings.self, from: bad)
        XCTAssertEqual(s.shortcutModifiers, 2048)
        XCTAssertEqual(s.shortcutKeyCode, 49)
    }

    func testUnknownModifierBitsFallBackToTheDefault() throws {
        let bad = Data(#"{"shortcutKeyCode": 49, "shortcutModifiers": 2049}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SpotlightSettings.self, from: bad).shortcutModifiers, 2048)
    }

    /// The regression CLAUDE.md records: a settings file written before this
    /// section existed must keep everything else the user configured.
    func testAnOldSettingsFileKeepsEverythingElse() throws {
        var old = DeckSettings()
        old.agentAtLogin = false
        old.clockbox.mainCityID = "Asia/Tokyo"
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "spotlight")
        let data = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(DeckSettings.self, from: data)
        XCTAssertFalse(loaded.agentAtLogin)
        XCTAssertEqual(loaded.clockbox.mainCityID, "Asia/Tokyo")
        XCTAssertEqual(loaded.spotlight, SpotlightSettings())
    }

    func testSpotlightSectionSurvivesInDeckSettings() throws {
        var s = DeckSettings()
        s.spotlight.keepInTrayOnly = true
        let back = try JSONDecoder().decode(DeckSettings.self, from: JSONEncoder().encode(s))
        XCTAssertTrue(back.spotlight.keepInTrayOnly)
    }
}
