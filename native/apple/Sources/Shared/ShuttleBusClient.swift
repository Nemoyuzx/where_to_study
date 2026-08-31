import Foundation

enum ShuttleBusSources {
    static let api = URL(string: "https://where-to-study.cn/api/shuttle-bus")!
    static let sourcePage = URL(string: "https://hq.bupt.edu.cn/tzgg.htm")!
    static let maximumPayloadBytes = 4 * 1024 * 1024
}

enum ShuttleBusError: LocalizedError, Equatable, Sendable {
    case service(String)

    var errorDescription: String? {
        switch self {
        case let .service(message): message
        }
    }
}

struct ShuttleBusService: Equatable, Sendable {
    let vehicle: String
    let count: Int
}

struct ShuttleBusDeparture: Identifiable, Equatable, Sendable {
    let departureTime: String
    let service: ShuttleBusService

    var id: String { departureTime }
}

struct ShuttleBusPeriod: Hashable, Sendable {
    let label: String
    let startDate: String?
    let endDate: String?

    var id: String {
        [startDate ?? "unknown", endDate ?? "open", label].joined(separator: ":")
    }

    func contains(_ date: String) -> Bool {
        guard let startDate, startDate <= date else { return false }
        return endDate.map { date <= $0 } ?? true
    }
}

struct ShuttleBusSchedule: Identifiable, Equatable, Sendable {
    let period: ShuttleBusPeriod
    let from: String
    let to: String
    let parseStatus: String
    let rows: [ShuttleBusScheduleRow]

    var id: String { "\(period.id):\(from):\(to)" }
}

struct ShuttleBusScheduleRow: Equatable, Sendable {
    let departureTime: String
    let services: [String: ShuttleBusService]
}

struct ShuttleBusStop: Identifiable, Equatable, Sendable {
    let campus: String
    let location: String

    var id: String { campus }
}

struct ShuttleBusNotice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let publishedAt: String
    let sourceURL: URL?
    let kind: String
    let notes: [String]
    let stops: [ShuttleBusStop]
    let parseStatus: String
    let schedules: [ShuttleBusSchedule]
}

struct ShuttleBusSnapshot: Equatable, Sendable {
    let generatedAt: String
    let status: String
    let sourceName: String
    let sourcePage: URL
    let lastParsedNoticeID: String?
    let notices: [ShuttleBusNotice]
}

protocol ShuttleBusFetching: Sendable {
    func fetch() async throws -> ShuttleBusSnapshot
}

struct ShuttleBusClient: ShuttleBusFetching {
    typealias DataLoader = @Sendable () async throws -> Data

    private let dataLoader: DataLoader

    init() {
        dataLoader = Self.loadLiveData
    }

    init(dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
    }

    func fetch() async throws -> ShuttleBusSnapshot {
        try Self.parse(data: try await dataLoader())
    }

    static func parse(data: Data) throws -> ShuttleBusSnapshot {
        guard data.count <= ShuttleBusSources.maximumPayloadBytes else {
            throw ShuttleBusError.service("班车数据响应过大。")
        }
        let payload: ShuttleBusPayloadDTO
        do {
            payload = try JSONDecoder().decode(ShuttleBusPayloadDTO.self, from: data)
        } catch {
            throw ShuttleBusError.service("班车数据格式不正确。")
        }
        guard payload.schemaVersion == "1.0", payload.items.count <= 50 else {
            throw ShuttleBusError.service("班车数据接口版本或数量不受支持。")
        }
        guard parseISO8601(payload.generatedAt) != nil else {
            throw ShuttleBusError.service("班车数据更新时间不正确。")
        }

        let notices = payload.items.compactMap(validatedNotice).sorted {
            ($0.publishedAt, $0.id) > ($1.publishedAt, $1.id)
        }
        guard !notices.isEmpty else {
            throw ShuttleBusError.service("班车接口暂未返回有效通知。")
        }
        let pageURL = trustedHTTPSURL(payload.source.pageURL, host: "hq.bupt.edu.cn")
            ?? ShuttleBusSources.sourcePage
        return ShuttleBusSnapshot(
            generatedAt: payload.generatedAt,
            status: payload.status,
            sourceName: payload.source.name,
            sourcePage: pageURL,
            lastParsedNoticeID: payload.lastParsedNoticeID,
            notices: notices
        )
    }

