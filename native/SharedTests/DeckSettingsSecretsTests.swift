import XCTest

/// The two host-side transforms: scrub on save, hydrate on load.
///
/// These pin the rules the critique caught (`prd-critique.md` C1, C2): a
/// keychain failure must be distinguishable from an unset token, and hydrate
/// must never blank a value the file already carries.
final class DeckSettingsSecretsTests: XCTestCase {

    private func populated() -> DeckSettings {
        var s = DeckSettings()
        s.openbox.token = "openbox-secret"
        s.shipbox.token = "shipbox-secret"
        s.taskbox.token = "taskbox-secret"
        s.prbox.github.token = "gh-secret"
        s.prbox.azure.token = "az-secret"
        // Non-secret fields that must survive untouched.
        s.shipbox.repos = ["owner/repo"]
        s.taskbox.organization = "ForesightAnalytics"
        s.taskbox.project = "ForesightManifold"
        return s
    }

    // MARK: - Scrub

    func testScrubBlanksExactlyTheFiveCredentials() {
        let scrubbed = populated().scrubbedOfSecrets()
        XCTAssertEqual(scrubbed.openbox.token, "")
        XCTAssertEqual(scrubbed.shipbox.token, "")
        XCTAssertEqual(scrubbed.taskbox.token, "")
        XCTAssertEqual(scrubbed.prbox.github.token, "")
        XCTAssertEqual(scrubbed.prbox.azure.token, "")
    }

    func testScrubChangesNothingElse() {
        let scrubbed = populated().scrubbedOfSecrets()
        XCTAssertEqual(scrubbed.shipbox.repos, ["owner/repo"])
        XCTAssertEqual(scrubbed.taskbox.organization, "ForesightAnalytics")
        XCTAssertEqual(scrubbed.taskbox.project, "ForesightManifold")

        // Everything outside the five is identical to a scrub of a settings
        // object that never held secrets at all.
        var withoutSecrets = populated()
        withoutSecrets.openbox.token = ""
        withoutSecrets.shipbox.token = ""
        withoutSecrets.taskbox.token = ""
        withoutSecrets.prbox.github.token = ""
        withoutSecrets.prbox.azure.token = ""
        XCTAssertEqual(scrubbed, withoutSecrets)
    }

    func testScrubLeavesTheOriginalIntact() {
        let original = populated()
        _ = original.scrubbedOfSecrets()
        XCTAssertEqual(original.shipbox.token, "shipbox-secret")
    }

    func testEncodedFormStillCarriesTokens() throws {
        // `encode(to:)` must stay symmetric — the decode regression tests in
        // DecodeTests depend on it. Only `save()` scrubs.
        let data = try JSONEncoder().encode(populated())
        let round = try JSONDecoder().decode(DeckSettings.self, from: data)
        XCTAssertEqual(round.shipbox.token, "shipbox-secret")
        XCTAssertEqual(round.prbox.azure.token, "az-secret")
    }

    func testTheFormSaveWritesCarriesNoSecret() throws {
        let data = try JSONEncoder().encode(populated().scrubbedOfSecrets())
        let json = String(data: data, encoding: .utf8) ?? ""
        for secret in ["openbox-secret", "shipbox-secret", "taskbox-secret",
                       "gh-secret", "az-secret"] {
            XCTAssertFalse(json.contains(secret), "\(secret) leaked into settings.json")
        }
    }

    // MARK: - Hydrate

    func testFoundOverwrites() {
        var s = DeckSettings()
        let failed = s.hydrate(from: [.shipboxToken: .found("from-keychain")])
        XCTAssertEqual(s.shipbox.token, "from-keychain")
        XCTAssertTrue(failed.isEmpty)
    }

    /// The upgraded-but-never-opened case (C2): the keychain is empty because
    /// migration hasn't run, and the file still holds the real token.
    func testAbsentKeepsTheValueDecodedFromTheFile() {
        var s = populated()
        let failed = s.hydrate(from: [.shipboxToken: .absent])
        XCTAssertEqual(s.shipbox.token, "shipbox-secret")
        XCTAssertTrue(failed.isEmpty)
    }

    func testMissingEntryEntirelyAlsoKeepsTheFileValue() {
        var s = populated()
        s.hydrate(from: [:])
        XCTAssertEqual(s.taskbox.token, "taskbox-secret")
    }

    /// A locked keychain must be reported, not silently turned into "unset".
    func testFailedIsReportedAndDoesNotBlank() {
        var s = populated()
        let failed = s.hydrate(from: [.taskboxToken: .failed(errSecInteractionNotAllowed)])
        XCTAssertEqual(failed, [.taskboxToken])
        XCTAssertEqual(s.taskbox.token, "taskbox-secret")
    }

    func testHydrateNeverBlanksAnything() {
        var s = populated()
        s.hydrate(from: [
            .openboxToken: .absent,
            .shipboxToken: .failed(errSecInteractionNotAllowed),
            .taskboxToken: .absent,
        ])
        XCTAssertEqual(s.openbox.token, "openbox-secret")
        XCTAssertEqual(s.shipbox.token, "shipbox-secret")
        XCTAssertEqual(s.taskbox.token, "taskbox-secret")
    }

    func testHydrateFillsAllFiveIndependently() {
        var s = DeckSettings()
        s.hydrate(from: [
            .openboxToken: .found("o"),
            .shipboxToken: .found("s"),
            .taskboxToken: .found("t"),
            .prboxGitHubToken: .found("g"),
            .prboxAzureToken: .found("a"),
        ])
        XCTAssertEqual(s.openbox.token, "o")
        XCTAssertEqual(s.shipbox.token, "s")
        XCTAssertEqual(s.taskbox.token, "t")
        XCTAssertEqual(s.prbox.github.token, "g")
        XCTAssertEqual(s.prbox.azure.token, "a")
    }

    func testSecretValueReadsEachField() {
        let s = populated()
        XCTAssertEqual(s.secretValue(.openboxToken), "openbox-secret")
        XCTAssertEqual(s.secretValue(.shipboxToken), "shipbox-secret")
        XCTAssertEqual(s.secretValue(.taskboxToken), "taskbox-secret")
        XCTAssertEqual(s.secretValue(.prboxGitHubToken), "gh-secret")
        XCTAssertEqual(s.secretValue(.prboxAzureToken), "az-secret")
    }
}
