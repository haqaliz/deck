import XCTest

/// Exercises the real keychain against a test-only service so the user's own
/// stored credentials are never touched.
final class DeckKeychainTests: XCTestCase {
    private let service = "com.deck.app.tests"

    override func setUp() {
        super.setUp()
        wipe()
    }

    override func tearDown() {
        wipe()
        super.tearDown()
    }

    private func wipe() {
        for secret in DeckSecret.allCases {
            DeckKeychain.delete(secret, service: service)
        }
    }

    // MARK: - The absent/failed distinction the whole feature rests on

    func testUnwrittenSecretReadsAsAbsentNotFailed() {
        XCTAssertEqual(DeckKeychain.read(.shipboxToken, service: service), .absent)
    }

    func testRoundTrip() {
        XCTAssertEqual(DeckKeychain.write(.shipboxToken, value: "ghp_abc", service: service), errSecSuccess)
        XCTAssertEqual(DeckKeychain.read(.shipboxToken, service: service), .found("ghp_abc"))
    }

    func testWriteOverwritesAnExistingValue() {
        DeckKeychain.write(.taskboxToken, value: "first", service: service)
        XCTAssertEqual(DeckKeychain.write(.taskboxToken, value: "second", service: service), errSecSuccess)
        XCTAssertEqual(DeckKeychain.read(.taskboxToken, service: service), .found("second"))
    }

    func testDeleteMakesTheSecretAbsentAgain() {
        DeckKeychain.write(.openboxToken, value: "tok", service: service)
        XCTAssertEqual(DeckKeychain.delete(.openboxToken, service: service), errSecSuccess)
        XCTAssertEqual(DeckKeychain.read(.openboxToken, service: service), .absent)
    }

    func testDeletingSomethingNeverStoredSucceeds() {
        XCTAssertEqual(DeckKeychain.delete(.prboxAzureToken, service: service), errSecSuccess)
    }

    func testSecretsAreIndependent() {
        DeckKeychain.write(.prboxGitHubToken, value: "gh", service: service)
        DeckKeychain.write(.prboxAzureToken, value: "az", service: service)
        XCTAssertEqual(DeckKeychain.read(.prboxGitHubToken, service: service), .found("gh"))
        XCTAssertEqual(DeckKeychain.read(.prboxAzureToken, service: service), .found("az"))
    }

    func testReadAllCoversEverySecret() {
        DeckKeychain.write(.shipboxToken, value: "s", service: service)
        let all = DeckKeychain.readAll(service: service)
        XCTAssertEqual(all.count, DeckSecret.allCases.count)
        XCTAssertEqual(all[.shipboxToken], .found("s"))
        XCTAssertEqual(all[.taskboxToken], .absent)
    }

    // MARK: - On-disk contract

    func testAccountNamesAreStable() {
        // Renaming any of these strands a token the user already pasted.
        XCTAssertEqual(DeckSecret.allCases.count, 5)
        XCTAssertEqual(
            Set(DeckSecret.allCases.map(\.rawValue)),
            ["openbox.token", "shipbox.token", "taskbox.token",
             "prbox.github.token", "prbox.azure.token"]
        )
    }
}

/// Per-account keychain items, the dynamic replacement for the fixed five.
///
/// Same test-only service, so nothing here touches the user's own credentials.
final class DeckKeychainAccountTests: XCTestCase {
    private let service = "com.deck.app.tests.accounts"
    private let ids = ["acct-one", "acct-two"]

    override func setUp() {
        super.setUp()
        wipe()
    }

    override func tearDown() {
        wipe()
        super.tearDown()
    }

    private func wipe() {
        for id in ids { DeckKeychain.delete(accountID: id, service: service) }
    }

    func testUnwrittenAccountReadsAsAbsentNotFailed() {
        XCTAssertEqual(DeckKeychain.read(accountID: "acct-one", service: service), .absent)
    }

    func testRoundTrip() {
        XCTAssertEqual(
            DeckKeychain.write(accountID: "acct-one", value: "ghp_abc", service: service),
            errSecSuccess
        )
        XCTAssertEqual(DeckKeychain.read(accountID: "acct-one", service: service), .found("ghp_abc"))
    }

    func testWriteOverwritesAnExistingValue() {
        DeckKeychain.write(accountID: "acct-one", value: "first", service: service)
        DeckKeychain.write(accountID: "acct-one", value: "second", service: service)
        XCTAssertEqual(DeckKeychain.read(accountID: "acct-one", service: service), .found("second"))
    }

    func testDeleteMakesTheAccountAbsentAgain() {
        DeckKeychain.write(accountID: "acct-one", value: "tok", service: service)
        XCTAssertEqual(DeckKeychain.delete(accountID: "acct-one", service: service), errSecSuccess)
        XCTAssertEqual(DeckKeychain.read(accountID: "acct-one", service: service), .absent)
    }

    func testDeletingSomethingNeverStoredSucceeds() {
        XCTAssertEqual(DeckKeychain.delete(accountID: "acct-two", service: service), errSecSuccess)
    }

    func testAccountsAreIndependent() {
        DeckKeychain.write(accountID: "acct-one", value: "one", service: service)
        DeckKeychain.write(accountID: "acct-two", value: "two", service: service)
        XCTAssertEqual(DeckKeychain.read(accountID: "acct-one", service: service), .found("one"))
        XCTAssertEqual(DeckKeychain.read(accountID: "acct-two", service: service), .found("two"))
    }

    func testReadAllCoversEveryRequestedAccount() {
        DeckKeychain.write(accountID: "acct-one", value: "one", service: service)
        let all = DeckKeychain.readAll(accountIDs: ids, service: service)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all["acct-one"], .found("one"))
        XCTAssertEqual(all["acct-two"], .absent)
    }

    // MARK: - On-disk contract

    func testItemNameIsDerivedFromTheAccountIdAndIsStable() {
        // A change to this format strands every token the user already pasted,
        // exactly as a rename of the legacy five would.
        XCTAssertEqual(DeckKeychain.itemName(forAccountID: "abc123"), "account.abc123.token")
    }

    func testAccountItemsDoNotCollideWithTheLegacyFive() {
        let legacy = Set(DeckSecret.allCases.map(\.rawValue))
        XCTAssertFalse(legacy.contains(DeckKeychain.itemName(forAccountID: "openbox")))
    }
}
