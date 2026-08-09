import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class DailyCourseNotificationTests: XCTestCase {
    func testPlannerCreatesOnlyCourseDaysWithStableIdentifiers() throws {
        let now = try date("2026-03-02 06:00")
        let requests = DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course()]),
            after: now,
            scanDayLimit: 3
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].identifier, "daily-course-summary.2026-03-02")
        XCTAssertEqual(requests[0].title, "今日课程 · 1 门")
        XCTAssertEqual(requests[0].body, "09:50-10:35 数据挖掘 @ 教二楼-335")
        XCTAssertEqual(requests[0].fireDate, try date("2026-03-02 07:30"))
    }

    func testPlannerSkipsEmptyDaysAndPastDeliveryTime() throws {
        XCTAssertTrue(DailyCourseNotificationPlanner.requests(
            for: schedule(courses: []),
            after: try date("2026-03-02 06:00"),
            scanDayLimit: 7
        ).isEmpty)
        XCTAssertTrue(DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course()]),
            after: try date("2026-03-02 08:00"),
            scanDayLimit: 1
        ).isEmpty)
    }

    func testPlannerMarksExamCourseTitle() throws {
        let requests = DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course(examWeeks: [1])]),
            after: try date("2026-03-02 06:00"),
            scanDayLimit: 1
        )

        XCTAssertEqual(requests.first?.body, "09:50-10:35 数据挖掘（试） @ 教二楼-335")
    }

    func testPlannerCapsWindowBelowSystemPendingLimit() throws {
        let everyDay = (1 ... 7).map { weekday in
            course(id: "course-\(weekday)", weekday: weekday, weeks: Array(1 ... 30))
        }
        let requests = DailyCourseNotificationPlanner.requests(
            for: schedule(courses: everyDay),
            after: try date("2026-03-02 06:00")
        )

        XCTAssertEqual(requests.count, DailyCourseNotificationPlanner.maximumPendingRequestCount)
        XCTAssertEqual(Set(requests.map(\.identifier)).count, requests.count)
    }

    func testPlannerScansBeyondThirtyDaysToActualLastCourseWeek() throws {
        let requests = DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course(weeks: [1, 8, 18])]),
            after: try date("2026-03-02 06:00")
        )

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map(\.identifier), [
            "daily-course-summary.2026-03-02",
            "daily-course-summary.2026-04-20",
            "daily-course-summary.2026-06-29"
        ])
        XCTAssertGreaterThan(
            try XCTUnwrap(requests.last).fireDate.timeIntervalSince(try date("2026-03-02 06:00")),
            30 * 24 * 60 * 60
        )
    }

    func testPlannerPendingLimitCountsCourseDaysRatherThanScannedNaturalDays() throws {
        let weeklyCourse = course(weeks: Array(1 ... 53))
        let requests = DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [weeklyCourse]),
            after: try date("2026-03-02 06:00")
        )

        XCTAssertEqual(requests.count, 53)
        XCTAssertEqual(requests.last?.identifier, "daily-course-summary.2027-03-01")
    }

    func testCoordinatorCancelsWhenPermissionRequestIsDenied() async throws {
        let scheduler = RecordingNotificationScheduler(
            authorization: .notDetermined,
            requestResult: false
        )
        let outcome = try await DailyCourseNotificationCoordinator(scheduler: scheduler).reconcile(
            enabled: true,
            requestPermissionIfNeeded: true,
            hasCredentials: true,
            schedule: schedule(courses: [course()]),
            now: try date("2026-03-02 06:00"),
            revision: 4
        )

        XCTAssertEqual(outcome, .permissionDenied)
        XCTAssertEqual(scheduler.cancelledRevisions, [4])
        XCTAssertTrue(scheduler.replacements.isEmpty)
    }

    func testCoordinatorClearsWithoutScheduleAndReplacesAfterRefresh() async throws {
        let scheduler = RecordingNotificationScheduler(
            authorization: .authorized,
            requestResult: true
        )
        let coordinator = DailyCourseNotificationCoordinator(scheduler: scheduler)
        let cleared = try await coordinator.reconcile(
            enabled: true,
            requestPermissionIfNeeded: false,
            hasCredentials: true,
            schedule: nil,
            now: try date("2026-03-02 06:00"),
            revision: 8
        )
        let replaced = try await coordinator.reconcile(
            enabled: true,
            requestPermissionIfNeeded: false,
            hasCredentials: true,
            schedule: schedule(courses: [course()]),
            now: try date("2026-03-02 06:00"),
            revision: 9
        )

        XCTAssertEqual(cleared, .waitingForSchedule)
        XCTAssertEqual(replaced, .scheduled(1))
        XCTAssertEqual(scheduler.cancelledRevisions, [8])
        XCTAssertEqual(scheduler.replacements.map(\.revision), [9])
        XCTAssertEqual(scheduler.replacements.first?.requests.count, 1)
    }

    func testSchedulerCancellationImmediatelyRemovesPersistedBatchWithoutEnumeration() async throws {
        let center = RecordingCourseNotificationCenter()
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = try date("2026-03-02 06:00")
        let scheduler = UserNotificationCourseScheduler(
            center: center,
            defaults: defaults,
            now: { fixedNow }
        )
        let request = try XCTUnwrap(DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course()]),
            after: fixedNow
        ).first)

        try await scheduler.replacePending(with: [request], revision: 4)
        scheduler.cancelPending(revision: 5)

        XCTAssertEqual(center.addedIdentifiers, ["daily-course-summary.2026-03-02.revision-4"])
        XCTAssertTrue(try XCTUnwrap(center.pendingRemovalBatches.last).contains(
            "daily-course-summary.2026-03-02.revision-4"
        ))
        XCTAssertTrue(try XCTUnwrap(center.deliveredRemovalBatches.last).contains(
            "daily-course-summary.2026-03-02.revision-4"
        ))
        XCTAssertEqual(defaults.stringArray(forKey: "dailyCourseNotificationIdentifiers"), [])
    }

    func testSchedulerRetainsPlannedIdentifiersWhenSystemAddFails() async throws {
        let center = RecordingCourseNotificationCenter()
        center.setAddFailureEnabled(true)
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = try date("2026-03-02 06:00")
        let scheduler = UserNotificationCourseScheduler(
            center: center,
            defaults: defaults,
            now: { fixedNow }
        )
        let request = try XCTUnwrap(DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course()]),
            after: fixedNow
        ).first)

        do {
            try await scheduler.replacePending(with: [request], revision: 6)
            XCTFail("Expected the notification center failure to propagate.")
        } catch NotificationTestError.unavailable {
            // The identifier must remain persisted so the lifecycle cleanup can remove it.
        }
        center.setAddFailureEnabled(false)
        scheduler.cancelPending(revision: 7)

        XCTAssertTrue(try XCTUnwrap(center.pendingRemovalBatches.last).contains(
            "daily-course-summary.2026-03-02.revision-6"
        ))
    }

    func testSchedulerRejectsOlderRevisionAfterCancellation() async throws {
        let center = RecordingCourseNotificationCenter()
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = try date("2026-03-02 06:00")
        let scheduler = UserNotificationCourseScheduler(
            center: center,
            defaults: defaults,
            now: { fixedNow }
        )
        let request = try XCTUnwrap(DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course()]),
            after: fixedNow
        ).first)

        scheduler.cancelPending(revision: 9)
        try await scheduler.replacePending(with: [request], revision: 8)

        XCTAssertTrue(center.addedIdentifiers.isEmpty)
    }

    func testNewerReplacementUsesDistinctIdentifierAndRemovesOlderBatch() async throws {
        let center = RecordingCourseNotificationCenter()
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = try date("2026-03-02 06:00")
        let scheduler = UserNotificationCourseScheduler(
            center: center,
            defaults: defaults,
            now: { fixedNow }
        )
        let request = try XCTUnwrap(DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course()]),
            after: fixedNow
        ).first)

        try await scheduler.replacePending(with: [request], revision: 10)
        try await scheduler.replacePending(with: [request], revision: 11)

        XCTAssertEqual(center.addedIdentifiers, [
            "daily-course-summary.2026-03-02.revision-10",
            "daily-course-summary.2026-03-02.revision-11"
        ])
        XCTAssertTrue(try XCTUnwrap(center.pendingRemovalBatches.last).contains(
            "daily-course-summary.2026-03-02.revision-10"
        ))
        XCTAssertEqual(
            defaults.stringArray(forKey: "dailyCourseNotificationIdentifiers"),
            ["daily-course-summary.2026-03-02.revision-11"]
        )
    }

    @MainActor
    func testColdLaunchClearsLegacyNotificationsWhenSwitchIsOff() {
        let scheduler = RecordingNotificationScheduler(
            authorization: .authorized,
            requestResult: true
        )
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = makeModel(notificationScheduler: scheduler, defaults: defaults)

        XCTAssertEqual(scheduler.cancelledRevisions, [1])
        XCTAssertTrue(scheduler.replacements.isEmpty)
    }

    @MainActor
    func testReturningActiveRechecksRevokedPermissionAndSynchronizesSwitch() async throws {
        let scheduler = RecordingNotificationScheduler(
            authorization: .authorized,
            requestResult: true
        )
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "dailyCourseNotificationsEnabled")
        let model = makeModel(
            notificationScheduler: scheduler,
            defaults: defaults,
            credentials: Credentials(account: "fixture-account", password: "fixture-password"),
            storedSchedule: schedule(courses: [course()])
        )
        try await waitUntil { !scheduler.replacements.isEmpty }

        scheduler.setAuthorization(.denied)
        model.refreshDailyCourseNotificationAuthorization()
        try await waitUntil { !model.dailyCourseNotificationsEnabled }

        XCTAssertFalse(defaults.bool(forKey: "dailyCourseNotificationsEnabled"))
        XCTAssertEqual(model.dailyCourseNotificationStatusMessage, "通知权限未开启，未安排课程摘要")
        XCTAssertFalse(scheduler.cancelledRevisions.isEmpty)
    }

    @MainActor
    func testAccountChangeAndLocalClearSubmitCancellationBeforeReturning() {
        let scheduler = RecordingNotificationScheduler(
            authorization: .authorized,
            requestResult: true
        )
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = makeModel(
            notificationScheduler: scheduler,
            defaults: defaults,
            credentials: Credentials(account: "fixture-account", password: "fixture-password"),
            storedSchedule: schedule(courses: [course()])
        )
        XCTAssertEqual(scheduler.cancelledRevisions, [1])

        model.account = "replacement-account"
        model.password = "replacement-password"
        XCTAssertTrue(model.saveSettings())
        XCTAssertEqual(scheduler.cancelledRevisions, [1, 2])

        model.clearLocalData()
        XCTAssertEqual(scheduler.cancelledRevisions, [1, 2, 3])
    }

    private func schedule(courses: [Course]) -> ScheduleSnapshot {
        ScheduleSnapshot(
            termID: "fixture-term",
            termStartDate: "2026-03-02",
            fetchedAt: "2026-03-01T12:00:00+08:00",
            courses: courses
        )
    }

    private func course(
        id: String = "course-1",
        weekday: Int = 1,
        weeks: [Int] = [1],
        examWeeks: [Int] = []
    ) -> Course {
        Course(
            id: id,
            name: "数据挖掘",
            teacher: "测试教师",
            room: "教二楼-335",
            weekText: "1周",
            weekNumbers: weeks,
            examWeekNumbers: examWeeks,
            weekday: weekday,
            startSlot: 2,
            endSlot: 2,
            sectionText: "第3节",
            timeRange: "09:50-10:35"
        )
    }

    private func date(_ value: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.shanghai.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: value))
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "DailyCourseNotificationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName) ?? .standard, suiteName)
    }

    @MainActor
    private func makeModel(
        notificationScheduler: any DailyCourseNotificationScheduling,
        defaults: UserDefaults,
        credentials: Credentials? = nil,
        storedSchedule: ScheduleSnapshot? = nil
    ) -> AppModel {
        AppModel(
            credentialStore: NotificationTestCredentialStore(credentials: credentials),
            scheduleStore: NotificationTestScheduleStore(schedule: storedSchedule),
            scheduleClient: NotificationTestScheduleClient(),
            classroomStore: NotificationTestClassroomStore(),
            classroomClient: NotificationTestClassroomClient(),
            holidayStore: NotificationTestHolidayStore(),
            holidayClient: NotificationTestHolidayClient(),
            calendarImporter: NotificationTestCalendarImporter(),
            dailyCourseNotificationScheduler: notificationScheduler,
            defaults: defaults
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for asynchronous model reconciliation.")
    }
}

