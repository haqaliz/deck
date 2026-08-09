import Darwin
import NetBoxCore

// MARK: - Network counters
//
// Per-interface rx/tx byte counters come from `getifaddrs` AF_LINK entries,
// whose `ifa_data` is a `struct if_data` with `ifi_ibytes` / `ifi_obytes`.

enum NetworkMetricsLoader {
    /// Byte counters for every interface, filtered to physical ones.
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
                result.append(InterfaceSample(
                    name: String(cString: namePtr),
                    rxBytes: UInt64(d.ifi_ibytes),
                    txBytes: UInt64(d.ifi_obytes)
                ))
            }
            ptr = ifa.ifa_next
        }
        return InterfaceFilter.included(result)
    }
}
