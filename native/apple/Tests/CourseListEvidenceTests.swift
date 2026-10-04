import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class CourseListEvidenceTests: XCTestCase {
    func testCourseParserRetainsOnlyExistingTeacherNamesAndAssignmentSiteID() {
        let teachers: [[String: Any]] = [["name": " Tutor A "], ["name": "Tutor A"], ["name": "Tutor B"], ["name": 5]]
        let records: [[String: Any]] = [
            ["id": "site-a", "siteName": "Original API title", "teachers": teachers],
            ["id": "site-b", "siteName": "Another API title"]
        ]
        let courses = UCloudAssignmentClient.parseCurrentCourses(["data": ["records": records]])
        XCTAssertEqual(courses.first?.name, "Original API title")
        XCTAssertEqual(courses.first?.teacherNames, ["Tutor A", "Tutor B"])
        XCTAssertEqual(courses.last?.teacherNames, [])
        let record: [String: Any] = [
            "id": "assignment", "assignmentTitle": "Original homework", "endTime": "2026-11-08 18:00:00", "assignmentStatus": 0
        ]
        let items = AssignmentDeadlineParser.parseAll(root: ["records": [record]], courseNameOverride: "Original API title", courseIDOverride: "site-a")
        XCTAssertEqual(items.first?.courseID, "site-a")
        XCTAssertEqual(items.first?.courseName, "Original API title")
    }

    func testAssignmentJoinUsesSiteIDAndRequiresUniqueExactLegacyCourseName() {
        let a = TeachingCloudCourse(id: "a", name: "Same name")
        let b = TeachingCloudCourse(id: "b", name: "Same name")
        let cached = [assignment("id-match", courseID: "a", name: "Old name"),
                      assignment("different-id", courseID: "b", name: "Same name"),
                      assignment("legacy", courseID: nil, name: "Same name")]
        XCTAssertEqual(CourseListEvidence.teachingCloudAssignments(course: a, roster: [a, b], cached: cached).map(\.id), ["id-match"])
        XCTAssertEqual(CourseListEvidence.teachingCloudAssignments(course: a, roster: [a], cached: cached).map(\.id), ["id-match", "legacy"])
        XCTAssertTrue(CourseListEvidence.teachingCloudAssignments(course: a, roster: [a], cached: [assignment("partial-name", courseID: nil, name: "Same")]).isEmpty)
    }

    func testCountsUseOnlyExplicitSubmissionStatusNeverCompletionOrUnknown() {
        let counts = CourseListEvidence.submissionCounts(statuses: [" 已提交 ", "SUBMITTED", "Submitted for grading", "未提交", "not submitted", "nothing submitted", "no submissions have been made yet", "已完成", "已批改", "已驳回", "unknown", nil])
        XCTAssertEqual(counts, CourseSubmissionCounts(pending: 4, submitted: 3))
        XCTAssertFalse(CourseListEvidence.submissionCounts(statuses: [nil, "unknown", "completed"]).hasEvidence)
    }

    func testQuizCompletionDoesNotCountAsAssignmentSubmission() throws {
        func item(_ id: String, kind: QMplusActivity.Kind, status: String) throws -> QMplusActivity {
            QMplusActivity(id: id, courseID: "1", title: "Original API activity", kind: kind,
                           url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/mod/\(kind == .quiz ? "quiz" : "assign")/view.php?id=\(id)")),
                           dueAt: nil, opensAt: nil, closesAt: nil, cutoffAt: nil, timeLimitSeconds: nil,
                           status: status, detailStatus: "available", rawTimeText: nil)
        }
        let activities = [try item("2", kind: .quiz, status: "submitted"), try item("3", kind: .assignment, status: "unknown"), try item("4", kind: .assignment, status: "Submitted for grading")]
        XCTAssertEqual(CourseListEvidence.qmplusCounts(activities: activities), CourseSubmissionCounts(pending: 0, submitted: 1))
    }

    func testDateCacheDeduplicatesActivitiesAndShanghaiDisplayDoesNotTreatUTCAsLocal() {
        let item = assignment("same", courseID: "a", name: "A")
        XCTAssertEqual(CourseListEvidence.cachedAssignments(query: nil, byDate: ["2026-11-08": [item], "2026-11-09": [item]]).count, 1)
        XCTAssertEqual(CourseListEvidence.cachedAssignments(query: [], byDate: ["2026-11-08": [item]]), [])
        XCTAssertEqual(CourseListEvidence.qmplusShanghaiTime("2026-11-08T15:05:00Z"), "2026-11-08 23:05")
        XCTAssertNil(CourseListEvidence.qmplusShanghaiTime(nil))
    }

    @MainActor
    func testDetailSelectionIsSourceScopedAndResetWithoutAnyNetworkWork() {
        let session = CoursesViewSession()
        session.presentDetails(source: .qmplus, courseID: "1")
        XCTAssertEqual(session.detailSelection, CourseCatalogSelection(source: .qmplus, courseID: "1"))
        XCTAssertTrue(session.detailPresentation.isPresented)
        session.reset()
        XCTAssertNil(session.detailSelection)
        XCTAssertFalse(session.detailPresentation.isPresented)
    }

    private func assignment(_ id: String, courseID: String?, name: String?) -> AssignmentDeadlineItem {
        AssignmentDeadlineItem(id: id, title: "Original API assignment", courseName: name,
                               deadline: "2026-11-08 18:00:00", status: "未提交", courseID: courseID)
    }
}
