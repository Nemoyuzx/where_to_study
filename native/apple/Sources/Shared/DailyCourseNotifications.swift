import Foundation
import UserNotifications

enum DailyCourseNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
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
            let termStart = contractDate(schedule.termStartDate, calendar: calendar),
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
            let date = contractDateString(day, calendar: calendar)
            requests.append(DailyCourseNotificationRequest(
                identifier: identifierPrefix + date,
                fireDate: fireDate,
                title: "今日课程 · \(courses.count) 门",
                body: entries.joined(separator: "；")
            ))
        }
        return requests
    }

    private static func contractDate(_ value: String, calendar: Calendar) -> Date? {
        var components = DateComponents()
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    private static func contractDateString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

protocol DailyCourseNotificationScheduling: Sendable {
    func authorizationStatus() async -> DailyCourseNotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func replacePending(
        with requests: [DailyCourseNotificationRequest],
        revision: UInt64
    ) async throws
    func cancelPending(revision: UInt64)
}

protocol CourseNotificationCenter: Sendable {
    func authorizationStatus() async -> DailyCourseNotificationAuthorization
    func requestAuthorization() async throws -> Bool
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

        let status = await scheduler.authorizationStatus()
        let authorized: Bool
        switch status {
        case .authorized:
            authorized = true
        case .notDetermined where requestPermissionIfNeeded:
            authorized = try await scheduler.requestAuthorization()
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

    func authorizationStatus() async -> DailyCourseNotificationAuthorization {
        await center.authorizationStatus()
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization()
    }

    func replacePending(
        with requests: [DailyCourseNotificationRequest],
        revision: UInt64
    ) async throws {
        let batch = requests.prefix(DailyCourseNotificationPlanner.maximumPendingRequestCount).map {
            ($0, systemIdentifier(for: $0, revision: revision))
        }
        let replacementIdentifiers = Set(batch.map(\.1))
        guard prepareRevision(revision, replacementIdentifiers: replacementIdentifiers) else {
            return
        }

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
        _ = prepareRevision(revision, replacementIdentifiers: [])
    }

    private func prepareRevision(
        _ revision: UInt64,
        replacementIdentifiers: Set<String>
    ) -> Bool {
        revisionLock.lock()
        defer { revisionLock.unlock() }
        guard revision >= currentRevision else { return false }
        currentRevision = revision
        removeOwnedNotifications(additionalIdentifiers: replacementIdentifiers)
        storeIdentifiers(replacementIdentifiers)
        return true
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

    private func removeOwnedNotifications(additionalIdentifiers: Set<String> = []) {
        let identifiers = storedIdentifiers()
            .union(additionalIdentifiers)
            .union(legacyDateIdentifiers())
            .filter { $0.hasPrefix(DailyCourseNotificationPlanner.identifierPrefix) }
            .sorted()
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

    func authorizationStatus() async -> DailyCourseNotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
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
