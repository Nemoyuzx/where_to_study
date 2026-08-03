import Foundation

protocol ScheduleStoring: Sendable {
    func load() throws -> ScheduleSnapshot?
    func save(_ schedule: ScheduleSnapshot) throws
}

enum ScheduleStoreError: LocalizedError {
    case unavailableDirectory

    var errorDescription: String? {
        switch self {
        case .unavailableDirectory:
            "无法定位本地课表目录。"
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
        return ScheduleSnapshot(
            termID: decoded.termID,
            termStartDate: decoded.termStartDate,
            fetchedAt: decoded.fetchedAt,
            courses: ScheduleLogic.applyingExamWeeks(to: decoded.courses)
        )
    }

    func save(_ schedule: ScheduleSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(schedule).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("WhereToStudyNative", isDirectory: true)
            .appendingPathComponent("schedule.json", isDirectory: false)
    }
}
