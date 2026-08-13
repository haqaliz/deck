import Foundation

// MARK: - Models

public enum ClipKind: String, Codable, Equatable {
    case text
    case image
    case file
    case other
}

public struct ClipItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let kind: ClipKind
    public let preview: String
    public let detail: String
    /// Full text for text items, capped at 4096 chars; nil otherwise.
    public let content: String?

    public init(id: UUID, date: Date, kind: ClipKind, preview: String, detail: String, content: String?) {
        self.id = id
        self.date = date
        self.kind = kind
        self.preview = preview
        self.detail = detail
        self.content = content
    }

    /// Builds an item from raw pasteboard data, applying the text cap and
    /// computing the preview/detail strings (pure, testable).
    public static func make(kind: ClipKind, content: String?, detail: String?, date: Date) -> ClipItem {
        let stored: String?
        switch kind {
        case .text:
            stored = content.map { String($0.prefix(4096)) }
        case .file:
            stored = content
        case .image, .other:
            stored = nil
        }
        let (preview, computedDetail) = ClipPreview.make(kind: kind, content: content, detail: detail)
        return ClipItem(
            id: UUID(),
            date: date,
            kind: kind,
            preview: preview,
            detail: computedDetail,
            content: stored
        )
    }
}

// MARK: - Classification

public enum ClipClassifier {
    private static let textTypes: Set<String> = [
        "public.string",
        "public.utf8-plain-text",
        "public.utf16-plain-text",
        "public.rtf",
        "public.html",
        "com.apple.traditional-mac-plain-text",
    ]
    private static let imageTypes: Set<String> = [
        "public.tiff",
        "public.png",
        "public.jpeg",
        "com.apple.icns",
    ]

    /// Classifies a pasteboard type list (raw identifiers) into a kind.
    /// Precedence: file > text > image > other.
    public static func kind(for types: [String]) -> ClipKind {
        let set = Set(types)
        if set.contains("public.file-url") { return .file }
        if !set.isDisjoint(with: textTypes) { return .text }
        if !set.isDisjoint(with: imageTypes) { return .image }
        return .other
    }
}

// MARK: - Preview formatting

public enum ClipPreview {
    /// Pure preview/detail computation for an item (empty detail allowed).
    public static func make(kind: ClipKind, content: String?, detail: String?) -> (preview: String, detail: String) {
        switch kind {
        case .text:
            let line = firstLine(content)
            return (truncate(line, to: 80), "")
        case .image:
            return ("Image", detail ?? "")
        case .file:
            let url = content ?? detail ?? ""
            return (lastPathComponent(url), url)
        case .other:
            return ("Other", "")
        }
    }

    public static func sizeString(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(max(bytes, 0))
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) B" }
        return String(format: "%.1f %@", value, units[unit])
    }

    private static func firstLine(_ content: String?) -> String {
        guard let content, !content.isEmpty else { return "" }
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
    }

    private static func truncate(_ string: String, to limit: Int) -> String {
        guard string.count > limit else { return string }
        return String(string.prefix(max(limit - 1, 0))) + "…"
    }

    private static func lastPathComponent(_ urlString: String) -> String {
        guard !urlString.isEmpty else { return "" }
        let trimmed = urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString
        return trimmed.split(separator: "/").last.map(String.init) ?? urlString
    }
}

// MARK: - History merge

public enum ClipHistory {
    /// Dedupe key for an item: text → content, file → content (URL),
    /// image → detail (size), other → nil (never deduped).
    public static func dedupeKey(_ item: ClipItem) -> String? {
        switch item.kind {
        case .text, .file:
            return item.content
        case .image:
            return item.detail.isEmpty ? nil : item.detail
        case .other:
            return nil
        }
    }

    /// Merges a new item into the history: refreshes the top item when it
    /// matches, moves a matching older item to the top, otherwise prepends.
    /// Trims to `maxCount`.
    public static func merge(existing: [ClipItem], new: ClipItem, maxCount: Int) -> [ClipItem] {
        guard maxCount > 0 else { return [] }
        let key = dedupeKey(new)

        var history = existing
        if let key, let matchIndex = history.firstIndex(where: { dedupeKey($0) == key }) {
            history.remove(at: matchIndex)
            history.insert(new, at: 0)
            return Array(history.prefix(maxCount))
        }
        history.insert(new, at: 0)
        return Array(history.prefix(maxCount))
    }
}
