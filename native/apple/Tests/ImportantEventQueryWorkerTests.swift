import XCTest
import Combine
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class ImportantEventQueryWorkerTests: XCTestCase {
    func testWorkerPreservesFiltersFavoritesAndReusesIndex() async throws {
        let now = Date(timeIntervalSince1970: 1_788_537_600)
        let items = fixtures
        let snapshot = PublicDeadlineSnapshot(
            date: "2026-09-05", items: items,
            source: CalendarDeadlineSources.primary, usedBackup: false
        )
        let snapshots = [snapshot.date: snapshot]
        let worker = ImportantEventQueryWorker()
        let favorites = [items[0], PublicDeadlineItem(
            id: "favorite", name: "已收藏校内通知", kind: .competition, source: .schoolNotice,
            deadline: "2030-09-05T12:00:00+08:00", organizer: nil, officialURL: nil
        )]
        let merged = ImportantEventQueryLogic.mergedItems(liveItems: items, favoriteItems: favorites)
        for category in ImportantEventCategory.allCases {
            for showsEnded in [false, true] {
                for query in ["", "  AI  ", "学校", "找不到"] {
                    let result = try await worker.query(
                        snapshots: snapshots, publicRevision: 1, favorites: favorites,
                        query: query, category: category, metadataCategory: "",
                        showsEnded: showsEnded, now: now
                    )
                    let effectiveCategory = ImportantEventQueryLogic.normalizedCategory(
                        category,
                        availableCategories: ImportantEventQueryLogic.availableCategories(in: merged)
                    )
                    XCTAssertEqual(result.items, ImportantEventQueryLogic.filteredItems(
                        merged, query: query, category: effectiveCategory, showsEnded: showsEnded, now: now
                    ))
                    XCTAssertEqual(result.metadataCategories, ImportantEventQueryLogic.metadataCategories(
                        in: merged, category: effectiveCategory, showsEnded: showsEnded, now: now
                    ))
                }
            }
        }
        let buildCount = await worker.indexBuildCount
        XCTAssertEqual(buildCount, 1, "Changing filters must not reparse the entire feed")
        _ = try await worker.query(
            snapshots: snapshots, publicRevision: 1, favorites: [], query: "", category: .all,
            metadataCategory: "不存在", showsEnded: true, now: now
        )
        let favoriteBuildCount = await worker.indexBuildCount
        XCTAssertEqual(favoriteBuildCount, 2)
        let emptyResult = try await worker.query(
            snapshots: [:], publicRevision: 2, favorites: [], query: "", category: .conference,
            metadataCategory: "AI", showsEnded: true, now: now
        )
        XCTAssertEqual(emptyResult.items, [])
        XCTAssertEqual(emptyResult.category, .all)
        XCTAssertEqual(emptyResult.metadataCategory, "")
    }

    @MainActor
    func testPrimaryNavigationDoesNotPublishThroughGlobalModel() {
        let model = AppModel(runtimeMode: .sample(review: false))
        var globalChanges = 0
        let observation = model.objectWillChange.sink { globalChanges += 1 }
        model.navigation.selectedSection = .calendar
        model.navigation.selectedSection = .queries
        model.navigation.selectedSection = .planner
        XCTAssertEqual(globalChanges, 0)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testRootRetainsSeparateLiveAndSampleServicesOnBothApplePlatforms() {
        let services = CalendarDataServices()
        XCTAssertTrue(services.services(sampleMode: false) === services.services(sampleMode: false))
        XCTAssertFalse(services.services(sampleMode: false).dailyInfo === services.services(sampleMode: true).dailyInfo)
        XCTAssertFalse(services.services(sampleMode: false).deadlines === services.services(sampleMode: true).deadlines)
        XCTAssertFalse(services.services(sampleMode: false).shuttle === services.services(sampleMode: true).shuttle)
        XCTAssertFalse(services.services(sampleMode: false).importantEvents === services.services(sampleMode: true).importantEvents)
    }

    func testLargeFeedWarmSearchAvoidsRepeatedDateParsing() async throws {
        let items = (0..<1000).map { index in
            PublicDeadlineItem(
                id: "event-\(index)", name: "AI 竞赛 \(index)", kind: .competition, source: .contestDDL,
                deadline: "2030-09-05T12:00:00+08:00", organizer: "学校", officialURL: nil,
                categories: ["AI"], tags: ["性能回归"]
            )
        }
        let snapshots = ["2030-09-05": PublicDeadlineSnapshot(
            date: "2030-09-05", items: items, source: CalendarDeadlineSources.primary, usedBackup: false
        )]
        let worker = ImportantEventQueryWorker()
        let clock = ContinuousClock()
        let coldStart = clock.now
        _ = try await worker.query(
            snapshots: snapshots, publicRevision: 1, favorites: [], query: "", category: .all,
            metadataCategory: "", showsEnded: false, now: .now
        )
        let cold = coldStart.duration(to: clock.now)
        let warmStart = clock.now
        for _ in 0..<10 {
            let result = try await worker.query(
                snapshots: snapshots, publicRevision: 1, favorites: [], query: "AI", category: .all,
                metadataCategory: "AI", showsEnded: false, now: .now
            )
            XCTAssertEqual(result.items.count, 1000)
        }
        let warm = warmStart.duration(to: clock.now)
        let count = await worker.indexBuildCount
        XCTAssertEqual(count, 1)
        print("EVENT_QUERY_BENCHMARK count=1000 cold=\(cold) warm10=\(warm)")
    }

    private var fixtures: [PublicDeadlineItem] {
        [
            PublicDeadlineItem(id: "active", name: "AI 竞赛", kind: .competition, source: .contestDDL,
                               deadline: "2030-09-05T12:00:00.000+08:00", organizer: "学校", officialURL: nil,
                               categories: ["AI"], tags: ["算法"]),
            PublicDeadlineItem(id: "past", name: "过去活动", kind: .summerCamp, source: .contestDDL,
                               deadline: "2020-09-05T12:00:00+08:00", organizer: nil, officialURL: nil),
            PublicDeadlineItem(id: "archived", name: "已归档", kind: .conference, source: .contestDDL,
                               deadline: "2030-09-05T12:00:00+08:00", organizer: nil, officialURL: nil, archived: true),
            PublicDeadlineItem(id: "invalid", name: "坏日期", kind: .hackathon, source: .contestDDL,
                               deadline: "invalid", organizer: nil, officialURL: nil),
            PublicDeadlineItem(id: "custom", name: "自定义不应出现", kind: .custom, source: .custom,
                               deadline: "2030-09-05T12:00:00+08:00", organizer: nil, officialURL: nil)
        ]
    }
}
