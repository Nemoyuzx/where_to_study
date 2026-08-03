import XCTest
@testable import WhereToStudyMac

final class ScheduleLogicTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: repositoryRoot
            .appendingPathComponent("contracts/v1/fixtures")
            .appendingPathComponent(name))
    }

    func testExamWeeksUseSeventeenthAndEighteenthExistingWeeks() {
        let weekly = Course(
            id: "weekly",
            name: "测试课程",
            teacher: "测试教师",
            room: "测试楼-101",
            weekText: "2-19",
            weekNumbers: Array(2...19),
            examWeekNumbers: [],
            weekday: 1,
            startSlot: 0,
            endSlot: 1,
            sectionText: "1-2节",
            timeRange: "08:00-09:35"
        )

        XCTAssertEqual(ScheduleLogic.examWeeks(in: [weekly]), Set([18, 19]))
    }

    func testWeekNumberUsesTermStartDate() {
        let calendar = Calendar.shanghai
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let target = calendar.date(byAdding: .day, value: 14, to: start)!

        XCTAssertEqual(ScheduleLogic.weekNumber(on: target, termStart: start), 3)
    }

    func testDateBeforeTermHasNoActiveWeek() {
        let calendar = Calendar.shanghai
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let target = calendar.date(byAdding: .day, value: -1, to: start)!

        XCTAssertEqual(ScheduleLogic.weekNumber(on: target, termStart: start), 0)
    }

    func testSharedSJDFixturesProduceContractSchedule() throws {
        let expected = try JSONDecoder().decode(
            ScheduleSnapshot.self,
            from: fixtureData("schedule.json")
        )
        let fetchedAt = ISO8601DateFormatter().date(from: expected.fetchedAt)!
        let parsed = try SJDScheduleParser.parse(
            currentData: fixtureData("sjd-current-week.json"),
            curriculumData: fixtureData("sjd-curriculum.json"),
            fallbackTermID: "fallback",
            fallbackTermStartDate: "2000-01-03",
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(parsed, expected)
    }

    func testScheduleStoreRoundTripsSharedFixture() throws {
        let expected = try JSONDecoder().decode(
            ScheduleSnapshot.self,
            from: fixtureData("schedule.json")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileScheduleStore(fileURL: directory.appendingPathComponent("schedule.json"))

        try store.save(expected)

        XCTAssertEqual(try store.load(), expected)
    }

    func testSharedSJDClassroomFixturesProduceContractCache() throws {
        let expected = try JSONDecoder().decode(
            ClassroomsCache.self,
            from: fixtureData("classrooms.json")
        )
        let parsed = try SJDClassroomParser.parse(
            payloads: [
                "01": fixtureData("sjd-classrooms-xitucheng.json"),
                "04": fixtureData("sjd-classrooms-shahe.json")
            ],
            targetDate: expected.targetDate,
            fetchedAt: expected.fetchedAt
        )

        XCTAssertEqual(parsed, expected)
    }

    func testClassroomStoreRoundTripsSharedFixture() throws {
        let expected = try JSONDecoder().decode(
            ClassroomsCache.self,
            from: fixtureData("classrooms.json")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileClassroomStore(fileURL: directory.appendingPathComponent("classrooms.json"))

        try store.save(expected)

        XCTAssertEqual(try store.load(), expected)
    }

    func testBusySlotsIncludeEverySlotCoveredByTodaysCourses() {
        let calendar = Calendar.shanghai
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let course = Course(
            id: "busy",
            name: "测试课程",
            teacher: "测试教师",
            room: "主楼-101",
            weekText: "1-18",
            weekNumbers: Array(1 ... 18),
            examWeekNumbers: [],
            weekday: 1,
            startSlot: 2,
            endSlot: 4,
            sectionText: "3-5节",
            timeRange: "09:50-12:15"
        )

        XCTAssertEqual(
            ScheduleLogic.busySlots(on: start, termStart: start, courses: [course]),
            Set([2, 3, 4])
        )
    }
}
