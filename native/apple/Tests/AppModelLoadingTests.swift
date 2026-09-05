import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class AppModelLoadingTests: XCTestCase {
    @MainActor
    func testDeferredLaunchLeavesMainActorAvailableAndLoadsCachesOffMainThread() async throws {
        let fixture = try LoadingFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()

        XCTAssertNil(model.schedule)
        try await waitUntil { fixture.scheduleStore.didStartLoading }
        // This mutation must remain available while the cache read is blocked.
        model.selectQueryCampus("04")
        XCTAssertEqual(model.queryCampusID, "04")
        XCTAssertFalse(fixture.scheduleStore.loadedOnMainThread)
        fixture.scheduleStore.releaseLoad()
        await model.awaitInitialLocalData()

        XCTAssertEqual(model.schedule, fixture.snapshot)
        XCTAssertEqual(model.classroomsCache, fixture.classroomStore.cache)
        XCTAssertFalse(fixture.classroomStore.loadedOnMainThread)
        try await waitUntil { fixture.holidayStore.didLoad }
        XCTAssertFalse(fixture.holidayStore.loadedOnMainThread)
    }

    @MainActor
    func testClearingDataDuringCacheReadDoesNotRestoreOldAccountData() async throws {
        let fixture = try LoadingFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        let pendingLoad = Task { await model.awaitInitialLocalData() }
        try await waitUntil { fixture.scheduleStore.didStartLoading }

        model.clearLocalData()
        fixture.scheduleStore.releaseLoad()
        await pendingLoad.value

        XCTAssertNil(model.schedule)
        XCTAssertNil(model.classroomsCache)
        XCTAssertTrue(model.account.isEmpty)
        XCTAssertEqual(model.statusMessage, "本地数据已清除")
    }

    @MainActor
    func testChangingAccountDuringCacheReadDiscardsPreviousAccountSnapshot() async throws {
        let fixture = try LoadingFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        let pendingLoad = Task { await model.awaitInitialLocalData() }
        try await waitUntil { fixture.scheduleStore.didStartLoading }

        model.account = "next-account"
        model.password = "next-password"
        XCTAssertTrue(model.saveSettings())
        fixture.scheduleStore.releaseLoad()
        await pendingLoad.value

        XCTAssertEqual(model.account, "next-account")
        XCTAssertNil(model.schedule)
        XCTAssertNil(model.classroomsCache)
        XCTAssertNil(try fixture.scheduleStore.loadSavedSnapshot())
    }

    @MainActor
    func testEnteringDemoDuringCacheReadKeepsDemoSnapshot() async throws {
        let fixture = try LoadingFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        let pendingLoad = Task { await model.awaitInitialLocalData() }
        try await waitUntil { fixture.scheduleStore.didStartLoading }

        model.enterReviewDemo()
        let demoSchedule = model.schedule
        let demoClassrooms = model.classroomsCache
        fixture.scheduleStore.releaseLoad()
        await pendingLoad.value

        XCTAssertTrue(model.isReviewDemo)
        XCTAssertEqual(model.schedule, demoSchedule)
        XCTAssertEqual(model.classroomsCache, demoClassrooms)
        XCTAssertEqual(model.termID, "review-demo")
    }

    @MainActor
    func testTermEditDuringCacheReadIsNotReplacedByLaunchSnapshot() async throws {
        let fixture = try LoadingFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(true, forKey: "automaticTermDetectionEnabled")
        let model = fixture.makeModel()
        try await waitUntil { fixture.scheduleStore.didStartLoading }

        model.setAutomaticTermDetectionEnabled(false)
        model.termID = "2025-2026-2"
        model.termStartDate = "2026-03-02"
        fixture.scheduleStore.releaseLoad()
        await model.awaitInitialLocalData()

        XCTAssertEqual(model.termID, "2025-2026-2")
        XCTAssertEqual(model.termStartDate, "2026-03-02")
        XCTAssertFalse(model.automaticTermDetectionEnabled)
        XCTAssertNil(model.schedule)
    }

    @MainActor
    func testAutomaticClassroomRefreshWaitsForTodaysCache() async throws {
        let fixture = try LoadingFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        try await waitUntil { fixture.scheduleStore.didStartLoading }

        model.refreshClassroomsIfNeeded()
        XCTAssertEqual(fixture.classroomClient.callCount, 0)
        fixture.scheduleStore.releaseLoad()
        await model.awaitInitialLocalData()
        // A forced refresh also exercises the persistence path off the UI actor.
        model.refreshClassrooms(force: true)
        try await waitUntil { model.classroomStatusMessage == "当天空教室已更新" }

        XCTAssertEqual(fixture.classroomClient.callCount, 1)
        XCTAssertFalse(fixture.classroomStore.savedOnMainThread)
    }

    @MainActor
    func testScheduleRefreshWaitsForCacheThenPersistsOffMainThread() async throws {
        let fixture = try LoadingFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        try await waitUntil { fixture.scheduleStore.didStartLoading }

        model.refreshSchedule()
        XCTAssertEqual(fixture.scheduleClient.callCount, 0)
        fixture.scheduleStore.releaseLoad()
        await model.awaitInitialLocalData()
        try await waitUntil { fixture.scheduleStore.didSave && !model.isRefreshingSchedule }

        XCTAssertEqual(fixture.scheduleClient.callCount, 1)
        XCTAssertFalse(fixture.scheduleStore.savedOnMainThread)
        XCTAssertEqual(model.schedule, fixture.snapshot)
    }

    func testPersistenceRejectsWorkQueuedBeforeAccountInvalidation() {
        let persistence = LocalDataPersistence()
        var savedAccounts = [String]()
        XCTAssertTrue(persistence.perform(ifGeneration: 0) { savedAccounts.append("old") })
        persistence.invalidate(generation: 1)
        savedAccounts.removeAll()

        XCTAssertFalse(persistence.perform(ifGeneration: 0) { savedAccounts.append("old") })
        XCTAssertTrue(persistence.perform(ifGeneration: 1) { savedAccounts.append("new") })
        XCTAssertEqual(savedAccounts, ["new"])
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the cache operation")
    }
}

