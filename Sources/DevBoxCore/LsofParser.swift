import Foundation

public enum LsofParser {
    /// Parses `lsof -nP -F -iTCP -sTCP:LISTEN` field-mode output.
    /// `p<pid>` starts a process block, `c<command>` names it, `n<host>:<port>`
    /// emits a row. Rows deduplicated by (command, name), sorted by port asc.
    public static func parse(_ raw: String) -> [PortInfo] {
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
