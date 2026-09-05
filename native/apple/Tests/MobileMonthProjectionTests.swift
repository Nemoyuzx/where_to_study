import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class MobileMonthProjectionTests: XCTestCase {
    func testFortyTwoDaysMatchExistingCourseAndAccessibilityLogicInBothLanguages() async throws {
        let worker = MobileMonthProjectionWorker()
        for language in [AppLanguage.simplifiedChinese, .english] {
            let input = try makeInput(language: language)
            let result = try await worker.build(input: input)
            let schedule = try XCTUnwrap(input.schedule)
            let termStart = try XCTUnwrap(StrictContractDateParser.date(from: schedule.termStartDate))
            let formatterCache = CalendarDateFormatterCache()
            let formatter = formatterCache.formatter(
                format: language == .english ? "EEEE, MMMM d, yyyy" : "yyyy年M月d日 EEEE",
                locale: language.locale
            )
            let todayKey = StrictContractDateParser.string(from: input.today)

            XCTAssertEqual(result.count, 42)
            XCTAssertEqual(result.map(\.date), input.days)
            XCTAssertEqual(result.first?.dateKey, "2026-08-31")
            XCTAssertEqual(result.last?.dateKey, "2026-10-11")
            for day in result {
                let expectedCourses = ScheduleLogic.courses(
                    on: day.date, termStart: termStart, courses: schedule.courses
                )
                let expectedHolidays = input.holidays.filter { $0.date == day.dateKey }
                XCTAssertEqual(day.courses, expectedCourses)
                XCTAssertEqual(day.holidays, expectedHolidays)
                XCTAssertEqual(day.holiday, expectedHolidays.first)
                XCTAssertEqual(day.dayNumberText, String(Calendar.shanghai.component(.day, from: day.date)))
                XCTAssertEqual(day.accessibilityLabel, TeachingCalendarLogic.dayAccessibilityLabel(
                    todayText: day.dateKey == todayKey ? AppLocalization.string("今天", language: language) : "",
                    formattedDate: formatter.string(from: day.date),
                    holidayNames: expectedHolidays.map(\.name),
                    courseDescriptions: expectedCourses.map { "\($0.timeRange)\($0.name)" }
                ))
            }
            let today = try XCTUnwrap(result.first { $0.dateKey == todayKey })
            XCTAssertEqual(today.courses.map(\.id), ["early", "late"])
            XCTAssertTrue(today.accessibilityLabel.hasPrefix(language == .english ? "Today，" : "今天，"))
            XCTAssertEqual(today.events.first?.title, language == .english ? "Off 示例假期" : "休 示例假期")
            let workday = try XCTUnwrap(result.first { $0.dateKey == "2026-09-08" })
            XCTAssertEqual(workday.events.first?.title, language == .english ? "Work 示例补班" : "班 示例补班")
        }
    }

    func testEventOrderIdentifiersKindsAndTimesMatchMonthAndAgendaContracts() async throws {
        let school = item("school", name: "校内通知", source: .schoolNotice)
        let contest = item("contest", name: "公开竞赛")
        let input = try makeInput(liveItems: [contest, school])
        let result = try await MobileMonthProjectionWorker().build(input: input)
        let day = try XCTUnwrap(result.first { $0.dateKey == "2026-09-07" })
        let holiday = try XCTUnwrap(day.holiday)

        XCTAssertEqual(day.events.map(\.id), [
            "holiday-\(holiday.id)", "2026-09-07-assignment-assignment", "2026-09-07-assignment-short",
            "2026-09-07-school-school", "2026-09-07-public-contest", "course-early", "course-late"
        ])
        XCTAssertEqual(day.events.map(\.categoryKey), [
            "法定节假日", "课程作业 DDL", "课程作业 DDL", "校内竞赛通知", "学科竞赛", "课程详情", "课程详情"
        ])
        XCTAssertEqual(day.events.map(\.kind), [.holiday, .assignment, .assignment, .schoolNotice, .competition, nil, nil])
        XCTAssertEqual(day.events.compactMap(\.deadlineItem), [school, contest])
        XCTAssertEqual(day.allDayEvents, [
            CalendarAllDayEvent(id: "2026-09-07-holiday-\(holiday.id)", title: "休 示例假期", kind: .holiday),
            CalendarAllDayEvent(
                id: "2026-09-07-assignment-assignment", title: "提交作业", time: "23:59",
                kind: .assignment, destinationURL: CalendarDeadlineSources.assignments
            ),
            CalendarAllDayEvent(
                id: "2026-09-07-assignment-short", title: "待公布时间", time: "待定",
                kind: .assignment, destinationURL: CalendarDeadlineSources.assignments
            ),
            CalendarAllDayEvent(
                id: "2026-09-07-school-school", title: school.name, time: "18:00",
                kind: .schoolNotice, deadlineItem: school
            ),
            CalendarAllDayEvent(
                id: "2026-09-07-public-contest", title: contest.name, time: "18:00",
                kind: .competition, deadlineItem: contest
            )
        ])
        XCTAssertEqual(day.deadlineKinds, [.assignment, .schoolNotice])
        XCTAssertEqual(day.assignments, input.assignmentsByDate[day.dateKey] ?? [])
    }

    func testSourceDeduplicationKeepsDistinctSourcesAndLiveVersionOfFavorite() async throws {
        let live = item("same-id", name: "AI 竞赛")
        let duplicate = item("duplicate-id", name: " ai 竞赛 ")
        let school = item("school", name: "AI 竞赛", source: .schoolNotice)
        let custom = item("custom", name: "AI 竞赛", source: .custom, kind: .custom)
        let olderFavorite = item("same-id", name: "旧收藏标题")
        let input = try makeInput(liveItems: [live, duplicate, school], customItems: [custom], favorites: [olderFavorite])
        let result = try await MobileMonthProjectionWorker().build(input: input)
        let day = try XCTUnwrap(result.first { $0.dateKey == "2026-09-07" })

        XCTAssertEqual(Set(day.publicItems.map(\.favoriteID)), Set([live, school, custom].map(\.favoriteID)))
        XCTAssertEqual(day.publicItems.count, 3)
        XCTAssertEqual(day.publicItems.first { $0.favoriteID == live.favoriteID }, live)
        XCTAssertFalse(day.publicItems.contains(duplicate))
        XCTAssertEqual(
            Set(day.events.compactMap(\.deadlineItem).map(\.favoriteID)),
            Set([live, school, custom].map(\.favoriteID))
        )
    }

    func testDisabledSourcesStillShowFavoritesWithoutFilteringTheirKinds() async throws {
        let live = item("live", name: "未收藏竞赛")
        let favorite = item("favorite", name: "收藏会议", kind: .conference)
        let customFavorite = item("custom-favorite", name: "收藏自定义", source: .custom, kind: .custom)
        let input = try makeInput(
            visibility: Self.allDisabled,
            liveItems: [live, favorite], customItems: [customFavorite], favorites: [customFavorite, favorite, favorite]
        )
        let result = try await MobileMonthProjectionWorker().build(input: input)
        let day = try XCTUnwrap(result.first { $0.dateKey == "2026-09-07" })

        XCTAssertEqual(day.publicItems.map(\.favoriteID), [favorite, customFavorite]
            .sorted { ($0.deadline, $0.name) < ($1.deadline, $1.name) }.map(\.favoriteID))
        XCTAssertEqual(day.events.compactMap(\.deadlineItem).count, 2)
        XCTAssertFalse(day.publicItems.contains(live))
    }

    func testLiveMergeCapAppliesBeforeFavoriteRestoration() async throws {
        let liveItems = (0 ..< 105).map { index in
            item("event-\(index)", name: String(format: "Event %03d", index))
        }
        let input = try makeInput(liveItems: liveItems, favorites: [liveItems[104], liveItems[0]])
        let result = try await MobileMonthProjectionWorker().build(input: input)
        let day = try XCTUnwrap(result.first { $0.dateKey == "2026-09-07" })

        XCTAssertEqual(day.publicItems.count, 101)
        XCTAssertEqual(day.publicItems, Array(liveItems.prefix(100)) + [liveItems[104]])
        XCTAssertFalse(day.publicItems.contains(liveItems[100]))
    }

    func testCancelledBuildDoesNotReturnAProjection() async throws {
        let input = try makeInput()
        let worker = MobileMonthProjectionWorker()
        let operation = Task<[MobileMonthDayProjection], Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.build(input: input)
        }
        do {
            _ = try await operation.value
            XCTFail("A cancelled month request must not publish a projection")
        } catch is CancellationError {
            // The owning pager performs its generation check separately.
        }
    }

    private func makeInput(
        language: AppLanguage = .simplifiedChinese,
        visibility: MobileMonthSourceVisibility = MobileMonthProjectionTests.allEnabled,
        liveItems: [PublicDeadlineItem] = [],
        customItems: [PublicDeadlineItem] = [],
        favorites: [PublicDeadlineItem] = []
    ) throws -> MobileMonthProjectionInput {
        let start = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-31"))
        let today = try XCTUnwrap(StrictContractDateParser.date(from: "2026-09-07"))
        let days = try (0 ..< 42).map { offset in
            try XCTUnwrap(Calendar.shanghai.date(byAdding: .day, value: offset, to: start))
        }
        let dateKey = "2026-09-07"
        return MobileMonthProjectionInput(
            days: days,
            schedule: ScheduleSnapshot(
                termID: "2026-2027-1", termStartDate: dateKey, fetchedAt: "2026-09-05T00:00:00Z",
                courses: [course("late", startSlot: 4), course("early", startSlot: 0)]
            ),
            holidays: [
                HolidayItem(date: dateKey, name: "示例假期", type: "holiday"),
                HolidayItem(date: "2026-09-08", name: "示例补班", type: "workday")
            ],
            favorites: favorites,
            publicByDate: [dateKey: PublicDeadlineSnapshot(
                date: dateKey, items: liveItems, source: CalendarDeadlineSources.primary, usedBackup: false
            )],
            customByDate: [dateKey: PublicDeadlineSnapshot(
                date: dateKey, items: customItems, source: CalendarDeadlineSources.backup, usedBackup: false
            )],
            assignmentsByDate: [dateKey: [
                AssignmentDeadlineItem(id: "assignment", title: "提交作业", courseName: "课程", deadline: "2026-09-07 23:59:00", status: "未提交"),
                AssignmentDeadlineItem(id: "short", title: "待公布时间", courseName: nil, deadline: "待定", status: nil)
            ]],
            visibility: visibility,
            language: language,
            today: today
        )
    }

    private func item(
        _ id: String,
        name: String,
        source: PublicDeadlineSource = .contestDDL,
        kind: PublicDeadlineKind = .competition
    ) -> PublicDeadlineItem {
        PublicDeadlineItem(
            id: id, name: name, kind: kind, source: source, deadline: "2026-09-07T18:00:00+08:00",
            organizer: nil, officialURL: nil
        )
    }

    private func course(_ id: String, startSlot: Int) -> Course {
        Course(
            id: id, name: id, teacher: "教师", room: "教室", weekText: "1-2",
            weekNumbers: [1, 2], examWeekNumbers: [], weekday: 1,
            startSlot: startSlot, endSlot: startSlot + 1, sectionText: "", timeRange: "08:00-09:35"
        )
    }

    private static let allEnabled = MobileMonthSourceVisibility(
        competitionEnabled: true, schoolNoticeEnabled: true, conferenceEnabled: true,
        summerCampEnabled: true, hackathonEnabled: true, customEnabled: true
    )

    private static let allDisabled = MobileMonthSourceVisibility(
        competitionEnabled: false, schoolNoticeEnabled: false, conferenceEnabled: false,
        summerCampEnabled: false, hackathonEnabled: false, customEnabled: false
    )
}
