import Foundation

// MARK: - TaskBox query presets (pure)
//
// Each preset is a complete WHERE condition for the Query field, replacing the
// draft exactly like the old "Start from default" button. Applying stays the
// user's decision: a preset never writes `settings.query` — the text lands in
// the draft and Apply is the only writer (custom-WIQL PRD A1).
//
// "Current sprint" may carry a team literal, `@CurrentIteration('[Project]\Team')`.
// Probed live: the literal takes the team's name (not its id), brackets are
// required, and it only answers for its own project — a different project
// answers 200 with 0 items (probe P17/P19/P20). That is why the team context
// is offered only for single-project accounts.

enum WiqlPreset: CaseIterable {
    case assignedToMe
    case createdByMe
    case currentSprint

    var title: String {
        switch self {
        case .assignedToMe: "Assigned to me"
        case .createdByMe: "Created by me"
        case .currentSprint: "Current sprint"
        }
    }

    /// The complete condition, with the shared open-state exclusion. `team` is
    /// non-nil only when the account has exactly one project and a team is
    /// chosen; the other presets ignore it.
    func condition(team: WiqlTeamContext?) -> String {
        switch self {
        case .assignedToMe:
            return WiqlClause.builtInCondition
        case .createdByMe:
            return "[System.CreatedBy] = @Me AND " + WiqlClause.openStates
        case .currentSprint:
            let macro = team.map { "@CurrentIteration('\($0.literal)')" } ?? "@CurrentIteration"
            return "[System.IterationPath] = \(macro) AND " + WiqlClause.openStates
        }
    }
}

/// The project + team a "Current sprint" preset names.
struct WiqlTeamContext: Equatable {
    var project: String
    var team: String

    /// `'[Project]\Team'` with quotes doubled — WIQL's literal escape, the
    /// same rule the validator follows for `'it''s'` (probe P14).
    var literal: String {
        "[\(escaped(project))]\\\(escaped(team))"
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
