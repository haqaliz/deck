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

/// One target per project, for an account that carries several.
enum AzureTargets {
    static func normalise(organization: String, projects: [String]) throws -> [AzureTarget] {
        let names = AzureAccountProjects.normalise(projects)
        guard !names.isEmpty else { throw AzureDevOpsError.invalidTarget }
        return try names.map { try AzureTarget.normalise(organization: organization, project: $0) }
    }
}

/// Merging several projects' work-item ids into the one organization-scoped
/// batch call.
enum AzureIDMerge {
    /// Round-robin, then truncate.
    ///
    /// The batch endpoint takes 200 ids, and concatenating instead would spend
    /// the whole budget on whichever project happens to be first — a user with
    /// one busy project would never see a row from the quiet ones. Taking in
    /// turns gives every project a share of the ceiling.
    static func interleave(_ lists: [[Int]], limit: Int) -> [Int] {
        var out: [Int] = []
        var index = 0
        var exhausted = false
        while !exhausted, out.count < limit {
            exhausted = true
            for list in lists where index < list.count {
                exhausted = false
                out.append(list[index])
                if out.count == limit { break }
            }
            index += 1
        }
        return out
    }
}

/// What the TaskBox header calls the thing it is showing.
enum TaskBoxScope {
    /// One project keeps today's wording exactly. Several show the
    /// organization, because naming one of them would be a lie about the rest.
    ///
    /// The name comes from the **targets**, never from the raw setting: the
    /// organization field accepts a full `https://dev.azure.com/{org}` URL, and
    /// only `AzureTarget.normalise` has stripped it.
    static func scope(organization: String, targets: [AzureTarget]) -> String {
        guard targets.count == 1, let only = targets.first else {
            let name = targets.first?.organizationName
                ?? organization.trimmingCharacters(in: .whitespacesAndNewlines)
            return name
        }
        return only.scope
    }
}

/// "which project could not be read", worded like ShipBox's per-repo note.
enum AzureProjectNote {
    struct Failure: Equatable {
        var project: String
        var outcome: FetchOutcome
    }

    /// One failure names itself; several sharing a reason collapse into one
    /// sentence; mixed reasons name the first rather than implying a shared
    /// cause.
    static func compose(failures: [Failure], source: FetchSource) -> String? {
        guard let first = failures.first else { return nil }
        guard let line = FetchStatusCopy.line(source: source, outcome: first.outcome),
              let initial = line.first
        else { return nil }
        let reason = line.replacingCharacters(
            in: line.startIndex...line.startIndex, with: initial.lowercased()
        )
        let others = failures.count - 1
        guard others > 0 else { return "\(first.project): \(reason)" }
        if failures.allSatisfy({ $0.outcome == first.outcome }) {
            return "\(first.project) + \(others) more: \(reason)"
        }
        return "\(first.project): \(reason) +\(others) more"
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

    /// The row's own project when it named one, the queried project otherwise.
    private static func projectBase(for project: String?, in target: AzureTarget) -> String {
        guard let project,
              let segment = project.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return target.projectBase }
        return "\(target.orgBase)/\(segment)"
    }

