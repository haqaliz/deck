import Foundation

// MARK: - Fetch status
//
// Why the last attempt to refresh an agent-pumped source failed. The three
// network-fetched widgets (ShipBox, HomeBox, OpenBox in remote mode) used to
// collapse "wrong token", "offline" and "nothing there yet" into one generic
// placeholder; this records the reason so the face can say it.
//
// Stored in its own small file per source rather than as fields on the
// snapshots, so that:
//   1. a failure never rewrites the data file (last-good data cannot be lost),
//   2. snapshot Equatable stays payload-only (the agent's "skipped
//      (unchanged)" write-avoidance keeps working),
//   3. a status can exist before any snapshot does (first run, bad token),
//   4. a missing file means exactly the pre-status behaviour.

enum FetchSource: String, Codable, CaseIterable {
    case shipbox, weather, opencodeRemote, taskbox
}

enum FetchOutcome: String, Codable {
    /// The fetch succeeded — renders nothing, and clears a previous failure.
    case ok
    /// The user hasn't supplied what the fetch needs (token, repo).
    case notConfigured
    /// Credentials or target are wrong: user-fixable (401/403/404, bad URL).
    case authOrTarget
    /// Transient and not the user's fault (offline, 5xx, rate limited).
    case unreachable
    /// Reached the service, could not make sense of the answer.
    case badResponse
}

struct FetchStatus: Codable, Equatable {
    var source: FetchSource
    var outcome: FetchOutcome
    var attemptedAt: Date

    init(source: FetchSource, outcome: FetchOutcome, attemptedAt: Date) {
        self.source = source
        self.outcome = outcome
        self.attemptedAt = attemptedAt
    }

    /// Tolerant decode: an outcome this build doesn't know (written by a newer
    /// agent) reads as `ok`, so an older widget renders nothing rather than a
    /// wrong reason.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(FetchSource.self, forKey: .source)
        let raw = try c.decode(String.self, forKey: .outcome)
        outcome = FetchOutcome(rawValue: raw) ?? .ok
        attemptedAt = try c.decode(Date.self, forKey: .attemptedAt)
    }
}

// MARK: - Classification (pure)

enum FetchClassifier {
    /// HTTP status → outcome. Shared by all three loaders: the question is
    /// always "can the user fix this, or do they just wait?".
    static func outcome(forStatusCode code: Int) -> FetchOutcome {
        switch code {
        case 401, 403, 404:
            return .authOrTarget
        case 429:
            // Rate-limited is not literally unreachable, but it is transient
            // and not user-fixable, so it groups here rather than earning its
            // own outcome (PRD §11 C5).
            return .unreachable
        case 500...599:
            return .unreachable
        default:
            return .badResponse
        }
    }

    static func outcome(for error: Error) -> FetchOutcome {
        switch error {
        case let error as HostGitHubLoader.GitHubError:
            switch error {
            case .invalidRepo: return .authOrTarget
            case .serverError(let code): return outcome(forStatusCode: code)
            case .transport: return .unreachable
            case .invalidPayload: return .badResponse
            }
        case let error as HostWeatherLoader.WeatherError:
            switch error {
            case .invalidLocation: return .authOrTarget
            case .serverError(let code): return outcome(forStatusCode: code)
            case .transport: return .unreachable
            case .invalidPayload: return .badResponse
            }
        case let error as AzureDevOpsError:
            switch error {
            case .invalidTarget: return .authOrTarget
            case .serverError(let code):
                // Azure DevOps answers a bad or expired PAT with 203 and an
                // HTML sign-in page rather than 401, and redirects to the same
                // page. The shared table would call those "unexpected
                // response" and send the user hunting for a server fault
                // instead of looking at the token field.
                if (201...399).contains(code) { return .authOrTarget }
                return outcome(forStatusCode: code)
            case .transport: return .unreachable
            case .invalidPayload: return .badResponse
            }
        case let error as RemoteOpenCodeLoader.RemoteError:
            switch error {
            case .invalidURL, .unauthorized: return .authOrTarget
            case .serverError(let code): return outcome(forStatusCode: code)
            case .transport: return .unreachable
            }
        default:
            // Never accuse the user of misconfiguring something over an error
            // we don't recognise.
            return .unreachable
        }
    }
}

// MARK: - Copy (pure)

