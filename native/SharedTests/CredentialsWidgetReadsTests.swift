import XCTest

/// Critique R1: two reads inside the sandboxed widget extension decide what
/// OpenBox and PRBox render, and both fields move onto accounts.
///
/// Neither failure is loud — no crash, no log, just a permanently wrong face —
/// so the replacements are pinned here. Everything they need is a *non-secret*
/// field, because the extension has no keychain access at all.
final class CredentialsWidgetReadsTests: XCTestCase {

    private func withAccount(_ account: CredentialAccount, on slot: CredentialSlot) -> DeckSettings {
        var s = DeckSettings()
        s.credentials.accounts = [account]
        s.setAccountID(account.id, for: slot)
        return s
    }

    private func opencodeAccount(serverURL: String) -> CredentialAccount {
        var a = CredentialAccount(id: "a1", kind: .opencode, label: "nuc")
        a.serverURL = serverURL
        return a
    }

    // MARK: - OpenBox: local database or remote server

    func testOpenBoxIsRemoteWhenItsAccountHasAServerURL() {
        let settings = withAccount(opencodeAccount(serverURL: "http://nuc:4096"), on: .openbox)

        XCTAssertTrue(settings.openBoxUsesRemoteServer)
    }

    func testOpenBoxIsLocalWhenNoAccountIsSelected() {
        // The new rule, and it is clearer than the old empty-URL convention:
        // None means the local opencode database.
        XCTAssertFalse(DeckSettings().openBoxUsesRemoteServer)
    }

    func testOpenBoxIsLocalWhenItsAccountHasNoServerURL() {
        let settings = withAccount(opencodeAccount(serverURL: ""), on: .openbox)

        XCTAssertFalse(settings.openBoxUsesRemoteServer)
    }

    func testOpenBoxIsLocalWhenItsAccountWasDeleted() {
        var settings = DeckSettings()
        settings.openbox.accountID = "gone"

        XCTAssertFalse(settings.openBoxUsesRemoteServer)
    }

    func testOpenBoxHonoursTheLegacyServerURLBeforeMigration() {
        // An upgraded-but-never-opened Deck: the agent is fetching remotely, so
        // the face must not claim to be local.
        var settings = DeckSettings()
        settings.openbox.serverURL = "http://nuc:4096"

        XCTAssertTrue(settings.openBoxUsesRemoteServer)
    }

    // MARK: - PRBox: a provider is on when it has an account

    func testAProviderIsOnExactlyWhenAnAccountIsSelected() {
        var settings = DeckSettings()
        settings.credentials.accounts = [
            CredentialAccount(id: "gh", kind: .github, label: "work"),
            CredentialAccount(id: "az", kind: .azure, label: "acme"),
        ]
        settings.prbox.github.accountID = "gh"

        XCTAssertTrue(settings.prBoxGitHubIsOn)
        XCTAssertFalse(settings.prBoxAzureIsOn)

        settings.prbox.azure.accountID = "az"
        XCTAssertTrue(settings.prBoxAzureIsOn)
    }

    func testAProviderIsOffWhenItsAccountWasDeleted() {
        var settings = DeckSettings()
        settings.prbox.github.accountID = "gone"

        XCTAssertFalse(settings.prBoxGitHubIsOn)
    }

    func testAProviderIsOffWhenItsAccountIsOfTheWrongKind() {
        var settings = DeckSettings()
        settings.credentials.accounts = [CredentialAccount(id: "az", kind: .azure, label: "acme")]
        settings.prbox.github.accountID = "az"

        XCTAssertFalse(settings.prBoxGitHubIsOn)
    }

    func testAProviderHonoursTheLegacyEnabledFlagBeforeMigration() {
        var settings = DeckSettings()
        settings.prbox.github.enabled = true

        XCTAssertTrue(settings.prBoxGitHubIsOn)
    }

    // MARK: - The property that makes all of this safe in the extension

