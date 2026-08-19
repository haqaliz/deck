import Foundation

// MARK: - Top processes snapshot
//
// The sandboxed widget extension cannot read other processes (ps is denied,
// proc_listpids/proc_pidinfo get the process killed). The host app samples
// processes and writes this snapshot into the container; the LiveBox widget
// reads it.

struct TopProcess: Codable, Equatable {
    let name: String
    let cpuPercent: Double
    let memPercent: Double
}

struct ProcessSnapshot: Codable, Equatable {
    var writtenAt: Date
    var processes: [TopProcess]

    /// Max age of a snapshot the widget still renders, given the process
    /// refresh interval. Tolerates one missed fast-agent tick; floors at 30s.
    static func maxAgeSeconds(for interval: Int) -> TimeInterval {
        TimeInterval(max(2 * interval, 30))
    }
}

enum ProcessSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("processes.json")
    }

    static func load(from url: URL = fileURL) -> ProcessSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProcessSnapshot.self, from: data)
    }

    static func save(_ snapshot: ProcessSnapshot, to url: URL = fileURL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: url)
    }
}

/// Top processes from `ps` — runs only in the unsandboxed host/agent.
enum HostProcessSampler {
    static func top(limit: Int) -> [TopProcess] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "comm=,%cpu=,%mem="]
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return PsParser.parse(text)
            .prefix(limit)
            .map { $0 }
    }
}

enum PsParser {
    /// Parses `ps -Aceo comm=,%cpu=,%mem=` output. %cpu/%mem are the last two
    /// whitespace tokens; comm is a full executable path that may contain
    /// spaces, so it is parsed right-anchored.
    static func parse(_ raw: String) -> [TopProcess] {
        raw
            .split(separator: "\n")
            .compactMap { row -> TopProcess? in
                let parts = row.split(whereSeparator: { $0 == " " }).filter { !$0.isEmpty }
                guard parts.count >= 3 else { return nil }
                let cpu = Double(parts[parts.count - 2]) ?? 0
                let mem = Double(parts[parts.count - 1]) ?? 0
                let path = parts[0..<parts.count - 2].joined(separator: " ")
                return TopProcess(
                    name: NSString(string: String(path)).lastPathComponent,
                    cpuPercent: cpu,
                    memPercent: mem
                )
            }
            .sorted { $0.cpuPercent > $1.cpuPercent }
    }
}
