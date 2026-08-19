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

    func testClassroomDefaultsExposeEveryOriginalBuildingForEachCampus() {
        XCTAssertEqual(
            ClassroomDefaults.buildings(for: "01"),
            ["教1", "教2", "教3", "教4", "主楼"]
        )
        XCTAssertEqual(
            ClassroomDefaults.buildings(for: "04"),
            ["综合教学楼N", "综合教学楼S", "教学实验综合楼N", "教学实验综合楼S", "智慧教学楼"]
        )
        XCTAssertTrue(ClassroomDefaults.buildings(for: "unknown").isEmpty)
    }

    func testSJDTransportUsesHTTPS() {
        XCTAssertEqual(SJDAPIClient.origin, "https://jwglweixin.bupt.edu.cn")
        XCTAssertEqual(URL(string: SJDAPIClient.origin)?.scheme, "https")
        XCTAssertTrue(SJDURLSession.shared.delegate is SJDURLSessionRedirectDelegate)
    }

    func testSJDLoginFormUsesStandardEncodingForReservedAndUnicodeCharacters() throws {
        let data = SJDFormURLEncoder.data([
            "userNo": "2026+test",
            "pwd": "A+B C&=中文*._-",
        ])
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(
            body,
            "pwd=A%2BB+C%26%3D%E4%B8%AD%E6%96%87*._-&userNo=2026%2Btest"
        )
    }

    func testSJDRedirectPolicyAllowsOnlySameSecureOriginAndEffectivePort() throws {
        let source = try XCTUnwrap(URL(string: "https://jwglweixin.bupt.edu.cn/bjyddx/login"))
        let explicitDefaultPort = try XCTUnwrap(URL(
            string: "https://jwglweixin.bupt.edu.cn:443/bjyddx/student/curriculum"
        ))

        XCTAssertTrue(SJDNetworkPolicy.allows(source))
        XCTAssertTrue(SJDNetworkPolicy.allowsRedirect(from: source, to: explicitDefaultPort))

        for destination in [
            "http://jwglweixin.bupt.edu.cn/bjyddx/student/curriculum",
            "https://example.com/bjyddx/student/curriculum",
            "https://sub.jwglweixin.bupt.edu.cn/bjyddx/student/curriculum",
            "https://jwglweixin.bupt.edu.cn:444/bjyddx/student/curriculum",
            "https://user@jwglweixin.bupt.edu.cn/bjyddx/student/curriculum",
        ] {
            XCTAssertFalse(
                SJDNetworkPolicy.allowsRedirect(from: source, to: URL(string: destination)),
                destination
            )
        }

        XCTAssertFalse(SJDNetworkPolicy.allowsRedirect(
            from: URL(string: "https://jwglweixin.bupt.edu.cn:444/bjyddx/login"),
            to: source
        ))
    }

    func testSJDResponseLimitsAcceptBoundaryAndRejectOneAdditionalByte() {
        for endpoint in SJDResponseEndpoint.allCases {
            let maximum = SJDResponseLimits.maximumBytes(for: endpoint)
            XCTAssertNoThrow(try SJDResponseLimits.validate(
                Data(repeating: 0x20, count: maximum),
                endpoint: endpoint
            ))
            XCTAssertThrowsError(try SJDResponseLimits.validate(
                Data(repeating: 0x20, count: maximum + 1),
                endpoint: endpoint
            ))
        }
    }

    func testSJDRequestsRejectActualOversizedBodiesDespiteSmallDeclaredLength() async throws {
        for endpoint in SJDResponseEndpoint.allCases {
            let transport = StubSJDHTTPTransport(
                data: Data(
                    repeating: 0x20,
                    count: SJDResponseLimits.maximumBytes(for: endpoint) + 1
                ),
                declaredContentLength: 1
            )
            let api = SJDAPIClient(transport: transport)

            do {
                switch endpoint {
                case .login:
                    _ = try await api.login(credentials: Credentials(account: "account", password: "password"))
                case .curriculum:
                    _ = try await api.curriculum(token: "token", week: "all")
                case .classrooms:
                    _ = try await api.classrooms(token: "token", campusID: "01")
                }
                XCTFail("Expected \(endpoint) to reject the oversized body.")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("响应过大"), String(describing: error))
            }
        }
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

    func testScheduleStoreRejectsInvalidContractDatesOnSaveAndLoad() throws {
        let expected = try JSONDecoder().decode(
            ScheduleSnapshot.self,
            from: fixtureData("schedule.json")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("schedule.json")
        let store = FileScheduleStore(fileURL: fileURL)

        for value in ["2026-02-30", "2026-13-01"] {
            let invalid = ScheduleSnapshot(
                termID: expected.termID,
                termStartDate: value,
                fetchedAt: expected.fetchedAt,
                courses: expected.courses
            )
            XCTAssertThrowsError(try store.save(invalid), value) { error in
                XCTAssertEqual(error as? ScheduleStoreError, .invalidTermStartDate)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalidCache = ScheduleSnapshot(
            termID: expected.termID,
            termStartDate: "2026-02-30",
            fetchedAt: expected.fetchedAt,
            courses: expected.courses
        )
        try JSONEncoder().encode(invalidCache).write(to: fileURL, options: .atomic)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ScheduleStoreError, .invalidTermStartDate)
        }
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

        XCTAssertEqual(expected.source, HolidayDefaults.source)
        XCTAssertEqual(actual, expected)
    }

    func testHolidayParserRejectsMismatchedItemYear() {
        let source = """
        {"year":2026,"region":"CN","dates":[
          {"date":"2025-12-31","name":"跨年假期","type":"public_holiday"}
        ]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: source,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))
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
        {"year":2026,"region":"CN","dates":[
          {"date":"2026-1-01","name":"测试","type":"public_holiday"}
        ]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: malformedDate,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let malformedEnvelope = #"{"year":2026,"region":"CN","dates":{}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: malformedEnvelope,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let tooManyRecords = Array(
            repeating: ["date": "2026-01-01", "name": "测试", "type": "public_holiday"],
            count: HolidaySourceLimits.maximumRecords + 1
        )
        let tooManyRecordsData = try! JSONSerialization.data(withJSONObject: [
            "year": 2026,
            "region": "CN",
            "dates": tooManyRecords
        ])
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: tooManyRecordsData,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))

        let longName = String(repeating: "节", count: HolidaySourceLimits.maximumNameLength + 1)
        let longNameData = try! JSONSerialization.data(withJSONObject: [
            "year": 2026,
            "region": "CN",
            "dates": [[
                "date": "2026-01-01",
                "name": longName,
                "type": "public_holiday"
            ]]
        ])
        XCTAssertThrowsError(try HolidaySourceParser.parse(
            data: longNameData,
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-01T00:00:00+08:00"
        ))
    }

    func testHolidayResponseAccumulatorRejectsActualByteBeyondHardLimit() throws {
        var data = Data(
            repeating: 0x20,
            count: HolidaySourceLimits.maximumPayloadBytes - 1
        )

        try HolidayResponseAccumulator.append(0x20, to: &data)
        XCTAssertEqual(data.count, HolidaySourceLimits.maximumPayloadBytes)
        XCTAssertThrowsError(try HolidayResponseAccumulator.append(0x20, to: &data))
        XCTAssertEqual(data.count, HolidaySourceLimits.maximumPayloadBytes)
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
        XCTAssertEqual(CalendarTimelineLogic.wholeHourMinutes.first, 8 * 60)
        XCTAssertEqual(CalendarTimelineLogic.wholeHourMinutes.last, 22 * 60)
        XCTAssertEqual(CalendarTimelineLogic.wholeHourMinutes.count, 15)
        XCTAssertTrue(CalendarTimelineLogic.courseBoundaryMinutes.contains(8 * 60 + 45))
        XCTAssertTrue(CalendarTimelineLogic.courseBoundaryMinutes.contains(13 * 60))
        XCTAssertFalse(CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes.contains(13 * 60))
        XCTAssertTrue(CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes.contains(13 * 60 + 45))
        XCTAssertTrue(
            Set(CalendarTimelineLogic.wholeHourMinutes)
                .isDisjoint(with: CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes)
        )
    }

    func testTimelineCourseMetadataIncludesLocationAndTeacher() {
        let course = Course(
            id: "metadata",
            name: "数据挖掘",
            teacher: "徐思雅",
            room: "教三楼-3-335",
            weekText: "1-16",
            weekNumbers: Array(1 ... 16),
            examWeekNumbers: [],
            weekday: 1,
            startSlot: 2,
            endSlot: 4,
            sectionText: "3-5节",
            timeRange: "09:50-12:15"
        )

        XCTAssertEqual(
            CalendarTimelineLogic.courseMetadata(course),
            "教三楼-3-335 · 教师：徐思雅"
        )
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

    func testCalendarTimelineMinimumWidthKeepsSevenDayWeekReadableOnIPad() {
        XCTAssertEqual(
            CalendarTimelineLogic.minimumDayAreaWidth(dayCount: 7, minimumDayWidth: 96),
            672
        )
        XCTAssertEqual(
            CalendarTimelineLogic.minimumDayAreaWidth(dayCount: 1, minimumDayWidth: 96),
            160
        )
    }

    func testAdaptiveLayoutPolicyKeepsCompactIPhoneTabs() {
        XCTAssertEqual(
            AdaptiveLayoutPolicy.primaryNavigation(width: 430, horizontalClass: .compact),
            .tabs
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.primaryNavigation(width: 900, horizontalClass: .compact),
            .tabs
        )
    }

    func testAdaptiveLayoutPolicyUsesSidebarOnlyForRegularUsableWidth() {
        XCTAssertEqual(
            AdaptiveLayoutPolicy.primaryNavigation(width: 1_024, horizontalClass: .regular),
            .sidebar
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.primaryNavigation(width: 699, horizontalClass: .regular),
            .tabs
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.primaryNavigation(width: 700, horizontalClass: .regular),
            .sidebar
        )
    }

    func testAdaptiveCalendarAndContentColumnsFollowAvailableDetailWidth() {
        XCTAssertEqual(
            AdaptiveLayoutPolicy.calendarPresentation(width: 900, horizontalClass: .compact),
            .compact
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.calendarPresentation(width: 759, horizontalClass: .regular),
            .compact
        )
        XCTAssertEqual(
            AdaptiveLayoutPolicy.calendarPresentation(width: 760, horizontalClass: .regular),
            .expanded
        )
        XCTAssertEqual(AdaptiveLayoutPolicy.contentColumnCount(width: 759), 1)
        XCTAssertEqual(AdaptiveLayoutPolicy.contentColumnCount(width: 760), 2)
    }

    func testMobilePageLayoutUsesCompactTopSpacingInLandscapeHeight() {
        let landscape = MobilePageLayoutPolicy.metrics(availableHeight: 393)
        let portrait = MobilePageLayoutPolicy.metrics(availableHeight: 852)

        XCTAssertEqual(landscape.topPadding, 16)
        XCTAssertEqual(landscape.sectionSpacing, 12)
        XCTAssertTrue(landscape.usesCompactTitle)
        XCTAssertEqual(portrait.topPadding, 20)
        XCTAssertEqual(portrait.sectionSpacing, 16)
        XCTAssertFalse(portrait.usesCompactTitle)
    }

    #if os(iOS)
    func testMobileTimelineKeepsDayAndWeekInsideViewport() {
        XCTAssertEqual(
            MobileCalendarTimelineLayout.contentWidth(
                availableWidth: 390,
                dayCount: 1,
                showsWeekColumns: false
            ),
            334
        )
        XCTAssertEqual(
            MobileCalendarTimelineLayout.contentWidth(
                availableWidth: 390,
                dayCount: 7,
                showsWeekColumns: true
            ),
            334
        )
        XCTAssertEqual(MobileCalendarTimelineLayout.yPosition(minute: 8 * 60), 0)
        XCTAssertEqual(MobileCalendarTimelineLayout.yPosition(minute: 15 * 60), 504)
        XCTAssertEqual(MobileCalendarTimelineLayout.yPosition(minute: 22 * 60), 1_008)
        XCTAssertEqual(
            MobileCalendarTimelineLayout.initialVisibleHour(currentHour: 17, includesToday: true),
            16
        )
        XCTAssertEqual(
            MobileCalendarTimelineLayout.initialVisibleHour(currentHour: 17, includesToday: false),
            8
        )
    }

    func testMobileTimelineRetainsAllFourteenCoursePeriods() {
        XCTAssertEqual(SlotMetadata.defaults.count, 14)
        XCTAssertEqual(SlotMetadata.defaults.first?.start, "08:00")
        XCTAssertEqual(SlotMetadata.defaults.last?.end, "20:55")
    }
    #endif

    func testYearCourseDensityContinuesIncreasingPastFourCourses() {
        let opacities = [1, 4, 5, 8, 12].map {
            TeachingCalendarLogic.yearCourseOpacity(courseCount: $0)
        }

        XCTAssertEqual(TeachingCalendarLogic.yearCourseOpacity(courseCount: 0), 0)
        XCTAssertEqual(opacities, opacities.sorted())
        XCTAssertEqual(Set(opacities).count, opacities.count)
        XCTAssertLessThan(opacities.last!, 1)
    }

    func testCalendarNavigationMovesByVisiblePeriod() throws {
        let calendar = Calendar.shanghai
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))

        XCTAssertEqual(
            calendar.component(.day, from: try XCTUnwrap(TeachingCalendarLogic.movedDate(
                from: date,
                unit: .day,
                direction: 1,
                calendar: calendar
            ))),
            16
        )
        XCTAssertEqual(
            calendar.component(.day, from: try XCTUnwrap(TeachingCalendarLogic.movedDate(
                from: date,
                unit: .week,
                direction: 1,
                calendar: calendar
            ))),
            22
        )
        XCTAssertEqual(
            calendar.component(.month, from: try XCTUnwrap(TeachingCalendarLogic.movedDate(
                from: date,
                unit: .month,
                direction: 1,
                calendar: calendar
            ))),
            7
        )
    }

    func testCalendarPeriodTitlesKeepWeekInPrimaryTitle() throws {
        let calendar = Calendar.shanghai
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))

        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(for: date, modeRawValue: "日", calendar: calendar),
            "2026年8月14日"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(for: date, modeRawValue: "周", calendar: calendar),
            "2026年8月 第 33 周"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(for: date, modeRawValue: "月", calendar: calendar),
            "2026年8月"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(for: date, modeRawValue: "年", calendar: calendar),
            "2026年"
        )
    }

    func testCalendarSwipeRequiresDeliberateHorizontalGesture() {
        XCTAssertEqual(TeachingCalendarLogic.swipeDirection(
            horizontalTranslation: -72,
            verticalTranslation: 12,
            predictedHorizontalTranslation: -118
        ), 1)
        XCTAssertEqual(TeachingCalendarLogic.swipeDirection(
            horizontalTranslation: 72,
            verticalTranslation: 12,
            predictedHorizontalTranslation: 118
        ), -1)
        XCTAssertNil(TeachingCalendarLogic.swipeDirection(
            horizontalTranslation: 30,
            verticalTranslation: 2,
            predictedHorizontalTranslation: 120
        ))
        XCTAssertNil(TeachingCalendarLogic.swipeDirection(
            horizontalTranslation: 80,
            verticalTranslation: 70,
            predictedHorizontalTranslation: 120
        ))
    }

    func testMonthExpansionSwipeRequiresDeliberateVerticalGesture() {
        XCTAssertEqual(
            TeachingCalendarLogic.monthExpansionAction(
                horizontalTranslation: 8,
                verticalTranslation: -72
            ),
            .collapse
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthExpansionAction(
                horizontalTranslation: 8,
                verticalTranslation: 72
            ),
            .expand
        )
        XCTAssertNil(TeachingCalendarLogic.monthExpansionAction(
            horizontalTranslation: 72,
            verticalTranslation: 42
        ))
        XCTAssertNil(TeachingCalendarLogic.monthExpansionAction(
            horizontalTranslation: 12,
            verticalTranslation: 30
        ))
    }

    func testCalendarGestureAxisLocksAfterDeliberateMovement() {
        XCTAssertNil(TeachingCalendarLogic.gestureAxis(
            horizontalTranslation: 4,
            verticalTranslation: 5
        ))
        XCTAssertEqual(TeachingCalendarLogic.gestureAxis(
            horizontalTranslation: 24,
            verticalTranslation: 8
        ), .horizontal)
        XCTAssertEqual(TeachingCalendarLogic.gestureAxis(
            horizontalTranslation: 8,
            verticalTranslation: -24
        ), .vertical)
    }

    func testMonthExpansionProgressTracksFingerAndClamps() {
        XCTAssertEqual(
            TeachingCalendarLogic.monthExpansionProgress(
                isExpanded: false,
                verticalTranslation: 75,
                travelDistance: 150
            ),
            0.5
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthExpansionProgress(
                isExpanded: true,
                verticalTranslation: -75,
                travelDistance: 150
            ),
            0.5
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthExpansionProgress(
                isExpanded: false,
                verticalTranslation: -40,
                travelDistance: 150
            ),
            0
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthExpansionProgress(
                isExpanded: true,
                verticalTranslation: 40,
                travelDistance: 150
            ),
            1
        )
    }

    func testMonthPositionTracksAllThreeDragStops() {
        XCTAssertEqual(
            TeachingCalendarLogic.monthPosition(
                isExpanded: false,
                isDetailRaised: false,
                verticalTranslation: -75,
                travelDistance: 150
            ),
            0.5
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthPosition(
                isExpanded: false,
                isDetailRaised: false,
                verticalTranslation: 75,
                travelDistance: 150
            ),
            1.5
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthGridExpansionProgress(position: 1.4),
            0.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthDetailLiftProgress(position: 0.35),
            0.65,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 0.52,
                verticalTranslation: -70,
                predictedVerticalTranslation: -130
            ),
            .detailRaised
        )
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 1.42,
                verticalTranslation: 60,
                predictedVerticalTranslation: 130
            ),
            .expanded
        )
    }

    func testLandscapeMonthPositionOnlySettlesAtTwoStops() {
        XCTAssertEqual(
            TeachingCalendarLogic.normalizedMonthPosition(
                .collapsed,
                allowsIntermediatePosition: false
            ),
            .detailRaised
        )
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 1.4,
                verticalTranslation: -70,
                predictedVerticalTranslation: -130,
                allowsIntermediatePosition: false
            ),
            .detailRaised
        )
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 0.6,
                verticalTranslation: 70,
                predictedVerticalTranslation: 130,
                allowsIntermediatePosition: false
            ),
            .expanded
        )
        XCTAssertNotEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 1,
                verticalTranslation: 0,
                predictedVerticalTranslation: 0,
                allowsIntermediatePosition: false
            ),
            .collapsed
        )
    }

    #if os(iOS)
    func testLandscapeCalendarRemovesPortraitTabBarInset() {
        XCTAssertEqual(
            MobileCalendarTimelineLayout.contentBottomInset(isLandscape: false),
            MobileCalendarTimelineLayout.bottomContentInset
        )
        XCTAssertEqual(MobileCalendarTimelineLayout.contentBottomInset(isLandscape: true), 0)
    }
    #endif

    func testExpandedMonthHeightReservesWeekdayGridSpacingAndHandle() {
        let availableHeight: CGFloat = 620
        let cellHeight = TeachingCalendarLogic.expandedMonthCellHeight(
            availableHeight: availableHeight
        )
        let reservedHeight: CGFloat = 18 + 8 + 20 + 28 + 16

        XCTAssertEqual(cellHeight, 88)
        XCTAssertLessThanOrEqual(cellHeight * 6 + reservedHeight, availableHeight)
        XCTAssertEqual(
            TeachingCalendarLogic.expandedMonthCellHeight(availableHeight: 300),
            35
        )
    }

    func testMonthGridExpansionUsesTheFullAvailableWidth() {
        let portrait = TeachingCalendarLogic.monthGridLayout(
            contentWidth: 369,
            availableHeight: 620
        )
        XCTAssertEqual(portrait.collapsedCellHeight, 49)
        XCTAssertEqual(portrait.collapsedGridWidth, 369)
        XCTAssertEqual(portrait.expandedCellHeight, 88)
        XCTAssertEqual(portrait.expandedGridWidth, portrait.collapsedGridWidth)

        let landscape = TeachingCalendarLogic.monthGridLayout(
            contentWidth: 828,
            availableHeight: 250
        )
        XCTAssertEqual(landscape.collapsedCellHeight, 30)
        XCTAssertEqual(landscape.expandedCellHeight, 30)
        XCTAssertEqual(landscape.collapsedGridWidth, 828)
        XCTAssertEqual(landscape.gridWidth(at: 0), 828)
        XCTAssertEqual(landscape.gridWidth(at: 1), 828)

        for progress in stride(from: CGFloat.zero, through: 1, by: 0.1) {
            XCTAssertGreaterThanOrEqual(
                landscape.cellHeight(at: progress),
                landscape.collapsedCellHeight
            )
        }
    }

    func testMonthEventCapacityUsesTheActualRemainingCellHeight() {
        let topInset = TeachingCalendarLogic.monthDayTopInset(collapsedCellHeight: 49)
        XCTAssertEqual(topInset, 9)
        XCTAssertEqual(
            TeachingCalendarLogic.monthEventRowCapacity(
                cellHeight: 49,
                dayTopInset: topInset
            ),
            1
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthEventRowCapacity(
                cellHeight: 88,
                dayTopInset: topInset
            ),
            3
        )
    }

    func testExpandedMonthEventsReserveLastRowForOverflowCount() {
        XCTAssertEqual(
            TeachingCalendarLogic.monthEventLayout(totalCount: 2, maximumRows: 2),
            .init(visibleEventCount: 2, hiddenEventCount: 0)
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthEventLayout(totalCount: 5, maximumRows: 2),
            .init(visibleEventCount: 1, hiddenEventCount: 4)
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthEventLayout(totalCount: 3, maximumRows: 0),
            .init(visibleEventCount: 0, hiddenEventCount: 3)
        )
    }

    func testPlannerSlotColumnsUseCompactReadableWidths() {
        XCTAssertEqual(PlannerLayoutMetrics.slotMinimumWidth, 104)
        XCTAssertEqual(PlannerLayoutMetrics.slotMaximumWidth, 156)
        XCTAssertEqual(PlannerLayoutMetrics.slotSpacing, 6)
    }

    func testDesktopColumnLayoutUsesNormalMarginsAndOneToTwoRatio() {
        let widths = DesktopColumnLayoutPolicy.widths(containerWidth: 1_200)

        XCTAssertEqual(DesktopColumnLayoutPolicy.horizontalPadding, 16)
        XCTAssertEqual(DesktopColumnLayoutPolicy.spacing, 16)
        XCTAssertEqual(widths.leading, 384)
        XCTAssertEqual(widths.trailing, 768)
        XCTAssertEqual(
            widths.leading + widths.trailing
                + DesktopColumnLayoutPolicy.horizontalPadding * 2
                + DesktopColumnLayoutPolicy.spacing,
            1_200
        )
    }

    func testDesktopColumnLayoutClampsWidthsForNarrowContainers() {
        let widths = DesktopColumnLayoutPolicy.widths(containerWidth: 40)

        XCTAssertEqual(widths.leading, 0)
        XCTAssertEqual(widths.trailing, 0)
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

private struct StubSJDHTTPTransport: SJDHTTPTransport {
    let data: Data
    let declaredContentLength: Int

    func data(
        for request: URLRequest,
        maximumBytes _: Int
    ) async throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(declaredContentLength)]
        ))
        XCTAssertEqual(response.expectedContentLength, Int64(declaredContentLength))
        return (data, response)
    }
}
