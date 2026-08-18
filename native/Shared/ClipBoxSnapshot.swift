import Foundation
import AppKit

// MARK: - ClipBox snapshot
//
// The clipboard belongs to other apps — blocked in the sandboxed widget — so
// the host agent reads NSPasteboard and writes this snapshot into the
// container. The ClipBox widget renders it. History accumulates in the
// snapshot file (dedupe + trim applied by the sampler).

enum ClipKind: String, Codable, Equatable {
    case text
    case image
    case file
    case other
}

struct ClipItem: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let kind: ClipKind
    let preview: String
    let detail: String
    /// Full text for text items (capped at 4096 chars) or the file URL;
    /// nil for image/other items.
    let content: String?
}

struct ClipBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    var items: [ClipItem]
}

enum ClipBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("clipbox.json")
    }

    static func load() -> ClipBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ClipBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: ClipBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }

    /// Purges the history (Clear history in the ClipBox settings tab).
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Reads the pasteboard and merges into the stored history — host/agent only
/// (unsandboxed).
enum HostClipBoardSampler {
    /// Rebuilds the snapshot from the current pasteboard state. Always
    /// returns a snapshot with a fresh `writtenAt` (cheap rewrite keeps the
    /// widget's staleness window honest); `nil` only when the pasteboard is
    /// unreadable at all.
    static func snapshot(maxCount: Int) -> ClipBoxSnapshot? {
        let pasteboard = NSPasteboard.general
        guard let typeIdentifiers = pasteboard.types?.map(\.rawValue) else { return nil }
        let kind = ClipClassifier.kind(for: typeIdentifiers)

        let previous = ClipBoxSnapshotStore.load()?.items ?? []
        guard let item = makeItem(from: pasteboard, kind: kind) else {
            // Nothing readable (empty or unrecognized pasteboard): refresh
            // the timestamp but keep the existing history untouched.
            return ClipBoxSnapshot(writtenAt: Date(), items: previous)
        }
        let merged = ClipHistory.merge(existing: previous, new: item, maxCount: maxCount)
        return ClipBoxSnapshot(writtenAt: Date(), items: merged)
    }

    private static func makeItem(from pasteboard: NSPasteboard, kind: ClipKind) -> ClipItem? {
        let date = Date()
        switch kind {
        case .text:
            guard let string = pasteboard.string(forType: .string), !string.isEmpty else { return nil }
            return ClipItem.make(kind: .text, content: string, detail: nil, date: date)
        case .file:
            guard let url = pasteboard.string(forType: .fileURL), !url.isEmpty else { return nil }
            return ClipItem.make(kind: .file, content: url, detail: nil, date: date)
        case .image:
            let data = pasteboard.data(forType: .tiff)
                ?? pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
            guard let data else { return nil }
            return ClipItem.make(kind: .image, content: nil, detail: ClipPreview.sizeString(data.count), date: date)
        case .other:
            return nil
        }
    }
}

// MARK: - Pure logic (ported from ClipBoxCore)

enum ClipClassifier {
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
    static func kind(for types: [String]) -> ClipKind {
        let set = Set(types)
        if set.contains("public.file-url") { return .file }
        if !set.isDisjoint(with: textTypes) { return .text }
        if !set.isDisjoint(with: imageTypes) { return .image }
        return .other
    }
}

enum ClipPreview {
    /// Pure preview/detail computation for an item (empty detail allowed).
    static func make(kind: ClipKind, content: String?, detail: String?) -> (preview: String, detail: String) {
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

    static func sizeString(_ bytes: Int) -> String {
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

enum ClipHistory {
    /// Dedupe key for an item: text → content, file → content (URL),
    /// image → detail (size), other → nil (never deduped).
    static func dedupeKey(_ item: ClipItem) -> String? {
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
    /// Trims to `maxCount`. History is newest-first (index 0 = newest).
    static func merge(existing: [ClipItem], new: ClipItem, maxCount: Int) -> [ClipItem] {
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

extension ClipItem {
    /// Builds an item from raw pasteboard data, applying the text cap and
    /// computing the preview/detail strings (pure, testable).
    static func make(kind: ClipKind, content: String?, detail: String?, date: Date) -> ClipItem {
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
