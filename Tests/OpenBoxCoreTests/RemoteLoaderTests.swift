import XCTest
@testable import OpenBoxCore

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("MockURLProtocol.handler not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class RemoteLoaderTests: XCTestCase {
    private var url: URL!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        url = URL(string: "http://127.0.0.1:4096")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    private func jsonResponse(_ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
         Data(body.utf8))
    }

    private func sessionJSON(id: String, updatedSecondsAgo: TimeInterval) -> String {
        let updated = Date().timeIntervalSince1970 * 1000 - updatedSecondsAgo * 1000
        return #"{"id":"\#(id)","time":{"created":0,"updated":\#(updated)}}"#
    }

    private func messageJSON(
        id: String,
        sessionID: String,
        secondsAgo: TimeInterval,
        input: Int,
        output: Int,
        cost: Double
    ) -> String {
        let created = Date().timeIntervalSince1970 * 1000 - secondsAgo * 1000
        return #"""
        {"info":{"id":"\#(id)","sessionID":"\#(sessionID)","role":"assistant",
        "time":{"created":\#(created)},"modelID":"deepseek-v4-flash-max",
        "providerID":"opencode-go","cost":\#(cost),
        "tokens":{"input":\#(input),"output":\#(output),"cache":{"read":0,"write":0}}}}
        """#
    }

    private func loader() -> RemoteOpenCodeMetricsLoader {
        RemoteOpenCodeMetricsLoader(url: url, password: "secret", session: session)
    }

    func testLoadsAndAggregatesMetricsOverHTTP() async throws {
        let sessions = [
            sessionJSON(id: "s1", updatedSecondsAgo: 60),
            sessionJSON(id: "s2", updatedSecondsAgo: 86_400 * 15),
        ]
        MockURLProtocol.handler = { request in
            if request.url?.path == "/session" {
                return self.jsonResponse(200, "[" + sessions.joined(separator: ",") + "]")
            }
            if request.url?.path == "/session/s1/message" {
                let messages = [
                    self.messageJSON(id: "m1", sessionID: "s1", secondsAgo: 3_600, input: 100, output: 50, cost: 0.02),
                    self.messageJSON(id: "m2", sessionID: "s1", secondsAgo: 86_400 * 2, input: 1_000, output: 200, cost: 0.1),
                ]
                return self.jsonResponse(200, "[" + messages.joined(separator: ",") + "]")
            }
            return self.jsonResponse(404, "{}")
        }

        let metrics = try await loader().load()

        XCTAssertEqual(metrics.input, 1100)
        XCTAssertEqual(metrics.output, 250)
        XCTAssertEqual(metrics.cost, 0.12, accuracy: 0.0001)
        XCTAssertEqual(metrics.todayInput, 100)
        XCTAssertEqual(metrics.models.count, 1)
        XCTAssertEqual(metrics.models.first?.modelID, "deepseek-v4")
    }

    func testSendsBasicAuthWithOpencodeUsername() async throws {
        var receivedAuth: String?
        MockURLProtocol.handler = { request in
            receivedAuth = request.value(forHTTPHeaderField: "Authorization")
            if request.url?.path == "/session" { return self.jsonResponse(200, "[]") }
            return self.jsonResponse(404, "{}")
        }

        _ = try await loader().load()

        let expected = "Basic " + Data("opencode:secret".utf8).base64EncodedString()
        XCTAssertEqual(receivedAuth, expected)
    }

    func testSkipsSessionsNotUpdatedInFourteenDays() async throws {
        let sessions = [
            sessionJSON(id: "s1", updatedSecondsAgo: 60),
            sessionJSON(id: "s2", updatedSecondsAgo: 86_400 * 15),
        ]
        var messageFetches: [String] = []
        MockURLProtocol.handler = { request in
            if request.url?.path == "/session" {
                return self.jsonResponse(200, "[" + sessions.joined(separator: ",") + "]")
            }
            if request.url?.path == "/session/s1/message" {
                messageFetches.append(request.url!.path)
                return self.jsonResponse(200, "[]")
            }
            return self.jsonResponse(404, "{}")
        }

        _ = try await loader().load()

        XCTAssertEqual(messageFetches, ["/session/s1/message"])
    }

    func testUnauthorizedThrows() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(401, #"{"name":"BadRequest"}"#) }

        do {
            _ = try await loader().load()
            XCTFail("expected unauthorized error")
        } catch let error as RemoteLoadError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testServerErrorThrows() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(500, "boom") }

        do {
            _ = try await loader().load()
            XCTFail("expected server error")
        } catch let error as RemoteLoadError {
            XCTAssertEqual(error, .serverError(statusCode: 500))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
