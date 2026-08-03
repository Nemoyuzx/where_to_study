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
    static let maximumRangeEntries = 32
    static let maximumRangeDays = 32
    static let maximumExpandedItems = 512
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
            guard data.count < HolidaySourceLimits.maximumPayloadBytes else {
                throw HolidayClientError.service("节假日数据响应过大。")
            }
            data.append(byte)
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
    private struct SourceHoliday: Decodable {
        let name: String
        let range: [String]
        let type: String
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
        let sourceItems: [SourceHoliday]
        do {
            sourceItems = try JSONDecoder().decode([SourceHoliday].self, from: data)
        } catch {
            throw HolidayClientError.service("节假日数据格式不正确。")
        }
        guard sourceItems.count <= HolidaySourceLimits.maximumRecords else {
            throw HolidayClientError.service("节假日数据记录过多。")
        }
        var items = [HolidayItem]()
        for item in sourceItems {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw HolidayClientError.service("节假日名称不能为空。")
            }
            guard name.unicodeScalars.count <= HolidaySourceLimits.maximumNameLength else {
                throw HolidayClientError.service("节假日名称过长。")
            }
            guard !item.range.isEmpty else {
                throw HolidayClientError.service("节假日日期范围不能为空。")
            }
            guard item.range.count <= HolidaySourceLimits.maximumRangeEntries else {
                throw HolidayClientError.service("节假日日期范围记录过多。")
            }
            let rangeDates = try item.range.map { value -> Date in
                guard let date = parseDate(value) else {
                    throw HolidayClientError.service("节假日数据日期格式不正确。")
                }
                return date
            }
            for (previous, next) in zip(rangeDates, rangeDates.dropFirst()) where next <= previous {
                throw HolidayClientError.service("节假日数据日期范围顺序不正确。")
            }
            let start = rangeDates[0]
            let end = rangeDates[rangeDates.count - 1]
            let daySpan = Calendar.shanghai.dateComponents([.day], from: start, to: end).day ?? .max
            guard daySpan >= 0, daySpan < HolidaySourceLimits.maximumRangeDays else {
                throw HolidayClientError.service("节假日数据日期跨度过大。")
            }
            guard let type = normalizedType(item.type) else { continue }
            var day = start
            while day <= end {
                if Calendar.shanghai.component(.year, from: day) == year {
                    guard items.count < HolidaySourceLimits.maximumExpandedItems else {
                        throw HolidayClientError.service("节假日展开记录过多。")
                    }
                    items.append(HolidayItem(
                        date: contractDateFormatter.string(from: day),
                        name: name,
                        type: type
                    ))
                }
                guard let next = Calendar.shanghai.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
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
        case "holiday": "holiday"
        case "workingday", "workday": "workday"
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
