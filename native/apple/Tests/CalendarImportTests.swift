import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class CalendarImportTests: XCTestCase {
    func testEventDraftsExpandActualWeeksAndUseSlotBoundaries() throws {
        let schedule = fixtureSchedule(
            weeks: [1, 3],
            examWeeks: [3],
            weekday: 1,
            startSlot: 2,
            endSlot: 4
        )

        let drafts = try CalendarImportLogic.eventDrafts(from: schedule)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.map(\.title), ["数据挖掘", "试 数据挖掘"])
        XCTAssertEqual(drafts.map(\.location), ["教二楼-3-335", "教二楼-3-335"])
        XCTAssertEqual(Self.formatter.string(from: drafts[0].startDate), "2026-03-02 09:50")
        XCTAssertEqual(Self.formatter.string(from: drafts[0].endDate), "2026-03-02 12:15")
        XCTAssertEqual(Self.formatter.string(from: drafts[1].startDate), "2026-03-16 09:50")
    }

    func testEventMarkersAreStableDistinctAndRecoverableFromNotes() throws {
        let schedule = fixtureSchedule(weeks: [1, 1, 2], examWeeks: [])

        let drafts = try CalendarImportLogic.eventDrafts(from: schedule)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(Set(drafts.map(\.marker)).count, 2)
        XCTAssertEqual(CalendarImportLogic.marker(in: drafts[0].notes), drafts[0].marker)
        XCTAssertEqual(
            CalendarImportLogic.eventMarker(termID: schedule.termID, courseID: "course-1", week: 1),
            drafts[0].marker
        )
    }

    func testInvalidTermDateAndSlotFailInsteadOfCreatingWrongEvents() {
        let invalidDate = ScheduleSnapshot(
            termID: "2025-2026-2",
            termStartDate: "not-a-date",
            fetchedAt: "2026-03-01T00:00:00Z",
            courses: []
        )
        XCTAssertThrowsError(try CalendarImportLogic.eventDrafts(from: invalidDate)) { error in
            XCTAssertEqual(error as? CalendarImportError, .invalidTermStartDate)
        }

        let invalidSlot = fixtureSchedule(weeks: [1], examWeeks: [], startSlot: 14, endSlot: 14)
        XCTAssertThrowsError(try CalendarImportLogic.eventDrafts(from: invalidSlot)) { error in
            XCTAssertEqual(error as? CalendarImportError, .invalidCourse("数据挖掘"))
        }
    }

    func testDailyRefreshUsesNextSevenOClockWithoutPolling() throws {
        let before = try XCTUnwrap(Self.formatter.date(from: "2026-08-03 06:59"))
        let atTarget = try XCTUnwrap(Self.formatter.date(from: "2026-08-03 07:00"))
        let after = try XCTUnwrap(Self.formatter.date(from: "2026-08-03 07:01"))

        XCTAssertEqual(Self.formatter.string(from: DailyRefreshLogic.nextRefresh(after: before)), "2026-08-03 07:00")
        XCTAssertEqual(Self.formatter.string(from: DailyRefreshLogic.nextRefresh(after: atTarget)), "2026-08-04 07:00")
        XCTAssertEqual(Self.formatter.string(from: DailyRefreshLogic.nextRefresh(after: after)), "2026-08-04 07:00")
    }

    private func fixtureSchedule(
        weeks: [Int],
        examWeeks: [Int],
        weekday: Int = 1,
        startSlot: Int = 0,
        endSlot: Int = 1
    ) -> ScheduleSnapshot {
        ScheduleSnapshot(
            termID: "2025-2026-2",
            termStartDate: "2026-03-02",
            fetchedAt: "2026-03-01T00:00:00Z",
            courses: [
                Course(
                    id: "course-1",
                    name: "数据挖掘",
                    teacher: "测试教师",
                    room: "教二楼-3-335",
                    weekText: "测试周",
                    weekNumbers: weeks,
                    examWeekNumbers: examWeeks,
                    weekday: weekday,
                    startSlot: startSlot,
                    endSlot: endSlot,
                    sectionText: "第 1-2 节",
                    timeRange: ""
                ),
            ]
        )
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.shanghai.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
