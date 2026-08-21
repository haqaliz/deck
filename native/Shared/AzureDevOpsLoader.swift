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

enum WiqlIdParser {
    /// Hard cap: the batch endpoint takes 200 ids and the face shows at most 8.
    static let idLimit = 50

    /// `nil` means the payload could not be read. `[]` means the query ran and
    /// matched nothing — "nothing assigned" is a success, not a failure.
    static func parse(_ data: Data) -> [Int]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["workItems"] as? [[String: Any]]
        else { return nil }
        let ids = items.compactMap { ($0["id"] as? NSNumber)?.intValue }
        return Array(ids.prefix(idLimit))
    }
}

// MARK: - Iteration calendar parser (pure)

enum IterationMapParser {
    /// `System.IterationPath` → the iteration's finish date.
    ///
    /// Returns a map, never an optional: this call is best-effort, so its
    /// failure mode is "no fallback dates available", never "the fetch failed".
    /// Keys are the raw backslash-separated paths, matched later byte for byte.
    static func parse(_ data: Data) -> [String: Date] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let values = json["value"] as? [[String: Any]]
        else { return [:] }

        var map: [String: Date] = [:]
        for entry in values {
            guard
                let path = entry["path"] as? String,
                let attributes = entry["attributes"] as? [String: Any],
                let finish = AzureDate.parse(attributes["finishDate"])
            else { continue }
            map[path] = finish
        }
        return map
    }
}

// MARK: - Work item batch parser (pure)

enum WorkItemParser {
    /// Contract notes: `fields` is a flat dictionary keyed by reference name;
    /// absent fields are omitted rather than null; `id` is a number; the
    /// entry's own `url` is the *API* endpoint, not a browsable link.
    static func parse(
        _ data: Data,
        target: AzureTarget,
        iterationEnds: [String: Date]
    ) -> [TaskItem]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let values = json["value"] as? [[String: Any]]
        else { return nil }
        return values.compactMap { item(from: $0, target: target, iterationEnds: iterationEnds) }
    }

    private static func item(
        from entry: [String: Any],
        target: AzureTarget,
        iterationEnds: [String: Date]
    ) -> TaskItem? {
        guard let fields = entry["fields"] as? [String: Any] else { return nil }
        // No title, no task. Defaulting to "Untitled" would put a phantom row
        // on the face.
        guard let title = fields["System.Title"] as? String, !title.isEmpty else { return nil }

        let id = (entry["id"] as? NSNumber)?.intValue
            ?? (fields["System.Id"] as? NSNumber)?.intValue
        guard let id else { return nil }

        let due = TaskFormatting.resolveDue(
            dueDate: AzureDate.parse(fields["Microsoft.VSTS.Scheduling.DueDate"]),
            targetDate: AzureDate.parse(fields["Microsoft.VSTS.Scheduling.TargetDate"]),
            iterationPath: fields["System.IterationPath"] as? String,
            iterationEnds: iterationEnds
        )

        return TaskItem(
            id: String(id),
            title: title,
            state: (fields["System.State"] as? String) ?? "",
            itemType: (fields["System.WorkItemType"] as? String) ?? "",
            url: "\(target.projectBase)/_workitems/edit/\(id)",
            provider: .azureDevOps,
            dueDate: due.date,
            dueSource: due.source,
            changedAt: AzureDate.parse(fields["System.ChangedDate"])
        )
    }
}
