import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class MobileYearProjectionTests: XCTestCase {
    func testCommonAndLeapYearsProjectOnlyRealDaysWithTwelveFixedSixRowMonths() async throws {
        let worker = MobileYearProjectionWorker()
        for (year, expectedCount, februaryCount) in [(2026, 365, 28), (2028, 366, 29)] {
            let input = try makeInput(year: year)
            let result = try await worker.build(input: input)
            let days = result.flatMap(\.days)

            XCTAssertEqual(result.count, 12)
            XCTAssertEqual(days.count, expectedCount)
            XCTAssertEqual(Set(days.map(\.id)).count, expectedCount)
            XCTAssertEqual(days.map(\.date), input.days)
            XCTAssertEqual(days.first?.dateKey, "\(year)-01-01")
            XCTAssertEqual(days.last?.dateKey, "\(year)-12-31")
            XCTAssertEqual(result[1].days.count, februaryCount)
            for (index, month) in result.enumerated() {
                XCTAssertEqual(month.monthKey, String(format: "%04d-%02d", year, index + 1))
                XCTAssertEqual(month.days.first?.date, month.monthStart)
                XCTAssertEqual(month.leadingBlankCount + month.days.count + month.trailingBlankCount, 42)
                XCTAssertTrue((0...6).contains(month.leadingBlankCount))
                XCTAssertGreaterThanOrEqual(month.trailingBlankCount, 0)
                XCTAssertTrue(month.days.allSatisfy {
                    Calendar.shanghai.isDate($0.date, equalTo: month.monthStart, toGranularity: .month)
                })
            }
        }
        let commonYear = try await worker.build(input: makeInput())
        XCTAssertEqual(commonYear[0].leadingBlankCount, 3, "January 2026 starts on Thursday")
        XCTAssertEqual(commonYear[1].leadingBlankCount, 6, "February 2026 starts on Sunday")
    }

    func testYearValuesMatchExistingMonthCourseAccessibilityAndBorderContractsInBothLanguages() async throws {
        for language in [AppLanguage.simplifiedChinese, .english] {
            let input = try makeInput(
                language: language,
                liveItems: [item("contest"), item("school", source: .schoolNotice)],
                includesAssignment: true
            )
            let result = try await MobileYearProjectionWorker().build(input: input)
            let monthReference = try await MobileMonthProjectionWorker().build(input: input)
            let days = result.flatMap(\.days)
            XCTAssertEqual(days.count, monthReference.count)
            for (day, reference) in zip(days, monthReference) {
                XCTAssertEqual(day.date, reference.date)
                XCTAssertEqual(day.dateKey, reference.dateKey)
                XCTAssertEqual(day.dayNumberText, reference.dayNumberText)
                XCTAssertEqual(day.accessibilityLabel, reference.accessibilityLabel)
                XCTAssertEqual(day.courseCount, reference.courses.count)
                XCTAssertEqual(day.deadlineKinds, reference.deadlineKinds)
            }
            let today = try XCTUnwrap(days.first { $0.dateKey == "2026-09-07" })
            XCTAssertEqual(today.courseCount, 2)
            XCTAssertEqual(today.deadlineKinds, [.assignment, .schoolNotice])
            XCTAssertTrue(today.accessibilityLabel.hasPrefix(language == .english ? "Today，" : "今天，"))
            XCTAssertTrue(today.accessibilityLabel.contains("示例假期"))
            XCTAssertEqual(result[8].monthTitle, language == .english ? "Sep" : "9月")
        }
    }

    func testDisabledSourcesRetainFavoriteConferenceAndCustomBorders() async throws {
        let favorite = item("favorite", kind: .conference)
        let customFavorite = item("custom-favorite", source: .custom, kind: .custom)
        let input = try makeInput(
            visibility: Self.allDisabled,
            liveItems: [item("unfavorited"), favorite, item("school", source: .schoolNotice)],
            customItems: [customFavorite],
            favorites: [favorite, customFavorite, favorite]
        )
        let day = try await projectedDay(input: input)
        XCTAssertEqual(day.deadlineKinds, [.conference, .customDeadline])
    }

    func testVisibleLiveVersionWinsOverAStaleFavoriteKind() async throws {
        let live = item("same-id", kind: .competition)
        let olderFavorite = item("same-id", kind: .conference)
        let input = try makeInput(liveItems: [live], favorites: [olderFavorite, olderFavorite])
        let day = try await projectedDay(input: input)
        XCTAssertEqual(day.deadlineKinds, [.competition])
    }

    func testLiveMergeCapPrecedesVisibilityAndFavoriteRestoration() async throws {
        let competitions = (0..<100).map { item("event-\($0)", name: String(format: "Event %03d", $0)) }
        let conference = item("conference", name: "Event 100", kind: .conference)
        let conferenceOnly = MobileMonthSourceVisibility(
            competitionEnabled: false, schoolNoticeEnabled: false, conferenceEnabled: true,
            summerCampEnabled: false, hackathonEnabled: false, customEnabled: false
        )
        let cappedInput = try makeInput(
            visibility: conferenceOnly, liveItems: competitions + [conference]
        )
        let cappedDay = try await projectedDay(input: cappedInput)
        XCTAssertTrue(cappedDay.deadlineKinds.isEmpty,
                      "Filtering disabled competitions must not restore the 101st live item")

        let favoriteInput = try makeInput(
            visibility: conferenceOnly, liveItems: competitions + [conference], favorites: [conference]
        )
        let favoriteDay = try await projectedDay(input: favoriteInput)
        XCTAssertEqual(favoriteDay.deadlineKinds, [.conference])
    }

    func testPublicMergeDeduplicatesNamesBeforeTheCapAndRestoresBothKinds() async throws {
        let competitions = (0..<99).map { item("event-\($0)", name: String(format: "Event %03d", $0)) }
        let duplicate = item("duplicate", name: " event 000 ")
        let conference = item("conference", name: "Event 099", kind: .conference)
        let input = try makeInput(liveItems: competitions + [duplicate, conference])
        let day = try await projectedDay(input: input)
        XCTAssertEqual(day.deadlineKinds, [.competition, .conference])
    }

    func testCompactKindOverloadMatchesAgendaPriorityAndExcludesHolidays() {
        let kinds: [CalendarAllDayEventKind] = [
            .holiday, .customDeadline, .hackathon, .workday, .conference,
            .competition, .schoolNotice, .assignment, .assignment
        ]
        let events = kinds.enumerated().map {
            CalendarAllDayEvent(id: String($0.offset), title: "", kind: $0.element)
        }
        XCTAssertEqual(CalendarDeadlinePresentation.topTwoDeadlineKinds(in: kinds), [.assignment, .schoolNotice])
        XCTAssertEqual(CalendarDeadlinePresentation.topTwoDeadlineKinds(in: kinds),
                       CalendarDeadlinePresentation.topTwoDeadlineKinds(in: events))
        XCTAssertTrue(CalendarDeadlinePresentation.topTwoDeadlineKinds(
            in: [CalendarAllDayEventKind.holiday, .workday]
        ).isEmpty)
    }

    func testHolidayNamesStayAccessibleWithoutAddingDeadlineBorders() async throws {
        let day = try await projectedDay(input: makeInput())
        XCTAssertTrue(day.deadlineKinds.isEmpty)
        XCTAssertTrue(day.accessibilityLabel.contains("示例假期"))
    }

    func testCancelledYearBuildDoesNotPublishAProjection() async throws {
        let input = try makeInput()
        let worker = MobileYearProjectionWorker()
        let operation = Task<[MobileYearMonthProjection], Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.build(input: input)
        }
        do {
            _ = try await operation.value
            XCTFail("A cancelled year request must not publish a projection")
        } catch is CancellationError {
            // The owning page cache also rejects stale owner/generation results.
        }
    }

    private func projectedDay(input: MobileMonthProjectionInput) async throws -> MobileYearDayProjection {
        let months = try await MobileYearProjectionWorker().build(input: input)
        return try XCTUnwrap(months.flatMap(\.days).first { $0.dateKey == "2026-09-07" })
    }

    private func makeInput(
        year: Int = 2026,
        language: AppLanguage = .simplifiedChinese,
        visibility: MobileMonthSourceVisibility = MobileYearProjectionTests.allEnabled,
        liveItems: [PublicDeadlineItem] = [],
        customItems: [PublicDeadlineItem] = [],
        favorites: [PublicDeadlineItem] = [],
        includesAssignment: Bool = false
    ) throws -> MobileMonthProjectionInput {
        let dateKey = "\(year)-09-07"
        let today = try XCTUnwrap(StrictContractDateParser.date(from: dateKey))
        return MobileMonthProjectionInput(
            days: TeachingCalendarLogic.datesInYear(containing: today),
            schedule: ScheduleSnapshot(
                termID: "\(year)-\(year + 1)-1", termStartDate: dateKey, fetchedAt: "2026-09-05T00:00:00Z",
                courses: [course("late", startSlot: 4), course("early", startSlot: 0)]
            ),
            holidays: [
                HolidayItem(date: dateKey, name: "示例假期", type: "holiday"),
                HolidayItem(date: "\(year)-09-08", name: "示例补班", type: "workday")
            ],
            favorites: favorites,
            publicByDate: [dateKey: PublicDeadlineSnapshot(
                date: dateKey, items: liveItems, source: CalendarDeadlineSources.primary, usedBackup: false
            )],
            customByDate: [dateKey: PublicDeadlineSnapshot(
                date: dateKey, items: customItems, source: CalendarDeadlineSources.backup, usedBackup: false
            )],
            assignmentsByDate: includesAssignment ? [dateKey: [AssignmentDeadlineItem(
                id: "assignment", title: "提交作业", courseName: "课程", deadline: "2026-09-07 23:59:00", status: "未提交"
            )]] : [:],
            visibility: visibility,
            language: language,
            today: today
        )
    }

    private func item(
        _ id: String,
        name: String? = nil,
        source: PublicDeadlineSource = .contestDDL,
        kind: PublicDeadlineKind = .competition
    ) -> PublicDeadlineItem {
        PublicDeadlineItem(
            id: id, name: name ?? id, kind: kind, source: source, deadline: "2026-09-07T18:00:00+08:00",
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
