import Foundation

// MARK: - Pull request search (PRBox)
//
// GitHub and Azure DevOps, reached with the `pr ` prefix. Built and tested on
// FIXTURES ONLY — no live request has been made against either service. The
// payload shapes follow each API's documentation and what PRBox's own parsers
// already read; `docs/planning/spotlight-more-sources/verification.md` lists
// what that leaves unverified.
//
//   GitHub  `search/issues` with every typed word quoted, so a typed `org:evil`
//           or `-involves:@me` is a phrase and not a qualifier. Scope is PRBox's
//           own scope setting, or `involves:@me` when there is none.
//   Azure   by id through the organisation-level route; by words, the most
//           recent 100 pull requests per project of any status, filtered
//           locally, because the list API has no text criteria.

enum PRSearchState: Equatable {
    case open, merged, closed
}

struct PRSearchHit: Equatable {
    var provider: PRProvider
    /// GitHub: "owner/repo". Azure: the repository name.
    var repo: String
    /// Azure only.
    var project: String?
    var number: Int
    var title: String
    var description: String
    var state: PRSearchState
    var isDraft: Bool
    var author: String
    var url: String
    var updated: Date?

    /// A number repeats across providers, repositories and projects.
    var id: String {
        switch provider {
        case .github: "pr:github:\(repo)#\(number)"
        case .azureDevOps: "pr:azure:\(project ?? "")/\(repo)#\(number)"
        default: "pr:\(provider):\(project ?? "")/\(repo)#\(number)"
        }
    }
}

enum PRSearch {
    static let totalLimit = 25

    static func stateWord(_ hit: PRSearchHit) -> String {
        if hit.state == .open, hit.isDraft { return "Draft" }
        switch hit.state {
        case .open: return "Open"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }

    /// Nothing is filtered out here: the service already decided these match
    /// (GitHub searched the body too), and a matcher that only reads titles must
    /// not drop them. The matcher only orders.
    static func results(from hits: [PRSearchHit], query: String) -> [SearchResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = GitHubPRSearch.number(from: text)
        var seen = Set<String>()
        let rows = hits.compactMap { hit -> SearchResult? in
            guard seen.insert(hit.id).inserted else { return nil }  // one PR from two requests
            var score = 10
            if let number, hit.number == number { score = 1000 }
            if let title = SpotlightMatcher.score(query: text, in: hit.title) { score = max(score, title) }
            if let body = SpotlightMatcher.score(query: text, in: hit.description) { score = max(score, body / 4) }

            // Remote data decides this link: http(s) with a host, or copy-only.
            let action: SpotlightAction = DeckLink.webURL(from: hit.url).map(SpotlightAction.open)
                ?? .copy("#\(hit.number)")
            let place = hit.project.map { "\($0) / \(hit.repo)" } ?? hit.repo
            let subtitle = ["\(place) #\(hit.number)", stateWord(hit), hit.author]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return SearchResult(id: hit.id, provider: .pr, title: hit.title, subtitle: subtitle,
                                score: score, action: action)
        }
        return Array(SpotlightRanking.sorted(rows).prefix(totalLimit))
    }
}

// MARK: - GitHub

enum GitHubPRSearch {
    static let maxTokens = 5
    static let maxTokenLength = 100
    static let perPage = 25
    /// How far back a bare number can be looked up: the most recently updated.
    static let recentLimit = 100

    /// Quotes and backslashes out (they would close or escape a phrase), control
    /// characters out, split, capped. Empty when there is too little to search for.
    static func tokens(for text: String) -> [String] {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if scalar == "\"" || scalar == "\\" { return nil }
            return CharacterSet.controlCharacters.contains(scalar) ? " " : scalar
        }))
        let words = cleaned.split(whereSeparator: { $0.isWhitespace })
            .prefix(maxTokens).map { String($0.prefix(maxTokenLength)) }
        guard RemoteSearchPolicy.shouldSearch(words.joined(separator: " ")) else { return [] }
        return words
    }

    private static func scopeTerm(_ scope: String) -> String {
        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "involves:@me" : trimmed
    }

    /// Every typed word is its own quoted term, AND-ed by GitHub, after the
    /// fixed prefix — so nothing typed can act as a qualifier.
    static func query(tokens: [String], scope: String) -> String {
        (["is:pr", scopeTerm(scope)] + tokens.map { "\"\($0)\"" } + ["in:title,body"]).joined(separator: " ")
    }

    static func recentQuery(scope: String) -> String {
        "is:pr \(scopeTerm(scope))"
    }

    /// A whole number, optionally with `#`: 1 to 9 digits.
    static func number(from text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "#" })
        guard (1...9).contains(t.count), t.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(t), n > 0 else {
            return nil
        }
        return n
    }

    static func url(query: String, perPage: Int) -> URL? {
        var components = URLComponents(string: "https://api.github.com/search/issues")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "order", value: "desc"),
        ]
        return components?.url
    }
}

