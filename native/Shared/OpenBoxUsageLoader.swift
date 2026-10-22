import Foundation

// MARK: - Console Go usage transport (host side)
//
// One read-only request per agent tick. The selected opencode account's token
// is a Console key; the endpoint is workspace-scoped by it, so there is no
// org/workspace id to discover. Decoding is separated from transport so the
// real Console payload is covered by a unit test.

enum OpenBoxUsageLoader {
    enum LoadError: Error, Equatable {
        case unauthorized
        case server(Int)
        case transport(String)
        case invalidResponse
        case noSubscription
    }

    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    static let statusURL = URL(string: "https://opencode.ai/console/api/go/status")!

    static func load(
        token: String,
        now: Date = Date(),
        transport: Transport? = nil
    ) async throws -> OpenBoxUsage {
        guard !token.isEmpty else { throw LoadError.unauthorized }

        var request = URLRequest(url: statusURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Deck", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            if let transport {
                (data, response) = try await transport(request)
            } else {
                (data, response) = try await URLSession.shared.data(for: request)
            }
        } catch {
            throw LoadError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LoadError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            return try decode(data, now: now)
        case 401, 403:
            throw LoadError.unauthorized
        default:
            throw LoadError.server(http.statusCode)
        }
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> OpenBoxUsage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = isoFractional.date(from: text) ?? iso.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an ISO-8601 date"
            )
        }

        let response: Response
        do {
            response = try decoder.decode(Response.self, from: data)
        } catch {
            throw LoadError.invalidResponse
        }

        guard let access = response.access, let meters = access.meters else {
            throw LoadError.noSubscription
        }
        return OpenBoxUsage(
            writtenAt: now,
            product: response.product ?? "go",
            cancelAtPeriodEnd: response.cancelAtPeriodEnd ?? false,
            fiveHour: meters.fiveHour,
            week: meters.week,
            month: meters.month
        )
    }

    private struct Response: Decodable {
        let product: String?
        let cancelAtPeriodEnd: Bool?
        let access: Access?

        struct Access: Decodable {
            let meters: Meters?
        }

        struct Meters: Decodable {
            let fiveHour: OpenBoxUsage.Meter?
            let week: OpenBoxUsage.Meter?
            let month: OpenBoxUsage.Meter?
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()
}
