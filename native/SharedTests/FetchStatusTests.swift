import XCTest

// Fetch status core: why the last attempt to fetch agent-pumped data failed,
// and the one line a widget face shows for it.

final class FetchClassifierTests: XCTestCase {

    // MARK: - Status codes (shared by all three loaders)

    func testAuthOrTargetStatusCodes() {
        for code in [401, 403, 404] {
            XCTAssertEqual(
                FetchClassifier.outcome(forStatusCode: code), .authOrTarget,
                "HTTP \(code) is user-fixable (wrong credentials or wrong target)"
            )
        }
    }

    func testTransientStatusCodesAreUnreachable() {
        for code in [429, 500, 502, 503] {
            XCTAssertEqual(
                FetchClassifier.outcome(forStatusCode: code), .unreachable,
                "HTTP \(code) is transient, not something the user can fix"
            )
        }
    }

    func testUnexpectedClientStatusCodeIsBadResponse() {
        XCTAssertEqual(FetchClassifier.outcome(forStatusCode: 418), .badResponse)
        XCTAssertEqual(FetchClassifier.outcome(forStatusCode: 400), .badResponse)
    }

    // MARK: - GitHub (ShipBox)

    func testGitHubInvalidRepoIsAuthOrTarget() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostGitHubLoader.GitHubError.invalidRepo), .authOrTarget)
    }

    func testGitHubServerErrorUsesStatusCode() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostGitHubLoader.GitHubError.serverError(404)), .authOrTarget)
        XCTAssertEqual(FetchClassifier.outcome(for: HostGitHubLoader.GitHubError.serverError(503)), .unreachable)
    }

    func testGitHubTransportIsUnreachable() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostGitHubLoader.GitHubError.transport("offline")), .unreachable)
    }

    func testGitHubInvalidPayloadIsBadResponse() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostGitHubLoader.GitHubError.invalidPayload), .badResponse)
    }

    // MARK: - wttr.in (HomeBox)

    func testWeatherInvalidLocationIsAuthOrTarget() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostWeatherLoader.WeatherError.invalidLocation), .authOrTarget)
    }

    func testWeatherServerErrorUsesStatusCode() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostWeatherLoader.WeatherError.serverError(404)), .authOrTarget)
        XCTAssertEqual(FetchClassifier.outcome(for: HostWeatherLoader.WeatherError.serverError(500)), .unreachable)
    }

    func testWeatherTransportIsUnreachable() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostWeatherLoader.WeatherError.transport("dns")), .unreachable)
    }

    func testWeatherInvalidPayloadIsBadResponse() {
        XCTAssertEqual(FetchClassifier.outcome(for: HostWeatherLoader.WeatherError.invalidPayload), .badResponse)
    }

    // MARK: - opencode serve (OpenBox remote)

    func testRemoteUnauthorizedIsAuthOrTarget() {
        XCTAssertEqual(FetchClassifier.outcome(for: RemoteOpenCodeLoader.RemoteError.unauthorized), .authOrTarget)
    }

    func testRemoteInvalidURLIsAuthOrTarget() {
        XCTAssertEqual(FetchClassifier.outcome(for: RemoteOpenCodeLoader.RemoteError.invalidURL), .authOrTarget)
    }

    func testRemoteServerErrorUsesStatusCode() {
        XCTAssertEqual(FetchClassifier.outcome(for: RemoteOpenCodeLoader.RemoteError.serverError(502)), .unreachable)
    }

    func testRemoteTransportIsUnreachable() {
        XCTAssertEqual(FetchClassifier.outcome(for: RemoteOpenCodeLoader.RemoteError.transport("timed out")), .unreachable)
    }

    // MARK: - Unknown errors

    func testUnknownErrorIsUnreachable() {
        struct Surprise: Error {}
        XCTAssertEqual(
            FetchClassifier.outcome(for: Surprise()), .unreachable,
            "an unrecognised error must not accuse the user of misconfiguring anything"
        )
    }
}

final class FetchStatusCopyTests: XCTestCase {

    func testOkHasNoLine() {
        for source in FetchSource.allCases {
            XCTAssertNil(FetchStatusCopy.line(source: source, outcome: .ok))
        }
    }

    func testShipBoxCopy() {
        XCTAssertEqual(FetchStatusCopy.line(source: .shipbox, outcome: .notConfigured), "Add a repo + token in settings")
        XCTAssertEqual(FetchStatusCopy.line(source: .shipbox, outcome: .authOrTarget), "Check repo + token")
        XCTAssertEqual(FetchStatusCopy.line(source: .shipbox, outcome: .unreachable), "Can't reach GitHub")
        XCTAssertEqual(FetchStatusCopy.line(source: .shipbox, outcome: .badResponse), "Unexpected GitHub response")
    }

