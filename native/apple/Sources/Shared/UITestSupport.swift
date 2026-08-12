import Foundation

enum AppLaunchConfiguration {
    static let uiTestingArgument = "--ui-testing"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    @MainActor
    static func makeModel() -> AppModel {
        guard isUITesting else { return AppModel() }

        let suiteName = "com.nemoyu.wheretostudy.native.ui-tests"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AppModel(
            credentialStore: UITestCredentialStore(),
            scheduleStore: UITestScheduleStore(),
            scheduleClient: UITestScheduleClient(),
            classroomStore: UITestClassroomStore(),
            classroomClient: UITestClassroomClient(),
            holidayStore: UITestHolidayStore(),
            holidayClient: UITestHolidayClient(),
            calendarImporter: UITestCalendarImporter(),
            dailyCourseNotificationScheduler: UITestDailyCourseNotificationScheduler(),
            defaults: defaults
        )
    }
}

private enum UITestDependencyError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "UI 测试模式不允许访问外部服务。"
    }
}

private struct UITestCredentialStore: CredentialStoring {
    func load() throws -> Credentials? { nil }
    func save(_: Credentials) throws {}
    func clear() throws {}
}

private struct UITestScheduleStore: ScheduleStoring {
    func load() throws -> ScheduleSnapshot? {
        let calendar = Calendar.shanghai
        let now = Date()
        let weekday = ((calendar.component(.weekday, from: now) + 5) % 7) + 1
        guard let weekStart = calendar.date(byAdding: .day, value: 1 - weekday, to: now) else {
            return nil
        }
        let adjacentWeekday = weekday == 7 ? 1 : weekday + 1
        return ScheduleSnapshot(
            termID: "ui-test-term",
            termStartDate: StrictContractDateParser.string(from: weekStart),
            fetchedAt: ISO8601DateFormatter().string(from: now),
            courses: [
                Course(
                    id: "ui-test-data-mining",
                    name: "数据挖掘",
                    teacher: "测试教师",
                    room: "教三楼-3-335",
                    weekText: "1-2",
                    weekNumbers: [1, 2],
                    examWeekNumbers: [],
                    weekday: weekday,
                    startSlot: 2,
                    endSlot: 4,
                    sectionText: "3-5节",
                    timeRange: "09:50-12:15"
                ),
                Course(
                    id: "ui-test-neural-network",
                    name: "神经网络与深度学习",
                    teacher: "测试教师",
                    room: "教三楼-3-539",
                    weekText: "1-2",
                    weekNumbers: [1, 2],
                    examWeekNumbers: [],
                    weekday: adjacentWeekday,
                    startSlot: 7,
                    endSlot: 8,
                    sectionText: "8-9节",
                    timeRange: "14:45-16:25"
                )
            ]
        )
    }
    func save(_: ScheduleSnapshot) throws {}
    func clear() throws {}
}

private struct UITestScheduleClient: ScheduleFetching {
    func fetch(
        credentials _: Credentials,
        fallbackTermID _: String,
        fallbackTermStartDate _: String
    ) async throws -> ScheduleSnapshot {
        throw UITestDependencyError.unavailable
    }
}

private struct UITestClassroomStore: ClassroomStoring {
    func load() throws -> ClassroomsCache? { nil }
    func save(_: ClassroomsCache) throws {}
    func clear() throws {}
}

private struct UITestClassroomClient: ClassroomFetching {
    func fetch(credentials _: Credentials, targetDate _: String) async throws -> ClassroomsCache {
        throw UITestDependencyError.unavailable
    }
}

private struct UITestHolidayStore: HolidayStoring {
    func load(year: Int) throws -> HolidaysSnapshot? {
        HolidaysSnapshot(
            year: year,
            source: "ui-test-fixture",
            fetchedAt: ISO8601DateFormatter().string(from: .now),
            items: []
        )
    }

    func save(_: HolidaysSnapshot) throws {}
    func clear() throws {}
}

private struct UITestHolidayClient: HolidayFetching {
    func fetch(year _: Int) async throws -> HolidaysSnapshot {
        throw UITestDependencyError.unavailable
    }
}

@MainActor
private struct UITestCalendarImporter: CalendarImporting {
    func importSchedule(_: ScheduleSnapshot) async throws -> CalendarImportResult {
        throw UITestDependencyError.unavailable
    }
}

private struct UITestDailyCourseNotificationScheduler: DailyCourseNotificationScheduling {
    func authorizationStatus(timeout _: Duration) async throws -> DailyCourseNotificationAuthorization { .denied }
    func requestAuthorization(timeout _: Duration) async throws -> Bool { false }
    func replacePending(
        with _: [DailyCourseNotificationRequest],
        revision _: UInt64
    ) async throws {}
    func cancelPending(revision _: UInt64) {}
}
