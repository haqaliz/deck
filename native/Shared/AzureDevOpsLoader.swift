import Foundation

// MARK: - Azure DevOps work items (host/agent only — unsandboxed)
//
// Three calls per refresh:
//   1. WIQL      → the ids assigned to the PAT's owner
//   2. batch     → the fields for those ids
//   3. iterations→ the sprint calendar, for the due-date fallback (best effort)
//
// The PAT is sent only to dev.azure.com over TLS, as HTTP Basic with an empty
// username. No default token is ever sent: an empty token means no fetch.

enum AzureDevOpsError: Error, Equatable {
    /// Organization or project is empty or unusable.
    case invalidTarget
    case serverError(Int)
    case transport(String)
    case invalidPayload
}

// MARK: - Target normalisation (pure)

/// A validated org/project pair, with both path segments percent-encoded and
/// the raw names kept for display.
struct AzureTarget: Equatable {
    /// Raw, trimmed — what the user typed, for the header.
    let organizationName: String
    let projectName: String
    /// Percent-encoded path segments.
    let organizationSegment: String
    let projectSegment: String

    var orgBase: String { "https://dev.azure.com/\(organizationSegment)" }
    var projectBase: String { "\(orgBase)/\(projectSegment)" }

    /// Header text: just the project when the names match (the common case for
    /// a single-project org), both when they differ.
    var scope: String {
        organizationName == projectName
            ? projectName
            : "\(organizationName) / \(projectName)"
    }

    /// Accepts a bare org name, a full `https://dev.azure.com/{org}` URL, or
    /// either with a trailing slash, and resolves all of them to one base.
    /// Both segments are percent-encoded, so a project name containing a space
    /// yields a valid URL rather than a malformed one that would surface as
    /// "unexpected response" and blame the server for a client bug.
    static func normalise(organization: String, project: String) throws -> AzureTarget {
        let org = strippedOrganization(organization)
        let proj = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !org.isEmpty, !proj.isEmpty else { throw AzureDevOpsError.invalidTarget }
        guard
            let orgSegment = org.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let projSegment = proj.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw AzureDevOpsError.invalidTarget }
        return AzureTarget(
            organizationName: org,
            projectName: proj,
            organizationSegment: orgSegment,
            projectSegment: projSegment
        )
    }

    private static func strippedOrganization(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://dev.azure.com/", "http://dev.azure.com/"] {
            if value.lowercased().hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                break
            }
        }
        while value.hasSuffix("/") { value = String(value.dropLast()) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Date parsing (pure)

enum AzureDate {
    /// Azure DevOps is inconsistent about fractional seconds across fields, and
    /// system fields can return seven digits — more than ISO8601DateFormatter
    /// accepts. Trying plain, then fractional, then a fraction-stripped retry
    /// covers all three without guessing per field.
    static func parse(_ raw: Any?) -> Date? {
        guard let string = raw as? String, !string.isEmpty else { return nil }
        if let date = plain.date(from: string) { return date }
        if let date = fractional.date(from: string) { return date }
        if let stripped = strippingFraction(string), let date = plain.date(from: stripped) {
            return date
        }
        return nil
    }

    /// "2026-08-24T00:00:00.0000000Z" -> "2026-08-24T00:00:00Z"
    private static func strippingFraction(_ string: String) -> String? {
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let rest = string[dot...]
        guard let end = rest.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else {
            return nil
        }
        return String(string[string.startIndex..<dot]) + String(rest[end...])
    }

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - WIQL id parser (pure)

struct ParsedWiql: Equatable {
    /// Every match, before the batch cap — this is what the header counts.
    var total: Int
    /// The ids actually fetched, capped, in WIQL order (most recently changed
    /// first).
    var ids: [Int]
}

enum WiqlIdParser {
    /// The workitemsbatch endpoint's own ceiling. The face shows at most 8
    /// rows, but the lane counts describe everything fetched, so the cap is set
    /// as high as the API allows rather than as low as the list needs.
    static let idLimit = 200

    /// `nil` means the payload could not be read. An empty `ids` means the
    /// query ran and matched nothing — "nothing assigned" is a success.
    static func parse(_ data: Data) -> ParsedWiql? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["workItems"] as? [[String: Any]]
        else { return nil }
        let ids = items.compactMap { ($0["id"] as? NSNumber)?.intValue }
        return ParsedWiql(total: ids.count, ids: Array(ids.prefix(idLimit)))
    }
}

// MARK: - Current sprint parser (pure)

enum CurrentSprintParser {
    /// The team's current iteration name, e.g. "Sprint 57". Best-effort: a team
    /// between sprints has none, and the header then shows nothing rather than
    /// a stale or invented sprint.
    static func parse(_ data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let values = json["value"] as? [[String: Any]],
            let first = values.first
        else { return nil }
        if let name = first["name"] as? String, !name.isEmpty { return name }
        // Fall back to the leaf of the backslash-separated path.
        if let path = first["path"] as? String, let leaf = path.split(separator: "\\").last {
            return String(leaf)
        }
        return nil
    }
}

// MARK: - Work item batch parser (pure)

enum WorkItemParser {
    /// Contract notes: `fields` is a flat dictionary keyed by reference name;
    /// absent fields are omitted rather than null; `id` is a number; the
    /// entry's own `url` is the *API* endpoint, not a browsable link.
    static func parse(_ data: Data, target: AzureTarget) -> [TaskItem]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let values = json["value"] as? [[String: Any]]
        else { return nil }
        return values.compactMap { item(from: $0, target: target) }
    }

    private static func item(from entry: [String: Any], target: AzureTarget) -> TaskItem? {
        guard let fields = entry["fields"] as? [String: Any] else { return nil }
        // No title, no task. Defaulting to "Untitled" would put a phantom row
        // on the face.
        guard let title = fields["System.Title"] as? String, !title.isEmpty else { return nil }

        let id = (entry["id"] as? NSNumber)?.intValue
            ?? (fields["System.Id"] as? NSNumber)?.intValue
        guard let id else { return nil }

        return TaskItem(
            id: String(id),
            title: title,
            state: (fields["System.State"] as? String) ?? "",
            itemType: (fields["System.WorkItemType"] as? String) ?? "",
            url: "\(target.projectBase)/_workitems/edit/\(id)",
            provider: .azureDevOps,
            changedAt: AzureDate.parse(fields["System.ChangedDate"])
        )
    }
}

