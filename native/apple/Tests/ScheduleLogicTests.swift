import XCTest
#if os(iOS)
import UIKit
#endif
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

    func testInformationQueryOnlyOffersEventTypesPresentInRemoteOrFavoriteItems() {
        let competition = PublicDeadlineItem(
            id: "competition",
            name: "未来竞赛",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-09-02T12:00:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let favoritePreAdmission = PublicDeadlineItem(
            id: "favorite-pre-admission",
            name: "收藏的预推免",
            kind: .preAdmission,
            source: .contestDDL,
            deadline: "2026-09-03T12:00:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let items = ImportantEventQueryLogic.mergedItems(
            liveItems: [competition],
            favoriteItems: [favoritePreAdmission]
        )

        XCTAssertEqual(
            ImportantEventQueryLogic.availableCategories(in: items),
            [.all, .competition, .preAdmission]
        )
        XCTAssertEqual(
            ImportantEventQueryLogic.normalizedCategory(
                .journalSpecialIssue,
                availableCategories: ImportantEventQueryLogic.availableCategories(in: items)
            ),
            .all
        )
    }

    func testInformationQueryMetadataCategoriesFollowTypeAndEndedScope() throws {
        let now = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-31"))
        let activeCompetition = PublicDeadlineItem(
            id: "active-competition",
            name: "未来竞赛",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-09-02T12:00:00+08:00",
            organizer: nil,
            officialURL: nil,
            categories: ["AI"]
        )
        let endedCompetition = PublicDeadlineItem(
            id: "ended-competition",
            name: "已结束竞赛",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-08-30T12:00:00+08:00",
            organizer: nil,
            officialURL: nil,
            categories: ["Robotics"]
        )
        let activeConference = PublicDeadlineItem(
            id: "active-conference",
            name: "未来会议",
            kind: .conference,
            source: .contestDDL,
            deadline: "2026-09-04T12:00:00+08:00",
            organizer: nil,
            officialURL: nil,
            categories: ["Systems"]
        )
        let items = [activeCompetition, endedCompetition, activeConference]

        XCTAssertEqual(
            ImportantEventQueryLogic.metadataCategories(
                in: items,
                category: .competition,
                showsEnded: false,
                now: now
            ),
            ["AI"]
        )
        XCTAssertEqual(
            Set(ImportantEventQueryLogic.metadataCategories(
                in: items,
                category: .competition,
                showsEnded: true,
                now: now
            )),
            Set(["AI", "Robotics"])
        )
        XCTAssertEqual(
            ImportantEventQueryLogic.metadataCategories(
                in: items,
                category: .conference,
                showsEnded: false,
                now: now
            ),
            ["Systems"]
        )
        XCTAssertEqual(
            ImportantEventQueryLogic.normalizedMetadataCategory(
                "Robotics",
                availableCategories: ["AI"]
            ),
            ""
        )
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

    func testClassroomClientFormatsShanghaiContractDatesWithoutFractionalSeconds() throws {
        let date = try XCTUnwrap(
            Calendar.shanghai.date(
                from: DateComponents(
                    timeZone: Calendar.shanghai.timeZone,
                    year: 2026,
                    month: 8,
                    day: 19,
                    hour: 7,
                    minute: 5,
                    second: 9
                )
            )
        )

        XCTAssertEqual(SJDClassroomClient.contractDate(date), "2026-08-19")
        XCTAssertEqual(SJDClassroomClient.timestamp(date), "2026-08-19T07:05:09+08:00")
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

    func testLegacyExamWeekMetadataIsClearedWithoutChangingCourseWeeks() throws {
        let weekly = Course(
            id: "weekly",
            name: "测试课程",
            teacher: "测试教师",
            room: "测试楼-101",
            weekText: "2-19",
            weekNumbers: Array(2...19),
            examWeekNumbers: [18, 19],
            weekday: 1,
            startSlot: 0,
            endSlot: 1,
            sectionText: "1-2节",
            timeRange: "08:00-09:35"
        )

        let normalized = try XCTUnwrap(ScheduleLogic.clearingLegacyExamWeeks(in: [weekly]).first)
        XCTAssertTrue(normalized.examWeekNumbers.isEmpty)
        XCTAssertEqual(normalized.weekNumbers, Array(2 ... 19))
    }

    func testWeekNumberUsesTermStartDate() {
        let calendar = Calendar.shanghai
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let target = calendar.date(byAdding: .day, value: 14, to: start)!

        XCTAssertEqual(ScheduleLogic.weekNumber(on: target, termStart: start), 3)
    }

    func testCivilWeekNumberUsesISO8601YearBoundaries() throws {
        let firstJanuary = try XCTUnwrap(StrictContractDateParser.date(from: "2021-01-01"))
        let finalMonday = try XCTUnwrap(StrictContractDateParser.date(from: "2026-12-28"))

        XCTAssertEqual(ScheduleLogic.civilWeekNumber(on: firstJanuary), 53)
        XCTAssertEqual(ScheduleLogic.civilWeekNumber(on: finalMonday), 53)
    }

    func testDateBeforeTermHasNoActiveWeek() {
        let calendar = Calendar.shanghai
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let target = calendar.date(byAdding: .day, value: -1, to: start)!

        XCTAssertEqual(ScheduleLogic.weekNumber(on: target, termStart: start), 0)
    }

    func testTeachingWeekIsOnlyReportedInsideTheKnownTermRange() throws {
        let calendar = Calendar.shanghai
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))
        )
        let course = Course(
            id: "term-range",
            name: "课程",
            teacher: "教师",
            room: "101",
            weekText: "1-3",
            weekNumbers: [1, 2, 3],
            examWeekNumbers: [],
            weekday: 1,
            startSlot: 0,
            endSlot: 1,
            sectionText: "1-2节",
            timeRange: "08:00-09:35"
        )

        XCTAssertEqual(
            ScheduleLogic.activeTeachingWeekNumber(
                on: calendar.date(byAdding: .day, value: 14, to: start)!,
                termStart: start,
                courses: [course]
            ),
            3
        )
        XCTAssertNil(
            ScheduleLogic.activeTeachingWeekNumber(
                on: calendar.date(byAdding: .day, value: -1, to: start)!,
                termStart: start,
                courses: [course]
            )
        )
        XCTAssertNil(
            ScheduleLogic.activeTeachingWeekNumber(
                on: calendar.date(byAdding: .day, value: 21, to: start)!,
                termStart: start,
                courses: [course]
            )
        )
    }

    func testMonthCourseLookupMatchesPerDayScheduleResolution() throws {
        let calendar = Calendar.shanghai
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))
        )
        let dates = (0 ..< 14).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
        let course = Course(
            id: "lookup",
            name: "课程",
            teacher: "教师",
            room: "101",
            weekText: "1-2",
            weekNumbers: [1, 2],
            examWeekNumbers: [],
            weekday: 1,
            startSlot: 0,
            endSlot: 1,
            sectionText: "1-2节",
            timeRange: "08:00-09:35"
        )
        let lookup = ScheduleLogic.coursesByDate(
            for: dates,
            termStart: start,
            courses: [course]
        )

        for date in dates {
            XCTAssertEqual(
                lookup[StrictContractDateParser.string(from: date)],
                ScheduleLogic.courses(on: date, termStart: start, courses: [course])
            )
        }
    }

    func testSharedSJDFixturesProduceContractSchedule() throws {
        let contract = try JSONDecoder().decode(
            ScheduleSnapshot.self,
            from: fixtureData("schedule.json")
        )
        let expected = ScheduleSnapshot(
            termID: contract.termID,
            termStartDate: contract.termStartDate,
            fetchedAt: contract.fetchedAt,
            courses: ScheduleLogic.clearingLegacyExamWeeks(in: contract.courses)
        )
        let fetchedAt = ISO8601DateFormatter().date(from: contract.fetchedAt)!
        let parsed = try SJDScheduleParser.parse(
            currentData: fixtureData("sjd-current-week.json"),
            curriculumData: fixtureData("sjd-curriculum.json"),
            fallbackTermID: "fallback",
            fallbackTermStartDate: "2000-01-03",
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(parsed, expected)
    }

    func testCurrentWeekMetadataReadsTopInfoAndInfersStartFromWeekZeroOrOne() throws {
        let curriculum = try JSONSerialization.data(withJSONObject: [
            "data": [["item": []]],
        ])
        let beforeFirstWeek = try SJDScheduleParser.parse(
            currentData: fixtureData("sjd-before-first-week.json"),
            curriculumData: curriculum,
            fallbackTermID: ScheduleDefaults.termID,
            fallbackTermStartDate: ScheduleDefaults.termStartDate
        )

        XCTAssertEqual(beforeFirstWeek.termID, "2026-2027-1")
        XCTAssertEqual(beforeFirstWeek.termStartDate, "2026-08-31")

        let firstWeek = try JSONSerialization.data(withJSONObject: [
            "data": [[
                "week": "1",
                "topInfo": [["semesterId": "2026-2027-1"]],
                "date": [[
                    "mxrq": "2026-08-31",
                    "zc": "1",
                    "xqid": "1",
                ]],
            ]],
        ])
        let parsedFirstWeek = try SJDScheduleParser.parse(
            currentData: firstWeek,
            curriculumData: curriculum,
            fallbackTermID: ScheduleDefaults.termID,
            fallbackTermStartDate: ScheduleDefaults.termStartDate
        )

        XCTAssertEqual(parsedFirstWeek.termID, "2026-2027-1")
        XCTAssertEqual(parsedFirstWeek.termStartDate, "2026-08-31")
    }

    func testTermStartInferencePrefersDateWeekAndTreatsZeroWeekdayAsSunday() throws {
        let current = try JSONSerialization.data(withJSONObject: [
            "data": [[
                "week": "9",
                "topInfo": [["semesterId": "2026-2027-1", "week": "8"]],
                "date": [[
                    "mxrq": "2026-08-30",
                    "zc": "0",
                    "xqid": "0",
                ]],
            ]],
        ])
        let curriculum = try JSONSerialization.data(withJSONObject: [
            "data": [["item": []]],
        ])

        let parsed = try SJDScheduleParser.parse(
            currentData: current,
            curriculumData: curriculum,
            fallbackTermID: ScheduleDefaults.termID,
            fallbackTermStartDate: ScheduleDefaults.termStartDate
        )

        XCTAssertEqual(parsed.termID, "2026-2027-1")
        XCTAssertEqual(parsed.termStartDate, "2026-08-31")
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

    func testTimelineAllDayHeadersReserveTheLastRowForOverflow() {
        XCTAssertEqual(
            CalendarTimelineLogic.allDayHeaderLayout(eventCount: 2),
            .init(visibleEventCount: 2, hiddenEventCount: 0, rowCount: 2)
        )
        XCTAssertEqual(
            CalendarTimelineLogic.allDayHeaderLayout(eventCount: 4),
            .init(visibleEventCount: 2, hiddenEventCount: 2, rowCount: 3)
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

    func testPrimaryNavigationOrderTitlesAndAccessibilityIdentifiers() {
        XCTAssertEqual(AppSection.allCases, [.planner, .calendar, .queries, .settings])
        XCTAssertEqual(AppSection.allCases.map(\.titleKey), ["空教室", "教学日历", "查询", "设置"])
        XCTAssertEqual(
            AppSection.allCases.map(\.accessibilityIdentifier),
            ["navigation.planner", "navigation.calendar", "navigation.queries", "navigation.settings"]
        )
    }

    func testSettingsLanguageCardPrecedesPrivacyAndLocalDataInEveryLayout() {
        let expectedBottomOrder: [SettingsSurfaceID] = [
            .language,
            .aboutAndPrivacy,
            .localData
        ]

        XCTAssertEqual(
            Array(SettingsLayoutPolicy.singleColumn.suffix(expectedBottomOrder.count)),
            expectedBottomOrder
        )
        XCTAssertEqual(
            Array(SettingsLayoutPolicy.trailingColumn.suffix(expectedBottomOrder.count)),
            expectedBottomOrder
        )
        XCTAssertFalse(SettingsLayoutPolicy.leadingColumn.contains(.language))
    }

    func testCompactTabIdentityRoundTripsWithInterfaceLanguage() {
        let chinese = AdaptiveLayoutPolicy.compactTabIdentity(
            languageRawValue: AppLanguage.simplifiedChinese.rawValue
        )
        let english = AdaptiveLayoutPolicy.compactTabIdentity(
            languageRawValue: AppLanguage.english.rawValue
        )

        XCTAssertNotEqual(chinese, english)
        XCTAssertEqual(
            chinese,
            AdaptiveLayoutPolicy.compactTabIdentity(
                languageRawValue: AppLanguage.simplifiedChinese.rawValue
            ),
            "Chinese -> English -> Chinese must recreate and then restore the same tab layout identity"
        )
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

    func testMobileWeekAllDayLabelsPreserveTheirDateColumns() {
        let calendar = Calendar.shanghai
        let monday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let days = [
            CalendarTimelineDay(
                date: monday,
                courses: [],
                holidays: [HolidayItem(date: "2026-06-15", name: "测试假日", type: "holiday")]
            ),
            CalendarTimelineDay(date: tuesday, courses: [], holidays: []),
            CalendarTimelineDay(
                date: wednesday,
                courses: [],
                holidays: [HolidayItem(date: "2026-06-17", name: "调休上班", type: "workday")]
            )
        ]

        XCTAssertEqual(
            MobileCalendarAllDayLayout.labels(for: days),
            ["休 测试假日", "", "班 调休上班"]
        )
        XCTAssertEqual(MobileCalendarAllDayLayout.height, 40)
        XCTAssertEqual(
            MobileCalendarAllDayLayout.dayWidth(availableWidth: 390, dayCount: 7),
            MobileCalendarTimelineLayout.contentWidth(
                availableWidth: 390,
                dayCount: 7,
                showsWeekColumns: true
            ) / 7
        )
    }

    func testMobileWeekAllDayLabelUsesPlusCountForDeadlinesThatDoNotFit() {
        let date = Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 23)
        )!
        let day = CalendarTimelineDay(
            date: date,
            courses: [],
            holidays: [],
            allDayEvents: [
                CalendarAllDayEvent(id: "assignment", title: "作业一", kind: .assignment),
                CalendarAllDayEvent(id: "school", title: "校内竞赛", kind: .schoolNotice),
                CalendarAllDayEvent(id: "holiday", title: "休 节日", kind: .holiday)
            ]
        )

        XCTAssertEqual(MobileCalendarAllDayLayout.labels(for: [day]), ["作业一 +2"])
    }
    #endif

    func testDeadlineVisibilityRespectsEveryIndependentSetting() {
        let contest = PublicDeadlineItem(
            id: "contest",
            name: "竞赛原文",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-08-23T18:00:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let school = PublicDeadlineItem(
            id: "school",
            name: "校内原文",
            kind: .competition,
            source: .schoolNotice,
            deadline: "2026-08-23T19:00:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let summerCamp = PublicDeadlineItem(
            id: "summer",
            name: "夏令营原文",
            kind: .summerCamp,
            source: .contestDDL,
            deadline: "2026-08-23T20:00:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let hackathon = PublicDeadlineItem(
            id: "hackathon",
            name: "黑客松原文",
            kind: .hackathon,
            source: .contestDDL,
            deadline: "2026-08-23T21:00:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let conference = PublicDeadlineItem(
            id: "conference",
            name: "会议原文",
            kind: .conference,
            source: .contestDDL,
            deadline: "2026-08-23T21:30:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let journal = PublicDeadlineItem(
            id: "journal",
            name: "期刊专题原文",
            kind: .journalSpecialIssue,
            source: .contestDDL,
            deadline: "2026-08-23T21:40:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let preAdmission = PublicDeadlineItem(
            id: "pre-admission",
            name: "预推免原文",
            kind: .preAdmission,
            source: .contestDDL,
            deadline: "2026-08-23T21:50:00+08:00",
            organizer: nil,
            officialURL: nil
        )
        let custom = PublicDeadlineItem(
            id: "custom",
            name: "自定义原文",
            kind: .competition,
            source: .custom,
            deadline: "2026-08-23T22:00:00+08:00",
            organizer: nil,
            officialURL: nil,
            sourceName: "Custom Feed"
        )

        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            contest,
            competitionEnabled: true,
            schoolNoticeEnabled: false,
            summerCampEnabled: false,
            hackathonEnabled: false
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            school,
            competitionEnabled: false,
            schoolNoticeEnabled: true,
            summerCampEnabled: false,
            hackathonEnabled: false
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            summerCamp,
            competitionEnabled: false,
            schoolNoticeEnabled: false,
            summerCampEnabled: true,
            hackathonEnabled: false
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            hackathon,
            competitionEnabled: false,
            schoolNoticeEnabled: false,
            summerCampEnabled: false,
            hackathonEnabled: true
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            conference,
            competitionEnabled: false,
            schoolNoticeEnabled: false,
            conferenceEnabled: true,
            summerCampEnabled: false,
            hackathonEnabled: false
        ))
        XCTAssertFalse(CalendarDeadlinePresentation.isVisible(
            conference,
            competitionEnabled: true,
            schoolNoticeEnabled: true,
            conferenceEnabled: false,
            summerCampEnabled: true,
            hackathonEnabled: true
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            journal,
            competitionEnabled: false,
            schoolNoticeEnabled: false,
            conferenceEnabled: true,
            summerCampEnabled: false,
            hackathonEnabled: false
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            preAdmission,
            competitionEnabled: false,
            schoolNoticeEnabled: false,
            conferenceEnabled: false,
            summerCampEnabled: true,
            hackathonEnabled: false
        ))
        XCTAssertFalse(CalendarDeadlinePresentation.isVisible(
            contest,
            competitionEnabled: false,
            schoolNoticeEnabled: true,
            summerCampEnabled: true,
            hackathonEnabled: true
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.isVisible(
            custom,
            competitionEnabled: false,
            schoolNoticeEnabled: false,
            summerCampEnabled: false,
            hackathonEnabled: false,
            customEnabled: true
        ))
        XCTAssertFalse(CalendarDeadlinePresentation.isVisible(
            custom,
            competitionEnabled: true,
            schoolNoticeEnabled: true,
            summerCampEnabled: true,
            hackathonEnabled: true,
            customEnabled: false
        ))

        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: contest), .competition)
        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: school), .schoolNotice)
        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: conference), .conference)
        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: journal), .conference)
        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: summerCamp), .summerCamp)
        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: preAdmission), .summerCamp)
        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: hackathon), .hackathon)
        XCTAssertEqual(CalendarDeadlinePresentation.eventKind(for: custom), .customDeadline)
    }

    func testCalendarDeadlineBorderPriorityIsAssignmentThenSchoolThenPublic() {
        let holiday = CalendarAllDayEvent(id: "holiday", title: "休", kind: .holiday)
        let publicDDL = CalendarAllDayEvent(
            id: "public",
            title: "公开竞赛原文",
            kind: .competition
        )
        let conference = CalendarAllDayEvent(
            id: "conference",
            title: "会议原文",
            kind: .conference
        )
        let school = CalendarAllDayEvent(
            id: "school",
            title: "校内通知原文",
            kind: .schoolNotice
        )
        let assignment = CalendarAllDayEvent(
            id: "assignment",
            title: "作业原文",
            kind: .assignment
        )

        XCTAssertNil(CalendarDeadlinePresentation.preferredDeadlineKind(in: [holiday]))
        XCTAssertEqual(CalendarDeadlinePresentation.topTwoDeadlineKinds(in: [holiday]), [])
        XCTAssertEqual(
            CalendarDeadlinePresentation.preferredDeadlineKind(in: [holiday, publicDDL]),
            .competition
        )
        XCTAssertEqual(
            CalendarDeadlinePresentation.topTwoDeadlineKinds(in: [holiday, publicDDL]),
            [.competition]
        )
        XCTAssertEqual(
            CalendarDeadlinePresentation.preferredDeadlineKind(in: [publicDDL, school]),
            .schoolNotice
        )
        XCTAssertEqual(
            CalendarDeadlinePresentation.topTwoDeadlineKinds(in: [publicDDL, school]),
            [.schoolNotice, .competition]
        )
        XCTAssertEqual(
            CalendarDeadlinePresentation.topTwoDeadlineKinds(in: [conference, publicDDL]),
            [.competition, .conference],
            "Distinct public DDL categories should retain two independent border colors"
        )
        XCTAssertEqual(
            CalendarDeadlinePresentation.preferredDeadlineKind(in: [school, assignment, publicDDL]),
            .assignment
        )
        XCTAssertEqual(
            CalendarDeadlinePresentation.topTwoDeadlineKinds(
                in: [publicDDL, assignment, school, assignment, publicDDL]
            ),
            [.assignment, .schoolNotice],
            "Three categories must render only the two highest-priority distinct borders"
        )
        XCTAssertTrue(CalendarDeadlinePresentation.showsSecondaryTodayIndicator(
            isToday: true,
            deadlineKind: .assignment
        ))
        XCTAssertTrue(CalendarDeadlinePresentation.showsSecondaryTodayIndicator(
            isToday: true,
            deadlineKind: .competition
        ))
        XCTAssertFalse(CalendarDeadlinePresentation.showsSecondaryTodayIndicator(
            isToday: true,
            deadlineKind: nil
        ))
        XCTAssertFalse(CalendarDeadlinePresentation.showsSecondaryTodayIndicator(
            isToday: false,
            deadlineKind: .schoolNotice
        ))
    }

    func testYearDeadlineLoadingCoversLeapAndCommonYears() throws {
        let calendar = Calendar.shanghai
        let leap = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 8, day: 23)))
        let common = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23)))

        XCTAssertEqual(TeachingCalendarLogic.datesInYear(containing: leap).count, 366)
        XCTAssertEqual(TeachingCalendarLogic.datesInYear(containing: common).count, 365)
        XCTAssertEqual(
            StrictContractDateParser.string(
                from: try XCTUnwrap(TeachingCalendarLogic.datesInYear(containing: common).last)
            ),
            "2026-12-31"
        )
    }

    func testCalendarDayAccessibilityLabelPreservesExistingWording() {
        XCTAssertEqual(
            TeachingCalendarLogic.dayAccessibilityLabel(
                todayText: "今天",
                formattedDate: "2026年8月25日 星期二",
                holidayNames: ["示例假期"],
                courseDescriptions: ["08:00-09:35高等数学", "10:00-11:35大学英语"]
            ),
            "今天，2026年8月25日 星期二，示例假期，08:00-09:35高等数学，10:00-11:35大学英语"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.dayAccessibilityLabel(
                formattedDate: "Tuesday, August 25, 2026",
                holidayNames: [],
                courseDescriptions: []
            ),
            "Tuesday, August 25, 2026，无课"
        )
    }

    func testCalendarMonthGridPositionUsesMondayFirstColumns() {
        XCTAssertEqual(
            TeachingCalendarLogic.monthGridPosition(dayNumber: 1, firstWeekday: 2),
            TeachingCalendarLogic.MonthGridPosition(row: 0, column: 0)
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthGridPosition(dayNumber: 1, firstWeekday: 1),
            TeachingCalendarLogic.MonthGridPosition(row: 0, column: 6)
        )
        XCTAssertEqual(
            TeachingCalendarLogic.monthGridPosition(dayNumber: 31, firstWeekday: 7),
            TeachingCalendarLogic.MonthGridPosition(row: 5, column: 0)
        )
    }

    func testYearPopoverPlacementTracksAnchorAndFlipsAtWindowEdges() {
        let container = CGSize(width: 1_200, height: 800)
        let panel = CGSize(width: 320, height: 360)

        XCTAssertEqual(
            TeachingCalendarLogic.yearPopoverPlacement(
                anchor: CGPoint(x: 300, y: 200),
                panelSize: panel,
                containerSize: container
            ),
            TeachingCalendarLogic.YearPopoverPlacement(
                origin: CGPoint(x: 140, y: 212),
                appearsBelowAnchor: true
            )
        )
        XCTAssertEqual(
            TeachingCalendarLogic.yearPopoverPlacement(
                anchor: CGPoint(x: 1_180, y: 780),
                panelSize: panel,
                containerSize: container
            ),
            TeachingCalendarLogic.YearPopoverPlacement(
                origin: CGPoint(x: 864, y: 408),
                appearsBelowAnchor: false
            )
        )
        XCTAssertEqual(
            TeachingCalendarLogic.yearPopoverPlacement(
                anchor: CGPoint(x: 5, y: 5),
                panelSize: panel,
                containerSize: container
            ),
            TeachingCalendarLogic.YearPopoverPlacement(
                origin: CGPoint(x: 16, y: 17),
                appearsBelowAnchor: true
            )
        )
    }

    func testCalendarBoundedCacheRetainsRecentMonthAndYearEntries() {
        let cache = CalendarBoundedCache<String, Int>(capacity: 2)
        var buildCount = 0
        func value(_ key: String) -> Int {
            cache.value(for: key) {
                buildCount += 1
                return buildCount
            }
        }

        XCTAssertEqual(value("month"), 1)
        XCTAssertEqual(value("year"), 2)
        XCTAssertEqual(value("month"), 1, "A cache hit must refresh LRU recency")
        XCTAssertEqual(value("next-month"), 3)
        XCTAssertEqual(value("year"), 4, "The least recently used entry must be evicted")
        XCTAssertEqual(cache.count, 2)

        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(value("month"), 5)
    }

    func testCalendarBackgroundPrewarmUsesTheSameVisibleRangesAsEveryView() throws {
        let date = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-24"))
        XCTAssertEqual(TeachingCalendarLogic.visibleDates(containing: date, modeRawValue: "日").count, 1)
        XCTAssertEqual(TeachingCalendarLogic.visibleDates(containing: date, modeRawValue: "周").count, 7)
        XCTAssertEqual(TeachingCalendarLogic.visibleDates(containing: date, modeRawValue: "月").count, 42)
        XCTAssertEqual(TeachingCalendarLogic.visibleDates(containing: date, modeRawValue: "年").count, 365)
    }

    func testDeadlineAgendaChromeHasCompleteEnglishLocalization() {
        XCTAssertEqual(
            AppLocalization.string("月视图全天日程", language: .english),
            "Month All-day Events"
        )
        XCTAssertEqual(
            AppLocalization.string("周视图全天日程", language: .english),
            "Week All-day Events"
        )
        XCTAssertEqual(
            AppLocalization.string("公开活动 DDL", language: .english),
            "Public Event Deadlines"
        )
        XCTAssertEqual(
            AppLocalization.string("关闭全天日程", language: .english),
            "Close all-day events"
        )
        XCTAssertEqual(
            AppLocalization.string("第 %lld 教学周", language: .english),
            "Teaching week %lld"
        )
        XCTAssertEqual(
            AppLocalization.string("非教学周", language: .english),
            "Outside teaching weeks"
        )
        XCTAssertEqual(
            AppLocalization.string("自定义日程源", language: .english),
            "Custom Schedule Feed"
        )
        XCTAssertEqual(
            AppLocalization.string("收藏管理", language: .english),
            "Favorite Management"
        )
        XCTAssertEqual(
            AppLocalization.string("取消收藏", language: .english),
            "Remove favorite"
        )
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

    #if os(macOS)
    func testDesktopYearLayoutScalesToAvailableWindowHeight() {
        let compact = TeachingCalendarLogic.desktopYearLayout(availableHeight: 480)
        let expanded = TeachingCalendarLogic.desktopYearLayout(availableHeight: 900)

        XCTAssertEqual(compact.totalHeight, 480, accuracy: 0.001)
        XCTAssertEqual(expanded.totalHeight, 900, accuracy: 0.001)
        XCTAssertLessThan(compact.monthHeight, expanded.monthHeight)
        XCTAssertLessThan(compact.dayCellHeight, expanded.dayCellHeight)
        XCTAssertLessThan(compact.monthTitleFontSize, expanded.monthTitleFontSize)
        XCTAssertLessThanOrEqual(compact.selectionDiameter, compact.dayCellHeight)
        XCTAssertLessThanOrEqual(expanded.selectionDiameter, expanded.dayCellHeight)
    }


    @MainActor
    func testMacKeyboardActionsSwitchViewsPageAndDismissOverlays() throws {
        let calendar = Calendar.shanghai
        let start = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-24"))
        let today = try XCTUnwrap(StrictContractDateParser.date(from: "2026-09-01"))
        let session = TeachingCalendarSessionState()
        session.selectedDate = start
        session.modeRawValue = "周"

        session.applyKeyboardAction(.nextPeriod, calendar: calendar)
        XCTAssertEqual(StrictContractDateParser.string(from: session.selectedDate), "2026-08-31")
        XCTAssertEqual(session.transitionDirection, 1)
        session.applyKeyboardAction(.previousPeriod, calendar: calendar)
        XCTAssertEqual(StrictContractDateParser.string(from: session.selectedDate), "2026-08-24")
        XCTAssertEqual(session.transitionDirection, -1)

        for (action, mode) in [
            (AppKeyboardAction.dayView, "日"),
            (.weekView, "周"),
            (.monthView, "月"),
            (.yearView, "年"),
        ] {
            session.applyKeyboardAction(action, calendar: calendar)
            XCTAssertEqual(session.modeRawValue, mode)
        }
        XCTAssertEqual(session.transitionDirection, 1)
        session.applyKeyboardAction(.today, now: today, calendar: calendar)
        XCTAssertEqual(session.selectedDate, today)
        XCTAssertEqual(session.transitionDirection, 1)

        let originalDismissGeneration = session.dismissOverlayGeneration
        session.applyKeyboardAction(.dismissOverlay, calendar: calendar)
        XCTAssertEqual(session.dismissOverlayGeneration, originalDismissGeneration + 1)
        XCTAssertEqual(AppSection.planner.keyboardShortcutDigit, "1")
        XCTAssertEqual(AppSection.calendar.keyboardShortcutDigit, "2")
        XCTAssertEqual(AppSection.queries.keyboardShortcutDigit, "3")
        XCTAssertEqual(AppSection.settings.keyboardShortcutDigit, "4")
    }

    func testMacKeyboardNotificationRejectsUnknownActions() {
        let valid = Notification(
            name: AppKeyboardCommandNotification.name,
            userInfo: [AppKeyboardCommandNotification.actionKey: AppKeyboardAction.monthView.rawValue]
        )
        let invalid = Notification(
            name: AppKeyboardCommandNotification.name,
            userInfo: [AppKeyboardCommandNotification.actionKey: "invalid"]
        )
        XCTAssertEqual(AppKeyboardCommandNotification.action(from: valid), .monthView)
        XCTAssertNil(AppKeyboardCommandNotification.action(from: invalid))
    }
    #endif

    func testCalendarNavigationMotionUsesOneDirectionContractForDatesAndModes() throws {
        let earlier = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-23"))
        let later = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-24"))

        XCTAssertEqual(TeachingCalendarNavigationMotion.direction(from: earlier, to: later), 1)
        XCTAssertEqual(TeachingCalendarNavigationMotion.direction(from: later, to: earlier), -1)
        XCTAssertEqual(TeachingCalendarNavigationMotion.modeDirection(from: "日", to: "年"), 1)
        XCTAssertEqual(TeachingCalendarNavigationMotion.modeDirection(from: "年", to: "周"), -1)
        XCTAssertEqual(
            TeachingCalendarNavigationMotion.transitionEdges(direction: 1),
            .init(insertion: .trailing, removal: .leading)
        )
        XCTAssertEqual(
            TeachingCalendarNavigationMotion.transitionEdges(direction: -1),
            .init(insertion: .leading, removal: .trailing)
        )
    }

    func testCalendarModeTransitionPreparesDirectionBeforeCommittingIdentity() {
        let session = TeachingCalendarSessionState()
        session.modeRawValue = "月"

        let enterYear = session.prepareModeTransition(to: "年")
        XCTAssertNotNil(enterYear)
        XCTAssertEqual(session.modeRawValue, "月", "Outgoing page must render the prepared edge first")
        XCTAssertEqual(session.transitionDirection, 1)
        XCTAssertTrue(session.commitModeTransition(to: "年", generation: enterYear!))
        XCTAssertEqual(session.modeRawValue, "年")

        let returnToMonth = session.prepareModeTransition(to: "月")
        XCTAssertNotNil(returnToMonth)
        XCTAssertEqual(session.modeRawValue, "年")
        XCTAssertEqual(session.transitionDirection, -1)
        XCTAssertTrue(session.commitModeTransition(to: "月", generation: returnToMonth!))
        XCTAssertEqual(session.modeRawValue, "月")

        session.modeRawValue = "日"
        let dayToYear = session.prepareModeTransition(to: "年")
        XCTAssertEqual(session.transitionDirection, 1)
        XCTAssertTrue(session.commitModeTransition(to: "年", generation: dayToYear!))
        let yearToDay = session.prepareModeTransition(to: "日")
        XCTAssertEqual(session.transitionDirection, -1)
        XCTAssertTrue(session.commitModeTransition(to: "日", generation: yearToDay!))
    }

    func testCalendarModeTransitionRejectsAStaleCommit() {
        let session = TeachingCalendarSessionState()
        session.modeRawValue = "月"

        let yearGeneration = session.prepareModeTransition(to: "年")!
        let dayGeneration = session.prepareModeTransition(to: "日")!

        XCTAssertFalse(session.commitModeTransition(to: "年", generation: yearGeneration))
        XCTAssertEqual(session.modeRawValue, "月")
        XCTAssertTrue(session.commitModeTransition(to: "日", generation: dayGeneration))
        XCTAssertEqual(session.modeRawValue, "日")
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

    func testMonthNavigationPreservesPreferredDayAcrossShortMonthsAndReversal() throws {
        let calendar = Calendar.shanghai
        let session = TeachingCalendarSessionState()
        session.selectedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))
        )

        let september = try XCTUnwrap(
            session.monthNavigationDestination(direction: 1, calendar: calendar)
        )
        session.commitMonthNavigation(to: september)
        XCTAssertEqual(calendar.component(.day, from: session.selectedDate), 30)

        let august = try XCTUnwrap(
            session.monthNavigationDestination(direction: -1, calendar: calendar)
        )
        session.commitMonthNavigation(to: august)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: session.selectedDate),
            DateComponents(year: 2026, month: 8, day: 31)
        )
    }

    func testMonthNavigationRestoresLeapDayAnchorAndResetsAfterExplicitSelection() throws {
        let calendar = Calendar.shanghai
        let session = TeachingCalendarSessionState()
        session.selectedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2028, month: 1, day: 31))
        )

        let february = try XCTUnwrap(
            session.monthNavigationDestination(direction: 1, calendar: calendar)
        )
        session.commitMonthNavigation(to: february)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: session.selectedDate),
            DateComponents(year: 2028, month: 2, day: 29)
        )

        let march = try XCTUnwrap(
            session.monthNavigationDestination(direction: 1, calendar: calendar)
        )
        session.commitMonthNavigation(to: march)
        XCTAssertEqual(calendar.component(.day, from: session.selectedDate), 31)

        session.selectedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2028, month: 3, day: 15))
        )
        let april = try XCTUnwrap(
            session.monthNavigationDestination(direction: 1, calendar: calendar)
        )
        session.commitMonthNavigation(to: april)
        XCTAssertEqual(calendar.component(.day, from: session.selectedDate), 15)
    }

    func testCalendarPeriodTitlesShowCivilAndTeachingWeeksTogether() throws {
        let calendar = Calendar.shanghai
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))

        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(for: date, modeRawValue: "日", calendar: calendar),
            "2026年8月14日"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(
                for: date,
                modeRawValue: "周",
                teachingWeekNumber: 3,
                calendar: calendar
            ),
            "2026年8月 · 公历第 33 周 · 第 3 教学周"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(for: date, modeRawValue: "周", calendar: calendar),
            "2026年8月 · 公历第 33 周 · 非教学周"
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

    func testCalendarPeriodTitlesSupportEnglishWithoutChangingModeIdentity() throws {
        let calendar = Calendar.shanghai
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))
        )

        XCTAssertEqual(
            TeachingCalendarLogic.periodTitle(
                for: date,
                modeRawValue: "日",
                language: .english,
                calendar: calendar
            ),
            "August 23, 2026"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.weekContext(
                for: date,
                teachingWeekNumber: 9,
                language: .english,
                calendar: calendar
            ),
            "Calendar Week 34 · Teaching Week 9"
        )
    }

    func testOutOfMonthSelectionUsesTheDestinationMonthForAnimationDirection() throws {
        let july = try XCTUnwrap(StrictContractDateParser.date(from: "2026-07-31"))
        let august = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-01"))
        let augustEnd = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-31"))

        XCTAssertEqual(TeachingCalendarLogic.monthPageDirection(from: july, to: august), 1)
        XCTAssertEqual(TeachingCalendarLogic.monthPageDirection(from: august, to: july), -1)
        XCTAssertNil(TeachingCalendarLogic.monthPageDirection(from: august, to: augustEnd))
    }

    func testAppLanguagePreferenceRoundTripsThroughUserDefaults() {
        let suiteName = "AppLanguagePreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppLocalization.persistedLanguage(defaults: defaults), .system)
        defaults.set(AppLanguage.english.rawValue, forKey: AppLocalization.defaultsKey)
        XCTAssertEqual(AppLocalization.persistedLanguage(defaults: defaults), .english)
        XCTAssertEqual(AppLanguage.english.resolvedResourceName, "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedResourceName, "zh-Hans")
        XCTAssertEqual(
            AppLanguage.system.resourceName(preferredLanguages: ["zh-Hans-CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            AppLanguage.system.resourceName(preferredLanguages: ["ja-JP"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.system.resourceName(preferredLanguages: ["ko-KR"]),
            "en"
        )
    }

    func testEnglishRuntimeStatusCopyUsesTheAppLocalizationBoundary() {
        XCTAssertEqual(
            AppLocalization.string("当天空教室已更新", language: .english),
            "Today's empty rooms are up to date"
        )
        XCTAssertEqual(
            AppLocalization.string("正在导入系统日历…", language: .english),
            "Importing into the system calendar…"
        )
        let format = AppLocalization.string(
            "已安排未来 %d 个有课日的课程摘要",
            language: .english
        )
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "en"), 3),
                       "Course summaries scheduled for 3 upcoming class days")
    }

    func testEnglishInformationQueryCopyUsesTheAppLocalizationBoundary() {
        let keys = [
            "信息查询",
            "班车查询",
            "重要事件",
            "搜索名称、主办方或来源",
            "学术会议",
            "期刊专题",
            "预推免",
            "事件类型",
            "活动分类",
            "全部分类",
            "显示已结束",
            "无法同步公开活动或校内通知，请稍后重试。",
        ]
        for key in keys {
            XCTAssertNotEqual(
                AppLocalization.string(key, language: .english),
                key,
                "Missing English query localization for \(key)"
            )
        }
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

    func testRaisedMonthDetailsReceiveFurtherUpwardDrags() {
        XCTAssertTrue(
            TeachingCalendarLogic.routesMonthDragToDetails(
                position: .detailRaised,
                verticalTranslation: -24
            )
        )
        XCTAssertFalse(
            TeachingCalendarLogic.routesMonthDragToDetails(
                position: .detailRaised,
                verticalTranslation: 24
            )
        )
        XCTAssertFalse(
            TeachingCalendarLogic.routesMonthDragToDetails(
                position: .collapsed,
                verticalTranslation: -24
            )
        )
        XCTAssertTrue(
            TeachingCalendarLogic.routesMonthDragToDetails(
                position: .detailRaised,
                verticalTranslation: 24,
                detailsCanScrollBackward: true
            )
        )
        XCTAssertFalse(
            TeachingCalendarLogic.routesMonthDragToDetails(
                position: .detailRaised,
                verticalTranslation: 24,
                detailsCanScrollBackward: false
            )
        )
    }

    #if os(iOS)
    func testMobileMonthAnimationKeepsDetailsOutsideTheHorizontalPageIdentity() throws {
        let august = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-23"))
        let september = try XCTUnwrap(StrictContractDateParser.date(from: "2026-09-23"))

        XCTAssertEqual(
            MobileCalendarAnimationPartition.contentIdentity(
                modeRawValue: "月",
                selectedDate: august
            ),
            MobileCalendarAnimationPartition.contentIdentity(
                modeRawValue: "月",
                selectedDate: september
            ),
            "The stable month shell keeps the details viewport out of horizontal paging"
        )
        XCTAssertNotEqual(
            MobileCalendarAnimationPartition.monthGridIdentity(selectedDate: august),
            MobileCalendarAnimationPartition.monthGridIdentity(selectedDate: september),
            "Only the month grid receives a new page identity"
        )
    }

    func testMobileNonMonthPageIdentityStillTracksItsNavigationPeriod() throws {
        let firstDay = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-23"))
        let nextDay = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-24"))

        XCTAssertNotEqual(
            MobileCalendarAnimationPartition.contentIdentity(
                modeRawValue: "日",
                selectedDate: firstDay
            ),
            MobileCalendarAnimationPartition.contentIdentity(
                modeRawValue: "日",
                selectedDate: nextDay
            )
        )
    }

    func testMobileYearAnimationReusesSingleGridShell() throws {
        let firstYear = try XCTUnwrap(StrictContractDateParser.date(from: "2026-08-23"))
        let nextYear = try XCTUnwrap(StrictContractDateParser.date(from: "2027-08-23"))

        XCTAssertEqual(
            MobileCalendarAnimationPartition.contentIdentity(
                modeRawValue: "年",
                selectedDate: firstYear
            ),
            MobileCalendarAnimationPartition.contentIdentity(
                modeRawValue: "年",
                selectedDate: nextYear
            ),
            "Year navigation must not render two complete year grids at once"
        )
    }

    func testMobileMonthPagingRepreparesDirectionForLeftThenRight() {
        var state = MobileMonthPagingState()

        let leftSwipeGeneration = state.prepare(direction: 1)
        XCTAssertEqual(state.preparedDirection, 1)
        XCTAssertTrue(state.accepts(leftSwipeGeneration))

        let rightSwipeGeneration = state.prepare(direction: -1)
        XCTAssertEqual(state.preparedDirection, -1)
        XCTAssertFalse(state.accepts(leftSwipeGeneration))
        XCTAssertTrue(state.accepts(rightSwipeGeneration))
    }

    func testMobileMonthPagingRepreparesDirectionForRightThenLeft() {
        var state = MobileMonthPagingState()

        let rightSwipeGeneration = state.prepare(direction: -1)
        XCTAssertEqual(state.preparedDirection, -1)
        XCTAssertTrue(state.accepts(rightSwipeGeneration))

        let leftSwipeGeneration = state.prepare(direction: 1)
        XCTAssertEqual(state.preparedDirection, 1)
        XCTAssertFalse(state.accepts(rightSwipeGeneration))
        XCTAssertTrue(state.accepts(leftSwipeGeneration))
    }

    @MainActor
    func testMonthDetailsRoutingReadsTheLiveUIKitOffsetInsteadOfAStaleFallback() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        scrollView.contentSize = CGSize(width: 320, height: 960)
        let state = MobileMonthDetailsScrollState()
        state.attach(scrollView)

        scrollView.contentOffset = CGPoint(x: 0, y: 80)
        XCTAssertTrue(state.routingSnapshot(fallback: false))

        // Simulate UIKit reaching the real top before SwiftUI has published its
        // previous Binding update. Routing must trust the live scroll view.
        scrollView.contentOffset = .zero
        XCTAssertFalse(state.routingSnapshot(fallback: true))
    }
    #endif

    func testMonthDetentsHonorDeliberateLowVelocityDrags() {
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 0.15,
                verticalTranslation: 29,
                predictedVerticalTranslation: 29
            ),
            .collapsed
        )
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 1.15,
                verticalTranslation: 29,
                predictedVerticalTranslation: 29
            ),
            .expanded
        )
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 0.85,
                verticalTranslation: -29,
                predictedVerticalTranslation: -29
            ),
            .detailRaised
        )
        XCTAssertEqual(
            TeachingCalendarLogic.settledMonthPosition(
                position: 0.09,
                verticalTranslation: 18,
                predictedVerticalTranslation: 18
            ),
            .detailRaised
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

    func testMonthPositionNormalizationSynchronizesStoredDetentWithoutRedundantSettling() {
        XCTAssertTrue(
            TeachingCalendarLogic.requiresMonthPositionUpdate(
                current: .collapsed,
                target: .detailRaised,
                verticalTranslation: 0
            ),
            "Landscape normalization must update the stored detent before returning to portrait"
        )
        XCTAssertFalse(
            TeachingCalendarLogic.requiresMonthPositionUpdate(
                current: .detailRaised,
                target: .detailRaised,
                verticalTranslation: 0
            )
        )
        XCTAssertTrue(
            TeachingCalendarLogic.requiresMonthPositionUpdate(
                current: .detailRaised,
                target: .detailRaised,
                verticalTranslation: 1
            ),
            "An active drag still needs to animate back to its settled position"
        )
    }

    #if os(iOS)
    func testLandscapeTimelineRemovesInsetWhileYearKeepsTabBarClearance() {
        XCTAssertEqual(
            MobileCalendarTimelineLayout.contentBottomInset(isLandscape: false),
            MobileCalendarTimelineLayout.bottomContentInset
        )
        XCTAssertEqual(MobileCalendarTimelineLayout.contentBottomInset(isLandscape: true), 0)
        XCTAssertEqual(
            MobileCalendarYearLayout.contentBottomInset(isLandscape: false),
            MobileCalendarYearLayout.bottomContentInset
        )
        XCTAssertEqual(
            MobileCalendarYearLayout.contentBottomInset(isLandscape: true),
            MobileCalendarYearLayout.bottomContentInset
        )
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

final class MobileCalendarPerformanceLogicTests: XCTestCase {
    #if os(iOS)
    func testFormatterCacheReusesExactRequestedLocaleWithoutChangingText() throws {
        let cache = MobileCalendarDateFormatterCache()
        let locale = Locale(identifier: "fr_FR")
        let format = "EEEE, MMMM d, yyyy"
        let date = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 25, hour: 12)
        ))
        let baseline = DateFormatter()
        baseline.calendar = .shanghai
        baseline.locale = locale
        baseline.timeZone = TimeZone(identifier: "Asia/Shanghai")
        baseline.dateFormat = format

        let first = cache.formatter(format: format, locale: locale)
        let second = cache.formatter(format: format, locale: locale)

        XCTAssertTrue(first === second)
        XCTAssertEqual(first.string(from: date), baseline.string(from: date))
        XCTAssertTrue(first.string(from: date).contains("mardi"))
    }
    #endif

    func testBoundedSnapshotCacheRetainsRecentMonthAndYearKeys() {
        let cache = CalendarBoundedCache<String, Int>(capacity: 2)
        var builds = 0
        func value(_ key: String) -> Int {
            cache.value(for: key) {
                builds += 1
                return builds
            }
        }

        XCTAssertEqual(value("month-2026-08"), 1)
        XCTAssertEqual(value("year-2026"), 2)
        XCTAssertEqual(value("month-2026-08"), 1)
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(cache.keys, ["year-2026", "month-2026-08"])

        XCTAssertEqual(value("month-2026-09"), 3)
        XCTAssertEqual(cache.keys, ["month-2026-08", "month-2026-09"])
        XCTAssertEqual(value("year-2026"), 4)
        XCTAssertEqual(builds, 4, "The least-recently-used year snapshot should rebuild after eviction")
        XCTAssertEqual(cache.keys, ["month-2026-09", "year-2026"])
    }

    func testBoundedSnapshotCacheInvalidationDropsEveryProjection() {
        let cache = CalendarBoundedCache<String, String>(capacity: 4)
        XCTAssertEqual(cache.value(for: "month") { "month-value" }, "month-value")
        XCTAssertEqual(cache.value(for: "year") { "year-value" }, "year-value")

        cache.removeAll()

        XCTAssertTrue(cache.isEmpty)
        XCTAssertTrue(cache.keys.isEmpty)
        XCTAssertEqual(cache.value(for: "month") { "rebuilt" }, "rebuilt")
    }

    func testSnapshotAccessibilityProjectionPreservesExistingPunctuationAndOrder() {
        XCTAssertEqual(
            TeachingCalendarLogic.dayAccessibilityLabel(
                todayText: "今天",
                formattedDate: "2026年8月25日 星期二",
                holidayNames: ["示例节日"],
                courseDescriptions: ["08:00-08:45数据结构", "09:50-10:35计算机网络"]
            ),
            "今天，2026年8月25日 星期二，示例节日，08:00-08:45数据结构，09:50-10:35计算机网络"
        )
        XCTAssertEqual(
            TeachingCalendarLogic.dayAccessibilityLabel(
                todayText: "",
                formattedDate: "Tuesday, August 25, 2026",
                holidayNames: [],
                courseDescriptions: []
            ),
            "Tuesday, August 25, 2026，无课"
        )
    }
}

