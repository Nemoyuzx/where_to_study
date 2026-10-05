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

    func testGroupedAssignmentJoinUsesEveryOriginalSiteIDAndExactLegacyGroupName() {
        let a = TeachingCloudCourse(id: "a", name: "Same name")
        let b = TeachingCloudCourse(id: "b", name: "Same name")
        let cached = [assignment("id-match", courseID: "a", name: "Old name"),
                      assignment("different-id", courseID: "b", name: "Same name"),
                      assignment("legacy", courseID: nil, name: "Same name")]
        XCTAssertEqual(CourseListEvidence.teachingCloudAssignments(course: a, roster: [a, b], cached: cached).map(\.id), ["different-id", "id-match", "legacy"])
        XCTAssertEqual(CourseListEvidence.teachingCloudAssignments(course: a, roster: [a], cached: cached).map(\.id), ["id-match", "legacy"])
        XCTAssertTrue(CourseListEvidence.teachingCloudAssignments(course: a, roster: [a], cached: [assignment("partial-name", courseID: nil, name: "Same")]).isEmpty)
        XCTAssertTrue(CourseListEvidence.teachingCloudAssignments(course: a, roster: [a], cached: [assignment("foreign-id", courseID: "foreign", name: "Same name")]).isEmpty)
    }

    func testGroupedAssignmentsPreserveClassScopedDuplicatesAndCountBothClasses() throws {
        let roster = [TeachingCloudCourse(id: "a", name: "Course"), TeachingCloudCourse(id: "b", name: " Course ")]
        let group = try XCTUnwrap(TeachingCloudCourseGrouping.groups(roster).first)
        let first = AssignmentDeadlineItem(id: "same-assignment-id", title: "Class A task", courseName: "Course",
            deadline: "2026-11-08 18:00:00", status: "未提交", courseID: "a")
        let second = AssignmentDeadlineItem(id: "same-assignment-id", title: "Class B task", courseName: "Course",
            deadline: "2026-11-08 18:00:00", status: "已提交", courseID: "b")
        let items = CourseListEvidence.teachingCloudAssignments(group: group, cached: [first, first, second])
        XCTAssertEqual(items, [first, second])
        XCTAssertEqual(Set(items.map(\.teachingCloudDisplayID)).count, 2, "Both class rows need independent SwiftUI identities")
        XCTAssertEqual(CourseListEvidence.submissionCounts(statuses: items.map(\.status)), .init(pending: 1, submitted: 1))
        XCTAssertEqual(CourseListEvidence.cachedAssignments(query: nil,
            byDate: ["2026-11-08": [first, second], "2026-11-09": [first]]).count, 2)
    }

    func testUnnamedCoursesNeverShareLegacyAssignmentsOrAnotherOriginalCourseID() throws {
        let roster = [TeachingCloudCourse(id: "a", name: nil), TeachingCloudCourse(id: "b", name: " ")]
        let group = try XCTUnwrap(TeachingCloudCourseGrouping.group(containing: "a", in: roster))
        let cached = [assignment("a-task", courseID: "a", name: nil),
                      assignment("b-task", courseID: "b", name: nil),
                      assignment("unknown", courseID: nil, name: " ")]
        XCTAssertEqual(CourseListEvidence.teachingCloudAssignments(group: group, cached: cached).map(\.id), ["a-task"])
    }

    func testCalendarSelectionForTheSecondClassResolvesTheWholeCurrentCourseGroup() throws {
        let roster = [TeachingCloudCourse(id: "a", name: "Course"), TeachingCloudCourse(id: "b", name: "Course")]
        let first = assignment("first", courseID: "a", name: "Course")
        let second = assignment("second", courseID: "b", name: "Course")
        let selected = try XCTUnwrap(CourseDeadlineCalendarProjection.teachingCloudSelection(second, roster: roster))
        XCTAssertEqual(selected.courseID, "b", "Calendar events keep their original class binding")
        let group = try XCTUnwrap(TeachingCloudCourseGrouping.group(containing: selected.courseID, in: roster))
        XCTAssertEqual(group.id, "a")
        XCTAssertEqual(CourseListEvidence.teachingCloudAssignments(group: group, cached: [first, second]), [first, second])
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

    func testAdministrativeReviewRequestMatchingIsExactAndAssignmentOnly() throws {
        for title in ["COURSEWORK MARK REVIEW REQUEST", " coursework\tmark\nreview request ",
                      "\u{FEFF}Coursework:\u{A0}Mark\u{202F}Review—Request", "coursework-mark_review/request:form",
                      "ＣＯＵＲＳＥＷＯＲＫ　ＭＡＲＫ　ＲＥＶＩＥＷ　ＲＥＱＵＥＳＴ－ＦＯＲＭ"] {
            XCTAssertFalse(QMplusCourseSelection.includesActivity(try qmplusItem("2", title: title)), title)
        }
        for title in ["Unscheduled coursework", "COURSEWORK MARK REVIEW REQUEST Essay",
                      "COURSEWORK MARK REVIEW REQUEST FORMS", "COURSEWORK MARK REVIEW REQUEST FORMULATION",
                      "Review and Feedback Essay", "COURSEWORK MARK REVIEWS REQUEST",
                      "COURSEWORK MARK REVIEW REQUEST?", "COURSEWORK MARK REVIEW REQUEST (FORM)",
                      "Coursework: Mark · Review—Request", "COURSEWORK|MARK|REVIEW|REQUEST",
                      "ℂOURSEWORK MARK REVIEW REQUEST"] {
            let item = try qmplusItem("2", title: title)
            XCTAssertNil(item.dueAt)
            XCTAssertTrue(QMplusCourseSelection.includesActivity(item), title)
        }
        XCTAssertTrue(QMplusCourseSelection.includesActivity(try qmplusItem("2", title: "COURSEWORK MARK REVIEW REQUEST", kind: .quiz)))
    }

    func testLegacyReviewRequestsAreExcludedFromDetailsSelectionAndBothSubmissionCounts() throws {
        let course = QMplusCourse(id: "1", name: "EBU Original course", shortName: nil,
            url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/course/view.php?id=1")),
            startAt: nil, endAt: nil, currentTermStatus: .current)
        let activities = [try qmplusItem("2", title: "COURSEWORK MARK REVIEW REQUEST", status: "not submitted"),
                          try qmplusItem("3", title: "Coursework mark review request / form", status: "submitted"),
                          try qmplusItem("4", title: "Real assignment without a deadline", status: "not submitted"),
                          try qmplusItem("5", title: "COURSEWORK MARK REVIEW REQUEST Essay", status: "submitted"),
                          try qmplusItem("6", title: "COURSEWORK MARK REVIEW REQUEST", kind: .quiz, status: "submitted")]
        let cached = QMplusSnapshot(schemaVersion: 1, source: "qmplus", fetchedAt: "2026-10-03T12:00:00.000Z",
            courses: [course], activities: activities, warnings: [])
        XCTAssertEqual(CourseListEvidence.qmplusActivities(courseID: "1", snapshot: cached).map(\.id), ["4", "5", "6"])
        XCTAssertEqual(CourseListEvidence.qmplusCounts(activities: cached.activities), CourseSubmissionCounts(pending: 1, submitted: 1))
        for history in [false, true] {
            XCTAssertEqual(QMplusCourseSelection(snapshot: cached, showsOtherTerms: history).activities.map(\.id), ["4", "5", "6"])
        }
        XCTAssertEqual(cached.activities.count, 5, "Filtering an old snapshot must not rewrite its source records")
        XCTAssertTrue(cached.activities.allSatisfy { $0.dueAt == nil })
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

    private func qmplusItem(_ id: String, title: String, kind: QMplusActivity.Kind = .assignment,
                            status: String = "unknown") throws -> QMplusActivity {
        QMplusActivity(id: id, courseID: "1", title: title, kind: kind,
            url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/mod/\(kind == .quiz ? "quiz" : "assign")/view.php?id=\(id)")),
            dueAt: nil, opensAt: nil, closesAt: nil, cutoffAt: nil, timeLimitSeconds: nil,
            status: status, detailStatus: "available", rawTimeText: nil)
    }
}