    private static func validatedNotice(_ value: ShuttleBusNoticeDTO) -> ShuttleBusNotice? {
        guard !value.id.isEmpty,
              StrictContractDateParser.date(from: value.publishedAt) != nil,
              !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.schedules.count <= 16
        else { return nil }

        let schedules = value.schedules.compactMap(validatedSchedule)
        return ShuttleBusNotice(
            id: value.id,
            title: value.title,
            publishedAt: value.publishedAt,
            sourceURL: trustedHTTPSURL(value.sourceURL, host: "hq.bupt.edu.cn"),
            kind: value.kind,
            notes: Array(value.notes.filter { !$0.isEmpty }.prefix(12)),
            stops: Array(value.stops.compactMap { stop in
                guard !stop.campus.isEmpty, !stop.location.isEmpty else { return nil }
                return ShuttleBusStop(campus: stop.campus, location: stop.location)
            }.prefix(8)),
            parseStatus: value.parseStatus,
            schedules: schedules
        )
    }

    private static func validatedSchedule(_ value: ShuttleBusScheduleDTO) -> ShuttleBusSchedule? {
        guard value.parseStatus == "parsed",
              !value.from.isEmpty,
              !value.to.isEmpty,
              value.rows.count <= 64
        else { return nil }
        if let startDate = value.period.startDate,
           StrictContractDateParser.date(from: startDate) == nil { return nil }
        if let endDate = value.period.endDate,
           StrictContractDateParser.date(from: endDate) == nil { return nil }
        let rows = value.rows.compactMap { row -> ShuttleBusScheduleRow? in
            guard validTime(row.departureTime) else { return nil }
            var services = [String: ShuttleBusService]()
            for (key, wrappedService) in row.services {
                guard ShuttleBusTodayLogic.weekdayKeys.contains(key),
                      let service = wrappedService,
                      !service.vehicle.isEmpty,
                      (1 ... 20).contains(service.count)
                else { continue }
                services[key] = ShuttleBusService(vehicle: service.vehicle, count: service.count)
            }
            return ShuttleBusScheduleRow(
                departureTime: row.departureTime,
                services: services
            )
        }.sorted { $0.departureTime < $1.departureTime }
        guard !rows.isEmpty else { return nil }
        return ShuttleBusSchedule(
            period: ShuttleBusPeriod(
                label: value.period.label,
                startDate: value.period.startDate,
                endDate: value.period.endDate
            ),
            from: value.from,
            to: value.to,
            parseStatus: value.parseStatus,
            rows: rows
        )
    }

    private static func trustedHTTPSURL(_ value: String?, host: String) -> URL? {
        guard let value,
              let url = URL(string: value),
              url.scheme == "https",
              url.host == host,
              url.user == nil,
              url.password == nil
        else { return nil }
        return url
    }

    private static func validTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2,
              parts[1].count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else { return false }
        return (0 ... 23).contains(hour) && (0 ... 59).contains(minute)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func loadLiveData() async throws -> Data {
        var request = URLRequest(url: ShuttleBusSources.api)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(
            configuration: configuration,
            delegate: ShuttleBusRedirectDelegate(),
            delegateQueue: nil
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.scheme == "https",
              http.url?.host == "where-to-study.cn"
        else {
            throw ShuttleBusError.service("班车接口暂时不可用。")
        }
        guard data.count <= ShuttleBusSources.maximumPayloadBytes else {
            throw ShuttleBusError.service("班车数据响应过大。")
        }
        return data
    }
}

final class ShuttleBusRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

enum ShuttleBusTodayLogic {
    static let weekdayKeys = Set([
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ])

    static func weekdayKey(for date: Date, calendar: Calendar = .shanghai) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: "sunday"
        case 2: "monday"
        case 3: "tuesday"
        case 4: "wednesday"
        case 5: "thursday"
        case 6: "friday"
        default: "saturday"
        }
    }

    static func scheduleNotice(in snapshot: ShuttleBusSnapshot) -> ShuttleBusNotice? {
        if let latest = snapshot.notices.first,
           latest.schedules.contains(where: { !$0.rows.isEmpty }) {
            return latest
        }
        guard let id = snapshot.lastParsedNoticeID else { return nil }
        return snapshot.notices.first { $0.id == id }
    }

    static func activeSchedules(
        in snapshot: ShuttleBusSnapshot,
        on date: Date,
        calendar: Calendar = .shanghai
    ) -> [ShuttleBusSchedule] {
        let dateString = StrictContractDateParser.string(from: date, calendar: calendar)
        guard let notice = scheduleNotice(in: snapshot) else { return [] }
        return notice.schedules.filter { $0.period.contains(dateString) }
    }

    static func departures(
        for schedule: ShuttleBusSchedule,
        on date: Date,
        calendar: Calendar = .shanghai
    ) -> [ShuttleBusDeparture] {
        let weekday = weekdayKey(for: date, calendar: calendar)
        return schedule.rows.compactMap { row in
            guard let service = row.services[weekday] else { return nil }
            return ShuttleBusDeparture(departureTime: row.departureTime, service: service)
        }
    }
}