    func testWeatherCopy() {
        XCTAssertEqual(FetchStatusCopy.line(source: .weather, outcome: .authOrTarget), "Check the location")
        XCTAssertEqual(FetchStatusCopy.line(source: .weather, outcome: .unreachable), "Can't reach wttr.in")
        XCTAssertEqual(FetchStatusCopy.line(source: .weather, outcome: .badResponse), "Unexpected wttr.in response")
    }

    func testWeatherNotConfiguredHasNoLine() {
        XCTAssertNil(
            FetchStatusCopy.line(source: .weather, outcome: .notConfigured),
            "an empty location is valid — wttr.in geolocates"
        )
    }

    func testOpenCodeRemoteCopy() {
        XCTAssertEqual(FetchStatusCopy.line(source: .opencodeRemote, outcome: .notConfigured), "Paste your opencode token")
        XCTAssertEqual(FetchStatusCopy.line(source: .opencodeRemote, outcome: .authOrTarget), "Check server URL + token")
        XCTAssertEqual(FetchStatusCopy.line(source: .opencodeRemote, outcome: .unreachable), "Can't reach the opencode server")
        XCTAssertEqual(FetchStatusCopy.line(source: .opencodeRemote, outcome: .badResponse), "Unexpected server response")
    }

    func testEveryFailureOutcomeHasCopyExceptWeatherNotConfigured() {
        let failures: [FetchOutcome] = [.notConfigured, .authOrTarget, .unreachable, .badResponse]
        for source in FetchSource.allCases {
            for outcome in failures {
                if source == .weather && outcome == .notConfigured { continue }
                XCTAssertNotNil(
                    FetchStatusCopy.line(source: source, outcome: outcome),
                    "\(source.rawValue) + \(outcome.rawValue) must say something"
                )
            }
        }
    }
}

final class FetchChipTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func status(_ outcome: FetchOutcome, agoSeconds: TimeInterval, source: FetchSource = .shipbox) -> FetchStatus {
        FetchStatus(source: source, outcome: outcome, attemptedAt: now.addingTimeInterval(-agoSeconds))
    }

    func testRecentFailureShowsItsReason() {
        let text = FetchChip.text(
            source: .shipbox,
            status: status(.authOrTarget, agoSeconds: 30),
            dataWrittenAt: now.addingTimeInterval(-30),
            now: now
        )
        XCTAssertEqual(text, "Check repo + token")
    }

    func testSuccessShowsNoChip() {
        let text = FetchChip.text(
            source: .shipbox,
            status: status(.ok, agoSeconds: 30),
            dataWrittenAt: now.addingTimeInterval(-30),
            now: now
        )
        XCTAssertNil(text)
    }

    func testNothingAttemptedInHalfAnHourSaysAgentHasNotRun() {
        let text = FetchChip.text(
            source: .shipbox,
            status: status(.ok, agoSeconds: 31 * 60),
            dataWrittenAt: now.addingTimeInterval(-31 * 60),
            now: now
        )
        XCTAssertEqual(text, "Agent hasn't run")
    }

    func testExactlyAtThresholdIsNotYetDead() {
        let text = FetchChip.text(
            source: .shipbox,
            status: status(.ok, agoSeconds: 30 * 60),
            dataWrittenAt: now.addingTimeInterval(-30 * 60),
            now: now
        )
        XCTAssertNil(text, "the boundary belongs to the living")
    }

    func testDeadAgentBeatsAStaleFailureReason() {
        let text = FetchChip.text(
            source: .shipbox,
            status: status(.authOrTarget, agoSeconds: 90 * 60),
            dataWrittenAt: now.addingTimeInterval(-90 * 60),
            now: now
        )
        XCTAssertEqual(text, "Agent hasn't run", "an hour-old reason is not news about now")
    }

    func testFreshAttemptKeepsOldDataAlive() {
        let text = FetchChip.text(
            source: .shipbox,
            status: status(.unreachable, agoSeconds: 30),
            dataWrittenAt: now.addingTimeInterval(-8 * 60 * 60),
            now: now
        )
        XCTAssertEqual(
            text, "Can't reach GitHub",
            "the agent is alive and trying — the data is just old"
        )
    }

    func testNoStatusAndNoDataSaysAgentHasNotRun() {
        let text = FetchChip.text(source: .shipbox, status: nil, dataWrittenAt: nil, now: now)
        XCTAssertEqual(text, "Agent hasn't run")
    }

    func testFreshDataWithoutAStatusShowsNoChip() {
        let text = FetchChip.text(
            source: .shipbox,
            status: nil,
            dataWrittenAt: now.addingTimeInterval(-60),
            now: now
        )
        XCTAssertNil(text, "an older Deck's snapshot with no status file is not an error")
    }

    func testWeatherNotConfiguredShowsNoChip() {
        let text = FetchChip.text(
            source: .weather,
            status: status(.notConfigured, agoSeconds: 30, source: .weather),
            dataWrittenAt: now.addingTimeInterval(-30),
            now: now
        )
        XCTAssertNil(text)
    }
}

