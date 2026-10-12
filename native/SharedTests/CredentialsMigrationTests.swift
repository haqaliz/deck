import XCTest

/// The one-way migration from the five welded `DeckSecret` fields to accounts.
///
/// Every test injects its keychain IO, so nothing here touches the real one.
/// The ordering under test — write → read back → assign → only then delete the
/// legacy item — is the property that stops a keychain failure from destroying
/// the only copy of a token.
final class CredentialsMigrationTests: XCTestCase {

    /// A fake keychain that starts holding the five legacy items.
    private final class Store {
        var accounts: [String: String] = [:]
        var legacy: Set<DeckSecret>
        var writeFails = false
        var readBackReturns: SecretRead?

        init(legacy: Set<DeckSecret>) { self.legacy = legacy }

        func write(_ id: String, _ value: String) -> OSStatus {
            if writeFails { return errSecIO }
            accounts[id] = value
            return errSecSuccess
        }

        func readBack(_ id: String) -> SecretRead {
            if let forced = readBackReturns { return forced }
            return accounts[id].map { .found($0) } ?? .absent
        }

        func deleteLegacy(_ secret: DeckSecret) -> OSStatus {
            legacy.remove(secret)
            return errSecSuccess
        }
    }

    private var ids = 0

    private func run(_ settings: inout DeckSettings, store: Store) -> Bool {
        ids = 0
        return CredentialsMigration.migrate(
            &settings,
            write: { store.write($0, $1) },
            readBack: { store.readBack($0) },
            deleteLegacy: { store.deleteLegacy($0) },
            makeID: { self.ids += 1; return "id\(self.ids)" }
        )
    }

    /// Settings as they arrive from a keychain-hydrated load: tokens in the
    /// legacy fields, no accounts.
    private func hydrated(
        openbox: String = "", serverURL: String? = nil,
        shipbox: String = "",
        taskbox: String = "", org: String = "", project: String = "",
        prGitHub: String = "", prGitHubEnabled: Bool = true,
        prAzure: String = "", prAzureEnabled: Bool = true,
        prOrg: String = "", prProject: String = ""
    ) -> DeckSettings {
        var s = DeckSettings()
        s.openbox.token = openbox
        s.openbox.serverURL = serverURL
        s.shipbox.token = shipbox
        s.taskbox.token = taskbox
        s.taskbox.organization = org
        s.taskbox.project = project
        s.prbox.github.token = prGitHub
        s.prbox.github.enabled = prGitHubEnabled
        s.prbox.azure.token = prAzure
        s.prbox.azure.enabled = prAzureEnabled
        s.prbox.azure.organization = prOrg
        s.prbox.azure.project = prProject
        return s
    }

    // MARK: - The happy path

    func testEachStoredTokenBecomesAnAccountTheSlotPointsAt() {
        var settings = hydrated(shipbox: "ghp_abc")
        let store = Store(legacy: [.shipboxToken])

        XCTAssertTrue(run(&settings, store: store))

        XCTAssertEqual(settings.credentials.accounts.count, 1)
        XCTAssertEqual(settings.account(for: .shipbox)?.token, "ghp_abc")
        XCTAssertEqual(store.accounts["id1"], "ghp_abc")
    }

    func testConnectionFieldsMoveOntoTheAccount() {
        var settings = hydrated(openbox: "tok", serverURL: "http://nuc:4096",
                                taskbox: "pat", org: "acme", project: "Manifold")
        let store = Store(legacy: [.openboxToken, .taskboxToken])

        run(&settings, store: store)

        XCTAssertEqual(settings.account(for: .openbox)?.serverURL, "http://nuc:4096")
        XCTAssertEqual(settings.account(for: .taskbox)?.organization, "acme")
        XCTAssertEqual(settings.account(for: .taskbox)?.projects, ["Manifold"])
    }

    func testTheLegacyItemIsDeletedOnlyAfterTheAccountIsConfirmed() {
        var settings = hydrated(shipbox: "ghp_abc")
        let store = Store(legacy: [.shipboxToken])

        run(&settings, store: store)

        XCTAssertTrue(store.legacy.isEmpty, "the legacy item is gone once the account holds the token")
    }

    func testTheLegacyFieldIsBlanked() {
        var settings = hydrated(shipbox: "ghp_abc")
        run(&settings, store: Store(legacy: [.shipboxToken]))

        XCTAssertEqual(settings.shipbox.token, "")
    }

    // MARK: - Dedupe

