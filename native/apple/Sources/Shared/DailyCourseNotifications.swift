import Foundation
import UserNotifications

enum DailyCourseNotificationSettings {
    static let enabledKey = "dailyCourseNotificationsEnabled"
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
        isEnabled: Bool
    ) -> UNNotificationPresentationOptions {
        guard
            isEnabled,
            identifier.hasPrefix(DailyCourseNotificationPlanner.identifierPrefix)
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
            isEnabled: defaults.bool(forKey: DailyCourseNotificationSettings.enabledKey)
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
        scanDayLimit: Int? = nil,
        calendar: Calendar = .shanghai
    ) -> [DailyCourseNotificationRequest] {
        guard
            let termStart = StrictContractDateParser.date(
                from: schedule.termStartDate,
                calendar: calendar
            ),
            let lastCourseWeek = schedule.courses
                .flatMap(\.weekNumbers)
                .filter({ $0 > 0 })
                .max()
        else { return [] }

        let startOfToday = calendar.startOfDay(for: now)
        let boundedLastWeek = min(lastCourseWeek, maximumScheduleWeek)
        guard
            let termLastDay = calendar.date(
                byAdding: .day,
                value: boundedLastWeek * 7 - 1,
                to: calendar.startOfDay(for: termStart)
            )
        else { return [] }
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
                let fireDate = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: day),
                fireDate > now
            else { continue }

            let courses = ScheduleLogic.courses(
                on: day,
                termStart: termStart,
                courses: schedule.courses,
                calendar: calendar
            )
            guard !courses.isEmpty else { continue }
            let week = ScheduleLogic.weekNumber(on: day, termStart: termStart, calendar: calendar)
            let entries = courses.map { course in
                let name = course.examWeekNumbers.contains(week) ? "\(course.name)（试）" : course.name
                let location = course.room.isEmpty ? "" : " @ \(course.room)"
                return "\(course.timeRange) \(name)\(location)"
            }
            let date = StrictContractDateParser.string(from: day, calendar: calendar)
            requests.append(DailyCourseNotificationRequest(
                identifier: identifierPrefix + date,
                fireDate: fireDate,
                title: "今日课程 · \(courses.count) 门",
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
}

enum DailyCourseNotificationReconcileOutcome: Equatable, Sendable {
    case disabled
    case permissionDenied
    case waitingForSchedule
    case scheduled(Int)
}

struct DailyCourseNotificationCoordinator: Sendable {
    let scheduler: any DailyCourseNotificationScheduling
    var authorizationTimeout: Duration = .seconds(8)

    func reconcile(
        enabled: Bool,
        requestPermissionIfNeeded: Bool,
        hasCredentials: Bool,
        schedule: ScheduleSnapshot?,
        now: Date = .now,
        revision: UInt64
    ) async throws -> DailyCourseNotificationReconcileOutcome {
        guard enabled else {
            scheduler.cancelPending(revision: revision)
            return .disabled
        }

        let status = try await scheduler.authorizationStatus(timeout: authorizationTimeout)
        let authorized: Bool
        switch status {
        case .authorized:
            authorized = true
        case .notDetermined where requestPermissionIfNeeded:
            authorized = try await scheduler.requestAuthorization(timeout: authorizationTimeout)
        case .notDetermined, .denied:
            authorized = false
        }
        guard authorized else {
            scheduler.cancelPending(revision: revision)
            return .permissionDenied
        }
        guard hasCredentials, let schedule else {
            scheduler.cancelPending(revision: revision)
            return .waitingForSchedule
        }

        let requests = DailyCourseNotificationPlanner.requests(for: schedule, after: now)
        try await scheduler.replacePending(with: requests, revision: revision)
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
        operation { resolver.resolve($0) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout.timeInterval) {
            resolver.resolve(.failure(DailyCourseNotificationAuthorizationError.timedOut))
        }
    }
    return try result.get()
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return max(0, TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
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
        let batch = requests.prefix(DailyCourseNotificationPlanner.maximumPendingRequestCount).map {
            ($0, systemIdentifier(for: $0, revision: revision))
        }
        let replacementIdentifiers = Set(batch.map(\.1))
        guard let identifiersToRemove = prepareRevision(
            revision,
            replacementIdentifiers: replacementIdentifiers
        ) else {
            return
        }
        await removeNotifications(identifiersToRemove)

        for (request, identifier) in batch {
            guard isCurrent(revision) else { return }
            try await center.add(
                identifier: identifier,
                title: request.title,
                body: request.body,
                fireDate: request.fireDate
            )
            guard isCurrent(revision) else {
                center.removePending(withIdentifiers: [identifier])
                return
            }
        }
    }

    func cancelPending(revision: UInt64) {
        guard let identifiersToRemove = prepareRevision(revision, replacementIdentifiers: []) else {
            return
        }
        let center = center
        Task.detached(priority: .utility) {
            Self.removeNotifications(identifiersToRemove, center: center)
        }
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
            .filter { $0.hasPrefix(DailyCourseNotificationPlanner.identifierPrefix) }
            .sorted()
    }

    private func removeNotifications(_ identifiers: [String]) async {
        let center = center
        await Task.detached(priority: .utility) {
            Self.removeNotifications(identifiers, center: center)
        }.value
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
}
