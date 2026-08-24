import Darwin
import CoreFoundation
import Foundation

struct CustomDeadlineFeedMetadata: Equatable, Sendable {
    let sourceName: String
    let homepage: URL?
    let itemCount: Int
}

struct ParsedCustomDeadlineFeed: Equatable, Sendable {
    let sourceURL: URL
    let sourceName: String
    let homepage: URL?
    let updatedAt: String?
    let itemsByDate: [String: [PublicDeadlineItem]]

    var metadata: CustomDeadlineFeedMetadata {
        CustomDeadlineFeedMetadata(
            sourceName: sourceName,
            homepage: homepage,
            itemCount: itemsByDate.values.reduce(0) { $0 + $1.count }
        )
    }

    func snapshots(for dates: [String]) -> [String: PublicDeadlineSnapshot] {
        Dictionary(uniqueKeysWithValues: dates.map { date in
            (
                date,
                PublicDeadlineSnapshot(
                    date: date,
                    items: itemsByDate[date] ?? [],
                    source: sourceURL,
                    usedBackup: false
                )
            )
        })
    }
}

enum CustomDeadlineFeedURLValidator {
    static func validatedURL(_ rawValue: String) throws -> URL {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized) else {
            throw CalendarDeadlineError.service("自定义日程地址格式不正确。")
        }
        try validate(url)
        return url
    }

    static func validate(_ url: URL) throws {
        guard
            url.scheme?.lowercased() == "https",
            let rawHost = url.host,
            !rawHost.isEmpty,
            url.user == nil,
            url.password == nil,
            url.fragment == nil
        else {
            throw CalendarDeadlineError.service("自定义日程地址必须是无凭据的 HTTPS URL。")
        }

        let host = rawHost
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard host != "localhost", !host.hasSuffix(".localhost") else {
            throw CalendarDeadlineError.service("自定义日程地址不能指向本机。")
        }
        guard !isForbiddenIPAddressLiteral(host) else {
            throw CalendarDeadlineError.service("自定义日程地址不能使用私有或保留 IP。")
        }
    }

    static func isForbiddenIPAddressLiteral(_ host: String) -> Bool {
        if host.hasPrefix("0x"),
           host.dropFirst(2).unicodeScalars.allSatisfy(
               CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains
           ) {
            return true
        }
        let numericIPv4Characters = CharacterSet(charactersIn: "0123456789.")
        if host.unicodeScalars.allSatisfy(numericIPv4Characters.contains) {
            let components = host.split(separator: ".", omittingEmptySubsequences: false)
            if components.count != 4
                || components.contains(where: { $0.count > 1 && $0.first == "0" }) {
                return true
            }
        }
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            let bytes = withUnsafeBytes(of: &ipv4.s_addr) { Array($0) }
            return isForbiddenIPv4(bytes)
        }

        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            return isForbiddenIPv6(bytes)
        }
        if host.unicodeScalars.allSatisfy(numericIPv4Characters.contains) {
            return true
        }
        return false
    }

    private static func isForbiddenIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        let first = bytes[0]
        let second = bytes[1]
        let third = bytes[2]
        if first == 0 || first == 10 || first == 127 || first >= 224 { return true }
        if first == 100, (64 ... 127).contains(second) { return true }
        if first == 169, second == 254 { return true }
        if first == 172, (16 ... 31).contains(second) { return true }
        if first == 192, second == 168 { return true }
        if first == 192, second == 0, third == 0 || third == 2 { return true }
        if first == 192, second == 88, third == 99 { return true }
        if first == 198, second == 18 || second == 19 { return true }
        if first == 198, second == 51, third == 100 { return true }
        if first == 203, second == 0, third == 113 { return true }
        return false
    }

    private static func isForbiddenIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }
        // Public IPv6 global unicast is 2000::/3. Other literal ranges are
        // link-local, multicast, loopback, IPv4-mapped, unique-local, or reserved.
        guard bytes[0] & 0xE0 == 0x20 else { return true }
        // RFC 3849 documentation prefix 2001:db8::/32 is not publicly routable.
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0D, bytes[3] == 0xB8 {
            return true
        }
        return false
    }
}

enum CustomDeadlineFeedParser {
    static let maximumItems = 5_000

