import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class CalendarDeadlineClientTests: XCTestCase {
    func testPublicDDLParserFiltersDateAndSupportedKinds() throws {
        let data = Data(#"""
        {
          "items":[
            {"id":"c1","name":"数据库竞赛","event_type":"competition","primary_deadline":"2026-08-22T18:00:00+08:00","organizer":"组委会","official_url":"https://example.com/c1"},
            {"id":"h1","name":"校园黑客松","event_type":"hackathon","primary_deadline":"2026-08-22T23:59:59+08:00"},
            {"id":"s1","name":"夏令营","event_type":"summer_camp","primary_deadline":"2026-08-23T23:59:59+08:00"},
            {"id":"x1","name":"未知类型","event_type":"other","primary_deadline":"2026-08-22T12:00:00+08:00"}
          ]
        }
        """#.utf8)

        let parsed = try PublicDeadlineClient.parse(
            data: data,
            requestedDate: "2026-08-22"
        )
        XCTAssertEqual(parsed.map(\.id), ["c1", "h1"])
        XCTAssertEqual(parsed.first?.officialURL?.scheme, "https")
    }

    func testPublicDDLParserDropsPlainHTTPOfficialLink() throws {
        let data = Data(#"""
        {"items":[{"id":"c1","name":"竞赛","event_type":"competition","primary_deadline":"2026-08-22T18:00:00+08:00","official_url":"http://example.com"}]}
        """#.utf8)
        let parsed = try PublicDeadlineClient.parse(
            data: data,
            requestedDate: "2026-08-22"
        )
        XCTAssertNil(parsed.first?.officialURL)
    }

    func testSchoolNoticeParserExpandsAllDeadlinesOnSelectedDay() throws {
        let data = Data(#"""
        {
          "items":[{
            "id":"bupt-ucloud-1",
            "name":"校内创新竞赛",
            "deadlines":[
              {"date":"2026-08-22T10:00:00+08:00","label":"材料提交"},
              {"date":"2026-08-23T23:59:59+08:00","label":"报名截止"}
            ],
            "source":"北京邮电大学教学云平台",
            "source_url":"https://ucloud.bupt.edu.cn/#/consulting?type=1&id=1"
          }]
        }
        """#.utf8)

        let parsed = try PublicDeadlineClient.parseSchoolNotices(
            data: data,
            requestedDate: "2026-08-22"
        )
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.kind, .competition)
        XCTAssertEqual(parsed.first?.source, .schoolNotice)
        XCTAssertEqual(parsed.first?.organizer, "北京邮电大学教学云平台 · 材料提交")
        XCTAssertEqual(parsed.first?.officialURL?.host, "ucloud.bupt.edu.cn")
    }

    func testAssignmentParserSupportsConfirmedCourseListContract() throws {
        let data = Data(#"""
        {
          "data":{
            "records":[
              {"id":7,"assignmentTitle":"第四次作业","siteName":"神经网络与深度学习","assignmentEndTime":"2026-06-30 23:59:00","assignmentStatus":99},
              {"id":8,"assignmentTitle":"第三次作业","assignmentEndTime":"2026-06-21 23:59:00","assignmentStatus":0}
            ]
          }
        }
        """#.utf8)
        let parsed = try AssignmentDeadlineParser.parse(
            data: data,
            requestedDate: "2026-06-30"
        )
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.title, "第四次作业")
        XCTAssertEqual(parsed.first?.courseName, "神经网络与深度学习")
        XCTAssertEqual(parsed.first?.status, "未提交")
    }

    func testAssignmentParserSupportsHomepageUndoneContract() throws {
        let data = Data(#"""
        {
          "data":{
            "undoneList":[
              {"activityId":"a1","activityName":"课程作业","type":3,"endTime":"2026-08-22 18:00:00"},
              {"activityId":"q1","activityName":"课程测验","type":4,"endTime":"2026-08-22 20:00:00"}
            ]
          }
        }
        """#.utf8)
        let parsed = try AssignmentDeadlineParser.parse(
            data: data,
            requestedDate: "2026-08-22"
        )
        XCTAssertEqual(parsed.map(\.id), ["a1"])
    }

    func testUCloudCASExecutionParserSupportsAttributeOrderAndEntities() {
        XCTAssertEqual(
            UCloudAssignmentClient.parseExecution(
                #"<input value='e1&amp;s1' type='hidden' name='execution'>"#
            ),
            "e1&s1"
        )
        XCTAssertEqual(
            UCloudAssignmentClient.parseExecution(#"<input name=execution value=token-2>"#),
            "token-2"
        )
    }

    func testUCloudTicketRedirectRequiresPinnedHTTPSHost() {
        XCTAssertEqual(
            UCloudAssignmentClient.ticket(
                from: "https://ucloud.bupt.edu.cn/?ticket=ST-test"
            ),
            "ST-test"
        )
        XCTAssertNil(UCloudAssignmentClient.ticket(
            from: "http://ucloud.bupt.edu.cn/?ticket=ST-test"
        ))
        XCTAssertNil(UCloudAssignmentClient.ticket(
            from: "https://evil.example/?ticket=ST-test"
        ))
    }

    func testAssignmentParserInjectsCourseNameFromCourseList() {
        let root: [String: Any] = [
            "data": [
                "records": [[
                    "id": "a1",
                    "assignmentTitle": "作业一",
                    "assignmentEndTime": "2026-08-22 23:59:00",
                    "assignmentStatus": 99
                ]]
            ]
        ]
        let items = AssignmentDeadlineParser.parseAll(
            root: root,
            courseNameOverride: "示例课程"
        )
        XCTAssertEqual(items.first?.courseName, "示例课程")
    }

    @MainActor
    func testClearingAssignmentsDiscardsAnOlderInFlightResponse() async {
        let client = SuspendedAssignmentClient()
        let store = CalendarDeadlineStore(assignmentClient: client)
        let request = Task {
            await store.loadAssignments(date: "2026-08-22", sampleMode: false)
        }

        await client.waitUntilStarted()
        store.clearAssignments()
        await client.complete(with: [
            AssignmentDeadlineItem(
                id: "old-account-assignment",
                title: "旧账号作业",
                courseName: "旧账号课程",
                deadline: "2026-08-22 23:59:00",
                status: "未提交"
            )
        ])
        await request.value

        XCTAssertTrue(store.assignmentsByDate.isEmpty)
        XCTAssertTrue(store.assignmentUnavailableByDate.isEmpty)
        XCTAssertTrue(store.loadingAssignmentDates.isEmpty)
    }
}

private actor SuspendedAssignmentClient: AssignmentDeadlineFetching {
    private var started = false
    private var startedWaiters = [CheckedContinuation<Void, Never>]()
    private var fetchContinuation: CheckedContinuation<[AssignmentDeadlineItem], Error>?

    func fetch(date _: String) async throws -> [AssignmentDeadlineItem] {
        started = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            fetchContinuation = continuation
        }
    }

    func reset() async {}

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func complete(with items: [AssignmentDeadlineItem]) {
        fetchContinuation?.resume(returning: items)
        fetchContinuation = nil
    }
}
