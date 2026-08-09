import SwiftUI
import Foundation

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(ns.redComponent)
        green = Double(ns.greenComponent)
        blue = Double(ns.blueComponent)
        alpha = Double(ns.alphaComponent)
    }
}

struct NetBoxSettings: Codable {
    var showChart = true
    var showInterfaces = true
    var interfaceCount = 3
    var upColor = CodableColor(.green)
    var downColor = CodableColor(.cyan)
    var launchAtLogin = false
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: NetBoxSettings {
        didSet { save() }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NetBox/settings.json")
    }

    init() {
        if
            let data = try? Data(contentsOf: Self.fileURL),
            let decoded = try? JSONDecoder().decode(NetBoxSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = NetBoxSettings()
        }
        settings.launchAtLogin = Self.launchAgentExists
    }

    private static var launchAgentURL: URL {
        let dir = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return dir.appendingPathComponent("LaunchAgents/com.netbox.widget.plist")
    }

    private static var launchAgentExists: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private var executablePath: String {
        if let path = Bundle.main.executablePath { return path }
        let raw = CommandLine.arguments[0]
        return URL(fileURLWithPath: raw).absoluteURL.standardizedFileURL.path
    }

    /// Enables/disables launch at login by creating or removing a LaunchAgent plist.
    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        let url = Self.launchAgentURL
        if enabled {
            let args = [executablePath] + Array(CommandLine.arguments.dropFirst())
            let plist: [String: Any] = [
                "Label": "com.netbox.widget",
                "ProgramArguments": args,
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            guard
                let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func save() {
        guard
            let data = try? JSONEncoder().encode(settings)
        else { return }
        try? FileManager.default.createDirectory(
            at: Self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.fileURL)
    }
}
