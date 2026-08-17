import Foundation

// MARK: - Disk per-volume (LiveBox large face)
//
// Pure logic extracted so the volume set / percent / formatting is testable in
// DeckSharedTests (the widget target can't be compiled into a unit-test
// bundle). The loader in DeckWidgets samples Volume resource values and feeds
// these pure functions. ROADMAP.md:69.

/// Raw record straight from the loader (getmntinfo + Volume resource keys).
struct RawVolume: Equatable {
    let name: String
    let mountPath: String
    let totalBytes: UInt64?
    let availableBytes: UInt64?
    let isLocal: Bool
    let isBrowsable: Bool
    let identifier: String
}

/// A displayable volume row.
struct DiskVolume: Equatable {
    let name: String
    let mountPoint: String
    let totalBytes: UInt64
    let availableBytes: UInt64

    var usedPercent: Double {
        LiveBoxDiskCore.usedPercent(total: totalBytes, available: availableBytes)
    }
}

enum LiveBoxDiskCore {
    /// Rows are capped so a machine with many mounts can't overflow the face.
    static let maxVolumes = 5
    /// Catalina+ split the boot volume: `/System/Volumes/Data` is the real
    /// read-write boot volume and must stay; its read-only `/` sibling and the
    /// Preboot/VM/Update siblings are dropped.
    static let bootDataMount = "/System/Volumes/Data"

    /// Used percent (0...100). 0 when the volume reports no usable capacity.
    static func usedPercent(total: UInt64, available: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return max(0, (Double(total) - Double(available)) / Double(total) * 100.0)
    }

    /// "512 MB free", "195 GB free", "1.2 TB free" (decimal units, glanceable).
    static func formatFreeBytes(_ bytes: UInt64) -> String {
        let n = Double(bytes)
        if n >= 1_000_000_000_000 { return String(format: "%.1f TB free", n / 1_000_000_000_000) }
        if n >= 1_000_000_000 { return String(format: "%.0f GB free", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.0f MB free", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0f KB free", n / 1_000) }
        return String(format: "%.0f B free", n)
    }

    /// Present the boot Data volume under its container name ("Macintosh HD -
    /// Data" → "Macintosh HD"); fall back to the mount path's last component
    /// when the localized name is empty.
    static func displayName(_ localizedName: String?, mountPath: String) -> String {
        guard let name = localizedName, !name.isEmpty else {
            return (mountPath as NSString).lastPathComponent
        }
        let suffix = " - Data"
        if name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// Local, browsable, real-capacity volumes only: drops the sealed system
    /// volume `/`, the non-boot `/System/Volumes/*` siblings, non-browsable
    /// system/disk-image mounts, and pseudo mounts; dedupes by identifier;
    /// sorts fullest-first; caps at `maxVolumes`.
    static func displayable(_ raw: [RawVolume]) -> [DiskVolume] {
        var seen = Set<String>()
        let kept = raw.compactMap { v -> DiskVolume? in
            guard v.isLocal, v.isBrowsable, let total = v.totalBytes, let available = v.availableBytes else { return nil }
            guard !isExcludedMount(v.mountPath) else { return nil }
            guard seen.insert(v.identifier).inserted else { return nil }
            return DiskVolume(
                name: displayName(v.name, mountPath: v.mountPath),
                mountPoint: v.mountPath,
                totalBytes: total,
                availableBytes: available
            )
        }
        return Array(kept.sorted { $0.usedPercent > $1.usedPercent }.prefix(maxVolumes))
    }

    private static func isExcludedMount(_ path: String) -> Bool {
        if path == "/" { return true }
        if path.hasPrefix("/System/Volumes/") { return path != bootDataMount }
        let pseudo = ["/dev", "/private/var/vm", "/home", "/net"]
        return pseudo.contains(path)
    }
}