@MainActor
private struct LoadingFixture {
    let suiteName = "AppModelLoadingTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let snapshot = ScheduleSnapshot(
        termID: "2026-2027-1", termStartDate: "2026-09-07",
        fetchedAt: "2026-09-05T08:00:00Z", courses: []
    )
    let scheduleStore: BlockingLoadingScheduleStore
    let classroomStore = LoadingClassroomStore(cache: SampleData.classrooms())
    let holidayStore = LoadingHolidayStore()
    let scheduleClient: LoadingScheduleClient
    let classroomClient: LoadingClassroomClient

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: "automaticTermDetectionEnabled")
        defaults.set(snapshot.termID, forKey: "termID")
        defaults.set(snapshot.termStartDate, forKey: "termStartDate")
        scheduleStore = BlockingLoadingScheduleStore(snapshot: snapshot)
        scheduleClient = LoadingScheduleClient(snapshot: snapshot)
        classroomClient = LoadingClassroomClient(snapshot: try XCTUnwrap(classroomStore.cache))
    }

    func makeModel() -> AppModel {
        AppModel(
            credentialStore: LoadingCredentialStore(),
            scheduleStore: scheduleStore,
            scheduleClient: scheduleClient,
            classroomStore: classroomStore,
            classroomClient: classroomClient,
            holidayStore: holidayStore,
            holidayClient: LoadingHolidayClient(),
            dailyCourseNotificationScheduler: LoadingNotificationScheduler(),
            now: { Date(timeIntervalSince1970: 1_788_595_200) },
            defaults: defaults,
            deferLocalDataLoading: true
        )
    }

    func cleanUp() {
        scheduleStore.releaseLoad()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class BlockingLoadingScheduleStore: ScheduleStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var snapshot: ScheduleSnapshot?
    private var started = false
    private var readOnMain = false
    private var saved = false
    private var wroteOnMain = false

    init(snapshot: ScheduleSnapshot) { self.snapshot = snapshot }
    var didStartLoading: Bool { lock.withLock { started } }
    var loadedOnMainThread: Bool { lock.withLock { readOnMain } }
    var didSave: Bool { lock.withLock { saved } }
    var savedOnMainThread: Bool { lock.withLock { wroteOnMain } }
    func releaseLoad() { gate.signal() }
    func loadSavedSnapshot() throws -> ScheduleSnapshot? { lock.withLock { snapshot } }

    func load() throws -> ScheduleSnapshot? {
        let captured = lock.withLock {
            started = true
            readOnMain = Thread.isMainThread
            return snapshot
        }
        guard gate.wait(timeout: .now() + 5) == .success else {
            throw CocoaError(.fileReadUnknown)
        }
        return captured
    }

    func save(_ schedule: ScheduleSnapshot) throws {
        lock.withLock {
            saved = true
            wroteOnMain = Thread.isMainThread
            snapshot = schedule
        }
    }

    func clear() throws { lock.withLock { snapshot = nil } }
}