final class SemesterLogicTests: XCTestCase {
    private func shanghaiDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.shanghai.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testScheduleDefaultsLeaveBothTermFieldsBlank() {
        XCTAssertEqual(ScheduleDefaults.termID, "")
        XCTAssertEqual(ScheduleDefaults.termStartDate, "")
    }

    func testMondayOfWeekContainingAnchorsSpringAndFallStartWeeks() {
        XCTAssertEqual(
            SemesterLogic.mondayOfWeekContaining(year: 2026, month: 3, day: 2),
            "2026-03-02"
        )
        XCTAssertEqual(
            SemesterLogic.mondayOfWeekContaining(year: 2025, month: 3, day: 2),
            "2025-02-24"
        )
        XCTAssertEqual(
            SemesterLogic.mondayOfWeekContaining(year: 2024, month: 3, day: 2),
            "2024-02-26"
        )
        XCTAssertEqual(
            SemesterLogic.mondayOfWeekContaining(year: 2026, month: 9, day: 1),
            "2026-08-31"
        )
        XCTAssertEqual(
            SemesterLogic.mondayOfWeekContaining(year: 2025, month: 9, day: 1),
            "2025-09-01"
        )
    }

    func testSuggestTermForSpringMonths() {
        let start = SemesterLogic.suggestTerm(for: shanghaiDate(2026, 3, 2))
        XCTAssertEqual(start.termID, "2025-2026-2")
        XCTAssertEqual(start.termStartDate, "2026-03-02")

        let lateSpring = SemesterLogic.suggestTerm(for: shanghaiDate(2026, 7, 31))
        XCTAssertEqual(lateSpring.termID, "2025-2026-2")
        XCTAssertEqual(lateSpring.termStartDate, "2026-03-02")
    }

