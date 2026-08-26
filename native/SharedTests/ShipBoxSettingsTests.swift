import XCTest

// ShipBox grew from one `repo` string to a list plus a mode (PRD §4).
//
// The migration matters more than the new keys: `DeckSettings.load()` falls
// back to `DeckSettings()` on any decode error, so a settings file written by
// v1.27 that fails to decode here doesn't surface as an error — it silently
// resets every widget's settings, including three API tokens. These tests pin
// the read path for both shapes.

private func decode<T: Decodable>(_ json: String, as _: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func roundTrip<T: Codable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

final class ShipBoxSettingsMigrationTests: XCTestCase {
    func testLegacySingleRepoBecomesAStaticListOfOne() throws {
        let s = try decode(#"{"repo":"haqaliz/deck","token":"t"}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repos, ["haqaliz/deck"])
        XCTAssertEqual(s.token, "t")
    }

    /// The mode has to follow the migration, not just the list. A v1.27 user
    /// configured exactly one repo on purpose; landing them in dynamic mode
    /// would silently replace it with whatever they pushed to most recently.
    func testLegacySingleRepoPinsStaticMode() throws {
        let s = try decode(#"{"repo":"haqaliz/deck"}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repoMode, .staticList)
    }

    func testLegacyEmptyRepoStaysDynamic() throws {
        let s = try decode(#"{"repo":"","token":"t"}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repoMode, .dynamic)
        XCTAssertEqual(s.repos, [])
    }

    func testAFileWithNeitherKeyDefaultsToDynamic() throws {
        let s = try decode(#"{}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repoMode, .dynamic)
        XCTAssertEqual(s.repos, [])
        XCTAssertEqual(s.maxRepoCount, 3)
    }

    func testTheNewShapeWinsOverTheLegacyKey() throws {
        let s = try decode(#"{"repo":"old/one","repos":["new/one"],"repoMode":"static"}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repos, ["new/one"])
    }

    /// A file migrates once and then stays clean — same rule MarketBox applied
    /// when it retired `symbols`.
    func testEncodingDropsTheLegacyKey() throws {
        let s = try decode(#"{"repo":"haqaliz/deck"}"#, as: ShipBoxSettings.self)
        let json = try roundTrip(s)
        XCTAssertNil(json["repo"], "the legacy key is read on the way in, never written back")
        XCTAssertEqual(json["repos"] as? [String], ["haqaliz/deck"])
        XCTAssertEqual(json["repoMode"] as? String, "static")
    }
}

final class ShipBoxSettingsNormalizationTests: XCTestCase {
    func testReposAreTrimmedAndEmptiesDropped() throws {
        let s = try decode(#"{"repos":["  a/b  ","","c/d"]}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repos, ["a/b", "c/d"])
    }

    /// GitHub treats owner/repo case-insensitively, so `A/B` and `a/b` are one
    /// repo — fetching both would double the cost and duplicate every row.
    func testReposAreDedupedCaseInsensitivelyKeepingTheFirstSpelling() throws {
        let s = try decode(#"{"repos":["Haqaliz/Deck","haqaliz/deck","x/y"]}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repos, ["Haqaliz/Deck", "x/y"])
    }

    func testReposAreCappedAtFive() throws {
        let s = try decode(#"{"repos":["a/1","a/2","a/3","a/4","a/5","a/6","a/7"]}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repos.count, ShipBoxSettings.maxRepoCount)
        XCTAssertEqual(s.repos.last, "a/5")
    }

    func testMaxRepoCountIsClampedToTheSameCeiling() throws {
        XCTAssertEqual(try decode(#"{"maxRepoCount":99}"#, as: ShipBoxSettings.self).maxRepoCount, 5)
        XCTAssertEqual(try decode(#"{"maxRepoCount":0}"#, as: ShipBoxSettings.self).maxRepoCount, 1)
    }

    /// Written by a newer build than this one; an unreadable mode must not
    /// throw, because throwing here resets every other widget's settings.
    func testAnUnknownModeFallsBackToDynamic() throws {
        let s = try decode(#"{"repoMode":"telepathy"}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repoMode, .dynamic)
    }

    func testExistingKeysAreUntouched() throws {
        let s = try decode(#"{"runCount":7,"showList":false}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.runCount, 7)
        XCTAssertFalse(s.showList)
        XCTAssertEqual(s.queuedColor, RGBA.systemOrange)
        XCTAssertEqual(s.failureColor, RGBA.systemRed)
    }
}
