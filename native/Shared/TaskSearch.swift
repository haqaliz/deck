import Foundation

// MARK: - TaskBox search
//
// Typed text becomes part of a WIQL query, which is the dangerous direction:
// a condition that closed its own parentheses once dropped the project clause
// and returned 7559 items from every project with a 200 (CLAUDE.md). So the
// text is only ever a *literal* — quotes doubled, control characters gone,
// length capped — and `TaskSearchTests` proves the query's shape cannot depend
// on what was typed.
//
// Unlike the widget's condition, nothing here filters by assignee or state:
// this is for finding any work item of any age.

enum TaskSearch {
    /// Far under WIQL's own limit, and longer than any title worth typing.
    static let maxTextLength = 100
    /// Work item ids are 32-bit; more digits than this is text, not an id.
    private static let maxIdDigits = 9

    /// Control characters out, whitespace collapsed, capped. What is left is
    /// safe to put inside a string literal once its quotes are doubled.
    static func sanitise(_ text: String) -> String {
        let cleaned = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || scalar.properties.isWhitespace
                ? " " : Character(scalar)
        }
        let collapsed = String(cleaned)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
        return String(collapsed.prefix(maxTextLength)).trimmingCharacters(in: .whitespaces)
    }

    /// The WIQL condition for a search, to be wrapped by `WiqlClause.query(for:)`.
    /// `nil` when there is too little to search for.
    ///
    /// `CONTAINS` on a string field is Azure's own matching; exactly how it
    /// treats partial words is measured in the probe, not assumed here.
    static func condition(for text: String) -> String? {
        let clean = sanitise(text)
        guard RemoteSearchPolicy.shouldSearch(clean) else { return nil }
        let literal = "'" + clean.replacingOccurrences(of: "'", with: "''") + "'"

        var condition = "[System.Title] CONTAINS \(literal) OR [System.Tags] CONTAINS \(literal)"
        // A whole number may also be a work item id. Digits only, so nothing
        // typed can reach this clause as anything but a number.
        if clean.count <= maxIdDigits, clean.allSatisfy({ $0.isASCII && $0.isNumber }) {
            condition += " OR [System.Id] = \(clean)"
        }
        return condition
    }
}

// MARK: - Results

extension TaskSearch {
    /// Azure's rows as panel results. **Nothing is filtered out here:** Azure
    /// decided these match, and a local matcher that disagrees about partial
    /// words must not drop them. The matcher only orders them.
    static func results(from tasks: [TaskItem], query: String) -> [SearchResult] {
        let text = sanitise(query)
        return tasks.map { task in
            let tagText = task.tags.joined(separator: " ")
            var score = 10
            if task.id == text { score = 1000 }
            if let title = SpotlightMatcher.score(query: text, in: task.title) { score = max(score, title) }
            // A tag hit is real but weaker than a title hit.
            if let tag = SpotlightMatcher.score(query: text, in: tagText) { score = max(score, tag / 2) }

            // The URL came from remote data, so it goes through the one
            // http(s)-with-a-host rule; a row that fails it can only be copied.
            let action: SpotlightAction = DeckLink.webURL(from: task.url).map(SpotlightAction.open)
                ?? .copy(task.id)

            let parts = [task.itemType, task.state, task.project ?? "", "#\(task.id)"]
                .filter { !$0.isEmpty }
            var subtitle = parts.joined(separator: " · ")
            if !task.tags.isEmpty { subtitle += " · " + task.tags.joined(separator: ", ") }

            return SearchResult(
                id: "task:\(task.project ?? ""):\(task.id)",
                provider: .task,
                title: task.title,
                subtitle: subtitle,
                score: score,
                action: action
            )
        }
    }
}
