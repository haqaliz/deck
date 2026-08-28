import XCTest

/// Phase 2: the account store inside `DeckSettings`.
///
/// Three of the critique's reds live here. R3 — `DeckSettings.CodingKeys` is
/// hand-written, so a forgotten case compiles, decodes as absent and never
/// encodes. R4 — the scrub is written against five fixed fields. R5 — the
/// failed-keychain set was typed by `DeckSecret`, which cannot name a dynamic
/// account.
final class CredentialsWiringTests: XCTestCase {

    private func account(_ id: String, _ kind: CredentialKind, _ label: String) -> CredentialAccount {
        CredentialAccount(id: id, kind: kind, label: label)
    }

    private func roundTrip(_ settings: DeckSettings) throws -> DeckSettings {
        try JSONDecoder().decode(DeckSettings.self, from: try JSONEncoder().encode(settings))
    }

    // MARK: - R3: the store persists at all

    func testAccountsSurviveAnEncodeDecodeCycle() throws {
        var settings = DeckSettings()
        settings.credentials.accounts = [
            account("a1", .github, "work"),
            account("a2", .opencode, "nuc"),
        ]

        let round = try roundTrip(settings)

        XCTAssertEqual(round.credentials.accounts.map(\.id), ["a1", "a2"])
        XCTAssertEqual(round.credentials.accounts.map(\.label), ["work", "nuc"])
    }

    func testSettingsFileWithoutACredentialsKeyKeepsEveryOtherSection() throws {
        // The trap this repo has already been bitten by: a throwing decode
        // reaches `load()`'s `?? DeckSettings()` and resets everything.
        let json = """
        {"shipbox":{"repos":["owner/repo"],"runCount":7},
         "taskbox":{"organization":"acme","project":"Manifold"},
         "agentAtLogin":false}
        """
        let settings = try JSONDecoder().decode(DeckSettings.self, from: Data(json.utf8))

        XCTAssertTrue(settings.credentials.accounts.isEmpty)
        XCTAssertEqual(settings.shipbox.repos, ["owner/repo"])
        XCTAssertEqual(settings.shipbox.runCount, 7)
        XCTAssertEqual(settings.taskbox.organization, "acme")
        XCTAssertFalse(settings.agentAtLogin)
    }

    func testAGarbageCredentialsSectionDoesNotResetTheRestOfTheFile() throws {
        let json = """
        {"credentials":{"accounts":[{"kind":"gitlab"}]},
         "shipbox":{"runCount":7}}
        """
        let settings = try JSONDecoder().decode(DeckSettings.self, from: Data(json.utf8))

        XCTAssertTrue(settings.credentials.accounts.isEmpty)
        XCTAssertEqual(settings.shipbox.runCount, 7)
    }

    // MARK: - R3's sibling: ShipBox has a hand-written encoder

    func testShipBoxAccountIDSurvivesItsHandWrittenEncoder() throws {
        // ShipBoxSettings.encode(to:) is explicit so it can drop the legacy
        // `repo` key. A field added to the struct but not to that encoder is
        // never written, and the user's selection silently resets.
        var settings = DeckSettings()
        settings.shipbox.accountID = "a1"

        XCTAssertEqual(try roundTrip(settings).shipbox.accountID, "a1")
    }

    func testEverySlotsAccountIDRoundTrips() throws {
        var settings = DeckSettings()
        for slot in CredentialSlot.allCases {
            settings.setAccountID(slot.rawValue + "-id", for: slot)
        }

        let round = try roundTrip(settings)

        for slot in CredentialSlot.allCases {
            XCTAssertEqual(round.accountID(for: slot), slot.rawValue + "-id", "\(slot) lost its selection")
        }
    }

    // MARK: - R4: no token ever reaches the file

    func testScrubBlanksEveryAccountToken() {
        var settings = DeckSettings()
        var one = account("a1", .github, "work")
        one.token = "gh-secret"
        var two = account("a2", .azure, "acme")
        two.token = "az-secret"
        settings.credentials.accounts = [one, two]

        let scrubbed = settings.scrubbedOfSecrets()

        XCTAssertEqual(scrubbed.credentials.accounts.map(\.token), ["", ""])
    }

    func testScrubLeavesAccountsOtherwiseUntouched() {
        var settings = DeckSettings()
        var one = account("a1", .azure, "acme")
        one.token = "az-secret"
        one.organization = "acme"
        one.projects = ["Manifold"]
        settings.credentials.accounts = [one]

        let scrubbed = settings.scrubbedOfSecrets()

        XCTAssertEqual(scrubbed.credentials.accounts[0].organization, "acme")
        XCTAssertEqual(scrubbed.credentials.accounts[0].projects, ["Manifold"])
        XCTAssertEqual(scrubbed.credentials.accounts[0].label, "acme")
    }

    func testEncodedSettingsContainNoAccountTokenAnywhere() throws {
        var settings = DeckSettings()
        var one = account("a1", .github, "work")
        one.token = "SENTINEL-TOKEN-VALUE"
        settings.credentials.accounts = [one]

        let text = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)

