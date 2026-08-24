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
    case shipbox, weather, opencodeRemote, taskbox, calbox
    /// PRBox is the first widget with two sources at once. They stay separate
    /// keys so a GitHub failure never clears an Azure success and each
    /// settings sub-tab shows its own sentence under its own fields.
    case prboxGitHub, prboxAzure
    /// MarketBox: one key for four providers. The loader only fails the fetch
    /// when no row at all could be priced, so a single source going down reads
    /// as a partial list with a note, not as a dead widget.
    case marketbox
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
        case let error as HostCalendarLoader.CalendarError:
            switch error {
            case .notConfigured: return .notConfigured
            case .accessDenied: return .authOrTarget
            case .readFailed: return .badResponse
            }
        case let error as RemoteOpenCodeLoader.RemoteError:
            switch error {
            case .invalidURL, .unauthorized: return .authOrTarget
            case .serverError(let code): return outcome(forStatusCode: code)
            case .transport: return .unreachable
            }
        case let error as MarketLoaderError:
            switch error {
            case .notConfigured: return .notConfigured
            // Every configured symbol resolved to no known kind — user-fixable.
            case .invalidSymbols: return .authOrTarget
            case .serverError(let code): return outcome(forStatusCode: code)
            case .transport: return .unreachable
            case .invalidPayload: return .badResponse
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
            case .prboxGitHub: return "add a token in settings"
            case .prboxAzure: return "add org, project + PAT in settings"
            // An empty location is valid — wttr.in geolocates.
            case .weather: return nil
            case .opencodeRemote: return "Paste your opencode token"
            case .taskbox: return "Add org, project + PAT in settings"
            case .calbox: return "Pick a calendar in settings"
            case .marketbox: return "Add symbols in settings"
            }
        case .authOrTarget:
            switch source {
            case .shipbox: return "Check repo + token"
            case .prboxGitHub: return "check token"
            case .prboxAzure: return "check org, project + PAT"
            case .weather: return "Check the location"
            case .opencodeRemote: return "Check server URL + token"
            case .taskbox: return "Check org, project + PAT"
            case .calbox: return "Allow calendar access"
            case .marketbox: return "Check the symbols"
            }
        case .unreachable:
            switch source {
            case .shipbox: return "Can't reach GitHub"
            case .prboxGitHub: return "offline"
            case .prboxAzure: return "can't reach Azure DevOps"
            case .weather: return "Can't reach wttr.in"
            case .opencodeRemote: return "Can't reach the opencode server"
            case .taskbox: return "Can't reach Azure DevOps"
            // No network in this path — kept only so the switch is total.
            case .calbox: return "Can't read the calendar"
            case .marketbox: return "Can't reach the price sources"
            }
        case .badResponse:
            switch source {
            case .shipbox: return "Unexpected GitHub response"
            case .prboxGitHub: return "unexpected GitHub response"
            case .prboxAzure: return "unexpected Azure DevOps response"
            case .weather: return "Unexpected wttr.in response"
            case .opencodeRemote: return "Unexpected server response"
            case .taskbox: return "Unexpected Azure DevOps response"
            case .calbox: return "Couldn't read the calendar"
            case .marketbox: return "Unexpected market response"
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
            case .prboxGitHub: return "Nothing is fetched until a token is set."
            case .prboxAzure: return "Nothing is fetched until an organization, a project and a token are all set."
            case .weather: return nil
            case .opencodeRemote: return "Remote mode fetches nothing until you paste your own token."
            case .taskbox: return "Nothing is fetched until an organization, a project and a token are all set."
            case .calbox: return "Nothing is read until at least one calendar is ticked."
            case .marketbox: return "Nothing is fetched until at least one symbol is set."
            }
        case .authOrTarget:
            switch source {
            case .shipbox:
                return "GitHub rejected the request: check owner/repo and that the token is valid and can see it."
            case .prboxGitHub:
                return "GitHub rejected the request: check that the token is valid and can see the repositories you expect."
            case .prboxAzure:
                return "Azure DevOps rejected the request, or the PAT's owner could not be identified: check the organization and project names, and that the PAT is valid and not expired. A read-only PAT that can see Code is enough."
            case .weather:
                return "wttr.in didn't recognise that location — try a city name, or leave it empty to geolocate."
            case .opencodeRemote:
                return "The opencode server rejected the request: check the server URL and your token."
            case .taskbox:
                return "Azure DevOps rejected the request: check the organization and project names, and that the PAT is valid and not expired."
            case .calbox:
                return "macOS is blocking calendar access. Grant it in System Settings → Privacy & Security → Calendars, for both Deck and DeckAgent."
            case .marketbox:
                return "The price sources didn't recognise a symbol: check the ticker list (crypto symbols like BTC, fiat codes like USD or CAD, and GOLD for 1 gram of gold)."
            }
        case .unreachable:
            switch source {
            case .shipbox: return "Couldn't reach api.github.com — offline, rate-limited, or GitHub is down."
            case .prboxGitHub: return "Couldn't reach api.github.com — offline, rate-limited, or GitHub is down."
            case .prboxAzure: return "Couldn't reach dev.azure.com — offline, rate-limited, or Azure DevOps is down."
            case .weather: return "Couldn't reach wttr.in — offline, or the service is down."
            case .opencodeRemote: return "Couldn't reach the opencode server — check it is running and reachable."
            case .taskbox: return "Couldn't reach dev.azure.com — offline, rate-limited, or Azure DevOps is down."
            case .calbox: return "Couldn't read the calendar store. Retrying every minute."
            case .marketbox: return "Couldn't reach a price source — offline, rate-limited, or a source is down. Retrying every minute."
            }
        case .badResponse:
            switch source {
            case .shipbox: return "Reached GitHub, but the response couldn't be read. Retrying every minute."
            case .prboxGitHub: return "Reached GitHub, but the response couldn't be read. Retrying every minute."
            case .prboxAzure: return "Reached Azure DevOps, but the response couldn't be read. Retrying every minute."
            case .weather: return "Reached wttr.in, but the response couldn't be read. Retrying every minute."
            case .opencodeRemote: return "Reached the server, but the response couldn't be read. Retrying every minute."
            case .taskbox: return "Reached Azure DevOps, but the response couldn't be read. Retrying every minute."
            case .calbox: return "Reached the calendar store but couldn't read it. Retrying every minute."
            case .marketbox: return "Reached the price sources, but the response couldn't be read. Retrying every minute."
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

// MARK: - PRBox chip (pure)
//
// PRBox is the first widget fed by two sources at once, so it is the first
// that can be half-broken: the header counts are a union, and a REVIEW count
// of 2 while GitHub is failing is not wrong, only partial. Nothing else on the
// face can say that, so the chip names the provider whose pull requests are
// missing.

enum PRFetchChip {
    /// One line for two providers, in strict precedence:
    ///
    /// 1. the agent is silent — every per-provider reason is stale by
    ///    definition, and blaming a token would send the user to the wrong
    ///    settings field;
    /// 2. nothing is configured;
    /// 3. both enabled providers are failing;
    /// 4. one is failing — named, because the counts quietly exclude it;
    /// 5. nothing to say.
    ///
    /// A disabled provider is ignored entirely, so switching one off also
    /// silences the failure it left behind.
    static func text(
        github: FetchStatus?,
        azure: FetchStatus?,
        githubEnabled: Bool,
        azureEnabled: Bool,
        dataWrittenAt: Date?,
        now: Date
    ) -> String? {
        guard githubEnabled || azureEnabled else { return "Not configured" }

        let attempts = [
            githubEnabled ? github?.attemptedAt : nil,
            azureEnabled ? azure?.attemptedAt : nil,
        ].compactMap { $0 }

        let newest = ([dataWrittenAt] + attempts.map { Optional($0) }).compactMap { $0 }.max()
        guard let newest else { return "Agent hasn't run" }
        if now.timeIntervalSince(newest) > FetchChip.deadAgentThreshold {
            return "Agent hasn't run"
        }

        var failures: [(name: String, source: FetchSource, outcome: FetchOutcome)] = []
        if githubEnabled, let github, github.outcome != .ok {
            failures.append(("GitHub", .prboxGitHub, github.outcome))
        }
        if azureEnabled, let azure, azure.outcome != .ok {
            failures.append(("Azure", .prboxAzure, azure.outcome))
        }
        guard let first = failures.first else { return nil }

        guard let reason = FetchStatusCopy.line(source: first.source, outcome: first.outcome) else {
            return nil
        }

        // Both down for the same reason is one fact, not two.
        if failures.count == 2, failures[0].outcome == failures[1].outcome {
            return "GitHub + Azure: \(reason)"
        }
        // Two different reasons cannot both fit; name one rather than imply
        // they share a cause.
        if failures.count == 2 {
            return "\(first.name): \(reason) +1 more"
        }
        return "\(first.name): \(reason)"
    }
}
