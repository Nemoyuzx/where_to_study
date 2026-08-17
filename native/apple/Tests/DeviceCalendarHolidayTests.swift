import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class DeviceCalendarHolidayTests: XCTestCase {
    func testNormalizedNameTrimsAndRejectsEmptyTitles() {
        XCTAssertEqual(DeviceCalendarHolidayLogic.normalizedName("  国庆节  "), "国庆节")
        XCTAssertNil(DeviceCalendarHolidayLogic.normalizedName("   "))
        XCTAssertNil(DeviceCalendarHolidayLogic.normalizedName(""))
    }

    func testKindClassifiesMakeupWorkdaysFromTitleKeywords() {
        XCTAssertEqual(DeviceCalendarHolidayLogic.kind(from: "春节补班"), "workday")
        XCTAssertEqual(DeviceCalendarHolidayLogic.kind(from: "国庆节调休"), "workday")
        XCTAssertEqual(DeviceCalendarHolidayLogic.kind(from: "端午节"), "holiday")
        XCTAssertEqual(DeviceCalendarHolidayLogic.kind(from: "国庆节"), "holiday")
    }

    func testDateStringRespectsRequestedYearAndShanghaiTimeZone() {
        let calendar = Calendar.shanghai
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)) else {
            return XCTFail("failed to build date")
        }
        XCTAssertEqual(
            DeviceCalendarHolidayLogic.dateString(date, year: 2026),
            "2026-10-01"
        )
        XCTAssertNil(DeviceCalendarHolidayLogic.dateString(date, year: 2025))
    }

    func testMergingWorkdaysAddsUniqueWorkdaysAndPreservesSource() {
        let base = HolidaysSnapshot(
            year: 2026,
            source: "device-calendar",
            fetchedAt: "2026-01-01T00:00:00Z",
            items: [HolidayItem(date: "2026-10-01", name: "国庆节", type: "holiday")]
        )
        let workday = HolidayItem(date: "2026-09-20", name: "国庆节补班", type: "workday")
        let merged = DeviceCalendarHolidayLogic.mergingWorkdays(
            into: base,
            workdays: [workday, workday]
        )

        XCTAssertEqual(merged.source, "device-calendar")
        XCTAssertEqual(merged.items.count, 2)
        XCTAssertEqual(merged.items.filter { $0.type == "workday" }.count, 1)

        let noAdditions = DeviceCalendarHolidayLogic.mergingWorkdays(into: base, workdays: [])
        XCTAssertEqual(noAdditions.items.count, 1)
    }
}
