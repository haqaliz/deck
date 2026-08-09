import Foundation

public enum NetBoxFormatters {
    /// "512 B/s", "1.2 KB/s", "3.4 MB/s", "1.2 GB/s"
    public static func formatRate(_ bytesPerSecond: Double) -> String {
        let n = max(0, bytesPerSecond)
        if n >= 1_000_000_000 { return String(format: "%.1f GB/s", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1f MB/s", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1f KB/s", n / 1_000) }
        return String(format: "%.0f B/s", n)
    }
}