    func testSuggestTermForFallMonths() {
        let start = SemesterLogic.suggestTerm(for: shanghaiDate(2026, 9, 1))
        XCTAssertEqual(start.termID, "2026-2027-1")
        XCTAssertEqual(start.termStartDate, "2026-08-31")

        let lateFall = SemesterLogic.suggestTerm(for: shanghaiDate(2026, 12, 31))
        XCTAssertEqual(lateFall.termID, "2026-2027-1")
        XCTAssertEqual(lateFall.termStartDate, "2026-08-31")
    }

    func testSuggestTermForJanuaryBelongsToPreviousYearsFall() {
        let suggested = SemesterLogic.suggestTerm(for: shanghaiDate(2026, 1, 1))
        XCTAssertEqual(suggested.termID, "2025-2026-1")
        XCTAssertEqual(suggested.termStartDate, "2025-09-01")
    }

    func testSuggestTermUsesExpectedMonthBoundaries() {
        let expectedByMonth = [
            1: ("2025-2026-1", "2025-09-01"),
            2: ("2025-2026-2", "2026-03-02"),
            3: ("2025-2026-2", "2026-03-02"),
            4: ("2025-2026-2", "2026-03-02"),
            5: ("2025-2026-2", "2026-03-02"),
            6: ("2025-2026-2", "2026-03-02"),
            7: ("2025-2026-2", "2026-03-02"),
            8: ("2026-2027-1", "2026-08-31"),
            9: ("2026-2027-1", "2026-08-31"),
            10: ("2026-2027-1", "2026-08-31"),
            11: ("2026-2027-1", "2026-08-31"),
            12: ("2026-2027-1", "2026-08-31"),
        ]

        for month in 1 ... 12 {
            let firstDay = SemesterLogic.suggestTerm(for: shanghaiDate(2026, month, 1))
            let expected = expectedByMonth[month]
            XCTAssertEqual(firstDay.termID, expected?.0, "month \(month)")
            XCTAssertEqual(firstDay.termStartDate, expected?.1, "month \(month)")
        }

        XCTAssertEqual(
            SemesterLogic.suggestTerm(for: shanghaiDate(2026, 1, 31)).termID,
            "2025-2026-1"
        )
        XCTAssertEqual(
            SemesterLogic.suggestTerm(for: shanghaiDate(2026, 7, 31)).termID,
            "2025-2026-2"
        )
        XCTAssertEqual(
            SemesterLogic.suggestTerm(for: shanghaiDate(2026, 12, 31)).termID,
            "2026-2027-1"
        )
    }

