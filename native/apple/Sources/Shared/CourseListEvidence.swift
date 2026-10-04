import Foundation

struct CourseSubmissionCounts: Equatable, Sendable {
    let pending: Int
    let submitted: Int
    var hasEvidence: Bool { pending > 0 || submitted > 0 }
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
        let uniqueName = course.name.map { name in roster.filter { $0.name == name }.count == 1 } ?? false
        var seen = Set<String>()
        return cached.filter { item in
            if let courseID = item.courseID { return courseID == course.id }
            return uniqueName && course.name != nil && item.courseName == course.name
        }.filter { seen.insert($0.id).inserted }
            .sorted { ($0.deadline, $0.id) < ($1.deadline, $1.id) }
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
        var seen = Set<String>()
        return byDate.keys.sorted(by: >).flatMap { byDate[$0] ?? [] }.filter { item in
            seen.insert((item.courseID ?? item.courseName ?? "") + "|" + item.id).inserted
        }
    }
}

enum CourseCatalogSource: String, Sendable { case teachingCloud, qmplus }

struct CourseCatalogSelection: Equatable, Sendable {
    let source: CourseCatalogSource
    let courseID: String
}
