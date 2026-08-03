import Foundation

protocol HolidayStoring: Sendable {
    func load(year: Int) throws -> HolidaysSnapshot?
    func save(_ snapshot: HolidaysSnapshot) throws
    func clear() throws
}

struct FileHolidayStore: HolidayStoring {
    let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL
    }

    func load(year: Int) throws -> HolidaysSnapshot? {
        try HolidayCacheContract.validateRequestedYear(year)
        let fileURL = fileURL(year: year)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= HolidaySourceLimits.maximumPayloadBytes else {
            throw HolidayClientError.service("本地节假日缓存过大。")
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        guard data.count <= HolidaySourceLimits.maximumPayloadBytes else {
            throw HolidayClientError.service("本地节假日缓存过大。")
        }
        return try HolidayCacheContract.decode(data, expectedYear: year)
    }

    func save(_ snapshot: HolidaysSnapshot) throws {
        try HolidayCacheContract.validate(snapshot)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= HolidaySourceLimits.maximumPayloadBytes else {
            throw HolidayClientError.service("本地节假日缓存过大。")
        }
        try data.write(to: fileURL(year: snapshot.year), options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try FileManager.default.removeItem(at: directoryURL)
    }

    private func fileURL(year: Int) -> URL {
        directoryURL.appendingPathComponent("holidays_\(year).json", isDirectory: false)
    }

    private static var defaultDirectoryURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("WhereToStudyNative", isDirectory: true)
            .appendingPathComponent("holidays", isDirectory: true)
    }
}

private enum HolidayCacheContract {
    private static let snapshotKeys = Set(["year", "source", "fetched_at", "items"])
    private static let itemKeys = Set(["date", "name", "type"])
    private static let maximumSourceLength = 512
    private static let maximumTimestampLength = 64

    static func decode(_ data: Data, expectedYear: Int) throws -> HolidaysSnapshot {
        try validateJSONStructure(data)

        let snapshot: HolidaysSnapshot
        do {
            snapshot = try JSONDecoder().decode(HolidaysSnapshot.self, from: data)
        } catch {
            throw HolidayClientError.service("本地节假日缓存格式不正确。")
        }
        try validate(snapshot, expectedYear: expectedYear)
        return snapshot
    }

    static func validateRequestedYear(_ year: Int) throws {
        guard HolidayDefaults.supportedYears.contains(year) else {
            throw HolidayClientError.service("节假日年份不在支持范围内。")
        }
    }

    static func validate(_ snapshot: HolidaysSnapshot, expectedYear: Int? = nil) throws {
        guard HolidayDefaults.supportedYears.contains(snapshot.year) else {
            throw HolidayClientError.service("本地节假日缓存的年份不在支持范围内。")
        }
        if let expectedYear, snapshot.year != expectedYear {
            throw HolidayClientError.service("本地节假日缓存年份与请求不一致。")
        }
        guard
            !snapshot.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            snapshot.source.unicodeScalars.count <= maximumSourceLength
        else {
            throw HolidayClientError.service("本地节假日缓存的数据源不正确。")
        }
        guard isContractTimestamp(snapshot.fetchedAt) else {
            throw HolidayClientError.service("本地节假日缓存的获取时间不正确。")
        }
        guard snapshot.items.count <= HolidaySourceLimits.maximumExpandedItems else {
            throw HolidayClientError.service("本地节假日缓存的条目数量超过限制。")
        }

        for item in snapshot.items {
            guard let itemYear = contractDateYear(item.date) else {
                throw HolidayClientError.service("本地节假日缓存的日期不正确。")
            }
            guard itemYear == snapshot.year else {
                throw HolidayClientError.service("本地节假日缓存包含其他年份的日期。")
            }
            guard
                !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                item.name.unicodeScalars.count <= HolidaySourceLimits.maximumNameLength
            else {
                throw HolidayClientError.service("本地节假日缓存的名称不正确。")
            }
            guard item.type == "holiday" || item.type == "workday" else {
                throw HolidayClientError.service("本地节假日缓存的类型不正确。")
            }
        }
    }

    private static func validateJSONStructure(_ data: Data) throws {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HolidayClientError.service("本地节假日缓存格式不正确。")
        }
        guard let root = value as? [String: Any] else {
            throw HolidayClientError.service("本地节假日缓存根对象格式不正确。")
        }
        guard Set(root.keys) == snapshotKeys else {
            throw HolidayClientError.service("本地节假日缓存字段不正确。")
        }
        guard let items = root["items"] as? [Any] else {
            throw HolidayClientError.service("本地节假日缓存的 items 格式不正确。")
        }
        for value in items {
            guard let item = value as? [String: Any] else {
                throw HolidayClientError.service("本地节假日缓存的条目格式不正确。")
            }
            guard Set(item.keys) == itemKeys else {
                throw HolidayClientError.service("本地节假日缓存的条目字段不正确。")
            }
        }
    }

    private static func contractDateYear(_ value: String) -> Int? {
        guard value.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil else { return nil }
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard
            components.count == 3,
            let year = Int(components[0]),
            let month = Int(components[1]),
            let day = Int(components[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year, normalized.month == month, normalized.day == day else {
            return nil
        }
        return year
    }

    private static func isContractTimestamp(_ value: String) -> Bool {
        guard
            value.count <= maximumTimestampLength,
            value.range(
                of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})$"#,
                options: .regularExpression
            ) != nil
        else { return false }

        guard contractDateYear(String(value.prefix(10))) != nil else { return false }
        let bytes = Array(value.utf8)
        func twoDigits(at index: Int) -> Int {
            Int(bytes[index] - 48) * 10 + Int(bytes[index + 1] - 48)
        }

        guard
            twoDigits(at: 11) <= 23,
            twoDigits(at: 14) <= 59,
            twoDigits(at: 17) <= 59
        else { return false }
        if bytes.count == 20 {
            return bytes[19] == 0x5A
        }
        return bytes.count == 25
            && twoDigits(at: 20) <= 23
            && twoDigits(at: 23) <= 59
    }
}
