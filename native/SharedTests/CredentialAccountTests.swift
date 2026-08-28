import XCTest

/// The account model that replaces the five welded `DeckSecret` fields.
///
/// Two properties are load-bearing and are pinned here rather than left to
/// review: an account's token must never reach `settings.json`, and one
/// unreadable account must never take the rest of the file down with it.
final class CredentialAccountTests: XCTestCase {

    private func decode(_ json: String) throws -> CredentialsSettings {
        try JSONDecoder().decode(CredentialsSettings.self, from: Data(json.utf8))
    }

    // MARK: - Tokens never reach the file

    func testEncodingAnAccountOmitsTheToken() throws {
        var account = CredentialAccount(id: "a1", kind: .github, label: "work")
        account.token = "SENTINEL-TOKEN-VALUE"

        let data = try JSONEncoder().encode(account)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains("SENTINEL-TOKEN-VALUE"), "the token must not be encoded")
        XCTAssertFalse(text.contains("\"token\""), "not even as an empty key")
    }

    func testEncodingAWholeStoreOmitsEveryToken() throws {
        var one = CredentialAccount(id: "a1", kind: .github, label: "work")
        one.token = "SENTINEL-ONE"
        var two = CredentialAccount(id: "a2", kind: .azure, label: "acme")
        two.token = "SENTINEL-TWO"

        let data = try JSONEncoder().encode(CredentialsSettings(accounts: [one, two]))
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains("SENTINEL-ONE"))
        XCTAssertFalse(text.contains("SENTINEL-TWO"))
    }

    func testDecodedAccountHasAnEmptyTokenAwaitingTheKeychain() throws {
        var account = CredentialAccount(id: "a1", kind: .opencode, label: "nuc")
        account.token = "SENTINEL"
        account.serverURL = "http://nuc:4096"

        let round = try JSONDecoder().decode(
            CredentialAccount.self,
            from: try JSONEncoder().encode(account)
        )

        XCTAssertEqual(round.token, "")
        XCTAssertEqual(round.serverURL, "http://nuc:4096", "non-secret fields survive")
    }

    // MARK: - Round trip

    func testEveryNonSecretFieldSurvivesARoundTrip() throws {
        var account = CredentialAccount(id: "a1", kind: .azure, label: "acme")
        account.organization = "acme"
        account.projects = ["Manifold"]
        account.verifiedIdentity = "Ali Haqiqi"
        account.azureIdentityID = "1c1e4e0a-0000-4000-8000-000000000001"
        account.verifiedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let round = try JSONDecoder().decode(
            CredentialAccount.self,
            from: try JSONEncoder().encode(account)
        )

        XCTAssertEqual(round, account, "no token was set, so the omitted field costs nothing here")
    }

    // MARK: - Tolerant decode

    func testAnAccountWithOnlyIdAndKindDecodes() throws {
        let store = try decode(#"{"accounts":[{"id":"a1","kind":"github"}]}"#)

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts[0].label, "")
        XCTAssertEqual(store.accounts[0].organization, "")
        XCTAssertNil(store.accounts[0].verifiedAt)
    }

    func testAnUnknownKindIsDroppedNotThrown() throws {
        // A kind written by a newer build. Throwing here would reach
        // DeckSettings.load()'s `?? DeckSettings()` and reset every setting.
        let store = try decode(#"{"accounts":[{"id":"a1","kind":"gitlab","label":"x"}]}"#)

        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testOneUnreadableAccountDoesNotTakeItsSiblingsDown() throws {
        let store = try decode("""
        {"accounts":[
          {"id":"a1","kind":"github","label":"work"},
          {"kind":"github","label":"no id"},
          {"id":"a3","kind":"azure","label":"acme"}
        ]}
        """)

        XCTAssertEqual(store.accounts.map(\.id), ["a1", "a3"])
    }

    func testAnAccountWithAnEmptyIdIsDropped() throws {
        // The id is the keychain item name. An empty one would collide with
        // every other empty one.
        let store = try decode(#"{"accounts":[{"id":"","kind":"github","label":"x"}]}"#)

        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testAMissingAccountsKeyDecodesAsEmpty() throws {
        XCTAssertTrue(try decode("{}").accounts.isEmpty)
    }

    // MARK: - Generated ids

    func testGeneratedIdsAreUnique() {
        let a = CredentialAccount(kind: .github, label: "one")
        let b = CredentialAccount(kind: .github, label: "two")

        XCTAssertFalse(a.id.isEmpty)
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Slots

    func testEverySlotDeclaresItsKind() {
        XCTAssertEqual(CredentialSlot.openbox.kind, .opencode)
        XCTAssertEqual(CredentialSlot.shipbox.kind, .github)
        XCTAssertEqual(CredentialSlot.taskbox.kind, .azure)
        XCTAssertEqual(CredentialSlot.prboxGitHub.kind, .github)
        XCTAssertEqual(CredentialSlot.prboxAzure.kind, .azure)
    }

    func testEverySlotMapsToTheFetchSourceItsWidgetAlreadyReports() {
        // These pairings are what keeps `credentialsUnavailable` landing on the
        // right widget's chip.
        XCTAssertEqual(CredentialSlot.openbox.source, .opencodeRemote)
        XCTAssertEqual(CredentialSlot.shipbox.source, .shipbox)
        XCTAssertEqual(CredentialSlot.taskbox.source, .taskbox)
        XCTAssertEqual(CredentialSlot.prboxGitHub.source, .prboxGitHub)
        XCTAssertEqual(CredentialSlot.prboxAzure.source, .prboxAzure)
    }

    func testSlotsCoverTheFiveLegacySecretsAndNoMore() {
        XCTAssertEqual(CredentialSlot.allCases.count, DeckSecret.allCases.count)
    }

    func testSlotDisplayNamesAreTheWidgetNamesTheDeleteDialogWillShow() {
        XCTAssertEqual(CredentialSlot.openbox.displayName, "OpenBox")
        XCTAssertEqual(CredentialSlot.shipbox.displayName, "ShipBox")
        XCTAssertEqual(CredentialSlot.taskbox.displayName, "TaskBox")
        XCTAssertEqual(CredentialSlot.prboxGitHub.displayName, "PRBox (GitHub)")
        XCTAssertEqual(CredentialSlot.prboxAzure.displayName, "PRBox (Azure DevOps)")
    }
}
