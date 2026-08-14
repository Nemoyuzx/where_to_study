import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class LocalDataClearTests: XCTestCase {
    func testHolidayLoadStateKeepsNewLoadWhenOldLoadFinishesAfterReset() throws {
        let year = 2026
        var loads = HolidayLoadState()
        let oldToken = try XCTUnwrap(loads.begin(year: year))

        loads.reset()
        let newToken = try XCTUnwrap(loads.begin(year: year))
        loads.finish(year: year, token: oldToken)

        XCTAssertNil(loads.begin(year: year))
        loads.finish(year: year, token: newToken)
        XCTAssertNotNil(loads.begin(year: year))
    }

    func testCredentialSaveDecisionPreservesOnlyTheSameStoredAccount() throws {
        XCTAssertEqual(
            try CredentialSettingsLogic.saveAction(
                account: " saved-account ",
                password: "",
                storedAccount: "saved-account",
                hasStoredPassword: true
            ),
            .preserve
        )

        XCTAssertThrowsError(try CredentialSettingsLogic.saveAction(
            account: "different-account",
            password: "",
            storedAccount: "saved-account",
            hasStoredPassword: true
        )) { error in
            XCTAssertEqual(error as? CredentialSettingsError, .passwordRequiredForChangedAccount)
        }

        XCTAssertEqual(
            try CredentialSettingsLogic.saveAction(
                account: " different-account ",
                password: "typed-value",
                storedAccount: "saved-account",
                hasStoredPassword: true
            ),
            .replace(Credentials(account: "different-account", password: "typed-value"))
        )
        XCTAssertEqual(
            try CredentialSettingsLogic.saveAction(
                account: "  ",
                password: "",
                storedAccount: "saved-account",
                hasStoredPassword: true
            ),
            .clear
        )
    }

    func testRequestCredentialsUseStoredValueOnlyForMatchingAccount() throws {
        let stored = Credentials(account: "saved-account", password: "stored-value")
        XCTAssertEqual(
            try CredentialSettingsLogic.credentialsForRequest(
                account: "saved-account",
                password: "",
                storedCredentials: stored
            ),
            stored
        )
        XCTAssertThrowsError(try CredentialSettingsLogic.credentialsForRequest(
            account: "different-account",
            password: "",
            storedCredentials: stored
        )) { error in
            XCTAssertEqual(error as? CredentialSettingsError, .passwordRequiredForChangedAccount)
        }
    }

    func testLaunchArgumentsSelectOnlyExplicitSampleModes() {
        XCTAssertFalse(AppRuntimeMode.live.isSample)
        XCTAssertFalse(AppRuntimeMode.sample(review: false).isReviewDemo)
        XCTAssertTrue(AppRuntimeMode.sample(review: true).isSample)
        XCTAssertTrue(AppRuntimeMode.sample(review: true).isReviewDemo)
    }

    @MainActor
    func testSampleModeBlocksAccountAndSystemMutations() {
        let suiteName = "ReviewDemoTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离的 UserDefaults。")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore(credentials: nil)
        let model = AppModel(
            runtimeMode: .sample(review: true),
            credentialStore: credentialStore,
            scheduleStore: InMemoryScheduleStore(schedule: Self.schedule),
            classroomStore: InMemoryClassroomStore(cache: Self.classrooms),
            holidayStore: FileHolidayStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )

        model.account = "must-not-save"
        model.password = "must-not-save"
        XCTAssertFalse(model.saveSettings())
        XCTAssertNil(try credentialStore.load())

        model.refreshSchedule()
        model.refreshClassrooms()
        model.importScheduleToCalendar()
        model.setDailyCourseNotificationsEnabled(true)

        XCTAssertEqual(model.statusMessage, "正在展示内置示例课表，未连接北邮服务")
        XCTAssertEqual(model.classroomStatusMessage, "正在展示内置示例空教室，未连接北邮服务")
        XCTAssertTrue(model.calendarImportStatusMessage.hasPrefix("示例模式已模拟同步 "))
        XCTAssertTrue(model.calendarImportStatusMessage.hasSuffix(" 个课程日期，未写入系统日历"))
        XCTAssertEqual(
            model.dailyCourseNotificationStatusMessage,
            "示例模式已模拟开启每日课程摘要，未申请通知权限"
        )
        XCTAssertTrue(model.dailyCourseNotificationsEnabled)
    }

    @MainActor
    func testNonReviewSampleModeStillBlocksCalendarAndNotificationActions() {
        let suiteName = "NonReviewSampleModeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离的 UserDefaults。")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            runtimeMode: .sample(review: false),
            scheduleStore: InMemoryScheduleStore(schedule: Self.schedule),
            classroomStore: InMemoryClassroomStore(cache: Self.classrooms),
            holidayStore: FileHolidayStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )

        model.importScheduleToCalendar()
        model.setDailyCourseNotificationsEnabled(true)

        XCTAssertEqual(model.calendarImportStatusMessage, "示例模式不会访问系统日历")
        XCTAssertEqual(model.dailyCourseNotificationStatusMessage, "示例模式不会申请通知权限")
        XCTAssertFalse(model.dailyCourseNotificationsEnabled)
    }

    @MainActor
    func testSuccessfulScheduleRefreshMessageAutomaticallyDismisses() async throws {
        let suiteName = "ScheduleStatusDismissTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let year = Calendar.shanghai.component(.year, from: .now)
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(
                credentials: Credentials(account: "fixture-account", password: "fixture-password")
            ),
            scheduleStore: InMemoryScheduleStore(schedule: nil),
            scheduleClient: ImmediateScheduleClient(snapshot: Self.schedule),
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: Self.holidays(year: year)),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            statusMessageAutoDismissDelay: .milliseconds(200),
            defaults: defaults
        )

        model.refreshSchedule()
        for _ in 0 ..< 50 where !model.statusMessage.hasPrefix("个人课表已更新") {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.statusMessage, "个人课表已更新，共 0 门课程")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(model.statusMessage.isEmpty)
    }

    @MainActor
    func testRuntimeReviewDemoRestoresLiveDataWithoutMutatingStores() throws {
        let suiteName = "RuntimeReviewDemoTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离的 UserDefaults。")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore(
            credentials: Credentials(account: "fixture-account", password: "fixture-password")
        )
        let model = AppModel(
            credentialStore: credentialStore,
            scheduleStore: InMemoryScheduleStore(schedule: Self.schedule),
            classroomStore: InMemoryClassroomStore(cache: Self.classrooms),
            holidayStore: InMemoryHolidayStore(snapshot: Self.holidays(
                year: Calendar.shanghai.component(.year, from: .now)
            )),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )

        model.enterReviewDemo()

        XCTAssertTrue(model.isReviewDemo)
        XCTAssertTrue(model.canExitSampleMode)
        XCTAssertEqual(model.schedule?.termID, "review-demo")
        XCTAssertTrue(model.account.isEmpty)
        XCTAssertEqual(
            try credentialStore.load(),
            Credentials(account: "fixture-account", password: "fixture-password")
        )

        model.exitReviewDemo()

        XCTAssertFalse(model.isSampleMode)
        XCTAssertEqual(model.account, "fixture-account")
        XCTAssertEqual(model.schedule, Self.schedule)
        XCTAssertEqual(model.classroomsCache, Self.classrooms)
        XCTAssertEqual(
            try credentialStore.load(),
            Credentials(account: "fixture-account", password: "fixture-password")
        )
    }

    func testFileStoresClearOwnedCachesIdempotently() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scheduleStore = FileScheduleStore(
            fileURL: directory.appendingPathComponent("schedule.json", isDirectory: false)
        )
        let classroomStore = FileClassroomStore(
            fileURL: directory.appendingPathComponent("classrooms.json", isDirectory: false)
        )
        let holidayStore = FileHolidayStore(
            directoryURL: directory.appendingPathComponent("holidays", isDirectory: true)
        )
        let year = Calendar.shanghai.component(.year, from: .now)

        try scheduleStore.save(Self.schedule)
        try classroomStore.save(Self.classrooms)
        try holidayStore.save(Self.holidays(year: year))

        try scheduleStore.clear()
        try classroomStore.clear()
        try holidayStore.clear()
        try scheduleStore.clear()
        try classroomStore.clear()
        try holidayStore.clear()

        XCTAssertNil(try scheduleStore.load())
        XCTAssertNil(try classroomStore.load())
        XCTAssertNil(try holidayStore.load(year: year))
    }

    @MainActor
    func testAppModelClearsCredentialsCachesPreferencesAndMemoryState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scheduleStore = FileScheduleStore(
            fileURL: directory.appendingPathComponent("schedule.json", isDirectory: false)
        )
        let classroomStore = FileClassroomStore(
            fileURL: directory.appendingPathComponent("classrooms.json", isDirectory: false)
        )
        let holidayStore = FileHolidayStore(
            directoryURL: directory.appendingPathComponent("holidays", isDirectory: true)
        )
        let year = Calendar.shanghai.component(.year, from: .now)
        try scheduleStore.save(Self.schedule)
        try classroomStore.save(Self.classrooms)
        try holidayStore.save(Self.holidays(year: year))

        let suiteName = "LocalDataClearTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离的 UserDefaults。")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("04", forKey: "campusID")
        defaults.set("fixture-term", forKey: "termID")
        defaults.set("2026-02-23", forKey: "termStartDate")

        let credentialStore = InMemoryCredentialStore(
            credentials: Credentials(account: "fixture-account", password: "fixture-password")
        )
        let model = AppModel(
            credentialStore: credentialStore,
            scheduleStore: scheduleStore,
            classroomStore: classroomStore,
            holidayStore: holidayStore,
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )
        model.selectedBuildings = ["主楼"]
        model.selectedSlots = [0]
        model.usePersonalSchedule = false

        XCTAssertEqual(model.account, "fixture-account")
        XCTAssertTrue(model.password.isEmpty)
        XCTAssertTrue(model.canPreserveSavedPassword)

        for value in ["2026-02-30", "2026-13-01"] {
            model.termStartDate = value
            XCTAssertFalse(model.saveSettings(), value)
            XCTAssertEqual(
                model.statusMessage,
                CredentialSettingsError.invalidTermStartDate.localizedDescription
            )
            XCTAssertEqual(
                try credentialStore.load(),
                Credentials(account: "fixture-account", password: "fixture-password")
            )
            XCTAssertEqual(model.schedule, Self.schedule)
            XCTAssertEqual(model.classroomsCache, Self.classrooms)
            XCTAssertEqual(try scheduleStore.load(), Self.schedule)
            XCTAssertEqual(try classroomStore.load(), Self.classrooms)
            XCTAssertEqual(defaults.string(forKey: "termStartDate"), "2026-02-23")
        }

        model.termStartDate = "2026-02-23"
        XCTAssertTrue(model.saveSettings())
        XCTAssertEqual(
            try credentialStore.load(),
            Credentials(account: "fixture-account", password: "fixture-password")
        )
        XCTAssertTrue(model.password.isEmpty)

        model.account = "replacement-account"
        XCTAssertFalse(model.saveSettings())
        XCTAssertEqual(
            model.statusMessage,
            CredentialSettingsError.passwordRequiredForChangedAccount.localizedDescription
        )
        XCTAssertEqual(
            try credentialStore.load(),
            Credentials(account: "fixture-account", password: "fixture-password")
        )

        model.password = "replacement-value"
        XCTAssertTrue(model.saveSettings())
        XCTAssertTrue(model.password.isEmpty)
        XCTAssertEqual(
            try credentialStore.load(),
            Credentials(account: "replacement-account", password: "replacement-value")
        )
        XCTAssertNil(model.schedule)
        XCTAssertNil(model.classroomsCache)
        XCTAssertNil(try scheduleStore.load())
        XCTAssertNil(try classroomStore.load())

        model.clearLocalData()

        XCTAssertNil(try credentialStore.load())
        XCTAssertNil(try scheduleStore.load())
        XCTAssertNil(try classroomStore.load())
        XCTAssertNil(try holidayStore.load(year: year))
        XCTAssertNil(defaults.object(forKey: "campusID"))
        XCTAssertNil(defaults.object(forKey: "termID"))
        XCTAssertNil(defaults.object(forKey: "termStartDate"))
        XCTAssertTrue(model.account.isEmpty)
        XCTAssertTrue(model.password.isEmpty)
        XCTAssertNil(model.schedule)
        XCTAssertNil(model.classroomsCache)
        XCTAssertTrue(model.holidaysByYear.isEmpty)
        XCTAssertTrue(model.holidayStatusByYear.isEmpty)
        XCTAssertEqual(model.campusID, "01")
        XCTAssertEqual(model.termID, ScheduleDefaults.termID)
        XCTAssertEqual(model.termStartDate, ScheduleDefaults.termStartDate)
        XCTAssertTrue(model.selectedBuildings.isEmpty)
        XCTAssertTrue(model.usePersonalSchedule)
        XCTAssertEqual(model.selectedSlots, Set(SlotMetadata.defaults.indices))
        XCTAssertEqual(model.statusMessage, "本地数据已清除")
    }

    private static let schedule = ScheduleSnapshot(
        termID: "fixture-term",
        termStartDate: "2026-02-23",
        fetchedAt: "2026-03-01T00:00:00+08:00",
        courses: []
    )

    private static var classrooms: ClassroomsCache {
        ClassroomsCache(
            cacheVersion: ClassroomDefaults.cacheVersion,
            targetDate: StrictContractDateParser.string(from: .now),
            fetchedAt: "2026-03-01T00:00:00+08:00",
            realtime: true,
            provider: "fixture",
            campuses: []
        )
    }

    private static func holidays(year: Int) -> HolidaysSnapshot {
        HolidaysSnapshot(
            year: year,
            source: HolidayDefaults.source,
            fetchedAt: ISO8601DateFormatter().string(from: .now),
            items: []
        )
    }

}