enum GitHubPRSearchParser {
    /// `items` of a search response that are pull requests (an issue has no
    /// `pull_request` key). A row missing what it needs is skipped.
    static func parse(_ data: Data) -> [PRSearchHit]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return nil }
        let iso = ISO8601DateFormatter()
        return items.compactMap { item in
            guard let pr = item["pull_request"] as? [String: Any],
                  let number = (item["number"] as? NSNumber)?.intValue,
                  let title = item["title"] as? String,
                  let url = item["html_url"] as? String,
                  let repo = repoName(from: item["repository_url"] as? String)
            else { return nil }
            let merged = (pr["merged_at"] as? String) != nil
            let state: PRSearchState = merged ? .merged : ((item["state"] as? String) == "closed" ? .closed : .open)
            return PRSearchHit(
                provider: .github, repo: repo, project: nil, number: number, title: title,
                description: (item["body"] as? String).map { String($0.prefix(400)) } ?? "",
                state: state, isDraft: (item["draft"] as? Bool) ?? false,
                author: ((item["user"] as? [String: Any])?["login"] as? String) ?? "",
                url: url, updated: (item["updated_at"] as? String).flatMap { iso.date(from: $0) })
        }
    }

    /// "https://api.github.com/repos/owner/repo" -> "owner/repo".
    private static func repoName(from apiURL: String?) -> String? {
        guard let apiURL, let range = apiURL.range(of: "/repos/") else { return nil }
        let name = String(apiURL[range.upperBound...])
        return name.split(separator: "/").count == 2 ? name : nil
    }
}

// MARK: - Azure DevOps

enum AzurePRSearch {
    static let listLimit = 100

    static func byIDURL(target: AzureTarget, id: Int) -> URL? {
        URL(string: "\(target.orgBase)/_apis/git/pullrequests/\(id)?api-version=7.1")
    }

    static func listURL(target: AzureTarget) -> URL? {
        var components = URLComponents(string: "\(target.projectBase)/_apis/git/pullrequests")
        components?.queryItems = [
            URLQueryItem(name: "searchCriteria.status", value: "all"),
            URLQueryItem(name: "$top", value: String(listLimit)),
            URLQueryItem(name: "api-version", value: "7.1"),
        ]
        return components?.url
    }

    /// Every word must appear in the title or the description.
    static func filter(_ hits: [PRSearchHit], tokens: [String]) -> [PRSearchHit] {
        hits.filter { hit in
            tokens.allSatisfy { token in
                SpotlightMatcher.score(query: token, in: hit.title) != nil
                    || SpotlightMatcher.score(query: token, in: hit.description) != nil
            }
        }
    }

    /// The by-id route is organisation-wide; only the projects PRBox is
    /// configured for are searched.
    static func restrict(_ hits: [PRSearchHit], toProjects projects: [String]) -> [PRSearchHit] {
        let allowed = Set(projects.map { $0.lowercased() })
        return hits.filter { allowed.contains(($0.project ?? "").lowercased()) }
    }

    /// A pull request that does not exist is a 404: an empty answer, not a failed
    /// search. Every other non-200 is the caller's to report (`nil`).
    static func interpretByID(status: Int, body: Data) -> [PRSearchHit]? {
        status == 404 ? [] : nil
    }
}

enum AzurePRSearchParser {
    static func parseList(_ data: Data, organization: String) -> [PRSearchHit]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["value"] as? [[String: Any]] else { return nil }
        return values.compactMap { hit(from: $0, organization: organization) }
    }

    static func parseOne(_ data: Data, organization: String) -> PRSearchHit? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return hit(from: object, organization: organization)
    }

    private static func hit(from entry: [String: Any], organization: String) -> PRSearchHit? {
        guard let number = (entry["pullRequestId"] as? NSNumber)?.intValue,
              let title = entry["title"] as? String,
              let repository = entry["repository"] as? [String: Any],
              let repo = repository["name"] as? String,
              let project = (repository["project"] as? [String: Any])?["name"] as? String,
              let target = try? AzureTarget.normalise(organization: organization, project: project)
        else { return nil }
        let state: PRSearchState
        switch entry["status"] as? String {
        case "completed": state = .merged
        case "abandoned": state = .closed
        default: state = .open
        }
        return PRSearchHit(
            provider: .azureDevOps, repo: repo, project: project, number: number, title: title,
            description: (entry["description"] as? String).map { String($0.prefix(400)) } ?? "",
            state: state, isDraft: (entry["isDraft"] as? Bool) ?? false,
            author: ((entry["createdBy"] as? [String: Any])?["displayName"] as? String) ?? "",
            url: AzurePRParser.webURL(target: target, repo: repo, number: number),
            updated: AzureDate.parse(entry["creationDate"]))
    }
}

// MARK: - Two sources, partial answers

enum SourceMerge {
    /// A side that failed still lets the other show. Only when nothing answered
    /// is it a failure: the first error, or `ifNothingAnswered` when both sides
    /// were deliberately skipped (`nil`).
    static func combine<A, B>(
        _ a: Result<[A], Error>?, _ b: Result<[B], Error>?, ifNothingAnswered: RemoteSearchFailure
    ) throws -> ([A], [B]) {
        var left: [A] = [], right: [B] = []
        var firstError: Error?
        var answered = false
        switch a {
        case .success(let v)?: left = v; answered = true
        case .failure(let e)?: firstError = firstError ?? e
        case nil: break
        }
        switch b {
        case .success(let v)?: right = v; answered = true
        case .failure(let e)?: firstError = firstError ?? e
        case nil: break
        }
        if answered { return (left, right) }
        throw firstError ?? SearchSourceFailure(ifNothingAnswered)
    }
}
