import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class AuthenticationSessionCacheTests: XCTestCase {
    func testConcurrentAndRepeatedRequestsShareOneLogin() async throws {
        let cache = AuthenticationSessionCache<String>()
        let probe = SessionProbe()
        let values = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    try await cache.perform(key: "same", login: { await probe.login() }) { $0 }
                }
            }
            var result = [String]()
            for try await value in group { result.append(value) }
            return result
        }
        XCTAssertEqual(Set(values), ["synthetic-token-1"])
        _ = try await cache.perform(key: "same", login: { await probe.login() }) { $0 }
        let count = await probe.logins
        XCTAssertEqual(count, 1)
    }

    func testExplicitExpirationRetriesOnceAndEvictsFailedRetry() async throws {
        let cache = AuthenticationSessionCache<String>()
        let probe = SessionProbe()
        let value = try await cache.perform(key: "same", login: { await probe.login() }) { token in
            if token == "synthetic-token-1" { throw AuthenticationSessionError.expired }
            return token
        }
        XCTAssertEqual(value, "synthetic-token-2")
        do {
            let _: String = try await cache.perform(key: "same", login: { await probe.login() }) { _ in
                throw AuthenticationSessionError.expired
            }
            XCTFail("Expected the second explicit expiration to be returned")
        } catch AuthenticationSessionError.expired {}
        let count = await probe.logins
        XCTAssertEqual(count, 3)
        let next = try await cache.perform(key: "same", login: { await probe.login() }) { $0 }
        XCTAssertEqual(next, "synthetic-token-4")
    }

    func testNetworkAndParserFailuresNeverTriggerLoginRetry() async throws {
        let cache = AuthenticationSessionCache<String>()
        let probe = SessionProbe()
        for failure in [0, 1] {
            do {
                let _: String = try await cache.perform(key: "same", login: { await probe.login() }) { _ in
                    if failure == 0 { throw URLError(.timedOut) }
                    throw ScheduleClientError.invalidResponse("synthetic malformed response")
                }
                XCTFail("Expected original failure")
            } catch is URLError {} catch ScheduleClientError.invalidResponse {} catch { XCTFail("Unexpected error") }
        }
        let count = await probe.logins
        XCTAssertEqual(count, 1)
    }

    func testChangedCredentialsResetAndKnownExpiryRequireNewLogin() async throws {
        let cache = AuthenticationSessionCache<String>()
        let probe = SessionProbe()
        let first = AuthenticationSessionPolicy.key(account: "account", password: "first")
        let second = AuthenticationSessionPolicy.key(account: "account", password: "second")
        XCTAssertNotEqual(first, second)
        _ = try await cache.perform(key: first, login: { await probe.login() }) { $0 }
        _ = try await cache.perform(key: second, login: { await probe.login() }) { $0 }
        cache.reset()
        _ = try await cache.perform(key: second, login: { await probe.login(expired: true) }) { $0 }
        _ = try await cache.perform(key: second, login: { await probe.login() }) { $0 }
        let count = await probe.logins
        XCTAssertEqual(count, 4)
    }

    func testResetRejectsLoginThatCompletesAfterClear() async throws {
        let cache = AuthenticationSessionCache<String>()
        let started = expectation(description: "login started")
        let gate = SessionGate()
        let task = Task {
            try await cache.perform(key: "old", login: {
                started.fulfill()
                await gate.wait()
                return AuthenticationSession(value: "old-token", expiresAt: .distantFuture)
            }) { $0 }
        }
        await fulfillment(of: [started], timeout: 2)
        cache.reset()
        await gate.release()
        do { _ = try await task.value; XCTFail("Old login must not survive clear") }
        catch is CancellationError {}
        let value = try await cache.perform(key: "new", login: {
            AuthenticationSession(value: "new-token", expiresAt: .distantFuture)
        }) { $0 }
        XCTAssertEqual(value, "new-token")
    }

    func testExpiredResponseAfterClearDoesNotReauthenticateOldAccount() async throws {
        let cache = AuthenticationSessionCache<String>()
        let probe = SessionProbe()
        let started = expectation(description: "request started")
        let gate = SessionGate()
        let task = Task {
            let _: String = try await cache.perform(key: "old", login: { await probe.login() }) { _ in
                started.fulfill()
                await gate.wait()
                throw AuthenticationSessionError.expired
            }
        }
        await fulfillment(of: [started], timeout: 2)
        cache.reset()
        await gate.release()
        do { try await task.value; XCTFail("Old request must not sign in after clear") }
        catch is CancellationError {}
        let count = await probe.logins
        XCTAssertEqual(count, 1)
    }

    func testExpirationDetectionExcludesPermissionNetworkAndMalformedResponses() throws {
        let url = URL(string: "https://jwglweixin.bupt.edu.cn/bjyddx/currentTerm")!
        for (status, body, expires) in [
            (401, "", true), (403, #"{"message":"forbidden"}"#, false),
            (403, #"{"code":401,"message":"token expired"}"#, false),
            (423, #"{"code":401,"message":"token expired"}"#, false),
            (500, #"{"code":401,"message":"token expired"}"#, false),
            (503, #"{"error":"invalid_token"}"#, false),
            (500, "", false), (200, "<html>invalid</html>", false),
            (200, #"{"code":0,"msg":"invalid data"}"#, false),
            (200, #"{"code":401}"#, true), (200, #"{"error":"invalid_token"}"#, true),
            (200, #"{"code":0,"msg":"token已过期"}"#, true)
        ] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            if expires {
                XCTAssertThrowsError(try AuthenticationSessionPolicy.checkExpiration(data: Data(body.utf8), response: response))
            } else {
                XCTAssertNoThrow(try AuthenticationSessionPolicy.checkExpiration(data: Data(body.utf8), response: response))
            }
        }
    }

    func testHTTPServerAndFirewallBodiesNeverReplayAuthenticatedRequests() async throws {
        for status in [403, 423, 500, 503] {
            let cache = AuthenticationSessionCache<String>()
            let probe = SessionProbe()
            let url = URL(string: "https://apiucloud.bupt.edu.cn/ykt-site/site/list/student/current")!
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            do {
                let _: String = try await cache.perform(key: "same", login: { await probe.login() }) { _ in
                    try AuthenticationSessionPolicy.checkExpiration(data: Data(#"{"code":401,"message":"token expired"}"#.utf8), response: response)
                    throw ScheduleClientError.service("synthetic HTTP failure")
                }
                XCTFail("Expected the original HTTP failure")
            } catch ScheduleClientError.service {}
            let count = await probe.logins
            XCTAssertEqual(count, 1)
        }
    }

    func testSJDVerifiedHTTP500UnauthorizedFixtureRefreshesOnlyOnce() async throws {
        for body in [#"{"code":"401","message":"非法访问：/currentTerm"}"#, #"{"code":401,"message":"非法访问：/currentTerm"}"#] {
            let transport = SJDExpirationFixtureTransport(status: 500, body: body)
            let api = SJDAPIClient(transport: transport)
            do {
                _ = try await api.authenticated(credentials: Credentials(account: "synthetic", password: "synthetic")) {
                    try await api.academic(token: $0, endpoint: .currentTerm)
                }
                XCTFail("A second explicit expiration must be returned")
            } catch AuthenticationSessionError.expired {}
            let counts = await transport.counts()
            XCTAssertEqual(counts.logins, 2)
            XCTAssertEqual(counts.queries, 2)
        }
    }

    func testSJDServerExceptionExcludesOtherStatusesMessagesAndHosts() async throws {
        for (status, body, host) in [
            (500, #"{"code":"500","message":"token expired"}"#, "jwglweixin.bupt.edu.cn"),
            (500, #"{"message":"token expired"}"#, "jwglweixin.bupt.edu.cn"),
            (503, #"{"code":"401"}"#, "jwglweixin.bupt.edu.cn"),
            (423, #"{"code":"401"}"#, "jwglweixin.bupt.edu.cn"),
            (403, #"{"code":"401"}"#, "jwglweixin.bupt.edu.cn"),
            (500, #"{"code":"401"}"#, "apiucloud.bupt.edu.cn")
        ] {
            let transport = SJDExpirationFixtureTransport(status: status, body: body, host: host)
            let api = SJDAPIClient(transport: transport)
            do {
                _ = try await api.authenticated(credentials: Credentials(account: "synthetic", password: "synthetic")) {
                    try await api.academic(token: $0, endpoint: .currentTerm)
                }
                XCTFail("Expected the original service failure")
            } catch ScheduleClientError.service {}
            let counts = await transport.counts()
            XCTAssertEqual(counts.logins, 1)
            XCTAssertEqual(counts.queries, 1)
        }
    }

    func testTTLAndJWTUseEarliestExpiryWithSafetyMargin() {
        let now = Date(timeIntervalSince1970: 1_000)
        let payload = Data(#"{"exp":1100}"#.utf8).base64EncodedString()
        XCTAssertEqual(AuthenticationSessionPolicy.expiresAt(token: "header.\(payload).signature", payload: ["expires_in": 200], now: now), Date(timeIntervalSince1970: 1_070))
        XCTAssertEqual(AuthenticationSessionPolicy.expiresAt(token: "opaque", payload: ["expires_in": 60], now: now), Date(timeIntervalSince1970: 1_030))
        XCTAssertEqual(AuthenticationSessionPolicy.expiresAt(token: "opaque", payload: [:], now: now), Date(timeIntervalSince1970: 2_170))
    }
}

private actor SessionProbe {
    private(set) var logins = 0
    func login(expired: Bool = false) -> AuthenticationSession<String> {
        logins += 1
        return AuthenticationSession(value: "synthetic-token-\(logins)", expiresAt: expired ? .distantPast : .distantFuture)
    }
}

private actor SJDExpirationFixtureTransport: SJDHTTPTransport {
    private let status: Int
    private let body: String
    private let host: String
    private var logins = 0
    private var queries = 0

    init(status: Int, body: String, host: String = "jwglweixin.bupt.edu.cn") {
        self.status = status
        self.body = body
        self.host = host
    }

    func counts() -> (logins: Int, queries: Int) { (logins, queries) }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        if request.url?.path == "/bjyddx/login" {
            logins += 1
            return (Data(#"{"code":1,"data":{"token":"synthetic-token"}}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        queries += 1
        return (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://\(host)/bjyddx/currentTerm")!,
            statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private actor SessionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
