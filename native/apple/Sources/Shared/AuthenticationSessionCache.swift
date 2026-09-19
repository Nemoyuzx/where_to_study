import CryptoKit
import Foundation

enum AuthenticationSessionError: LocalizedError {
    case expired

    var errorDescription: String? { "登录状态已过期，请刷新重试。" }
}

struct AuthenticationSession<Value: Sendable>: Sendable {
    let value: Value
    let expiresAt: Date
}

/// Process-memory only. Credentials remain in the existing Keychain store;
/// tokens, cookies and credential fingerprints are never persisted or logged.
/// A synchronous reset also invalidates an in-flight login before it can publish.
final class AuthenticationSessionCache<Value: Sendable>: @unchecked Sendable {
    private struct Flight {
        let id: UUID
        let task: Task<AuthenticationSession<Value>, Error>
    }
    private let lock = NSLock()
    private var key: String?
    private var generation = UUID()
    private var flight: Flight?
    private var cached: (id: UUID, session: AuthenticationSession<Value>)?

    func reset() {
        let task = lock.withLock {
            let task = flight?.task
            key = nil
            generation = UUID()
            flight = nil
            cached = nil
            return task
        }
        task?.cancel()
    }

    private func invalidate(id: UUID) {
        lock.withLock {
            if cached?.id == id { cached = nil }
        }
    }

    private func session(
        key nextKey: String,
        expectedGeneration: UUID?,
        login: @escaping @Sendable () async throws -> AuthenticationSession<Value>
    ) async throws -> (id: UUID, value: Value, generation: UUID) {
        let selection: (cached: (UUID, Value, UUID)?, flight: Flight?, generation: UUID) = try lock.withLock {
            if let expectedGeneration, generation != expectedGeneration { throw CancellationError() }
            if key != nextKey {
                flight?.task.cancel()
                flight = nil
                cached = nil
                key = nextKey
                generation = UUID()
            }
            if let cached, cached.session.expiresAt > Date() {
                return ((cached.id, cached.session.value, generation), nil, generation)
            }
            if let flight { return (nil, flight, generation) }
            let next = Flight(id: UUID(), task: Task { try await login() })
            flight = next
            return (nil, next, generation)
        }
        if let cached = selection.cached { return cached }
        guard let selected = selection.flight else { throw CancellationError() }
        do {
            let session = try await selected.task.value
            return try lock.withLock {
                guard key == nextKey, generation == selection.generation,
                      flight?.id == selected.id || cached?.id == selected.id
                else { throw CancellationError() }
                cached = (selected.id, session)
                flight = nil
                return (selected.id, session.value, generation)
            }
        } catch {
            lock.withLock {
                if flight?.id == selected.id { flight = nil }
            }
            throw error
        }
    }

    func perform<Result: Sendable>(
        key: String,
        login: @escaping @Sendable () async throws -> AuthenticationSession<Value>,
        operation: @Sendable (Value) async throws -> Result
    ) async throws -> Result {
        var expectedGeneration: UUID?
        for attempt in 0 ... 1 {
            let lease = try await session(key: key, expectedGeneration: expectedGeneration, login: login)
            expectedGeneration = lease.generation
            do {
                let result = try await operation(lease.value)
                try Task.checkCancellation()
                // Clearing data, changing accounts or entering demo mode must
                // not allow an old request to return as current data.
                try lock.withLock {
                    guard self.key == key, cached?.id == lease.id else { throw CancellationError() }
                }
                return result
            } catch AuthenticationSessionError.expired {
                invalidate(id: lease.id)
                if attempt == 1 { throw AuthenticationSessionError.expired }
            }
        }
        throw AuthenticationSessionError.expired
    }
}

enum AuthenticationSessionPolicy {
    static func key(account: String, password: String) -> String {
        let bytes = (try? JSONEncoder().encode([account.trimmingCharacters(in: .whitespacesAndNewlines), password])) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func expiresAt(token: String, payload: [String: Any], now: Date = .now) -> Date {
        var candidates = [Date]()
        for field in ["expires_in", "expiresIn"] {
            if let value = payload[field], let seconds = Double(String(describing: value)), seconds.isFinite, seconds >= 0 {
                candidates.append(now.addingTimeInterval(seconds))
            }
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 3 {
            var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            if let data = Data(base64Encoded: base64),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let expiration = object["exp"] as? NSNumber {
                candidates.append(Date(timeIntervalSince1970: expiration.doubleValue))
            }
        }
        // The mobile academic service can issue opaque tokens without a TTL.
        // Bound their reuse to 20 minutes; explicit expiration still evicts early.
        return (candidates.min() ?? now.addingTimeInterval(20 * 60)).addingTimeInterval(-30)
    }

    static func checkExpiration(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw AuthenticationSessionError.expired }
        // A server/firewall failure can carry an auth-looking body. Only a
        // successful HTTP response may describe a business-level expiry.
        guard (200 ..< 300).contains(http.statusCode) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let code = String(describing: object["code"] ?? "")
        let error = object["error"] as? String ?? ""
        let message = ((object["msg"] ?? object["Msg"] ?? object["message"]) as? String ?? "").lowercased()
        let explicitMessages = ["token已过期", "token过期", "token失效", "登录已过期", "登录过期", "登录失效", "登录状态已失效", "token expired", "token has expired", "invalid token"]
        if code == "401" || error == "invalid_token" || explicitMessages.contains(where: message.contains) {
            throw AuthenticationSessionError.expired
        }
    }
}
