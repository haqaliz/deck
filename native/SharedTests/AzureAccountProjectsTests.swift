import XCTest

/// One Azure account now carries several projects. Three things are pinned
/// here because getting any of them wrong is silent: the normalisation the
/// whole feature funnels through, the on-disk migration from the pre-list
/// `project` string, and the verification fingerprint that decides whether a
/// green "signed in as…" badge survives an edit.
final class AzureAccountProjectsTests: XCTestCase {

    // MARK: - Normalisation

    func testTrimsAndDropsEmpties() {
        XCTAssertEqual(
            AzureAccountProjects.normalise(["  ForesightManifold ", "", "   ", "Manifold Ops"]),
            ["ForesightManifold", "Manifold Ops"]
        )
    }

    func testDeduplicatesCaseInsensitivelyKeepingTheFirstSpelling() {
        // Azure treats project names case-insensitively in a URL but displays
        // them cased, so the first spelling is the one the user typed or picked.
        XCTAssertEqual(
            AzureAccountProjects.normalise(["Manifold Ops", "manifold ops", "MANIFOLD OPS"]),
            ["Manifold Ops"]
        )
    }

    func testPreservesOrder() {
        XCTAssertEqual(
            AzureAccountProjects.normalise(["b", "a", "c"]),
            ["b", "a", "c"]
        )
    }

    func testCapsAtFive() {
        let normalised = AzureAccountProjects.normalise(
            ["p1", "p2", "p3", "p4", "p5", "p6", "p7"]
        )
        XCTAssertEqual(normalised, ["p1", "p2", "p3", "p4", "p5"])
        XCTAssertEqual(AzureAccountProjects.maxProjects, 5)
    }

    func testEmptyInputYieldsEmptyList() {
        XCTAssertEqual(AzureAccountProjects.normalise([]), [])
        XCTAssertEqual(AzureAccountProjects.normalise(["", "  "]), [])
    }

    // MARK: - On-disk migration

    private func decodeAccount(_ json: String) throws -> CredentialAccount {
        try JSONDecoder().decode(CredentialAccount.self, from: Data(json.utf8))
    }

    func testDecodesTheProjectsList() throws {
        let account = try decodeAccount("""
        {"id":"a1","kind":"azure","projects":["ForesightManifold","Manifold Ops"]}
        """)
        XCTAssertEqual(account.projects, ["ForesightManifold", "Manifold Ops"])
    }

    func testDecodesALegacyProjectStringAsAOneElementList() throws {
        let account = try decodeAccount("""
        {"id":"a1","kind":"azure","project":"ForesightManifold"}
        """)
        XCTAssertEqual(account.projects, ["ForesightManifold"])
    }

    func testAnEmptyLegacyProjectStringIsNoProjectAtAll() throws {
        let account = try decodeAccount("""
        {"id":"a1","kind":"azure","project":""}
        """)
        XCTAssertEqual(account.projects, [])
    }

    func testNeitherKeyYieldsAnEmptyList() throws {
        let account = try decodeAccount("""
        {"id":"a1","kind":"azure"}
        """)
        XCTAssertEqual(account.projects, [])
    }

    func testThePluralKeyWinsOverTheLegacyOne() throws {
        // A file written by this build and then read by it must not resurrect
        // a value the migration is retiring.
        let account = try decodeAccount("""
        {"id":"a1","kind":"azure","project":"Old","projects":["New"]}
        """)
        XCTAssertEqual(account.projects, ["New"])
    }

    func testEncodingWritesProjectsAndClearsTheLegacyKey() throws {
        // CLAUDE.md: a migration that moves a field must clear the old copy, or
        // the pre-migration fallback keeps answering from a dead field after the
        // new control has taken over.
        var account = CredentialAccount(id: "a1", kind: .azure)
        account.projects = ["ForesightManifold"]

        let text = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)

        XCTAssertTrue(text.contains("\"projects\""))
        XCTAssertFalse(text.contains("\"project\":"), "the singular key must not be written")
    }

    func testARoundTripPreservesTheList() throws {
        var account = CredentialAccount(id: "a1", kind: .azure)
        account.projects = ["ForesightManifold", "Manifold Ops"]

        let decoded = try JSONDecoder().decode(
            CredentialAccount.self, from: try JSONEncoder().encode(account)
        )
        XCTAssertEqual(decoded.projects, account.projects)
    }

    // MARK: - Verification fingerprint

    private func azureAccount(_ projects: [String]) -> CredentialAccount {
        var account = CredentialAccount(id: "a1", kind: .azure)
        account.organization = "ForesightAnalytics"
        account.projects = projects
        account.token = "pat"
        return account
    }

    func testAddingAProjectInvalidatesAVerification() {
        XCTAssertNotEqual(
            azureAccount(["ForesightManifold"]).credentialFingerprint,
            azureAccount(["ForesightManifold", "Manifold Ops"]).credentialFingerprint
        )
    }

    func testRemovingAProjectInvalidatesAVerification() {
        XCTAssertNotEqual(
            azureAccount(["ForesightManifold", "Manifold Ops"]).credentialFingerprint,
            azureAccount(["Manifold Ops"]).credentialFingerprint
        )
    }

    func testReorderingTheSlotsDoesNotInvalidateAVerification() {
        // The five slots are a UI arrangement. Shuffling them changes nothing
        // the verification depended on, and invalidating there would make a
        // good badge flicker for no reason.
        XCTAssertEqual(
            azureAccount(["ForesightManifold", "Manifold Ops"]).credentialFingerprint,
            azureAccount(["Manifold Ops", "ForesightManifold"]).credentialFingerprint
        )
    }

    func testANewTokenStillInvalidatesAVerification() {
        var one = azureAccount(["ForesightManifold"])
        var two = azureAccount(["ForesightManifold"])
        two.token = "different"
        XCTAssertNotEqual(one.credentialFingerprint, two.credentialFingerprint)
        one.token = "different"
        XCTAssertEqual(one.credentialFingerprint, two.credentialFingerprint)
    }
}