        XCTAssertFalse(text.contains("SENTINEL-TOKEN-VALUE"))
    }

    // MARK: - Resolution

    func testAnUnsetSlotResolvesToNothing() {
        XCTAssertNil(DeckSettings().account(for: .shipbox))
    }

    func testASlotPointingAtADeletedAccountResolvesToNothing() {
        // Deleting an account leaves dangling ids behind on purpose. They must
        // read as "not configured", never as an error.
        var settings = DeckSettings()
        settings.shipbox.accountID = "gone"

        XCTAssertNil(settings.account(for: .shipbox))
    }

    func testASlotPointingAtTheWrongKindResolvesToNothing() {
        var settings = DeckSettings()
        settings.credentials.accounts = [account("a1", .azure, "acme")]
        settings.shipbox.accountID = "a1"

        XCTAssertNil(settings.account(for: .shipbox), "ShipBox is GitHub; an Azure account cannot serve it")
    }

    func testAMatchingSlotResolvesToItsAccount() {
        var settings = DeckSettings()
        settings.credentials.accounts = [account("a1", .github, "work")]
        settings.shipbox.accountID = "a1"

        XCTAssertEqual(settings.account(for: .shipbox)?.label, "work")
    }

    func testTwoSlotsCanShareOneAccount() {
        // The concrete pain this whole change removes: one GitHub token pasted
        // twice.
        var settings = DeckSettings()
        settings.credentials.accounts = [account("a1", .github, "work")]
        settings.shipbox.accountID = "a1"
        settings.prbox.github.accountID = "a1"

        XCTAssertEqual(settings.account(for: .shipbox)?.id, "a1")
        XCTAssertEqual(settings.account(for: .prboxGitHub)?.id, "a1")
    }

    func testSlotsUsingAnAccountNamesEveryWidgetThatWouldBreak() {
        // Drives the delete confirmation's copy.
        var settings = DeckSettings()
        settings.credentials.accounts = [account("a1", .github, "work")]
        settings.shipbox.accountID = "a1"
        settings.prbox.github.accountID = "a1"

        XCTAssertEqual(settings.slots(using: "a1"), [.shipbox, .prboxGitHub])
        XCTAssertEqual(settings.slots(using: "other"), [])
    }

    // MARK: - R5: hydrate, keyed by account id

    func testHydrateFillsTokensFromTheKeychain() {
        var settings = DeckSettings()
        settings.credentials.accounts = [account("a1", .github, "work")]

        let failed = settings.hydrateAccounts(from: ["a1": .found("gh-secret")])

        XCTAssertEqual(settings.credentials.accounts[0].token, "gh-secret")
        XCTAssertTrue(failed.isEmpty)
    }

    func testAFailedReadIsReportedAndIsNotAnAbsence() {
        // The whole point of the credentialsUnavailable outcome: a locked
        // keychain must not read as "you never pasted a token".
        var settings = DeckSettings()
        settings.credentials.accounts = [account("a1", .github, "work")]

        let failed = settings.hydrateAccounts(from: ["a1": .failed(errSecInteractionNotAllowed)])

        XCTAssertEqual(failed, ["a1"])
        XCTAssertEqual(settings.credentials.accounts[0].token, "")
    }

    func testAnAbsentReadIsNotReportedAsAFailure() {
        var settings = DeckSettings()
        settings.credentials.accounts = [account("a1", .github, "work")]

        XCTAssertTrue(settings.hydrateAccounts(from: ["a1": .absent]).isEmpty)
    }

    func testHydrateNeverBlanksAValueItCannotReplace() {
        // Same rule as the legacy hydrate: `.found` overwrites, nothing else
        // does. Blanking on failure would wipe a working credential the moment
        // the keychain hiccups.
        var settings = DeckSettings()
        var one = account("a1", .github, "work")
        one.token = "already-here"
        settings.credentials.accounts = [one]

        settings.hydrateAccounts(from: ["a1": .failed(errSecInteractionNotAllowed)])
        XCTAssertEqual(settings.credentials.accounts[0].token, "already-here")

        settings.hydrateAccounts(from: ["a1": .absent])
        XCTAssertEqual(settings.credentials.accounts[0].token, "already-here")
    }

    // MARK: - Parity with the legacy mapping while both exist

    func testSlotSourcesStillMatchTheLegacySecretSources() {
        // The migration reads `DeckSecret` and writes slots. If these two
        // mappings ever drift, a failure lands on the wrong widget's chip.
        XCTAssertEqual(CredentialSlot.openbox.source, DeckSecret.openboxToken.fetchSource)
        XCTAssertEqual(CredentialSlot.shipbox.source, DeckSecret.shipboxToken.fetchSource)
        XCTAssertEqual(CredentialSlot.taskbox.source, DeckSecret.taskboxToken.fetchSource)
        XCTAssertEqual(CredentialSlot.prboxGitHub.source, DeckSecret.prboxGitHubToken.fetchSource)
        XCTAssertEqual(CredentialSlot.prboxAzure.source, DeckSecret.prboxAzureToken.fetchSource)
    }
}
