import Foundation

// MARK: - TaskBox custom condition (pure)
//
// The user writes only the WHERE condition. Deck owns everything around it —
// SELECT, FROM WorkItems, the project clause and ORDER BY — so link queries
// (which answer `workItemRelations`, not `workItems`) and a user ORDER BY are
// impossible by construction rather than parsed around.
//
// Wrapping the condition in parentheses does not keep it there. Measured
// against a live org: `'Active') OR ([System.Id] > 0` inside our `AND ( … )`
// closes the wrapper early, the project clause stops applying, and the query
// returned 7559 items from the whole organization instead of one project's.
// So a condition is validated before it is ever sent, on both the settings
// and the agent path.

enum WiqlClause {
    enum Problem: Equatable {
        /// A `)` closes more than was opened — the escape above — or a `(` is
        /// never closed.
        case unbalancedParentheses
        case unterminatedLiteral
        case unterminatedField
        /// A word Deck adds itself, or one that would make this more than a
        /// condition.
        case reservedKeyword(String)
        case tooLong

        /// The settings caption under the field.
        var message: String {
            switch self {
            case .unbalancedParentheses:
                "Unbalanced parentheses. Every ( needs a matching ), outside quotes."
            case .unterminatedLiteral:
                "A quoted value is never closed. Write a quote inside a value as ''."
            case .unterminatedField:
                "A [field name] is never closed."
            case .reservedKeyword(let word):
                "\(word) is added by Deck. Write only the condition."
            case .tooLong:
                "The condition is longer than \(WiqlClause.maxLength) characters."
            }
        }
    }

    /// Far inside WIQL's own 32K limit, and far past any hand-written condition.
    static let maxLength = 4000

    /// Today's filter, unchanged: open items assigned to whoever owns the PAT.
    /// `@Me` is the PAT's owner — not whoever is signed in to the browser or the
    /// az CLI.
    static let builtInCondition =
        "[System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed', 'Removed', 'Done')"

    /// Checked in this order and whole-word, case-insensitive, outside literals
    /// and field names — so `CONTAINS 'order by'` and `[Custom.FromDate]` pass.
    private static let reserved: [(words: [String], name: String)] = [
        (["ORDER", "BY"], "ORDER BY"),
        (["ASOF"], "ASOF"),
        (["MODE"], "MODE"),
        (["SELECT"], "SELECT"),
        (["FROM"], "FROM"),
    ]

    static func isCustom(_ condition: String) -> Bool {
        !trimmed(condition).isEmpty
    }

    /// `[System.TeamProject] = @project` is load-bearing: the project in the
    /// request URL only sets the macro context, and without the clause the
    /// query spans every project the PAT can read (67 items across three
    /// projects instead of the configured one's 25).
    static func query(for condition: String) -> String {
        let body = isCustom(condition) ? trimmed(condition) : builtInCondition
        return "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project "
            + "AND (\(body)) ORDER BY [System.ChangedDate] DESC"
    }

    /// nil means the condition may be sent. Empty is valid and means the
    /// built-in filter.
    static func validate(_ condition: String) -> Problem? {
        let text = trimmed(condition)
        guard text.count <= maxLength else { return .tooLong }

        enum State { case normal, literal, field }
        var state = State.normal
        var depth = 0
        var words: [String] = []
        var word = ""

        func endWord() {
            if !word.isEmpty { words.append(word.uppercased()) }
            word = ""
        }

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch state {
            case .literal:
                if c == "'" {
                    // `''` is WIQL's escape for a quote inside a value.
                    if i + 1 < chars.count, chars[i + 1] == "'" { i += 1 } else { state = .normal }
                }
            case .field:
                if c == "]" { state = .normal }
            case .normal:
                if c.isLetter || c.isNumber || c == "_" {
                    word.append(c)
                } else {
                    endWord()
                    // A literal or a field is a word boundary that the
                    // keyword check must not see across.
                    if c == "'" || c == "[" { words.append("") }
                    switch c {
                    case "'": state = .literal
                    case "[": state = .field
                    case "(": depth += 1
                    case ")":
                        depth -= 1
                        if depth < 0 { return .unbalancedParentheses }
                    default: break
                    }
                }
            }
            i += 1
        }
        endWord()

        switch state {
        case .literal: return .unterminatedLiteral
        case .field: return .unterminatedField
        case .normal: break
        }
        if depth != 0 { return .unbalancedParentheses }

        for (sequence, name) in reserved where contains(words, sequence) {
            return .reservedKeyword(name)
        }
        return nil
    }

    private static func contains(_ words: [String], _ sequence: [String]) -> Bool {
        guard words.count >= sequence.count else { return false }
        for start in 0...(words.count - sequence.count)
        where Array(words[start..<start + sequence.count]) == sequence {
            return true
        }
        return false
    }

    private static func trimmed(_ condition: String) -> String {
        condition.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