private final class RecordingNotificationScheduler: DailyCourseNotificationScheduling, @unchecked Sendable {
    struct Replacement: Sendable {
        let requests: [DailyCourseNotificationRequest]
        let revision: UInt64
    }

    private let lock = NSLock()
    private var authorization: DailyCourseNotificationAuthorization
    private let requestResult: Bool
    private var storedCancelledRevisions = [UInt64]()
    private var storedReplacements = [Replacement]()

    init(authorization: DailyCourseNotificationAuthorization, requestResult: Bool) {
        self.authorization = authorization
        self.requestResult = requestResult
    }

    var cancelledRevisions: [UInt64] {
        lock.withLock { storedCancelledRevisions }
    }

    var replacements: [Replacement] {
        lock.withLock { storedReplacements }
    }

    func setAuthorization(_ authorization: DailyCourseNotificationAuthorization) {
        lock.withLock { self.authorization = authorization }
    }

    func authorizationStatus() async -> DailyCourseNotificationAuthorization {
        lock.withLock { authorization }
    }
    func requestAuthorization() async throws -> Bool { requestResult }

    func replacePending(
        with requests: [DailyCourseNotificationRequest],
        revision: UInt64
    ) async throws {
        lock.withLock {
            storedReplacements.append(Replacement(requests: requests, revision: revision))
        }
    }

