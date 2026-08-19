import XCTest

// Ported from the SettingsCore scratch package (8ca082b) and extended to all
// nine settings structs: tolerant decode keeps defaults on missing keys.

private func decode<T: Decodable>(_ json: String, as _: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

final class OpenBoxSettingsDecodeTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let s = try decode(#"{"token":"abc","refreshInterval":30,"showChart":false}"#, as: OpenBoxSettings.self)
        XCTAssertEqual(s.token, "abc")
        XCTAssertNil(s.serverURL)
        XCTAssertEqual(s.refreshInterval, 30)
        XCTAssertFalse(s.showChart)
        XCTAssertTrue(s.showModels)
        XCTAssertEqual(s.inputColor, RGBA(.cyan))
        XCTAssertEqual(s.outputColor, RGBA(.green))
        XCTAssertEqual(s.costColor, RGBA(.orange))
    }

    func testSessionKeysDefaultOffWithCountThree() throws {
        let s = try decode(#"{}"#, as: OpenBoxSettings.self)
        XCTAssertFalse(s.showSessions)
        XCTAssertFalse(s.showTools)
        XCTAssertEqual(s.sessionCount, 3)
    }

    func testSessionKeysDecodeExplicitValues() throws {
        let s = try decode(#"{"showSessions":true,"sessionCount":5}"#, as: OpenBoxSettings.self)
        XCTAssertTrue(s.showSessions)
        XCTAssertEqual(s.sessionCount, 5)
    }

    func testFullFixtureDecodesExactValues() throws {
        let json = """
        {"token":"t","serverURL":"http://h:4096","refreshInterval":5,"showChart":false,"showCostChart":true,"showModels":false,"showTools":false,"toolCount":7,"modelCount":2,
         "inputColor":{"red":0.1,"green":0.2,"blue":0.3,"alpha":0.4},
         "outputColor":{"red":0.5,"green":0.6,"blue":0.7,"alpha":0.8},
         "costColor":{"red":0.9,"green":0.8,"blue":0.7,"alpha":0.6}}
        """
        let s = try decode(json, as: OpenBoxSettings.self)
        var expected = OpenBoxSettings()
        expected.token = "t"
        expected.serverURL = "http://h:4096"
        expected.refreshInterval = 5
        expected.showChart = false
        expected.showCostChart = true
        expected.showModels = false
        expected.showTools = false
        expected.toolCount = 7
        expected.modelCount = 2
        expected.inputColor = RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        expected.outputColor = RGBA(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8)
        expected.costColor = RGBA(red: 0.9, green: 0.8, blue: 0.7, alpha: 0.6)
        XCTAssertEqual(s, expected)
    }

    func testExplicitNullServerURLDecodesNil() throws {
        let s = try decode(#"{"serverURL":null}"#, as: OpenBoxSettings.self)
        XCTAssertNil(s.serverURL)
    }

    func testTypeMismatchStillThrows() {
        XCTAssertThrowsError(try decode(#"{"showChart":"yes"}"#, as: OpenBoxSettings.self))
    }

    func testUnknownKeysAreIgnored() throws {
        let s = try decode(#"{"bogus":123,"showChart":false}"#, as: OpenBoxSettings.self)
        XCTAssertFalse(s.showChart)
        XCTAssertEqual(s.refreshInterval, 60)
    }

    func testEncodeRoundTripPreservesValues() throws {
        var s = OpenBoxSettings()
        s.token = "t"
        s.serverURL = "http://h:4096"
        s.refreshInterval = 5
        s.showChart = false
        s.showCostChart = true
        s.showModels = true
        s.showTools = false
        s.toolCount = 2
        s.modelCount = 1
        s.inputColor = RGBA(red: 0.1, green: 0.2, blue: 0.3)
        s.outputColor = RGBA(.green)
        s.costColor = RGBA(.orange)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(OpenBoxSettings.self, from: data)
        XCTAssertEqual(back, s)
    }
}

final class NetBoxSettingsDecodeTests: XCTestCase {
    func testEmptyFixtureDecodesAllDefaults() throws {
        let s = try decode(#"{}"#, as: NetBoxSettings.self)
        XCTAssertEqual(s, NetBoxSettings())
    }

    func testPartialFixtureKeepsDefaults() throws {
        let s = try decode(#"{"interfaceCount":7}"#, as: NetBoxSettings.self)
        XCTAssertEqual(s.interfaceCount, 7)
        XCTAssertTrue(s.showChart)
        XCTAssertEqual(s.upColor, RGBA(.green))
    }

    func testMissingPinnedInterfaceDecodesNil() throws {
        let s = try decode(#"{}"#, as: NetBoxSettings.self)
        XCTAssertNil(s.pinnedInterface)
    }

    func testPinnedInterfaceDecodesExplicitValue() throws {
        let s = try decode(#"{"pinnedInterface":"en0"}"#, as: NetBoxSettings.self)
        XCTAssertEqual(s.pinnedInterface, "en0")
    }

    func testExplicitNullPinnedInterfaceDecodesNil() throws {
        let s = try decode(#"{"pinnedInterface":null}"#, as: NetBoxSettings.self)
        XCTAssertNil(s.pinnedInterface)
    }

    func testPinnedInterfaceRoundTrip() throws {
        var s = NetBoxSettings()
        s.pinnedInterface = "en1"
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(NetBoxSettings.self, from: data)
        XCTAssertEqual(back.pinnedInterface, "en1")
    }

    func testOldFileWithoutThresholdKeysKeepsDefaults() throws {
        // Pre-threshold settings.json must not reset every setting.
        let s = try decode(#"{"interfaceCount":7}"#, as: NetBoxSettings.self)
        XCTAssertEqual(s.interfaceCount, 7)
        XCTAssertTrue(s.showThresholdColors)
        XCTAssertEqual(s.warnThreshold, 50)
        XCTAssertEqual(s.alarmThreshold, 100)
    }

    func testThresholdKeysRoundTrip() throws {
        let s = try decode(
            #"{"showThresholdColors":false,"warnThreshold":20,"alarmThreshold":80}"#,
            as: NetBoxSettings.self
        )
        XCTAssertFalse(s.showThresholdColors)
        XCTAssertEqual(s.warnThreshold, 20)
        XCTAssertEqual(s.alarmThreshold, 80)
    }

    func testZeroThresholdsFloorToOne() throws {
        // A hand-edited 0 must not make every positive rate an alarm.
        let s = try decode(#"{"warnThreshold":0,"alarmThreshold":0}"#, as: NetBoxSettings.self)
        XCTAssertEqual(s.warnThreshold, 1)
        XCTAssertEqual(s.alarmThreshold, 1)
    }
}

final class BatBoxSettingsDecodeTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let s = try decode(#"{"showChart":false}"#, as: BatBoxSettings.self)
        XCTAssertFalse(s.showChart)
        XCTAssertTrue(s.showStatus)
        XCTAssertEqual(s.levelColor, RGBA(.green))
    }
}

final class GitBoxSettingsDecodeTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let s = try decode(
            #"{"repoPaths":["/a","/b"],"barColor":{"red":1,"green":0,"blue":0,"alpha":1}}"#,
            as: GitBoxSettings.self
        )
        XCTAssertEqual(s.repoPaths, ["/a", "/b"])
        XCTAssertEqual(s.barColor, RGBA(red: 1, green: 0, blue: 0))
        XCTAssertEqual(s.repoCount, 5)
        XCTAssertEqual(s.scanDepth, 3)
        XCTAssertEqual(s.todayColor, RGBA(.orange))
    }

    func testMissingRepoPathsDecodesEmpty() throws {
        let s = try decode(#"{}"#, as: GitBoxSettings.self)
        XCTAssertEqual(s.repoPaths, [])
    }
}

final class DevBoxSettingsDecodeTests: XCTestCase {
    func testEmptyFixtureDecodesAllDefaults() throws {
        let s = try decode(#"{}"#, as: DevBoxSettings.self)
        XCTAssertEqual(s, DevBoxSettings())
    }
}

final class LiveBoxSettingsDecodeTests: XCTestCase {
    func testEmptyFixtureDecodesAllDefaults() throws {
        let s = try decode(#"{}"#, as: LiveBoxSettings.self)
        XCTAssertEqual(s, LiveBoxSettings())
    }

    func testOldFileWithoutThresholdKeysKeepsDefaults() throws {
        // Pre-threshold settings.json must not reset every setting.
        let s = try decode(#"{"showCPU":false}"#, as: LiveBoxSettings.self)
        XCTAssertFalse(s.showCPU)
        XCTAssertTrue(s.showThresholdColors)
        XCTAssertEqual(s.cpuWarnThreshold, 80)
        XCTAssertEqual(s.cpuAlarmThreshold, 90)
        XCTAssertEqual(s.memWarnThreshold, 80)
        XCTAssertEqual(s.memAlarmThreshold, 90)
        XCTAssertEqual(s.diskWarnThreshold, 80)
        XCTAssertEqual(s.diskAlarmThreshold, 90)
    }

    func testLegacyPairMigratesToAllThreeMetrics() throws {
        // settings-schema migration (ROADMAP.md:56): old warn/alarm pair is
        // inherited by every metric when no per-metric key is present.
        let s = try decode(#"{"warnThreshold":85,"alarmThreshold":92}"#, as: LiveBoxSettings.self)
        XCTAssertEqual(s.cpuWarnThreshold, 85)
        XCTAssertEqual(s.cpuAlarmThreshold, 92)
        XCTAssertEqual(s.memWarnThreshold, 85)
        XCTAssertEqual(s.memAlarmThreshold, 92)
        XCTAssertEqual(s.diskWarnThreshold, 85)
        XCTAssertEqual(s.diskAlarmThreshold, 92)
    }

    func testPerMetricKeysRoundTrip() throws {
        let s = try decode(
            #"{"showThresholdColors":false,"cpuWarnThreshold":70,"cpuAlarmThreshold":95,"memWarnThreshold":60,"memAlarmThreshold":85,"diskWarnThreshold":50,"diskAlarmThreshold":80}"#,
            as: LiveBoxSettings.self
        )
        XCTAssertFalse(s.showThresholdColors)
        XCTAssertEqual(s.cpuWarnThreshold, 70)
        XCTAssertEqual(s.cpuAlarmThreshold, 95)
        XCTAssertEqual(s.memWarnThreshold, 60)
        XCTAssertEqual(s.memAlarmThreshold, 85)
        XCTAssertEqual(s.diskWarnThreshold, 50)
        XCTAssertEqual(s.diskAlarmThreshold, 80)
    }

    func testMixedKeysKeepPresentFallBackLegacy() throws {
        // CPU pair explicit; MEM/DISK absent → fall back to the legacy pair.
        let s = try decode(
            #"{"cpuWarnThreshold":70,"cpuAlarmThreshold":95,"warnThreshold":85,"alarmThreshold":92}"#,
            as: LiveBoxSettings.self
        )
        XCTAssertEqual(s.cpuWarnThreshold, 70)
        XCTAssertEqual(s.cpuAlarmThreshold, 95)
        XCTAssertEqual(s.memWarnThreshold, 85)
        XCTAssertEqual(s.memAlarmThreshold, 92)
        XCTAssertEqual(s.diskWarnThreshold, 85)
        XCTAssertEqual(s.diskAlarmThreshold, 92)
    }

    func testEncodedOutputOmitsLegacyKeys() throws {
        var s = LiveBoxSettings()
        s.cpuWarnThreshold = 55
        s.memAlarmThreshold = 88
        let data = try JSONEncoder().encode(s)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["warnThreshold"])
        XCTAssertNil(object["alarmThreshold"])
        XCTAssertEqual(object["cpuWarnThreshold"] as? Int, 55)
        XCTAssertEqual(object["memAlarmThreshold"] as? Int, 88)
        XCTAssertEqual(object["diskWarnThreshold"] as? Int, 80)
    }

    func testExistingKeysStillDecodeAndEncode() throws {
        let s = try decode(
            #"{"showPerCoreCores":true,"processRefreshInterval":30}"#,
            as: LiveBoxSettings.self
        )
        XCTAssertTrue(s.showPerCoreCores)
        XCTAssertEqual(s.processRefreshInterval, 30)
    }

    func testOldFileWithoutPerVolumeKeyKeepsDefault() throws {
        let s = try decode(#"{"showDisk":false}"#, as: LiveBoxSettings.self)
        XCTAssertFalse(s.showDisk)
        XCTAssertTrue(s.showPerVolumeDisk)
    }

    func testPerVolumeKeyRoundTrips() throws {
        let s = try decode(#"{"showPerVolumeDisk":false}"#, as: LiveBoxSettings.self)
        XCTAssertFalse(s.showPerVolumeDisk)
    }

    func testOldFileWithoutRefreshIntervalKeyKeepsDefault() throws {
        let s = try decode(#"{"showCPU":false}"#, as: LiveBoxSettings.self)
        XCTAssertFalse(s.showCPU)
        XCTAssertEqual(s.processRefreshInterval, 15)
    }

    func testRefreshIntervalDecodesExplicitValue() throws {
        let s = try decode(#"{"processRefreshInterval":30}"#, as: LiveBoxSettings.self)
        XCTAssertEqual(s.processRefreshInterval, 30)
    }

    func testRefreshIntervalRoundTrips() throws {
        var s = LiveBoxSettings()
        s.processRefreshInterval = 5
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(LiveBoxSettings.self, from: data)
        XCTAssertEqual(back.processRefreshInterval, 5)
    }
}

final class ClipBoxSettingsDecodeTests: XCTestCase {
    func testPartialFixtureKeepsDefaults() throws {
        let s = try decode(#"{"historyCount":9}"#, as: ClipBoxSettings.self)
        XCTAssertEqual(s.historyCount, 9)
        XCTAssertTrue(s.showList)
        XCTAssertEqual(s.textColor, RGBA(.indigo))
    }
}

final class HomeBoxSettingsDecodeTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let s = try decode(#"{"unitsFahrenheit":true}"#, as: HomeBoxSettings.self)
        XCTAssertTrue(s.unitsFahrenheit)
        XCTAssertEqual(s.timezoneIDs, ["local", "UTC"])
        XCTAssertEqual(s.location, "")
    }
}

final class ShipBoxSettingsDecodeTests: XCTestCase {
    func testEmptyFixtureDecodesAllDefaults() throws {
        let s = try decode(#"{}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s, ShipBoxSettings())
    }

    func testPartialFixtureKeepsDefaults() throws {
        let s = try decode(#"{"repo":"a/b","runCount":8}"#, as: ShipBoxSettings.self)
        XCTAssertEqual(s.repo, "a/b")
        XCTAssertEqual(s.runCount, 8)
        XCTAssertEqual(s.successColor, RGBA(.green))
    }
}
