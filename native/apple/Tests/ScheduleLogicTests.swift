import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

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

    func testSJDTransportUsesHTTPS() {
        XCTAssertEqual(SJDAPIClient.origin, "https://jwglweixin.bupt.edu.cn")
        XCTAssertEqual(URL(string: SJDAPIClient.origin)?.scheme, "https")
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

    func testScheduleRoomNormalizationKeepsThreeDigitAndDualDoorRooms() {
        XCTAssertEqual(SJDScheduleParser.normalizeCourseRoom("3-335"), "335")
        XCTAssertEqual(SJDScheduleParser.normalizeCourseRoom("教1-101"), "101")
        XCTAssertEqual(SJDScheduleParser.normalizeCourseRoom("202-203"), "202-203")
        XCTAssertEqual(SJDScheduleParser.normalizeCourseRoom("217-218"), "217-218")
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

    func testSharedHolidayFixtureMatchesContract() throws {
        let expected = try JSONDecoder().decode(
            HolidaysSnapshot.self,
            from: fixtureData("holidays.json")
        )
        let actual = try HolidaySourceParser.parse(
            data: fixtureData("holiday-source.json"),
            year: expected.year,
            source: expected.source,
            fetchedAt: expected.fetchedAt
        )

        XCTAssertEqual(actual, expected)
    }

    func testHolidayParserKeepsOnlyRequestedYearForCrossYearRange() throws {
        let source = """
        [{"name":"跨年假期","range":["2025-12-31","2026-01-02"],"type":"holiday"}]
        """.data(using: .utf8)!

        let snapshot = try HolidaySourceParser.parse(
            data: source,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        )

        XCTAssertEqual(snapshot.items.map(\.date), ["2026-01-01", "2026-01-02"])
    }

    func testHolidayParserRejectsOversizedOrMalformedSourceData() {
        let oversized = Data(repeating: 0x20, count: HolidaySourceLimits.maximumPayloadBytes + 1)
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: oversized,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let malformedDate = """
        [{"name":"测试","range":["2026-1-01"],"type":"holiday"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: malformedDate,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let malformedMiddleDate = """
        [{"name":"测试","range":["2026-01-01","2026-1-02","2026-01-03"],"type":"holiday"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: malformedMiddleDate,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let longRange = """
        [{"name":"测试","range":["2026-01-01","2026-02-02"],"type":"holiday"}]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: longRange,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let tooManyRecords = Array(
            repeating: ["name": "测试", "range": ["2026-01-01"], "type": "holiday"],
            count: HolidaySourceLimits.maximumRecords + 1
        )
        let tooManyRecordsData = try! JSONSerialization.data(withJSONObject: tooManyRecords)
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: tooManyRecordsData,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let longName = String(repeating: "节", count: HolidaySourceLimits.maximumNameLength + 1)
        let longNameData = try! JSONSerialization.data(withJSONObject: [[
            "name": longName,
            "range": ["2026-01-01"],
            "type": "holiday"
        ]])
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: longNameData,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))
    }

    func testHolidayStoreRoundTripsSharedFixture() throws {
        let expected = try JSONDecoder().decode(
            HolidaysSnapshot.self,
            from: fixtureData("holidays.json")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileHolidayStore(directoryURL: directory)

        try store.save(expected)

        XCTAssertEqual(try store.load(year: expected.year), expected)
    }

    func testHolidayStoreRejectsOversizedCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: HolidaySourceLimits.maximumPayloadBytes + 1)
            .write(to: directory.appendingPathComponent("holidays_2026.json"))
        let store = FileHolidayStore(directoryURL: directory)

        XCTAssertThrowsError(try store.load(year: 2026))
    }

    func testTimelineKeepsHourAndCourseSlotCoordinatesIndependent() {
        XCTAssertEqual(CalendarTimelineLogic.position(minute: 7 * 60 + 59), 0)
        XCTAssertEqual(CalendarTimelineLogic.position(minute: 8 * 60), 0)
        XCTAssertEqual(CalendarTimelineLogic.position(minute: 15 * 60), 0.5)
        XCTAssertEqual(CalendarTimelineLogic.position(minute: 22 * 60), 1)
        XCTAssertEqual(CalendarTimelineLogic.position(minute: 22 * 60 + 1), 1)
        XCTAssertEqual(CalendarTimelineLogic.minute(of: "09:50"), 9 * 60 + 50)
        XCTAssertNil(CalendarTimelineLogic.minute(of: "24:00"))
        XCTAssertTrue(CalendarTimelineLogic.hourLabelIsObscured(
            hourMinute: 17 * 60,
            currentMinute: 16 * 60 + 51
        ))
        XCTAssertFalse(CalendarTimelineLogic.hourLabelIsObscured(
            hourMinute: 17 * 60,
            currentMinute: 16 * 60 + 47
        ))
    }

    func testMobileTimelineViewportAdaptsToPhoneAndTabletSizeClasses() {
        XCTAssertEqual(CalendarTimelineLogic.mobileViewportHeight(
            compactWidth: true,
            compactHeight: false
        ), 420)
        XCTAssertEqual(CalendarTimelineLogic.mobileViewportHeight(
            compactWidth: true,
            compactHeight: true
        ), 300)
        XCTAssertEqual(CalendarTimelineLogic.mobileViewportHeight(
            compactWidth: false,
            compactHeight: false
        ), 700)
    }

    func testYearCourseDensityContinuesIncreasingPastFourCourses() {
        let opacities = [1, 4, 5, 8, 12].map {
            TeachingCalendarLogic.yearCourseOpacity(courseCount: $0)
        }

        XCTAssertEqual(TeachingCalendarLogic.yearCourseOpacity(courseCount: 0), 0)
        XCTAssertEqual(opacities, opacities.sorted())
        XCTAssertEqual(Set(opacities).count, opacities.count)
        XCTAssertLessThan(opacities.last!, 1)
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