// MARK: - Fetch (host/agent only — unsandboxed)

enum HostAzureDevOpsLoader {
    /// Open work items assigned to the PAT's owner in the configured project,
    /// most recently changed first, plus the team's current sprint.
    ///
    /// `@Me` resolves to whoever owns the PAT — not to whoever is signed in to
    /// the `az` CLI or the browser.
    static func fetch(
        organization: String,
        project: String,
        token: String
    ) async throws -> TaskBoxSnapshot {
        let target = try AzureTarget.normalise(organization: organization, project: project)
        let auth = "Basic " + Data(":\(token)".utf8).base64EncodedString()

        let wiql = try await workItemIDs(target: target, auth: auth)
        let sprint = await currentSprint(target: target, auth: auth)

        // Nothing assigned is a real answer, and it skips the batch entirely.
        guard !wiql.ids.isEmpty else {
            return TaskBoxSnapshot(
                writtenAt: Date(), scope: target.scope,
                totalCount: wiql.total, sprint: sprint, tasks: []
            )
        }

        let tasks = try await workItems(ids: wiql.ids, target: target, auth: auth)
        return TaskBoxSnapshot(
            writtenAt: Date(),
            scope: target.scope,
            totalCount: wiql.total,
            sprint: sprint,
            tasks: TaskFormatting.sorted(tasks)
        )
    }

    /// Fixed in code rather than user-editable: a hand-written WIQL that
    /// matches nothing is indistinguishable from one that is wrong, and the
    /// failure copy could not tell the user which.
    ///
    /// `[System.TeamProject] = @project` is load-bearing. The project in the
    /// request URL only sets the macro context; without this clause the query
    /// spans every project the PAT can read, which on the dev org returned 67
    /// items across three projects instead of the 25 actually in the
    /// configured one.
    private static let wiqlQuery = """
    SELECT [System.Id] FROM WorkItems \
    WHERE [System.TeamProject] = @project \
    AND [System.AssignedTo] = @Me \
    AND [System.State] NOT IN ('Closed', 'Removed', 'Done') \
    ORDER BY [System.ChangedDate] DESC
    """

    private static func workItemIDs(target: AzureTarget, auth: String) async throws -> ParsedWiql {
        guard let url = URL(string: "\(target.projectBase)/_apis/wit/wiql?api-version=7.1") else {
            throw AzureDevOpsError.invalidTarget
        }
        let data = try await send(url: url, auth: auth, body: ["query": wiqlQuery])
        guard let parsed = WiqlIdParser.parse(data) else { throw AzureDevOpsError.invalidPayload }
        return parsed
    }

