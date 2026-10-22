import XCTest

/// The Console Go payload, captured 2026-10-22. These are the exact numbers the
/// dashboard renders: 0% rolling, 28% weekly, 85% monthly.
final class OpenBoxUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_684_800) // 2026-10-22T16:00:00Z

    private let fixture = """
    {
      "subscriberUserId": "acc_01M0WYDE3RCN2HA9VTJ562NT7M",
      "product": "go",
      "renewalProduct": "go",
      "paymentMethodId": "payment_method_01M3HBV654JDVFRP72H0R2HCJS",
      "paymentMethodKind": "card",
      "renewalCurrency": "usd",
      "useBalance": false,
      "cancelAtPeriodEnd": false,
      "resumability": "renewing",
      "renewalPending": false,
      "nextPeriodPaid": false,
      "access": {
        "startsAt": "2026-09-27T12:01:03.000Z",
        "endsAt": "2026-10-27T12:01:03.000Z",
        "cancelAtPeriodEnd": false,
        "meters": {
          "fiveHour": {
            "startsAt": "2026-10-22T14:31:24.000Z",
            "resetsAt": "2026-10-22T19:31:24.000Z",
            "limitMicroCents": "1200000000",
            "usedMicroCents": "6639170"
          },
          "week": {
            "startsAt": "2026-10-19T00:00:00.000Z",
            "resetsAt": "2026-10-26T00:00:00.000Z",
            "limitMicroCents": "3000000000",
            "usedMicroCents": "849821991"
          },
          "month": {
            "resetsAt": "2026-10-27T12:01:03.000Z",
            "limitMicroCents": "6000000000",
            "usedMicroCents": "5078102976"
          }
        }
      },
      "upgradePrice": { "amountMicroCents": "3846000000", "currency": "usd" }
    }
    """

    private func decodedFixture() throws -> OpenBoxUsage {
        try OpenBoxUsageLoader.decode(Data(fixture.utf8), now: now)
    }

    func testDecodesConsoleMeters() throws {
        let usage = try decodedFixture()
        XCTAssertEqual(usage.product, "go")
        XCTAssertEqual(usage.productLabel, "GO")
        XCTAssertFalse(usage.cancelAtPeriodEnd)
        XCTAssertTrue(usage.hasMeters)

        let fiveHour = try XCTUnwrap(usage.fiveHour)
        XCTAssertEqual(fiveHour.usedMicroCents, 6_639_170)
        XCTAssertEqual(fiveHour.limitMicroCents, 1_200_000_000)
        XCTAssertEqual(fiveHour.resetsAt, Date(timeIntervalSince1970: 1_792_697_484))
        XCTAssertEqual(fiveHour.percent, 0.553, accuracy: 0.001)

        let week = try XCTUnwrap(usage.week)
        XCTAssertEqual(week.percent, 28.327, accuracy: 0.01)
        XCTAssertEqual(week.percentText, "28%")

        let month = try XCTUnwrap(usage.month)
        XCTAssertEqual(month.percent, 84.635, accuracy: 0.01)
        XCTAssertEqual(month.percentText, "85%")
        XCTAssertEqual(month.remainingMicroCents, 921_897_024)
    }

    func testDateTimeStrategyAcceptsFractionalSeconds() throws {
        let month = try XCTUnwrap(try decodedFixture().month)
        XCTAssertEqual(month.resetsAt, Date(timeIntervalSince1970: 1_793_102_463))
    }

    func testNumericMicroCentsDecodeToo() throws {
        let json = #"{"product":"go","access":{"meters":{"month":{"usedMicroCents":500,"limitMicroCents":1000}}}}"#
        let usage = try OpenBoxUsageLoader.decode(Data(json.utf8), now: now)
        XCTAssertEqual(usage.month?.usedMicroCents, 500)
        XCTAssertEqual(usage.month?.percentText, "50%")
    }

    func testNoSubscriptionIsItsOwnError() {
        let json = #"{"product":"go","access":null}"#
        XCTAssertThrowsError(try OpenBoxUsageLoader.decode(Data(json.utf8), now: now)) {
            XCTAssertEqual($0 as? OpenBoxUsageLoader.LoadError, .noSubscription)
        }
    }

    func testMalformedPayloadIsRejected() {
        XCTAssertThrowsError(try OpenBoxUsageLoader.decode(Data("not json".utf8), now: now)) {
            XCTAssertEqual($0 as? OpenBoxUsageLoader.LoadError, .invalidResponse)
        }
    }

    func testPercentTextAtTheCapAndJustBelow() {
        let atCap = OpenBoxUsage.Meter(usedMicroCents: 120, limitMicroCents: 100, resetsAt: nil)
        XCTAssertEqual(atCap.percentText, "100%+")
        XCTAssertEqual(atCap.remainingMicroCents, 0)

        let justBelow = OpenBoxUsage.Meter(usedMicroCents: 9_960, limitMicroCents: 10_000, resetsAt: nil)
        XCTAssertEqual(justBelow.percentText, ">99%")

        let zeroLimit = OpenBoxUsage.Meter(usedMicroCents: 10, limitMicroCents: 0, resetsAt: nil)
        XCTAssertEqual(zeroLimit.percent, 0)
        XCTAssertEqual(zeroLimit.percentText, "0%")
    }

    func testMoneyFormatting() {
        XCTAssertEqual(OpenBoxUsageFormatters.money(6_639_170), "$0.07")
        XCTAssertEqual(OpenBoxUsageFormatters.money(849_821_991), "$8.50")
        XCTAssertEqual(OpenBoxUsageFormatters.money(1_200_000_000), "$12")
        XCTAssertEqual(OpenBoxUsageFormatters.money(5_078_102_976), "$50.78")
        XCTAssertEqual(OpenBoxUsageFormatters.money(921_897_024), "$9.22")
        XCTAssertEqual(OpenBoxUsageFormatters.money(0), "$0.00")
    }

    func testStoreRoundTrip() throws {
        let usage = try decodedFixture()
        let data = try JSONEncoder().encode(usage)
        XCTAssertEqual(try JSONDecoder().decode(OpenBoxUsage.self, from: data), usage)
    }

    // MARK: - Transport

    func testTransportSuccess() async throws {
        let usage = try await OpenBoxUsageLoader.load(
            token: "test",
            now: now,
            transport: { _ in (Data(self.fixture.utf8), self.http(200)) }
        )
        XCTAssertEqual(usage.month?.percentText, "85%")
    }

    func testTransportUnauthorized() async {
        do {
            _ = try await OpenBoxUsageLoader.load(
                token: "test",
                transport: { _ in (Data(), self.http(401)) }
            )
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? OpenBoxUsageLoader.LoadError, .unauthorized)
        }
    }

    func testEmptyTokenNeverHitsTheNetwork() async {
        do {
            _ = try await OpenBoxUsageLoader.load(
                token: "",
                transport: { _ in
                    XCTFail("transport must not run without a token")
                    return (Data(), self.http(200))
                }
            )
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? OpenBoxUsageLoader.LoadError, .unauthorized)
        }
    }

    private func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: OpenBoxUsageLoader.statusURL,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
