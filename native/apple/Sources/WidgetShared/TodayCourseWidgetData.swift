import Foundation

enum TodayCourseWidgetData {
    static let appGroupIdentifier = "group.com.nemoyu.wheretostudy.native"
    static let archiveFileName = "widget-schedule.json"

    struct Archive: Codable, Equatable, Sendable {
        let termStartDate: String
        let fetchedAt: String
        let courses: [Course]
    }

    struct Course: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let room: String
        let timeRange: String
        let weekday: Int
        let weekNumbers: [Int]
        let examWeekNumbers: [Int]
        let startSlot: Int
    }

    static func save(schedule: ScheduleSnapshot) throws {
        let archive = Archive(
            termStartDate: schedule.termStartDate,
            fetchedAt: schedule.fetchedAt,
            courses: schedule.courses.map {
                Course(
                    id: $0.id,
                    name: $0.name,
                    room: $0.room,
                    timeRange: $0.timeRange,
                    weekday: $0.weekday,
                    weekNumbers: $0.weekNumbers,
                    examWeekNumbers: $0.examWeekNumbers,
                    startSlot: $0.startSlot
                )
            }
        )
        let data = try JSONEncoder().encode(archive)
        var saved = false
        var lastError: Error?
        for fileURL in writableFileURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                saved = true
            } catch {
                lastError = error
            }
        }
        if !saved, let lastError { throw lastError }
    }

    static func load() -> Archive? {
        for fileURL in readableFileURLs() {
            guard
                let data = try? Data(contentsOf: fileURL),
                !data.isEmpty,
                let archive = try? JSONDecoder().decode(Archive.self, from: data)
            else { continue }
            return archive
        }
        return nil
    }

    static func clear() {
        for fileURL in writableFileURLs() where FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func courses(on date: Date, archive: Archive?, calendar: Calendar = .shanghai) -> [Course] {
        guard
            let archive,
            let termStart = StrictContractDateParser.date(from: archive.termStartDate, calendar: calendar)
        else { return [] }
        let week = ScheduleLogic.weekNumber(on: date, termStart: termStart, calendar: calendar)
        let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
        return archive.courses
            .filter { $0.weekday == weekday && $0.weekNumbers.contains(week) }
            .sorted { lhs, rhs in
                lhs.startSlot == rhs.startSlot ? lhs.name < rhs.name : lhs.startSlot < rhs.startSlot
            }
    }

    static func nextMidnight(after date: Date, calendar: Calendar = .shanghai) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(24 * 60 * 60)
    }

    private static func readableFileURLs() -> [URL] {
        writableFileURLs().filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func writableFileURLs() -> [URL] {
        #if APP_STORE_BUILD
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return [groupURL.appendingPathComponent(archiveFileName, isDirectory: false)]
        }
        return []
        #else
        // Ad-hoc local packages have no registered App Group container. Keep a
        // compatibility copy for those preview builds only; App Store archives
        // define APP_STORE_BUILD and use the signed group container exclusively.
        let supportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhereToStudyNative", isDirectory: true)
            .appendingPathComponent(archiveFileName, isDirectory: false)
        return [supportURL]
        #endif
    }
}
