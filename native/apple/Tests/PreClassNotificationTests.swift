import XCTest
import UserNotifications
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class PreClassNotificationTests: XCTestCase {
    func testOffsetsDefaultAndStrictPersistedFallback() {
        let suite = "PreClass.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(defaults.bool(forKey: PreClassNotificationSettings.enabledKey))
        XCTAssertEqual(PreClassNotificationSettings.loadOffsets(defaults: defaults), [10])
        let corrupt: [Any] = [[], [0], [-1], [1441], [true], [1.5], ["10"], [10, 10], [1, 2, 3, 4, 5, 6], "10"]
        for value in corrupt {
            defaults.set(value, forKey: PreClassNotificationSettings.offsetsKey)
            XCTAssertEqual(PreClassNotificationSettings.loadOffsets(defaults: defaults), [10], "\(value)")
        }
        defaults.set([1440, 10, 1], forKey: PreClassNotificationSettings.offsetsKey)
        XCTAssertEqual(PreClassNotificationSettings.loadOffsets(defaults: defaults), [1440, 10, 1])
    }

    func testOffsetInputRejectsDuplicatesFractionsAndOutOfRangeWithoutClamping() {
        XCTAssertEqual(PreClassNotificationSettings.parse(["1440", "10", "1"]), [1440, 10, 1])
        for value in [[""], ["0"], ["1441"], ["1.5"], ["+10"], ["1e2"], ["１０"], ["10", "10"], []] {
            XCTAssertNil(PreClassNotificationSettings.parse(value), "\(value)")
        }
    }

    func testOneOccurrenceAcrossSeveralLessonPeriodsAndDuplicateRows() {
        let course = Self.course(endSlot: 3)
        let schedule = Self.schedule(courses: [course, course])
        let reminders = PreClassNotificationPlanner.requests(for: schedule, after: Self.now, offsets: [30, 10])
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.fireDate), [Self.date(7, 30), Self.date(7, 50)])
        XCTAssertEqual(Set(reminders.map(\.identifier)).count, 2)
        XCTAssertTrue(reminders.allSatisfy { $0.body.contains("08:00") })
        // The same course has another actual start, not another lesson period.
        let otherStart = Self.course(startSlot: 2, endSlot: 3)
        XCTAssertEqual(PreClassNotificationPlanner.requests(
            for: Self.schedule(courses: [course, otherStart]), after: Self.now).count, 2)
    }

    func testTimedExamOverridesCourseAndUnknownTimeExamDoesNotCreateReminder() {
        let exams = ExamSchedule(termID: "2025-2026-2", accountKey: "fixture", fetchedAt: "", status: "fresh", message: "", items: [
            Self.exam(id: "timed", start: "08:20", end: "09:20"),
            Self.exam(id: "unknown", start: "", end: "")
        ])
        let requests = PreClassNotificationPlanner.requests(
            for: Self.schedule(courses: [Self.course(endSlot: 1)], exams: exams), after: Self.now)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.fireDate, Self.date(8, 10))
        XCTAssertEqual(requests.first?.title, "考试将在 10 分钟后开始")
        XCTAssertTrue(requests.first?.body.contains("示例考试") == true)
        XCTAssertFalse(requests.first?.body.contains("示例课程") == true)
    }

    func testExpiredReminderIsNotReplayedAtBoundary() {
        let schedule = Self.schedule(courses: [Self.course()])
        XCTAssertEqual(PreClassNotificationPlanner.requests(for: schedule, after: Self.date(7, 49)).count, 1)
        XCTAssertTrue(PreClassNotificationPlanner.requests(for: schedule, after: Self.date(7, 50)).isEmpty)
        XCTAssertTrue(PreClassNotificationPlanner.requests(for: schedule, after: Self.date(8, 10)).isEmpty)
        XCTAssertTrue(PreClassNotificationPlanner.requests(for: schedule, after: Self.now, offsets: [0]).isEmpty)
    }

    func testShanghaiLeadTimeCanCrossYearBoundary() {
        let schedule = Self.schedule(courses: [Self.course(weekday: 5)], start: "2026-12-28")
        let now = Calendar.shanghai.date(from: DateComponents(year: 2026, month: 12, day: 30))!
        let reminders = PreClassNotificationPlanner.requests(for: schedule, after: now, offsets: [1440, 600])
        XCTAssertEqual(reminders.map { ISO8601DateFormatter().string(from: $0.fireDate) }, [
            "2026-12-31T00:00:00Z", "2026-12-31T14:00:00Z"
        ])
        XCTAssertTrue(reminders.allSatisfy { $0.body.contains("2027-01-01 08:00") })
    }

    func testInvalidContractDateAndInvalidLessonTimesAreExcluded() {
        XCTAssertTrue(PreClassNotificationPlanner.requests(
            for: Self.schedule(courses: [Self.course()], start: "2026-02-30"), after: Self.now).isEmpty)
        XCTAssertTrue(PreClassNotificationPlanner.requests(
            for: Self.schedule(courses: [Self.course(startSlot: -1)]), after: Self.now).isEmpty)
    }

    func testReminderContentUsesSelectedLanguageWithoutTranslatingCourseNames() {
        let schedule = Self.schedule(courses: [Self.course()])
        let chinese = PreClassNotificationPlanner.requests(for: schedule, after: Self.now, language: .simplifiedChinese)
        let english = PreClassNotificationPlanner.requests(for: schedule, after: Self.now, language: .english)
        XCTAssertEqual(chinese.first?.title, "课程将在 10 分钟后开始")
        XCTAssertEqual(english.first?.title, "Class starts in 10 minutes")
        XCTAssertTrue(english.first?.body.contains("示例课程") == true)
        XCTAssertEqual(english.first?.identifier, chinese.first?.identifier)
        XCTAssertEqual(DailyCourseNotificationPlanner.requests(for: schedule, after: Self.now,
                                                              language: .english).first?.title, "Today's classes · 1")
    }

    func testMergedBudgetKeepsEarliestBothCategoriesAndRefillsInForeground() {
        let schedule = Self.schedule(courses: (1 ... 7).map { Self.course(weekday: $0, weeks: Array(1 ... 30)) })
        func plan(after now: Date) -> [DailyCourseNotificationRequest] {
            CourseNotificationPlan.earliest(
                DailyCourseNotificationPlanner.requests(for: schedule, after: now)
                    + PreClassNotificationPlanner.requests(for: schedule, after: now, offsets: [30, 10]), after: now)
        }
        let initial = plan(after: Self.now)
        XCTAssertEqual(initial.count, 63)
        XCTAssertTrue(initial.contains { $0.identifier.hasPrefix("daily-course-summary.") })
        XCTAssertTrue(initial.contains { $0.identifier.hasPrefix("pre-class-reminder.") })
        XCTAssertEqual(initial.map(\.fireDate), initial.map(\.fireDate).sorted())
        let later = Self.now.addingTimeInterval(7 * 86400)
        let refilled = plan(after: later)
        XCTAssertEqual(refilled.count, 63)
        XCTAssertTrue(refilled.allSatisfy { $0.fireDate > later })
        XCTAssertGreaterThan(refilled.last!.fireDate, initial.last!.fireDate)
    }

    func testForegroundPresentationHonorsEachIndependentSwitch() {
        XCTAssertTrue(DailyCourseNotificationForegroundPolicy.presentationOptions(
            identifier: "pre-class-reminder.x", isEnabled: true).isEmpty)
        XCTAssertFalse(DailyCourseNotificationForegroundPolicy.presentationOptions(
            identifier: "pre-class-reminder.x", isEnabled: false, preClassEnabled: true).isEmpty)
        XCTAssertTrue(DailyCourseNotificationForegroundPolicy.presentationOptions(
            identifier: "daily-course-summary.x", isEnabled: false, preClassEnabled: true).isEmpty)
    }

    func testCategoryCancellationPreservesOtherPendingRequests() async throws {
        let fixture = Self.schedulerFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        try await fixture.scheduler.replacePending(with: Self.twoCategories(), revision: 1)
        fixture.scheduler.cancelPending(category: .preClass, revision: 2)
        try await Self.waitUntil { fixture.center.pending.count == 1 }
        XCTAssertTrue(fixture.center.pending.keys.allSatisfy { $0.hasPrefix("daily-course-summary.") })
        XCTAssertEqual(fixture.defaults.stringArray(forKey: "dailyCourseNotificationIdentifiers")?.count, 1)
        try await fixture.scheduler.replacePending(with: Self.twoCategories(), revision: 3)
        fixture.scheduler.cancelPending(category: .dailySummary, revision: 4)
        try await Self.waitUntil { fixture.center.pending.count == 1 }
        XCTAssertTrue(fixture.center.pending.keys.allSatisfy { $0.hasPrefix("pre-class-reminder.") })
    }

    func testLateAddFromOldRevisionCannotSurviveOrDeleteNewCategory() async throws {
        let fixture = Self.schedulerFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.center.pauseNextAdd()
        let old = Self.replaceAsynchronously(fixture.scheduler)
        try await Self.waitUntil { fixture.center.suspendedAdds == 1 }
        fixture.scheduler.invalidate(revision: 2)
        try await fixture.scheduler.replacePending(with: [Self.twoCategories()[1]], revision: 2)
        fixture.center.resumeAdds()
        try await old.value
        XCTAssertEqual(Array(fixture.center.pending.keys), ["daily-course-summary.test.revision-2"])
    }

    func testSingleAddFailureRetriesOnceContinuesOtherCategoryAndRecovers() async throws {
        let fixture = Self.schedulerFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.center.failPreClass(true)
        do {
            try await fixture.scheduler.replacePending(with: Self.twoCategories(), revision: 1)
            XCTFail("Expected the failed item to be reported")
        } catch PreClassTestFailure.unavailable { }
        XCTAssertEqual(fixture.center.attempts["pre-class-reminder.test.revision-1"], 2)
        XCTAssertEqual(Array(fixture.center.pending.keys), ["daily-course-summary.test.revision-1"])
        fixture.center.failPreClass(false)
        try await fixture.scheduler.replacePending(with: Self.twoCategories(), revision: 2)
        XCTAssertEqual(fixture.center.pending.count, 2)
        XCTAssertTrue(fixture.center.pending.keys.allSatisfy { $0.hasSuffix("revision-2") })
    }

    func testSchedulerFiltersExpiredRequestsAndCapsMergedInput() async throws {
        let fixture = Self.schedulerFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let future = (1 ... 90).map { index in
            DailyCourseNotificationRequest(identifier: "pre-class-reminder.\(index)",
                fireDate: Self.now.addingTimeInterval(Double(index) * 60), title: "", body: "")
        }
        let expired = DailyCourseNotificationRequest(identifier: "pre-class-reminder.expired", fireDate: Self.now, title: "", body: "")
        try await fixture.scheduler.replacePending(with: Array(future.reversed()) + [expired], revision: 1)
        XCTAssertEqual(fixture.center.pending.count, 63)
        XCTAssertTrue(fixture.center.pending.values.allSatisfy { $0 > Self.now })
        XCTAssertEqual(fixture.center.pending.values.max(), Self.now.addingTimeInterval(63 * 60))
    }

    private static let now = date(6, 0)
    private static func date(_ hour: Int, _ minute: Int) -> Date {
        Calendar.shanghai.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: hour, minute: minute))!
    }
    private static func course(weekday: Int = 1, weeks: [Int] = [1], startSlot: Int = 0, endSlot: Int = 1) -> Course {
        Course(id: "course-\(weekday)", name: "示例课程", teacher: "", room: "教学楼", weekText: "", weekNumbers: weeks,
               examWeekNumbers: [], weekday: weekday, startSlot: startSlot, endSlot: endSlot, sectionText: "", timeRange: "08:00-09:35")
    }
    private static func schedule(courses: [Course], start: String = "2026-03-02", exams: ExamSchedule? = nil) -> ScheduleSnapshot {
        ScheduleSnapshot(termID: "2025-2026-2", termStartDate: start, fetchedAt: "", courses: courses, examSchedule: exams)
    }
    private static func exam(id: String, start: String, end: String) -> ExamArrangement {
        ExamArrangement(id: id, name: "示例考试", date: "2026-03-02", startTime: start,
                        endTime: end, room: "考场", seat: "", timeText: "时间待定")
    }
    private static func twoCategories() -> [DailyCourseNotificationRequest] {
        [.init(identifier: "pre-class-reminder.test", fireDate: date(7, 20), title: "", body: ""),
         .init(identifier: "daily-course-summary.test", fireDate: date(7, 30), title: "", body: "")]
    }
    private static func replaceAsynchronously(_ scheduler: UserNotificationCourseScheduler) -> Task<Void, any Error> {
        Task.detached { try await scheduler.replacePending(with: twoCategories(), revision: 1) }
    }
    private static func schedulerFixture() -> (scheduler: UserNotificationCourseScheduler, center: PreClassTestCenter, defaults: UserDefaults, suite: String) {
        let suite = "PreClass.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let center = PreClassTestCenter()
        return (UserNotificationCourseScheduler(center: center, defaults: defaults, now: { Self.now }), center, defaults, suite)
    }
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for injected notification operation")
    }
}

