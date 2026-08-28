import XCTest

/// One decision table for "should this slot fetch, and if not, what does the
/// widget say?", so the agent and the host app cannot drift apart.
///
/// The distinction the whole keychain feature rests on lives here: a locked
/// keychain is `unavailable`, not `notConfigured`. Collapsing them tells the
/// user to paste a token they already pasted.
final class CredentialGateTests: XCTestCase {

    private func settings(
        kind: CredentialKind,
        token: String = "tok",
        organization: String = "",
        project: String = "",
        projects: [String]? = nil,
        serverURL: String = "",
        on slot: CredentialSlot
    ) -> DeckSettings {
        var s = DeckSettings()
        var account = CredentialAccount(id: "a1", kind: kind, label: "x")
        account.token = token
        account.organization = organization
        account.projects = projects ?? (project.isEmpty ? [] : [project])
        account.serverURL = serverURL
        s.credentials.accounts = [account]
        s.setAccountID("a1", for: slot)
        return s
    }

    // MARK: - Fetch

    func testAHealthySlotFetches() {
        let s = settings(kind: .github, on: .shipbox)

        XCTAssertEqual(s.gate(.shipbox, unavailable: []), .fetch(ResolvedCredential(token: "tok")))
    }

    func testAzureNeedsItsOrganizationAndProject() {
        let complete = settings(kind: .azure, organization: "acme", project: "Manifold", on: .taskbox)
        XCTAssertEqual(
            complete.gate(.taskbox, unavailable: []),
            .fetch(ResolvedCredential(token: "tok", organization: "acme", projects: ["Manifold"]))
        )

        let noProject = settings(kind: .azure, organization: "acme", on: .taskbox)
        XCTAssertEqual(noProject.gate(.taskbox, unavailable: []), .notConfigured)

        let noOrg = settings(kind: .azure, project: "Manifold", on: .taskbox)
        XCTAssertEqual(noOrg.gate(.taskbox, unavailable: []), .notConfigured)
    }

    func testAzureFieldsOfWhitespaceAreNotFields() {
        let s = settings(kind: .azure, organization: "  ", project: "Manifold", on: .taskbox)

        XCTAssertEqual(s.gate(.taskbox, unavailable: []), .notConfigured)
    }

    func testTheAzureCredentialIsHandedOverTrimmed() {
        let s = settings(kind: .azure, organization: " acme ", project: " Manifold ", on: .taskbox)

        XCTAssertEqual(
            s.gate(.taskbox, unavailable: []),
            .fetch(ResolvedCredential(token: "tok", organization: "acme", projects: ["Manifold"]))
        )
    }

    // MARK: - Unavailable is not unconfigured

    func testALockedKeychainIsItsOwnAnswer() {
        let s = settings(kind: .github, token: "", on: .shipbox)

        XCTAssertEqual(s.gate(.shipbox, unavailable: ["a1"]), .unavailable)
    }

    func testAnUnavailableCredentialWinsOverEveryOtherComplaint() {
        // An Azure account that is both unreadable and missing its project is
        // unreadable first: fix the keychain, then see what else is wrong.
        let s = settings(kind: .azure, token: "", organization: "acme", on: .taskbox)

        XCTAssertEqual(s.gate(.taskbox, unavailable: ["a1"]), .unavailable)
    }

    func testAnotherAccountsFailureIsNotThisSlotsProblem() {
        let s = settings(kind: .github, on: .shipbox)

        XCTAssertEqual(s.gate(.shipbox, unavailable: ["somebody-else"]), .fetch(ResolvedCredential(token: "tok")))
    }

    // MARK: - Off vs not configured

    func testNothingSelectedIsOffNotBroken() {
        // "Off" is what lets PRBox clear a failure a provider left behind
        // instead of reporting it forever.
        XCTAssertEqual(DeckSettings().gate(.prboxGitHub, unavailable: []), .off)
    }

    func testADeletedAccountIsNotConfiguredNotOff() {
        // The user pointed this slot at something. It is gone. That is a
        // problem to report, not a switch they turned off.
        var s = DeckSettings()
        s.shipbox.accountID = "gone"

        XCTAssertEqual(s.gate(.shipbox, unavailable: []), .notConfigured)
    }