    func cancelPending(revision: UInt64) {
        lock.withLock { storedCancelledRevisions.append(revision) }
    }
}

private final class RecordingCourseNotificationCenter: CourseNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFailAdd = false
    private var storedAddedIdentifiers = [String]()
    private var storedPendingRemovalBatches = [[String]]()
    private var storedDeliveredRemovalBatches = [[String]]()

    var addedIdentifiers: [String] { lock.withLock { storedAddedIdentifiers } }
    var pendingRemovalBatches: [[String]] { lock.withLock { storedPendingRemovalBatches } }
    var deliveredRemovalBatches: [[String]] { lock.withLock { storedDeliveredRemovalBatches } }

    func setAddFailureEnabled(_ enabled: Bool) {
        lock.withLock { shouldFailAdd = enabled }
    }

    func authorizationStatus() async -> DailyCourseNotificationAuthorization { .authorized }
    func requestAuthorization() async throws -> Bool { true }

    func add(
        identifier: String,
        title _: String,
        body _: String,
        fireDate _: Date
    ) async throws {
        let shouldFail = lock.withLock {
            storedAddedIdentifiers.append(identifier)
            return shouldFailAdd
        }
        if shouldFail { throw NotificationTestError.unavailable }
    }

    func removePending(withIdentifiers identifiers: [String]) {
        lock.withLock { storedPendingRemovalBatches.append(identifiers) }
    }

    func removeDelivered(withIdentifiers identifiers: [String]) {
        lock.withLock { storedDeliveredRemovalBatches.append(identifiers) }
    }
}

