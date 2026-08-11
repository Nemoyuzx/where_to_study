import Foundation

protocol HolidayFetching: Sendable {
    func fetch(year: Int) async throws -> HolidaysSnapshot
}

enum HolidayClientError: LocalizedError {
    case service(String)

    var errorDescription: String? {
        switch self {
        case let .service(message): message
        }
    }
}

enum HolidaySourceLimits {
    static let maximumPayloadBytes = 256 * 1024
    static let maximumRecords = 128
    static let maximumNameLength = 80
    static let maximumExpandedItems = 512
}

enum HolidayResponseAccumulator {
    static func append(_ byte: UInt8, to data: inout Data) throws {
        guard data.count < HolidaySourceLimits.maximumPayloadBytes else {
            throw HolidayClientError.service("节假日数据响应过大。")
        }
        data.append(byte)
    }
}

enum HolidayUserAgent {
    static func value(bundle: Bundle = .main) -> String {
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "WhereToStudyNative/\(version.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown")"
    }
}

struct HolidayClient: HolidayFetching {
    private let session: URLSession
    private let source: String

    init(session: URLSession = .shared, source: String = HolidayDefaults.source) {
        self.session = session
        self.source = source
    }

    func fetch(year: Int) async throws -> HolidaysSnapshot {
        guard HolidayDefaults.supportedYears.contains(year) else {
            throw HolidayClientError.service("节假日年份不在支持范围内。")
        }
        guard let url = URL(string: "\(source)/\(year).json") else {
            throw HolidayClientError.service("节假日数据源地址不正确。")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw HolidayClientError.service("节假日数据源返回错误，HTTP \(status)。")
        }
        if response.expectedContentLength > Int64(HolidaySourceLimits.maximumPayloadBytes) {
            throw HolidayClientError.service("节假日数据响应过大。")
        }
        var data = Data()
        data.reserveCapacity(min(
            max(Int(response.expectedContentLength), 0),
            HolidaySourceLimits.maximumPayloadBytes
        ))
        for try await byte in bytes {
            try HolidayResponseAccumulator.append(byte, to: &data)
        }
        return try HolidaySourceParser.parse(
            data: data,
            year: year,
            source: source,
            fetchedAt: Self.timestamp()
        )
    }

    private static func timestamp(_ date: Date = .now) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }
}

enum HolidaySourceParser {
    private struct SourceResponse: Decodable {
        let year: Int
        let region: String
        let dates: [SourceHoliday]
    }

    private struct SourceHoliday: Decodable {
        let date: String
        let name: String?
        let nameCN: String?
        let nameEN: String?
        let type: String

        enum CodingKeys: String, CodingKey {
            case date, name, type
            case nameCN = "name_cn"
            case nameEN = "name_en"
        }
    }

    static func parse(
        data: Data,
        year: Int,
        source: String,
        fetchedAt: String
    ) throws -> HolidaysSnapshot {
        guard HolidayDefaults.supportedYears.contains(year) else {
            throw HolidayClientError.service("节假日年份不在支持范围内。")
        }
        guard data.count <= HolidaySourceLimits.maximumPayloadBytes else {
            throw HolidayClientError.service("节假日数据响应过大。")
        }
        let payload: SourceResponse
        do {
            payload = try JSONDecoder().decode(SourceResponse.self, from: data)
        } catch {
            throw HolidayClientError.service("节假日数据格式不正确。")
        }
        guard payload.year == year else {
            throw HolidayClientError.service("节假日数据年份与请求不一致。")
        }
        guard payload.region == "CN" else {
            throw HolidayClientError.service("节假日数据区域不正确。")
        }
        guard payload.dates.count <= HolidaySourceLimits.maximumRecords else {
            throw HolidayClientError.service("节假日数据记录过多。")
        }
        var items = [HolidayItem]()
        for item in payload.dates {
            let chineseName = item.nameCN?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = chineseName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName ?? ""
            guard !name.isEmpty else {
                throw HolidayClientError.service("节假日名称不能为空。")
            }
            guard name.unicodeScalars.count <= HolidaySourceLimits.maximumNameLength else {
                throw HolidayClientError.service("节假日名称过长。")
            }
            guard let date = parseDate(item.date) else {
                throw HolidayClientError.service("节假日数据日期格式不正确。")
            }
            guard Calendar.shanghai.component(.year, from: date) == year else {
                throw HolidayClientError.service("节假日数据包含其他年份的日期。")
            }
            guard let type = normalizedType(item.type) else { continue }
            guard items.count < HolidaySourceLimits.maximumExpandedItems else {
                throw HolidayClientError.service("节假日展开记录过多。")
            }
            items.append(HolidayItem(
                date: contractDateFormatter.string(from: date),
                name: name,
                type: type
            ))
        }
        guard !items.isEmpty else {
            throw HolidayClientError.service("节假日数据没有可识别的法定节假日或调休记录。")
        }
        return HolidaysSnapshot(
            year: year,
            source: source,
            fetchedAt: fetchedAt,
            items: items.sorted { ($0.date, $0.type, $0.name) < ($1.date, $1.type, $1.name) }
        )
    }

    private static func normalizedType(_ value: String) -> String? {
        switch value {
        case "public_holiday": "holiday"
        case "transfer_workday": "workday"
        default: nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        guard
            value.count == 10,
            value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
            let date = contractDateFormatter.date(from: value),
            contractDateFormatter.string(from: date) == value
        else { return nil }
        return date
    }

    private static let contractDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}

enum HolidayOfflineFallback {
    static let source = "https://www.gov.cn/yaowen/liebiao/202511/content_7047099.htm"

    static func snapshot(year: Int, fetchedAt: String = timestamp()) -> HolidaysSnapshot? {
        guard year == 2026 else { return nil }
        let ranges = [
            ("元旦", "2026-01-01", "2026-01-03", "holiday"),
            ("元旦补班", "2026-01-04", "2026-01-04", "workday"),
            ("春节补班", "2026-02-14", "2026-02-14", "workday"),
            ("春节", "2026-02-15", "2026-02-23", "holiday"),
            ("春节补班", "2026-02-28", "2026-02-28", "workday"),
            ("清明节", "2026-04-04", "2026-04-06", "holiday"),
            ("劳动节", "2026-05-01", "2026-05-05", "holiday"),
            ("劳动节补班", "2026-05-09", "2026-05-09", "workday"),
            ("端午节", "2026-06-19", "2026-06-21", "holiday"),
            ("中秋节", "2026-09-25", "2026-09-27", "holiday"),
            ("国庆节补班", "2026-09-20", "2026-09-20", "workday"),
            ("国庆节", "2026-10-01", "2026-10-07", "holiday"),
            ("国庆节补班", "2026-10-10", "2026-10-10", "workday")
        ]
        var items = [HolidayItem]()
        for (name, startValue, endValue, type) in ranges {
            guard
                var date = contractDateFormatter.date(from: startValue),
                let end = contractDateFormatter.date(from: endValue)
            else { return nil }
            while date <= end {
                items.append(HolidayItem(
                    date: contractDateFormatter.string(from: date),
                    name: name,
                    type: type
                ))
                guard let next = Calendar.shanghai.date(byAdding: .day, value: 1, to: date) else {
                    return nil
                }
                date = next
            }
        }
        return HolidaysSnapshot(
            year: year,
            source: source,
            fetchedAt: fetchedAt,
            items: items
        )
    }

    private static func timestamp(_ date: Date = .now) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }

    private static let contractDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}
