import Foundation

enum PublicDeadlineKind: String, CaseIterable, Sendable {
    case competition
    case summerCamp = "summer_camp"
    case hackathon

    var title: String {
        switch self {
        case .competition: "学科竞赛"
        case .summerCamp: "夏令营"
        case .hackathon: "黑客松"
        }
    }

    var systemImage: String {
        switch self {
        case .competition: "trophy"
        case .summerCamp: "tent"
        case .hackathon: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum PublicDeadlineSource: String, Sendable {
    case contestDDL = "contest_ddl"
    case schoolNotice = "school_notice"

    var title: String {
        switch self {
        case .contestDDL: "Contest DDL"
        case .schoolNotice: "校内竞赛通知"
        }
    }
}

struct PublicDeadlineItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: PublicDeadlineKind
    let source: PublicDeadlineSource
    let deadline: String
    let organizer: String?
    let officialURL: URL?
}

struct PublicDeadlineSnapshot: Equatable, Sendable {
    let date: String
    let items: [PublicDeadlineItem]
    let source: URL
    let usedBackup: Bool
}

struct AssignmentDeadlineItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let courseName: String?
    let deadline: String
    let status: String?
}

protocol PublicDeadlineFetching: Sendable {
    func fetch(date: String) async throws -> PublicDeadlineSnapshot
    func fetch(dates: [String]) async throws -> [String: PublicDeadlineSnapshot]
    func prewarm() async throws -> [String: PublicDeadlineSnapshot]
}

extension PublicDeadlineFetching {
    func fetch(dates: [String]) async throws -> [String: PublicDeadlineSnapshot] {
        var snapshots = [String: PublicDeadlineSnapshot]()
        for date in dates {
            snapshots[date] = try await fetch(date: date)
        }
        return snapshots
    }

    func prewarm() async throws -> [String: PublicDeadlineSnapshot] { [:] }
}

protocol AssignmentDeadlineFetching: Sendable {
    func fetch(date: String) async throws -> [AssignmentDeadlineItem]
    func fetch(dates: [String]) async throws -> [String: [AssignmentDeadlineItem]]
    func reset() async
}

extension AssignmentDeadlineFetching {
    func fetch(dates: [String]) async throws -> [String: [AssignmentDeadlineItem]] {
        var itemsByDate = [String: [AssignmentDeadlineItem]]()
        for date in dates {
            itemsByDate[date] = try await fetch(date: date)
        }
        return itemsByDate
    }
}

enum CalendarDeadlineError: LocalizedError, Equatable, Sendable {
    case service(String)

    var errorDescription: String? {
        switch self {
        case let .service(message): message
        }
    }
}

struct LoadedPublicDeadlineFeed: Sendable {
    struct ContestFeed: Sendable {
        let itemsByDate: [String: [PublicDeadlineItem]]
        let source: URL
        let usedBackup: Bool
    }

    let contest: ContestFeed?
    let schoolItemsByDate: [String: [PublicDeadlineItem]]

    func snapshots(for requestedDates: [String]? = nil) -> [String: PublicDeadlineSnapshot] {
        var dates = Set(requestedDates ?? [])
        if requestedDates == nil {
            if let contest {
                dates.formUnion(contest.itemsByDate.keys)
            }
            dates.formUnion(schoolItemsByDate.keys)
        }
        return Dictionary(uniqueKeysWithValues: dates.sorted().map { date in
            let contestItems = contest?.itemsByDate[date] ?? []
            let schoolItems = schoolItemsByDate[date] ?? []
            return (
                date,
                PublicDeadlineSnapshot(
                    date: date,
                    items: PublicDeadlineClient.merge([contestItems, schoolItems]),
                    source: contest?.source ?? CalendarDeadlineSources.schoolNotices,
                    usedBackup: contest?.usedBackup ?? false
                )
            )
        })
    }
}

actor PublicDeadlineFullFeedCache {
    typealias Loader = @Sendable () async throws -> LoadedPublicDeadlineFeed

    private struct CacheEntry {
        let fetchedAt: Date
        let feed: LoadedPublicDeadlineFeed
    }

    private struct InFlightFetch {
        let id: UInt64
        let task: Task<LoadedPublicDeadlineFeed, Error>
    }

    private static let lifetime: TimeInterval = 5 * 60

    private let loader: Loader
    private var cache: CacheEntry?
    private var inFlight: InFlightFetch?
    private var nextFlightID: UInt64 = 0

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func load(refreshStaleCache: Bool) async throws -> LoadedPublicDeadlineFeed {
        if let cache {
            let isFresh = Date().timeIntervalSince(cache.fetchedAt) < Self.lifetime
            if !refreshStaleCache || isFresh {
                return cache.feed
            }
        }

        let flight: InFlightFetch
        if let inFlight {
            flight = inFlight
        } else {
            nextFlightID &+= 1
            let loader = loader
            flight = InFlightFetch(
                id: nextFlightID,
                task: Task { try await loader() }
            )
            inFlight = flight
        }

        do {
            let feed = try await flight.task.value
            if inFlight?.id == flight.id {
                cache = CacheEntry(fetchedAt: Date(), feed: feed)
                inFlight = nil
            }
            return feed
        } catch {
            if inFlight?.id == flight.id {
                inFlight = nil
            }
            throw error
        }
    }
}

enum CalendarDeadlineSources {
    static let primary = URL(
        string: "https://nemoyuzx.github.io/contest-ddl/data/competitions.json"
    )!
    static let primaryPage = URL(string: "https://nemoyuzx.github.io/contest-ddl/")!
    static let backup = URL(string: "http://101.201.29.29/api/contest-events")!
    static let schoolNotices = URL(string: "http://101.201.29.29/api/contest-notices")!
    static let assignments = URL(
        string: "https://ucloud.bupt.edu.cn/uclass/course.html#/student/studentAssignmentListPage?ind=3"
    )!
    static let maximumPayloadBytes = 2 * 1024 * 1024
    static let maximumItemsPerDay = 100
}

struct PublicDeadlineClient: PublicDeadlineFetching {
    private let fullFeedCache: PublicDeadlineFullFeedCache