final class FetchStatusStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FetchStatusStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var storeURL: URL { dir.appendingPathComponent("fetch-shipbox.json") }

    private func makeStatus() -> FetchStatus {
        FetchStatus(
            source: .shipbox,
            outcome: .authOrTarget,
            attemptedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testSaveThenLoadRoundTrips() {
        FetchStatusStore.save(makeStatus(), to: storeURL)
        XCTAssertEqual(FetchStatusStore.load(from: storeURL), makeStatus())
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(FetchStatusStore.load(from: storeURL))
    }

    func testCorruptFileLoadsNilAndNextSaveHeals() {
        try? "not-json{{{".write(to: storeURL, atomically: true, encoding: .utf8)
        XCTAssertNil(FetchStatusStore.load(from: storeURL))
        FetchStatusStore.save(makeStatus(), to: storeURL)
        XCTAssertEqual(FetchStatusStore.load(from: storeURL), makeStatus())
    }

    func testUnknownOutcomeDecodesAsOk() throws {
        let json = #"{"source":"shipbox","outcome":"somethingNewerDecksKnow","attemptedAt":1000}"#
        try json.write(to: storeURL, atomically: true, encoding: .utf8)
        let loaded = FetchStatusStore.load(from: storeURL)
        XCTAssertEqual(
            loaded?.outcome, .ok,
            "an unknown outcome must render nothing, never a wrong reason"
        )
    }

    func testEachSourceGetsItsOwnFile() {
        let urls = FetchSource.allCases.map { FetchStatusStore.fileURL(for: $0).lastPathComponent }
        XCTAssertEqual(Set(urls).count, FetchSource.allCases.count)
        XCTAssertTrue(urls.allSatisfy { $0.hasPrefix("fetch-") && $0.hasSuffix(".json") })
    }
}

// MARK: - Settings-tab hints (shipbox-settings-status)

final class FetchStatusHintTests: XCTestCase {
    /// The widget chip is one terse line; the settings tab has room for a
    /// sentence that says what to actually do.
    func testHintIsLongerAndMoreSpecificThanTheChip() {
        for source in FetchSource.allCases {
            for outcome in [FetchOutcome.notConfigured, .authOrTarget, .unreachable, .badResponse] {
                guard let hint = FetchStatusCopy.hint(source: source, outcome: outcome) else { continue }
                XCTAssertGreaterThan(hint.count, 20, "\(source)/\(outcome) hint too terse: \(hint)")
                XCTAssertTrue(hint.hasSuffix("."), "\(source)/\(outcome) hint should read as a sentence")
            }
        }
    }

    func testSuccessHasNoHint() {
        for source in FetchSource.allCases {
            XCTAssertNil(FetchStatusCopy.hint(source: source, outcome: .ok), "\(source)")
        }
    }

    func testEveryFailureOutcomeHasAHintWhereTheChipHasALine() {
        for source in FetchSource.allCases {
            for outcome in [FetchOutcome.notConfigured, .authOrTarget, .unreachable, .badResponse] {
                let hasLine = FetchStatusCopy.line(source: source, outcome: outcome) != nil
                let hasHint = FetchStatusCopy.hint(source: source, outcome: outcome) != nil
                XCTAssertEqual(hasLine, hasHint, "\(source)/\(outcome): chip and hint must agree on whether to speak")
            }
        }
    }

    func testShipBoxAuthHintNamesBothCauses() {
        let hint = FetchStatusCopy.hint(source: .shipbox, outcome: .authOrTarget)

        // GitHub answers 404 for a private repo the token can't see, so the
        // copy must not blame the repo name alone.
        XCTAssertEqual(
            hint,
            "GitHub rejected the request: check owner/repo and that the token is valid and can see it."
        )
    }
}