    private static func workItems(
        ids: [Int], target: AzureTarget, auth: String
    ) async throws -> [TaskItem] {
        guard let url = URL(string: "\(target.orgBase)/_apis/wit/workitemsbatch?api-version=7.1") else {
            throw AzureDevOpsError.invalidTarget
        }
        let body: [String: Any] = [
            "ids": ids,
            "fields": [
                "System.Id",
                "System.Title",
                "System.State",
                "System.WorkItemType",
                "System.ChangedDate",
            ],
            // Required, not cosmetic: without it the whole batch fails when a
            // single id is inaccessible or was deleted between the WIQL call
            // and this one — a real race at a 60s cadence.
            "errorPolicy": "omit",
        ]
        let data = try await send(url: url, auth: auth, body: body)
        guard let tasks = WorkItemParser.parse(data, target: target) else {
            throw AzureDevOpsError.invalidPayload
        }
        return tasks
    }

    /// Best-effort: any failure yields nil and the header simply omits the
    /// sprint. A missing iteration must never fail the tick or blank a working
    /// task list.
    private static func currentSprint(target: AzureTarget, auth: String) async -> String? {
        guard let url = URL(
            string: "\(target.projectBase)/_apis/work/teamsettings/iterations?$timeframe=current&api-version=7.1"
        ) else { return nil }
        guard let data = try? await send(url: url, auth: auth, body: nil) else { return nil }
        return CurrentSprintParser.parse(data)
    }

    /// `body == nil` sends a GET; otherwise a JSON POST.
    private static func send(url: URL, auth: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let encoded = try? JSONSerialization.data(withJSONObject: body) else {
                throw AzureDevOpsError.invalidPayload
            }
            request.httpBody = encoded
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AzureDevOpsError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AzureDevOpsError.transport("Not an HTTP response")
        }
        // Anything but a clean 200 is an error, including the 203 sign-in page
        // Azure DevOps serves for a bad PAT — the classifier reads the code.
        guard http.statusCode == 200 else {
            throw AzureDevOpsError.serverError(http.statusCode)
        }
        return data
    }
}

// MARK: - PRBox: identity (pure)
//
// The Git pull-request API takes identity GUIDs for `creatorId` and
// `reviewerId`. It has no `@Me` macro — and, critically, it does not reject a
// value it cannot parse. Measured against a live organization:
//
//     …/pullrequests?searchCriteria.status=active                    → 6
//       &searchCriteria.creatorId=@me                                → 6   (200, unfiltered)
//       &searchCriteria.creatorId=<well-formed unknown GUID>         → 0
//
// So an unresolvable identity must fail the fetch rather than fall back. An
// unfiltered query renders every open pull request in the project as though it
// were the user's own work, and nothing about the response says otherwise.

enum ConnectionDataParser {
    /// The PAT owner's identity GUID, or nil if the payload doesn't carry one.
    /// An empty string is nil: interpolated into the query it produces the
    /// unfiltered case again.
    static func parse(_ data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let user = root["authenticatedUser"] as? [String: Any],
            let id = user["id"] as? String,
            !id.isEmpty
        else { return nil }
        return id
    }
}

// MARK: - PRBox: pull-request parser (pure)

enum AzurePRParser {
    /// nil means "couldn't read the answer"; an empty array means "no pull
    /// requests". The face words those differently.
    static func parse(
        _ data: Data, role: PRRole, me: String, target: AzureTarget
    ) -> [PullRequestItem]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["value"] as? [[String: Any]]
        else { return nil }

        return rows.compactMap { item(from: $0, role: role, me: me, target: target) }
    }

    private static func item(
        from entry: [String: Any], role: PRRole, me: String, target: AzureTarget
    ) -> PullRequestItem? {
        guard
            let number = entry["pullRequestId"] as? Int,
            let title = entry["title"] as? String,
            let repository = entry["repository"] as? [String: Any],
            let repo = repository["name"] as? String,
            let createdAt = AzureDate.parse(entry["creationDate"])
        else { return nil }

        // `reviewerId` returns every pull request the user is a reviewer on,
        // including ones already voted on, while GitHub drops a PR from
        // `review-requested` as soon as it is reviewed. Keeping only the
        // unvoted ones makes one list mean one thing.
        if role == .reviewing, !isAwaitingVote(from: me, in: entry) { return nil }

        return PullRequestItem(
            id: "azureDevOps:\(repo)#\(number)",
            number: number,
            title: title,
            repo: repo,
            role: role,
            provider: .azureDevOps,
            isDraft: entry["isDraft"] as? Bool ?? false,
            createdAt: createdAt,
            url: webURL(target: target, repo: repo, number: number)
        )
    }

    private static func isAwaitingVote(from me: String, in entry: [String: Any]) -> Bool {
        guard let reviewers = entry["reviewers"] as? [[String: Any]] else { return false }
        guard let mine = reviewers.first(where: { $0["id"] as? String == me }) else { return false }
        return (mine["vote"] as? Int ?? 0) == 0
    }

    /// The payload has no browsable link — `url` is the REST endpoint and
    /// `repository.webUrl` is absent — so the web URL is constructed.
    static func webURL(target: AzureTarget, repo: String, number: Int) -> String {
        let repoSegment = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        return "\(target.projectBase)/_git/\(repoSegment)/pullrequest/\(number)"
    }
}