    init() {
        fullFeedCache = PublicDeadlineFullFeedCache {
            try await Self.loadFullFeed()
        }
    }

    init(feedLoader: @escaping PublicDeadlineFullFeedCache.Loader) {
        fullFeedCache = PublicDeadlineFullFeedCache(loader: feedLoader)
    }

    func fetch(date: String) async throws -> PublicDeadlineSnapshot {
        let snapshots = try await fetch(dates: [date])
        guard let snapshot = snapshots[date] else {
            throw CalendarDeadlineError.service("DDL 日期数据缺失。")
        }
        return snapshot
    }

    func fetch(dates: [String]) async throws -> [String: PublicDeadlineSnapshot] {
        let requestedDates = Array(Set(dates)).sorted()
        guard !requestedDates.isEmpty else { return [:] }
        guard requestedDates.allSatisfy({ StrictContractDateParser.date(from: $0) != nil }) else {
            throw CalendarDeadlineError.service("DDL 日期格式不正确。")
        }

        let feed = try await fullFeedCache.load(refreshStaleCache: false)
        return feed.snapshots(for: requestedDates)
    }

    func prewarm() async throws -> [String: PublicDeadlineSnapshot] {
        let feed = try await fullFeedCache.load(refreshStaleCache: true)
        return feed.snapshots()
    }

    private static func loadFullFeed() async throws -> LoadedPublicDeadlineFeed {
        var contest: LoadedPublicDeadlineFeed.ContestFeed?
        var contestError: Error?
        do {
            let data = try await Self.fetchData(
                from: CalendarDeadlineSources.primary,
                allowedScheme: "https",
                allowedHost: "nemoyuzx.github.io"
            )
            contest = LoadedPublicDeadlineFeed.ContestFeed(
                itemsByDate: try Self.parseAll(data: data),
                source: CalendarDeadlineSources.primary,
                usedBackup: false
            )
        } catch let primaryError {
            do {
                let data = try await Self.fetchData(
                    from: CalendarDeadlineSources.backup,
                    allowedScheme: "http",
                    allowedHost: "101.201.29.29"
                )
                contest = LoadedPublicDeadlineFeed.ContestFeed(
                    itemsByDate: try Self.parseAll(data: data),
                    source: CalendarDeadlineSources.backup,
                    usedBackup: true
                )
            } catch let backupError {
                contestError = CalendarDeadlineError.service(
                    "主 DDL 数据源不可用（\(primaryError.localizedDescription)）；"
                        + "备用数据源也不可用（\(backupError.localizedDescription)）。"
                )
            }
        }

        var schoolItemsByDate: [String: [PublicDeadlineItem]]?
        var schoolError: Error?
        do {
            let data = try await Self.fetchData(
                from: CalendarDeadlineSources.schoolNotices,
                allowedScheme: "http",
                allowedHost: "101.201.29.29"
            )
            schoolItemsByDate = try Self.parseAllSchoolNotices(data: data)
        } catch {
            schoolError = error
        }

        if contest == nil, schoolItemsByDate == nil {
            throw CalendarDeadlineError.service(
                "公开活动 DDL 不可用（\(contestError?.localizedDescription ?? "未知错误")）；"
                    + "校内竞赛通知也不可用（\(schoolError?.localizedDescription ?? "未知错误")）。"
            )
        }
        return LoadedPublicDeadlineFeed(
            contest: contest,
            schoolItemsByDate: schoolItemsByDate ?? [:]
        )
    }

    static func parse(data: Data, requestedDate: String) throws -> [PublicDeadlineItem] {
        guard StrictContractDateParser.date(from: requestedDate) != nil else {
            throw CalendarDeadlineError.service("DDL 日期格式不正确。")
        }
        return try parseAll(data: data)[requestedDate] ?? []
    }

    static func parseAll(data: Data) throws -> [String: [PublicDeadlineItem]] {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CalendarDeadlineError.service("DDL 数据格式不正确。")
        }
        let records = extractRecords(root)
        var itemsByDate = [String: [PublicDeadlineItem]]()
        for record in records {
            guard
                let rawKind = string(record, keys: ["event_type", "eventType", "type"]),
                let kind = PublicDeadlineKind(rawValue: rawKind),
                let id = string(record, keys: ["id", "event_id", "eventId"]),
                let name = string(record, keys: ["name", "title", "event_name"]),
                let deadline = string(
                    record,
                    keys: ["primary_deadline", "primaryDeadline", "deadline", "end_time"]
                ),
                parseISO8601(deadline) != nil,
                deadline.count >= 10
            else { continue }

            let date = String(deadline.prefix(10))
            guard StrictContractDateParser.date(from: date) != nil,
                  (itemsByDate[date]?.count ?? 0) < CalendarDeadlineSources.maximumItemsPerDay
            else { continue }

            let officialURL = string(
                record,
                keys: ["official_url", "officialUrl", "url"]
            ).flatMap { value -> URL? in
                guard
                    let url = URL(string: value),
                    url.scheme == "https",
                    url.host != nil,
                    url.user == nil,
                    url.password == nil
                else { return nil }
                return url
            }
            itemsByDate[date, default: []].append(PublicDeadlineItem(
                id: id,
                name: name,
                kind: kind,
                source: .contestDDL,
                deadline: deadline,
                organizer: string(record, keys: ["organizer", "host"]),
                officialURL: officialURL
            ))
        }
        return itemsByDate.mapValues { items in
            items.sorted { ($0.deadline, $0.name) < ($1.deadline, $1.name) }
        }
    }

