import Foundation
import SwiftUI

// MARK: - Color (Codable RGBA)

struct RGBA: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(ns.redComponent)
        green = Double(ns.greenComponent)
        blue = Double(ns.blueComponent)
        alpha = Double(ns.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Settings

struct DeckSettings: Codable, Equatable {
    var livebox = LiveBoxSettings()
    var openbox = OpenBoxSettings()
    var netbox = NetBoxSettings()
    var batbox = BatBoxSettings()
    var gitbox = GitBoxSettings()
    var agentAtLogin = true

    /// Settings live inside the widget extension's sandbox container so both
    /// the (unsandboxed) host app and the sandboxed extension can use them.
    /// NOTE: inside the sandbox, homeDirectoryForCurrentUser already points at
    /// the container (…/Containers/com.deck.app.widgets/Data), so the two
    /// resolve to the same absolute path.
    static var containerDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        if isSandboxed {
            return home.appendingPathComponent("Library/Application Support/Deck", isDirectory: true)
        }
        return home.appendingPathComponent("Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck", isDirectory: true)
    }

    static var fileURL: URL {
        containerDirectory.appendingPathComponent("settings.json")
    }

    static func load() -> DeckSettings {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return DeckSettings() }
        return (try? JSONDecoder().decode(DeckSettings.self, from: data)) ?? DeckSettings()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: Self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.fileURL)
    }
}

struct LiveBoxSettings: Codable, Equatable {
    var showChart = true
    var showCPU = true
    var showMEM = true
    var showDisk = true
    var showProcesses = true
    var processCount = 3
    var cpuColor = RGBA(.green)
    var memColor = RGBA(.cyan)
    var diskColor = RGBA(.orange)
}

struct OpenBoxSettings: Codable, Equatable {
    var token = ""
    /// Non-empty → remote server mode (auto-switch); empty → local DB.
    var serverURL: String?
    var refreshInterval = 60
    var showChart = true
    var showModels = true
    var inputColor = RGBA(.cyan)
    var outputColor = RGBA(.green)
    var costColor = RGBA(.orange)
}

struct NetBoxSettings: Codable, Equatable {
    var showChart = true
    var showInterfaces = true
    var interfaceCount = 3
    var upColor = RGBA(.green)
    var downColor = RGBA(.cyan)
}

struct BatBoxSettings: Codable, Equatable {
    var showChart = true
    var showStatus = true
    var levelColor = RGBA(.green)
}

struct GitBoxSettings: Codable, Equatable {
    var showChart = true
    var showRepos = true
    var repoCount = 5
    var scanDepth = 3
    var repoPaths: [String] = []
    var barColor = RGBA(.blue)
    var todayColor = RGBA(.orange)
}

// MARK: - ColorPicker binding helper

extension Binding where Value == RGBA {
    var color: Binding<Color> {
        Binding<Color>(
            get: { wrappedValue.color },
            set: { wrappedValue = RGBA($0) }
        )
    }
}
