import XCTest
import UserNotifications
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class DailyCourseNotificationTests: XCTestCase {
    func testForegroundDelegateInstallationAndPresentationPolicy() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delegate = DailyCourseNotificationForegroundDelegate(defaults: defaults)
        let center = RecordingNotificationDelegateInstaller()
        let identifier = DailyCourseNotificationPlanner.identifierPrefix + "2026-03-02.revision-1"

        DailyCourseNotificationCenterConfiguration.installForegroundDelegate(
            center: center,
            delegate: delegate
        )

        XCTAssertTrue(center.delegate === delegate)
        XCTAssertFalse(defaults.bool(forKey: DailyCourseNotificationSettings.enabledKey))
        XCTAssertEqual(DailyCourseNotificationForegroundPolicy.presentationOptions(
            identifier: identifier,
            isEnabled: false
        ), [])
        XCTAssertEqual(DailyCourseNotificationForegroundPolicy.presentationOptions(
            identifier: "unrelated-notification",
            isEnabled: true
        ), [])

        let enabledOptions = DailyCourseNotificationForegroundPolicy.presentationOptions(
            identifier: identifier,
            isEnabled: true
        )
        XCTAssertTrue(enabledOptions.contains(.banner))
        XCTAssertTrue(enabledOptions.contains(.list))
        XCTAssertTrue(enabledOptions.contains(.sound))
    }

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

    func testReminderTimeDefaultsAndRejectsMalformedStoredValues() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(DailyCourseNotificationSettings.loadMinutes(defaults: defaults), 450)
        for invalid in [-1, 1440, "09:30", "600", true, 600.5] as [Any] {
            defaults.set(invalid, forKey: DailyCourseNotificationSettings.minutesKey)
            XCTAssertEqual(DailyCourseNotificationSettings.loadMinutes(defaults: defaults), 450)
        }
        for minutes in [0, 450, 600, 1439] {
            defaults.set(minutes, forKey: DailyCourseNotificationSettings.minutesKey)
            XCTAssertEqual(DailyCourseNotificationSettings.loadMinutes(defaults: defaults), minutes)
        }
    }

    func testPlannerUsesSelectedBeijingTimeAndOnlyFutureDelivery() throws {
        let snapshot = schedule(courses: [course(weeks: [1, 2])])
        for minutes in [0, 450, 600, 1439] {
            let requests = DailyCourseNotificationPlanner.requests(
                for: snapshot, after: try date("2026-03-01 23:59"),
                dailyCourseNotificationMinutes: minutes
            )
            let fireDate = try XCTUnwrap(requests.first).fireDate
            let parts = Calendar.shanghai.dateComponents([.day, .hour, .minute], from: fireDate)
            XCTAssertEqual(parts.day, 2)
            XCTAssertEqual(parts.hour, minutes / 60)
            XCTAssertEqual(parts.minute, minutes % 60)
            let next = DailyCourseNotificationPlanner.requests(
                for: snapshot, after: fireDate, dailyCourseNotificationMinutes: minutes
            )
            XCTAssertEqual(next.count, 1)
            XCTAssertEqual(next.first?.identifier, "daily-course-summary.2026-03-09")
        }
        let changedLater = DailyCourseNotificationPlanner.requests(
            for: snapshot, after: try date("2026-03-02 08:00"), dailyCourseNotificationMinutes: 600
        )
        XCTAssertEqual(changedLater.first?.fireDate, try date("2026-03-02 10:00"))
        XCTAssertEqual(DailyCourseNotificationPlanner.requests(
            for: snapshot, after: try date("2026-03-02 06:00"), dailyCourseNotificationMinutes: 1440
        ).first?.fireDate, try date("2026-03-02 07:30"))
    }

    func testPlannerSelectedMidnightAcrossYearAndTeachingWeekBoundary() throws {
        let snapshot = schedule(courses: [
            course(id: "new-year", weekday: 4, weeks: [1]),
            course(id: "next-week", weekday: 1, weeks: [2])
        ], termStartDate: "2025-12-29")
        let requests = DailyCourseNotificationPlanner.requests(
            for: snapshot, after: try date("2025-12-31 23:59"), dailyCourseNotificationMinutes: 0
        )
        XCTAssertEqual(requests.map(\.fireDate), [
            try date("2026-01-01 00:00"), try date("2026-01-05 00:00")
        ])
    }

    @MainActor
    func testTimeChangePersistsAndReschedulesLatestRevisionWithoutEnablingNotifications() async throws {
        let scheduler = RecordingNotificationScheduler(authorization: .authorized, requestResult: true)
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: DailyCourseNotificationSettings.enabledKey)
        let model = makeModel(notificationScheduler: scheduler, defaults: defaults,
            credentials: Credentials(account: "fixture-account", password: "fixture-password"),
            storedSchedule: schedule(courses: [course(weeks: [1, 2])]))
        try await waitUntil { !scheduler.replacements.isEmpty }
        let initialRevision = try XCTUnwrap(scheduler.replacements.last).revision
        XCTAssertTrue(model.setDailyCourseNotificationMinutes(600))
        XCTAssertTrue(model.setDailyCourseNotificationMinutes(615))
        try await waitUntil {
            scheduler.replacements.last?.requests.first?.fireDate == (try? self.date("2026-03-02 10:15"))
        }
        XCTAssertGreaterThan(try XCTUnwrap(scheduler.replacements.last).revision, initialRevision)
        XCTAssertEqual(defaults.integer(forKey: DailyCourseNotificationSettings.minutesKey), 615)
        XCTAssertFalse(model.setDailyCourseNotificationMinutes(-1))
        XCTAssertFalse(model.setDailyCourseNotificationMinutes(1440))
        XCTAssertEqual(model.dailyCourseNotificationMinutes, 615)

        model.setDailyCourseNotificationsEnabled(false)
        let replacements = scheduler.replacements.count
        XCTAssertTrue(model.setDailyCourseNotificationMinutes(0))
        await Task.yield()
        XCTAssertFalse(model.dailyCourseNotificationsEnabled)
        XCTAssertEqual(scheduler.replacements.count, replacements)
        XCTAssertEqual(defaults.integer(forKey: DailyCourseNotificationSettings.minutesKey), 0)
        model.clearLocalData()
        XCTAssertEqual(model.dailyCourseNotificationMinutes, 450)
        XCTAssertNil(defaults.object(forKey: DailyCourseNotificationSettings.minutesKey))
    }

    @MainActor
    func testTimeChangeRestoresPreferenceAndHonorsRevokedPermission() async throws {
        let scheduler = RecordingNotificationScheduler(authorization: .denied, requestResult: true)
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(1439, forKey: DailyCourseNotificationSettings.minutesKey)
        let model = makeModel(notificationScheduler: scheduler, defaults: defaults)
        XCTAssertEqual(model.dailyCourseNotificationMinutes, 1439)
        model.setDailyCourseNotificationsEnabled(true)
        XCTAssertTrue(model.setDailyCourseNotificationMinutes(600))
        try await waitUntil { !model.dailyCourseNotificationsEnabled }
        XCTAssertTrue(scheduler.replacements.isEmpty)
        XCTAssertEqual(model.dailyCourseNotificationMinutes, 600)
        XCTAssertFalse(defaults.bool(forKey: DailyCourseNotificationSettings.enabledKey))
    }

    @MainActor
    func testTimeChangeImmediatelyCancelsOldRequestsWhileAuthorizationIsSuspended() async throws {
        let scheduler = RecordingNotificationScheduler(authorization: .authorized, requestResult: true)
        let (defaults, suiteName) = isolatedDefaults()
        defer {
            scheduler.resumeAuthorizationQueries()
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(true, forKey: DailyCourseNotificationSettings.enabledKey)
        let model = makeModel(notificationScheduler: scheduler, defaults: defaults,
            credentials: Credentials(account: "fixture-account", password: "fixture-password"),
            storedSchedule: schedule(courses: [course()]),
            now: try date("2026-03-02 07:29").addingTimeInterval(59))
        try await waitUntil { !scheduler.replacements.isEmpty }
        let original = try XCTUnwrap(scheduler.replacements.last)
        XCTAssertEqual(original.requests.first?.fireDate, try date("2026-03-02 07:30"))
        let replacementCount = scheduler.replacements.count
        let cancellationCount = scheduler.cancelledRevisions.count

        scheduler.pauseAuthorizationQueries()
        XCTAssertTrue(model.setDailyCourseNotificationMinutes(555))
        // No suspension between the edit and these checks: cancellation must
        // already have been submitted before the permission query can return.
        XCTAssertEqual(scheduler.cancelledRevisions.count, cancellationCount + 1)
        let cancelledRevision = try XCTUnwrap(scheduler.cancelledRevisions.last)
        XCTAssertGreaterThan(cancelledRevision, original.revision)
        XCTAssertTrue(model.dailyCourseNotificationsEnabled)
        XCTAssertTrue(defaults.bool(forKey: DailyCourseNotificationSettings.enabledKey))

        try await waitUntil { scheduler.pendingAuthorizationQueryCount == 1 }
        XCTAssertEqual(scheduler.replacements.count, replacementCount)
        scheduler.resumeAuthorizationQueries()
        try await waitUntil { scheduler.replacements.count > replacementCount }
        let replacement = try XCTUnwrap(scheduler.replacements.last)
        XCTAssertGreaterThan(replacement.revision, cancelledRevision)
        XCTAssertEqual(replacement.requests.first?.fireDate, try date("2026-03-02 09:15"))
        XCTAssertEqual(model.dailyCourseNotificationMinutes, 555)
        XCTAssertTrue(model.dailyCourseNotificationsEnabled)
    }

    @MainActor
    func testReviewTimePreviewDoesNotOverwriteLivePreference() {
        let scheduler = RecordingNotificationScheduler(authorization: .authorized, requestResult: true)
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(600, forKey: DailyCourseNotificationSettings.minutesKey)
        let model = makeModel(notificationScheduler: scheduler, defaults: defaults)
        model.enterReviewDemo()
        XCTAssertTrue(model.isReviewDemo)
        XCTAssertEqual(model.dailyCourseNotificationMinutes, 450)
        XCTAssertTrue(model.setDailyCourseNotificationMinutes(615))
        XCTAssertEqual(defaults.integer(forKey: DailyCourseNotificationSettings.minutesKey), 600)
        XCTAssertTrue(scheduler.replacements.isEmpty)
        model.exitReviewDemo()
        XCTAssertEqual(model.dailyCourseNotificationMinutes, 600)
    }

    func testPlannerRejectsInvalidContractDates() throws {
        let now = try date("2026-03-02 06:00")

        for value in ["2026-02-30", "2026-13-01"] {
            XCTAssertTrue(DailyCourseNotificationPlanner.requests(
                for: schedule(courses: [course()], termStartDate: value),
                after: now,
                scanDayLimit: 1
            ).isEmpty, value)
        }
    }

    func testPlannerIgnoresLegacyExamWeekMetadata() throws {
        let requests = DailyCourseNotificationPlanner.requests(
            for: schedule(courses: [course(examWeeks: [1])]),
            after: try date("2026-03-02 06:00"),
            scanDayLimit: 1
        )

        XCTAssertEqual(requests.first?.body, "09:50-10:35 数据挖掘 @ 教二楼-335")
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
            dailyCourseNotificationMinutes: 615,
            now: try date("2026-03-02 06:00"),
            revision: 9
        )

        XCTAssertEqual(cleared, .waitingForSchedule)
        XCTAssertEqual(replaced, .scheduled(1))
        XCTAssertEqual(scheduler.cancelledRevisions, [8])
        XCTAssertEqual(scheduler.replacements.map(\.revision), [9])
        XCTAssertEqual(scheduler.replacements.first?.requests.count, 1)
        XCTAssertEqual(scheduler.replacements.first?.requests.first?.fireDate, try date("2026-03-02 10:15"))
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
        let pendingRemovalCount = center.pendingRemovalBatches.count
        let deliveredRemovalCount = center.deliveredRemovalBatches.count
        scheduler.cancelPending(revision: 5)
        try await waitForNotificationCleanup {
            center.pendingRemovalBatches.count > pendingRemovalCount
                && center.deliveredRemovalBatches.count > deliveredRemovalCount
        }

        XCTAssertEqual(center.addedIdentifiers, ["daily-course-summary.2026-03-02.revision-4"])
        XCTAssertTrue(try XCTUnwrap(center.pendingRemovalBatches.last).contains(
            "daily-course-summary.2026-03-02.revision-4"
        ))
        XCTAssertTrue(try XCTUnwrap(center.deliveredRemovalBatches.last).contains(
            "daily-course-summary.2026-03-02.revision-4"
        ))
        XCTAssertEqual(defaults.stringArray(forKey: "dailyCourseNotificationIdentifiers"), [])
    }

    func testSchedulerCancellationDoesNotBlockCallerDuringSystemCleanup() async throws {
        let center = RecordingCourseNotificationCenter(pendingRemovalDelay: 0.75)
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scheduler = UserNotificationCourseScheduler(center: center, defaults: defaults)

        let startedAt = Date()
        scheduler.cancelPending(revision: 1)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 0.25)
        try await waitForNotificationCleanup {
            !center.pendingRemovalBatches.isEmpty && !center.deliveredRemovalBatches.isEmpty
        }
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
        let pendingRemovalCount = center.pendingRemovalBatches.count
        scheduler.cancelPending(revision: 7)
        try await waitForNotificationCleanup {
            center.pendingRemovalBatches.count > pendingRemovalCount
        }

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
    func testAuthorizationStatusTimeoutConvergesModelState() async throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scheduler = UserNotificationCourseScheduler(
            center: NonRespondingCourseNotificationCenter(mode: .authorizationStatus),
            defaults: defaults
        )
        defaults.set(true, forKey: "dailyCourseNotificationsEnabled")
        defaults.set(AppLanguage.english.rawValue, forKey: AppLocalization.defaultsKey)
        let model = makeModel(
            notificationScheduler: scheduler,
            notificationAuthorizationTimeout: .milliseconds(50),
            defaults: defaults,
            credentials: Credentials(account: "fixture-account", password: "fixture-password"),
            storedSchedule: schedule(courses: [course()])
        )

        try await waitUntil { !model.dailyCourseNotificationsEnabled }

        XCTAssertFalse(defaults.bool(forKey: "dailyCourseNotificationsEnabled"))
        XCTAssertEqual(
            model.dailyCourseNotificationStatusMessage,
            model.localized("课程摘要安排失败：")
                + model.localized("通知权限状态读取超时，请在系统设置中确认通知权限。")
        )
    }

    @MainActor
    func testAuthorizationRequestTimeoutLeavesConfirmingState() async throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scheduler = UserNotificationCourseScheduler(
            center: NonRespondingCourseNotificationCenter(mode: .authorizationRequest),
            defaults: defaults
        )
        defaults.set(AppLanguage.english.rawValue, forKey: AppLocalization.defaultsKey)
        let model = makeModel(
            notificationScheduler: scheduler,
            notificationAuthorizationTimeout: .milliseconds(50),
            defaults: defaults,
            credentials: Credentials(account: "fixture-account", password: "fixture-password"),
            storedSchedule: schedule(courses: [course()])
        )

        model.setDailyCourseNotificationsEnabled(true)
        try await waitUntil { !model.dailyCourseNotificationsEnabled }

        XCTAssertEqual(
            model.dailyCourseNotificationStatusMessage,
            model.localized("课程摘要安排失败：")
                + model.localized("通知权限状态读取超时，请在系统设置中确认通知权限。")
        )
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

    private func schedule(
        courses: [Course],
        termStartDate: String = "2026-03-02"
    ) -> ScheduleSnapshot {
        ScheduleSnapshot(
            termID: "2025-2026-2",
            termStartDate: termStartDate,
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
        notificationAuthorizationTimeout: Duration = .seconds(8),
        defaults: UserDefaults,
        credentials: Credentials? = nil,
        storedSchedule: ScheduleSnapshot? = nil,
        now: Date = DailyCourseNotificationTests.modelNow
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
            dailyCourseNotificationAuthorizationTimeout: notificationAuthorizationTimeout,
            now: { now },
            defaults: defaults
        )
    }

    private static let modelNow = Calendar.shanghai.date(
        from: DateComponents(year: 2026, month: 3, day: 2, hour: 6)
    )!

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

