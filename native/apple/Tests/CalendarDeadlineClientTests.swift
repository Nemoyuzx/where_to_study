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

    func testBatchParsersReuseOnePayloadAcrossVisibleDates() throws {
        let contestData = Data(#"""
        {"items":[
          {"id":"c1","name":"竞赛一","event_type":"competition","primary_deadline":"2026-08-22T18:00:00+08:00"},
          {"id":"c2","name":"竞赛二","event_type":"competition","primary_deadline":"2026-08-23T18:00:00+08:00"}
        ]}
        """#.utf8)
        let parsed = try PublicDeadlineClient.parse(
            data: contestData,
            requestedDates: ["2026-08-22", "2026-08-23"]
        )

        XCTAssertEqual(parsed["2026-08-22"]?.map(\.id), ["c1"])
        XCTAssertEqual(parsed["2026-08-23"]?.map(\.id), ["c2"])
    }

    @MainActor
    func testStoreLoadsVisiblePublicDatesThroughOneBatchRequest() async {
        let recorder = BatchDeadlineRecorder()
        let store = CalendarDeadlineStore(client: BatchDeadlineClient(recorder: recorder))
        let dates = ["2026-08-22", "2026-08-23", "2026-08-24"]

        await store.loadPublic(dates: dates, sampleMode: false)

        let batches = await recorder.batches
        XCTAssertEqual(batches, [dates])
        XCTAssertEqual(Set(store.publicByDate.keys), Set(dates))
    }

    @MainActor
    func testCancelledViewTaskDoesNotAbandonSharedPublicRangeLoad() async {
        let client = SuspendedPublicDeadlineClient()
        let store = CalendarDeadlineStore(client: client)
        let dates = ["2026-08-22", "2026-08-23"]
        let originalViewTask = Task {
            await store.loadPublic(dates: dates, sampleMode: false)
        }
        await client.waitUntilStarted()

        originalViewTask.cancel()
        await store.loadPublic(dates: dates, sampleMode: false)
        await client.complete(dates: dates)
        await originalViewTask.value

        XCTAssertEqual(Set(store.publicByDate.keys), Set(dates))
        XCTAssertTrue(store.loadingPublicDates.isEmpty)
        let invocationCount = await client.invocationCount
        XCTAssertEqual(invocationCount, 1)
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

    func testUCloudConcurrentDatesShareOneAccountWideFetchAll() async throws {
        let provider = ControlledUCloudFetch()
        let selection = FlightSelectionRecorder()
        let client = UCloudAssignmentClient(
            credentialStore: StaticDeadlineCredentialStore(),
            fetchAll: { credentials in
                try await provider.fetch(credentials: credentials)
            },
            flightSelectionObserver: { isLeader in
                Task { await selection.record(isLeader: isLeader) }
            }
        )
        let first = Task { try await client.fetch(date: "2026-08-22") }
        await provider.waitUntilInvocationCount(1)
        let second = Task { try await client.fetch(date: "2026-08-23") }

        await selection.waitUntilCount(2)
        let leadership = await selection.values
        XCTAssertEqual(leadership.filter { $0 }.count, 1)
        XCTAssertEqual(leadership.filter { !$0 }.count, 1)
        let invocationCountBeforeCompletion = await provider.invocationCount
        XCTAssertEqual(invocationCountBeforeCompletion, 1)

        await provider.complete(
            invocation: 1,
            with: [
                assignment(id: "first", deadline: "2026-08-22 18:00:00"),
                assignment(id: "second", deadline: "2026-08-23 19:00:00")
            ]
        )
        let firstItems = try await first.value
        let secondItems = try await second.value
        XCTAssertEqual(firstItems.map(\.id), ["first"])
        XCTAssertEqual(secondItems.map(\.id), ["second"])
        let invocationCountAfterCompletion = await provider.invocationCount
        XCTAssertEqual(invocationCountAfterCompletion, 1)
    }

    func testUCloudBatchFiltersSeveralVisibleDatesAfterOneAccountWideFetch() async throws {
        let provider = ControlledUCloudFetch()
        let client = UCloudAssignmentClient(
            credentialStore: StaticDeadlineCredentialStore(),
            fetchAll: { credentials in
                try await provider.fetch(credentials: credentials)
            }
        )
        let request = Task {
            try await client.fetch(dates: ["2026-08-22", "2026-08-23", "2026-08-24"])
        }
        await provider.waitUntilInvocationCount(1)
        await provider.complete(
            invocation: 1,
            with: [
                assignment(id: "first", deadline: "2026-08-22 18:00:00"),
                assignment(id: "second", deadline: "2026-08-23 19:00:00")
            ]
        )

        let itemsByDate = try await request.value
        XCTAssertEqual(itemsByDate["2026-08-22"]?.map(\.id), ["first"])
        XCTAssertEqual(itemsByDate["2026-08-23"]?.map(\.id), ["second"])
        XCTAssertEqual(itemsByDate["2026-08-24"], [])
        let invocationCount = await provider.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testUCloudResetInvalidatesOldFlightAndPreventsItsCacheWriteBack() async throws {
        let provider = ControlledUCloudFetch()
        let client = UCloudAssignmentClient(
            credentialStore: StaticDeadlineCredentialStore(),
            fetchAll: { credentials in
                try await provider.fetch(credentials: credentials)
            }
        )
        let oldRequest = Task { try await client.fetch(date: "2026-08-23") }
        await provider.waitUntilInvocationCount(1)

        await client.reset()
        let refreshedRequest = Task { try await client.fetch(date: "2026-08-23") }
        await provider.waitUntilInvocationCount(2)
        await provider.complete(
            invocation: 2,
            with: [assignment(id: "new", deadline: "2026-08-23 09:00:00")]
        )
        let refreshed = try await refreshedRequest.value
        XCTAssertEqual(refreshed.map(\.id), ["new"])

        await provider.complete(
            invocation: 1,
            with: [assignment(id: "old", deadline: "2026-08-23 08:00:00")]
        )
        do {
            _ = try await oldRequest.value
            XCTFail("已清空的旧请求不应再交付结果")
        } catch is CancellationError {
            // Expected: reset invalidates both the shared task and its eventual write-back.
        }

        let cached = try await client.fetch(date: "2026-08-23")
        XCTAssertEqual(cached.map(\.id), ["new"])
        let finalInvocationCount = await provider.invocationCount
        XCTAssertEqual(finalInvocationCount, 2)
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

private actor BatchDeadlineRecorder {
    private(set) var batches = [[String]]()

    func record(_ dates: [String]) {
        batches.append(dates)
    }
}

private actor SuspendedPublicDeadlineClient: PublicDeadlineFetching {
    private(set) var invocationCount = 0
    private var startedWaiters = [CheckedContinuation<Void, Never>]()
    private var continuation: CheckedContinuation<[String: PublicDeadlineSnapshot], Error>?

    func fetch(date: String) async throws -> PublicDeadlineSnapshot {
        let snapshots = try await fetch(dates: [date])
        guard let snapshot = snapshots[date] else {
            throw CalendarDeadlineError.service("missing test snapshot")
        }
        return snapshot
    }

    func fetch(dates _: [String]) async throws -> [String: PublicDeadlineSnapshot] {
        invocationCount += 1
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard invocationCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func complete(dates: [String]) {
        continuation?.resume(returning: Dictionary(uniqueKeysWithValues: dates.map { date in
            (
                date,
                PublicDeadlineSnapshot(
                    date: date,
                    items: [],
                    source: CalendarDeadlineSources.primary,
                    usedBackup: false
                )
            )
        }))
        continuation = nil
    }
}

private struct BatchDeadlineClient: PublicDeadlineFetching {
    let recorder: BatchDeadlineRecorder

    func fetch(date: String) async throws -> PublicDeadlineSnapshot {
        let snapshots = try await fetch(dates: [date])
        return try XCTUnwrap(snapshots[date])
    }

    func fetch(dates: [String]) async throws -> [String: PublicDeadlineSnapshot] {
        await recorder.record(dates)
        return Dictionary(uniqueKeysWithValues: dates.map { date in
            (
                date,
                PublicDeadlineSnapshot(
                    date: date,
                    items: [],
                    source: CalendarDeadlineSources.primary,
                    usedBackup: false
                )
            )
        })
    }
}

private struct StaticDeadlineCredentialStore: CredentialStoring {
    func load() throws -> Credentials? {
        Credentials(account: "2023000000", password: "password")
    }

    func save(_: Credentials) throws {}
    func clear() throws {}
}

private actor ControlledUCloudFetch {
    private(set) var invocationCount = 0
    private var invocationWaiters = [(count: Int, continuation: CheckedContinuation<Void, Never>)]()
    private var continuations = [
        Int: CheckedContinuation<[AssignmentDeadlineItem], Error>
    ]()

    func fetch(credentials _: Credentials) async throws -> [AssignmentDeadlineItem] {
        invocationCount += 1
        let invocation = invocationCount
        let ready = invocationWaiters.filter { $0.count <= invocationCount }
        invocationWaiters.removeAll { $0.count <= invocationCount }
        ready.forEach { $0.continuation.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[invocation] = continuation
        }
    }

    func waitUntilInvocationCount(_ count: Int) async {
        guard invocationCount < count else { return }
        await withCheckedContinuation { continuation in
            invocationWaiters.append((count, continuation))
        }
    }

    func complete(invocation: Int, with items: [AssignmentDeadlineItem]) {
        continuations.removeValue(forKey: invocation)?.resume(returning: items)
    }
}

private actor FlightSelectionRecorder {
    private(set) var values = [Bool]()
    private var waiters = [(count: Int, continuation: CheckedContinuation<Void, Never>)]()

    func record(isLeader: Bool) {
        values.append(isLeader)
        let ready = waiters.filter { $0.count <= values.count }
        waiters.removeAll { $0.count <= values.count }
        ready.forEach { $0.continuation.resume() }
    }

    func waitUntilCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

private func assignment(id: String, deadline: String) -> AssignmentDeadlineItem {
    AssignmentDeadlineItem(
        id: id,
        title: id,
        courseName: "course",
        deadline: deadline,
        status: "未提交"
    )
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
