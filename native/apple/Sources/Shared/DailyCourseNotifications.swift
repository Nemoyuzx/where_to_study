import Foundation
import CoreFoundation
import UserNotifications

enum DailyCourseNotificationSettings {
    static let enabledKey = "dailyCourseNotificationsEnabled"
    static let minutesKey = "dailyCourseNotificationMinutes"
    static let defaultMinutes = 450

    static func normalizedMinutes(_ minutes: Int) -> Int {
        (0 ... 1439).contains(minutes) ? minutes : defaultMinutes
    }

    static func loadMinutes(defaults: UserDefaults) -> Int {
        // Do not use integer(forKey:): a missing value would become midnight.
        guard let value = defaults.object(forKey: minutesKey) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue == Double(value.intValue)
        else { return defaultMinutes }
        return normalizedMinutes(value.intValue)
    }
}

enum DailyCourseNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

enum DailyCourseNotificationAuthorizationError: LocalizedError, Equatable, Sendable {
    case timedOut

    var errorDescription: String? {
        "通知权限状态读取超时，请在系统设置中确认通知权限。"
    }
}

enum DailyCourseNotificationForegroundPolicy {
    static func presentationOptions(
        identifier: String,
        isEnabled: Bool,
        preClassEnabled: Bool = false
    ) -> UNNotificationPresentationOptions {
        guard (isEnabled && identifier.hasPrefix(DailyCourseNotificationPlanner.identifierPrefix))
            || (preClassEnabled && identifier.hasPrefix(PreClassNotificationPlanner.identifierPrefix))
        else { return [] }
        return [.banner, .list, .sound]
    }
}

final class DailyCourseNotificationForegroundDelegate: NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let shared = DailyCourseNotificationForegroundDelegate()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(DailyCourseNotificationForegroundPolicy.presentationOptions(
            identifier: notification.request.identifier,
            isEnabled: defaults.bool(forKey: DailyCourseNotificationSettings.enabledKey),
            preClassEnabled: defaults.bool(forKey: PreClassNotificationSettings.enabledKey)
        ))
    }
}

protocol UserNotificationCenterDelegateInstalling: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }
}

extension UNUserNotificationCenter: UserNotificationCenterDelegateInstalling {}

enum DailyCourseNotificationCenterConfiguration {
    static func installForegroundDelegate(
        center: any UserNotificationCenterDelegateInstalling = UNUserNotificationCenter.current(),
        delegate: DailyCourseNotificationForegroundDelegate = .shared
    ) {
        center.delegate = delegate
    }
}

struct DailyCourseNotificationRequest: Equatable, Sendable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}

enum DailyCourseNotificationPlanner {
    static let identifierPrefix = "daily-course-summary."
    // iOS keeps at most 64 pending local notifications. Reserve one slot for
    // other app features and fill the remaining slots with actual course days.
    static let maximumPendingRequestCount = 63
    static let maximumScheduleWeek = 53
    static let maximumScanDayCount = 400