private enum PreClassTestFailure: Error { case unavailable }

final class PreClassTestCenter: CourseNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPending = [String: Date]()
    private var storedAttempts = [String: Int]()
    private var storedDelivered = Set<String>()
    private var failingOffset: Int?
    private var watchedDefaults: UserDefaults?
    private var storedEnabledAtAdd = [Bool]()
    private var failReminders = false
    private var shouldPause = false
    private var continuations = [CheckedContinuation<Void, Never>]()
    var pending: [String: Date] { lock.withLock { storedPending } }
    var attempts: [String: Int] { lock.withLock { storedAttempts } }
    var delivered: Set<String> { lock.withLock { storedDelivered } }
    var preClassEnabledAtAdd: [Bool] { lock.withLock { storedEnabledAtAdd } }
    var suspendedAdds: Int { lock.withLock { continuations.count } }
    func failPreClass(_ value: Bool) { lock.withLock { failReminders = value } }
    func failOffset(_ value: Int?) { lock.withLock { failingOffset = value } }
    func watchPreferences(_ defaults: UserDefaults) { lock.withLock { watchedDefaults = defaults } }
    func deliverPending() {
        lock.withLock { storedDelivered.formUnion(storedPending.keys); storedPending = [:] }
    }
    func pauseNextAdd() { lock.withLock { shouldPause = true } }
    func resumeAdds() {
        let current = lock.withLock { let current = continuations; continuations = []; return current }
        current.forEach { $0.resume() }
    }
    func authorizationStatus(completion: @escaping @Sendable (DailyCourseNotificationAuthorization) -> Void) { completion(.authorized) }
    func requestAuthorization(completion: @escaping @Sendable (Result<Bool, any Error>) -> Void) { completion(.success(true)) }
    func add(identifier: String, title _: String, body _: String, fireDate: Date) async throws {
        let pause = lock.withLock {
            storedAttempts[identifier, default: 0] += 1
            if let watchedDefaults {
                storedEnabledAtAdd.append(watchedDefaults.bool(forKey: PreClassNotificationSettings.enabledKey))
            }
            let pause = shouldPause
            shouldPause = false
            return pause
        }
        if pause { await withCheckedContinuation { continuation in lock.withLock { continuations.append(continuation) } } }
        try lock.withLock {
            if failReminders && identifier.hasPrefix("pre-class-reminder.") { throw PreClassTestFailure.unavailable }
            if let failingOffset, identifier.contains(".\(failingOffset).revision-") { throw PreClassTestFailure.unavailable }
            storedPending[identifier] = fireDate
        }
    }
    func removePending(withIdentifiers identifiers: [String]) {
        lock.withLock { identifiers.forEach { storedPending.removeValue(forKey: $0) } }
    }
    func removeDelivered(withIdentifiers identifiers: [String]) {
        lock.withLock { storedDelivered.subtract(identifiers) }
    }
    func deliveredIdentifiers(completion: @escaping @Sendable ([String]) -> Void) {
        completion(lock.withLock { Array(storedDelivered) })
    }
}
