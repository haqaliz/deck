import Foundation

/// Atomic snapshot writes: unique temp file in the same directory, then
/// replaceItemAt (falling back to an atomic write). The target is either the
/// complete new content or the untouched old content — never a partial file.
enum AtomicFile {
    /// Returns false (never throws) if the data could not be persisted.
    ///
    /// `posixPermissions` is applied to the temp file *and* re-applied to the
    /// destination, because `replaceItemAt` carries the replaced file's own
    /// metadata over. Pass `0o600` for anything holding a credential.
    static func write(_ data: Data, to url: URL, posixPermissions: Int? = nil) -> Bool {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let temp = dir.appendingPathComponent(
                "\(url.lastPathComponent).tmp.\(UUID().uuidString)"
            )
            try data.write(to: temp, options: .atomic)
            applyPermissions(posixPermissions, to: temp)
            do {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                try data.write(to: url, options: .atomic)
            }
            applyPermissions(posixPermissions, to: url)
            return true
        } catch {
            return false
        }
    }

    private static func applyPermissions(_ mode: Int?, to url: URL) {
        guard let mode else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: mode)],
            ofItemAtPath: url.path
        )
    }
}