    static func requests(
        for schedule: ScheduleSnapshot,
        after now: Date,
        dailyCourseNotificationMinutes: Int = DailyCourseNotificationSettings.defaultMinutes,
        scanDayLimit: Int? = nil,
        language: AppLanguage = .simplifiedChinese,
        calendar: Calendar = .shanghai
    ) -> [DailyCourseNotificationRequest] {
        guard
            let termStart = StrictContractDateParser.date(
                from: schedule.termStartDate,
                calendar: calendar
            ),
            let lastCourseWeek = schedule.courses.flatMap(\.weekNumbers).filter({ $0 > 0 }).max()
                ?? (schedule.examSchedule?.items.isEmpty == false ? 1 : nil)
        else { return [] }

        let minutes = DailyCourseNotificationSettings.normalizedMinutes(dailyCourseNotificationMinutes)
        let startOfToday = calendar.startOfDay(for: now)
        let boundedLastWeek = min(lastCourseWeek, maximumScheduleWeek)
        guard
            let courseLastDay = calendar.date(
                byAdding: .day,
                value: boundedLastWeek * 7 - 1,
                to: calendar.startOfDay(for: termStart)
            )
        else { return [] }
        let lastExamDay = schedule.examSchedule?.items.compactMap {
            StrictContractDateParser.date(from: $0.date, calendar: calendar)
        }.max()
        let termLastDay = max(courseLastDay, lastExamDay ?? courseLastDay)
        let remainingTermDays = (calendar.dateComponents(
            [.day],
            from: startOfToday,
            to: termLastDay
        ).day ?? -1) + 1
        guard remainingTermDays > 0 else { return [] }

        let requestedScanDays = scanDayLimit.map { max(0, $0) } ?? remainingTermDays
        let scanDayCount = min(requestedScanDays, remainingTermDays, maximumScanDayCount)
        var requests = [DailyCourseNotificationRequest]()
        requests.reserveCapacity(min(maximumPendingRequestCount, scanDayCount))

        for dayOffset in 0 ..< scanDayCount {
            if requests.count == maximumPendingRequestCount { break }
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                let fireDate = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                fireDate > now
            else { continue }

            let courses = ScheduleLogic.courses(
                on: day,
                termStart: termStart,
                courses: schedule.courses,
                exams: schedule.examSchedule,
                calendar: calendar
            )
            guard !courses.isEmpty else { continue }
            let entries = courses.map { course in
                let location = course.room.isEmpty ? "" : " @ \(course.room)"
                let kind = course.isExam ? AppLocalization.string("考试", language: language) + " · " : ""
                let time = course.isExam && course.minuteInterval == nil
                    ? AppLocalization.string("时间待定", language: language) : course.timeRange
                return "\(kind)\(time) \(course.name)\(location)"
            }
            let date = StrictContractDateParser.string(from: day, calendar: calendar)
            requests.append(DailyCourseNotificationRequest(
                identifier: identifierPrefix + date,
                fireDate: fireDate,
                title: String(format: AppLocalization.string("今日课程 · %d 门", language: language),
                              locale: language.locale, courses.count),
                body: entries.joined(separator: "；")
            ))
        }
        return requests
    }

}

protocol DailyCourseNotificationScheduling: Sendable {
    func authorizationStatus(timeout: Duration) async throws -> DailyCourseNotificationAuthorization
    func requestAuthorization(timeout: Duration) async throws -> Bool
    func replacePending(
        with requests: [DailyCourseNotificationRequest],
        revision: UInt64
    ) async throws
    func cancelPending(revision: UInt64)
    func clearPending(revision: UInt64)
    func cancelPending(category: CourseNotificationCategory, revision: UInt64, includingDelivered: Bool)
    func invalidate(revision: UInt64)
}

extension DailyCourseNotificationScheduling {
    func clearPending(revision: UInt64) { cancelPending(revision: revision) }
    func cancelPending(category _: CourseNotificationCategory, revision: UInt64, includingDelivered _: Bool) {
        cancelPending(revision: revision)
    }
    func cancelPending(category: CourseNotificationCategory, revision: UInt64) {
        cancelPending(category: category, revision: revision, includingDelivered: true)
    }
    func invalidate(revision _: UInt64) {}
}

protocol CourseNotificationCenter: Sendable {
    func authorizationStatus(
        completion: @escaping @Sendable (DailyCourseNotificationAuthorization) -> Void
    )
    func requestAuthorization(
        completion: @escaping @Sendable (Result<Bool, any Error>) -> Void
    )
    func add(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date
    ) async throws
    func removePending(withIdentifiers identifiers: [String])
    func removeDelivered(withIdentifiers identifiers: [String])
    func deliveredIdentifiers(completion: @escaping @Sendable ([String]) -> Void)
}

