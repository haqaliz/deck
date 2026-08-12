import Foundation

public struct PortInfo: Equatable {
    public let command: String
    public let host: String
    public let port: Int

    public init(command: String, host: String, port: Int) {
        self.command = command
        self.host = host
        self.port = port
    }
}

public struct ContainerInfo: Equatable {
    public let name: String
    public let image: String
    public let status: String
    public let cpuPercent: Double?
    public let memPercent: Double?

    public init(name: String, image: String, status: String, cpuPercent: Double?, memPercent: Double?) {
        self.name = name
        self.image = image
        self.status = status
        self.cpuPercent = cpuPercent
        self.memPercent = memPercent
    }
}

public enum DockerState: Equatable {
    case unavailable
    case noContainers
    case running
}
