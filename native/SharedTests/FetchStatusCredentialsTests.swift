import XCTest

/// The `credentialsUnavailable` outcome and the secret → source mapping.
///
/// This is where critique C1 lives: if a locked keychain cannot be told apart
/// from an unset token, this outcome never fires and the user is sent to the
/// wrong field.
final class FetchStatusCredentialsTests: XCTestCase {

    private let credentialed: Set<FetchSource> =
        [.shipbox, .taskbox, .opencodeRemote, .prboxGitHub, .prboxAzure]

    func testEverySecretMapsToItsOwnSource() {
        let sources = DeckSecret.allCases.map(\.fetchSource)
        XCTAssertEqual(Set(sources).count, DeckSecret.allCases.count, "two secrets share a source")
        XCTAssertEqual(Set(sources), credentialed)
    }

    func testSpecificMappings() {
        XCTAssertEqual(DeckSecret.shipboxToken.fetchSource, .shipbox)
        XCTAssertEqual(DeckSecret.taskboxToken.fetchSource, .taskbox)
        XCTAssertEqual(DeckSecret.openboxToken.fetchSource, .opencodeRemote)
        XCTAssertEqual(DeckSecret.prboxGitHubToken.fetchSource, .prboxGitHub)
        XCTAssertEqual(DeckSecret.prboxAzureToken.fetchSource, .prboxAzure)
    }

    func testCopySpeaksForExactlyTheCredentialedSources() {
        for source in FetchSource.allCases {
            let line = FetchStatusCopy.line(source: source, outcome: .credentialsUnavailable)
            let hint = FetchStatusCopy.hint(source: source, outcome: .credentialsUnavailable)
            if credentialed.contains(source) {
                XCTAssertNotNil(line, "\(source) should say something on the face")
                XCTAssertNotNil(hint, "\(source) should say something in settings")
            } else {
                XCTAssertNil(line, "\(source) has no credentials and cannot reach this state")
                XCTAssertNil(hint, "\(source) has no credentials and cannot reach this state")
            }
        }
    }

    /// The file's own invariant: `hint` speaks exactly when `line` speaks.
    func testHintSpeaksExactlyWhenLineSpeaks() {
        for source in FetchSource.allCases {
            let line = FetchStatusCopy.line(source: source, outcome: .credentialsUnavailable)
            let hint = FetchStatusCopy.hint(source: source, outcome: .credentialsUnavailable)
            XCTAssertEqual(line == nil, hint == nil, "\(source) disagrees between face and settings")
        }
    }

    /// It must not read as "you forgot to configure this".
    func testTheCopyNeverTellsTheUserToPasteATokenAgain() {
        for source in credentialed {
            let hint = FetchStatusCopy.hint(source: source, outcome: .credentialsUnavailable) ?? ""
            XCTAssertTrue(hint.lowercased().contains("keychain"))
            XCTAssertFalse(hint.lowercased().contains("nothing is fetched until"))
        }
    }

    /// Pre-existing behaviour, re-pinned because a new case makes it matter:
    /// an outcome an older build doesn't know decodes as `ok` (render nothing)
    /// rather than throwing or inventing a reason.
    func testUnknownOutcomeStillDecodesAsOk() throws {
        let json = """
        {"source":"shipbox","outcome":"somethingFromANewerDeck","attemptedAt":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let status = try decoder.decode(FetchStatus.self, from: json)
        XCTAssertEqual(status.outcome, .ok)
    }

    func testCredentialsUnavailableRoundTrips() throws {
        let original = FetchStatus(source: .taskbox, outcome: .credentialsUnavailable,
                                   attemptedAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(original)
        let round = try JSONDecoder().decode(FetchStatus.self, from: data)
        XCTAssertEqual(round.outcome, .credentialsUnavailable)
    }
}
