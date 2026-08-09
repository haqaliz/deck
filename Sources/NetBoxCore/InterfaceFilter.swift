import Foundation

public enum InterfaceFilter {
    /// Prefixes of non-physical / non-user interfaces that never appear.
    public static let excludedPrefixes = [
        "lo", "utun", "awdl", "llw", "anpi", "ap", "bridge", "vboxnet", "vmnet", "gif", "stf",
    ]

    public static func isIncluded(_ name: String) -> Bool {
        !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    public static func included(_ samples: [InterfaceSample]) -> [InterfaceSample] {
        samples.filter { isIncluded($0.name) }
    }
}
