import XCTest

/// What the General tab is allowed to say about a `.down` verdict.
///
/// Pure and in `Shared` for one reason: the previous version of this wording
/// lived inside a private SwiftUI view and could not be asserted on at all, so
/// the notice's honesty rested on review. It is the only user-visible surface
/// this feature has.
final class AgentLivenessCopyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var recent: AgentEvidence { .ran(at: Date(timeIntervalSince1970: 1_700_000_000 - 60)) }
    private var old: AgentEvidence { .ran(at: Date(timeIntervalSince1970: 1_700_000_000 - 21_600)) }

    private func notice(
        _ scope: AgentLiveness.Down.Scope,
        processes: AgentEvidence,
        data: AgentEvidence
    ) -> String {
        AgentLivenessCopy.notice(
            for: AgentLiveness.Down(scope: scope, processes: processes, data: data),
            relativeTo: now
        )
    }

    // MARK: Scope

    /// Unchanged from the single-witness release: one fault, one sentence.
    func testBothDownKeepsTheOriginalWording() {
        XCTAssertTrue(
            notice(.both, processes: old, data: old)
                .hasPrefix("Background refresh has stopped. Deck's agents are registered "
                           + "but macOS is not running them."),
            "both-down wording changed"
        )
    }

    /// The case this feature exists for. Saying "LiveBox is still updating"
    /// matters: the user is looking at a widget that visibly works, and a notice
    /// that contradicted the screen would read as the notice being wrong.
    func testDataAgentDownNamesTheDataAgentAndAcquitsLiveBox() {
        let text = notice(.data, processes: recent, data: old)
        XCTAssertTrue(text.hasPrefix("Widget data has stopped refreshing."), text)
        XCTAssertTrue(text.contains("data agent"), text)
        XCTAssertTrue(text.contains("LiveBox is still updating."), text)
    }

    func testProcessAgentDownNamesTheProcessAgentAndAcquitsTheRest() {
        let text = notice(.processes, processes: old, data: recent)
        XCTAssertTrue(text.hasPrefix("LiveBox's process rows have stopped refreshing."), text)
        XCTAssertTrue(text.contains("process agent"), text)
        XCTAssertTrue(text.contains("Other widget data is still updating."), text)
    }

    /// A launchd label is not user-facing text. The user has no way to act on
    /// one, and the tab already has a Restart button that does the acting.
    func testNoWordingNamesALaunchdLabel() {
        for scope in [AgentLiveness.Down.Scope.both, .data, .processes] {
            let text = notice(scope, processes: old, data: old)
            XCTAssertFalse(text.contains("com.deck"), text)
        }
    }

    // MARK: The evidence sentence

    func testATimestampIsReportedAsALastRefresh() {
        XCTAssertTrue(
            notice(.data, processes: recent, data: old).contains("Last refresh:"),
            "a known last refresh must be stated"
        )
    }

    func testNoEvidenceAtAllSaysNothingWasRecorded() {
        XCTAssertTrue(
            notice(.both, processes: .never, data: .never)
                .hasSuffix("No refresh has been recorded."),
            notice(.both, processes: .never, data: .never)
        )
    }

    /// The corrupt-vs-absent split, at its only user-visible point. A file that
    /// exists but will not decode was written by something, so claiming no
    /// refresh was ever recorded is a false statement about the machine.
    func testAnUnreadableWitnessSaysSoRatherThanClaimingNothingRan() {
        let text = notice(.both, processes: .unreadable, data: .unreadable)
        XCTAssertTrue(text.hasSuffix("The last refresh could not be read."), text)
        XCTAssertFalse(text.contains("No refresh has been recorded"), text)
    }

    /// The reported evidence follows the verdict's own ordering, so a scoped
    /// fault never quotes the healthy agent's refresh as though it were the
    /// stopped one's.
    func testAScopedFaultQuotesItsOwnAgentsEvidence() {
        XCTAssertTrue(
            notice(.data, processes: recent, data: .never)
                .hasSuffix("No refresh has been recorded."),
            "the data agent never ran; the process agent's recent refresh is not the answer"
        )
    }
}
