import Foundation

/// Serializes persistence with account/cache invalidation. Reads can run without
/// the lock because their results are checked again before entering UI state.
final class LocalDataPersistence: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    func invalidate(generation: Int) {
        lock.withLock { self.generation = generation }
    }

    func perform(ifGeneration expected: Int, _ operation: () throws -> Void) rethrows -> Bool {
        try lock.withLock {
            guard generation == expected else { return false }
            try operation()
            return true
        }
    }

    func saveSchedule(_ snapshot: ScheduleSnapshot, to store: any ScheduleStoring, generation: Int) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            try self.perform(ifGeneration: generation) { try store.save(snapshot) }
        }.value
    }

    func saveClassrooms(_ cache: ClassroomsCache, to store: any ClassroomStoring, generation: Int) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            try self.perform(ifGeneration: generation) { try store.save(cache) }
        }.value
    }

    func saveHolidays(_ snapshot: HolidaysSnapshot, to store: any HolidayStoring, generation: Int) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            try self.perform(ifGeneration: generation) { try store.save(snapshot) }
        }.value
    }
}

struct InitialLocalDataSnapshots: Sendable {
    let schedule: Result<ScheduleSnapshot?, Error>
    let classrooms: Result<ClassroomsCache?, Error>
}

enum LocalDataLoading {
    static func schedule(from store: any ScheduleStoring) -> Result<ScheduleSnapshot?, Error> {
        Result { try store.load() }
    }

    static func classrooms(from store: any ClassroomStoring) -> Result<ClassroomsCache?, Error> {
        Result { try store.load() }
    }

    static func holidays(from store: any HolidayStoring, year: Int) -> Result<HolidaysSnapshot?, Error> {
        Result { try store.load(year: year) }
    }

    static func initialSnapshots(
        scheduleStore: any ScheduleStoring,
        classroomStore: any ClassroomStoring
    ) async -> InitialLocalDataSnapshots {
        await Task.detached(priority: .userInitiated) {
            InitialLocalDataSnapshots(
                schedule: schedule(from: scheduleStore),
                classrooms: classrooms(from: classroomStore)
            )
        }.value
    }

    static func holidaySnapshot(from store: any HolidayStoring, year: Int) async -> Result<HolidaysSnapshot?, Error> {
        await Task.detached(priority: .utility) { holidays(from: store, year: year) }.value
    }
}

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
