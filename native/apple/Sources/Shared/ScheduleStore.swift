import Foundation

protocol ScheduleStoring: Sendable {
    func load() throws -> ScheduleSnapshot?
    func save(_ schedule: ScheduleSnapshot) throws
    func clear() throws
}

enum ScheduleStoreError: LocalizedError, Equatable {
    case unavailableDirectory
    case invalidTermStartDate

    var errorDescription: String? {
        switch self {
        case .unavailableDirectory:
            "无法定位本地课表目录。"
        case .invalidTermStartDate:
            "本地课表的第一周周一日期格式不正确。"
        }
    }
}

struct FileScheduleStore: ScheduleStoring {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func load() throws -> ScheduleSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        let decoded = try JSONDecoder().decode(ScheduleSnapshot.self, from: data)
        guard StrictContractDateParser.date(from: decoded.termStartDate) != nil else {
            throw ScheduleStoreError.invalidTermStartDate
        }
        return ScheduleSnapshot(
            termID: decoded.termID,
            termStartDate: decoded.termStartDate,
            fetchedAt: decoded.fetchedAt,
            courses: ScheduleLogic.clearingLegacyExamWeeks(in: decoded.courses)
        )
    }

    func save(_ schedule: ScheduleSnapshot) throws {
        guard StrictContractDateParser.date(from: schedule.termStartDate) != nil else {
            throw ScheduleStoreError.invalidTermStartDate
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(schedule).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static var defaultFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("WhereToStudyNative", isDirectory: true)
            .appendingPathComponent("schedule.json", isDirectory: false)
    }
}
