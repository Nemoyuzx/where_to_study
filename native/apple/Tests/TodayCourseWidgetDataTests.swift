import XCTest

#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class TodayCourseWidgetDataTests: XCTestCase {
    func testWidgetEmptyStateAlwaysUsesNoCoursesCopy() {
        XCTAssertEqual(TodayCourseWidgetData.emptyMessage, "今日无课")
        XCTAssertEqual(
            TodayCourseWidgetData.emptyMessage(language: .english),
            "No classes today"
        )
    }

    func testWidgetLanguageUsesChineseOnlyForChineseSystemLanguages() {
        XCTAssertEqual(
            TodayCourseWidgetData.Language.resolve(
                rawValue: "system",
                preferredLanguages: ["zh-Hans-CN"]
            ),
            .simplifiedChinese
        )
        XCTAssertEqual(
            TodayCourseWidgetData.Language.resolve(
                rawValue: "system",
                preferredLanguages: ["ja-JP"]
            ),
            .english
        )
        XCTAssertEqual(
            TodayCourseWidgetData.Language.resolve(
                rawValue: "en",
                preferredLanguages: ["zh-Hans"]
            ),
            .english
        )
        XCTAssertEqual(AppLocalization.defaultsKey, TodayCourseWidgetData.languageDefaultsKey)
    }

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
        XCTAssertNil(TodayCourseWidgetData.weekNumber(on: secondWeek, archive: archive))
    }

    func testWidgetPreferencesNormalizeCourseLimit() {
        XCTAssertEqual(
            TodayCourseWidgetData.Preferences(showsLocation: false, courseLimit: 0).normalized,
            .init(showsLocation: false, courseLimit: 1)
        )
        XCTAssertEqual(
            TodayCourseWidgetData.Preferences(showsLocation: true, courseLimit: 8).normalized,
            .init(showsLocation: true, courseLimit: 6)
        )
    }

    func testLegacyWidgetPreferencesDefaultToShowingTeacher() throws {
        let data = try XCTUnwrap(#"{"showsLocation":false,"courseLimit":9}"#.data(using: .utf8))
        let preferences = try JSONDecoder().decode(TodayCourseWidgetData.Preferences.self, from: data)

        XCTAssertTrue(preferences.showsTeacher)
        XCTAssertEqual(preferences.normalized.courseLimit, 6)
    }

    func testWidgetStatusHighlightsCurrentThenUpcomingCourse() throws {
        let courses = TodayCourseWidgetData.previewCourses()
        let duringFirstCourse = try date(hour: 10, minute: 0)
        let betweenCourses = try date(hour: 12, minute: 30)

        XCTAssertEqual(
            TodayCourseWidgetData.highlightedCourseID(in: courses, at: duringFirstCourse),
            "widget-preview-data-mining"
        )
        XCTAssertEqual(
            TodayCourseWidgetData.statusSummary(for: courses, at: duringFirstCourse),
            "进行中 · 12:15 下课"
        )
        XCTAssertEqual(
            TodayCourseWidgetData.highlightedCourseID(in: courses, at: betweenCourses),
            "widget-preview-network"
        )
        XCTAssertEqual(
            TodayCourseWidgetData.statusSummary(for: courses, at: betweenCourses),
            "下一节 · 13:00"
        )
        XCTAssertEqual(
            TodayCourseWidgetData.statusSummary(
                for: courses,
                at: duringFirstCourse,
                language: .english
            ),
            "Now · ends 12:15"
        )
        XCTAssertEqual(
            TodayCourseWidgetData.CoursePhase.upcoming.badgeText(language: .english),
            "Next"
        )
    }

    func testWidgetEnglishDayContextLocalizesOnlyStaticDateLabels() throws {
        let monday = try XCTUnwrap(StrictContractDateParser.date(from: "2026-03-02"))
        XCTAssertEqual(
            TodayCourseWidgetData.dayContext(
                on: monday,
                weekNumber: 1,
                language: .english
            ),
            "Mar 2 · Mon · Calendar Week 10 · Teaching Week 1"
        )
        XCTAssertEqual(TodayCourseWidgetData.previewCourses().first?.name, "高等数学")
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
            startSlot: startSlot
        )
    }

    private func date(hour: Int, minute: Int) throws -> Date {
        try XCTUnwrap(Calendar.shanghai.date(from: DateComponents(
            timeZone: Calendar.shanghai.timeZone,
            year: 2026,
            month: 3,
            day: 2,
            hour: hour,
            minute: minute
        )))
    }
}
