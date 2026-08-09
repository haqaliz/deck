import Foundation

/// Detects whether the native WidgetKit widget (com.netbox.app.widget) is
/// registered with the system. When it is, the window widget's manual
/// "open at startup" and "close" affordances are redundant — the system
/// manages the native widget's lifecycle.
enum NativeWidgetDetector {
    private static let bundleID = "com.netbox.app.widget"
    private static var cached: Bool?
    private static var cachedAt: Date?

    static func isRegistered() -> Bool {
        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < 60 {
            return cached
        }
        let result = check()
        cached = result
        cachedAt = Date()
        return result
    }

    private static func check() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["pluginkit", "-m", "-i", bundleID]
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let out = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
