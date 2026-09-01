import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class ShuttleBusClientTests: XCTestCase {
    func testParserAndTodayLogicUseOnlyTheActivePeriodAndWeekday() throws {
        let snapshot = try ShuttleBusClient.parse(data: fixtureData)
        XCTAssertEqual(snapshot.notices.first?.id, "latest")
        XCTAssertEqual(snapshot.sourcePage.host, "hq.bupt.edu.cn")

        let day = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 31)
        ))
        let schedules = ShuttleBusTodayLogic.activeSchedules(in: snapshot, on: day)
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules.first?.from, "西土城路校区")
        XCTAssertEqual(
            schedules.first.map { ShuttleBusTodayLogic.departures(for: $0, on: day) }?.map(\.departureTime),
            ["06:30", "08:30"]
        )
    }

    func testTodayLogicDoesNotPresentExpiredScheduleAsCurrent() throws {
        let snapshot = try ShuttleBusClient.parse(data: fixtureData)
        let day = try XCTUnwrap(Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 9, day: 5)
        ))
        XCTAssertTrue(ShuttleBusTodayLogic.activeSchedules(in: snapshot, on: day).isEmpty)
    }

    func testParserRejectsUnsupportedSchema() {
        let data = fixtureData.replacingOccurrences(of: #""schema_version":"1.0""#, with: #""schema_version":"2.0""#)
        XCTAssertThrowsError(try ShuttleBusClient.parse(data: Data(data.utf8)))
    }

    func testParserDropsNeedsReviewScheduleWithUnknownDirectionWithoutRejectingPayload() throws {
        let snapshot = try ShuttleBusClient.parse(data: fixtureData)
        let notice = try XCTUnwrap(snapshot.notices.first)

        XCTAssertEqual(notice.schedules.count, 2)
        XCTAssertTrue(notice.schedules.allSatisfy { !$0.from.isEmpty && !$0.to.isEmpty })
    }

    @MainActor
    func testLiveClientStoreAndTodayUIState() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WTS_RUN_LIVE_SHUTTLE_TESTS"] == "1",
            "Set WTS_RUN_LIVE_SHUTTLE_TESTS=1 to exercise the production shuttle API."
        )

        let store = ShuttleBusStore()
        await store.load(force: true)

        XCTAssertTrue(store.errorMessage.isEmpty, store.errorMessage)
        let snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(snapshot.sourcePage.host, "hq.bupt.edu.cn")
        let schedules = ShuttleBusTodayLogic.activeSchedules(in: snapshot, on: .now)
        XCTAssertFalse(schedules.isEmpty, "The production payload should contain an active timetable today.")
        XCTAssertGreaterThan(
            schedules.flatMap { ShuttleBusTodayLogic.departures(for: $0, on: .now) }.count,
            0,
            "The iPhone UI should have at least one departure to render today."
        )
    }

    func testRedirectDelegateRejectsRedirectBeforeFollowingIt() throws {
        let original = try XCTUnwrap(URL(string: "https://where-to-study.cn/api/shuttle-bus"))
        let redirected = try XCTUnwrap(URL(string: "https://example.com/redirected"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: original,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": redirected.absoluteString]
        ))
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: original)
        let expectation = expectation(description: "shuttle redirect rejected")
        ShuttleBusRedirectDelegate().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirected)
        ) { request in
            XCTAssertNil(request)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testImportantEventQueryMergesFavoritesSortsAndExcludesCustom() {
        let later = event(
            id: "later",
            name: "人工智能会议",
            kind: .conference,
            source: .contestDDL,
            deadline: "2026-09-02T12:00:00+08:00"
        )
        let earlier = event(
            id: "earlier",
            name: "校内竞赛",
            kind: .competition,
            source: .schoolNotice,
            deadline: "2026-09-01T12:00:00+08:00"
        )
        let custom = event(
            id: "custom",
            name: "自定义",
            kind: .custom,
            source: .custom,
            deadline: "2026-08-31T12:00:00+08:00"
        )
        let merged = ImportantEventQueryLogic.mergedItems(
            liveItems: [later, custom],
            favoriteItems: [earlier, later]
        )
        XCTAssertEqual(merged.map(\.id), ["earlier", "later"])
        XCTAssertEqual(
            ImportantEventQueryLogic.filteredItems(
                merged,
                query: "人工智能",
                category: .conference,
                now: fixedNow
            ).map(\.id),
            ["later"]
        )
        XCTAssertEqual(
            ImportantEventQueryLogic.filteredItems(
                merged,
                query: "",
                category: .schoolNotice,
                now: fixedNow
            ).map(\.id),
            ["earlier"]
        )
    }

    func testImportantEventQuerySearchesMetadataAndFiltersRealCategory() {
        let item = PublicDeadlineItem(
            id: "metadata",
            name: "会议简称",
            kind: .conference,
            source: .contestDDL,
            deadline: "2026-09-10T12:00:00+08:00",
            organizer: "组委会",
            officialURL: nil,
            categories: ["人工智能", "计算机视觉"],
            tags: ["CCF A"],
            level: "international",
            location: "Beijing",
            description: "视觉语言模型",
            eligibility: "researchers",
            notes: "投稿前复核官网",
            metadataSource: PublicDeadlineMetadataSource(
                name: "CCFDDL",
                url: URL(string: "https://ccfddl.com"),
                sourceType: "trusted_community",
                authority: 4
            ),
            status: "submission_open",
            region: "global",
            mode: "offline"
        )
        XCTAssertEqual(
            ImportantEventQueryLogic.filteredItems(
                [item],
                query: "视觉语言",
                category: .all,
                metadataCategory: "人工智能",
                now: fixedNow
            ).map(\.id),
            ["metadata"]
        )
        XCTAssertTrue(ImportantEventQueryLogic.filteredItems(
            [item],
            query: "CCFDDL",
            category: .all,
            metadataCategory: "机器人",
            now: fixedNow
        ).isEmpty)
        XCTAssertEqual(
            Set(ImportantEventQueryLogic.metadataCategories(
                in: [item],
                now: fixedNow
            )),
            Set(["人工智能", "计算机视觉"])
        )
    }

    func testImportantEventQueryHidesPastAndArchivedByDefault() {
        let future = event(
            id: "future",
            name: "未来",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-09-02T12:00:00+08:00"
        )
        let past = event(
            id: "past",
            name: "过去",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-08-30T12:00:00+08:00"
        )
        let archived = PublicDeadlineItem(
            id: "archived",
            name: "已归档",
            kind: .competition,
            source: .contestDDL,
            deadline: "2026-09-03T12:00:00+08:00",
            organizer: nil,
            officialURL: nil,
            archived: true
        )
        XCTAssertEqual(
            ImportantEventQueryLogic.filteredItems(
                [past, archived, future],
                query: "",
                category: .all,
                now: fixedNow
            ).map(\.id),
            ["future"]
        )
        XCTAssertEqual(
            Set(ImportantEventQueryLogic.filteredItems(
                [past, archived, future],
                query: "",
                category: .all,
                showsEnded: true,
                now: fixedNow
            ).map(\.id)),
            Set(["past", "archived", "future"])
        )
    }

    func testImportantEventIncrementalRenderingStartsSmallAndLoadsNearBottom() {
        XCTAssertEqual(
            ImportantEventIncrementalRendering.visibleCount(totalCount: 75, requestedCount: 20),
            20
        )
        XCTAssertFalse(ImportantEventIncrementalRendering.shouldLoadNextBatch(
            appearingIndex: 14,
            visibleCount: 20,
            totalCount: 75
        ))
        XCTAssertTrue(ImportantEventIncrementalRendering.shouldLoadNextBatch(
            appearingIndex: 16,
            visibleCount: 20,
            totalCount: 75
        ))
        XCTAssertEqual(
            ImportantEventIncrementalRendering.nextRequestedCount(
                currentCount: 20,
                totalCount: 75
            ),
            40
        )
        XCTAssertEqual(
            ImportantEventIncrementalRendering.nextRequestedCount(
                currentCount: 60,
                totalCount: 75
            ),
            75
        )
        XCTAssertFalse(ImportantEventIncrementalRendering.shouldLoadNextBatch(
            appearingIndex: 74,
            visibleCount: 75,
            totalCount: 75
        ))
    }

    func testModeSelectionIsLocalAndFirstAppearancePrewarmsBothSources() {
        XCTAssertTrue(InformationQueryLoadPolicy.sources(for: .modeSelection).isEmpty)
        XCTAssertEqual(
            InformationQueryLoadPolicy.sources(for: .firstAppearance),
            [.shuttle, .importantEvents]
        )
        XCTAssertEqual(
            InformationQueryLoadPolicy.sources(for: .manualShuttleRefresh),
            [.shuttle]
        )
        XCTAssertEqual(
            InformationQueryLoadPolicy.sources(for: .manualEventRefresh),
            [.importantEvents]
        )
    }

    @MainActor
    func testFirstAppearancePrewarmsShuttleAndEventsConcurrently() async throws {
        let gate = QueryPrewarmGate()
        let shuttleStore = ShuttleBusStore(client: GatedShuttleClient(gate: gate))
        let deadlineStore = CalendarDeadlineStore(client: GatedDeadlineClient(gate: gate))
        let preload = Task { @MainActor in
            await InformationQueryPreloader.prewarm(
                shuttleStore: shuttleStore,
                deadlineStore: deadlineStore,
                sampleMode: false
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        let startedSources = await gate.startedSources
        XCTAssertEqual(startedSources, [.shuttle, .importantEvents])
        await gate.release()
        await preload.value
        XCTAssertNotNil(shuttleStore.snapshot)
        XCTAssertFalse(deadlineStore.isLoadingPublicFeed)
    }

    func testDynamicPublicFeedErrorsUseEnglishFallbackCopy() {
        XCTAssertEqual(
            InformationQueryErrorLocalization.string(
                "主 DDL 数据源不可用（网络连接失败）；备用数据源也不可用。",
                language: .english
            ),
            "Unable to sync public events or on-campus notices. Try again later."
        )
    }

    private func event(
        id: String,
        name: String,
        kind: PublicDeadlineKind,
        source: PublicDeadlineSource,
        deadline: String
    ) -> PublicDeadlineItem {
        PublicDeadlineItem(
            id: id,
            name: name,
            kind: kind,
            source: source,
            deadline: deadline,
            organizer: nil,
            officialURL: nil
        )
    }

    private var fixtureData: Data {
        Data(fixtureJSON.utf8)
    }

    private var fixtureJSON: String {
        #"""
        {
          "schema_version":"1.0",
          "generated_at":"2026-08-31T00:59:26Z",
          "status":"healthy",
          "source":{"name":"北京邮电大学后勤部","page_url":"https://hq.bupt.edu.cn/tzgg.htm"},
          "last_parsed_notice_id":"latest",
          "items":[{
            "id":"latest",
            "title":"关于两校区班车运行调整的通知",
            "published_at":"2026-08-19",
            "source_url":"https://hq.bupt.edu.cn/info/1010/1541.htm",
            "kind":"regular_schedule",
            "notes":[],
            "stops":[{"campus":"西土城路校区","location":"教三楼西侧"}],
            "parse_status":"parsed",
            "schedules":[
              {
                "period":{"label":"第一时段","start_date":"2026-08-27","end_date":"2026-09-04"},
                "from":"西土城路校区",
                "to":"沙河校区",
                "parse_status":"parsed",
                "rows":[
                  {"departure_time":"06:30","services":{"monday":{"vehicle":"大巴","count":1},"tuesday":null}},
                  {"departure_time":"08:30","services":{"monday":{"vehicle":"中巴","count":1}}}
                ]
              },
              {
                "period":{"label":"第二时段","start_date":"2026-09-07","end_date":null},
                "from":"沙河校区",
                "to":"西土城路校区",
                "parse_status":"parsed",
                "rows":[{"departure_time":"07:00","services":{"monday":{"vehicle":"大巴","count":1}}}]
              },
              {
                "period":{"label":"通知所示时段","start_date":null,"end_date":null},
                "from":null,
                "to":null,
                "parse_status":"needs_review",
                "rows":[]
              }
            ]
          }]
        }
        """#
    }

    private var fixedNow: Date {
        Calendar.shanghai.date(
            from: DateComponents(year: 2026, month: 8, day: 31, hour: 12)
        )!
    }
}

private extension Data {
    func replacingOccurrences(of target: String, with replacement: String) -> String {
        String(decoding: self, as: UTF8.self).replacingOccurrences(of: target, with: replacement)
    }
}

private actor QueryPrewarmGate {
    private(set) var startedSources = Set<InformationQueryLoadSource>()
    private var released = false
    private var continuations = [CheckedContinuation<Void, Never>]()

    func begin(_ source: InformationQueryLoadSource) async {
        startedSources.insert(source)
        guard !released else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private struct GatedShuttleClient: ShuttleBusFetching {
    let gate: QueryPrewarmGate

    func fetch() async throws -> ShuttleBusSnapshot {
        await gate.begin(.shuttle)
        return ShuttleBusSampleData.snapshot()
    }
}

private struct GatedDeadlineClient: PublicDeadlineFetching {
    let gate: QueryPrewarmGate

    func fetch(date: String) async throws -> PublicDeadlineSnapshot {
        PublicDeadlineSnapshot(
            date: date,
            items: [],
            source: CalendarDeadlineSources.primary,
            usedBackup: false
        )
    }

    func prewarm() async throws -> [String: PublicDeadlineSnapshot] {
        await gate.begin(.importantEvents)
        return [:]
    }
}