// MARK: - PRBox: count ceiling

enum AzurePRCap {
    /// How many rows to ask for. Deliberately larger than any row cap the face
    /// can show: Azure DevOps reports no total for a pull-request query — the
    /// response carries `count` (rows returned) and nothing else — so asking
    /// for exactly the row cap would make every count saturate at the cap and
    /// silently understate the queue.
    static let ceiling = 101

    /// A fetch that came back full can only promise "at least this many".
    static func isCapped(rowCount: Int, ceiling: Int = ceiling) -> Bool {
        rowCount >= ceiling
    }
}

// MARK: - PRBox: fetch (host/agent only — unsandboxed)

enum HostAzurePRLoader {
    /// Both roles, identity-scoped. Three requests on the first tick and two
    /// after it, since the GUID only changes when the PAT's owner does.
    static func fetch(
        organization: String, project: String, token: String, cap: Int
    ) async throws -> PRRoleTotals {
        let target = try AzureTarget.normalise(organization: organization, project: project)
        let auth = "Basic " + Data(":\(token)".utf8).base64EncodedString()

        let me = try await identity(target: target, auth: auth)

        var items: [PullRequestItem] = []
        var totals: [PRRole: (count: Int, capped: Bool)] = [:]

        for role in [PRRole.authored, PRRole.reviewing] {
            let data = try await send(role: role, me: me, target: target, auth: auth)
            guard let parsed = AzurePRParser.parse(data, role: role, me: me, target: target) else {
                throw AzureDevOpsError.invalidPayload
            }
            // Counted after the vote filter, so the header matches the rows.
            totals[role] = (parsed.count, AzurePRCap.isCapped(rowCount: parsed.count))
            items.append(contentsOf: parsed.prefix(cap))
        }

        return PRRoleTotals(
            authoredTotal: totals[.authored]?.count ?? 0,
            reviewingTotal: totals[.reviewing]?.count ?? 0,
            authoredCapped: totals[.authored]?.capped ?? false,
            reviewingCapped: totals[.reviewing]?.capped ?? false,
            items: items
        )
    }

    /// Resolves the PAT owner's GUID, or throws. See `ConnectionDataParser` for
    /// why there is no fallback.
    static func requireIdentity(_ data: Data) throws -> String {
        guard let id = ConnectionDataParser.parse(data) else {
            throw AzureDevOpsError.invalidTarget
        }
        return id
    }

    private static func identity(target: AzureTarget, auth: String) async throws -> String {
        guard let url = URL(string: "\(target.orgBase)/_apis/connectionData?api-version=7.1-preview") else {
            throw AzureDevOpsError.invalidTarget
        }
        return try requireIdentity(try await get(url: url, auth: auth))
    }

    private static func send(
        role: PRRole, me: String, target: AzureTarget, auth: String
    ) async throws -> Data {
        let criterion = role == .authored ? "creatorId" : "reviewerId"
        var components = URLComponents(string: "\(target.projectBase)/_apis/git/pullrequests")
        components?.queryItems = [
            URLQueryItem(name: "searchCriteria.status", value: "active"),
            URLQueryItem(name: "searchCriteria.\(criterion)", value: me),
            URLQueryItem(name: "$top", value: String(AzurePRCap.ceiling)),
            URLQueryItem(name: "api-version", value: "7.1"),
        ]
        guard let url = components?.url else { throw AzureDevOpsError.invalidTarget }
        return try await get(url: url, auth: auth)
    }

    private static func get(url: URL, auth: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AzureDevOpsError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AzureDevOpsError.transport("Not an HTTP response")
        }
        // A bad or expired PAT answers 203 with an HTML sign-in page rather
        // than 401; FetchClassifier maps 201...399 to authOrTarget for exactly
        // this reason.
        guard http.statusCode == 200 else {
            throw AzureDevOpsError.serverError(http.statusCode)
        }
        return data
    }
}
