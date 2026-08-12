import Foundation

public enum DockerParser {
    /// Joins `docker ps` identity rows (name|image|status) with `docker stats`
    /// usage rows (name|cpu%|mem%). ps is the identity source; stats-only
    /// names are dropped; a ps row missing from stats keeps nil percentages.
    /// Empty ps output → `.noContainers` (non-zero exit is mapped to
    /// `.unavailable` by the caller, which owns process execution).
    public static func parseContainers(psOutput: String, statsOutput: String) -> (containers: [ContainerInfo], state: DockerState) {
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
    public static func parsePercent(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("%") else { return nil }
        let value = trimmed.dropLast()
        guard !value.isEmpty, value.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Double(value)
    }
}
