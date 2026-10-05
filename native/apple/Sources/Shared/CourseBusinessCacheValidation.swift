import Foundation
import CoreFoundation

/// Pure validation of business-only cache envelopes. No filesystem, Keychain,
/// account lookup, credential digest, browser data or network access.
enum CourseBusinessCacheValidation {
    static let maximumCloudBytes = 2 * 1024 * 1024
    static let maximumQMplusBytes = QMplusSnapshotPolicy.maximumBytes
    static let maximumQMplusEnvelopeBytes = maximumQMplusBytes + 2048

    static func validate(data: Data, kind: CourseBusinessCacheKind, now: Date = .now) throws {
        let maximum = kind == .qmplus ? maximumQMplusEnvelopeBytes : maximumCloudBytes
        guard data.count <= maximum,
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(envelope.keys) == ["schemaVersion", "scope", "fetchedAt", "partial", "payload"],
              integer(envelope["schemaVersion"]) == 1,
              let scope = envelope["scope"] as? [String: Any], Set(scope.keys) == ["owner", "epoch"],
              let owner = scope["owner"] as? String, let epoch = scope["epoch"] as? String,
              opaqueUUID(epoch), validOwner(owner, kind: kind),
              let fetchedAt = envelope["fetchedAt"] as? String, let date = fetchedDate(fetchedAt),
              now.timeIntervalSince1970.isFinite, date.timeIntervalSince(now) <= 60,
              boolean(envelope["partial"]) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }

        switch kind {
        case .courses: try validateCourses(envelope["payload"])
        case .assignments: try validateAssignments(envelope["payload"])
        case .qmplus: try validateQMplus(envelope["payload"], envelopeDate: date)
        }
    }

    private static func opaqueUUID(_ value: String) -> Bool {
        value.utf8.count == 36 && UUID(uuidString: value)?.uuidString == value.uppercased()
    }

    private static func validOwner(_ value: String, kind: CourseBusinessCacheKind) -> Bool {
        // Public fixed sources are not personal identifiers. Older OS QMplus
        // legitimately uses "legacy"; deterministic account hashes are never
        // accepted as owners of this new business cache format.
        opaqueUUID(value) || value == kind.domain || (kind == .qmplus && value == "legacy")
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue == Double(number.intValue) else { return nil }
        return number.intValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func fetchedDate(_ value: String) -> Date? {
        guard value.utf16.count <= 64,
              value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,9})?Z$",
                          options: .regularExpression) != nil,
              StrictContractDateParser.date(from: String(value.prefix(10))) != nil else { return nil }
        return QMplusSnapshotPolicy.utcDate(value)
    }

    private static func keys(_ row: [String: Any], allowed: Set<String>, required: Set<String>) throws {
        let actual = Set(row.keys)
        guard actual.isSubset(of: allowed), required.isSubset(of: actual) else { throw CocoaError(.fileReadCorruptFile) }
    }

    @discardableResult
    private static func text(_ value: Any?, maximum: Int, nonempty: Bool = false, optional: Bool = false) throws -> String? {
        if optional && (value == nil || value is NSNull) { return nil }
        guard let value = value as? String, value.utf16.count <= maximum,
              !nonempty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }

    private static func validateCourses(_ payload: Any?) throws {
        guard let courses = payload as? [[String: Any]], courses.count <= 100 else { throw CocoaError(.fileReadCorruptFile) }
        var identifiers = Set<String>()
        for row in courses {
            try keys(row, allowed: ["id", "name", "teacherNames"], required: ["id", "teacherNames"])
            guard let id = try text(row["id"], maximum: 128, nonempty: true), identifiers.insert(id).inserted,
                  let teachers = row["teacherNames"] as? [String], teachers.count <= 20 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try text(row["name"], maximum: 2048, optional: true)
            for teacher in teachers { try text(teacher, maximum: 256, nonempty: true) }
        }
    }

    private static func validateAssignments(_ payload: Any?) throws {
        guard let items = payload as? [[String: Any]], items.count <= 5000 else { throw CocoaError(.fileReadCorruptFile) }
        var keysSeen = Set<[String]>()
        for row in items {
            try keys(row, allowed: ["id", "title", "courseName", "deadline", "status", "courseID"],
                     required: ["id", "title", "deadline"])
            guard let id = try text(row["id"], maximum: 256, nonempty: true),
                  let deadline = try text(row["deadline"], maximum: 64, nonempty: true),
                  StrictContractDateParser.date(from: String(deadline.prefix(10))) != nil,
                  AssignmentDeadlineParser.isValidCachedDeadline(deadline),
                  keysSeen.insert([id, deadline]).inserted else { throw CocoaError(.fileReadCorruptFile) }
            // The canonical client deduplicates by (id, deadline), not title,
            // course name or a guessed endpoint-specific numeric ID format.
            try text(row["title"], maximum: 2048, nonempty: true)
            try text(row["courseName"], maximum: 2048, optional: true)
            try text(row["status"], maximum: 512, optional: true)
            try text(row["courseID"], maximum: 128, nonempty: true, optional: true)
        }
    }

    private static func validateQMplus(_ payload: Any?, envelopeDate: Date) throws {
        guard let snapshot = payload as? [String: Any],
              Set(snapshot.keys) == ["schema_version", "source", "fetched_at", "courses", "activities", "warnings"],
              let fetchedAt = snapshot["fetched_at"] as? String, let date = fetchedDate(fetchedAt),
              abs(date.timeIntervalSince(envelopeDate)) < 0.001,
              let courses = snapshot["courses"] as? [[String: Any]],
              let activities = snapshot["activities"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        for course in courses {
            try keys(course, allowed: ["id", "name", "short_name", "url", "start_at", "end_at", "current_term_status"],
                     required: ["id", "name", "url", "current_term_status"])
        }
        for activity in activities {
            try keys(activity, allowed: ["id", "course_id", "title", "kind", "url", "due_at", "opens_at", "closes_at",
                                         "cutoff_at", "time_limit_seconds", "status", "detail_status", "raw_time_text"],
                     required: ["id", "course_id", "title", "kind", "url", "detail_status"])
        }
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.withoutEscapingSlashes])
        guard data.count <= maximumQMplusBytes else { throw CocoaError(.fileReadCorruptFile) }
        // Existing policy validates all DTOs and safe official URLs before its
        // presentation-only administrative Assignment filter is applied.
        _ = try QMplusSnapshotPolicy.decode(data)
    }
}