    func testAnAccountOfTheWrongKindIsNotConfigured() {
        var s = settings(kind: .azure, on: .taskbox)
        s.shipbox.accountID = "a1"

        XCTAssertEqual(s.gate(.shipbox, unavailable: []), .notConfigured)
    }

    func testAnAccountWithNoTokenIsNotConfigured() {
        let s = settings(kind: .github, token: "", on: .shipbox)

        XCTAssertEqual(s.gate(.shipbox, unavailable: []), .notConfigured)
    }

    // MARK: - The pre-migration file

    func testAnUnmigratedSlotStillFetches() {
        var s = DeckSettings()
        s.shipbox.token = "ghp"

        XCTAssertEqual(s.gate(.shipbox, unavailable: []), .fetch(ResolvedCredential(token: "ghp")))
    }

    func testAnUnmigratedSlotWithNothingStoredIsOff() {
        XCTAssertEqual(DeckSettings().gate(.shipbox, unavailable: []), .off)
    }

    // MARK: - A locked keychain before the migration has run

    func testAnUnreadableLegacyItemIsUnavailableToo() {
        // DeckAgent can run for weeks on an unmigrated file. A locked keychain
        // must read the same there as it does afterwards.
        var s = DeckSettings()
        s.shipbox.token = ""

        XCTAssertEqual(
            s.gate(.shipbox, unavailableAccounts: [], unavailableLegacySecrets: [.shipboxToken]),
            .unavailable
        )
    }

    func testALegacyFailureIsIgnoredOnceTheSlotHasAnAccount() {
        let s = settings(kind: .github, on: .shipbox)

        XCTAssertEqual(
            s.gate(.shipbox, unavailableAccounts: [], unavailableLegacySecrets: [.shipboxToken]),
            .fetch(ResolvedCredential(token: "tok"))
        )
    }

    // MARK: - The outcome each answer records

    func testEveryNonFetchAnswerKnowsWhatToRecord() {
        XCTAssertEqual(CredentialGate.unavailable.outcome, .credentialsUnavailable)
        XCTAssertEqual(CredentialGate.notConfigured.outcome, .notConfigured)
        // A provider that is simply switched off records `ok`, which is what
        // clears a stale failure from when it was on.
        XCTAssertEqual(CredentialGate.off.outcome, .ok)
        XCTAssertNil(CredentialGate.fetch(ResolvedCredential(token: "t")).outcome)
    }

    // MARK: - Several projects

    func testEveryConfiguredProjectReachesTheLoader() {
        let s = settings(
            kind: .azure, organization: "acme",
            projects: ["ForesightManifold", "Manifold Ops"], on: .taskbox
        )

        XCTAssertEqual(
            s.gate(.taskbox, unavailable: []),
            .fetch(ResolvedCredential(
                token: "tok", organization: "acme",
                projects: ["ForesightManifold", "Manifold Ops"]
            ))
        )
    }

    func testAnAccountWithNoUsableProjectIsNotConfigured() {
        // An organization without a project is half a target; the loader would
        // only fail later with something less legible.
        let s = settings(kind: .azure, organization: "acme", projects: ["", "  "], on: .taskbox)

        XCTAssertEqual(s.gate(.taskbox, unavailable: []), .notConfigured)
    }

    func testTheProjectListIsNormalisedOnTheWayThrough() {
        // The gate is the last gate: a duplicate reaching a loader would double
        // every row that project owns, and a sixth would blow the slot budget.
        let s = settings(
            kind: .azure, organization: "acme",
            projects: [" Manifold Ops ", "manifold ops", "p3", "p4", "p5", "p6"],
            on: .prboxAzure
        )

        XCTAssertEqual(
            s.gate(.prboxAzure, unavailable: []),
            .fetch(ResolvedCredential(
                token: "tok", organization: "acme",
                projects: ["Manifold Ops", "p3", "p4", "p5", "p6"]
            ))
        )
    }

    func testALegacyProjectStringStillFetchesAsAOneElementList() {
        // A Deck upgraded but never opened runs on a file the migration has not
        // touched; the pre-accounts field must still name one project.
        var s = DeckSettings()
        s.taskbox.token = "tok"
        s.taskbox.organization = "acme"
        s.taskbox.project = "ForesightManifold"

        XCTAssertEqual(
            s.gate(.taskbox, unavailable: []),
            .fetch(ResolvedCredential(
                token: "tok", organization: "acme", projects: ["ForesightManifold"]
            ))
        )
    }
}
