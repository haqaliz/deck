import Foundation

/// A failure from either infra provider. One enum keeps `FetchClassifier` and
/// the two loaders from growing parallel cases.
enum InfraProviderError: Error, Equatable {
    case notConfigured
    case serverError(Int)
    case transport(String)
    case invalidPayload
}

/// URL normalisation shared by the verifier, the loaders and the deep links.
///
/// A trailing slash is the one difference users type that changes nothing, so
/// every entry point strips it rather than making the caller remember.
enum InfraEndpoint {
    static func base(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty, URL(string: value)?.host != nil else { return nil }
        return value
    }

    static func url(_ base: String, _ path: String) -> URL? {
        URL(string: base + (path.hasPrefix("/") ? path : "/" + path))
    }
}

/// The two providers' read paths: a bearer-style auth header, a 10s timeout,
/// and the same status/transport split as the rest of Deck's loaders.
enum InfraHTTP {
    static func get(_ url: URL, token: String, scheme: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("\(scheme) \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    static func post(
        _ url: URL, token: String, scheme: String, body: Data,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 10
        request.setValue("\(scheme) \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw InfraProviderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw InfraProviderError.invalidPayload
        }
        guard (200...299).contains(http.statusCode) else {
            throw InfraProviderError.serverError(http.statusCode)
        }
        return data
    }
}

/// Timestamps come back as ISO-8601, usually with fractional seconds; both
/// spellings occur in one response, so try the fractional form first.
enum InfraDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return fractional.date(from: raw) ?? plain.date(from: raw)
    }
}

/// Deep links. Built from the credential's own URLs, never hard-coded, and
/// filtered by `DeckLink.webURL` at the widget boundary like every other
/// remote URL.
enum InfraLinks {    static func kibanaDiscover(
        uiURL: String, index: String, query: String, fromMinutes: Int
    ) -> URL? {
        guard let base = InfraEndpoint.base(uiURL) else { return nil }
        let q = query.replacingOccurrences(of: " ", with: "%20")
        let raw = "\(base)/app/discover#/?_g=(time:(from:now-\(fromMinutes)m,to:now))"
            + "&_a=(index:'\(index)',query:(language:kuery,query:'\(q)'))"
        return URL(string: raw)
    }

    static func grafanaDashboard(
        baseURL: String, uid: String, host: String?, fromMinutes: Int
    ) -> URL? {
        guard let base = InfraEndpoint.base(baseURL) else { return nil }
        var raw = "\(base)/d/\(uid)?from=now-\(fromMinutes)m&to=now"
        if let host, !host.isEmpty {
            raw += "&var-host=\(host)"
        }
        return URL(string: raw)
    }

    static func grafanaAlerts(baseURL: String) -> URL? {
        guard let base = InfraEndpoint.base(baseURL) else { return nil }
        return URL(string: "\(base)/alerting/list")
    }
}