    func testSuggestTermUsesShanghaiDateAcrossUTCBoundaries() throws {
        let formatter = ISO8601DateFormatter()
        let beforeFebruary = try XCTUnwrap(formatter.date(from: "2026-01-31T15:59:00Z"))
        let afterFebruary = try XCTUnwrap(formatter.date(from: "2026-01-31T16:00:00Z"))
        let beforeAugust = try XCTUnwrap(formatter.date(from: "2026-07-31T15:59:00Z"))
        let afterAugust = try XCTUnwrap(formatter.date(from: "2026-07-31T16:00:00Z"))

        XCTAssertEqual(SemesterLogic.suggestTerm(for: beforeFebruary).termID, "2025-2026-1")
        XCTAssertEqual(SemesterLogic.suggestTerm(for: afterFebruary).termID, "2025-2026-2")
        XCTAssertEqual(SemesterLogic.suggestTerm(for: beforeAugust).termID, "2025-2026-2")
        XCTAssertEqual(SemesterLogic.suggestTerm(for: afterAugust).termID, "2026-2027-1")
    }

    func testAutomaticSettingsIgnorePersistedDefaultsAndOldTermCache() {
        let resolved = SemesterLogic.resolveSettings(
            automaticDetectionEnabled: true,
            persistedTermID: ScheduleDefaults.termID,
            persistedTermStartDate: ScheduleDefaults.termStartDate,
            cachedTermID: "2025-2026-2",
            cachedTermStartDate: "2026-03-09",
            for: shanghaiDate(2026, 8, 24)
        )

        XCTAssertEqual(
            resolved,
            SemesterLogic.Settings(termID: "2026-2027-1", termStartDate: "2026-08-31")
        )
    }

