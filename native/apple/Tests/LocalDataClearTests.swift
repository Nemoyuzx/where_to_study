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

    func testAutomaticScheduleRefreshLaunchGateRequiresEveryCondition() {
        XCTAssertTrue(AutomaticScheduleRefreshLogic.shouldRequest(
            isSampleMode: false,
            automaticTermDetectionEnabled: true,
            hasSavedPassword: true,
            alreadyRequested: false
        ))
        XCTAssertFalse(AutomaticScheduleRefreshLogic.shouldRequest(
            isSampleMode: true,
            automaticTermDetectionEnabled: true,
            hasSavedPassword: true,
            alreadyRequested: false
        ))
        XCTAssertFalse(AutomaticScheduleRefreshLogic.shouldRequest(
            isSampleMode: false,
            automaticTermDetectionEnabled: false,
            hasSavedPassword: true,
            alreadyRequested: false
        ))
        XCTAssertFalse(AutomaticScheduleRefreshLogic.shouldRequest(
            isSampleMode: false,
            automaticTermDetectionEnabled: true,
            hasSavedPassword: false,
            alreadyRequested: false
        ))
        XCTAssertFalse(AutomaticScheduleRefreshLogic.shouldRequest(
            isSampleMode: false,
            automaticTermDetectionEnabled: true,
            hasSavedPassword: true,
            alreadyRequested: true
        ))
    }

    @MainActor
    func testManualModeKeepsMissingTermFieldsBlankAndRejectsSaveOrRefresh() async throws {
        let suiteName = "ManualMissingTermSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "automaticTermDetectionEnabled")
        let liveSchedule = ScheduleSnapshot(
            termID: "2026-2027-1",
            termStartDate: "2026-09-07",
            fetchedAt: "2026-08-24T13:00:00Z",
            courses: []
        )
        let scheduleClient = RecordingScheduleClient(snapshot: liveSchedule)
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(
                credentials: Credentials(account: "fixture-account", password: "fixture-password")
            ),
            scheduleStore: RecordingScheduleStore(schedule: nil),
            scheduleClient: scheduleClient,
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )

        XCTAssertEqual(model.termID, "")
        XCTAssertEqual(model.termStartDate, "")
        XCTAssertFalse(model.saveSettings())
        XCTAssertEqual(model.statusMessage, CredentialSettingsError.invalidTermID.localizedDescription)
        model.refreshSchedule()
        XCTAssertEqual(model.statusMessage, CredentialSettingsError.invalidTermID.localizedDescription)
        XCTAssertEqual(scheduleClient.callCount, 0)

        model.termID = "2024-2025-1"
        XCTAssertFalse(model.saveSettings())
        XCTAssertEqual(
            model.statusMessage,
            CredentialSettingsError.invalidTermStartDate.localizedDescription
        )
        model.refreshSchedule()
        XCTAssertEqual(
            model.statusMessage,
            CredentialSettingsError.invalidTermStartDate.localizedDescription
        )
        XCTAssertEqual(scheduleClient.callCount, 0)

        model.termStartDate = "2024-10-14"
        XCTAssertTrue(model.saveSettings())
        model.refreshSchedule()
        for _ in 0 ..< 100 where scheduleClient.callCount < 1 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(scheduleClient.fallbackTermID, "2024-2025-1")
        XCTAssertEqual(scheduleClient.fallbackTermStartDate, "2024-10-14")
        XCTAssertEqual(model.termID, "2024-2025-1")
        XCTAssertEqual(model.termStartDate, "2024-10-14")
    }

    @MainActor
    func testDisablingAutomaticDetectionClearsDerivedTermUntilManualInput() throws {
        let suiteName = "DisableAutomaticTermDetection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 24)
        ))
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(credentials: nil),
            scheduleStore: RecordingScheduleStore(schedule: nil),
            scheduleClient: RecordingScheduleClient(snapshot: ScheduleSnapshot(
                termID: "2026-2027-1",
                termStartDate: "2026-09-07",
                fetchedAt: "2026-08-24T13:00:00Z",
                courses: []
            )),
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            now: { fixedNow },
            defaults: defaults
        )

        XCTAssertEqual(model.termID, "2026-2027-1")
        XCTAssertEqual(model.termStartDate, "2026-08-31")

        model.setAutomaticTermDetectionEnabled(false)

        XCTAssertEqual(model.termID, "")
        XCTAssertEqual(model.termStartDate, "")
        XCTAssertEqual(defaults.string(forKey: "termID"), "")
        XCTAssertEqual(defaults.string(forKey: "termStartDate"), "")
        XCTAssertFalse(model.saveSettings())
        XCTAssertEqual(model.statusMessage, CredentialSettingsError.invalidTermID.localizedDescription)
    }

    @MainActor
    func testAutomaticLaunchRejectsOldCacheButKeepsCurrentTermCache() throws {
        let fixedNow = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 24)
        ))
        let year = Calendar.shanghai.component(.year, from: fixedNow)
        let oldSchedule = ScheduleSnapshot(
            termID: "2025-2026-2",
            termStartDate: "2026-03-02",
            fetchedAt: "2026-07-01T00:00:00Z",
            courses: []
        )
        let currentSchedule = ScheduleSnapshot(
            termID: "2026-2027-1",
            termStartDate: "2026-09-07",
            fetchedAt: "2026-08-24T13:00:00Z",
            courses: []
        )

        let oldSuiteName = "RejectOldAutomaticSchedule.\(UUID().uuidString)"
        let oldDefaults = try XCTUnwrap(UserDefaults(suiteName: oldSuiteName))
        defer { oldDefaults.removePersistentDomain(forName: oldSuiteName) }
        let oldStore = RecordingScheduleStore(schedule: oldSchedule)
        let oldModel = AppModel(
            credentialStore: InMemoryCredentialStore(credentials: nil),
            scheduleStore: oldStore,
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: Self.holidays(year: year)),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            now: { fixedNow },
            defaults: oldDefaults
        )

        XCTAssertNil(oldModel.schedule)
        XCTAssertTrue(oldModel.todayCourses.isEmpty)
        XCTAssertEqual(oldModel.termID, "2026-2027-1")
        XCTAssertEqual(oldModel.termStartDate, "2026-08-31")
        XCTAssertEqual(try oldStore.load(), oldSchedule, "The rejected cache remains recoverable on disk")

        let currentSuiteName = "KeepCurrentAutomaticSchedule.\(UUID().uuidString)"
        let currentDefaults = try XCTUnwrap(UserDefaults(suiteName: currentSuiteName))
        defer { currentDefaults.removePersistentDomain(forName: currentSuiteName) }
        let currentModel = AppModel(
            credentialStore: InMemoryCredentialStore(credentials: nil),
            scheduleStore: RecordingScheduleStore(schedule: currentSchedule),
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: Self.holidays(year: year)),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            now: { fixedNow },
            defaults: currentDefaults
        )

        XCTAssertEqual(currentModel.schedule, currentSchedule)
        XCTAssertEqual(currentModel.termID, currentSchedule.termID)
        XCTAssertEqual(currentModel.termStartDate, currentSchedule.termStartDate)
    }

    @MainActor
    func testAutomaticRefreshUsesAcceptedCachedRealStartDateAsFallback() async throws {
        let suiteName = "CurrentCacheAutomaticFallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 24)
        ))
        let currentSchedule = ScheduleSnapshot(
            termID: "2026-2027-1",
            termStartDate: "2026-09-07",
            fetchedAt: "2026-08-24T13:00:00Z",
            courses: []
        )
        let scheduleStore = RecordingScheduleStore(schedule: currentSchedule)
        let scheduleClient = RecordingScheduleClient(snapshot: currentSchedule)
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(
                credentials: Credentials(account: "fixture-account", password: "fixture-password")
            ),
            scheduleStore: scheduleStore,
            scheduleClient: scheduleClient,
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: Self.holidays(year: 2026)),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            now: { fixedNow },
            defaults: defaults
        )

        XCTAssertEqual(model.schedule, currentSchedule)
        model.refreshSchedule()
        for _ in 0 ..< 100 where scheduleClient.callCount < 1 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(scheduleClient.fallbackTermID, "2026-2027-1")
        XCTAssertEqual(scheduleClient.fallbackTermStartDate, "2026-09-07")
    }

    @MainActor
    func testAutomaticLaunchRefreshUsesDetectedFallbackOnceThenPersistsLiveMetadata() async throws {
        let suiteName = "AutomaticLaunchScheduleRefresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(ScheduleDefaults.termID, forKey: "termID")
        defaults.set(ScheduleDefaults.termStartDate, forKey: "termStartDate")
        let fixedNow = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 24)
        ))
        let liveSchedule = ScheduleSnapshot(
            termID: "2026-2027-1",
            termStartDate: "2026-09-07",
            fetchedAt: "2026-08-24T13:00:00Z",
            courses: []
        )
        let scheduleStore = RecordingScheduleStore(schedule: nil)
        let scheduleClient = RecordingScheduleClient(snapshot: liveSchedule)
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(
                credentials: Credentials(account: "fixture-account", password: "fixture-password")
            ),
            scheduleStore: scheduleStore,
            scheduleClient: scheduleClient,
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            now: { fixedNow },
            defaults: defaults
        )

        XCTAssertEqual(model.termID, "2026-2027-1")
        XCTAssertEqual(model.termStartDate, "2026-08-31")

        model.refreshScheduleAutomaticallyIfNeeded()
        model.refreshScheduleAutomaticallyIfNeeded()
        for _ in 0 ..< 100 where scheduleStore.savedSchedule == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(scheduleClient.callCount, 1)
        XCTAssertEqual(scheduleClient.fallbackTermID, "2026-2027-1")
        XCTAssertEqual(scheduleClient.fallbackTermStartDate, "2026-08-31")
        XCTAssertEqual(scheduleStore.savedSchedule, liveSchedule)
        XCTAssertEqual(model.schedule, liveSchedule)
        XCTAssertEqual(model.termID, liveSchedule.termID)
        XCTAssertEqual(model.termStartDate, liveSchedule.termStartDate)
        XCTAssertEqual(defaults.string(forKey: "termID"), liveSchedule.termID)
        XCTAssertEqual(defaults.string(forKey: "termStartDate"), liveSchedule.termStartDate)
    }

    @MainActor
    func testSavingFirstCredentialsTriggersAutomaticRefreshWithoutAnotherAppear() async throws {
        let suiteName = "FirstCredentialAutomaticRefresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 24)
        ))
        let liveSchedule = ScheduleSnapshot(
            termID: "2026-2027-1",
            termStartDate: "2026-09-07",
            fetchedAt: "2026-08-24T13:00:00Z",
            courses: []
        )
        let scheduleClient = RecordingScheduleClient(snapshot: liveSchedule)
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(credentials: nil),
            scheduleStore: RecordingScheduleStore(schedule: nil),
            scheduleClient: scheduleClient,
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            now: { fixedNow },
            defaults: defaults
        )

        model.refreshScheduleAutomaticallyIfNeeded()
        XCTAssertEqual(scheduleClient.callCount, 0)

        model.account = "new-account"
        model.password = "new-password"
        XCTAssertTrue(model.saveSettings())
        for _ in 0 ..< 100 where model.schedule == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(scheduleClient.callCount, 1)
        XCTAssertEqual(model.schedule, liveSchedule)
    }

    @MainActor
    func testSwitchingFromManualToAutomaticTriggersRefreshAndAccountChangeResetsGate() async throws {
        let suiteName = "AutomaticRefreshGateReset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "automaticTermDetectionEnabled")
        defaults.set("manual-term", forKey: "termID")
        defaults.set("2024-10-14", forKey: "termStartDate")
        let fixedNow = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 24)
        ))
        let liveSchedule = ScheduleSnapshot(
            termID: "2026-2027-1",
            termStartDate: "2026-09-07",
            fetchedAt: "2026-08-24T13:00:00Z",
            courses: []
        )
        let oldManualSchedule = ScheduleSnapshot(
            termID: "2025-2026-2",
            termStartDate: "2026-03-02",
            fetchedAt: "2026-07-01T00:00:00Z",
            courses: []
        )
        let scheduleClient = RecordingScheduleClient(snapshot: liveSchedule)
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(
                credentials: Credentials(account: "first-account", password: "first-password")
            ),
            scheduleStore: RecordingScheduleStore(schedule: oldManualSchedule),
            scheduleClient: scheduleClient,
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            now: { fixedNow },
            defaults: defaults
        )

        model.refreshScheduleAutomaticallyIfNeeded()
        XCTAssertEqual(scheduleClient.callCount, 0)
        XCTAssertEqual(model.schedule, oldManualSchedule)

        model.setAutomaticTermDetectionEnabled(true)
        XCTAssertNil(model.schedule)
        for _ in 0 ..< 100 where scheduleClient.callCount < 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(scheduleClient.callCount, 1)

        model.account = "second-account"
        model.password = "second-password"
        XCTAssertTrue(model.saveSettings())
        for _ in 0 ..< 100 where scheduleClient.callCount < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(scheduleClient.callCount, 2)
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
        model.setAppLanguage(.english)

        model.account = "must-not-save"
        model.password = "must-not-save"
        XCTAssertFalse(model.saveSettings())
        XCTAssertNil(try credentialStore.load())

        model.refreshSchedule()
        model.refreshClassrooms()
        model.importScheduleToCalendar()
        model.setDailyCourseNotificationsEnabled(true)

        XCTAssertEqual(
            model.statusMessage,
            "正在展示内置示例课表，未连接北邮服务"
        )
        XCTAssertEqual(
            model.localized(model.statusMessage),
            "Showing the built-in demo schedule; not connected to BUPT services"
        )
        XCTAssertEqual(
            model.classroomStatusMessage,
            "正在展示内置示例空教室，未连接北邮服务"
        )
        XCTAssertEqual(
            model.localized(model.classroomStatusMessage),
            "Showing built-in demo rooms; not connected to BUPT services"
        )
        let importedCount = (try? CalendarImportLogic.eventDrafts(from: Self.schedule).count) ?? 0
        XCTAssertEqual(
            model.calendarImportStatusMessage,
            model.localizedFormat(
                "示例模式已模拟同步 %d 个课程日期，未写入系统日历",
                importedCount
            )
        )
        XCTAssertEqual(
            model.dailyCourseNotificationStatusMessage,
            "示例模式已模拟开启每日课程摘要，未申请通知权限"
        )
        XCTAssertEqual(
            model.localized(model.dailyCourseNotificationStatusMessage),
            "Daily course summaries are simulated as enabled; notification permission was not requested"
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
        let expectedStatus = model.localizedFormat("个人课表已更新，共 %d 门课程", 0)
        for _ in 0 ..< 50 where model.statusMessage != expectedStatus {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.statusMessage, expectedStatus)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(model.statusMessage.isEmpty)
    }

    @MainActor
    func testSuccessfulSettingsSaveMessageAutomaticallyDismisses() async throws {
        let suiteName = "SettingsStatusDismissTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let year = Calendar.shanghai.component(.year, from: .now)
        let model = AppModel(
            credentialStore: InMemoryCredentialStore(
                credentials: Credentials(account: "fixture-account", password: "fixture-password")
            ),
            scheduleStore: InMemoryScheduleStore(schedule: Self.schedule),
            classroomStore: InMemoryClassroomStore(cache: Self.classrooms),
            holidayStore: InMemoryHolidayStore(snapshot: Self.holidays(year: year)),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            statusMessageAutoDismissDelay: .milliseconds(200),
            defaults: defaults
        )

        XCTAssertTrue(model.saveSettings())
        XCTAssertEqual(model.statusMessage, model.localized("设置已保存"))
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
            now: { Self.scheduleNow },
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

    @MainActor
    func testClassroomQueryCampusDoesNotChangeSavedDefaultCampus() throws {
        let suiteName = "ClassroomQueryCampusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("04", forKey: "campusID")
        let model = AppModel(
            scheduleStore: InMemoryScheduleStore(schedule: Self.schedule),
            classroomStore: InMemoryClassroomStore(cache: Self.classrooms),
            holidayStore: InMemoryHolidayStore(snapshot: Self.holidays(
                year: Calendar.shanghai.component(.year, from: .now)
            )),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )

        XCTAssertEqual(model.campusID, "04")
        XCTAssertEqual(model.queryCampusID, "04")
        model.selectedBuildings = ["智慧教学楼"]

        model.selectQueryCampus("01")

        XCTAssertEqual(model.queryCampusID, "01")
        XCTAssertEqual(model.campusID, "04")
        XCTAssertEqual(defaults.string(forKey: "campusID"), "04")
        XCTAssertTrue(model.selectedBuildings.isEmpty)
        XCTAssertEqual(model.campusBuildings, ClassroomDefaults.buildings(for: "01"))
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
            now: { Self.scheduleNow },
            defaults: defaults
        )
        model.selectedBuildings = ["主楼"]
        model.selectedSlots = [0]
        model.usePersonalSchedule = false
        model.setAutomaticTermDetectionEnabled(false)
        model.termID = "2025-2026-2"

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
            XCTAssertEqual(defaults.string(forKey: "termStartDate"), "")
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

        model.customDeadlinesURL = "https://example.com/feed.json"
        model.setCustomDeadlinesEnabled(true)
        XCTAssertEqual(try model.saveCustomDeadlineSettings()?.host, "example.com")
        model.setFavorite(Self.favorite(id: "clear-me"), isFavorite: true)
        XCTAssertEqual(model.favoriteDeadlines.count, 1)

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
        XCTAssertEqual(model.queryCampusID, "01")
        let detectedTerm = SemesterLogic.suggestTerm()
        XCTAssertEqual(model.termID, detectedTerm.termID)
        XCTAssertEqual(model.termStartDate, detectedTerm.termStartDate)
        XCTAssertTrue(model.selectedBuildings.isEmpty)
        XCTAssertTrue(model.usePersonalSchedule)
        XCTAssertFalse(model.customDeadlinesEnabled)
        XCTAssertTrue(model.customDeadlinesURL.isEmpty)
        XCTAssertTrue(model.favoriteDeadlines.isEmpty)
        XCTAssertEqual(model.selectedSlots, Set(SlotMetadata.defaults.indices))
        XCTAssertEqual(model.statusMessage, "本地数据已清除")
    }

    @MainActor
    func testFavoriteSnapshotsPersistAndIgnoreDisabledSourceSwitches() throws {
        let suiteName = "FavoriteDeadlinePersistence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let favorite = Self.favorite(id: "persisted")
        let first = AppModel(
            scheduleStore: InMemoryScheduleStore(schedule: nil),
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )
        first.setCompetitionDeadlinesEnabled(false)
        first.customDeadlinesURL = "https://example.com/feed.json"
        first.setCustomDeadlinesEnabled(true)
        XCTAssertNotNil(try first.saveCustomDeadlineSettings())
        first.setFavorite(favorite, isFavorite: true)

        let relaunched = AppModel(
            scheduleStore: InMemoryScheduleStore(schedule: nil),
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )
        XCTAssertEqual(relaunched.favoriteDeadlines, [favorite])
        XCTAssertTrue(relaunched.customDeadlinesEnabled)
        XCTAssertEqual(relaunched.customDeadlineSourceURL?.host, "example.com")
        XCTAssertEqual(
            relaunched.visibleDeadlineItems(liveItems: [favorite], on: "2026-09-18"),
            [favorite]
        )
        XCTAssertTrue(relaunched.hasCalendarDeadlinesToDisplay)
    }

    @MainActor
    func testFavoriteSnapshotStorageIsCappedAtFiveHundred() throws {
        let suiteName = "FavoriteDeadlineCap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            scheduleStore: InMemoryScheduleStore(schedule: nil),
            classroomStore: InMemoryClassroomStore(cache: nil),
            holidayStore: InMemoryHolidayStore(snapshot: nil),
            dailyCourseNotificationScheduler: NoopNotificationScheduler(),
            defaults: defaults
        )
        for index in 0 ..< 510 {
            model.setFavorite(Self.favorite(id: "favorite-\(index)"), isFavorite: true)
        }

        XCTAssertEqual(model.favoriteDeadlines.count, AppModel.maximumFavoriteDeadlines)
        XCTAssertEqual(model.favoriteDeadlines.first?.id, "favorite-509")
        XCTAssertFalse(model.favoriteDeadlines.contains { $0.id == "favorite-0" })
    }

    private static let scheduleNow = Calendar.shanghai.date(
        from: DateComponents(year: 2026, month: 8, day: 24)
    )!

    private static let schedule = ScheduleSnapshot(
        termID: "2026-2027-1",
        termStartDate: "2026-09-07",
        fetchedAt: "2026-08-24T13:00:00Z",
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

    private static func favorite(id: String) -> PublicDeadlineItem {
        PublicDeadlineItem(
            id: id,
            name: "收藏日程 \(id)",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-09-18T23:59:00+08:00",
            organizer: "示例组织方",
            officialURL: URL(string: "https://example.com/events/\(id)")
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

private final class RecordingScheduleClient: ScheduleFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: ScheduleSnapshot
    private var recordedCallCount = 0
    private var recordedFallbackTermID: String?
    private var recordedFallbackTermStartDate: String?

    init(snapshot: ScheduleSnapshot) {
        self.snapshot = snapshot
    }

    var callCount: Int {
        lock.withLock { recordedCallCount }
    }

    var fallbackTermID: String? {
        lock.withLock { recordedFallbackTermID }
    }

    var fallbackTermStartDate: String? {
        lock.withLock { recordedFallbackTermStartDate }
    }

    func fetch(
        credentials _: Credentials,
        fallbackTermID: String,
        fallbackTermStartDate: String
    ) async throws -> ScheduleSnapshot {
        lock.withLock {
            recordedCallCount += 1
            recordedFallbackTermID = fallbackTermID
            recordedFallbackTermStartDate = fallbackTermStartDate
        }
        return snapshot
    }
}

private final class RecordingScheduleStore: ScheduleStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var schedule: ScheduleSnapshot?
    private var recordedSavedSchedule: ScheduleSnapshot?

    init(schedule: ScheduleSnapshot?) {
        self.schedule = schedule
    }

    var savedSchedule: ScheduleSnapshot? {
        lock.withLock { recordedSavedSchedule }
    }

    func load() throws -> ScheduleSnapshot? {
        lock.withLock { schedule }
    }

    func save(_ schedule: ScheduleSnapshot) throws {
        lock.withLock {
            self.schedule = schedule
            recordedSavedSchedule = schedule
        }
    }

    func clear() throws {
        lock.withLock {
            schedule = nil
            recordedSavedSchedule = nil
        }
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