private enum NotificationTestError: Error {
    case unavailable
}

private final class NotificationTestCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?

    init(credentials: Credentials?) {
        self.credentials = credentials
    }

    func load() throws -> Credentials? { lock.withLock { credentials } }
    func save(_ credentials: Credentials) throws { lock.withLock { self.credentials = credentials } }
    func clear() throws { lock.withLock { credentials = nil } }
}

private final class NotificationTestScheduleStore: ScheduleStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var schedule: ScheduleSnapshot?

    init(schedule: ScheduleSnapshot?) {
        self.schedule = schedule
    }

    func load() throws -> ScheduleSnapshot? { lock.withLock { schedule } }
    func save(_ schedule: ScheduleSnapshot) throws { lock.withLock { self.schedule = schedule } }
    func clear() throws { lock.withLock { schedule = nil } }
}

private struct NotificationTestScheduleClient: ScheduleFetching {
    func fetch(
        credentials _: Credentials,
        fallbackTermID _: String,
        fallbackTermStartDate _: String
    ) async throws -> ScheduleSnapshot {
        throw NotificationTestError.unavailable
    }
}

private struct NotificationTestClassroomStore: ClassroomStoring {
    func load() throws -> ClassroomsCache? { nil }
    func save(_: ClassroomsCache) throws {}
    func clear() throws {}
}

private struct NotificationTestClassroomClient: ClassroomFetching {
    func fetch(credentials _: Credentials, targetDate _: String) async throws -> ClassroomsCache {
        throw NotificationTestError.unavailable
    }
}

private struct NotificationTestHolidayStore: HolidayStoring {
    func load(year: Int) throws -> HolidaysSnapshot? {
        HolidaysSnapshot(
            year: year,
            source: "notification-test-fixture",
            fetchedAt: ISO8601DateFormatter().string(from: .now),
            items: []
        )
    }

    func save(_: HolidaysSnapshot) throws {}
    func clear() throws {}
}

private struct NotificationTestHolidayClient: HolidayFetching {
    func fetch(year _: Int) async throws -> HolidaysSnapshot {
        throw NotificationTestError.unavailable
    }
}

@MainActor
private struct NotificationTestCalendarImporter: CalendarImporting {
    func importSchedule(_: ScheduleSnapshot) async throws -> CalendarImportResult {
        throw NotificationTestError.unavailable
    }
}
