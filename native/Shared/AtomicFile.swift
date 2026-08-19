import Foundation

/// Atomic snapshot writes: unique temp file in the same directory, then
/// replaceItemAt (falling back to an atomic write). The target is either the
/// complete new content or the untouched old content — never a partial file.
enum AtomicFile {
    /// Returns false (never throws) if the data could not be persisted.
    static func write(_ data: Data, to url: URL) -> Bool {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let temp = dir.appendingPathComponent(
                "\(url.lastPathComponent).tmp.\(UUID().uuidString)"
            )
            try data.write(to: temp, options: .atomic)
            do {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
                return true
            } catch {
                try? FileManager.default.removeItem(at: temp)
                try data.write(to: url, options: .atomic)
                return true
            }
        } catch {
            return false
        }
    }
}
