import Foundation

enum AppLaunchConfiguration {
    static let uiTestingArgument = "--ui-testing"
    static let uiTestingLiveArgument = "--ui-testing-live"
    static let reviewDemoArgument = "--review-demo"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    static var isReviewDemo: Bool {
        ProcessInfo.processInfo.arguments.contains(reviewDemoArgument)
            || ProcessInfo.processInfo.environment["WHERE_TO_STUDY_REVIEW_DEMO"] == "1"
    }

    static var isUITestingLive: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingLiveArgument)
    }

    static var isXCTestRunning: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    @MainActor
    static func makeModel() -> AppModel {
        guard isUITesting || isUITestingLive || isReviewDemo else { return AppModel() }

        let suiteName: String
        if isReviewDemo {
            suiteName = "com.nemoyu.wheretostudy.native.review-demo"
        } else if isUITestingLive {
            suiteName = "com.nemoyu.wheretostudy.native.ui-tests-live"
        } else {
            suiteName = "com.nemoyu.wheretostudy.native.ui-tests"
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        if let language = ProcessInfo.processInfo.environment["WHERE_TO_STUDY_UI_LANGUAGE"],
           AppLanguage(rawValue: language) != nil {
            defaults.set(language, forKey: AppLocalization.defaultsKey)
        }
        if isUITestingLive {
            return AppModel(
                credentialStore: SampleCredentialStore(),
                scheduleStore: SampleScheduleStore(schedule: nil),
                scheduleClient: SampleScheduleClient(),
                classroomStore: SampleClassroomStore(cache: nil),
                classroomClient: SampleClassroomClient(),
                holidayStore: SampleHolidayStore(),
                holidayClient: SampleHolidayClient(),
                calendarImporter: SampleCalendarImporter(),
                dailyCourseNotificationScheduler: SampleDailyCourseNotificationScheduler(),
                defaults: defaults
            )
        }
        return AppModel(
            runtimeMode: .sample(review: isReviewDemo),
            credentialStore: SampleCredentialStore(),
            scheduleStore: SampleScheduleStore(),
            scheduleClient: SampleScheduleClient(),
            classroomStore: SampleClassroomStore(),
            classroomClient: SampleClassroomClient(),
            holidayStore: SampleHolidayStore(),
            holidayClient: SampleHolidayClient(),
            calendarImporter: SampleCalendarImporter(),
            dailyCourseNotificationScheduler: SampleDailyCourseNotificationScheduler(),
            defaults: defaults
        )
    }
}

enum AppRuntimeMode: Equatable, Sendable {
    case live
    case sample(review: Bool)

    var isSample: Bool {
        if case .sample = self { true } else { false }
    }

    var isReviewDemo: Bool {
        if case .sample(review: true) = self { true } else { false }
    }
}

private enum SampleDependencyError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "示例模式不会访问外部服务或系统数据。"
    }
}

private struct SampleCredentialStore: CredentialStoring {
    func load() throws -> Credentials? { nil }
    func save(_: Credentials) throws { throw SampleDependencyError.unavailable }
    func clear() throws {}
}

private struct SampleScheduleStore: ScheduleStoring {
    let schedule: ScheduleSnapshot?

    init(schedule: ScheduleSnapshot? = SampleData.schedule()) {
        self.schedule = schedule
    }

    func load() throws -> ScheduleSnapshot? { schedule }
    func save(_: ScheduleSnapshot) throws { throw SampleDependencyError.unavailable }
    func clear() throws {}
}

private struct SampleScheduleClient: ScheduleFetching {
    func fetch(
        credentials _: Credentials,
        fallbackTermID _: String,
        fallbackTermStartDate _: String
    ) async throws -> ScheduleSnapshot {
        throw SampleDependencyError.unavailable
    }
}

private struct SampleClassroomStore: ClassroomStoring {
    let cache: ClassroomsCache?

    init(cache: ClassroomsCache? = SampleData.classrooms()) {
        self.cache = cache
    }

    func load() throws -> ClassroomsCache? { cache }
    func save(_: ClassroomsCache) throws { throw SampleDependencyError.unavailable }
    func clear() throws {}
}

private struct SampleClassroomClient: ClassroomFetching {
    func fetch(credentials _: Credentials, targetDate _: String) async throws -> ClassroomsCache {
        throw SampleDependencyError.unavailable
    }
}