    func testOneGitHubTokenSharedByTwoWidgetsCollapsesIntoOneAccount() {
        // The concrete pain: today the same token is pasted twice.
        var settings = hydrated(shipbox: "ghp_same", prGitHub: "ghp_same")
        let store = Store(legacy: [.shipboxToken, .prboxGitHubToken])

        run(&settings, store: store)

        XCTAssertEqual(settings.credentials.accounts.count, 1)
        XCTAssertEqual(settings.accountID(for: .shipbox), settings.accountID(for: .prboxGitHub))
        XCTAssertTrue(store.legacy.isEmpty, "both legacy items are represented and both are gone")
    }

    func testTwoDifferentGitHubTokensStayTwoAccounts() {
        var settings = hydrated(shipbox: "ghp_one", prGitHub: "ghp_two")

        run(&settings, store: Store(legacy: [.shipboxToken, .prboxGitHubToken]))

        XCTAssertEqual(settings.credentials.accounts.count, 2)
        XCTAssertNotEqual(settings.accountID(for: .shipbox), settings.accountID(for: .prboxGitHub))
    }

    func testAzureAccountsWithTheSameTokenButDifferentProjectsDoNotCollapse() {
        // Same PAT, two projects, is two accounts — the ergonomic cost of
        // putting the project on the account.
        var settings = hydrated(taskbox: "pat", org: "acme", project: "Manifold",
                                prAzure: "pat", prOrg: "acme", prProject: "Foresight")

        run(&settings, store: Store(legacy: [.taskboxToken, .prboxAzureToken]))

        XCTAssertEqual(settings.credentials.accounts.count, 2)
    }

    func testAzureAccountsIdenticalInEveryFieldDoCollapse() {
        var settings = hydrated(taskbox: "pat", org: "acme", project: "Manifold",
                                prAzure: "pat", prOrg: "acme", prProject: "Manifold")

        run(&settings, store: Store(legacy: [.taskboxToken, .prboxAzureToken]))

        XCTAssertEqual(settings.credentials.accounts.count, 1)
    }

    // MARK: - R2: a provider that was switched off must stay switched off

    func testADisabledPRBoxProviderKeepsItsTokenButIsNotSelected() {
        var settings = hydrated(prGitHub: "ghp_abc", prGitHubEnabled: false)

        run(&settings, store: Store(legacy: [.prboxGitHubToken]))

        XCTAssertEqual(settings.credentials.accounts.count, 1, "the token is never lost")
        XCTAssertNil(settings.accountID(for: .prboxGitHub), "and the provider stays off")
    }

    func testADisabledProviderDoesNotStopItsAccountBeingSharedWithAnEnabledOne() {
        var settings = hydrated(shipbox: "ghp_same", prGitHub: "ghp_same", prGitHubEnabled: false)

        run(&settings, store: Store(legacy: [.shipboxToken, .prboxGitHubToken]))

        XCTAssertEqual(settings.credentials.accounts.count, 1)
        XCTAssertNotNil(settings.accountID(for: .shipbox))
        XCTAssertNil(settings.accountID(for: .prboxGitHub))
    }

    // MARK: - Failure leaves everything exactly as it was

    func testAFailedWriteChangesNothingAndDeletesNothing() {
        var settings = hydrated(shipbox: "ghp_abc")
        let store = Store(legacy: [.shipboxToken])
        store.writeFails = true

        XCTAssertFalse(run(&settings, store: store))

        XCTAssertTrue(settings.credentials.accounts.isEmpty)
        XCTAssertNil(settings.accountID(for: .shipbox))
        XCTAssertEqual(settings.shipbox.token, "ghp_abc", "the only copy is still here")
        XCTAssertEqual(store.legacy, [.shipboxToken])
    }

    func testAReadBackThatDisagreesChangesNothingAndDeletesNothing() {
        var settings = hydrated(shipbox: "ghp_abc")
        let store = Store(legacy: [.shipboxToken])
        store.readBackReturns = .found("something-else")

        XCTAssertFalse(run(&settings, store: store))

        XCTAssertTrue(settings.credentials.accounts.isEmpty)
        XCTAssertEqual(settings.shipbox.token, "ghp_abc")
        XCTAssertEqual(store.legacy, [.shipboxToken])
    }

    func testAFailedReadBackChangesNothing() {
        var settings = hydrated(shipbox: "ghp_abc")
        let store = Store(legacy: [.shipboxToken])
        store.readBackReturns = .failed(errSecInteractionNotAllowed)

        XCTAssertFalse(run(&settings, store: store))
        XCTAssertTrue(settings.credentials.accounts.isEmpty)
        XCTAssertEqual(store.legacy, [.shipboxToken])
    }

    // MARK: - Idempotence

