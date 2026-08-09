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

struct OpenBoxSettings: Codable {
    var token: String = ProcessInfo.processInfo.environment["OPENCODE_TOKEN"] ?? ""
    var refreshInterval: Int = 5
    var showChart = true
    var showModels = true
    var inputColor = CodableColor(.cyan)
    var outputColor = CodableColor(.green)
    var costColor = CodableColor(.orange)
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: OpenBoxSettings {
        didSet { save() }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("OpenBox/settings.json")
    }

    init() {
        if
            let data = try? Data(contentsOf: Self.fileURL),
            let decoded = try? JSONDecoder().decode(OpenBoxSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = OpenBoxSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? FileManager.default.createDirectory(
            at: Self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.fileURL)
    }
}
