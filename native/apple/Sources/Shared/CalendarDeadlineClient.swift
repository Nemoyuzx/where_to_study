import Foundation

enum PublicDeadlineKind: String, CaseIterable, Codable, Sendable {
    case competition
    case conference
    case journalSpecialIssue = "journal_special_issue"
    case summerCamp = "summer_camp"
    case hackathon
    case preAdmission = "pre_admission"
    case custom

    var title: String {
        switch self {
        case .competition: "学科竞赛"
        case .conference: "学术会议"
        case .journalSpecialIssue: "期刊专题"
        case .summerCamp: "夏令营"
        case .hackathon: "黑客松"
        case .preAdmission: "预推免"
        case .custom: "自定义日程"
        }
    }

    var systemImage: String {
        switch self {
        case .competition: "trophy"
        case .conference: "person.3"
        case .journalSpecialIssue: "doc.text.magnifyingglass"
        case .summerCamp: "tent"
        case .hackathon: "chevron.left.forwardslash.chevron.right"
        case .preAdmission: "graduationcap"
        case .custom: "calendar.badge.plus"
        }
    }
}

enum PublicDeadlineSource: String, Codable, Sendable {
    case contestDDL = "contest_ddl"
    case schoolNotice = "school_notice"
    case custom

    var title: String {
        switch self {
        case .contestDDL: "Contest DDL"
        case .schoolNotice: "校内竞赛通知"
        case .custom: "自定义日程"
        }
    }
}

struct PublicDeadlineMetadataSource: Codable, Equatable, Sendable {
    let name: String
    let url: URL?
    let sourceType: String?
    let authority: Int?
}

struct PublicDeadlineItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: PublicDeadlineKind
    let source: PublicDeadlineSource
    let deadline: String
    let organizer: String?
    let officialURL: URL?
    let sourceName: String?
    let sourceHomepage: URL?
    let categories: [String]
    let tags: [String]
    let level: String?
    let location: String?
    let description: String?
    let eligibility: String?
    let notes: String?
    let metadataSource: PublicDeadlineMetadataSource?
    let status: String?
    let region: String?
    let mode: String?
    let archived: Bool

    init(
        id: String,
        name: String,
        kind: PublicDeadlineKind,
        source: PublicDeadlineSource,
        deadline: String,
        organizer: String?,
        officialURL: URL?,
        sourceName: String? = nil,
        sourceHomepage: URL? = nil,
        categories: [String] = [],
        tags: [String] = [],
        level: String? = nil,
        location: String? = nil,
        description: String? = nil,
        eligibility: String? = nil,
        notes: String? = nil,
        metadataSource: PublicDeadlineMetadataSource? = nil,
        status: String? = nil,
        region: String? = nil,
        mode: String? = nil,
        archived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.source = source
        self.deadline = deadline
        self.organizer = organizer
        self.officialURL = officialURL
        self.sourceName = sourceName
        self.sourceHomepage = sourceHomepage
        self.categories = categories
        self.tags = tags
        self.level = level
        self.location = location
        self.description = description
        self.eligibility = eligibility
        self.notes = notes
        self.metadataSource = metadataSource
        self.status = status
        self.region = region
        self.mode = mode
        self.archived = archived
    }

    var favoriteID: String {
        [source.rawValue, sourceName ?? "", id, deadline].joined(separator: "\u{001F}")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, source, deadline, organizer, officialURL, sourceName, sourceHomepage
        case categories, tags, level, location, description, eligibility, notes, metadataSource
        case status, region, mode, archived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(PublicDeadlineKind.self, forKey: .kind)
        source = try container.decode(PublicDeadlineSource.self, forKey: .source)
        deadline = try container.decode(String.self, forKey: .deadline)
        organizer = try container.decodeIfPresent(String.self, forKey: .organizer)
        officialURL = try container.decodeIfPresent(URL.self, forKey: .officialURL)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceHomepage = try container.decodeIfPresent(URL.self, forKey: .sourceHomepage)
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        level = try container.decodeIfPresent(String.self, forKey: .level)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        eligibility = try container.decodeIfPresent(String.self, forKey: .eligibility)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        metadataSource = try container.decodeIfPresent(
            PublicDeadlineMetadataSource.self,
            forKey: .metadataSource
        )
        status = try container.decodeIfPresent(String.self, forKey: .status)
        region = try container.decodeIfPresent(String.self, forKey: .region)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

struct PublicDeadlineSnapshot: Equatable, Sendable {
    let date: String
    let items: [PublicDeadlineItem]
    let source: URL
    let usedBackup: Bool
}

struct AssignmentDeadlineItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let courseName: String?
    let deadline: String
    let status: String?
    let courseID: String?

    init(id: String, title: String, courseName: String?, deadline: String, status: String?, courseID: String? = nil) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.deadline = deadline
        self.status = status
        self.courseID = courseID
    }
}

protocol PublicDeadlineFetching: Sendable {
    func fetch(date: String) async throws -> PublicDeadlineSnapshot
    func fetch(dates: [String]) async throws -> [String: PublicDeadlineSnapshot]
    func prewarm() async throws -> [String: PublicDeadlineSnapshot]
    func refresh() async throws -> [String: PublicDeadlineSnapshot]
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

    func refresh() async throws -> [String: PublicDeadlineSnapshot] {
        try await prewarm()
    }
}

protocol AssignmentDeadlineFetching: Sendable {
    func fetchAll(force: Bool) async throws -> [AssignmentDeadlineItem]
    func fetch(date: String) async throws -> [AssignmentDeadlineItem]
    func fetch(dates: [String]) async throws -> [String: [AssignmentDeadlineItem]]
    func reset() async
    func cachedAssignmentResult() async throws -> AssignmentDeadlineResult?
    func fetchAssignmentResult(force: Bool) async throws -> AssignmentDeadlineResult
    func fetchAssignmentResult(dates: [String], force: Bool) async throws -> AssignmentDeadlineResult
    func isAssignmentScopeCurrent(_ scope: CourseBusinessCacheScope) -> Bool
}

struct AssignmentDeadlineResult: Sendable {
    let items: [AssignmentDeadlineItem]
    let fetchedAt: String
    var scope: CourseBusinessCacheScope? = nil
    var partial = false
    var retainingPrevious = false
    var cachePersistenceFailed = false
    var coversAllCourses = true
}

private struct UCloudPartialAssignmentError: Error, Sendable {
    let items: [AssignmentDeadlineItem]
}

extension AssignmentDeadlineFetching {
    func cachedAssignmentResult() async throws -> AssignmentDeadlineResult? { nil }
    func isAssignmentScopeCurrent(_: CourseBusinessCacheScope) -> Bool { true }
    func fetchAssignmentResult(force: Bool) async throws -> AssignmentDeadlineResult {
        let items = try await fetchAll(force: force)
        return .init(items: items, fetchedAt: SJDClassroomClient.timestamp())
    }
    func fetchAssignmentResult(dates: [String], force: Bool) async throws -> AssignmentDeadlineResult {
        let grouped = try await fetch(dates: dates)
        return .init(items: dates.sorted().flatMap { grouped[$0] ?? [] }, fetchedAt: SJDClassroomClient.timestamp(),
                     coversAllCourses: false)
    }
    func fetchAll(force: Bool) async throws -> [AssignmentDeadlineItem] {
        throw CalendarDeadlineError.service("课程作业查询暂不可用，请稍后重试。")
    }
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