private func waitForNotificationCleanup(
    timeout: Duration = .seconds(10),
    condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "Timed out waiting for notification cleanup.")
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
    private var authorizationPaused = false
    private var pendingAuthorizationQueries = [CheckedContinuation<DailyCourseNotificationAuthorization, Never>]()

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

    var pendingAuthorizationQueryCount: Int {
        lock.withLock { pendingAuthorizationQueries.count }
    }

    func pauseAuthorizationQueries() {
        lock.withLock { authorizationPaused = true }
    }

    func resumeAuthorizationQueries() {
        let (continuations, status) = lock.withLock {
            authorizationPaused = false
            let continuations = pendingAuthorizationQueries
            pendingAuthorizationQueries.removeAll()
            return (continuations, authorization)
        }
        continuations.forEach { $0.resume(returning: status) }
    }

    func authorizationStatus(timeout _: Duration) async throws -> DailyCourseNotificationAuthorization {
        await withCheckedContinuation { continuation in
            let status: DailyCourseNotificationAuthorization? = lock.withLock {
                if authorizationPaused {
                    pendingAuthorizationQueries.append(continuation)
                    return nil
                }
                return authorization
            }
            if let status { continuation.resume(returning: status) }
        }
    }
    func requestAuthorization(timeout _: Duration) async throws -> Bool { requestResult }

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
    private let pendingRemovalDelay: TimeInterval
    private var shouldFailAdd = false
    private var storedAddedIdentifiers = [String]()
    private var storedPendingRemovalBatches = [[String]]()
    private var storedDeliveredRemovalBatches = [[String]]()

    var addedIdentifiers: [String] { lock.withLock { storedAddedIdentifiers } }
    var pendingRemovalBatches: [[String]] { lock.withLock { storedPendingRemovalBatches } }
    var deliveredRemovalBatches: [[String]] { lock.withLock { storedDeliveredRemovalBatches } }

    init(pendingRemovalDelay: TimeInterval = 0) {
        self.pendingRemovalDelay = pendingRemovalDelay
    }

    func setAddFailureEnabled(_ enabled: Bool) {
        lock.withLock { shouldFailAdd = enabled }
    }

    func authorizationStatus(
        completion: @escaping @Sendable (DailyCourseNotificationAuthorization) -> Void
    ) {
        completion(.authorized)
    }

    func requestAuthorization(
        completion: @escaping @Sendable (Result<Bool, any Error>) -> Void
    ) {
        completion(.success(true))
    }

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
        if pendingRemovalDelay > 0 {
            Thread.sleep(forTimeInterval: pendingRemovalDelay)
        }
        lock.withLock { storedPendingRemovalBatches.append(identifiers) }
    }

    func removeDelivered(withIdentifiers identifiers: [String]) {
        lock.withLock { storedDeliveredRemovalBatches.append(identifiers) }
    }
}

private final class NonRespondingCourseNotificationCenter: CourseNotificationCenter, @unchecked Sendable {
    enum Mode {
        case authorizationStatus
        case authorizationRequest
    }

    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func authorizationStatus(
        completion: @escaping @Sendable (DailyCourseNotificationAuthorization) -> Void
    ) {
        if mode == .authorizationRequest { completion(.notDetermined) }
    }

    func requestAuthorization(
        completion _: @escaping @Sendable (Result<Bool, any Error>) -> Void
    ) {}

    func add(
        identifier _: String,
        title _: String,
        body _: String,
        fireDate _: Date
    ) async throws {}

    func removePending(withIdentifiers _: [String]) {}
    func removeDelivered(withIdentifiers _: [String]) {}
}

private enum NotificationTestError: Error {
    case unavailable
}

private final class RecordingNotificationDelegateInstaller: UserNotificationCenterDelegateInstalling {
    var delegate: (any UNUserNotificationCenterDelegate)?
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


    func importFavorites(_: [PublicDeadlineItem]) async throws -> CalendarImportResult {
        throw NotificationTestError.unavailable
    }
}