    func testAutomaticSettingsKeepValidRealStartDateForCurrentCachedTerm() {
        let resolved = SemesterLogic.resolveSettings(
            automaticDetectionEnabled: true,
            persistedTermID: ScheduleDefaults.termID,
            persistedTermStartDate: ScheduleDefaults.termStartDate,
            cachedTermID: " 2026-2027-1 ",
            cachedTermStartDate: " 2026-09-07 ",
            for: shanghaiDate(2026, 8, 24)
        )

        XCTAssertEqual(
            resolved,
            SemesterLogic.Settings(termID: "2026-2027-1", termStartDate: "2026-09-07")
        )
    }

    func testAutomaticSettingsRejectInvalidCurrentTermCachedStartDate() {
        let resolved = SemesterLogic.resolveSettings(
            automaticDetectionEnabled: true,
            persistedTermID: nil,
            persistedTermStartDate: nil,
            cachedTermID: "2026-2027-1",
            cachedTermStartDate: "2026-09-31",
            for: shanghaiDate(2026, 8, 24)
        )

        XCTAssertEqual(
            resolved,
            SemesterLogic.Settings(termID: "2026-2027-1", termStartDate: "2026-08-31")
        )
    }

    func testManualSettingsKeepPersistedValuesAndIgnoreCache() {
        let resolved = SemesterLogic.resolveSettings(
            automaticDetectionEnabled: false,
            persistedTermID: "manual-term",
            persistedTermStartDate: "2024-10-14",
            cachedTermID: "2026-2027-1",
            cachedTermStartDate: "2026-09-07",
            for: shanghaiDate(2026, 8, 24)
        )

        XCTAssertEqual(
            resolved,
            SemesterLogic.Settings(termID: "manual-term", termStartDate: "2024-10-14")
        )
    }