extension CourseNotificationCenter {
    func deliveredIdentifiers(completion: @escaping @Sendable ([String]) -> Void) { completion([]) }
}

enum DailyCourseNotificationReconcileOutcome: Equatable, Sendable {
    case disabled
    case permissionDenied
    case permissionRequired
    case waitingForSchedule
    case scheduled(Int)
    case scheduledReminders(daily: Int, preClass: Int)
}

struct DailyCourseNotificationCoordinator: Sendable {
    let scheduler: any DailyCourseNotificationScheduling
    var authorizationTimeout: Duration = .seconds(8)

    func reconcile(
        enabled: Bool,
        requestPermissionIfNeeded: Bool,
        hasCredentials: Bool,
        schedule: ScheduleSnapshot?,
        dailyCourseNotificationMinutes: Int = DailyCourseNotificationSettings.defaultMinutes,
        preClassEnabled: Bool = false,
        preClassOffsets: [Int] = PreClassNotificationSettings.defaultOffsets,
        language: AppLanguage = .simplifiedChinese,
        now: Date = .now,
        revision: UInt64,
        onAuthorized: @MainActor @Sendable () -> Void = {}
    ) async throws -> DailyCourseNotificationReconcileOutcome {
        guard enabled || preClassEnabled else {
            scheduler.cancelPending(revision: revision)
            return .disabled
        }

        let status = try await scheduler.authorizationStatus(timeout: authorizationTimeout)
        try Task.checkCancellation()
        let authorized: Bool
        switch status {
        case .authorized:
            authorized = true
        case .notDetermined where requestPermissionIfNeeded:
            authorized = try await scheduler.requestAuthorization(timeout: authorizationTimeout)
        case .notDetermined:
            scheduler.clearPending(revision: revision)
            return .permissionRequired
        case .denied:
            authorized = false
        }
        try Task.checkCancellation()
        guard authorized else {
            scheduler.cancelPending(revision: revision)
            return .permissionDenied
        }
        await onAuthorized()
        try Task.checkCancellation()
        guard hasCredentials, let schedule else {
            scheduler.clearPending(revision: revision)
            return .waitingForSchedule
        }

        let summaries = enabled ? DailyCourseNotificationPlanner.requests(
            for: schedule,
            after: now,
            dailyCourseNotificationMinutes: dailyCourseNotificationMinutes,
            language: language
        ) : []
        let reminders = preClassEnabled ? PreClassNotificationPlanner.requests(
            for: schedule, after: now, offsets: preClassOffsets, language: language
        ) : []
        let requests = CourseNotificationPlan.earliest(summaries + reminders, after: now)
        try await scheduler.replacePending(with: requests, revision: revision)
        if preClassEnabled {
            let daily = requests.filter { $0.identifier.hasPrefix(DailyCourseNotificationPlanner.identifierPrefix) }.count
            return .scheduledReminders(daily: daily, preClass: requests.count - daily)
        }
        return .scheduled(requests.count)
    }
}

private final class CallbackTimeoutResolver<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<Value, any Error>, Never>?

    init(continuation: CheckedContinuation<Result<Value, any Error>, Never>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<Value, any Error>) {
        let continuation = lock.withLock {
            let current = self.continuation
            self.continuation = nil
            return current
        }
        continuation?.resume(returning: result)
    }
}

private func callbackValueBeforeTimeout<Value: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable (@escaping @Sendable (Result<Value, any Error>) -> Void) -> Void
) async throws -> Value {
    let result = await withCheckedContinuation { continuation in
        let resolver = CallbackTimeoutResolver<Value>(continuation: continuation)
        let timeoutTask = Task.detached {
            do {
                try await ContinuousClock().sleep(for: timeout)
            } catch {
                return
            }
            resolver.resolve(.failure(DailyCourseNotificationAuthorizationError.timedOut))
        }
        operation {
            timeoutTask.cancel()
            resolver.resolve($0)
        }
    }
    return try result.get()
}

