import Foundation

public enum Formatters {
    public static func portLabel(host: String, port: Int) -> String {
        "\(host):\(port)"
    }

    public static func percentString(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }
}