@MainActor
final class ShuttleBusStore: ObservableObject {
    @Published private(set) var snapshot: ShuttleBusSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage = ""

    private let client: any ShuttleBusFetching

    init(client: any ShuttleBusFetching = ShuttleBusClient()) {
        self.client = client
    }

    func load(force: Bool = false, sampleMode: Bool = false) async {
        guard !isLoading, force || snapshot == nil else { return }
        if sampleMode {
            snapshot = ShuttleBusSampleData.snapshot()
            errorMessage = ""
            return
        }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            snapshot = try await client.fetch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ShuttleBusSampleData {
    static func snapshot(now: Date = .now, calendar: Calendar = .shanghai) -> ShuttleBusSnapshot {
        let today = StrictContractDateParser.string(from: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        let period = ShuttleBusPeriod(
            label: "示例运行时段",
            startDate: today,
            endDate: StrictContractDateParser.string(from: end, calendar: calendar)
        )
        let weekdayServices = Dictionary(uniqueKeysWithValues: ShuttleBusTodayLogic.weekdayKeys.map {
            ($0, ShuttleBusService(vehicle: "大巴", count: 1))
        })
        let rows = ["06:30", "08:30", "12:00", "17:30"].map {
            ShuttleBusScheduleRow(departureTime: $0, services: weekdayServices)
        }
        let notice = ShuttleBusNotice(
            id: "sample-shuttle",
            title: "示例：两校区班车运行安排",
            publishedAt: today,
            sourceURL: nil,
            kind: "regular_schedule",
            notes: ["示例数据不连接班车服务。"],
            stops: [
                ShuttleBusStop(campus: "西土城路校区", location: "教三楼西侧"),
                ShuttleBusStop(campus: "沙河校区", location: "学生活动中心南侧"),
            ],
            parseStatus: "parsed",
            schedules: [
                ShuttleBusSchedule(
                    period: period,
                    from: "西土城路校区",
                    to: "沙河校区",
                    parseStatus: "parsed",
                    rows: rows
                ),
                ShuttleBusSchedule(
                    period: period,
                    from: "沙河校区",
                    to: "西土城路校区",
                    parseStatus: "parsed",
                    rows: rows
                ),
            ]
        )
        return ShuttleBusSnapshot(
            generatedAt: "2026-01-01T00:00:00+08:00",
            status: "healthy",
            sourceName: "示例数据",
            sourcePage: ShuttleBusSources.sourcePage,
            lastParsedNoticeID: notice.id,
            notices: [notice]
        )
    }
}

private struct ShuttleBusPayloadDTO: Decodable {
    let schemaVersion: String
    let generatedAt: String
    let status: String
    let source: ShuttleBusSourceDTO
    let lastParsedNoticeID: String?
    let items: [ShuttleBusNoticeDTO]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status, source, items
        case lastParsedNoticeID = "last_parsed_notice_id"
    }
}

private struct ShuttleBusSourceDTO: Decodable {
    let name: String
    let pageURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case pageURL = "page_url"
    }
}

private struct ShuttleBusNoticeDTO: Decodable {
    let id: String
    let title: String
    let publishedAt: String
    let sourceURL: String?
    let kind: String
    let notes: [String]
    let stops: [ShuttleBusStopDTO]
    let parseStatus: String
    let schedules: [ShuttleBusScheduleDTO]

    enum CodingKeys: String, CodingKey {
        case id, title, kind, notes, stops, schedules
        case publishedAt = "published_at"
        case sourceURL = "source_url"
        case parseStatus = "parse_status"
    }
}

private struct ShuttleBusStopDTO: Decodable {
    let campus: String
    let location: String
}

private struct ShuttleBusScheduleDTO: Decodable {
    let period: ShuttleBusPeriodDTO
    let from: String
    let to: String
    let parseStatus: String
    let rows: [ShuttleBusScheduleRowDTO]

    enum CodingKeys: String, CodingKey {
        case period, from, to, rows
        case parseStatus = "parse_status"
    }
}

private struct ShuttleBusPeriodDTO: Decodable {
    let label: String
    let startDate: String?
    let endDate: String?

    enum CodingKeys: String, CodingKey {
        case label
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

private struct ShuttleBusScheduleRowDTO: Decodable {
    let departureTime: String
    let services: [String: ShuttleBusServiceDTO?]

    enum CodingKeys: String, CodingKey {
        case departureTime = "departure_time"
        case services
    }
}

private struct ShuttleBusServiceDTO: Decodable {
    let vehicle: String
    let count: Int
}
