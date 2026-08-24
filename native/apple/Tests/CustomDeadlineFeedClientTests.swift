import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class CustomDeadlineFeedClientTests: XCTestCase {
    func testV1FixtureParsesCompleteCustomSnapshots() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        let feed = try CustomDeadlineFeedParser.parse(
            data: try fixtureData("custom-deadline-feed.json"),
            sourceURL: sourceURL
        )

        XCTAssertEqual(feed.sourceName, "示例自定义日程")
        XCTAssertEqual(feed.homepage?.absoluteString, "https://example.com/calendar")
        XCTAssertEqual(feed.updatedAt, "2026-08-24T08:00:00+08:00")
        XCTAssertEqual(feed.metadata.itemCount, 2)
        let custom = try XCTUnwrap(feed.itemsByDate["2026-09-18"]?.first)
        XCTAssertEqual(custom.kind, .custom)
        XCTAssertEqual(custom.source, .custom)
        XCTAssertEqual(custom.sourceName, "示例自定义日程")
        XCTAssertEqual(custom.organizer, "示例组织方")
        XCTAssertEqual(custom.officialURL?.scheme, "https")
    }

    func testInvalidEnvelopeFailsButInvalidItemsAreSkipped() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        let invalidEnvelope = Data(#"{"version":1,"source":"Feed","items":[],"extra":true}"#.utf8)
        XCTAssertThrowsError(
            try CustomDeadlineFeedParser.parse(data: invalidEnvelope, sourceURL: sourceURL)
        )

        let mixed = Data(#"""
        {
          "version":1,
          "source":"Feed",
          "items":[
            {"id":"valid","name":"Valid","event_type":"custom","primary_deadline":"2026-09-18T23:59:00+08:00"},
            {"id":"no-zone","name":"No zone","event_type":"custom","primary_deadline":"2026-09-18T23:59:00"},
            {"id":"unsafe-link","name":"Unsafe","event_type":"custom","primary_deadline":"2026-09-18T23:59:00+08:00","official_url":"https://127.0.0.1/item"},
            {"id":"extra","name":"Extra","event_type":"custom","primary_deadline":"2026-09-18T23:59:00+08:00","unknown":1}
          ]
        }
        """#.utf8)
        let feed = try CustomDeadlineFeedParser.parse(data: mixed, sourceURL: sourceURL)
        XCTAssertEqual(feed.itemsByDate["2026-09-18"]?.map(\.id), ["valid"])
    }

    func testParserRejectsOversizedPayload() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        XCTAssertThrowsError(try CustomDeadlineFeedParser.parse(
            data: Data(repeating: 0x20, count: CalendarDeadlineSources.maximumPayloadBytes + 1),
            sourceURL: sourceURL
        ))
    }

    func testParserCapsAcceptedItemsAtOneHundredPerDay() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        let items: [[String: Any]] = (0 ..< 120).map { index in
            [
                "id": "item-\(index)",
                "name": "Item \(index)",
                "event_type": "custom",
                "primary_deadline": "2026-09-18T23:59:00+08:00",
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "source": "Feed",
            "items": items,
        ])
        let feed = try CustomDeadlineFeedParser.parse(data: data, sourceURL: sourceURL)

        XCTAssertEqual(feed.itemsByDate["2026-09-18"]?.count, 100)
    }

    func testURLValidatorRejectsCredentialsLocalhostAndReservedLiterals() throws {
        for value in [
            "http://example.com/feed.json",
            "https://user:password@example.com/feed.json",
            "https://localhost/feed.json",
            "https://calendar.localhost/feed.json",
            "https://127.0.0.1/feed.json",
            "https://10.0.0.1/feed.json",
            "https://169.254.1.1/feed.json",
            "https://192.168.1.1/feed.json",
            "https://198.51.100.1/feed.json",
            "https://2130706433/feed.json",
            "https://0x7f000001/feed.json",
            "https://0177.0.0.1/feed.json",
            "https://127.1/feed.json",
            "https://[::1]/feed.json",
            "https://[fc00::1]/feed.json",
            "https://[2001:db8::1]/feed.json",
        ] {
            XCTAssertThrowsError(try CustomDeadlineFeedURLValidator.validatedURL(value), value)
        }
        XCTAssertEqual(
            try CustomDeadlineFeedURLValidator.validatedURL(
                " https://calendar.example.com/feed.json?campus=1 "
            ).host,
            "calendar.example.com"
        )
        XCTAssertEqual(
            try CustomDeadlineFeedURLValidator.validatedURL(
                "https://8.8.8.8/feed.json"
            ).host,
            "8.8.8.8"
        )
    }

    func testSuccessfulFeedIsCachedForFiveMinutes() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        let recorder = CustomFeedLoadRecorder(data: try fixtureData("custom-deadline-feed.json"))
        let client = try CustomDeadlineFeedClient(sourceURL: sourceURL) { url in
            await recorder.load(url)
        }

        _ = try await client.fetch(dates: ["2026-09-18"])
        _ = try await client.fetch(dates: ["2026-10-08"])
        _ = try await client.validateFeed()

        let invocationCount = await recorder.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testClientRejectsCalendarRangesOverThreeHundredSeventyDays() async throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        let fixture = try fixtureData("custom-deadline-feed.json")
        let client = try CustomDeadlineFeedClient(sourceURL: sourceURL) { _ in
            fixture
        }
        let calendar = Calendar.shanghai
        let start = try XCTUnwrap(StrictContractDateParser.date(from: "2026-01-01"))
        let dates = (0 ..< 371).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }.map { StrictContractDateParser.string(from: $0) }

        do {
            _ = try await client.fetch(dates: dates)
            XCTFail("Expected an oversized date range to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("370"))
        }
    }

    func testRedirectDelegateRejectsEveryRedirect() throws {
        let original = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        let redirected = try XCTUnwrap(URL(string: "https://example.com/other.json"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: original,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": redirected.absoluteString]
        ))
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: original)
        let expectation = expectation(description: "redirect rejected")
        CustomDeadlineRedirectDelegate().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirected)
        ) { request in
            XCTAssertNil(request)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testRequestIsCredentialFreeJSONGet() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/feed.json"))
        let request = try CustomDeadlineFeedClient.request(for: url)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.httpBody)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let contractURL = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/v1/fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: contractURL)
    }
}

private actor CustomFeedLoadRecorder {
    private(set) var invocationCount = 0
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func load(_: URL) -> Data {
        invocationCount += 1
        return data
    }
}