final class UserNotificationCourseScheduler: DailyCourseNotificationScheduling, @unchecked Sendable {
    private static let storedIdentifiersKey = "dailyCourseNotificationIdentifiers"

    private let center: any CourseNotificationCenter
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let revisionLock = NSLock()
    private var currentRevision: UInt64 = 0

    init(
        center: any CourseNotificationCenter = SystemCourseNotificationCenter(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.center = center
        self.defaults = defaults
        self.now = now
    }

    func authorizationStatus(timeout: Duration) async throws -> DailyCourseNotificationAuthorization {
        try await callbackValueBeforeTimeout(timeout) { completion in
            self.center.authorizationStatus { completion(.success($0)) }
        }
    }

    func requestAuthorization(timeout: Duration) async throws -> Bool {
        try await callbackValueBeforeTimeout(timeout) { completion in
            self.center.requestAuthorization(completion: completion)
        }
    }

    func replacePending(
        with requests: [DailyCourseNotificationRequest],
        revision: UInt64
    ) async throws {
        let batch = CourseNotificationPlan.earliest(requests, after: now()).map {
            ($0, systemIdentifier(for: $0, revision: revision))
        }
        let replacementIdentifiers = Set(batch.map(\.1))
        guard let identifiersToRemove = prepareRevision(
            revision,
            replacementIdentifiers: replacementIdentifiers
        ) else {
            return
        }
        await removePendingNotifications(identifiersToRemove)

        var firstFailure: (any Error)?
        for (request, identifier) in batch {
            guard isCurrent(revision) else { return }
            guard request.fireDate > now() else { continue }
            // Retry an individual transient failure once. A failed reminder
            // must not prevent another reminder or daily summary being added.
            for attempt in 0 ... 1 {
                guard isCurrent(revision), request.fireDate > now() else { break }
                do {
                    try await center.add(identifier: identifier, title: request.title,
                                         body: request.body, fireDate: request.fireDate)
                    break
                } catch {
                    if attempt == 1 { firstFailure = firstFailure ?? error }
                }
            }
            guard isCurrent(revision) else {
                center.removePending(withIdentifiers: [identifier])
                return
            }
        }
        if let firstFailure { throw firstFailure }
    }

    func cancelPending(revision: UInt64) {
        guard let identifiersToRemove = prepareRevision(revision, replacementIdentifiers: []) else {
            return
        }
        let center = center
        Task.detached(priority: .utility) {
            Self.removeNotifications(identifiersToRemove, center: center)
        }
        removeRetiredDeliveredNotifications(category: nil)
    }

    func invalidate(revision: UInt64) {
        revisionLock.withLock { currentRevision = max(currentRevision, revision) }
    }

    func clearPending(revision: UInt64) {
        guard let identifiers = prepareRevision(revision, replacementIdentifiers: []) else { return }
        let center = center
        Task.detached(priority: .utility) { center.removePending(withIdentifiers: identifiers) }
    }

    func cancelPending(category: CourseNotificationCategory, revision: UInt64, includingDelivered: Bool) {
        let identifiers: [String]? = revisionLock.withLock {
            guard revision >= currentRevision else { return nil }
            currentRevision = revision
            let existing = storedIdentifiers()
            let removed = Set(ownedNotificationIdentifiers().filter { $0.hasPrefix(category.identifierPrefix) })
            storeIdentifiers(existing.subtracting(removed))
            return removed.sorted()
        }
        guard let identifiers else { return }
        let center = center
        Task.detached(priority: .utility) {
            center.removePending(withIdentifiers: identifiers)
            if includingDelivered { center.removeDelivered(withIdentifiers: identifiers) }
        }
        if includingDelivered { removeRetiredDeliveredNotifications(category: category) }
    }

    private func prepareRevision(
        _ revision: UInt64,
        replacementIdentifiers: Set<String>
    ) -> [String]? {
        revisionLock.lock()
        defer { revisionLock.unlock() }
        guard revision >= currentRevision else { return nil }
        currentRevision = revision
        let identifiersToRemove = ownedNotificationIdentifiers(
            additionalIdentifiers: replacementIdentifiers
        )
        storeIdentifiers(replacementIdentifiers)
        return identifiersToRemove
    }

    private func isCurrent(_ revision: UInt64) -> Bool {
        revisionLock.lock()
        defer { revisionLock.unlock() }
        return revision == currentRevision
    }

    private func systemIdentifier(
        for request: DailyCourseNotificationRequest,
        revision: UInt64
    ) -> String {
        "\(request.identifier).revision-\(revision)"
    }

    private func ownedNotificationIdentifiers(
        additionalIdentifiers: Set<String> = []
    ) -> [String] {
        storedIdentifiers()
            .union(additionalIdentifiers)
            .union(legacyDateIdentifiers())
            .filter { CourseNotificationCategory.owns($0) }
            .sorted()
    }

    private func removePendingNotifications(_ identifiers: [String]) async {
        let center = center
        await Task.detached(priority: .utility) {
            center.removePending(withIdentifiers: identifiers)
        }.value
    }

    private func removeRetiredDeliveredNotifications(category: CourseNotificationCategory?) {
        // A normal replan leaves delivered notifications alone. At an explicit
        // cancellation boundary also remove delivered IDs from older batches,
        // which are no longer in the persisted pending set. A newer batch may
        // arrive while the asynchronous system lookup is in flight; retain it.
        center.deliveredIdentifiers { [weak self] identifiers in
            guard let self else { return }
            let removed = self.revisionLock.withLock {
                let active = self.storedIdentifiers()
                return identifiers.filter { identifier in
                    CourseNotificationCategory.owns(identifier)
                        && (category.map { identifier.hasPrefix($0.identifierPrefix) } ?? true)
                        && !active.contains(identifier)
                }
            }
            if !removed.isEmpty { self.center.removeDelivered(withIdentifiers: removed) }
        }
    }

    private static func removeNotifications(
        _ identifiers: [String],
        center: any CourseNotificationCenter
    ) {
        center.removePending(withIdentifiers: identifiers)
        center.removeDelivered(withIdentifiers: identifiers)
    }

    private func storedIdentifiers() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.storedIdentifiersKey) ?? [])
    }

    private func storeIdentifiers(_ identifiers: Set<String>) {
        defaults.set(identifiers.sorted(), forKey: Self.storedIdentifiersKey)
    }

    private func legacyDateIdentifiers() -> Set<String> {
        let calendar = Calendar.shanghai
        let today = calendar.startOfDay(for: now())
        let radius = DailyCourseNotificationPlanner.maximumScanDayCount
        return Set((-radius ... radius).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return String(
                format: "%@%04d-%02d-%02d",
                DailyCourseNotificationPlanner.identifierPrefix,
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            )
        })
    }
}

private final class SystemCourseNotificationCenter: CourseNotificationCenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus(
        completion: @escaping @Sendable (DailyCourseNotificationAuthorization) -> Void
    ) {
        center.getNotificationSettings { settings in
            let status: DailyCourseNotificationAuthorization = switch settings.authorizationStatus {
            case .notDetermined: .notDetermined
            case .denied: .denied
            case .authorized, .provisional, .ephemeral: .authorized
            @unknown default: .denied
            }
            completion(status)
        }
    }

    func requestAuthorization(
        completion: @escaping @Sendable (Result<Bool, any Error>) -> Void
    ) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(granted))
            }
        }
    }

    func add(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var components = Calendar.shanghai.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.timeZone = Calendar.shanghai.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        ))
    }

    func removePending(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func deliveredIdentifiers(completion: @escaping @Sendable ([String]) -> Void) {
        center.getDeliveredNotifications { notifications in
            completion(notifications.map { $0.request.identifier })
        }
    }
}
