import XCTest

private let boot = RawVolume(
    name: "Macintosh HD - Data",
    mountPath: "/System/Volumes/Data",
    totalBytes: 1_000_000_000_000,
    availableBytes: 300_000_000_000,
    isLocal: true,
    identifier: "boot-data"
)
private let system = RawVolume(
    name: "Macintosh HD",
    mountPath: "/",
    totalBytes: 1_000_000_000_000,
    availableBytes: 0,
    isLocal: true,
    identifier: "system"
)
private let external = RawVolume(
    name: "Backup",
    mountPath: "/Volumes/Backup",
    totalBytes: 2_000_000_000_000,
    availableBytes: 1_000_000_000_000,
    isLocal: true,
    identifier: "external"
)

final class LiveBoxDiskPercentTests: XCTestCase {
    func testUsedPercent() {
        XCTAssertEqual(LiveBoxDiskCore.usedPercent(total: 100, available: 30), 70)
        XCTAssertEqual(LiveBoxDiskCore.usedPercent(total: 100, available: 0), 100)
    }

    func testZeroTotalIsZero() {
        XCTAssertEqual(LiveBoxDiskCore.usedPercent(total: 0, available: 0), 0)
        XCTAssertEqual(LiveBoxDiskCore.usedPercent(total: 0, available: 5), 0)
    }

    func testUsedPercentNeverNegative() {
        XCTAssertEqual(LiveBoxDiskCore.usedPercent(total: 100, available: 130), 0)
    }
}

final class LiveBoxDiskFormatTests: XCTestCase {
    func testTerabytes() {
        XCTAssertEqual(LiveBoxDiskCore.formatFreeBytes(1_200_000_000_000), "1.2 TB free")
    }

    func testGigabytes() {
        XCTAssertEqual(LiveBoxDiskCore.formatFreeBytes(195_000_000_000), "195 GB free")
    }

    func testMegabytes() {
        XCTAssertEqual(LiveBoxDiskCore.formatFreeBytes(512_000_000), "512 MB free")
    }

    func testBytes() {
        XCTAssertEqual(LiveBoxDiskCore.formatFreeBytes(0), "0 B free")
        XCTAssertEqual(LiveBoxDiskCore.formatFreeBytes(999), "999 B free")
    }
}

final class LiveBoxDiskNameTests: XCTestCase {
    func testStripsDataSuffix() {
        XCTAssertEqual(LiveBoxDiskCore.displayName("Macintosh HD - Data", mountPath: "/System/Volumes/Data"), "Macintosh HD")
    }

    func testPlainNameUnchanged() {
        XCTAssertEqual(LiveBoxDiskCore.displayName("Backup", mountPath: "/Volumes/Backup"), "Backup")
    }

    func testEmptyNameFallsBackToMountLastComponent() {
        XCTAssertEqual(LiveBoxDiskCore.displayName(nil, mountPath: "/Volumes/External"), "External")
        XCTAssertEqual(LiveBoxDiskCore.displayName("", mountPath: "/Volumes/External"), "External")
    }
}

final class LiveBoxDiskSetTests: XCTestCase {
    func testEmptyInputYieldsEmpty() {
        XCTAssertEqual(LiveBoxDiskCore.displayable([]), [])
    }

    func testKeepsBootDataAndExternalDropsSystemVolume() {
        let result = LiveBoxDiskCore.displayable([system, boot, external])
        XCTAssertEqual(result.map(\.mountPoint), ["/System/Volumes/Data", "/Volumes/Backup"])
    }

    func testDropsSystemSiblingsExceptData() {
        let preboot = RawVolume(name: "Preboot", mountPath: "/System/Volumes/Preboot", totalBytes: 500_000_000, availableBytes: 100_000_000, isLocal: true, identifier: "preboot")
        let vm = RawVolume(name: "VM", mountPath: "/System/Volumes/VM", totalBytes: 500_000_000, availableBytes: 100_000_000, isLocal: true, identifier: "vm")
        let update = RawVolume(name: "Update", mountPath: "/System/Volumes/Update", totalBytes: 500_000_000, availableBytes: 100_000_000, isLocal: true, identifier: "update")
        let result = LiveBoxDiskCore.displayable([boot, preboot, vm, update])
        XCTAssertEqual(result.map(\.mountPoint), ["/System/Volumes/Data"])
    }

    func testDropsPseudoMounts() {
        let dev = RawVolume(name: "dev", mountPath: "/dev", totalBytes: 500_000_000, availableBytes: 100_000_000, isLocal: true, identifier: "dev")
        let vm = RawVolume(name: "vm", mountPath: "/private/var/vm", totalBytes: 500_000_000, availableBytes: 100_000_000, isLocal: true, identifier: "vm")
        let result = LiveBoxDiskCore.displayable([dev, vm, boot])
        XCTAssertEqual(result.map(\.mountPoint), ["/System/Volumes/Data"])
    }

    func testDropsNonLocalVolumes() {
        let network = RawVolume(name: "NAS", mountPath: "/Volumes/NAS", totalBytes: 1_000_000_000, availableBytes: 500_000_000, isLocal: false, identifier: "nas")
        let result = LiveBoxDiskCore.displayable([network, boot])
        XCTAssertEqual(result.map(\.mountPoint), ["/System/Volumes/Data"])
    }

    func testDropsNilCapacityVolumes() {
        let unknown = RawVolume(name: "Unknown", mountPath: "/Volumes/Unknown", totalBytes: nil, availableBytes: nil, isLocal: true, identifier: "unknown")
        let result = LiveBoxDiskCore.displayable([unknown, boot])
        XCTAssertEqual(result.map(\.mountPoint), ["/System/Volumes/Data"])
    }

    func testDedupesByIdentifier() {
        let duplicate = RawVolume(name: "Macintosh HD - Data", mountPath: "/Volumes/Data", totalBytes: 1_000_000_000, availableBytes: 500_000_000, isLocal: true, identifier: "boot-data")
        let result = LiveBoxDiskCore.displayable([boot, duplicate])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].mountPoint, "/System/Volumes/Data")
    }

    func testSortsFullestFirst() {
        let result = LiveBoxDiskCore.displayable([external, boot])
        XCTAssertEqual(result.map(\.name), ["Macintosh HD", "Backup"])
    }

    func testCapsAtMaxVolumes() {
        let many = (0..<8).map { i in
            RawVolume(name: "Vol \(i)", mountPath: "/Volumes/Vol \(i)", totalBytes: 1_000_000_000, availableBytes: UInt64(i) * 100_000_000, isLocal: true, identifier: "v\(i)")
        }
        let result = LiveBoxDiskCore.displayable(many)
        XCTAssertEqual(result.count, LiveBoxDiskCore.maxVolumes)
    }

    func testDiskVolumeUsedPercent() {
        let volume = DiskVolume(name: "Backup", mountPoint: "/Volumes/Backup", totalBytes: 200, availableBytes: 40)
        XCTAssertEqual(volume.usedPercent, 80)
    }
}