private final class LoadingClassroomStore: ClassroomStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: ClassroomsCache?
    private var readOnMain = false
    private var wroteOnMain = false
    init(cache: ClassroomsCache) { snapshot = cache }
    var cache: ClassroomsCache? { lock.withLock { snapshot } }
    var loadedOnMainThread: Bool { lock.withLock { readOnMain } }
    var savedOnMainThread: Bool { lock.withLock { wroteOnMain } }
    func load() throws -> ClassroomsCache? {
        lock.withLock {
            readOnMain = Thread.isMainThread
            return snapshot
        }
    }
    func save(_ cache: ClassroomsCache) throws {
        lock.withLock {
            wroteOnMain = Thread.isMainThread
            snapshot = cache
        }
    }
    func clear() throws { lock.withLock { snapshot = nil } }
}

private final class LoadingHolidayStore: HolidayStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var readOnMain = false
    var didLoad: Bool { lock.withLock { loaded } }
    var loadedOnMainThread: Bool { lock.withLock { readOnMain } }
    func load(year: Int) throws -> HolidaysSnapshot? {
        lock.withLock {
            loaded = true
            readOnMain = Thread.isMainThread
        }
        return HolidaysSnapshot(
            year: year, source: "test", fetchedAt: ISO8601DateFormatter().string(from: .now), items: []
        )
    }
    func save(_: HolidaysSnapshot) throws {}
    func clear() throws {}
}

private final class LoadingScheduleClient: ScheduleFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let snapshot: ScheduleSnapshot
    init(snapshot: ScheduleSnapshot) { self.snapshot = snapshot }
    var callCount: Int { lock.withLock { calls } }
    func fetch(
        credentials _: Credentials,
        fallbackTermID _: String,
        fallbackTermStartDate _: String
    ) async throws -> ScheduleSnapshot {
        lock.withLock { calls += 1 }
        return snapshot
    }
}

private final class LoadingClassroomClient: ClassroomFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let snapshot: ClassroomsCache
    init(snapshot: ClassroomsCache) { self.snapshot = snapshot }
    var callCount: Int { lock.withLock { calls } }
    func fetch(credentials _: Credentials, targetDate _: String) async throws -> ClassroomsCache {
        lock.withLock { calls += 1 }
        return snapshot
    }
}

private final class LoadingCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials? = Credentials(account: "old-account", password: "old-password")
    func load() throws -> Credentials? { lock.withLock { credentials } }
    func save(_ value: Credentials) throws { lock.withLock { credentials = value } }
    func clear() throws { lock.withLock { credentials = nil } }
}

private struct LoadingHolidayClient: HolidayFetching {
    func fetch(year _: Int) async throws -> HolidaysSnapshot { throw CocoaError(.fileReadUnknown) }
}

private struct LoadingNotificationScheduler: DailyCourseNotificationScheduling {
    func authorizationStatus(timeout _: Duration) async throws -> DailyCourseNotificationAuthorization { .denied }
    func requestAuthorization(timeout _: Duration) async throws -> Bool { false }
    func replacePending(with _: [DailyCourseNotificationRequest], revision _: UInt64) async throws {}
    func cancelPending(revision _: UInt64) {}
}
