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

    // Thermal row (plan_20260820.md Phase 2): opt-in, so an existing
    // settings.json must keep LiveBox rendering exactly as before.

    func testOldFileWithoutThermalKeyDefaultsOff() throws {
        let s = try decode(#"{"showCPU":false}"#, as: LiveBoxSettings.self)
        XCTAssertFalse(s.showCPU)
        XCTAssertFalse(s.showThermal)
    }

    func testThermalKeyDecodesExplicitValue() throws {
        let s = try decode(#"{"showThermal":true}"#, as: LiveBoxSettings.self)
        XCTAssertTrue(s.showThermal)
    }

    /// LiveBoxSettings hand-writes both the decoder and the encoder, so a
    /// missing `encode` line would silently drop the setting on every save.
    func testThermalKeyRoundTrips() throws {
        var s = LiveBoxSettings()
        s.showThermal = true
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(LiveBoxSettings.self, from: data)
        XCTAssertTrue(back.showThermal)
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

final class WeatherBoxSettingsDecodeTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let s = try decode(#"{"unitsFahrenheit":true}"#, as: WeatherBoxSettings.self)
        XCTAssertTrue(s.unitsFahrenheit)
        XCTAssertTrue(s.showForecast)
        XCTAssertEqual(s.location, "")
    }
}

final class ClockBoxSettingsDecodeTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let s = try decode(#"{"showOffset":false}"#, as: ClockBoxSettings.self)
        XCTAssertFalse(s.showOffset)
        XCTAssertTrue(s.showRelativeDay)
        XCTAssertEqual(s.cityIDs, [ClockBoxCore.localID, "UTC"])
        XCTAssertEqual(s.mainCityID, "", "absent main clock means auto")
        XCTAssertEqual(s.timeColor, RGBA(.teal))
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

final class TaskBoxSettingsDecodeTests: XCTestCase {
    func testEmptyFixtureDecodesAllDefaults() throws {
        let s = try decode(#"{}"#, as: TaskBoxSettings.self)
        XCTAssertEqual(s, TaskBoxSettings())
    }

    func testPartialFixtureKeepsDefaults() throws {
        let s = try decode(
            #"{"organization":"Contoso","project":"My Project","taskCount":8}"#,
            as: TaskBoxSettings.self
        )
        XCTAssertEqual(s.organization, "Contoso")
        XCTAssertEqual(s.project, "My Project")
        XCTAssertEqual(s.taskCount, 8)
        XCTAssertTrue(s.showList)
        XCTAssertTrue(s.showLegend)
        XCTAssertEqual(s.todoColor, RGBA(.blue))
        XCTAssertEqual(s.stateMapping, TaskStateMapping(), "the mapping defaults when absent")
    }

    /// A settings file written by a newer build must not cost the user their
    /// whole TaskBox configuration.
    func testUnknownFutureFieldIsIgnored() throws {
        let s = try decode(#"{"organization":"C","somethingNew":true}"#, as: TaskBoxSettings.self)
        XCTAssertEqual(s.organization, "C")
    }

    func testDeckSettingsWithoutATaskBoxSectionStillLoads() throws {
        let s = try decode(#"{"shipbox":{"repo":"a/b"}}"#, as: DeckSettings.self)
        XCTAssertEqual(s.shipbox.repo, "a/b")
        XCTAssertEqual(s.taskbox, TaskBoxSettings())
    }
}

/// Guards the data-loss path that adding a widget section opens up.
///
/// `DeckSettings.load()` falls back to `DeckSettings()` on any decode error, so
/// a container-level `keyNotFound` doesn't surface as an error — it silently
/// replaces every setting the user has. These tests are the reason the
/// container decodes tolerantly and not just each section.
final class DeckSettingsSchemaEvolutionTests: XCTestCase {
    func testSettingsFileFromBeforeTaskBoxKeepsEveryOtherSection() throws {
        let s = try decode("""
        {"livebox":{"showCPU":false},"openbox":{"token":"abc"},"netbox":{},
         "batbox":{},"gitbox":{"scanDepth":4},"devbox":{},"clipbox":{},
         "homebox":{"location":"Tehran"},"shipbox":{"repo":"a/b"},
         "agentAtLogin":false}
        """, as: DeckSettings.self)
        XCTAssertFalse(s.livebox.showCPU)
        XCTAssertEqual(s.openbox.token, "abc")
        XCTAssertEqual(s.gitbox.scanDepth, 4)
        XCTAssertEqual(s.weatherbox.location, "Tehran", "legacy homebox key migrates")
        XCTAssertEqual(s.shipbox.repo, "a/b")
        XCTAssertFalse(s.agentAtLogin)
        XCTAssertEqual(s.taskbox, TaskBoxSettings(), "the new section defaults")
    }

    func testAnyOneSectionCanBeAbsentWithoutLosingTheOthers() throws {
        let s = try decode(#"{"openbox":{"token":"kept"}}"#, as: DeckSettings.self)
        XCTAssertEqual(s.openbox.token, "kept")
        XCTAssertEqual(s.livebox, LiveBoxSettings())
        XCTAssertEqual(s.shipbox, ShipBoxSettings())
    }

    func testAnEmptyObjectDecodesToAllDefaults() throws {
        XCTAssertEqual(try decode(#"{}"#, as: DeckSettings.self), DeckSettings())
    }
}

final class TaskStateMappingDecodeTests: XCTestCase {
    /// A user who has customised the mapping must keep it across updates, and a
    /// settings file predating the mapping must gain the defaults rather than
    /// an empty mapping that sends every state to "other".
    func testPartialMappingKeepsTheOtherLanesAtTheirDefaults() throws {
        let s = try decode(#"{"stateMapping":{"todo":"Icebox"}}"#, as: TaskBoxSettings.self)
        XCTAssertEqual(s.stateMapping.todo, "Icebox")
        XCTAssertEqual(s.stateMapping.inProgress, TaskStateMapping().inProgress)
        XCTAssertEqual(s.stateMapping.testing, TaskStateMapping().testing)
    }

    func testAbsentMappingDecodesToDefaults() throws {
        let s = try decode(#"{"organization":"C"}"#, as: TaskBoxSettings.self)
        XCTAssertEqual(s.stateMapping.lane(for: "Committed"), .inProgress)
    }
}

// MARK: - Container-level round trip
//
// `DeckSettings.init(from:)` assigns each section by hand. A section that is
// declared as a property but forgotten in that initializer still *encodes*
// (the property exists) while silently decoding back to its defaults — the
// user's settings are written to disk and then ignored on every load. That
// is not hypothetical: `calbox` shipped with exactly this omission.
//
// One test closes the whole class of bug: mutate every section away from its
// defaults, encode, decode, and require the result to be identical. Any
// forgotten section fails here, including sections added in the future.

final class DeckSettingsRoundTripTests: XCTestCase {
    /// Every section set to something that is *not* its default, so a dropped
    /// section can never coincidentally compare equal.
    private func mutatedSettings() -> DeckSettings {
        var s = DeckSettings()
        s.livebox.processCount = 9
        s.livebox.cpuColor = RGBA(red: 0.11, green: 0.22, blue: 0.33)
        s.openbox.token = "round-trip-token"
        s.openbox.modelCount = 7
        s.netbox.interfaceCount = 8
        s.netbox.pinnedInterface = "en7"
        s.batbox.showChart = false
        s.batbox.levelColor = RGBA(red: 0.44, green: 0.55, blue: 0.66)
        s.gitbox.repoPaths = ["/tmp/one", "/tmp/two"]
        s.gitbox.scanDepth = 6
        s.devbox.portCount = 11
        s.devbox.showContainers = false
        s.clipbox.historyCount = 12
        s.clipbox.textColor = RGBA(red: 0.77, green: 0.88, blue: 0.99)
        s.weatherbox.location = "Reykjavik"
        s.weatherbox.unitsFahrenheit = true
        s.clockbox.cityIDs = ["Asia/Tokyo", "Europe/Paris"]
        s.clockbox.mainCityID = "Europe/Paris"
        s.clockbox.showOffset = false
        s.shipbox.repo = "owner/name"
        s.shipbox.runCount = 13
        s.taskbox.organization = "org"
        s.taskbox.project = "proj"
        s.calbox.todayCount = 3
        s.calbox.showTomorrow = false
        s.calbox.accentColor = RGBA(red: 0.01, green: 0.02, blue: 0.03)
        s.agentAtLogin = false
        return s
    }

    func testEverySectionSurvivesRoundTrip() throws {
        let original = mutatedSettings()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeckSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// Pins the failure to the exact section rather than the whole blob, so a
    /// future regression reports *which* section was dropped.
    func testEachSectionIndividually() throws {
        let original = mutatedSettings()
        let data = try JSONEncoder().encode(original)
        let d = try JSONDecoder().decode(DeckSettings.self, from: data)
        XCTAssertEqual(d.livebox, original.livebox, "livebox dropped on decode")
        XCTAssertEqual(d.openbox, original.openbox, "openbox dropped on decode")
        XCTAssertEqual(d.netbox, original.netbox, "netbox dropped on decode")
        XCTAssertEqual(d.batbox, original.batbox, "batbox dropped on decode")
        XCTAssertEqual(d.gitbox, original.gitbox, "gitbox dropped on decode")
        XCTAssertEqual(d.devbox, original.devbox, "devbox dropped on decode")
        XCTAssertEqual(d.clipbox, original.clipbox, "clipbox dropped on decode")
        XCTAssertEqual(d.weatherbox, original.weatherbox, "weatherbox dropped on decode")
        XCTAssertEqual(d.clockbox, original.clockbox, "clockbox dropped on decode")
        XCTAssertEqual(d.shipbox, original.shipbox, "shipbox dropped on decode")
        XCTAssertEqual(d.taskbox, original.taskbox, "taskbox dropped on decode")
        XCTAssertEqual(d.calbox, original.calbox, "calbox dropped on decode")
        XCTAssertEqual(d.agentAtLogin, original.agentAtLogin, "agentAtLogin dropped on decode")
    }
}

// MARK: - homebox -> weatherbox + clockbox migration

final class HomeBoxSplitMigrationTests: XCTestCase {
    /// A settings.json written before the split has no `weatherbox` and no
    /// `clockbox`. Both must come from the retired `homebox` blob rather than
    /// resetting the user's location, units and zones to defaults.
    private let preSplit = """
    {"homebox":{"location":"Reykjavik","unitsFahrenheit":true,"showForecast":false,
                "timezoneIDs":["local","Asia/Tokyo","Europe/Paris"],"showZones":true},
     "livebox":{"processCount":9}}
    """

    func testWeatherSettingsCarryOver() throws {
        let s = try decode(preSplit, as: DeckSettings.self)
        XCTAssertEqual(s.weatherbox.location, "Reykjavik")
        XCTAssertTrue(s.weatherbox.unitsFahrenheit)
        XCTAssertFalse(s.weatherbox.showForecast)
    }

    func testZonesBecomeClockCities() throws {
        let s = try decode(preSplit, as: DeckSettings.self)
        XCTAssertEqual(s.clockbox.cityIDs, ["local", "Asia/Tokyo", "Europe/Paris"])
    }

    /// The migration must not disturb unrelated sections.
    func testOtherSectionsAreUntouched() throws {
        let s = try decode(preSplit, as: DeckSettings.self)
        XCTAssertEqual(s.livebox.processCount, 9)
        XCTAssertEqual(s.netbox, NetBoxSettings())
    }

    /// A file with the new keys ignores any stale `homebox` left beside them.
    func testNewKeysWinOverLegacyBlob() throws {
        let json = """
        {"homebox":{"location":"Old","timezoneIDs":["UTC"]},
         "weatherbox":{"location":"New"},
         "clockbox":{"cityIDs":["Asia/Tehran"]}}
        """
        let s = try decode(json, as: DeckSettings.self)
        XCTAssertEqual(s.weatherbox.location, "New")
        XCTAssertEqual(s.clockbox.cityIDs, ["Asia/Tehran"])
    }

    /// A file with neither shape decodes to defaults, not to an error.
    func testAbsentEverythingDecodesDefaults() throws {
        let s = try decode(#"{}"#, as: DeckSettings.self)
        XCTAssertEqual(s.weatherbox, WeatherBoxSettings())
        XCTAssertEqual(s.clockbox, ClockBoxSettings())
    }

    /// The old cap was 3 and the new one is 4, so nothing truncates on the way
    /// in — but a hand-edited file with more than 4 must still be clamped.
    func testCityListIsClampedToTheMaximum() throws {
        let json = """
        {"clockbox":{"cityIDs":["UTC","Asia/Tokyo","Europe/Paris","America/Toronto","Asia/Tehran",
                                "Australia/Sydney","Europe/Berlin"]}}
        """
        let s = try decode(json, as: DeckSettings.self)
        XCTAssertEqual(s.clockbox.cityIDs.count, ClockBoxCore.maxCities)
        XCTAssertEqual(s.clockbox.cityIDs.last, "Australia/Sydney")
    }

    /// The retired keys must not be written back out.
    func testEncodedOutputHasNoHomeboxKey() throws {
        let data = try JSONEncoder().encode(try decode(preSplit, as: DeckSettings.self))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("\"homebox\""))
        XCTAssertTrue(json.contains("\"weatherbox\""))
        XCTAssertTrue(json.contains("\"clockbox\""))
    }
}
