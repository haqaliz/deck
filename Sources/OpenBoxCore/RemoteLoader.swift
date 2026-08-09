import Foundation

public enum RemoteLoadError: Error, Equatable {
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int)
    case transportError(String)
}

/// Fetches usage metrics from an `opencode serve` instance over HTTP.
///
/// Auth is HTTP basic: username `opencode`, password from settings.
/// Fetch sequence per refresh: `GET /session`, then `GET /session/{id}/message`
/// for each session updated within the last 14 days. Messages are aggregated
/// by `RemoteMetrics.aggregate` (pure, tested separately).
public struct RemoteOpenCodeMetricsLoader {
    private let baseURL: URL
    private let password: String
    private let session: URLSession

    public init(url: URL, password: String, session: URLSession = .shared) {
        baseURL = url
        self.password = password
        self.session = session
    }

    public func load() async throws -> OpenCodeMetrics {
        let sessions = try await get([RemoteSession].self, path: "/session")
        let cutoff = Date().timeIntervalSince1970 * 1000 - 14 * 86_400 * 1000
        let recent = sessions.filter { $0.time.updated >= cutoff }

        if recent.contains(where: { $0.cost != nil || $0.tokens != nil }) {
            return RemoteMetrics.aggregate(sessions: recent, now: Date())
        }

        var messages: [RemoteMessage] = []
        for remoteSession in recent {
            let envelopes = try await get(
                [RemoteMessageEnvelope].self,
                path: "/session/\(remoteSession.id)/message"
            )
            messages.append(contentsOf: envelopes.map(\.info))
        }

        return RemoteMetrics.aggregate(
            sessions: recent,
            messages: messages,
            now: Date()
        )
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw RemoteLoadError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoteLoadError.transportError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoteLoadError.transportError("Not an HTTP response")
        }
        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw RemoteLoadError.transportError("Invalid JSON: \(error.localizedDescription)")
            }
        case 401, 403:
            throw RemoteLoadError.unauthorized
        default:
            throw RemoteLoadError.serverError(statusCode: http.statusCode)
        }
    }

    private var basicAuthHeader: String {
        "Basic " + Data("opencode:\(password)".utf8).base64EncodedString()
    }
}
