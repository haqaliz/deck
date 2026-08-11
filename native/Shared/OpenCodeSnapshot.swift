import Foundation

// MARK: - OpenCode snapshot
//
// The sandboxed widget extension cannot read the opencode SQLite DB (legacy
// file exceptions are dropped for extensions). Instead the Deck host app reads
// the DB and writes a snapshot JSON into the extension's container; the
// OpenBox widget reads that snapshot.

struct OpenCodeSnapshot: Codable, Equatable {
    var writtenAt: Date
    var sessions: Int64
    var input: Int64
    var output: Int64
    var cost: Double
    var daily: [Day]
    var models: [Model]
    var totalInput: Int64
    var totalOutput: Int64
    var totalCost: Double

    struct Day: Codable, Equatable {
        let day: String
        let input: Int64
        let output: Int64
    }

    struct Model: Codable, Equatable {
        let model: String
        let cost: Double
        let input: Int64
        let output: Int64
    }
}

enum OpenCodeSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("opencode.json")
    }

    static func load() -> OpenCodeSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(OpenCodeSnapshot.self, from: data)
    }

    static func save(_ snapshot: OpenCodeSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}