    func testEveryWidgetReadIsAnswerableFromTheFileAloneWithNoToken() {
        // What the extension actually sees: settings.json, tokens absent.
        var authored = DeckSettings()
        var opencode = CredentialAccount(id: "a1", kind: .opencode, label: "nuc")
        opencode.serverURL = "http://nuc:4096"
        opencode.token = "SECRET"
        var github = CredentialAccount(id: "a2", kind: .github, label: "work")
        github.token = "SECRET"
        authored.credentials.accounts = [opencode, github]
        authored.openbox.accountID = "a1"
        authored.prbox.github.accountID = "a2"

        let asTheExtensionSeesIt = try! JSONDecoder().decode(
            DeckSettings.self,
            from: try! JSONEncoder().encode(authored.scrubbedOfSecrets())
        )

        XCTAssertEqual(asTheExtensionSeesIt.credentials.accounts.map(\.token), ["", ""])
        XCTAssertTrue(asTheExtensionSeesIt.openBoxUsesRemoteServer)
        XCTAssertTrue(asTheExtensionSeesIt.prBoxGitHubIsOn)
    }

    // MARK: - Migration must not leave the moved fields behind

    private func migrated(_ settings: inout DeckSettings) {
        var ids = 0
        var store: [String: String] = [:]
        CredentialsMigration.migrate(
            &settings,
            write: { store[$0] = $1; return errSecSuccess },
            readBack: { store[$0].map { .found($0) } ?? .absent },
            deleteLegacy: { _ in errSecSuccess },
            makeID: { ids += 1; return "id\(ids)" }
        )
    }

    func testMigrationClearsTheServerURLThatMovedOntoTheAccount() {
        var settings = DeckSettings()
        settings.openbox.token = "tok"
        settings.openbox.serverURL = "http://nuc:4096"

        migrated(&settings)

        XCTAssertEqual(settings.account(for: .openbox)?.serverURL, "http://nuc:4096")
        XCTAssertNil(settings.openbox.serverURL, "a stale duplicate would outlive the account")
    }

    func testMigrationClearsTheAzureOrganizationAndProjectThatMoved() {
        var settings = DeckSettings()
        settings.taskbox.token = "pat"
        settings.taskbox.organization = "acme"
        settings.taskbox.project = "Manifold"

        migrated(&settings)

        XCTAssertEqual(settings.account(for: .taskbox)?.organization, "acme")
        XCTAssertEqual(settings.taskbox.organization, "")
        XCTAssertEqual(settings.taskbox.project, "")
    }

    func testMigrationClearsThePRBoxEnabledFlagItRepresentedAsASelection() {
        // Otherwise the legacy fallback above would keep answering from a dead
        // field after the picker became the real control.
        var settings = DeckSettings()
        settings.prbox.github.token = "ghp"
        settings.prbox.github.enabled = true

        migrated(&settings)

        XCTAssertNotNil(settings.accountID(for: .prboxGitHub))
        XCTAssertFalse(settings.prbox.github.enabled)
    }

    func testMigrationLeavesAnUnmigratedSlotsFieldsAlone() {
        // A slot whose write failed must keep everything the fallback needs.
        var settings = DeckSettings()
        settings.taskbox.token = "pat"
        settings.taskbox.organization = "acme"
        settings.taskbox.project = "Manifold"

        var attempted = 0
        CredentialsMigration.migrate(
            &settings,
            write: { _, _ in attempted += 1; return errSecIO },
            readBack: { _ in .absent },
            deleteLegacy: { _ in errSecSuccess },
            makeID: { "id1" }
        )

        XCTAssertEqual(attempted, 1)
        XCTAssertEqual(settings.taskbox.organization, "acme")
        XCTAssertEqual(settings.taskbox.project, "Manifold")
        XCTAssertEqual(settings.credential(for: .taskbox)?.organization, "acme")
    }
}