    static func parse(
        data: Data,
        requestedDates: [String]
    ) throws -> [String: [PublicDeadlineItem]] {
        guard requestedDates.allSatisfy({ StrictContractDateParser.date(from: $0) != nil }) else {
            throw CalendarDeadlineError.service("DDL 日期格式不正确。")
        }
        let allItemsByDate = try parseAll(data: data)
        return Dictionary(uniqueKeysWithValues: requestedDates.map { date in
            (date, allItemsByDate[date] ?? [])
        })
    }

    static func parseSchoolNotices(
        data: Data,
        requestedDate: String
    ) throws -> [PublicDeadlineItem] {
        guard StrictContractDateParser.date(from: requestedDate) != nil else {
            throw CalendarDeadlineError.service("DDL 日期格式不正确。")
        }
        return try parseAllSchoolNotices(data: data)[requestedDate] ?? []
    }

    static func parseAllSchoolNotices(
        data: Data
    ) throws -> [String: [PublicDeadlineItem]] {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CalendarDeadlineError.service("校内竞赛通知格式不正确。")
        }
        var itemsByDate = [String: [PublicDeadlineItem]]()
        for record in extractRecords(root) {
            guard
                let id = string(record, keys: ["id", "source_id"]),
                let name = string(record, keys: ["name", "title"])
            else { continue }
            let source = string(record, keys: ["source"])
                ?? "北京邮电大学教学云平台"
            let officialURL = string(record, keys: ["source_url"])
                .flatMap(trustedOfficialURL)
            var deadlines = record["deadlines"] as? [[String: Any]] ?? []
            if deadlines.isEmpty,
               let primary = string(record, keys: ["primary_deadline"]) {
                deadlines = [[
                    "date": primary,
                    "label": string(record, keys: ["primary_deadline_label"]) ?? "截止时间"
                ]]
            }
            for (index, deadlineRecord) in deadlines.enumerated() {
                guard
                    let deadline = string(deadlineRecord, keys: ["date"]),
                    parseISO8601(deadline) != nil,
                    deadline.count >= 10
                else { continue }
                let date = String(deadline.prefix(10))
                guard StrictContractDateParser.date(from: date) != nil,
                      (itemsByDate[date]?.count ?? 0)
                        < CalendarDeadlineSources.maximumItemsPerDay
                else { continue }
                let label = string(deadlineRecord, keys: ["label"]) ?? "截止时间"
                itemsByDate[date, default: []].append(PublicDeadlineItem(
                    id: "school:\(id):\(index)",
                    name: name,
                    kind: .competition,
                    source: .schoolNotice,
                    deadline: deadline,
                    organizer: "\(source) · \(label)",
                    officialURL: officialURL
                ))
            }
        }
        return itemsByDate.mapValues { items in
            items.sorted { ($0.deadline, $0.name) < ($1.deadline, $1.name) }
        }
    }

    static func parseSchoolNotices(
        data: Data,
        requestedDates: [String]
    ) throws -> [String: [PublicDeadlineItem]] {
        guard requestedDates.allSatisfy({ StrictContractDateParser.date(from: $0) != nil }) else {
            throw CalendarDeadlineError.service("DDL 日期格式不正确。")
        }
        let allItemsByDate = try parseAllSchoolNotices(data: data)
        return Dictionary(uniqueKeysWithValues: requestedDates.map { date in
            (date, allItemsByDate[date] ?? [])
        })
    }

    static func merge(_ groups: [[PublicDeadlineItem]]) -> [PublicDeadlineItem] {
        var seen = Set<String>()
        var result = [PublicDeadlineItem]()
        for item in groups.flatMap({ $0 }) {
            let key = [
                item.source.rawValue,
                item.kind.rawValue,
                item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                item.deadline
            ].joined(separator: "\u{001F}")
            if seen.insert(key).inserted {
                result.append(item)
            }
        }
        return Array(result.sorted {
            ($0.deadline, $0.name) < ($1.deadline, $1.name)
        }.prefix(CalendarDeadlineSources.maximumItemsPerDay))
    }

    private static func fetchData(
        from url: URL,
        allowedScheme: String,
        allowedHost: String
    ) async throws -> Data {
        guard
            url.scheme == allowedScheme,
            url.host == allowedHost,
            url.user == nil,
            url.password == nil
        else {
            throw CalendarDeadlineError.service("DDL 数据源地址不受信任。")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(
            configuration: configuration,
            delegate: FixedDeadlineRedirectDelegate(),
            delegateQueue: nil
        )
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200 ... 299).contains(http.statusCode),
            response.url?.scheme == allowedScheme,
            response.url?.host == allowedHost
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CalendarDeadlineError.service("DDL 数据源返回错误，HTTP \(status)。")
        }
        guard
            response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(CalendarDeadlineSources.maximumPayloadBytes),
            data.count <= CalendarDeadlineSources.maximumPayloadBytes
        else {
            throw CalendarDeadlineError.service("DDL 数据响应过大。")
        }
        return data
    }

    private static func extractRecords(_ root: Any) -> [[String: Any]] {
        if let array = root as? [[String: Any]] { return array }
        guard let object = root as? [String: Any] else { return [] }
        for key in ["items", "records", "data"] {
            if let array = object[key] as? [[String: Any]] { return array }
            if let nested = object[key] as? [String: Any] {
                for nestedKey in ["items", "records"] {
                    if let array = nested[nestedKey] as? [[String: Any]] { return array }
                }
            }
        }
        return []
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            let raw: String?
            switch object[key] {
            case let value as String: raw = value
            case let value as NSNumber: raw = value.stringValue
            default: raw = nil
            }
            if let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private static func trustedOfficialURL(_ value: String) -> URL? {
        guard
            let url = URL(string: value),
            url.scheme == "https",
            url.host != nil,
            url.user == nil,
            url.password == nil
        else { return nil }
        return url
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

actor UCloudAssignmentClient: AssignmentDeadlineFetching {
    private struct Cache {
        let account: String
        let fetchedAt: Date
        let items: [AssignmentDeadlineItem]
    }

    private struct AuthenticatedSession {
        let session: URLSession
        let accessToken: String
        let userID: String
    }

    private struct InFlightFetch {
        let id: UInt64
        let revision: UInt64
        let task: Task<[AssignmentDeadlineItem], Error>
    }

    private static let casLoginURL = URL(
        string: "https://auth.bupt.edu.cn/authserver/login?service=https%3A%2F%2Fucloud.bupt.edu.cn"
    )!
    private static let serviceOrigin = URL(string: "https://ucloud.bupt.edu.cn")!
    private static let apiOrigin = URL(string: "https://apiucloud.bupt.edu.cn")!
    private static let portalAuthorization = "Basic  cG9ydGFsOnBvcnRhbF9zZWNyZXQ="
    private static let maximumLoginBytes = 1 * 1024 * 1024
    private static let maximumTokenBytes = 512 * 1024
    private static let maximumAPIBytes = 8 * 1024 * 1024
    private static let maximumCourses = 100
    private static let maximumAssignments = 5_000
    private static let cacheLifetime: TimeInterval = 10 * 60

    private let credentialStore: any CredentialStoring
    private let fetchAllProvider: @Sendable (Credentials) async throws -> [AssignmentDeadlineItem]
    private let flightSelectionObserver: (@Sendable (Bool) -> Void)?
    private var cache: Cache?
    private var inFlightFetches = [String: InFlightFetch]()
    private var revision: UInt64 = 0
    private var nextFlightID: UInt64 = 0

    init(credentialStore: any CredentialStoring = KeychainCredentialStore()) {
        self.credentialStore = credentialStore
        fetchAllProvider = { credentials in
            try await Self.fetchAll(credentials: credentials)
        }
        flightSelectionObserver = nil
    }

    init(
        credentialStore: any CredentialStoring,
        fetchAll: @escaping @Sendable (Credentials) async throws -> [AssignmentDeadlineItem],
        flightSelectionObserver: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.credentialStore = credentialStore
        fetchAllProvider = fetchAll
        self.flightSelectionObserver = flightSelectionObserver
    }

    func fetch(date: String) async throws -> [AssignmentDeadlineItem] {
        let itemsByDate = try await fetch(dates: [date])
        return itemsByDate[date] ?? []
    }

    func fetch(dates: [String]) async throws -> [String: [AssignmentDeadlineItem]] {
        let requestedDates = Array(Set(dates)).sorted()
        guard requestedDates.allSatisfy({ StrictContractDateParser.date(from: $0) != nil }) else {
            throw CalendarDeadlineError.service("作业日期格式不正确。")
        }
        guard !requestedDates.isEmpty else { return [:] }
        let allItems = try await accountWideItems()
        let requestedDateSet = Set(requestedDates)
        var itemsByDate = Dictionary(
            uniqueKeysWithValues: requestedDates.map { ($0, [AssignmentDeadlineItem]()) }
        )
        for item in allItems {
            let date = String(item.deadline.prefix(10))
            if requestedDateSet.contains(date) {
                itemsByDate[date, default: []].append(item)
            }
        }
        return itemsByDate
    }

    private func accountWideItems() async throws -> [AssignmentDeadlineItem] {
        guard let credentials = try credentialStore.load(),
              !credentials.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.password.isEmpty
        else {
            throw CalendarDeadlineError.service("请先在设置中保存教务账号和密码。")
        }
        let account = credentials.account.trimmingCharacters(in: .whitespacesAndNewlines)
        let allItems: [AssignmentDeadlineItem]
        if let cache,
           cache.account == account,
           Date().timeIntervalSince(cache.fetchedAt) < Self.cacheLifetime {
            allItems = cache.items
        } else {
            let flight: InFlightFetch
            let isFlightLeader: Bool
            if let existing = inFlightFetches[account], existing.revision == revision {
                flight = existing
                isFlightLeader = false
            } else {
                nextFlightID &+= 1
                let flightID = nextFlightID
                let requestRevision = revision
                let normalizedCredentials = Credentials(
                    account: account,
                    password: credentials.password
                )
                let fetchAllProvider = fetchAllProvider
                flight = InFlightFetch(
                    id: flightID,
                    revision: requestRevision,
                    task: Task {
                        try await fetchAllProvider(normalizedCredentials)
                    }
                )
                inFlightFetches[account] = flight
                isFlightLeader = true
            }
            flightSelectionObserver?(isFlightLeader)
            do {
                allItems = try await flight.task.value
            } catch {
                if inFlightFetches[account]?.id == flight.id {
                    inFlightFetches.removeValue(forKey: account)
                }
                throw error
            }
            guard revision == flight.revision else {
                throw CancellationError()
            }
            if inFlightFetches[account]?.id == flight.id {
                cache = Cache(account: account, fetchedAt: Date(), items: allItems)
                inFlightFetches.removeValue(forKey: account)
            }
        }
        return allItems
    }

    func reset() async {
        revision &+= 1
        cache = nil
        let invalidated = inFlightFetches.values.map(\.task)
        inFlightFetches.removeAll()
        invalidated.forEach { $0.cancel() }
    }

    private static func fetchAll(credentials: Credentials) async throws -> [AssignmentDeadlineItem] {
        let authenticated = try await authenticate(credentials: credentials)
        defer { authenticated.session.invalidateAndCancel() }
        let courseRoot = try await getAPI(
            path: "/ykt-site/site/list/student/current",
            queryItems: [
                URLQueryItem(name: "size", value: "9999"),
                URLQueryItem(name: "current", value: "1"),
                URLQueryItem(name: "userId", value: authenticated.userID),
                URLQueryItem(name: "siteRoleCode", value: "2")
            ],
            authenticated: authenticated
        )
        let courses = courseRecords(courseRoot).prefix(maximumCourses)
        var allItems = [AssignmentDeadlineItem]()
        var successfulCourseRequests = 0
        var firstCourseError: Error?
        for course in courses {
            let body: [String: Any] = [
                "siteId": course.id,
                "userId": authenticated.userID,
                "keyword": "",
                "chapterId": "",
                "nodeId": "",
                "current": 1,
                "size": 9999,
                "studentAssignmentStatus": "",
                "status": "",
                "sortColumn": "",
                "sortType": ""
            ]
            do {
                let root = try await postAPI(
                    path: "/ykt-site/work/student/list",
                    body: body,
                    authenticated: authenticated
                )
                successfulCourseRequests += 1
                allItems.append(contentsOf: AssignmentDeadlineParser.parseAll(
                    root: root,
                    courseNameOverride: course.name
                ))
            } catch {
                if firstCourseError == nil { firstCourseError = error }
            }
            if allItems.count >= maximumAssignments { break }
        }
        if !courses.isEmpty, successfulCourseRequests == 0 {
            throw firstCourseError
                ?? CalendarDeadlineError.service("教学云课程作业接口暂时不可用。")
        }

        if let undoneRoot = try? await getAPI(
            path: "/ykt-site/site/student/undone",
            queryItems: [URLQueryItem(name: "userId", value: authenticated.userID)],
            authenticated: authenticated
        ) {
            allItems.append(contentsOf: AssignmentDeadlineParser.parseAll(
                root: undoneRoot,
                courseNameOverride: nil
            ))
        }
        return merge(allItems)
    }

    private static func authenticate(credentials: Credentials) async throws -> AuthenticatedSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(
            configuration: configuration,
            delegate: FixedDeadlineRedirectDelegate(),
            delegateQueue: nil
        )
        do {
            var loginPageRequest = URLRequest(url: casLoginURL)
            loginPageRequest.timeoutInterval = 20
            loginPageRequest.setValue("text/html", forHTTPHeaderField: "Accept")
            loginPageRequest.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
            let (loginData, loginResponse) = try await session.data(for: loginPageRequest)
            let loginHTTP = try checkedHTTP(
                loginResponse,
                data: loginData,
                maximumBytes: maximumLoginBytes,
                label: "统一认证登录页",
                expectedHost: "auth.bupt.edu.cn",
                acceptedStatuses: 200 ... 299
            )
            guard let html = String(data: loginData, encoding: .utf8),
                  let execution = parseExecution(html)
            else {
                throw CalendarDeadlineError.service("统一认证登录页缺少 execution 参数。")
            }
            let cookies = cookieHeader(response: loginHTTP, url: casLoginURL)
            guard !cookies.isEmpty, cookies.utf8.count <= 16 * 1024 else {
                throw CalendarDeadlineError.service("统一认证未返回有效会话 Cookie。")
            }

            var loginRequest = URLRequest(url: casLoginURL)
            loginRequest.httpMethod = "POST"
            loginRequest.timeoutInterval = 20
            loginRequest.httpBody = formData([
                ("username", credentials.account),
                ("password", credentials.password),
                ("type", "username_password"),
                ("execution", execution),
                ("_eventId", "submit")
            ])
            loginRequest.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            loginRequest.setValue(cookies, forHTTPHeaderField: "Cookie")
            loginRequest.setValue(casLoginURL.absoluteString, forHTTPHeaderField: "Referer")
            loginRequest.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
            let (loginResultData, loginResultResponse) = try await session.data(for: loginRequest)
            guard loginResultData.count <= maximumLoginBytes,
                  let loginResultHTTP = loginResultResponse as? HTTPURLResponse,
                  let location = loginResultHTTP.value(forHTTPHeaderField: "Location"),
                  let ticket = ticket(from: location)
            else {
                throw CalendarDeadlineError.service(
                    "统一认证未返回有效票据；请检查账号密码，若官方页面要求验证码请先完成验证。"
                )
            }

            let tokenURL = try trustedAPIURL(path: "/ykt-basics/oauth/token")
            var tokenRequest = URLRequest(url: tokenURL)
            tokenRequest.httpMethod = "POST"
            tokenRequest.timeoutInterval = 20
            tokenRequest.httpBody = formData([
                ("ticket", ticket),
                ("grant_type", "third")
            ])
            applyAPIHeaders(to: &tokenRequest, accessToken: nil)
            tokenRequest.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            let (tokenData, tokenResponse) = try await session.data(for: tokenRequest)
            _ = try checkedHTTP(
                tokenResponse,
                data: tokenData,
                maximumBytes: maximumTokenBytes,
                label: "教学云令牌接口",
                expectedHost: "apiucloud.bupt.edu.cn",
                acceptedStatuses: 200 ... 299
            )
            guard let tokenObject = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
                  let accessToken = string(tokenObject["access_token"]),
                  let userID = string(tokenObject["user_id"] ?? tokenObject["userId"])
            else {
                throw CalendarDeadlineError.service("教学云令牌接口未返回有效令牌或用户标识。")
            }
            return AuthenticatedSession(
                session: session,
                accessToken: accessToken,
                userID: userID
            )
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }

    private static func getAPI(
        path: String,
        queryItems: [URLQueryItem],
        authenticated: AuthenticatedSession
    ) async throws -> Any {
        let base = try trustedAPIURL(path: path)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw CalendarDeadlineError.service("教学云接口地址无效。")
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw CalendarDeadlineError.service("教学云接口地址无效。")
        }
        var request = URLRequest(url: url)
        applyAPIHeaders(to: &request, accessToken: authenticated.accessToken)
        return try await apiRoot(request: request, session: authenticated.session)
    }

    private static func postAPI(
        path: String,
        body: [String: Any],
        authenticated: AuthenticatedSession
    ) async throws -> Any {
        var request = URLRequest(url: try trustedAPIURL(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAPIHeaders(to: &request, accessToken: authenticated.accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await apiRoot(request: request, session: authenticated.session)
    }

    private static func apiRoot(request: URLRequest, session: URLSession) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        _ = try checkedHTTP(
            response,
            data: data,
            maximumBytes: maximumAPIBytes,
            label: "教学云数据接口",
            expectedHost: "apiucloud.bupt.edu.cn",
            acceptedStatuses: 200 ... 299
        )
        let root = try JSONSerialization.jsonObject(with: data)
        if let object = root as? [String: Any],
           let code = string(object["code"]), code != "200" {
            throw CalendarDeadlineError.service("教学云数据接口返回业务状态 (code)。")
        }
        return root
    }

    private static func trustedAPIURL(path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: apiOrigin)?.absoluteURL,
              url.scheme == "https",
              url.host == "apiucloud.bupt.edu.cn",
              url.user == nil,
              url.password == nil
        else {
            throw CalendarDeadlineError.service("教学云接口地址不受信任。")
        }
        return url
    }

    private static func checkedHTTP(
        _ response: URLResponse,
        data: Data,
        maximumBytes: Int,
        label: String,
        expectedHost: String,
        acceptedStatuses: ClosedRange<Int>
    ) throws -> HTTPURLResponse {
        guard data.count <= maximumBytes,
              response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(maximumBytes)
        else {
            throw CalendarDeadlineError.service("\(label)响应过大。")
        }
        guard let http = response as? HTTPURLResponse,
              acceptedStatuses.contains(http.statusCode),
              response.url?.scheme == "https",
              response.url?.host == expectedHost
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CalendarDeadlineError.service("\(label)返回 HTTP \(status)。")
        }
        return http
    }

    private static func applyAPIHeaders(to request: inout URLRequest, accessToken: String?) {
        request.timeoutInterval = 20
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(portalAuthorization, forHTTPHeaderField: "Authorization")
        request.setValue("000000", forHTTPHeaderField: "Tenant-Id")
        request.setValue(serviceOrigin.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
        if let accessToken {
            request.setValue(accessToken, forHTTPHeaderField: "Blade-Auth")
        }
    }

    private static func formData(_ fields: [(String, String)]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func cookieHeader(response: HTTPURLResponse, url: URL) -> String {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = String(describing: entry.value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
    }

    static func parseExecution(_ html: String) -> String? {
        guard let inputRegex = try? NSRegularExpression(
            pattern: #"<input\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let attributeRegex = try? NSRegularExpression(
            pattern: #"\b(name|value)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let wholeRange = NSRange(html.startIndex ..< html.endIndex, in: html)
        for match in inputRegex.matches(in: html, range: wholeRange) {
            guard let inputRange = Range(match.range, in: html) else { continue }
            let input = String(html[inputRange])
            let inputNSRange = NSRange(input.startIndex ..< input.endIndex, in: input)
            var name: String?
            var value: String?
            for attribute in attributeRegex.matches(in: input, range: inputNSRange) {
                guard let keyRange = Range(attribute.range(at: 1), in: input) else { continue }
                let rawValue = (2 ... 4).compactMap { index -> String? in
                    guard attribute.range(at: index).location != NSNotFound,
                          let range = Range(attribute.range(at: index), in: input)
                    else { return nil }
                    return String(input[range])
                }.first
                guard let rawValue else { continue }
                switch input[keyRange].lowercased() {
                case "name": name = decodeHTMLEntities(rawValue)
                case "value": value = decodeHTMLEntities(rawValue)
                default: break
                }
            }
            if name == "execution", let value, !value.isEmpty { return value }
        }
        return nil
    }

    static func ticket(from location: String) -> String? {
        guard let url = URL(string: location, relativeTo: serviceOrigin)?.absoluteURL,
              url.scheme == "https",
              url.host == "ucloud.bupt.edu.cn",
              url.user == nil,
              url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let ticket = components.queryItems?.first(where: { $0.name == "ticket" })?.value,
              !ticket.isEmpty
        else { return nil }
        return ticket
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func string(_ value: Any?) -> String? {
        let result: String?
        switch value {
        case let value as String: result = value
        case let value as NSNumber: result = value.stringValue
        default: result = nil
        }
        return result?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func courseRecords(_ root: Any) -> [(id: String, name: String?)] {
        guard let object = root as? [String: Any] else { return [] }
        let firstData = object["data"] as? [String: Any] ?? object
        let secondData = firstData["data"] as? [String: Any] ?? firstData
        let records = secondData["records"] as? [[String: Any]] ?? []
        return records.compactMap { record in
            guard let id = string(record["id"] ?? record["siteId"] ?? record["courseId"])
            else { return nil }
            let name = string(
                record["siteName"] ?? record["courseName"] ?? record["siteTitle"] ?? record["name"]
            )
            return (id, name)
        }
    }

    private static func merge(_ items: [AssignmentDeadlineItem]) -> [AssignmentDeadlineItem] {
        var resultByKey = [String: AssignmentDeadlineItem]()
        for item in items.prefix(maximumAssignments) {
            let key = "\(item.id)\u{1F}\(item.deadline)"
            if let existing = resultByKey[key] {
                if existing.courseName == nil, item.courseName != nil {
                    resultByKey[key] = item
                }
            } else {
                resultByKey[key] = item
            }
        }
        return resultByKey.values.sorted {
            ($0.deadline, $0.courseName ?? "", $0.title, $0.id)
                < ($1.deadline, $1.courseName ?? "", $1.title, $1.id)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum AssignmentDeadlineParser {
    static func parse(data: Data, requestedDate: String) throws -> [AssignmentDeadlineItem] {
        guard StrictContractDateParser.date(from: requestedDate) != nil else {
            throw CalendarDeadlineError.service("作业日期格式不正确。")
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CalendarDeadlineError.service("作业数据格式不正确。")
        }
        return parseAll(root: root, courseNameOverride: nil)
            .filter { $0.deadline.hasPrefix(requestedDate) }
            .sorted { ($0.deadline, $0.title) < ($1.deadline, $1.title) }
    }

    static func parseAll(
        root: Any,
        courseNameOverride: String?
    ) -> [AssignmentDeadlineItem] {
        collectRecords(root).compactMap { record in
            if let type = number(record["type"]), type != 3, type != 5 { return nil }
            guard
                let deadline = string(record, keys: ["assignmentEndTime", "endTime"]),
                parseAssignmentDate(deadline) != nil,
                let id = string(record, keys: ["id", "assignmentId", "activityId"]),
                let title = string(
                    record,
                    keys: ["assignmentTitle", "activityName", "title"]
                )
            else { return nil }
            return AssignmentDeadlineItem(
                id: id,
                title: title,
                courseName: string(record, keys: ["siteName", "courseName", "siteTitle"])
                    ?? courseNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                deadline: deadline,
                status: assignmentStatus(record["assignmentStatus"])
            )
        }
    }

    private static func collectRecords(_ root: Any) -> [[String: Any]] {
        guard let object = root as? [String: Any] else { return [] }
        let firstData = object["data"] as? [String: Any] ?? object
        let secondData = firstData["data"] as? [String: Any] ?? firstData
        return (secondData["records"] as? [[String: Any]])
            ?? (secondData["undoneList"] as? [[String: Any]])
            ?? []
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            let raw: String?
            switch object[key] {
            case let value as String: raw = value
            case let value as NSNumber: raw = value.stringValue
            default: raw = nil
            }
            if let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private static func assignmentStatus(_ value: Any?) -> String? {
        switch number(value) {
        case 99: "未提交"
        case 0: "已提交"
        case 1: "已批改"
        case 2: "已驳回"
        default: (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func parseAssignmentDate(_ value: String) -> Date? {
        if let date = PublicDeadlineClientDateBridge.parseISO8601(value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .shanghai
        formatter.timeZone = Calendar.shanghai.timeZone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private enum PublicDeadlineClientDateBridge {
    static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private final class FixedDeadlineRedirectDelegate: NSObject, URLSessionTaskDelegate {
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

@MainActor
final class CalendarDeadlineStore: ObservableObject {
    @Published private(set) var publicByDate = [String: PublicDeadlineSnapshot]()
    @Published private(set) var publicErrors = [String: String]()
    @Published private(set) var loadingPublicDates = Set<String>()
    @Published private(set) var assignmentsByDate = [String: [AssignmentDeadlineItem]]()
    @Published private(set) var assignmentUnavailableByDate = [String: String]()
    @Published private(set) var loadingAssignmentDates = Set<String>()

    private let client: any PublicDeadlineFetching
    private let assignmentClient: any AssignmentDeadlineFetching
    private var assignmentRevision: UInt64 = 0
    private var publicPrewarmFlight: (
        id: UInt64,
        task: Task<[String: PublicDeadlineSnapshot], Error>
    )?
    private var nextPublicPrewarmFlightID: UInt64 = 0

    init(
        client: any PublicDeadlineFetching = PublicDeadlineClient(),
        assignmentClient: any AssignmentDeadlineFetching = UCloudAssignmentClient()
    ) {
        self.client = client
        self.assignmentClient = assignmentClient
    }

    func prewarmPublicIfNeeded(
        publicDeadlinesEnabled: Bool,
        sampleMode: Bool
    ) async {
        guard publicDeadlinesEnabled, !sampleMode else { return }

        let flight: (id: UInt64, task: Task<[String: PublicDeadlineSnapshot], Error>)
        if let publicPrewarmFlight {
            flight = publicPrewarmFlight
        } else {
            nextPublicPrewarmFlightID &+= 1
            let client = client
            flight = (
                id: nextPublicPrewarmFlightID,
                task: Task { try await client.prewarm() }
            )
            publicPrewarmFlight = flight
        }

        do {
            let snapshots = try await flight.task.value
            guard publicPrewarmFlight?.id == flight.id else { return }
            var updated = publicByDate
            for (date, snapshot) in snapshots {
                updated[date] = snapshot
            }
            publicByDate = updated
            publicPrewarmFlight = nil
        } catch {
            if publicPrewarmFlight?.id == flight.id {
                // Startup prewarming is deliberately silent. Leaving the
                // completion flag unset lets the visible date load or a later
                // settings off -> on transition retry the same shared client.
                publicPrewarmFlight = nil
            }
        }
    }

    func loadPublic(date: String, sampleMode: Bool, force: Bool = false) async {
        await loadPublic(dates: [date], sampleMode: sampleMode, force: force)
    }

    func loadPublic(dates: [String], sampleMode: Bool, force: Bool = false) async {
        let requestedDates = Array(Set(dates)).sorted().filter { date in
            (force || publicByDate[date] == nil) && !loadingPublicDates.contains(date)
        }
        guard !requestedDates.isEmpty else { return }
        loadingPublicDates.formUnion(requestedDates)
        var clearedErrors = publicErrors
        requestedDates.forEach { clearedErrors.removeValue(forKey: $0) }
        publicErrors = clearedErrors
        defer { loadingPublicDates.subtract(requestedDates) }
        if sampleMode {
            var updated = publicByDate
            for date in requestedDates {
                updated[date] = PublicDeadlineSnapshot(
                    date: date,
                    items: [
                        PublicDeadlineItem(
                            id: "sample-competition",
                            name: "全国大学生示例竞赛",
                            kind: .competition,
                            source: .contestDDL,
                            deadline: "\(date)T23:59:00+08:00",
                            organizer: "示例组委会",
                            officialURL: nil
                        ),
                        PublicDeadlineItem(
                            id: "sample-school-notice",
                            name: "校内示例竞赛通知",
                            kind: .competition,
                            source: .schoolNotice,
                            deadline: "\(date)T18:00:00+08:00",
                            organizer: "学校公开通知页",
                            officialURL: nil
                        )
                    ],
                    source: CalendarDeadlineSources.primary,
                    usedBackup: false
                )
            }
            publicByDate = updated
            return
        }
        do {
            // The visible SwiftUI task is intentionally allowed to be cancelled
            // when users page or select quickly. Keep the shared range owner
            // unstructured so its cache write still completes; a replacement
            // view task can safely observe the same loading set instead of
            // leaving the month permanently empty.
            let rangeOwner = Task {
                try await client.fetch(dates: requestedDates)
            }
            let snapshots = try await rangeOwner.value
            var updated = publicByDate
            for date in requestedDates {
                updated[date] = snapshots[date] ?? PublicDeadlineSnapshot(
                    date: date,
                    items: [],
                    source: CalendarDeadlineSources.primary,
                    usedBackup: false
                )
            }
            publicByDate = updated
        } catch {
            var updated = publicErrors
            requestedDates.forEach { updated[$0] = error.localizedDescription }
            publicErrors = updated
        }
    }

    func loadCalendarEvents(
        dates: [String],
        sampleMode: Bool,
        includesPublicDeadlines: Bool
    ) async {
        let requestedDates = Array(Set(dates)).sorted()
        guard !requestedDates.isEmpty else { return }
        if includesPublicDeadlines {
            await loadPublic(dates: requestedDates, sampleMode: sampleMode)
        }
        guard !Task.isCancelled else { return }
        await loadAssignments(dates: requestedDates, sampleMode: sampleMode)
    }

    func loadAssignments(date: String, sampleMode: Bool, force: Bool = false) async {
        await loadAssignments(dates: [date], sampleMode: sampleMode, force: force)
    }

    func loadAssignments(dates: [String], sampleMode: Bool, force: Bool = false) async {
        let requestedDates = Array(Set(dates)).sorted().filter { date in
            (force || assignmentsByDate[date] == nil) && !loadingAssignmentDates.contains(date)
        }
        guard !requestedDates.isEmpty else { return }
        if sampleMode {
            var updatedAssignments = assignmentsByDate
            var updatedUnavailable = assignmentUnavailableByDate
            for date in requestedDates {
                updatedAssignments[date] = [
                    AssignmentDeadlineItem(
                        id: "sample-assignment",
                        title: "示例课程作业",
                        courseName: "示例课程",
                        deadline: "\(date) 23:59:00",
                        status: "未提交"
                    )
                ]
                updatedUnavailable.removeValue(forKey: date)
            }
            assignmentsByDate = updatedAssignments
            assignmentUnavailableByDate = updatedUnavailable
            return
        }
        let requestRevision = assignmentRevision
        loadingAssignmentDates.formUnion(requestedDates)
        var loadingMessages = assignmentUnavailableByDate
        requestedDates.forEach { loadingMessages[$0] = "正在同步云课堂作业…" }
        assignmentUnavailableByDate = loadingMessages
        defer {
            if assignmentRevision == requestRevision {
                loadingAssignmentDates.subtract(requestedDates)
            }
        }
        do {
            let itemsByDate = try await assignmentClient.fetch(dates: requestedDates)
            guard assignmentRevision == requestRevision else { return }
            var updatedAssignments = assignmentsByDate
            var updatedUnavailable = assignmentUnavailableByDate
            for date in requestedDates {
                updatedAssignments[date] = itemsByDate[date] ?? []
                updatedUnavailable.removeValue(forKey: date)
            }
            assignmentsByDate = updatedAssignments
            assignmentUnavailableByDate = updatedUnavailable
        } catch {
            guard assignmentRevision == requestRevision else { return }
            var updatedAssignments = assignmentsByDate
            var updatedUnavailable = assignmentUnavailableByDate
            for date in requestedDates {
                updatedAssignments[date] = []
                updatedUnavailable[date] = error.localizedDescription
            }
            assignmentsByDate = updatedAssignments
            assignmentUnavailableByDate = updatedUnavailable
        }
    }

    func clearAssignments() {
        assignmentRevision &+= 1
        assignmentsByDate.removeAll()
        assignmentUnavailableByDate.removeAll()
        loadingAssignmentDates.removeAll()
        Task { await assignmentClient.reset() }
    }
}
