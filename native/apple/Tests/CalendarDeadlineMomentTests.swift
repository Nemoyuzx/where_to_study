import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class CalendarDeadlineMomentTests: XCTestCase {
    func testDeadlinePointsAreAdditionalAndKeepOriginalAllDayEvents() throws {
        let date = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-06"))
        let events = [cloud("a", "2026-10-06 17:35:59"), cloud("b", "2026-10-06 17:35"),
                      cloud("date-only", "2026-10-06"), CalendarAllDayEvent(id: "public", title: "public", time: "17:35", kind: .competition)]
        let day = CalendarTimelineDay(date: date, courses: [], holidays: [], allDayEvents: events)
        XCTAssertEqual(day.allDayEvents, events)
        XCTAssertEqual(day.deadlineMoments.map(\.minute), [17 * 60 + 35])
        XCTAssertEqual(day.deadlineMoments[0].events.map(\.id), ["a", "b"])
        XCTAssertEqual(day.deadlineMoments[0].time, "17:35")
        let updated = CalendarTimelineDay(copying: day, allDayEvents: [events[2]])
        XCTAssertEqual(updated.allDayEvents, [events[2]])
        XCTAssertTrue(updated.deadlineMoments.isEmpty)
        XCTAssertEqual(updated.coursePlacements, day.coursePlacements)
    }

    func testExplicitTimestampsUseShanghaiDateAndUnknownTimesAreNotInvented() throws {
        let date = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-06"))
        let events = [cloud("z", "2026-10-05T16:15:00Z"), cloud("offset", "2026-10-05T17:15:00+01:00"),
                      cloud("tomorrow", "2026-10-06T16:00:00Z"), cloud("missing", "2026-10-06"),
                      cloud("bad-day", "2026-02-30 12:00"), cloud("bad-hour", "2026-10-06 24:00"),
                      cloud("bad-second", "2026-10-06 12:00:60"), cloud("garbage", "2026-10-06 12:00oops")]
        let moments = CalendarDeadlineMomentLogic.moments(on: date, events: events)
        XCTAssertEqual(moments.map(\.minute), [15])
        XCTAssertEqual(moments[0].events.map(\.id), ["z", "offset"])
    }

    func testQMplusTypedPointsAreDeduplicatedAndMinuteAxisIncludesDayEdges() throws {
        let date = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-06"))
        let qm = CalendarAllDayEvent(id: "qm", title: "Quiz", time: "07:45", kind: .assignment,
            courseSelection: .init(source: .qmplus, courseID: "ebu"))
        let untyped = CalendarAllDayEvent(id: "untyped", title: "No time evidence", time: "12:00", kind: .assignment)
        let moments = CalendarDeadlineMomentLogic.moments(on: date,
            events: [cloud("zero", "2026-10-06 00:00"), qm, qm, cloud("last", "2026-10-06 23:59:59"), untyped])
        XCTAssertEqual(moments.map(\.minute), [0, 465, 1439])
        XCTAssertEqual(moments[1].events.count, 1)
        XCTAssertEqual(CalendarTimelineLogic.bounds(for: [], deadlineMinutes: moments.map(\.minute)), 0 ... 1440)
        XCTAssertEqual(CalendarTimelineLogic.bounds(for: []), 480 ... 1320)
        XCTAssertEqual(CalendarTimelineLogic.bounds(for: [], deadlineMinutes: [465]), 420 ... 1320)
    }

    func testOnlyBadgeMovesToProtectCourseTitlesAndViewportEdges() {
        XCTAssertEqual(CalendarDeadlineMomentLogic.badgeCenter(anchor: 0, lower: 0, upper: 100,
            courseTitleStarts: []), 9)
        XCTAssertEqual(CalendarDeadlineMomentLogic.badgeCenter(anchor: 99, lower: 0, upper: 100,
            courseTitleStarts: []), 91)
        XCTAssertEqual(CalendarDeadlineMomentLogic.badgeCenter(anchor: 40, lower: 0, upper: 100,
            courseTitleStarts: [40]), 81)
        XCTAssertEqual(CalendarDeadlineMomentLogic.badgeCenter(anchor: 40, lower: 0, upper: 100,
            courseTitleStarts: [], previous: 39), 59)
    }

    func testHorizontalDeadlineStripUsesTheDayColumnWithFourPointInsets() {
        XCTAssertEqual(CalendarDeadlineMomentLogic.markerWidth(dayWidth: 100), 92)
        XCTAssertEqual(CalendarDeadlineMomentLogic.markerWidth(dayWidth: 50), 42)
        XCTAssertEqual(CalendarDeadlineMomentLogic.markerWidth(dayWidth: 200), 192)
        XCTAssertEqual(CalendarDeadlineMomentLogic.markerWidth(dayWidth: 4), 1)
    }

    func testOwnerWideCacheProjectsCrossDayDeadlinesWithoutChangingOriginalAllDayBucket() throws {
        let rawDay = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-05"))
        let actualDay = try XCTUnwrap(StrictContractDateParser.date(from: "2026-10-06"))
        let event = cloud("utc", "2026-10-05T16:15:00Z")
        let days = [CalendarTimelineDay(date: rawDay, courses: [], holidays: [], allDayEvents: [event]),
                    CalendarTimelineDay(date: actualDay, courses: [], holidays: [], allDayEvents: [])]
        let projected = CourseDeadlineCalendarProjection.applying(to: days, snapshot: nil, enabled: false,
            assignments: [try XCTUnwrap(event.assignmentItem)])
        XCTAssertEqual(projected[0].allDayEvents, [event])
        XCTAssertTrue(projected[1].allDayEvents.isEmpty)
        XCTAssertTrue(projected[0].deadlineMoments.isEmpty)
        XCTAssertEqual(projected[1].deadlineMoments.map(\.minute), [15])
        XCTAssertEqual(projected[1].deadlineMoments.first?.events.first?.assignmentItem?.courseID, "course")
    }

    func testCloseTailTimesShareOneBadgeButRetainEveryExactMinuteAnchor() {
        let first = CalendarDeadlineMoment(minute: 1438, events: [cloud("a", "2026-10-06 23:58")])
        let last = CalendarDeadlineMoment(minute: 1439, events: [cloud("b", "2026-10-06 23:59")])
        let display = CalendarDeadlineMomentLogic.displayMoments([first, last], hourHeight: 64)
        XCTAssertEqual(display.count, 1)
        XCTAssertEqual(display.first?.anchorMinutes, [1438, 1439])
        XCTAssertEqual(display.first?.events.map(\.id), ["a", "b"])
        XCTAssertEqual(CalendarDeadlineMomentLogic.displayMoments([first,
            .init(minute: 60, events: [])].sorted { $0.minute < $1.minute }, hourHeight: 64).count, 2)
    }

    func testOnlyExplicitUnsubmittedEvidenceMarksTheDeadlineStrip() {
        func event(_ status: String?) -> CalendarAllDayEvent {
            .init(id: "a", title: "a", kind: .assignment,
                assignmentItem: .init(id: "a", title: "a", courseName: nil, deadline: "2026-10-06 23:59", status: status))
        }
        XCTAssertTrue(event("未提交").hasPendingSubmission)
        XCTAssertTrue(event("No submissions have been made yet").hasPendingSubmission)
        XCTAssertFalse(event("已提交").hasPendingSubmission)
        XCTAssertFalse(event(nil).hasPendingSubmission)
        XCTAssertFalse(event("Unknown").hasPendingSubmission)
        XCTAssertFalse(event("Draft").hasPendingSubmission)
        XCTAssertTrue(CalendarDeadlineMoment(minute: 1439, events: [event(nil), event("未提交")]).hasPendingSubmission)
    }

    private func cloud(_ id: String, _ deadline: String) -> CalendarAllDayEvent {
        CalendarAllDayEvent(id: id, title: id, kind: .assignment,
            assignmentItem: .init(id: id, title: id, courseName: "Course", deadline: deadline, status: nil, courseID: "course"))
    }
}
