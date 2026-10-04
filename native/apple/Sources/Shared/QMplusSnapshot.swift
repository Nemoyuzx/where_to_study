import Foundation

enum QMplusCurrentTermStatus: String, Codable, Sendable {
    case current, other, unknown
}

struct QMplusCourse: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let shortName: String?
    let url: URL
    let startAt: String?
    let endAt: String?
    let currentTermStatus: QMplusCurrentTermStatus
    enum CodingKeys: String, CodingKey {
        case id, name, url
        case shortName = "short_name", startAt = "start_at", endAt = "end_at"
        case currentTermStatus = "current_term_status"
    }
}

struct QMplusActivity: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case assignment, quiz }
    let id: String
    let courseID: String
    let title: String
    let kind: Kind
    let url: URL
    let dueAt: String?
    let opensAt: String?
    let closesAt: String?
    let cutoffAt: String?
    let timeLimitSeconds: Int?
    let status: String?
    let detailStatus: String
    let rawTimeText: String?
    enum CodingKeys: String, CodingKey {
        case id, title, kind, url, status
        case courseID = "course_id", dueAt = "due_at", opensAt = "opens_at"
        case closesAt = "closes_at", cutoffAt = "cutoff_at", timeLimitSeconds = "time_limit_seconds"
        case detailStatus = "detail_status", rawTimeText = "raw_time_text"
    }
}

struct QMplusSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let source: String
    let fetchedAt: String
    let courses: [QMplusCourse]
    let activities: [QMplusActivity]
    let warnings: [String]
    enum CodingKeys: String, CodingKey {
        case source, courses, activities, warnings
        case schemaVersion = "schema_version", fetchedAt = "fetched_at"
    }
}

/// A presentation-only selection: the complete source snapshot stays intact.
struct QMplusCourseSelection: Equatable, Sendable {
    let courses: [QMplusCourse]
    let activities: [QMplusActivity]

    static func includesCourse(_ course: QMplusCourse) -> Bool {
        course.name.range(of: "EBU", options: [.anchored, .caseInsensitive]) != nil
    }

    init(snapshot: QMplusSnapshot, showsOtherTerms: Bool) {
        courses = snapshot.courses.filter {
            Self.includesCourse($0) && (showsOtherTerms || $0.currentTermStatus != .other)
        }
        let courseIDs = Set(courses.map(\.id))
        activities = snapshot.activities.filter { courseIDs.contains($0.courseID) }
    }
}

enum QMplusSnapshotError: Error { case invalidSnapshot }

enum QMplusSnapshotPolicy {
    static let maximumBytes = 512 * 1024

    static func isBusinessURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "qmplus.qmul.ac.uk",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        guard ["/course/view.php", "/mod/assign/view.php", "/mod/quiz/view.php"].contains(url.path),
              components.fragment == nil, let items = components.queryItems, items.count == 1,
              items[0].name == "id", let id = items[0].value else { return false }
        return id.range(of: "^[1-9][0-9]{0,15}$", options: .regularExpression) != nil
    }

    static func utcDate(_ value: String?) -> Date? {
        guard let value, value.hasSuffix("Z") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func decode(_ data: Data) throws -> QMplusSnapshot {
        guard data.count <= maximumBytes else { throw QMplusSnapshotError.invalidSnapshot }
        let snapshot = try JSONDecoder().decode(QMplusSnapshot.self, from: data)
        guard snapshot.schemaVersion == 1, snapshot.source == "qmplus", utcDate(snapshot.fetchedAt) != nil,
              snapshot.courses.count <= 100, snapshot.activities.count <= 500, snapshot.warnings.count <= 40,
              Set(snapshot.courses.map(\.id)).count == snapshot.courses.count,
              Set(snapshot.activities.map(\.id)).count == snapshot.activities.count else {
            throw QMplusSnapshotError.invalidSnapshot
        }
        let courseIDs = Set(snapshot.courses.map(\.id))
        func validText(_ value: String?, limit: Int) -> Bool { value.map { $0.utf16.count <= limit } ?? true }
        func validID(_ value: String) -> Bool { value.range(of: "^[1-9][0-9]{0,15}$", options: .regularExpression) != nil }
        func validDate(_ value: String?) -> Bool { value == nil || utcDate(value) != nil }
        guard snapshot.courses.allSatisfy({ course in
            validID(course.id) && !course.name.isEmpty && course.name.utf16.count <= 512
                && validText(course.shortName, limit: 512) && isBusinessURL(course.url)
                && course.url.path == "/course/view.php"
                && URLComponents(url: course.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == course.id
                && validDate(course.startAt) && validDate(course.endAt)
        }), snapshot.activities.allSatisfy({ activity in
            validID(activity.id) && courseIDs.contains(activity.courseID)
                && !activity.title.isEmpty && activity.title.utf16.count <= 512 && isBusinessURL(activity.url)
                && activity.url.path == (activity.kind == .assignment ? "/mod/assign/view.php" : "/mod/quiz/view.php")
                && URLComponents(url: activity.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == activity.id
                && validDate(activity.dueAt) && validDate(activity.opensAt)
                && validDate(activity.closesAt) && validDate(activity.cutoffAt)
                && validText(activity.rawTimeText, limit: 1000) && validText(activity.status, limit: 512)
                && ["available", "restricted", "unavailable"].contains(activity.detailStatus)
                && (activity.timeLimitSeconds.map { $0 >= 0 } ?? true)
        }), snapshot.warnings.allSatisfy({ $0.utf16.count <= 1000 }) else { throw QMplusSnapshotError.invalidSnapshot }
        return snapshot
    }
}