enum FetchStatusCopy {
    /// One short line for the widget face, or nil when there is nothing to say.
    static func line(source: FetchSource, outcome: FetchOutcome) -> String? {
        switch outcome {
        case .ok:
            return nil
        case .notConfigured:
            switch source {
            case .shipbox: return "Add a repo + token in settings"
            // An empty location is valid — wttr.in geolocates.
            case .weather: return nil
            case .opencodeRemote: return "Paste your opencode token"
            case .taskbox: return "Add org, project + PAT in settings"
            }
        case .authOrTarget:
            switch source {
            case .shipbox: return "Check repo + token"
            case .weather: return "Check the location"
            case .opencodeRemote: return "Check server URL + token"
            case .taskbox: return "Check org, project + PAT"
            }
        case .unreachable:
            switch source {
            case .shipbox: return "Can't reach GitHub"
            case .weather: return "Can't reach wttr.in"
            case .opencodeRemote: return "Can't reach the opencode server"
            case .taskbox: return "Can't reach Azure DevOps"
            }
        case .badResponse:
            switch source {
            case .shipbox: return "Unexpected GitHub response"
            case .weather: return "Unexpected wttr.in response"
            case .opencodeRemote: return "Unexpected server response"
            case .taskbox: return "Unexpected Azure DevOps response"
            }
        }
    }

    /// A full sentence for the settings window, where the fields that cause the
    /// failure are on screen and there is room to say what to do about it.
    /// Speaks exactly when `line` speaks.
    static func hint(source: FetchSource, outcome: FetchOutcome) -> String? {
        switch outcome {
        case .ok:
            return nil
        case .notConfigured:
            switch source {
            case .shipbox: return "Nothing is fetched until both a repo and a token are set."
            case .weather: return nil
            case .opencodeRemote: return "Remote mode fetches nothing until you paste your own token."
            case .taskbox: return "Nothing is fetched until an organization, a project and a token are all set."
            }
        case .authOrTarget:
            switch source {
            case .shipbox:
                return "GitHub rejected the request: check owner/repo and that the token is valid and can see it."
            case .weather:
                return "wttr.in didn't recognise that location — try a city name, or leave it empty to geolocate."
            case .opencodeRemote:
                return "The opencode server rejected the request: check the server URL and your token."
            case .taskbox:
                return "Azure DevOps rejected the request: check the organization and project names, and that the PAT is valid and not expired."
            }
        case .unreachable:
            switch source {
            case .shipbox: return "Couldn't reach api.github.com — offline, rate-limited, or GitHub is down."
            case .weather: return "Couldn't reach wttr.in — offline, or the service is down."
            case .opencodeRemote: return "Couldn't reach the opencode server — check it is running and reachable."
            case .taskbox: return "Couldn't reach dev.azure.com — offline, rate-limited, or Azure DevOps is down."
            }
        case .badResponse:
            switch source {
            case .shipbox: return "Reached GitHub, but the response couldn't be read. Retrying every minute."
            case .weather: return "Reached wttr.in, but the response couldn't be read. Retrying every minute."
            case .opencodeRemote: return "Reached the server, but the response couldn't be read. Retrying every minute."
            case .taskbox: return "Reached Azure DevOps, but the response couldn't be read. Retrying every minute."
            }
        }
    }
}

// MARK: - Face resolution (pure)

enum FetchChip {
    /// Past this with no attempt recorded, the agent is presumed not running.
    static let deadAgentThreshold: TimeInterval = 30 * 60

    /// The single place the face logic lives: what one line (if any) belongs
    /// on the widget next to the age hint.
    ///
    /// A failure chip only means something if an attempt was actually made, so
    /// a silent agent gets its own wording rather than an arbitrarily old
    /// reason — the widget still renders whatever data it has either way.
    static func text(
        source: FetchSource,
        status: FetchStatus?,
        dataWrittenAt: Date?,
        now: Date
    ) -> String? {
        let newest = [dataWrittenAt, status?.attemptedAt].compactMap { $0 }.max()
        guard let newest else { return "Agent hasn't run" }
        if now.timeIntervalSince(newest) > deadAgentThreshold { return "Agent hasn't run" }
        guard let status, status.outcome != .ok else { return nil }
        return FetchStatusCopy.line(source: source, outcome: status.outcome)
    }
}

// MARK: - Store

enum FetchStatusStore {
    static func fileURL(for source: FetchSource) -> URL {
        DeckSettings.containerDirectory
            .appendingPathComponent("fetch-\(source.rawValue).json")
    }

    static func load(from url: URL) -> FetchStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FetchStatus.self, from: data)
    }

    static func load(_ source: FetchSource) -> FetchStatus? {
        load(from: fileURL(for: source))
    }

    static func save(_ status: FetchStatus, to url: URL) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        _ = AtomicFile.write(data, to: url)
    }

    static func save(_ status: FetchStatus) {
        save(status, to: fileURL(for: status.source))
    }

    /// Records an attempt's outcome for `source`. Every fetch branch calls
    /// this — including the "not configured" skips and the successes, since a
    /// success is what clears a stale failure.
    @discardableResult
    static func record(_ outcome: FetchOutcome, for source: FetchSource, at date: Date = Date()) -> FetchOutcome {
        save(FetchStatus(source: source, outcome: outcome, attemptedAt: date))
        return outcome
    }
}
