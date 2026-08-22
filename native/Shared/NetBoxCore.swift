import Foundation
import Darwin

// MARK: - Network counters (getifaddrs AF_LINK)

struct InterfaceSample: Codable, Equatable {
    let name: String
    let rxBytes: UInt64
    let txBytes: UInt64
}

struct InterfaceRates: Equatable {
    let name: String
    let up: Double
    let down: Double
}

enum NetworkMetricsLoader {
    static let excludedPrefixes = [
        "lo", "utun", "awdl", "llw", "anpi", "ap", "bridge", "vboxnet", "vmnet", "gif", "stf",
    ]

    /// Byte counters for every physical interface.
    static func sample() -> [InterfaceSample] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [InterfaceSample] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let ifa = current.pointee
            if let namePtr = ifa.ifa_name,
               ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                let name = String(cString: namePtr)
                if !excludedPrefixes.contains(where: { name.hasPrefix($0) }) {
                    result.append(InterfaceSample(
                        name: name,
                        rxBytes: UInt64(d.ifi_ibytes),
                        txBytes: UInt64(d.ifi_obytes)
                    ))
                }
            }
            ptr = ifa.ifa_next
        }
        return result
    }

    /// Names of interfaces that are both up-and-running and carry an IP.
    ///
    /// Deliberately computed fresh each render rather than stored on
    /// `InterfaceSample`: that struct is `Codable` and persisted in
    /// UserDefaults, so adding a field would break decoding of samples
    /// already on disk. Nothing here needs to survive a restart.
    static func liveInterfaces() -> Set<String> {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var running: Set<String> = []
        var addressed: Set<String> = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let ifa = current.pointee
            if let namePtr = ifa.ifa_name {
                let name = String(cString: namePtr)
                if !excludedPrefixes.contains(where: { name.hasPrefix($0) }) {
                    let flags = Int32(ifa.ifa_flags)
                    if flags & IFF_UP != 0 && flags & IFF_RUNNING != 0 {
                        running.insert(name)
                    }
                    let family = ifa.ifa_addr?.pointee.sa_family
                    if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                        addressed.insert(name)
                    }
                }
            }
            ptr = ifa.ifa_next
        }
        return running.intersection(addressed)
    }

    static func rates(previous: InterfaceSample, current: InterfaceSample, interval: TimeInterval) -> InterfaceRates {
        let down = rate(previousBytes: previous.rxBytes, currentBytes: current.rxBytes, interval: interval)
        let up = rate(previousBytes: previous.txBytes, currentBytes: current.txBytes, interval: interval)
        return InterfaceRates(name: current.name, up: up, down: down)
    }

    private static func rate(
        previousBytes: UInt64,
        currentBytes: UInt64,
        interval: TimeInterval
    ) -> Double {
        guard interval > 0, currentBytes >= previousBytes else { return 0 }
        return Double(currentBytes - previousBytes) / interval
    }
}

/// Which interfaces the widget displays: a manual pin wins when it is still
/// present in the sample; anything else (no pin, or the pin vanished, e.g.
/// Wi-Fi off) falls back to all interfaces — the provider's "most active"
/// auto pick.
enum NetBoxPinnedInterface {
    static func select(pinned: String?, interfaces: [InterfaceRates]) -> [InterfaceRates] {
        guard let pinned, !pinned.isEmpty else { return interfaces }
        let filtered = interfaces.filter { $0.name == pinned }
        return filtered.isEmpty ? interfaces : filtered
    }
}

/// Warn/alarm tier for a network rate (NetBox threshold coloring).
/// Thresholds are in decimal MB/s (×1,000,000, matching NetBoxFormatters).
/// A non-positive rate is "no reading" — idle, stale, or a counter reset —
/// and is never tinted, even when the configured thresholds are 0.
/// Thresholds below 1 MB/s are floored to 1 so a hand-edited 0 can never
/// make any traffic an alarm.
enum NetBoxThresholdTier {
    static func tier(rate: Double, warnMBps: Int, alarmMBps: Int) -> ThresholdTier {
        guard rate > 0 else { return .normal }
        let warn = max(1, warnMBps) * 1_000_000
        let alarm = max(1, alarmMBps) * 1_000_000
        return ThresholdTier.tier(value: rate, warn: Double(warn), alarm: Double(alarm))
    }
}

enum NetBoxFormatters {
    /// "512 B/s", "1.2 KB/s", "3.4 MB/s", "1.2 GB/s"
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let n = max(0, bytesPerSecond)
        if n >= 1_000_000_000 { return String(format: "%.1f GB/s", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1f MB/s", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1f KB/s", n / 1_000) }
        return String(format: "%.0f B/s", n)
    }
}


/// Which interface is "the" active one, and in what order the list renders.
///
/// Sorting on traffic alone is an all-ties sort whenever the machine is idle,
/// so the winner collapsed to whatever `getifaddrs` returned first — a dead
/// `en4` bridge outranking the Wi-Fi actually carrying the connection. A live
/// link (up, running, and addressed) always outranks a dead one; traffic only
/// breaks ties within each group.
enum NetBoxActiveInterface {
    static func sorted(rates: [InterfaceRates], live: Set<String>) -> [InterfaceRates] {
        rates.sorted { lhs, rhs in
            let lhsLive = live.contains(lhs.name)
            let rhsLive = live.contains(rhs.name)
            if lhsLive != rhsLive { return lhsLive }
            return max(lhs.up, lhs.down) > max(rhs.up, rhs.down)
        }
    }

    static func select(rates: [InterfaceRates], live: Set<String>) -> InterfaceRates? {
        sorted(rates: rates, live: live).first
    }
}
