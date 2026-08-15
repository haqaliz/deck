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
    var tools: [ToolCount]
    var costDaily: [CostDay]
    var sessionList: [SessionRow]
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

    struct ToolCount: Codable, Equatable {
        let tool: String
        let count: Int64
    }

    struct SessionRow: Codable, Equatable {
        let title: String
        let input: Int64
        let output: Int64
        let timeCreated: Date
    }

    struct CostDay: Codable, Equatable {
        let day: String
        let model: String
        let cost: Double
    }

    /// Tolerant decode: `tools` is newer than the first snapshots — missing
    /// key falls back to [] instead of throwing (PR #8 pattern).
    init(writtenAt: Date, sessions: Int64, input: Int64, output: Int64, cost: Double,
         daily: [Day], models: [Model], tools: [ToolCount],
         costDaily: [CostDay],
         sessionList: [SessionRow],
         totalInput: Int64, totalOutput: Int64, totalCost: Double) {
        self.writtenAt = writtenAt
        self.sessions = sessions
        self.input = input
        self.output = output
        self.cost = cost
        self.daily = daily
        self.models = models
        self.tools = tools
        self.costDaily = costDaily
        self.sessionList = sessionList
        self.totalInput = totalInput
        self.totalOutput = totalOutput
        self.totalCost = totalCost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writtenAt = try c.decode(Date.self, forKey: .writtenAt)
        sessions = try c.decode(Int64.self, forKey: .sessions)
        input = try c.decode(Int64.self, forKey: .input)
        output = try c.decode(Int64.self, forKey: .output)
        cost = try c.decode(Double.self, forKey: .cost)
        daily = try c.decode([Day].self, forKey: .daily)
        models = try c.decode([Model].self, forKey: .models)
        tools = try c.decodeIfPresent([ToolCount].self, forKey: .tools) ?? []
        costDaily = try c.decodeIfPresent([CostDay].self, forKey: .costDaily) ?? []
        sessionList = try c.decodeIfPresent([SessionRow].self, forKey: .sessionList) ?? []
        totalInput = try c.decode(Int64.self, forKey: .totalInput)
        totalOutput = try c.decode(Int64.self, forKey: .totalOutput)
        totalCost = try c.decode(Double.self, forKey: .totalCost)
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
