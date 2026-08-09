import Foundation

/// Splits `provider/model-id-variant` (or `provider:model`) into
/// provider, id and variant. e.g. `opencode-go/deepseek-v4-flash-free`
/// → provider `opencode-go`, id `deepseek-v4`, variant `flash free`.
public enum ModelParser {
public static let variants: Set<String> = [
        "flash", "mini", "max", "pro", "sonnet", "opus", "haiku", "turbo",
        "free", "latest", "small", "large", "nano", "medium", "plus",
        "preview", "thinking", "lite", "ultra", "grande", "dash", "snap",
        "exp", "extended", "high", "low", "fast", "reasoning",
    ]

public static func parse(_ raw: String) -> (provider: String, id: String, variant: String?) {
        // 1. OpenCode stores the model as JSON: {"id":..., "providerID":..., "variant":...}
        if let data = raw.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var provider = (obj["providerID"] as? String) ?? "local"
            var id = (obj["id"] as? String) ?? raw
            let variant = obj["variant"] as? String

            // the id may carry its own vendor prefix: "qwen/qwen3.8-max"
            if let slash = id.firstIndex(of: "/") {
                provider += " · " + String(id[..<slash])
                id = String(id[id.index(after: slash)...])
            }
            return (provider: provider, id: id, variant: variant)
        }

        // 2. Fallback for plain `provider/model-id-variant` strings
        var provider = "local"
        var idPart = raw
        if let slash = raw.lastIndex(of: "/") {
            provider = String(raw[..<slash])
            idPart = String(raw[raw.index(after: slash)...])
        } else if let colon = raw.lastIndex(of: ":") {
            provider = String(raw[..<colon])
            idPart = String(raw[raw.index(after: colon)...])
        }

        let tokens = idPart.split(separator: "-").map(String.init)
        var idTokens = tokens
        var variantTokens: [String] = []

        while let last = idTokens.last, variants.contains(last.lowercased()) {
            variantTokens.insert(last, at: 0)
            idTokens.removeLast()
        }

        if variantTokens.isEmpty,
           let index = idTokens.firstIndex(where: { variants.contains($0.lowercased()) }) {
            variantTokens = [idTokens[index]]
            idTokens.remove(at: index)
        }

        return (
            provider: provider,
            id: idTokens.joined(separator: "-"),
            variant: variantTokens.isEmpty ? nil : variantTokens.joined(separator: " ")
        )
    }
}
