import Foundation

struct CourseSubmissionCounts: Equatable, Sendable {
    let pending: Int
    let submitted: Int
    var hasEvidence: Bool { pending > 0 || submitted > 0 }
}

struct TeachingCloudAssignmentDisplayID: Hashable, Sendable {
    let courseID: String?
    let legacyCourseName: String?
    let assignmentID: String
}

extension AssignmentDeadlineItem {
    // Assignment IDs are scoped to their original classes in the merged UI.
    // This computed identity never changes the cached/API assignment record.
    var teachingCloudDisplayID: TeachingCloudAssignmentDisplayID {
        .init(courseID: courseID,
              legacyCourseName: courseID == nil ? TeachingCloudCourseGrouping.normalizedName(courseName) : nil,
              assignmentID: id)
    }
}

enum CourseListEvidence {
    static func qmplusShanghaiTime(_ value: String?) -> String? {
        guard let date = QMplusSnapshotPolicy.utcDate(value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .shanghai
        formatter.timeZone = Calendar.shanghai.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func submissionCounts(statuses: [String?]) -> CourseSubmissionCounts {
        let pending: Set<String> = ["未提交", "not submitted", "nothing submitted", "no submissions have been made yet"]
        let submitted: Set<String> = ["已提交", "submitted", "submitted for grading"]
        var pendingCount = 0, submittedCount = 0
        for status in statuses {
            guard let value = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { continue }
            if pending.contains(value) { pendingCount += 1 }
            if submitted.contains(value) { submittedCount += 1 }
        }
        return CourseSubmissionCounts(pending: pendingCount, submitted: submittedCount)
    }

    static func teachingCloudAssignments(course: TeachingCloudCourse, roster: [TeachingCloudCourse],
                                         cached: [AssignmentDeadlineItem]) -> [AssignmentDeadlineItem] {
        guard let group = TeachingCloudCourseGrouping.group(containing: course.id, in: roster) else { return [] }
        return teachingCloudAssignments(group: group, cached: cached)
    }

    static func teachingCloudAssignments(group: TeachingCloudCourseGroup,
                                         cached: [AssignmentDeadlineItem]) -> [AssignmentDeadlineItem] {
        let courseIDs = group.courseIDs
        var seen = Set<TeachingCloudAssignmentDisplayID>()
        return cached.filter { item in
            if let courseID = item.courseID { return courseIDs.contains(courseID) }
            return group.name != nil && TeachingCloudCourseGrouping.normalizedName(item.courseName) == group.name
        }.filter { seen.insert($0.teachingCloudDisplayID).inserted }
            .sorted { ($0.deadline, $0.id, $0.courseID ?? "") < ($1.deadline, $1.id, $1.courseID ?? "") }
    }

    static func qmplusActivities(courseID: String, snapshot: QMplusSnapshot?) -> [QMplusActivity] {
        (snapshot?.activities ?? []).filter { $0.courseID == courseID && QMplusCourseSelection.includesActivity($0) }
    }

    static func qmplusCounts(activities: [QMplusActivity]) -> CourseSubmissionCounts {
        submissionCounts(statuses: activities.filter { $0.kind == .assignment && QMplusCourseSelection.includesActivity($0) }.map(\.status))
    }

    static func cachedAssignments(query: [AssignmentDeadlineItem]?,
                                  byDate: [String: [AssignmentDeadlineItem]]) -> [AssignmentDeadlineItem] {
        if let query { return query }
        var seen = Set<TeachingCloudAssignmentDisplayID>()
        return byDate.keys.sorted(by: >).flatMap { byDate[$0] ?? [] }.filter { item in
            seen.insert(item.teachingCloudDisplayID).inserted
        }
    }
}

enum CourseCatalogSource: String, Sendable { case teachingCloud, qmplus }

struct CourseCatalogSelection: Equatable, Sendable {
    let source: CourseCatalogSource
    let courseID: String
}
