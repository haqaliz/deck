import Foundation

// MARK: - DevBox snapshot
//
// lsof and docker are subprocesses — blocked in the sandboxed widget — so the
// host agent samples them and writes this snapshot into the container. The
// DevBox widget renders it.

struct PortInfo: Codable, Equatable {
    let command: String
    let host: String
    let port: Int
}

struct ContainerInfo: Codable, Equatable {
    let name: String
    let image: String
    let status: String
    let cpuPercent: Double?
    let memPercent: Double?
}

enum DockerState: String, Codable, Equatable {
    case unavailable
    case noContainers
    case running
}

struct DevBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    var ports: [PortInfo]
    var containers: [ContainerInfo]
    var dockerState: DockerState
}

enum DevBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("devbox.json")
    }

    static func load() -> DevBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DevBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: DevBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}

/// Runs lsof/docker — host/agent only (unsandboxed).
enum HostDevBoxSampler {
    /// Full snapshot; nil only when both lsof and docker are unreadable
    /// (environment problem — the widget then shows its unavailable card).
    static func snapshot() -> DevBoxSnapshot? {
        let portsResult = run("/usr/sbin/lsof", ["-nP", "-F", "-iTCP", "-sTCP:LISTEN"])
        let ports = portsResult.flatMap { LsofParser.parse($0) } ?? []

        let psResult = run("/usr/bin/env", ["docker", "ps", "--format", "{{.Names}}|{{.Image}}|{{.Status}}"])
        let statsResult = run("/usr/bin/env", ["docker", "stats", "--no-stream", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}"])

        let dockerState: DockerState
        if let psOutput = psResult, !psOutput.isEmpty {
            dockerState = .running
        } else if psResult != nil {
            dockerState = .noContainers
        } else {
            dockerState = .unavailable
        }

        guard !ports.isEmpty || dockerState != .unavailable else { return nil }

        let containers: [ContainerInfo]
        if let psOutput = psResult {
            containers = DockerParser.parseContainers(
                psOutput: psOutput,
                statsOutput: statsResult ?? ""
            ).containers
        } else {
            containers = []
        }

        return DevBoxSnapshot(
            writtenAt: Date(),
            ports: ports,
            containers: containers,
            dockerState: dockerState
        )
    }

    /// Runs a process synchronously; returns stdout on exit 0, nil otherwise.
    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

// MARK: - Parsers (ported from DevBoxCore)

enum LsofParser {
    /// Parses `lsof -nP -F -iTCP -sTCP:LISTEN` field-mode output.
    /// `p<pid>` starts a process block, `c<command>` names it, `n<host>:<port>`
    /// emits a row. Rows deduplicated by (command, name), sorted by port asc.
    static func parse(_ raw: String) -> [PortInfo] {
        var command: String?
        var seen: [String: PortInfo] = [:]
        var order: [String] = []

        for line in raw.split(separator: "\n") {
            let token = String(line)
            guard !token.isEmpty else { continue }
            let value = token.dropFirst()
            switch token.first {
            case "c":
                command = String(value)
            case "n":
                guard let command, let port = port(from: String(value)) else { continue }
                let host = String(value.dropLast(String(port).count + 1))
                guard !host.isEmpty else { continue }
                let key = "\(command)|\(value)"
                if seen[key] == nil {
                    seen[key] = PortInfo(command: command, host: host, port: port)
                    order.append(key)
                }
            default:
                break
            }
        }

        return order
            .compactMap { seen[$0] }
            .sorted { $0.port != $1.port ? $0.port < $1.port : $0.command < $1.command }
    }

    /// Port is the integer after the last ":"; nil when absent or unparseable.
    private static func port(from name: String) -> Int? {
        guard let lastColon = name.lastIndex(of: ":") else { return nil }
        let tail = name[lastColon...].dropFirst()
        guard !tail.isEmpty, let port = Int(tail) else { return nil }
        return port
    }
}

enum DockerParser {
    /// Joins `docker ps` identity rows (name|image|status) with `docker stats`
    /// usage rows (name|cpu%|mem%). ps is the identity source; stats-only
    /// names are dropped; a ps row missing from stats keeps nil percentages.
    static func parseContainers(psOutput: String, statsOutput: String) -> (containers: [ContainerInfo], state: DockerState) {
        var stats: [String: (Double?, Double?)] = [:]
        for line in statsOutput.split(separator: "\n") where !line.isEmpty {
            let parts = line.split(separator: "|").map(String.init)
            guard parts.count >= 3 else { continue }
            stats[parts[0]] = (parsePercent(parts[1]), parsePercent(parts[2]))
        }

        var containers: [ContainerInfo] = []
        for line in psOutput.split(separator: "\n") where !line.isEmpty {
            let parts = line.split(separator: "|").map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0].split(separator: ",").first.map(String.init) ?? parts[0]
            let usage = stats[name]
            containers.append(ContainerInfo(
                name: name,
                image: parts[1],
                status: parts[2],
                cpuPercent: usage?.0,
                memPercent: usage?.1
            ))
        }

        return (containers, containers.isEmpty ? .noContainers : .running)
    }

    /// "0.05%" → 0.05; any garbage/missing → nil.
    static func parsePercent(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("%") else { return nil }
        let value = trimmed.dropLast()
        guard !value.isEmpty, value.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Double(value)
    }
}

enum Formatters {
    static func portLabel(host: String, port: Int) -> String {
        "\(host):\(port)"
    }

    static func percentString(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }
}