    func testASecondRunIsANoOp() {
        var settings = hydrated(shipbox: "ghp_abc")
        let store = Store(legacy: [.shipboxToken])
        run(&settings, store: store)

        XCTAssertFalse(run(&settings, store: store))
        XCTAssertEqual(settings.credentials.accounts.count, 1)
    }

    func testSettingsThatAlreadyHaveAnAccountAreLeftAlone() {
        var settings = hydrated(shipbox: "ghp_abc")
        settings.credentials.accounts = [CredentialAccount(id: "existing", kind: .github, label: "mine")]

        XCTAssertFalse(run(&settings, store: Store(legacy: [.shipboxToken])))
        XCTAssertEqual(settings.credentials.accounts.map(\.id), ["existing"])
    }

    func testNothingStoredMeansNothingToDo() {
        var settings = DeckSettings()
        XCTAssertFalse(run(&settings, store: Store(legacy: [])))
        XCTAssertTrue(settings.credentials.accounts.isEmpty)
    }

    // MARK: - Labels

    func testAzureAccountsAreNamedAfterTheirOrganization() {
        var settings = hydrated(taskbox: "pat", org: "acme", project: "Manifold")
        run(&settings, store: Store(legacy: [.taskboxToken]))

        XCTAssertEqual(settings.account(for: .taskbox)?.label, "acme")
    }

    func testOpencodeAccountsAreNamedAfterTheirServerHost() {
        var settings = hydrated(openbox: "tok", serverURL: "http://nuc:4096")
        run(&settings, store: Store(legacy: [.openboxToken]))

        XCTAssertEqual(settings.account(for: .openbox)?.label, "nuc")
    }

    func testGitHubAccountsGetTheKindNameAndCollisionsGetTheWidget() {
        var settings = hydrated(shipbox: "ghp_one", prGitHub: "ghp_two")
        run(&settings, store: Store(legacy: [.shipboxToken, .prboxGitHubToken]))

        XCTAssertEqual(settings.account(for: .shipbox)?.label, "GitHub")
        XCTAssertEqual(settings.account(for: .prboxGitHub)?.label, "GitHub (PRBox)")
    }

    func testAnAccountWithNothingToNameItFallsBackToItsKind() {
        var settings = hydrated(openbox: "tok")
        run(&settings, store: Store(legacy: [.openboxToken]))

        XCTAssertEqual(settings.account(for: .openbox)?.label, "opencode")
    }

    // MARK: - The pre-accounts fields are not a fetch path

    func testAPopulatedLegacyFieldWithNoAccountIsNotAConfiguredCredential() {
        // The fetch-time fallback is gone. A file that predates the migration
        // still migrates when Deck opens, but until then its pre-accounts fields
        // resolve nothing.
        let settings = hydrated(openbox: "tok", serverURL: "http://nuc:4096",
                                shipbox: "ghp", taskbox: "pat", org: "acme",
                                project: "Manifold", prGitHub: "ghp2",
                                prAzure: "pat2", prOrg: "acme", prProject: "F")

        for slot in CredentialSlot.allCases {
            XCTAssertNil(settings.credential(for: slot), "\(slot) must not resolve from a legacy field")
        }
    }

    func testClearingASlotAfterMigrationResurrectsNothing() {
        // A migrated slot's pre-accounts field is blank and its legacy keychain
        // item is gone, so clearing the selection leaves nothing behind.
        var settings = hydrated(shipbox: "ghp")
        run(&settings, store: Store(legacy: [.shipboxToken]))
        settings.setAccountID(nil, for: .shipbox)

        XCTAssertNil(settings.credential(for: .shipbox))
    }

    func testASlotPointingAtADeletedAccountIsNotConfigured() {
        // A dangling id means the user deleted the account. That is "not
        // configured", not an invitation to use a stale token.
        var settings = hydrated(shipbox: "ghp")
        settings.credentials.accounts = [CredentialAccount(id: "a1", kind: .opencode, label: "nuc")]
        settings.shipbox.accountID = "gone"

        XCTAssertNil(settings.credential(for: .shipbox))
    }

    func testAResolvedAccountWins() {
        var settings = hydrated(shipbox: "stale-legacy")
        var account = CredentialAccount(id: "a1", kind: .github, label: "work")
        account.token = "current"
        settings.credentials.accounts = [account]
        settings.shipbox.accountID = "a1"

        XCTAssertEqual(settings.credential(for: .shipbox)?.token, "current")
    }

    func testAnEmptyTokenIsNotAUsableCredential() {
        var settings = DeckSettings()
        settings.credentials.accounts = [CredentialAccount(id: "a1", kind: .github, label: "work")]
        settings.shipbox.accountID = "a1"

        XCTAssertNil(settings.credential(for: .shipbox), "an account with no token is not configured")
    }
}
