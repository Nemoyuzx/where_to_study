import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class AssignmentQueryTests: XCTestCase {
    func testFilteringUsesCourseTitleStatusAndChronologicalDeadlines() {
        let items = [
            AssignmentDeadlineItem(id: "later", title: "report", courseName: "Physics", deadline: "2026-09-21 10:00", status: "未提交"),
            AssignmentDeadlineItem(id: "past", title: "homework", courseName: "Physics", deadline: "2026-09-18 12:00", status: "已提交"),
            AssignmentDeadlineItem(id: "today", title: "problem set", courseName: "Math", deadline: "2026-09-19 18:00", status: nil)
        ]
        XCTAssertEqual(AssignmentQueryLogic.filtered(items, query: "", showsEnded: false, today: "2026-09-19").map(\.id), ["today", "later"])
        XCTAssertEqual(AssignmentQueryLogic.filtered(items, query: "physics", showsEnded: true, today: "2026-09-19").map(\.id), ["past", "later"])
        XCTAssertEqual(AssignmentQueryLogic.filtered(items, query: "已提交", showsEnded: true, today: "2026-09-19").map(\.id), ["past"])
    }

    @MainActor
    func testQueryReusesCalendarCacheAndRetainsLastGoodDataOnRefreshFailure() async {
        let client = AssignmentQueryFixture()
        let store = CalendarDeadlineStore(assignmentClient: client)
        await store.loadAssignmentQuery(sampleMode: false)
        await store.loadAssignmentQuery(sampleMode: false)
        await store.loadAssignments(date: "2026-09-19", sampleMode: false)
        let first = await client.counts()
        XCTAssertEqual(first.all, 1)
        XCTAssertEqual(first.date, 0)
        XCTAssertEqual(store.assignmentQueryItems?.count, 1)
        XCTAssertEqual(store.assignmentsByDate["2026-09-19"]?.count, 1)
        await client.failNext()
        await store.loadAssignmentQuery(sampleMode: false, force: true)
        XCTAssertFalse(store.assignmentQueryError.isEmpty)
        XCTAssertEqual(store.assignmentQueryItems?.count, 1)
        store.clearAssignments()
        XCTAssertNil(store.assignmentQueryItems)
        await store.loadAssignmentQuery(sampleMode: true)
        let afterSample = await client.counts()
        XCTAssertEqual(afterSample.all, 2)
        XCTAssertEqual(store.assignmentQueryItems?.first?.id, "sample-assignment")
    }
}

private actor AssignmentQueryFixture: AssignmentDeadlineFetching {
    private var allCount = 0
    private var dateCount = 0
    private var fails = false
    func failNext() { fails = true }
    func counts() -> (all: Int, date: Int) { (allCount, dateCount) }
    func fetchAll(force: Bool) async throws -> [AssignmentDeadlineItem] {
        allCount += 1
        if fails { throw URLError(.timedOut) }
        return [.init(id: "synthetic", title: "Synthetic assignment", courseName: "Course", deadline: "2026-09-19 20:00", status: "未提交")]
    }
    func fetch(date: String) async throws -> [AssignmentDeadlineItem] { dateCount += 1; return [] }
    func reset() async {}
}
