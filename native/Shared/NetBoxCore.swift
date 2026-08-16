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
