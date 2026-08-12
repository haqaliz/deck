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
    var devbox = DevBoxSettings()
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
    var showPerCoreCores = true
    var processCount = 3
    var cpuColor = RGBA(.green)
    var memColor = RGBA(.cyan)
    var diskColor = RGBA(.orange)

    /// Tolerant decode: missing keys keep the defaults instead of throwing
    /// (the synthesized decoder throws, which would reset every setting via
    /// `DeckSettings.load()`'s fallback when old settings.json files lack
    /// newly added keys).
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showCPU = try c.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        showMEM = try c.decodeIfPresent(Bool.self, forKey: .showMEM) ?? true
        showDisk = try c.decodeIfPresent(Bool.self, forKey: .showDisk) ?? true
        showProcesses = try c.decodeIfPresent(Bool.self, forKey: .showProcesses) ?? true
        showPerCoreCores = try c.decodeIfPresent(Bool.self, forKey: .showPerCoreCores) ?? true
        processCount = try c.decodeIfPresent(Int.self, forKey: .processCount) ?? 3
        cpuColor = try c.decodeIfPresent(RGBA.self, forKey: .cpuColor) ?? RGBA(.green)
        memColor = try c.decodeIfPresent(RGBA.self, forKey: .memColor) ?? RGBA(.cyan)
        diskColor = try c.decodeIfPresent(RGBA.self, forKey: .diskColor) ?? RGBA(.orange)
    }
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

    /// Tolerant decode: missing keys keep the defaults instead of throwing
    /// (the synthesized decoder throws, which would reset every setting via
    /// `DeckSettings.load()`'s fallback when old settings.json files lack
    /// newly added keys).
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL)
        refreshInterval = try c.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? 60
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showModels = try c.decodeIfPresent(Bool.self, forKey: .showModels) ?? true
        inputColor = try c.decodeIfPresent(RGBA.self, forKey: .inputColor) ?? RGBA(.cyan)
        outputColor = try c.decodeIfPresent(RGBA.self, forKey: .outputColor) ?? RGBA(.green)
        costColor = try c.decodeIfPresent(RGBA.self, forKey: .costColor) ?? RGBA(.orange)
    }
}

struct NetBoxSettings: Codable, Equatable {
    var showChart = true
    var showInterfaces = true
    var interfaceCount = 3
    var upColor = RGBA(.green)
    var downColor = RGBA(.cyan)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showInterfaces = try c.decodeIfPresent(Bool.self, forKey: .showInterfaces) ?? true
        interfaceCount = try c.decodeIfPresent(Int.self, forKey: .interfaceCount) ?? 3
        upColor = try c.decodeIfPresent(RGBA.self, forKey: .upColor) ?? RGBA(.green)
        downColor = try c.decodeIfPresent(RGBA.self, forKey: .downColor) ?? RGBA(.cyan)
    }
}

struct BatBoxSettings: Codable, Equatable {
    var showChart = true
    var showStatus = true
    var levelColor = RGBA(.green)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showStatus = try c.decodeIfPresent(Bool.self, forKey: .showStatus) ?? true
        levelColor = try c.decodeIfPresent(RGBA.self, forKey: .levelColor) ?? RGBA(.green)
    }
}

struct GitBoxSettings: Codable, Equatable {
    var showChart = true
    var showRepos = true
    var repoCount = 5
    var scanDepth = 3
    var repoPaths: [String] = []
    var barColor = RGBA(.blue)
    var todayColor = RGBA(.orange)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showRepos = try c.decodeIfPresent(Bool.self, forKey: .showRepos) ?? true
        repoCount = try c.decodeIfPresent(Int.self, forKey: .repoCount) ?? 5
        scanDepth = try c.decodeIfPresent(Int.self, forKey: .scanDepth) ?? 3
        repoPaths = try c.decodeIfPresent([String].self, forKey: .repoPaths) ?? []
        barColor = try c.decodeIfPresent(RGBA.self, forKey: .barColor) ?? RGBA(.blue)
        todayColor = try c.decodeIfPresent(RGBA.self, forKey: .todayColor) ?? RGBA(.orange)
    }
}

struct DevBoxSettings: Codable, Equatable {
    var showPorts = true
    var showContainers = true
    var portCount = 5
    var containerCount = 5
    var portColor = RGBA(.teal)
    var containerColor = RGBA(.mint)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPorts = try c.decodeIfPresent(Bool.self, forKey: .showPorts) ?? true
        showContainers = try c.decodeIfPresent(Bool.self, forKey: .showContainers) ?? true
        portCount = try c.decodeIfPresent(Int.self, forKey: .portCount) ?? 5
        containerCount = try c.decodeIfPresent(Int.self, forKey: .containerCount) ?? 5
        portColor = try c.decodeIfPresent(RGBA.self, forKey: .portColor) ?? RGBA(.teal)
        containerColor = try c.decodeIfPresent(RGBA.self, forKey: .containerColor) ?? RGBA(.mint)
    }
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