    private static func item(from entry: [String: Any], target: AzureTarget) -> TaskItem? {
        guard let fields = entry["fields"] as? [String: Any] else { return nil }
        // The batch endpoint is organization-scoped, so one response can carry
        // rows from every configured project. Without this the row would deep
        // link into whichever project happened to be queried.
        let project = (fields["System.TeamProject"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
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
            url: "\(projectBase(for: project, in: target))/_workitems/edit/\(id)",
            provider: .azureDevOps,
            changedAt: AzureDate.parse(fields["System.ChangedDate"]),
            project: project
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
        projects: [String],
        token: String
    ) async throws -> TaskBoxSnapshot {
        let targets = try AzureTargets.normalise(organization: organization, projects: projects)
        let auth = "Basic " + Data(":\(token)".utf8).base64EncodedString()
        let scope = TaskBoxScope.scope(organization: organization, targets: targets)

        // Concurrent, not serial: `timeoutInterval` is per request, so five
        // projects at a 10s timeout could otherwise spend most of the 60s tick
        // waiting. Five sources measured 9.4s serially against 2.1s in
        // parallel.
        let queried = try await inParallel(targets) { target in
            try await workItemIDs(target: target, auth: auth)
        }

        var idLists: [[Int]] = []
        var total = 0
        var failures: [AzureProjectNote.Failure] = []
        var firstError: Error?
        for (target, result) in zip(targets, queried) {
            switch result {
            case .success(let wiql):
                idLists.append(wiql.ids)
                total += wiql.total
            case .failure(let error):
                failures.append(.init(
                    project: target.projectName, outcome: FetchClassifier.outcome(for: error)
                ))
                firstError = firstError ?? error
            }
        }

        // Reaching none of them is a failed tick: throwing leaves the last good
        // snapshot standing rather than blanking the widget. Reaching some is a
        // partial answer, which is worth more than nothing and says so.
        if idLists.isEmpty, let firstError { throw firstError }
        let note = AzureProjectNote.compose(failures: failures, source: .taskbox)

        // The sprint is per project *and* per team, so it can only be shown
        // when there is exactly one project to be wrong about.
        let sprint = targets.count == 1
            ? await currentSprint(target: targets[0], auth: auth)
            : nil

        let ids = AzureIDMerge.interleave(idLists, limit: WiqlIdParser.idLimit)

        // Nothing assigned is a real answer, and it skips the batch entirely.
        guard !ids.isEmpty else {
            return TaskBoxSnapshot(
                writtenAt: Date(), scope: scope,
                totalCount: total, sprint: sprint, tasks: [], note: note
            )
        }

        // One call for every project: `workitemsbatch` is organization-scoped,
        // and each row names its own project.
        let tasks = try await workItems(ids: ids, target: targets[0], auth: auth)
        return TaskBoxSnapshot(
            writtenAt: Date(),
            scope: scope,
            totalCount: total,
            sprint: sprint,
            tasks: TaskFormatting.sorted(tasks),
            note: note
        )
    }

    /// The ShipBox fan-out, which is the codebase's one concurrent loader.
    private static func inParallel<S, T>(
        _ inputs: [S],
        _ work: @escaping @Sendable (S) async throws -> T
    ) async throws -> [Result<T, Error>] where S: Sendable, T: Sendable {
        try await withThrowingTaskGroup(of: (Int, Result<T, Error>).self) { group in
            for (index, input) in inputs.enumerated() {
                group.addTask {
                    do { return (index, .success(try await work(input))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var collected: [(Int, Result<T, Error>)] = []
            for try await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
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
                // Load-bearing: the batch is organization-scoped, so this is
                // the only thing that says which project a row came from.
                "System.TeamProject",
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

// MARK: - Project discovery (settings window only)

/// The projects a PAT can see, for the account editor's five slots.
enum AzureProjectsParser {
    /// nil means "couldn't read the answer"; an empty array means "this PAT
    /// sees no project", which the editor words differently.
    ///
    /// Sorted by name rather than left in API order or sorted by
    /// `lastUpdateTime`: a picker whose entries move between openings is worse
    /// than one that is merely alphabetical.
    static func parse(_ data: Data) -> [String]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["value"] as? [[String: Any]]
        else { return nil }

        return rows
            .compactMap { row -> String? in
                guard let name = (row["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
                else { return nil }
                // A project mid-creation or mid-deletion cannot be queried;
                // an absent state is not a claim either way.
                if let state = row["state"] as? String, state != "wellFormed" { return nil }
                return name
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// Host-app only, and never on the agent tick: this exists to populate a picker
/// while someone is looking at the settings window.
enum HostAzureProjectsLoader {
    static func list(organization: String, token: String) async throws -> [String] {
        // The project is irrelevant to this endpoint; `normalise` needs one.
        let target = try AzureTarget.normalise(organization: organization, project: "_")
        guard let url = URL(string: "\(target.orgBase)/_apis/projects?api-version=7.1&$top=200")
        else { throw AzureDevOpsError.invalidTarget }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Basic " + Data(":\(token)".utf8).base64EncodedString(),
            forHTTPHeaderField: "Authorization"
        )
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
        guard http.statusCode == 200 else { throw AzureDevOpsError.serverError(http.statusCode) }
        guard let names = AzureProjectsParser.parse(data) else {
            throw AzureDevOpsError.invalidPayload
        }
        return names
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
            // The project is part of the identity, not decoration: PR numbers
            // are per repo and a repo name is only unique within its project,
            // so two projects with an `api` repo would otherwise share an id —
            // a duplicate ForEach key, and one row silently dropped.
            id: "azureDevOps:\(target.projectName)/\(repo)#\(number)",
            number: number,
            title: title,
            repo: repo,
            role: role,
            provider: .azureDevOps,
            isDraft: entry["isDraft"] as? Bool ?? false,
            createdAt: createdAt,
            url: webURL(target: target, repo: repo, number: number),
            project: target.projectName
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
        organization: String, projects: [String], token: String, cap: Int
    ) async throws -> PRRoleTotals {
        let targets = try AzureTargets.normalise(organization: organization, projects: projects)
        let auth = "Basic " + Data(":\(token)".utf8).base64EncodedString()

        // One call for every project: `connectionData` is organization-scoped,
        // and the identity only changes when the PAT's owner does.
        let me = try await identity(target: targets[0], auth: auth)

        // Every project × both roles at once. Serially this is 2N round trips
        // at a 10s timeout each, against a 60s tick.
        let queries = targets.flatMap { target in
            [PRRole.authored, PRRole.reviewing].map { (target: target, role: $0) }
        }
        let results = try await inParallel(queries) { query in
            let data = try await send(role: query.role, me: me, target: query.target, auth: auth)
            guard let parsed = AzurePRParser.parse(
                data, role: query.role, me: me, target: query.target
            ) else { throw AzureDevOpsError.invalidPayload }
            return parsed
        }

        var items: [PullRequestItem] = []
        var totals: [PRRole: (count: Int, capped: Bool)] = [
            .authored: (0, false), .reviewing: (0, false),
        ]
        var failures: [AzureProjectNote.Failure] = []
        var firstError: Error?
        var succeeded = false

        for (query, result) in zip(queries, results) {
            switch result {
            case .success(let parsed):
                succeeded = true
                // Counted after the vote filter, so the header matches the rows.
                let running = totals[query.role] ?? (0, false)
                totals[query.role] = (
                    running.count + parsed.count,
                    running.capped || AzurePRCap.isCapped(rowCount: parsed.count)
                )
                items.append(contentsOf: parsed.prefix(cap))
            case .failure(let error):
                let outcome = FetchClassifier.outcome(for: error)
                // Both roles of one project failing is one thing to say, not two.
                if !failures.contains(where: { $0.project == query.target.projectName }) {
                    failures.append(.init(project: query.target.projectName, outcome: outcome))
                }
                firstError = firstError ?? error
            }
        }

        // Same rule as TaskBox: some is a partial answer, none is a failed tick.
        if !succeeded, let firstError { throw firstError }

        return PRRoleTotals(
            authoredTotal: totals[.authored]?.count ?? 0,
            reviewingTotal: totals[.reviewing]?.count ?? 0,
            authoredCapped: totals[.authored]?.capped ?? false,
            reviewingCapped: totals[.reviewing]?.capped ?? false,
            items: items,
            note: AzureProjectNote.compose(failures: failures, source: .prboxAzure)
        )
    }

    /// The ShipBox fan-out. See `HostAzureDevOpsLoader.inParallel`.
    private static func inParallel<S, T>(
        _ inputs: [S],
        _ work: @escaping @Sendable (S) async throws -> T
    ) async throws -> [Result<T, Error>] where S: Sendable, T: Sendable {
        try await withThrowingTaskGroup(of: (Int, Result<T, Error>).self) { group in
            for (index, input) in inputs.enumerated() {
                group.addTask {
                    do { return (index, .success(try await work(input))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var collected: [(Int, Result<T, Error>)] = []
            for try await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
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
