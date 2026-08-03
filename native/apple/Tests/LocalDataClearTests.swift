import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class LocalDataClearTests: XCTestCase {
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
            defaults: defaults
        )
        model.selectedBuildings = ["主楼"]
        model.selectedSlots = [0]
        model.usePersonalSchedule = false

        XCTAssertEqual(model.account, "fixture-account")
        XCTAssertTrue(model.password.isEmpty)
        XCTAssertTrue(model.canPreserveSavedPassword)
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
            targetDate: dateFormatter.string(from: .now),
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