    static func parse(data: Data, sourceURL: URL) throws -> ParsedCustomDeadlineFeed {
        guard data.count <= CalendarDeadlineSources.maximumPayloadBytes else {
            throw CalendarDeadlineError.service("自定义日程响应超过 2 MiB。")
        }
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CalendarDeadlineError.service("自定义日程顶层必须是对象。")
            }
            root = object
        } catch let error as CalendarDeadlineError {
            throw error
        } catch {
            throw CalendarDeadlineError.service("自定义日程 JSON 格式不正确。")
        }

        let allowedEnvelopeKeys: Set<String> = [
            "version", "source", "homepage", "updated_at", "items",
        ]
        guard Set(root.keys).isSubset(of: allowedEnvelopeKeys),
              let version = root["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.intValue == 1,
              let sourceName = normalizedString(root["source"], maximumLength: 80),
              let records = root["items"] as? [Any],
              records.count <= maximumItems
        else {
            throw CalendarDeadlineError.service("自定义日程不符合 v1 接口规范。")
        }

        let homepage: URL?
        if let homepageValue = root["homepage"] {
            guard let rawHomepage = homepageValue as? String,
                  let parsedHomepage = try? CustomDeadlineFeedURLValidator.validatedURL(rawHomepage)
            else {
                throw CalendarDeadlineError.service("自定义日程来源主页不是安全的 HTTPS URL。")
            }
            homepage = parsedHomepage
        } else {
            homepage = nil
        }

        let updatedAt: String?
        if let updatedValue = root["updated_at"] {
            guard let rawUpdatedAt = updatedValue as? String,
                  parseRFC3339WithTimeZone(rawUpdatedAt) != nil
            else {
                throw CalendarDeadlineError.service("自定义日程更新时间格式不正确。")
            }
            updatedAt = rawUpdatedAt
        } else {
            updatedAt = nil
        }

        let allowedItemKeys: Set<String> = [
            "id", "name", "event_type", "primary_deadline", "organizer", "official_url",
        ]
        var itemsByDate = [String: [PublicDeadlineItem]]()
        var seen = Set<String>()
        for rawRecord in records {
            guard let record = rawRecord as? [String: Any],
                  Set(record.keys).isSubset(of: allowedItemKeys),
                  let id = normalizedString(record["id"], maximumLength: 128),
                  let name = normalizedString(record["name"], maximumLength: 200),
                  let rawKind = record["event_type"] as? String,
                  let kind = PublicDeadlineKind(rawValue: rawKind),
                  let deadline = record["primary_deadline"] as? String,
                  parseRFC3339WithTimeZone(deadline) != nil,
                  deadline.count >= 10
            else { continue }

            let organizer: String?
            if let rawOrganizer = record["organizer"] {
                guard let value = normalizedString(rawOrganizer, maximumLength: 200) else { continue }
                organizer = value
            } else {
                organizer = nil
            }

            let officialURL: URL?
            if let rawOfficialURL = record["official_url"] {
                guard let value = rawOfficialURL as? String,
                      let url = try? CustomDeadlineFeedURLValidator.validatedURL(value)
                else { continue }
                officialURL = url
            } else {
                officialURL = nil
            }

            let date = String(deadline.prefix(10))
            guard StrictContractDateParser.date(from: date) != nil,
                  (itemsByDate[date]?.count ?? 0) < CalendarDeadlineSources.maximumItemsPerDay
            else { continue }
            let item = PublicDeadlineItem(
                id: id,
                name: name,
                kind: kind,
                source: .custom,
                deadline: deadline,
                organizer: organizer,
                officialURL: officialURL,
                sourceName: sourceName,
                sourceHomepage: homepage
            )
            guard seen.insert(item.favoriteID).inserted else { continue }
            itemsByDate[date, default: []].append(item)
        }
        itemsByDate = itemsByDate.mapValues { items in
            items.sorted { ($0.deadline, $0.name) < ($1.deadline, $1.name) }
        }
        return ParsedCustomDeadlineFeed(
            sourceURL: sourceURL,
            sourceName: sourceName,
            homepage: homepage,
            updatedAt: updatedAt,
            itemsByDate: itemsByDate
        )
    }

    private static func normalizedString(_ value: Any?, maximumLength: Int) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumLength else { return nil }
        return normalized
    }

    private static func parseRFC3339WithTimeZone(_ value: String) -> Date? {
        guard value.range(
            of: #"(?:Z|[+-][0-9]{2}:[0-9]{2})$"#,
            options: .regularExpression
        ) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

actor CustomDeadlineFeedCache {
    typealias Loader = @Sendable (URL) async throws -> Data

    private struct CacheEntry {
        let fetchedAt: Date
        let feed: ParsedCustomDeadlineFeed
    }

    private let sourceURL: URL
    private let loader: Loader
    private var cache: CacheEntry?
    private var inFlight: Task<ParsedCustomDeadlineFeed, Error>?

    init(sourceURL: URL, loader: @escaping Loader) {
        self.sourceURL = sourceURL
        self.loader = loader
    }

    func load(refreshStaleCache: Bool) async throws -> ParsedCustomDeadlineFeed {
        if let cache {
            let isFresh = Date().timeIntervalSince(cache.fetchedAt) < 5 * 60
            if !refreshStaleCache || isFresh {
                return cache.feed
            }
        }
        let task: Task<ParsedCustomDeadlineFeed, Error>
        if let inFlight {
            task = inFlight
        } else {
            let sourceURL = sourceURL
            let loader = loader
            task = Task {
                let data = try await loader(sourceURL)
                return try CustomDeadlineFeedParser.parse(data: data, sourceURL: sourceURL)
            }
            inFlight = task
        }
        do {
            let feed = try await task.value
            cache = CacheEntry(fetchedAt: Date(), feed: feed)
            inFlight = nil
            return feed
        } catch {
            inFlight = nil
            throw error
        }
    }
}

struct CustomDeadlineFeedClient: Sendable {
    let sourceURL: URL
    private let cache: CustomDeadlineFeedCache

    init(sourceURL: URL) throws {
        try CustomDeadlineFeedURLValidator.validate(sourceURL)
        self.sourceURL = sourceURL
        cache = CustomDeadlineFeedCache(sourceURL: sourceURL) { url in
            try await Self.fetchData(from: url)
        }
    }

    init(sourceURL: URL, loader: @escaping CustomDeadlineFeedCache.Loader) throws {
        try CustomDeadlineFeedURLValidator.validate(sourceURL)
        self.sourceURL = sourceURL
        cache = CustomDeadlineFeedCache(sourceURL: sourceURL, loader: loader)
    }

    func fetch(dates: [String]) async throws -> [String: PublicDeadlineSnapshot] {
        let requestedDates = Array(Set(dates)).sorted()
        guard requestedDates.count <= 370,
              requestedDates.allSatisfy({ StrictContractDateParser.date(from: $0) != nil })
        else {
            throw CalendarDeadlineError.service("自定义日程查询范围不正确或超过 370 天。")
        }
        return try await cache.load(refreshStaleCache: false).snapshots(for: requestedDates)
    }

    func validateFeed() async throws -> CustomDeadlineFeedMetadata {
        try await cache.load(refreshStaleCache: true).metadata
    }

    func prewarm(dates: [String]) async throws -> [String: PublicDeadlineSnapshot] {
        let requestedDates = Array(Set(dates)).sorted()
        guard requestedDates.count <= 370,
              requestedDates.allSatisfy({ StrictContractDateParser.date(from: $0) != nil })
        else {
            throw CalendarDeadlineError.service("自定义日程查询范围不正确或超过 370 天。")
        }
        return try await cache.load(refreshStaleCache: true).snapshots(for: requestedDates)
    }

    static func fetchData(from url: URL) async throws -> Data {
        try CustomDeadlineFeedURLValidator.validate(url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: CustomDeadlineRedirectDelegate(),
            delegateQueue: nil
        )
        let request = try request(for: url)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              response.url == url
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CalendarDeadlineError.service("自定义日程返回 HTTP \(status)。")
        }
        guard response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(CalendarDeadlineSources.maximumPayloadBytes),
              data.count <= CalendarDeadlineSources.maximumPayloadBytes
        else {
            throw CalendarDeadlineError.service("自定义日程响应超过 2 MiB。")
        }
        return data
    }

    static func request(for url: URL) throws -> URLRequest {
        try CustomDeadlineFeedURLValidator.validate(url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
        return request
    }
}

protocol CustomDeadlineFeedFetching: Sendable {
    var sourceURL: URL { get }
    func fetch(dates: [String]) async throws -> [String: PublicDeadlineSnapshot]
    func validateFeed() async throws -> CustomDeadlineFeedMetadata
    func prewarm(dates: [String]) async throws -> [String: PublicDeadlineSnapshot]
}

extension CustomDeadlineFeedClient: CustomDeadlineFeedFetching {}

final class CustomDeadlineRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
