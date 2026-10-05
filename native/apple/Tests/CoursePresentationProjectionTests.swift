import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

// Pure production policy specifications. Not executed under the user's current
// prohibition on local automated tests; no WebView, credentials or requests.
@MainActor
final class CoursePresentationProjectionTests: XCTestCase {
    func testExpansionAndInfoSelectionAreIndependentAndResettable() {
        let session = CoursesViewSession()
        session.toggleExpansion(source: .teachingCloud, courseID: "same-id")
        XCTAssertTrue(session.isExpanded(source: .teachingCloud, courseID: "same-id"))
        XCTAssertFalse(session.isExpanded(source: .qmplus, courseID: "same-id"))
        XCTAssertNil(session.detailSelection)
        session.presentDetails(source: .qmplus, courseID: "same-id")
        XCTAssertEqual(session.detailSelection, .init(source: .qmplus, courseID: "same-id"))
        XCTAssertFalse(session.isExpanded(source: .qmplus, courseID: "same-id"))
        session.toggleExpansion(source: .qmplus, courseID: "same-id")
        session.collapseQMplus()
        XCTAssertTrue(session.isExpanded(source: .teachingCloud, courseID: "same-id"))
        XCTAssertFalse(session.isExpanded(source: .qmplus, courseID: "same-id"))
        session.reset()
        XCTAssertTrue(session.expandedCourseKeys.isEmpty)
        XCTAssertNil(session.detailSelection)
    }

    func testAllTermGroupingPreservesEveryResultAndDoesNotGuessMissingSemester() {
        let items = [grade("a", term: "2026-2027-1"), grade("b", term: nil),
                     grade("c", term: "2025-2026-2"), grade("d", term: " 2026-2027-1 "), grade("e", term: " ")]
        let groups = GradeTermGrouping.groups(items)
        XCTAssertEqual(groups.map(\.name), ["2026-2027-1", nil, "2025-2026-2"])
        XCTAssertEqual(groups.map { $0.items.map(\.id) }, [["a", "d"], ["b", "e"], ["c"]])
        XCTAssertEqual(groups.flatMap(\.items).count, items.count)
        XCTAssertEqual(groups[0].items[0].score, "0")
        XCTAssertEqual(groups[0].items[0].credits, "0")
        XCTAssertTrue(GradeTermGrouping.groups([]).isEmpty)
    }

    func testCalendarUsesAssignmentDueAndQuizCloseOnlyInShanghaiDay() throws {
        let snapshot = fixture(activities: [
            activity("assignment", due: "2026-10-05T16:15:00Z", cutoff: "2026-10-07T00:00:00Z"),
            activity("no-due", due: nil, cutoff: "2026-10-05T16:15:00Z"),
            activity("quiz", kind: .quiz, opens: "2026-10-05T08:00:00Z", closes: "2026-10-05T16:30:00Z"),
            activity("quiz-open-only", kind: .quiz, opens: "2026-10-05T16:00:00Z"),
            activity("bad-date", due: "not-a-date")])
        let today = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-05"))
        let next = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-06"))
        XCTAssertTrue(CourseDeadlineCalendarProjection.qmplusEvents(on: today, snapshot: snapshot, enabled: true).isEmpty)
        let events = CourseDeadlineCalendarProjection.qmplusEvents(on: next, snapshot: snapshot, enabled: true)
        XCTAssertEqual(events.map(\.id), ["qmplus-calendar|assignment", "qmplus-calendar|quiz"])
        XCTAssertEqual(events.map(\.time), ["00:15", "00:30"])
        XCTAssertTrue(events.allSatisfy { $0.kind == .assignment && $0.courseSelection?.courseID == "current" })
        XCTAssertEqual(CourseListEvidence.qmplusActivities(courseID: "current", snapshot: snapshot).count, 5,
                       "Unknown dates remove only the calendar projection, never real course activity cards")
    }