    func load(
        refreshStaleCache: Bool,
        forceReload: Bool = false
    ) async throws -> LoadedPublicDeadlineFeed {
        if let cache {
            let isFresh = Date().timeIntervalSince(cache.fetchedAt) < Self.lifetime
            if !forceReload, (!refreshStaleCache || isFresh) {
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
    static let mirror = URL(
        string: "https://where-to-study.cn/contest-ddl/data/competitions.json"
    )!
    static let primaryPage = URL(string: "https://nemoyuzx.github.io/contest-ddl/")!
    static let backup = URL(string: "https://where-to-study.cn/api/contest-events")!
    static let schoolNotices = URL(string: "https://where-to-study.cn/api/contest-notices")!
    static let assignments = URL(
        string: "https://ucloud.bupt.edu.cn/uclass/course.html#/student/studentAssignmentListPage?ind=3"
    )!
    static let maximumPayloadBytes = 4 * 1024 * 1024
    static let maximumItemsPerDay = 100
}

struct PublicDeadlineClient: PublicDeadlineFetching {
    private struct ContestCandidate: Sendable {
        let feed: LoadedPublicDeadlineFeed.ContestFeed
        let generatedAt: Date
    }

    private struct ContestFetchAttempt: Sendable {
        let candidate: ContestCandidate?
        let errorDescription: String?
    }

    typealias DataLoader = @Sendable (URL) async throws -> Data

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

    func refresh() async throws -> [String: PublicDeadlineSnapshot] {
        let feed = try await fullFeedCache.load(refreshStaleCache: true, forceReload: true)
        return feed.snapshots()
    }

    private static func loadFullFeed() async throws -> LoadedPublicDeadlineFeed {
        try await loadFullFeed { url in
            let allowedHost: String
            switch url {
            case CalendarDeadlineSources.primary:
                allowedHost = "nemoyuzx.github.io"
            case CalendarDeadlineSources.mirror,
                 CalendarDeadlineSources.backup,
                 CalendarDeadlineSources.schoolNotices:
                allowedHost = "where-to-study.cn"
            default:
                throw CalendarDeadlineError.service("DDL 数据源地址不受信任。")
            }
            return try await fetchData(
                from: url,
                allowedScheme: "https",
                allowedHost: allowedHost
            )
        }
    }

    static func loadFullFeed(
        fetchData: @escaping DataLoader
    ) async throws -> LoadedPublicDeadlineFeed {
        var contest: LoadedPublicDeadlineFeed.ContestFeed?
        var contestError: Error?
        async let primaryAttempt = Self.fetchContestCandidate(
            from: CalendarDeadlineSources.primary,
            usedBackup: false,
            fetchData: fetchData
        )
        async let mirrorAttempt = Self.fetchContestCandidate(
            from: CalendarDeadlineSources.mirror,
            usedBackup: true,
            fetchData: fetchData
        )
        let (primary, mirror) = await (primaryAttempt, mirrorAttempt)
        if let primaryCandidate = primary.candidate,
           let mirrorCandidate = mirror.candidate {
            contest = mirrorCandidate.generatedAt > primaryCandidate.generatedAt
                ? mirrorCandidate.feed : primaryCandidate.feed
        } else {
            contest = primary.candidate?.feed ?? mirror.candidate?.feed
        }
        if contest == nil {
            do {
                let data = try await fetchData(CalendarDeadlineSources.backup)
                contest = try Self.parseContestCandidate(
                    data: data,
                    source: CalendarDeadlineSources.backup,
                    usedBackup: true
                ).feed
            } catch {
                contestError = CalendarDeadlineError.service(
                    "主 DDL 数据源不可用（\(primary.errorDescription ?? "未知错误")）；"
                        + "镜像数据源不可用（\(mirror.errorDescription ?? "未知错误")）；"
                        + "备用接口也不可用（\(error.localizedDescription)）。"
                )
            }
        }

        var schoolItemsByDate: [String: [PublicDeadlineItem]]?
        var schoolError: Error?
        do {
            let data = try await fetchData(CalendarDeadlineSources.schoolNotices)
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

    private static func fetchContestCandidate(
        from source: URL,
        usedBackup: Bool,
        fetchData: @escaping DataLoader
    ) async -> ContestFetchAttempt {
        do {
            let data = try await fetchData(source)
            return ContestFetchAttempt(
                candidate: try parseContestCandidate(
                    data: data,
                    source: source,
                    usedBackup: usedBackup
                ),
                errorDescription: nil
            )
        } catch {
            return ContestFetchAttempt(candidate: nil, errorDescription: error.localizedDescription)
        }
    }

    private static func parseContestCandidate(
        data: Data,
        source: URL,
        usedBackup: Bool
    ) throws -> ContestCandidate {
        guard data.count <= CalendarDeadlineSources.maximumPayloadBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = root["schema_version"] as? String,
              schemaVersion == "1.4",
              root["timezone"] as? String == "Asia/Shanghai",
              let timestamp = root["generated_at"] as? String,
              let generatedAt = parseISO8601(timestamp),
              let records = root["items"] as? [[String: Any]],
              records.count <= 5_000
        else {
            throw CalendarDeadlineError.service("DDL 数据结构或生成时间不正确。")
        }
        return ContestCandidate(
            feed: LoadedPublicDeadlineFeed.ContestFeed(
                itemsByDate: parseAll(root: root),
                source: source,
                usedBackup: usedBackup
            ),
            generatedAt: generatedAt
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
        return parseAll(root: root)
    }

    private static func parseAll(root: Any) -> [String: [PublicDeadlineItem]] {
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
                officialURL: officialURL,
                categories: stringArray(record, key: "categories"),
                tags: stringArray(record, key: "tags"),
                level: string(record, keys: ["level"]),
                location: string(record, keys: ["location"]),
                description: string(record, keys: ["description"]),
                eligibility: string(record, keys: ["eligibility"]),
                notes: string(record, keys: ["notes"]),
                metadataSource: metadataSource(record["source"]),
                status: string(record, keys: ["status"]),
                region: string(record, keys: ["region"]),
                mode: string(record, keys: ["mode"]),
                archived: boolean(record["archived"]) ?? false
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
                    officialURL: officialURL,
                    categories: ["校内竞赛通知"],
                    tags: [label],
                    description: string(record, keys: ["title"]),
                    metadataSource: PublicDeadlineMetadataSource(
                        name: source,
                        url: officialURL,
                        sourceType: "school_public_notice",
                        authority: nil
                    ),
                    status: "published"
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

    static func fetchData(
        from url: URL,
        allowedScheme: String,
        allowedHost: String,
        configuration suppliedConfiguration: URLSessionConfiguration? = nil
    ) async throws -> Data {
        guard
            url.scheme == allowedScheme,
            url.host == allowedHost,
            url.user == nil,
            url.password == nil
        else {
            throw CalendarDeadlineError.service("DDL 数据源地址不受信任。")
        }
        let configuration = suppliedConfiguration ?? .ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
        let receiver = BoundedPublicDeadlineReceiver(
            maximumBytes: CalendarDeadlineSources.maximumPayloadBytes,
            allowedScheme: allowedScheme,
            allowedHost: allowedHost
        )
        return try await receiver.load(request: request, configuration: configuration)
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

    private static func stringArray(_ object: [String: Any], key: String) -> [String] {
        guard let values = object[key] as? [Any] else { return [] }
        var seen = Set<String>()
        return Array(values.compactMap { value -> String? in
            guard let string = value as? String else { return nil }
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  normalized.count <= 120,
                  seen.insert(normalized).inserted
            else { return nil }
            return normalized
        }.prefix(32))
    }

    private static func metadataSource(_ value: Any?) -> PublicDeadlineMetadataSource? {
        if let name = value as? String {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            return PublicDeadlineMetadataSource(
                name: normalized,
                url: nil,
                sourceType: nil,
                authority: nil
            )
        }
        guard let object = value as? [String: Any],
              let name = string(object, keys: ["name"])
        else { return nil }
        let url = string(object, keys: ["url"]).flatMap(trustedOfficialURL)
        let authority = (object["authority"] as? NSNumber)?.intValue
        return PublicDeadlineMetadataSource(
            name: name,
            url: url,
            sourceType: string(object, keys: ["source_type", "sourceType"]),
            authority: authority
        )
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
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

actor UCloudAssignmentClient: AssignmentDeadlineFetching, TeachingCloudCourseFetching {
    static let shared = UCloudAssignmentClient()
    private struct Cache {
        let account: String
        let fetchedAt: Date
        let items: [AssignmentDeadlineItem]
        var partial = false
    }

    private final class AuthenticatedSession: Sendable {
        let session: URLSession
        let accessToken: String
        let userID: String

        init(session: URLSession, accessToken: String, userID: String) {
            self.session = session
            self.accessToken = accessToken
            self.userID = userID
        }

        deinit { session.invalidateAndCancel() }
    }

    private struct InFlightFetch {
        let id: UInt64
        let revision: UInt64
        let task: Task<[AssignmentDeadlineItem], Error>
    }

    private struct CourseCache {
        let account: String
        let fetchedAt: Date
        let courses: [TeachingCloudCourse]
    }

    private struct CourseFlight {
        let id: UInt64
        let revision: UInt64
        let task: Task<[TeachingCloudCourse], Error>
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
    private static let sessions = AuthenticationSessionCache<AuthenticatedSession>()

    nonisolated static func resetSessions() { sessions.reset() }

    private let credentialStore: any CredentialStoring
    private nonisolated let businessCache: CourseBusinessCacheStorage
    private let fetchAllProvider: (@Sendable (Credentials) async throws -> [AssignmentDeadlineItem])?
    private let fetchCoursesProvider: @Sendable (Credentials) async throws -> [TeachingCloudCourse]
    private let flightSelectionObserver: (@Sendable (Bool) -> Void)?
    private var cache: Cache?
    private var courseCache: CourseCache?
    private var courseFlight: CourseFlight?
    private var activeCredentials: Credentials?
    private var activeScope: CourseBusinessCacheScope?
    private var restoredScope: CourseBusinessCacheScope?
    private var launchWarmAttempted = false
    private var courseAttempted = false
    private var assignmentAttempted = false
    private var coursePersistenceFailed = false
    private var assignmentPersistenceFailed = false
    private var assignmentPartial = false
    private var assignmentRetainingPrevious = false
    private var assignmentPreparations = Set<UInt64>()
    private var courseLastAttemptAt: Date?
    private var assignmentLastAttemptAt: Date?
    private var courseHasLiveResult = false
    private var courseRetainingPrevious = false
    private var inFlightFetches = [String: InFlightFetch]()
    private var revision: UInt64 = 0
    private var nextFlightID: UInt64 = 0

    init(credentialStore: any CredentialStoring = KeychainCredentialStore(), businessCache: CourseBusinessCacheStorage = .shared) {
        self.credentialStore = credentialStore
        self.businessCache = businessCache
        fetchAllProvider = nil
        fetchCoursesProvider = { try await Self.fetchCurrentCourses(credentials: $0) }
        flightSelectionObserver = nil
    }

    init(
        credentialStore: any CredentialStoring,
        fetchAll: @escaping @Sendable (Credentials) async throws -> [AssignmentDeadlineItem],
        fetchCourses: (@Sendable (Credentials) async throws -> [TeachingCloudCourse])? = nil,
        flightSelectionObserver: (@Sendable (Bool) -> Void)? = nil,
        businessCache: CourseBusinessCacheStorage = .shared
    ) {
        self.credentialStore = credentialStore
        self.businessCache = businessCache
        fetchAllProvider = fetchAll
        fetchCoursesProvider = fetchCourses ?? { try await Self.fetchCurrentCourses(credentials: $0) }
        self.flightSelectionObserver = flightSelectionObserver
    }

    func fetch(date: String) async throws -> [AssignmentDeadlineItem] {
        let itemsByDate = try await fetch(dates: [date])
        return itemsByDate[date] ?? []
    }

    func fetchAll(force: Bool = false) async throws -> [AssignmentDeadlineItem] {
        try await accountWideItems(force: force)
    }

    nonisolated func isCourseScopeCurrent(_ scope: CourseBusinessCacheScope) -> Bool {
        businessCache.isCurrent(scope, kind: .courses)
    }

    nonisolated func isAssignmentScopeCurrent(_ scope: CourseBusinessCacheScope) -> Bool {
        businessCache.isCurrent(scope, kind: .assignments)
    }

    func cachedCourseResult() async throws -> TeachingCloudCourseResult? {
        _ = try normalizedCurrentCredentials()
        restoreDiskCacheIfNeeded()
        guard let courseCache, let scope = activeScope, isCourseScopeCurrent(scope) else { return nil }
        return .init(courses: courseCache.courses, fetchedAt: courseCache.fetchedAt, scope: scope,
                     retainingPrevious: courseRetainingPrevious, cachePersistenceFailed: coursePersistenceFailed,
                     ownerAccount: courseCache.account)
    }

    func fetchCourseResult(force: Bool) async throws -> TeachingCloudCourseResult {
        let credentials = try normalizedCurrentCredentials()
        let scope = activeScope, requestRevision = revision
        _ = try await fetchCurrentCourses(force: force)
        guard requestRevision == revision, try normalizedCurrentCredentials() == credentials, activeScope == scope,
              let result = try await cachedCourseResult() else { throw CancellationError() }
        guard result.scope == scope, requestRevision == revision else { throw CancellationError() }
        return result
    }

    func cachedAssignmentResult() async throws -> AssignmentDeadlineResult? {
        _ = try normalizedCurrentCredentials()
        restoreDiskCacheIfNeeded()
        guard let cache, let scope = activeScope, isAssignmentScopeCurrent(scope) else { return nil }
        return .init(items: cache.items, fetchedAt: Self.timestamp(cache.fetchedAt), scope: scope,
                     partial: assignmentPartial || cache.partial, retainingPrevious: assignmentRetainingPrevious,
                     cachePersistenceFailed: assignmentPersistenceFailed)
    }

    func fetchAssignmentResult(force: Bool) async throws -> AssignmentDeadlineResult {
        let credentials = try normalizedCurrentCredentials()
        let scope = activeScope, requestRevision = revision
        _ = try await accountWideItems(force: force)
        guard requestRevision == revision, try normalizedCurrentCredentials() == credentials, activeScope == scope,
              let result = try await cachedAssignmentResult() else { throw CancellationError() }
        guard result.scope == scope, requestRevision == revision else { throw CancellationError() }
        return result
    }

    func fetchAssignmentResult(dates: [String], force: Bool) async throws -> AssignmentDeadlineResult {
        guard dates.allSatisfy({ StrictContractDateParser.date(from: $0) != nil }) else {
            throw CalendarDeadlineError.service("作业日期格式不正确。")
        }
        return try await fetchAssignmentResult(force: force)
    }

    // Root invokes this independently of the selected page. The marker belongs
    // to the canonical actor/credential+epoch owner, not each window or surface.
    func launchWarmOnce() async {
        do {
            _ = try normalizedCurrentCredentials()
            restoreDiskCacheIfNeeded()
            guard !launchWarmAttempted else { return }
            launchWarmAttempted = true
            _ = try await fetchAssignmentResult(force: false)
        } catch { /* Views retain their labelled last-good DTO and timestamps. */ }
    }

    private func restoreDiskCacheIfNeeded() {
        guard let scope = activeScope, restoredScope != scope else { return }
        restoredScope = scope
        if let value = try? businessCache.load(kind: .courses, scope: scope, maximumBytes: Self.maximumAPIBytes,
            as: [TeachingCloudCourse].self), let date = QMplusSnapshotPolicy.utcDate(value.fetchedAt),
           value.payload.count <= Self.maximumCourses,
           Set(value.payload.map(\.id)).count == value.payload.count,
           value.payload.allSatisfy({ !$0.id.isEmpty && $0.teacherNames.allSatisfy { !$0.isEmpty } }),
           isCourseScopeCurrent(scope) {
            courseCache = .init(account: activeCredentials?.account ?? "", fetchedAt: date, courses: value.payload)
            courseRetainingPrevious = true
        }
        if let value = try? businessCache.load(kind: .assignments, scope: scope, maximumBytes: Self.maximumAPIBytes,
            as: [AssignmentDeadlineItem].self), let date = QMplusSnapshotPolicy.utcDate(value.fetchedAt),
           value.payload.count <= Self.maximumAssignments,
           value.payload.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && AssignmentDeadlineParser.isValidCachedDeadline($0.deadline) }),
           isAssignmentScopeCurrent(scope) {
            cache = .init(account: activeCredentials?.account ?? "", fetchedAt: date, items: value.payload, partial: value.partial)
            assignmentPartial = value.partial; assignmentRetainingPrevious = true
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func isRecent(_ date: Date?) -> Bool {
        guard let date else { return false }
        let elapsed = Date().timeIntervalSince(date)
        return elapsed >= 0 && elapsed < cacheLifetime
    }

    private static func withBudget<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: .seconds(120)); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }

    func fetchCurrentCourses(force: Bool = false) async throws -> [TeachingCloudCourse] {
        let credentials = try normalizedCurrentCredentials()
        restoreDiskCacheIfNeeded()
        guard let scope = activeScope else { throw CancellationError() }
        if !force, courseAttempted, courseFlight == nil, let courseCache, courseCache.account == credentials.account,
           Self.isRecent(courseHasLiveResult ? courseCache.fetchedAt : courseLastAttemptAt) {
            return courseCache.courses
        }
        let selected: CourseFlight
        if let courseFlight { selected = courseFlight } else {
            courseAttempted = true
            courseLastAttemptAt = .now
            nextFlightID &+= 1
            let provider = fetchCoursesProvider
            selected = CourseFlight(id: nextFlightID, revision: revision,
                                    task: Task { try await Self.withBudget { try await provider(credentials) } })
            courseFlight = selected
        }
        do {
            let courses = try await selected.task.value
            guard selected.revision == revision,
                  try normalizedCurrentCredentials() == credentials, activeScope == scope,
                  businessCache.isCurrent(scope, kind: .courses) else { throw CancellationError() }
            if courseFlight?.id == selected.id {
                courseCache = CourseCache(account: credentials.account, fetchedAt: .now, courses: courses)
                coursePersistenceFailed = false
                courseHasLiveResult = true; courseRetainingPrevious = false
                if let courseCache {
                    do {
                        try businessCache.save(CourseBusinessCachedValue(schemaVersion: 1, scope: scope,
                            fetchedAt: Self.timestamp(courseCache.fetchedAt), partial: false, payload: courses),
                            kind: .courses, maximumBytes: Self.maximumAPIBytes)
                    } catch {
                        guard businessCache.isCurrent(scope, kind: .courses) else { throw CancellationError() }
                        coursePersistenceFailed = true
                    }
                }
                courseFlight = nil
            }
            return courses
        } catch {
            if courseFlight?.id == selected.id { courseFlight = nil }
            if selected.revision == revision { courseRetainingPrevious = courseCache != nil }
            throw error
        }
    }

    private func normalizedCurrentCredentials() throws -> Credentials {
        let credentials: Credentials
        let scope: CourseBusinessCacheScope
        do { (credentials, scope) = try businessCache.ucloudCredentialBinding(store: credentialStore) }
        catch {
            invalidateAuthentication()
            throw error
        }
        let normalized = Credentials(account: credentials.account.trimmingCharacters(in: .whitespacesAndNewlines),
                                     password: credentials.effectiveTeachingCloudPassword)
        if activeCredentials != normalized || activeScope != scope {
            invalidateAuthentication(); activeCredentials = normalized; activeScope = scope
        }
        return normalized
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

    private func accountWideItems(force: Bool = false) async throws -> [AssignmentDeadlineItem] {
        let normalizedCredentials = try normalizedCurrentCredentials()
        restoreDiskCacheIfNeeded()
        guard let scope = activeScope else { throw CancellationError() }
        let account = normalizedCredentials.account
        let allItems: [AssignmentDeadlineItem]
        if !force, assignmentAttempted, assignmentPreparations.isEmpty, inFlightFetches[account] == nil,
           let cache, cache.account == account, Self.isRecent(assignmentLastAttemptAt) {
            allItems = cache.items
        } else {
            let flight: InFlightFetch
            let isFlightLeader: Bool
            if let existing = inFlightFetches[account], existing.revision == revision {
                flight = existing
                isFlightLeader = false
            } else {
                assignmentAttempted = true
                assignmentLastAttemptAt = .now
                nextFlightID &+= 1
                let flightID = nextFlightID
                assignmentPreparations.insert(flightID)
                defer { assignmentPreparations.remove(flightID) }
                let requestRevision = revision
                let fetchAllProvider = fetchAllProvider
                let currentCourses = fetchAllProvider == nil ? try await fetchCurrentCourses(force: force) : nil
                guard requestRevision == revision else { throw CancellationError() }
                // Course loading suspends this actor; a second caller may have
                // selected the assignment flight before we resume.
                if let existing = inFlightFetches[account], existing.revision == revision {
                    flight = existing
                    isFlightLeader = false
                } else {
                    flight = InFlightFetch(
                        id: flightID,
                        revision: requestRevision,
                        task: Task {
                            try await Self.withBudget {
                                if let fetchAllProvider { return try await fetchAllProvider(normalizedCredentials) }
                                return try await Self.fetchAll(credentials: normalizedCredentials, courses: currentCourses ?? [])
                            }
                        }
                    )
                    inFlightFetches[account] = flight
                    isFlightLeader = true
                }
            }
            flightSelectionObserver?(isFlightLeader)
            do {
                allItems = try await flight.task.value
            } catch {
                if inFlightFetches[account]?.id == flight.id {
                    inFlightFetches.removeValue(forKey: account)
                }
                if let partial = error as? UCloudPartialAssignmentError,
                   activeScope == scope, businessCache.isCurrent(scope, kind: .assignments) {
                    assignmentPartial = true
                    if let cache, cache.account == account {
                        assignmentRetainingPrevious = true
                        return cache.items
                    }
                    let next = Cache(account: account, fetchedAt: .now, items: partial.items, partial: true)
                    cache = next
                    do {
                        try businessCache.save(CourseBusinessCachedValue(schemaVersion: 1, scope: scope,
                            fetchedAt: Self.timestamp(next.fetchedAt), partial: true, payload: next.items),
                            kind: .assignments, maximumBytes: Self.maximumAPIBytes)
                    } catch {
                        guard businessCache.isCurrent(scope, kind: .assignments) else { throw CancellationError() }
                        assignmentPersistenceFailed = true
                    }
                    return next.items
                }
                throw error
            }
            let (latest, latestScope) = try businessCache.ucloudCredentialBinding(store: credentialStore)
            guard revision == flight.revision,
                  latest.account.trimmingCharacters(in: .whitespacesAndNewlines) == account,
                  latest.effectiveTeachingCloudPassword == normalizedCredentials.password,
                  latestScope == scope
            else {
                throw CancellationError()
            }
            if inFlightFetches[account]?.id == flight.id {
                cache = Cache(account: account, fetchedAt: Date(), items: allItems)
                assignmentPartial = false; assignmentRetainingPrevious = false; assignmentPersistenceFailed = false
                if let cache {
                    do {
                        try businessCache.save(CourseBusinessCachedValue(schemaVersion: 1, scope: scope,
                            fetchedAt: Self.timestamp(cache.fetchedAt), partial: cache.partial, payload: cache.items),
                            kind: .assignments, maximumBytes: Self.maximumAPIBytes)
                    } catch {
                        guard businessCache.isCurrent(scope, kind: .assignments) else { throw CancellationError() }
                        assignmentPersistenceFailed = true
                    }
                }
                inFlightFetches.removeValue(forKey: account)
            }
        }
        return allItems
    }

    func reset() async {
        invalidateAuthentication()
    }

    private func invalidateAuthentication() {
        Self.sessions.reset()
        revision &+= 1
        cache = nil
        courseCache = nil
        courseFlight?.task.cancel()
        courseFlight = nil
        activeCredentials = nil
        activeScope = nil; restoredScope = nil
        launchWarmAttempted = false; courseAttempted = false; assignmentAttempted = false
        coursePersistenceFailed = false; assignmentPersistenceFailed = false
        assignmentPartial = false; assignmentRetainingPrevious = false
        assignmentPreparations.removeAll()
        courseLastAttemptAt = nil; assignmentLastAttemptAt = nil
        courseHasLiveResult = false; courseRetainingPrevious = false
        let invalidated = inFlightFetches.values.map(\.task)
        inFlightFetches.removeAll()
        invalidated.forEach { $0.cancel() }
    }

    private static func fetchAll(credentials: Credentials, courses: [TeachingCloudCourse]) async throws -> [AssignmentDeadlineItem] {
        try await sessions.perform(
            key: AuthenticationSessionPolicy.key(account: credentials.account, password: credentials.password),
            login: { try await authenticate(credentials: credentials) },
            operation: { try await fetchAll(authenticated: $0, courses: courses) }
        )
    }

    private static func fetchCurrentCourses(credentials: Credentials) async throws -> [TeachingCloudCourse] {
        try await sessions.perform(
            key: AuthenticationSessionPolicy.key(account: credentials.account, password: credentials.password),
            login: { try await authenticate(credentials: credentials) },
            operation: { try await fetchCurrentCourses(authenticated: $0) }
        )
    }

    private static func fetchCurrentCourses(authenticated: AuthenticatedSession) async throws -> [TeachingCloudCourse] {
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
        return parseCurrentCourses(courseRoot)
    }

    static func parseCurrentCourses(_ root: Any) -> [TeachingCloudCourse] {
        var seen = Set<String>()
        return courseRecords(root).prefix(maximumCourses).compactMap { course in
            guard seen.insert(course.id).inserted else { return nil }
            return TeachingCloudCourse(id: course.id, name: course.name, teacherNames: course.teacherNames)
        }
    }

    private static func fetchAll(authenticated: AuthenticatedSession, courses: [TeachingCloudCourse]) async throws -> [AssignmentDeadlineItem] {
        var allItems = [AssignmentDeadlineItem]()
        var successfulCourseRequests = 0
        var firstCourseError: Error?
        for course in courses {
            try Task.checkCancellation()
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
                    courseNameOverride: course.name,
                    courseIDOverride: course.id
                ))
            } catch AuthenticationSessionError.expired {
                throw AuthenticationSessionError.expired
            } catch {
                if firstCourseError == nil { firstCourseError = error }
            }
            if allItems.count >= maximumAssignments { break }
        }
        if !courses.isEmpty, successfulCourseRequests == 0 {
            throw firstCourseError
                ?? CalendarDeadlineError.service("教学云课程作业接口暂时不可用。")
        }

        do {
            let undoneRoot = try await getAPI(
            path: "/ykt-site/site/student/undone",
            queryItems: [URLQueryItem(name: "userId", value: authenticated.userID)],
            authenticated: authenticated
            )
            allItems.append(contentsOf: AssignmentDeadlineParser.parseAll(
                root: undoneRoot,
                courseNameOverride: nil
            ))
        } catch AuthenticationSessionError.expired {
            throw AuthenticationSessionError.expired
        } catch {
            // The supplementary undone feed is optional. Other request failures
            // keep the original course-list behavior and never trigger login.
        }
        let merged = merge(allItems)
        if firstCourseError != nil { throw UCloudPartialAssignmentError(items: merged) }
        return merged
    }

    private static func authenticate(credentials: Credentials) async throws -> AuthenticationSession<AuthenticatedSession> {
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
            return AuthenticationSession(value: AuthenticatedSession(
                session: session,
                accessToken: accessToken,
                userID: userID
            ), expiresAt: AuthenticationSessionPolicy.expiresAt(token: accessToken, payload: tokenObject))
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
        try AuthenticationSessionPolicy.checkExpiration(data: data, response: response)
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
        SJDFormURLEncoder.data(Dictionary(uniqueKeysWithValues: fields))
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

    private static func courseRecords(_ root: Any) -> [(id: String, name: String?, teacherNames: [String])] {
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
            var seenTeachers = Set<String>()
            let teachers = (record["teachers"] as? [[String: Any]] ?? []).compactMap { teacher -> String? in
                guard let rawName = teacher["name"] as? String,
                      let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                      seenTeachers.insert(name).inserted else { return nil }
                return name
            }
            return (id, name, teachers)
        }
    }

    private static func merge(_ items: [AssignmentDeadlineItem]) -> [AssignmentDeadlineItem] {
        var resultByKey = [String: AssignmentDeadlineItem]()
        for item in items.prefix(maximumAssignments) {
            let key = "\(item.id)\u{1F}\(item.deadline)"
            if let existing = resultByKey[key] {
                if existing.courseName == nil, item.courseName != nil {
                    resultByKey[key] = AssignmentDeadlineItem(id: item.id, title: item.title, courseName: item.courseName,
                                                             deadline: item.deadline, status: item.status,
                                                             courseID: item.courseID ?? existing.courseID)
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
    static func isValidCachedDeadline(_ value: String) -> Bool { parseAssignmentDate(value) != nil }
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
        courseNameOverride: String?,
        courseIDOverride: String? = nil
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
                status: assignmentStatus(record["assignmentStatus"]),
                courseID: courseIDOverride ?? string(record, keys: ["siteId", "courseId"])
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

private final class BoundedPublicDeadlineReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private let allowedScheme: String
    private let allowedHost: String
    private let lock = NSLock()
    private var received = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var finished = false
    private var cancelled = false

    init(maximumBytes: Int, allowedScheme: String, allowedHost: String) {
        self.maximumBytes = maximumBytes
        self.allowedScheme = allowedScheme
        self.allowedHost = allowedHost
    }

    func load(request: URLRequest, configuration: URLSessionConfiguration) async throws -> Data {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled else {
                    lock.unlock()
                    session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.session = session
                self.continuation = continuation
                let task = session.dataTask(with: request)
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let hasPendingContinuation = continuation != nil && !finished
        lock.unlock()
        if hasPendingContinuation { finish(.failure(CancellationError())) }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              http.url?.scheme == allowedScheme,
              http.url?.host == allowedHost
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            finish(.failure(CalendarDeadlineError.service("DDL 数据源返回错误，HTTP \(status)。")))
            completionHandler(.cancel)
            return
        }
        guard http.expectedContentLength <= 0
            || http.expectedContentLength <= Int64(maximumBytes)
        else {
            finish(.failure(CalendarDeadlineError.service("DDL 数据响应过大。")))
            completionHandler(.cancel)
            return
        }
        lock.lock()
        self.response = http
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let isTooLarge = data.count > maximumBytes - received.count
        if !finished && !isTooLarge { received.append(data) }
        lock.unlock()
        if isTooLarge {
            finish(.failure(CalendarDeadlineError.service("DDL 数据响应过大。")))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let validResponse = response != nil
        let data = received
        lock.unlock()
        if validResponse {
            finish(.success(data))
        } else {
            finish(.failure(CalendarDeadlineError.service("DDL 数据源响应不正确。")))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}

private enum SampleCalendarDeadlineBuilder {
    static func publicSnapshots(dates: [String]) -> [String: PublicDeadlineSnapshot] {
        Dictionary(uniqueKeysWithValues: dates.map { date in
            (date, PublicDeadlineSnapshot(
                date: date,
                items: [
                    PublicDeadlineItem(
                        id: "sample-competition", name: "全国大学生示例竞赛",
                        kind: .competition, source: .contestDDL,
                        deadline: "\(date)T23:59:00+08:00", organizer: "示例组委会", officialURL: nil
                    ),
                    PublicDeadlineItem(
                        id: "sample-school-notice", name: "校内示例竞赛通知",
                        kind: .competition, source: .schoolNotice,
                        deadline: "\(date)T18:00:00+08:00", organizer: "学校公开通知页", officialURL: nil
                    ),
                    PublicDeadlineItem(
                        id: "sample-summer-camp", name: "示例高校夏令营",
                        kind: .summerCamp, source: .contestDDL,
                        deadline: "\(date)T20:00:00+08:00", organizer: "示例高校", officialURL: nil
                    ),
                    PublicDeadlineItem(
                        id: "sample-hackathon", name: "示例校园黑客松",
                        kind: .hackathon, source: .contestDDL,
                        deadline: "\(date)T21:00:00+08:00", organizer: "示例社区", officialURL: nil
                    ),
                    PublicDeadlineItem(
                        id: "sample-conference", name: "示例学术会议",
                        kind: .conference, source: .contestDDL,
                        deadline: "\(date)T22:00:00+08:00", organizer: "示例学术组织", officialURL: nil
                    ),
                ],
                source: CalendarDeadlineSources.primary,
                usedBackup: false
            ))
        })
    }

    static func assignments(dates: [String]) -> [String: [AssignmentDeadlineItem]] {
        Dictionary(uniqueKeysWithValues: dates.map { date in
            (date, [AssignmentDeadlineItem(
                id: "sample-assignment", title: "示例课程作业", courseName: "示例课程",
                deadline: "\(date) 23:59:00", status: "未提交", courseID: "sample-course"
            )])
        })
    }
}

@MainActor
final class CalendarDeadlineStore: ObservableObject {
    @Published private(set) var publicByDate = [String: PublicDeadlineSnapshot]() {
        didSet { publicDataRevision &+= 1 }
    }
    private(set) var publicDataRevision: UInt64 = 0
    @Published private(set) var publicErrors = [String: String]()
    @Published private(set) var loadingPublicDates = Set<String>()
    @Published private(set) var customByDate = [String: PublicDeadlineSnapshot]()
    @Published private(set) var customErrors = [String: String]()
    @Published private(set) var loadingCustomDates = Set<String>()
    @Published private(set) var customSourceMetadata: CustomDeadlineFeedMetadata?
    @Published private(set) var assignmentsByDate = [String: [AssignmentDeadlineItem]]()
    @Published private(set) var assignmentUnavailableByDate = [String: String]()
    @Published private(set) var loadingAssignmentDates = Set<String>()
    @Published private(set) var assignmentQueryItems: [AssignmentDeadlineItem]?
    @Published private(set) var assignmentQueryError = ""
    @Published private(set) var isLoadingAssignmentQuery = false
    @Published private(set) var assignmentQueryFetchedAt: String?
    @Published private(set) var isRefreshingAssignmentQuery = false
    @Published private(set) var isPartialAssignmentQuery = false
    @Published private(set) var isRetainingPreviousAssignments = false
    private var assignmentQueryAttempted = false
    @Published private(set) var isLoadingPublicFeed = false
    @Published private(set) var publicFeedError = ""

    private let client: any PublicDeadlineFetching
    private let assignmentClient: any AssignmentDeadlineFetching
    private let customClientFactory: @Sendable (URL) throws -> any CustomDeadlineFeedFetching
    private var customClient: (any CustomDeadlineFeedFetching)?
    private var customSourceURL: URL?
    private var customRevision: UInt64 = 0
    private var assignmentRevision: UInt64 = 0
    private var assignmentResetTask: Task<Void, Never>?
    private var publicPrewarmFlight: (
        id: UInt64,
        task: Task<[String: PublicDeadlineSnapshot], Error>
    )?
    private var nextPublicPrewarmFlightID: UInt64 = 0
    private var publicPrewarmAttempted = false
    private var publicPrewarmError: String?

    init(
        client: any PublicDeadlineFetching = PublicDeadlineClient(),
        assignmentClient: any AssignmentDeadlineFetching = UCloudAssignmentClient.shared,
        customClientFactory: @escaping @Sendable (URL) throws -> any CustomDeadlineFeedFetching = {
            try CustomDeadlineFeedClient(sourceURL: $0)
        }
    ) {
        self.client = client
        self.assignmentClient = assignmentClient
        self.customClientFactory = customClientFactory
    }

    func prewarmPublicIfNeeded(
        publicDeadlinesEnabled: Bool,
        sampleMode: Bool,
        force: Bool = false
    ) async {
        guard publicDeadlinesEnabled, !sampleMode else { return }
        publicPrewarmAttempted = true

        let flight: (id: UInt64, task: Task<[String: PublicDeadlineSnapshot], Error>)
        if let publicPrewarmFlight {
            flight = publicPrewarmFlight
        } else {
            isLoadingPublicFeed = true
            publicFeedError = ""
            nextPublicPrewarmFlightID &+= 1
            let client = client
            let force = force
            flight = (
                id: nextPublicPrewarmFlightID,
                task: Task {
                    if force { return try await client.refresh() }
                    return try await client.prewarm()
                }
            )
            publicPrewarmFlight = flight
        }

        do {
            let snapshots = try await flight.task.value
            guard publicPrewarmFlight?.id == flight.id else { return }
            if force {
                if publicByDate != snapshots { publicByDate = snapshots }
            } else {
                var updated = publicByDate
                for (date, snapshot) in snapshots {
                    updated[date] = snapshot
                }
                if publicByDate != updated { publicByDate = updated }
            }
            publicPrewarmError = nil
            publicFeedError = ""
            publicPrewarmFlight = nil
            isLoadingPublicFeed = false
        } catch {
            if publicPrewarmFlight?.id == flight.id {
                // Startup prewarming is deliberately silent in global UI.
                // Visible calendar tasks reuse this error instead of starting
                // network work during paging; scene activation or a settings
                // off -> on transition owns the next refresh attempt.
                publicPrewarmError = error.localizedDescription
                publicFeedError = error.localizedDescription
                publicPrewarmFlight = nil
                isLoadingPublicFeed = false
            }
        }
    }

    func loadPublicQuery(sampleMode: Bool, force: Bool = false) async {
        if sampleMode {
            let calendar = Calendar.shanghai
            let dates = (0 ..< 7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: .now)
            }.map { StrictContractDateParser.string(from: $0) }
            await loadPublic(dates: dates, sampleMode: true)
            return
        }
        await prewarmPublicIfNeeded(
            publicDeadlinesEnabled: true,
            sampleMode: false,
            force: force
        )
    }

    func loadPublic(date: String, sampleMode: Bool, force: Bool = false) async {
        await loadPublic(dates: [date], sampleMode: sampleMode, force: force)
    }

    func loadPublic(dates: [String], sampleMode: Bool, force: Bool = false) async {
        if !sampleMode,
           !force,
           publicPrewarmAttempted,
           publicByDate.isEmpty,
           let publicPrewarmError {
            var updatedErrors = publicErrors
            dates.forEach { updatedErrors[$0] = publicPrewarmError }
            if publicErrors != updatedErrors { publicErrors = updatedErrors }
            return
        }
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
            let generated = await Task.detached(priority: .utility) {
                SampleCalendarDeadlineBuilder.publicSnapshots(dates: requestedDates)
            }.value
            guard !Task.isCancelled else { return }
            var updated = publicByDate
            generated.forEach { updated[$0.key] = $0.value }
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
        includesPublicDeadlines: Bool,
        customSourceURL: URL? = nil
    ) async {
        let requestedDates = Array(Set(dates)).sorted()
        guard !requestedDates.isEmpty else { return }
        if includesPublicDeadlines {
            await loadPublic(dates: requestedDates, sampleMode: sampleMode)
        }
        if let customSourceURL, !sampleMode {
            await loadCustom(dates: requestedDates, sourceURL: customSourceURL)
        } else if customSourceURL == nil {
            clearCustomSource()
        }
        guard !Task.isCancelled else { return }
        await loadAssignments(dates: requestedDates, sampleMode: sampleMode)
    }

    func publicItems(for date: String) -> [PublicDeadlineItem] {
        PublicDeadlineClient.merge([
            publicByDate[date]?.items ?? [],
            customByDate[date]?.items ?? [],
        ])
    }

    func validateCustomFeed(sourceURL: URL) async throws -> CustomDeadlineFeedMetadata {
        try configureCustomSource(sourceURL)
        guard let customClient else {
            throw CalendarDeadlineError.service("自定义日程客户端未初始化。")
        }
        let revision = customRevision
        let metadata = try await customClient.validateFeed()
        guard revision == customRevision, self.customSourceURL == sourceURL else {
            throw CancellationError()
        }
        customSourceMetadata = metadata
        return metadata
    }

    func prewarmCustomIfNeeded(
        sourceURL: URL,
        dates: [String],
        sampleMode: Bool
    ) async {
        guard !sampleMode, !dates.isEmpty else { return }
        do {
            try configureCustomSource(sourceURL)
            guard let customClient else { return }
            let revision = customRevision
            let snapshots = try await customClient.prewarm(dates: dates)
            guard revision == customRevision, self.customSourceURL == sourceURL else { return }
            customByDate = snapshots
            customSourceMetadata = try? await customClient.validateFeed()
            customErrors.removeAll()
        } catch {
            guard self.customSourceURL == sourceURL else { return }
            customErrors["source"] = error.localizedDescription
        }
    }

    func loadCustom(
        dates: [String],
        sourceURL: URL,
        force: Bool = false
    ) async {
        do {
            try configureCustomSource(sourceURL)
        } catch {
            customErrors["source"] = error.localizedDescription
            return
        }
        guard let customClient else { return }
        if !force, let prewarmError = customErrors["source"], customByDate.isEmpty {
            var updatedErrors = customErrors
            dates.forEach { updatedErrors[$0] = prewarmError }
            if customErrors != updatedErrors { customErrors = updatedErrors }
            return
        }
        let requestedDates = Array(Set(dates)).sorted().filter { date in
            (force || customByDate[date] == nil) && !loadingCustomDates.contains(date)
        }
        guard !requestedDates.isEmpty else { return }
        let revision = customRevision
        loadingCustomDates.formUnion(requestedDates)
        var clearedErrors = customErrors
        requestedDates.forEach { clearedErrors.removeValue(forKey: $0) }
        if customErrors != clearedErrors { customErrors = clearedErrors }
        defer {
            if revision == customRevision {
                loadingCustomDates.subtract(requestedDates)
            }
        }
        do {
            let rangeOwner = Task { try await customClient.fetch(dates: requestedDates) }
            let snapshots = try await rangeOwner.value
            guard revision == customRevision, self.customSourceURL == sourceURL else { return }
            var updated = customByDate
            for date in requestedDates {
                updated[date] = snapshots[date] ?? PublicDeadlineSnapshot(
                    date: date,
                    items: [],
                    source: sourceURL,
                    usedBackup: false
                )
            }
            customByDate = updated
            if customSourceMetadata == nil {
                customSourceMetadata = try? await customClient.validateFeed()
            }
        } catch {
            guard revision == customRevision else { return }
            var updatedErrors = customErrors
            requestedDates.forEach { updatedErrors[$0] = error.localizedDescription }
            customErrors = updatedErrors
        }
    }

    func clearCustomSource() {
        guard customSourceURL != nil || !customByDate.isEmpty || !customErrors.isEmpty else { return }
        customRevision &+= 1
        customClient = nil
        customSourceURL = nil
        customByDate.removeAll()
        customErrors.removeAll()
        loadingCustomDates.removeAll()
        customSourceMetadata = nil
    }

    private func configureCustomSource(_ sourceURL: URL) throws {
        guard customSourceURL != sourceURL else { return }
        let client = try customClientFactory(sourceURL)
        customRevision &+= 1
        customClient = client
        customSourceURL = sourceURL
        customByDate.removeAll()
        customErrors.removeAll()
        loadingCustomDates.removeAll()
        customSourceMetadata = nil
    }

    func loadAssignments(date: String, sampleMode: Bool, force: Bool = false) async {
        await loadAssignments(dates: [date], sampleMode: sampleMode, force: force)
    }

    func restoreCachedAssignments(sampleMode: Bool) async {
        guard !sampleMode else { return }
        let revision = assignmentRevision
        await assignmentResetTask?.value
        guard revision == assignmentRevision, let result = try? await assignmentClient.cachedAssignmentResult(),
              revision == assignmentRevision, !Task.isCancelled, acceptsAssignmentResult(result) else { return }
        installAssignmentResult(result, dates: [], fromCache: true)
    }

    private func acceptsAssignmentResult(_ result: AssignmentDeadlineResult) -> Bool {
        result.scope.map { assignmentClient.isAssignmentScopeCurrent($0) } ?? true
    }

    private func installAssignmentResult(_ result: AssignmentDeadlineResult, dates: [String], fromCache: Bool) {
        let grouped = Dictionary(grouping: result.items, by: { String($0.deadline.prefix(10)) })
        isPartialAssignmentQuery = result.partial
        isRetainingPreviousAssignments = result.retainingPrevious
        if result.coversAllCourses {
            assignmentQueryItems = result.items
            assignmentQueryFetchedAt = result.fetchedAt
        }
        let keys = result.coversAllCourses ? Set(assignmentsByDate.keys).union(grouped.keys).union(dates) : Set(dates)
        var next = assignmentsByDate
        var errors = assignmentUnavailableByDate
        for date in keys {
            if result.partial, grouped[date] == nil, next[date] != nil { continue }
            next[date] = grouped[date] ?? []
            if result.partial {
                errors[date] = "以下内容仅来自本机已同步缓存；未列出不代表已经提交或没有作业。"
            } else { errors.removeValue(forKey: date) }
        }
        assignmentsByDate = next; assignmentUnavailableByDate = errors
        assignmentQueryError = result.cachePersistenceFailed
            ? "本次课程数据已读取，但本地缓存未更新。重启后可能显示此前缓存。"
            : (result.partial ? "以下内容仅来自本机已同步缓存；未列出不代表已经提交或没有作业。" : "")
    }

    func loadAssignments(dates: [String], sampleMode: Bool, force: Bool = false) async {
        let revisionBeforeReset = assignmentRevision
        await assignmentResetTask?.value
        guard revisionBeforeReset == assignmentRevision else { return }
        if !sampleMode { await restoreCachedAssignments(sampleMode: false) }
        guard revisionBeforeReset == assignmentRevision else { return }
        let requestedDates = Array(Set(dates)).sorted().filter { date in
            (force || assignmentsByDate[date] == nil) && !loadingAssignmentDates.contains(date)
        }
        guard !requestedDates.isEmpty else { return }
        if sampleMode {
            let generated = await Task.detached(priority: .utility) {
                SampleCalendarDeadlineBuilder.assignments(dates: requestedDates)
            }.value
            guard !Task.isCancelled, revisionBeforeReset == assignmentRevision else { return }
            var updatedAssignments = assignmentsByDate
            var updatedUnavailable = assignmentUnavailableByDate
            for date in requestedDates {
                updatedAssignments[date] = generated[date]
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
            let result = try await assignmentClient.fetchAssignmentResult(dates: requestedDates, force: force)
            guard assignmentRevision == requestRevision, acceptsAssignmentResult(result) else { return }
            installAssignmentResult(result, dates: requestedDates, fromCache: false)
        } catch {
            guard assignmentRevision == requestRevision else { return }
            var updatedAssignments = assignmentsByDate
            var updatedUnavailable = assignmentUnavailableByDate
            for date in requestedDates {
                if updatedAssignments[date] == nil { updatedAssignments[date] = [] }
                updatedUnavailable[date] = error.localizedDescription
            }
            assignmentsByDate = updatedAssignments
            assignmentUnavailableByDate = updatedUnavailable
        }
    }

    func loadAssignmentQuery(sampleMode: Bool, force: Bool = false) async {
        let beforeReset = assignmentRevision
        await assignmentResetTask?.value
        guard beforeReset == assignmentRevision, !isLoadingAssignmentQuery,
              !isRefreshingAssignmentQuery,
              force || !assignmentQueryAttempted else { return }
        if !sampleMode { await restoreCachedAssignments(sampleMode: false) }
        guard beforeReset == assignmentRevision, !isRefreshingAssignmentQuery else { return }
        assignmentQueryAttempted = true
        if sampleMode {
            let today = StrictContractDateParser.string(from: .now)
            assignmentQueryItems = SampleCalendarDeadlineBuilder.assignments(dates: [today])[today] ?? []
            assignmentQueryFetchedAt = SJDClassroomClient.timestamp()
            assignmentQueryError = ""
            return
        }
        let requestRevision = assignmentRevision
        isRefreshingAssignmentQuery = true
        isLoadingAssignmentQuery = assignmentQueryItems == nil
        assignmentQueryError = ""
        defer { if requestRevision == assignmentRevision { isLoadingAssignmentQuery = false; isRefreshingAssignmentQuery = false } }
        do {
            let result = try await assignmentClient.fetchAssignmentResult(force: force)
            guard requestRevision == assignmentRevision, acceptsAssignmentResult(result) else { return }
            installAssignmentResult(result, dates: [], fromCache: false)
        } catch {
            guard requestRevision == assignmentRevision else { return }
            assignmentQueryError = "课程作业获取失败，请检查个人账户中的教学云密码或稍后重试。"
            isRetainingPreviousAssignments = assignmentQueryItems != nil
        }
    }

    func clearAssignments() {
        assignmentRevision &+= 1
        assignmentQueryItems = nil
        assignmentQueryError = ""
        assignmentQueryFetchedAt = nil
        assignmentQueryAttempted = false
        isLoadingAssignmentQuery = false
        isRefreshingAssignmentQuery = false; isPartialAssignmentQuery = false; isRetainingPreviousAssignments = false
        assignmentsByDate.removeAll()
        assignmentUnavailableByDate.removeAll()
        loadingAssignmentDates.removeAll()
        let previousReset = assignmentResetTask
        assignmentResetTask = Task {
            await previousReset?.value
            await assignmentClient.reset()
        }
    }
}