private final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?

    init(credentials: Credentials?) {
        self.credentials = credentials
    }

    func load() throws -> Credentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    func save(_ credentials: Credentials) throws {
        lock.lock()
        defer { lock.unlock() }
        self.credentials = credentials
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        credentials = nil
    }
}

private struct InMemoryScheduleStore: ScheduleStoring {
    let schedule: ScheduleSnapshot?
    func load() throws -> ScheduleSnapshot? { schedule }
    func save(_: ScheduleSnapshot) throws {}
    func clear() throws {}
}

private struct ImmediateScheduleClient: ScheduleFetching {
    let snapshot: ScheduleSnapshot

    func fetch(
        credentials _: Credentials,
        fallbackTermID _: String,
        fallbackTermStartDate _: String
    ) async throws -> ScheduleSnapshot {
        snapshot
    }
}

private struct InMemoryClassroomStore: ClassroomStoring {
    let cache: ClassroomsCache?
    func load() throws -> ClassroomsCache? { cache }
    func save(_: ClassroomsCache) throws {}
    func clear() throws {}
}

private struct InMemoryHolidayStore: HolidayStoring {
    let snapshot: HolidaysSnapshot?
    func load(year: Int) throws -> HolidaysSnapshot? {
        snapshot?.year == year ? snapshot : nil
    }
    func save(_: HolidaysSnapshot) throws {}
    func clear() throws {}
}

private struct NoopNotificationScheduler: DailyCourseNotificationScheduling {
    func authorizationStatus(timeout _: Duration) async throws -> DailyCourseNotificationAuthorization { .denied }
    func requestAuthorization(timeout _: Duration) async throws -> Bool { false }
    func replacePending(
        with _: [DailyCourseNotificationRequest],
        revision _: UInt64
    ) async throws {}
    func cancelPending(revision _: UInt64) {}
}