    func testProjectionHonorsOtherTermSwitchAdministrativeFilterAndFeatureOff() throws {
        let old = QMplusCourse(id: "old", name: "EBU OLD", shortName: nil,
                               url: URL(string: "https://qmplus.qmul.ac.uk/course/view.php?id=old")!,
                               startAt: nil, endAt: nil, currentTermStatus: .other)
        let snapshot = fixture(activities: [activity("current", due: "2026-10-05T09:00:00Z"),
            activity("review", title: "COURSEWORK MARK REVIEW REQUEST", due: "2026-10-05T09:00:00Z"),
            activity("old", courseID: "old", due: "2026-10-05T09:00:00Z")], otherCourses: [old])
        let day = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-05"))
        XCTAssertEqual(CourseDeadlineCalendarProjection.qmplusEvents(on: day, snapshot: snapshot, enabled: true).count, 1)
        XCTAssertEqual(CourseDeadlineCalendarProjection.qmplusEvents(on: day, snapshot: snapshot,
            enabled: true, showsOtherTerms: true).count, 2)
        let holiday = CalendarAllDayEvent(id: "holiday", title: "holiday", kind: .holiday)
        let exam = CalendarAllDayEvent(id: "exam", title: "exam", kind: .exam)
        let base = CalendarTimelineDay(date: day, courses: [], holidays: [], allDayEvents: [holiday, exam])
        let first = CourseDeadlineCalendarProjection.applying(to: [base], snapshot: snapshot, enabled: true)
        let again = CourseDeadlineCalendarProjection.applying(to: first, snapshot: snapshot, enabled: true)
        XCTAssertEqual(first[0].allDayEvents, again[0].allDayEvents)
        let off = CourseDeadlineCalendarProjection.applying(to: again, snapshot: snapshot, enabled: false)
        XCTAssertEqual(off[0].allDayEvents, [holiday, exam])
        let qmEvent = try XCTUnwrap(first[0].allDayEvents.first { $0.courseSelection != nil })
        XCTAssertNil(CourseDeadlineCalendarProjection.selection(for: qmEvent, roster: [], snapshot: snapshot, enabled: false))
        XCTAssertNil(CourseDeadlineCalendarProjection.selection(for: qmEvent, roster: [], snapshot: nil, enabled: true))
    }

    func testCourseNavigationRequiresCurrentExplicitCourseIDRatherThanGuessingNames() {
        let roster = [TeachingCloudCourse(id: "one", name: "Same"), TeachingCloudCourse(id: "two", name: "Same")]
        let unnamed = AssignmentDeadlineItem(id: "a", title: "a", courseName: "Same", deadline: "2026-10-05 18:00", status: nil)
        XCTAssertNil(CourseDeadlineCalendarProjection.teachingCloudSelection(unnamed, roster: roster))
        XCTAssertNil(CourseDeadlineCalendarProjection.teachingCloudSelection(unnamed, roster: Array(roster.prefix(1))))
        let identified = AssignmentDeadlineItem(id: "a", title: "a", courseName: "Same", deadline: "2026-10-05 18:00", status: nil, courseID: "two")
        XCTAssertEqual(CourseDeadlineCalendarProjection.teachingCloudSelection(identified, roster: roster),
                       .init(source: .teachingCloud, courseID: "two"))
        XCTAssertNil(CourseDeadlineCalendarProjection.teachingCloudSelection(identified, roster: Array(roster.prefix(1))))
    }

    private func grade(_ id: String, term: String?) -> GradeItem {
        .init(id: id, name: id, score: "0", credits: "0", courseCode: nil,
              courseAttribute: nil, courseNature: nil, examNature: nil, semesterName: term)
    }

    private func fixture(activities: [QMplusActivity], otherCourses: [QMplusCourse] = []) -> QMplusSnapshot {
        let course = QMplusCourse(id: "current", name: "EBU CURRENT", shortName: nil,
            url: URL(string: "https://qmplus.qmul.ac.uk/course/view.php?id=current")!,
            startAt: nil, endAt: nil, currentTermStatus: .current)
        return QMplusSnapshot(schemaVersion: 1, source: "qmplus", fetchedAt: "2026-10-05T12:00:00Z",
            courses: [course] + otherCourses, activities: activities, warnings: [])
    }

    private func activity(_ id: String, courseID: String = "current", title: String? = nil,
                          kind: QMplusActivity.Kind = .assignment, due: String? = nil,
                          cutoff: String? = nil, opens: String? = nil, closes: String? = nil) -> QMplusActivity {
        .init(id: id, courseID: courseID, title: title ?? id, kind: kind,
              url: URL(string: "https://qmplus.qmul.ac.uk/mod/\(kind.rawValue)/view.php?id=\(id)")!,
              dueAt: due, opensAt: opens, closesAt: closes, cutoffAt: cutoff, timeLimitSeconds: nil,
              status: nil, detailStatus: "available", rawTimeText: nil)
    }
}
