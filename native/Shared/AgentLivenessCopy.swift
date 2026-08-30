import Foundation

/// What the General tab says when an agent is registered and not running.
///
/// Pure, and in `Shared` rather than inside the view, because it is this
/// feature's only user-visible surface and the previous version could not be
/// asserted on at all — it lived in a private SwiftUI view, so its honesty
/// rested entirely on review.
enum AgentLivenessCopy {
    /// Names the half that stopped, and says what is still working.
    ///
    /// Naming the working half is not padding: the user is looking at a desktop
    /// where some widgets are visibly fine, and a notice that seemed to
    /// contradict the screen would read as the notice being wrong. Never names
    /// a launchd label — the user cannot act on one, and the Restart button
    /// beside this text is what does the acting.
    static func notice(for down: AgentLiveness.Down, relativeTo now: Date = Date()) -> String {
        scope(down.scope) + " " + evidence(down.reported, relativeTo: now)
    }

    private static func scope(_ scope: AgentLiveness.Down.Scope) -> String {
        switch scope {
        case .both:
            return "Background refresh has stopped. Deck's agents are registered "
                + "but macOS is not running them."
        case .data:
            return "Widget data has stopped refreshing. Deck's data agent is registered "
                + "but macOS is not running it. LiveBox is still updating."
        case .processes:
            return "LiveBox's process rows have stopped refreshing. Deck's process agent "
                + "is registered but macOS is not running it. Other widget data is "
                + "still updating."
        }
    }

    private static func evidence(_ evidence: AgentEvidence, relativeTo now: Date) -> String {
        switch evidence {
        case .ran(let at):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Last refresh: \(formatter.localizedString(for: at, relativeTo: now))."
        case .never:
            return "No refresh has been recorded."
        case .unreadable:
            // Something wrote that file. Claiming no refresh was ever recorded
            // would be a false statement about the machine, which is the whole
            // reason absent and unreadable are different answers.
            return "The last refresh could not be read."
        }
    }
}