    func testValidTermIDAcceptsStandardAndRejectsMalformed() {
        XCTAssertTrue(SemesterLogic.isValidTermID("2025-2026-2"))
        XCTAssertTrue(SemesterLogic.isValidTermID("2025-2026-1"))
        XCTAssertTrue(SemesterLogic.isValidTermID(" 2025-2026-2 "))
        for value in ["2025-2026-3", "2025-2026", "20252026-2", "25-26-2", "2025-2026-0", ""] {
            XCTAssertFalse(SemesterLogic.isValidTermID(value), value)
        }
    }

    func testValidTermStartDateRejectsImpossibleDates() {
        XCTAssertTrue(SemesterLogic.isValidTermStartDate("2026-03-02"))
        XCTAssertTrue(SemesterLogic.isValidTermStartDate("2024-02-29"))
        XCTAssertTrue(SemesterLogic.isValidTermStartDate(" 2026-03-02 "))
        for value in [
            "2026-02-30", "2025-02-29", "2026-13-01", "2026-00-01",
            "2026-03-2", "20260302", "",
        ] {
            XCTAssertFalse(SemesterLogic.isValidTermStartDate(value), value)
        }
    }

    func testMatchesCurrentPeriodComparesAgainstSuggestion() {
        let now = shanghaiDate(2026, 3, 2)
        XCTAssertTrue(SemesterLogic.matchesCurrentPeriod(
            termID: "2025-2026-2",
            termStartDate: "2026-03-02",
            on: now
        ))
        XCTAssertFalse(SemesterLogic.matchesCurrentPeriod(
            termID: "2025-2026-1",
            termStartDate: "2025-09-01",
            on: now
        ))
        XCTAssertFalse(SemesterLogic.matchesCurrentPeriod(
            termID: "not-a-term",
            termStartDate: "2026-03-02",
            on: now
        ))
        XCTAssertFalse(SemesterLogic.matchesCurrentPeriod(
            termID: "2025-2026-2",
            termStartDate: "not-a-date",
            on: now
        ))
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
