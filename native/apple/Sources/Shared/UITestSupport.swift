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
    func load() throws -> ScheduleSnapshot? { nil }
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
    func authorizationStatus() async -> DailyCourseNotificationAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func replacePending(
        with _: [DailyCourseNotificationRequest],
        revision _: UInt64
    ) async throws {}
    func cancelPending(revision _: UInt64) {}
}
