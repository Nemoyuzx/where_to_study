import XCTest

#if os(macOS)
@testable import WhereToStudyMac

final class TodayCourseWidgetDataTests: XCTestCase {
    func testWidgetArchiveSelectsAndOrdersCoursesForRequestedDate() throws {
        let archive = TodayCourseWidgetData.Archive(
            termStartDate: "2026-03-02",
            fetchedAt: "2026-03-01T12:00:00+08:00",
            courses: [
                course(id: "later", name: "神经网络", weekday: 1, weeks: [1], startSlot: 8),
                course(id: "other-day", name: "羽毛球", weekday: 2, weeks: [1], startSlot: 2),
                course(id: "earlier", name: "数据挖掘", weekday: 1, weeks: [1], startSlot: 2)
            ]
        )

        let date = try XCTUnwrap(StrictContractDateParser.date(from: "2026-03-02"))
        let courses = TodayCourseWidgetData.courses(on: date, archive: archive)

        XCTAssertEqual(courses.map(\.id), ["earlier", "later"])
    }

    func testWidgetArchiveReturnsNoCoursesOutsideCourseWeeks() throws {
        let archive = TodayCourseWidgetData.Archive(
            termStartDate: "2026-03-02",
            fetchedAt: "2026-03-01T12:00:00+08:00",
            courses: [course(id: "course", name: "数据挖掘", weekday: 1, weeks: [1], startSlot: 2)]
        )
        let secondWeek = try XCTUnwrap(StrictContractDateParser.date(from: "2026-03-09"))

        XCTAssertTrue(TodayCourseWidgetData.courses(on: secondWeek, archive: archive).isEmpty)
    }

    private func course(
        id: String,
        name: String,
        weekday: Int,
        weeks: [Int],
        startSlot: Int
    ) -> TodayCourseWidgetData.Course {
        .init(
            id: id,
            name: name,
            room: "教二楼-335",
            timeRange: "09:50-10:35",
            weekday: weekday,
            weekNumbers: weeks,
            examWeekNumbers: [],
            startSlot: startSlot
        )
    }
}
#endif