private struct SampleHolidayStore: HolidayStoring {
    func load(year: Int) throws -> HolidaysSnapshot? {
        HolidayOfflineFallback.snapshot(year: year)
            ?? HolidaysSnapshot(
                year: year,
                source: "review-demo",
                fetchedAt: SampleData.timestamp,
                items: []
            )
    }

    func save(_: HolidaysSnapshot) throws { throw SampleDependencyError.unavailable }
    func clear() throws {}
}

private struct SampleHolidayClient: HolidayFetching {
    func fetch(year _: Int) async throws -> HolidaysSnapshot {
        throw SampleDependencyError.unavailable
    }
}

@MainActor
private struct SampleCalendarImporter: CalendarImporting {
    func importSchedule(_: ScheduleSnapshot) async throws -> CalendarImportResult {
        throw SampleDependencyError.unavailable
    }
}

private struct SampleDailyCourseNotificationScheduler: DailyCourseNotificationScheduling {
    func authorizationStatus(timeout _: Duration) async throws -> DailyCourseNotificationAuthorization { .denied }
    func requestAuthorization(timeout _: Duration) async throws -> Bool { false }
    func replacePending(
        with _: [DailyCourseNotificationRequest],
        revision _: UInt64
    ) async throws {}
    func cancelPending(revision _: UInt64) {}
}

enum SampleData {
    static let timestamp = "2026-01-01T00:00:00+08:00"

    static func schedule(now: Date = .now, calendar: Calendar = .shanghai) -> ScheduleSnapshot {
        let weekday = ((calendar.component(.weekday, from: now) + 5) % 7) + 1
        let weekStart = calendar.date(byAdding: .day, value: 1 - weekday, to: now) ?? now
        let adjacentWeekday = weekday == 7 ? 1 : weekday + 1
        return ScheduleSnapshot(
            termID: "review-demo",
            termStartDate: StrictContractDateParser.string(from: weekStart),
            fetchedAt: timestamp,
            courses: [
                Course(
                    id: "sample-data-mining",
                    name: "数据挖掘",
                    teacher: "示例教师",
                    room: "教3-335",
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
                    id: "sample-neural-network",
                    name: "神经网络与深度学习",
                    teacher: "示例教师",
                    room: "教3-539",
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

    static func classrooms(now: Date = .now) -> ClassroomsCache {
        let targetDate = StrictContractDateParser.string(from: now)
        return ClassroomsCache(
            cacheVersion: ClassroomDefaults.cacheVersion,
            targetDate: targetDate,
            fetchedAt: timestamp,
            realtime: false,
            provider: "review-demo",
            campuses: [
                CampusClassrooms(
                    campusID: "01",
                    campusName: "西土城",
                    targetDate: targetDate,
                    fetchedAt: timestamp,
                    realtime: false,
                    provider: "review-demo",
                    rooms: [
                        room("教1", "101", size: 80, slots: Array(0 ... 13)),
                        room("教2", "201", size: 64, slots: [0, 1, 5, 6, 9, 10, 11]),
                        room("主楼", "217-218", size: 60, slots: [0, 1, 7, 8, 9, 10, 11, 12, 13])
                    ]
                ),
                CampusClassrooms(
                    campusID: "04",
                    campusName: "沙河",
                    targetDate: targetDate,
                    fetchedAt: timestamp,
                    realtime: false,
                    provider: "review-demo",
                    rooms: [
                        room("综合教学楼N", "101", size: 90, slots: Array(0 ... 13)),
                        room("智慧教学楼", "305-306", size: 60, slots: [0, 1, 2, 3, 8, 9])
                    ]
                )
            ]
        )
    }

    static func holidays(year: Int) -> HolidaysSnapshot {
        HolidayOfflineFallback.snapshot(year: year)
            ?? HolidaysSnapshot(
                year: year,
                source: "review-demo",
                fetchedAt: timestamp,
                items: []
            )
    }

    private static func room(
        _ building: String,
        _ number: String,
        size: Int,
        slots: [Int]
    ) -> Classroom {
        Classroom(
            id: "\(building)-\(number)",
            building: building,
            room: number,
            name: "\(building)-\(number)",
            size: size,
            type: "",
            availableSlots: slots,
            source: "review-demo"
        )
    }
}
