import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class MobileMonthPageWindowTests: XCTestCase {
    func testAdjacentNavigationKeepsTheIncomingPageIdentityThroughRecenter() throws {
        var state = window(2026, 1, 15)
        let originalIDs = state.pages.map(\.id)
        let sourceSlot = try slot(for: date(2026, 1, 1), in: state)
        let targetSlot = try slot(for: date(2026, 2, 1), in: state)
        let departingSlot = try slot(for: date(2025, 12, 1), in: state)
        let next = try XCTUnwrap(state.request(direction: 1))

        XCTAssertEqual(state.centerMonth, date(2026, 1, 1))
        XCTAssertEqual(state.selectedDate, date(2026, 2, 15))
        XCTAssertEqual(state.pages.map(\.id), originalIDs)
        XCTAssertFalse(state.hasPendingNavigation)
        XCTAssertEqual(next.direction, 1)
        XCTAssertEqual(next.sourceMonth, date(2026, 1, 1))
        XCTAssertEqual(next.targetMonth, date(2026, 2, 1))
        XCTAssertTrue(state.settle(generation: next.generation))
        assertPages(state, [date(2026, 1, 1), date(2026, 2, 1), date(2026, 3, 1)])
        XCTAssertEqual(try slot(for: next.sourceMonth, in: state), sourceSlot)
        XCTAssertEqual(try slot(for: next.targetMonth, in: state), targetSlot)
        XCTAssertEqual(try slot(for: date(2026, 3, 1), in: state), departingSlot)
        XCTAssertEqual(state.centerSlot, targetSlot)
        XCTAssertNil(state.beginPendingNavigation())
        XCTAssertFalse(state.settle(generation: next.generation))
    }

    func testContinuousForwardRequestsAccumulateAndCoalesceWithoutChangingActivePages() throws {
        var state = window(2026, 1, 31)
        let first = try XCTUnwrap(state.request(direction: 1))
        let movingPages = state.pages
        XCTAssertNil(state.request(direction: 1))
        XCTAssertEqual(state.requestedDate, date(2026, 3, 31))
        XCTAssertNil(state.request(direction: 1))
        XCTAssertEqual(state.requestedDate, date(2026, 4, 30))
        XCTAssertEqual(state.selectedDate, date(2026, 2, 28))
        XCTAssertEqual(state.pages, movingPages)
        XCTAssertEqual(state.transition, first)
        XCTAssertTrue(state.hasPendingNavigation)

        XCTAssertTrue(state.settle(generation: first.generation))
        let coalesced = try XCTUnwrap(state.beginPendingNavigation())
        XCTAssertEqual(coalesced.sourceMonth, date(2026, 2, 1))
        XCTAssertEqual(coalesced.targetDate, date(2026, 4, 30))
        assertPages(state, [date(2026, 1, 1), date(2026, 2, 1), date(2026, 4, 1)])
        XCTAssertTrue(state.settle(generation: coalesced.generation))
        XCTAssertEqual(state.preferredDayOfMonth, 31)
        assertPages(state, [date(2026, 3, 1), date(2026, 4, 1), date(2026, 5, 1)])
    }

    func testContinuousBackwardRequestsCrossYearAndKeepMonthEndAnchor() throws {
        var state = window(2026, 3, 31)
        let first = try XCTUnwrap(state.request(direction: -1))
        XCTAssertNil(state.request(direction: -1))
        XCTAssertNil(state.request(direction: -1))
        XCTAssertEqual(state.requestedDate, date(2025, 12, 31))
        XCTAssertTrue(state.settle(generation: first.generation))
        let next = try XCTUnwrap(state.beginPendingNavigation())
        XCTAssertEqual(next.direction, -1)
        assertPages(state, [date(2025, 12, 1), date(2026, 2, 1), date(2026, 3, 1)])
        XCTAssertTrue(state.settle(generation: next.generation))
        assertPages(state, [date(2025, 11, 1), date(2025, 12, 1), date(2026, 1, 1)])
    }

    func testForwardThenBackwardQueuesReturnToOriginalDayWithoutRetargetingActivePage() throws {
        var state = window(2026, 1, 31)
        let originalSlot = state.centerSlot
        let outward = try XCTUnwrap(state.request(direction: 1))
        let outwardSlot = try slot(for: outward.targetMonth, in: state)
        let movingPages = state.pages
        XCTAssertNil(state.request(direction: -1))
        XCTAssertEqual(state.requestedDate, date(2026, 1, 31))
        XCTAssertEqual(state.pages, movingPages)
        XCTAssertTrue(state.settle(generation: outward.generation))
        XCTAssertEqual(state.centerSlot, outwardSlot)
        let returning = try XCTUnwrap(state.beginPendingNavigation())
        XCTAssertEqual(returning.direction, -1)
        XCTAssertEqual(try slot(for: returning.targetMonth, in: state), originalSlot)
        XCTAssertTrue(state.settle(generation: returning.generation))
        XCTAssertEqual(state.centerSlot, originalSlot)
        XCTAssertEqual(state.selectedDate, date(2026, 1, 31))
        XCTAssertEqual(state.centerMonth, date(2026, 1, 1))
        XCTAssertNil(state.beginPendingNavigation())
    }

    func testOppositeQueuedRequestsCancelTheirNetMovement() throws {
        var state = window(2026, 1, 31)
        let first = try XCTUnwrap(state.request(direction: 1))
        XCTAssertNil(state.request(direction: 1))
        XCTAssertNil(state.request(direction: -1))
        XCTAssertEqual(state.requestedDate, first.targetDate)
        XCTAssertFalse(state.hasPendingNavigation)
        XCTAssertTrue(state.settle(generation: first.generation))
        XCTAssertNil(state.beginPendingNavigation())
        XCTAssertEqual(state.selectedDate, date(2026, 2, 28))
    }

    func testDistantAbsoluteNavigationUsesOnlyTheIncomingSlotAndResetsTheAnchor() throws {
        var state = window(2026, 1, 31)
        let far = try XCTUnwrap(state.request(to: date(2027, 8, 12)))
        XCTAssertEqual(state.selectedDate, date(2027, 8, 12))
        XCTAssertEqual(state.centerMonth, date(2026, 1, 1))
        assertPages(state, [date(2025, 12, 1), date(2026, 1, 1), date(2027, 8, 1)])
        XCTAssertTrue(state.settle(generation: far.generation))
        assertPages(state, [date(2027, 7, 1), date(2027, 8, 1), date(2027, 9, 1)])
        let next = try XCTUnwrap(state.request(direction: 1))
        XCTAssertEqual(next.targetDate, date(2027, 9, 12))
    }

    func testAbsoluteABAReturnPreservesActivePagesAndRejectsStaleCompletion() throws {
        let original = date(2026, 1, 31)
        var state = window(2026, 1, 31)
        let outward = try XCTUnwrap(state.request(to: date(2027, 8, 12)))
        let movingPages = state.pages
        XCTAssertNil(state.request(to: original))
        XCTAssertEqual(state.pages, movingPages)
        XCTAssertTrue(state.settle(generation: outward.generation))
        let returning = try XCTUnwrap(state.beginPendingNavigation())
        let beforeStaleCompletion = state
        XCTAssertFalse(state.settle(generation: outward.generation))
        XCTAssertEqual(state, beforeStaleCompletion)
        assertPages(state, [date(2026, 1, 1), date(2027, 8, 1), date(2027, 9, 1)])
        XCTAssertTrue(state.settle(generation: returning.generation))
        XCTAssertEqual(state.selectedDate, original)
    }

    func testMonthEndAnchorSurvivesLeapFebruaryAndPreservesTimeOfDay() throws {
        let january = date(2028, 1, 31, hour: 17, minute: 42)
        var state = MobileMonthPageWindow(selectedDate: january, calendar: calendar)
        let february = try XCTUnwrap(state.request(direction: 1))
        XCTAssertEqual(february.targetDate, date(2028, 2, 29, hour: 17, minute: 42))
        XCTAssertTrue(state.settle(generation: february.generation))
        let march = try XCTUnwrap(state.request(direction: 1))
        XCTAssertEqual(march.targetDate, date(2028, 3, 31, hour: 17, minute: 42))
        XCTAssertEqual(state.preferredDayOfMonth, 31)
    }

    func testSameMonthDaySelectionDoesNotAnimateAndSetsTheNextPageAnchor() throws {
        var state = window(2026, 1, 31)
        let originalPages = state.pages
        XCTAssertNil(state.request(to: date(2026, 1, 12)))
        XCTAssertEqual(state.selectedDate, date(2026, 1, 12))
        XCTAssertEqual(state.pages, originalPages)
        XCTAssertEqual(state.preferredDayOfMonth, 12)
        XCTAssertEqual(try XCTUnwrap(state.request(direction: 1)).targetDate, date(2026, 2, 12))
    }

    func testReducedMotionImmediatelyAppliesLatestRequestAndInvalidatesOldCompletion() throws {
        var state = window(2026, 1, 31)
        let old = try XCTUnwrap(state.request(direction: 1))
        XCTAssertNil(state.request(direction: 1))
        XCTAssertNil(state.beginPendingNavigation(animated: false))
        XCTAssertEqual(state.selectedDate, date(2026, 3, 31))
        XCTAssertEqual(state.centerMonth, date(2026, 3, 1))
        XCTAssertNil(state.transition)
        XCTAssertFalse(state.hasPendingNavigation)
        XCTAssertFalse(state.settle(generation: old.generation))
        XCTAssertEqual(state.preferredDayOfMonth, 31)
        assertPages(state, [date(2026, 2, 1), date(2026, 3, 1), date(2026, 4, 1)])
    }

    func testModeRebaseDiscardsQueuedTargetsAndStaleCompletion() throws {
        var state = window(2026, 1, 31)
        let old = try XCTUnwrap(state.request(direction: 1))
        XCTAssertNil(state.request(direction: 1))
        state.rebase(to: date(2026, 10, 9))
        XCTAssertFalse(state.settle(generation: old.generation))
        XCTAssertEqual(state.requestedDate, date(2026, 10, 9))
        XCTAssertEqual(state.preferredDayOfMonth, 9)
        XCTAssertNil(state.beginPendingNavigation())
        assertPages(state, [date(2026, 9, 1), date(2026, 10, 1), date(2026, 11, 1)])
    }

    func testRebaseCanPreserveClampedDayAnchorWhenCancellingMotion() throws {
        var state = window(2026, 1, 31)
        let old = try XCTUnwrap(state.request(direction: 1))
        state.rebase(to: old.targetDate, preservingMonthDayAnchor: true)
        XCTAssertFalse(state.settle(generation: old.generation))
        XCTAssertEqual(try XCTUnwrap(state.request(direction: 1)).targetDate, date(2026, 3, 31))
    }

    func testEveryWindowStaysBoundedDuringMixedAndDistantRequests() throws {
        var state = window(2026, 1, 31)
        for index in 0 ..< 120 {
            if index % 5 == 0 {
                _ = state.request(to: date(2025 + index % 4, 1 + index % 12, 15))
            } else {
                _ = state.request(direction: index % 3 == 0 ? -1 : 1)
            }
            assertBounded(state)
            if index % 3 == 2, let transition = state.transition {
                let incomingSlot = try slot(for: transition.targetMonth, in: state)
                XCTAssertTrue(state.settle(generation: transition.generation))
                XCTAssertEqual(try slot(for: transition.targetMonth, in: state), incomingSlot)
                assertBounded(state)
                _ = state.beginPendingNavigation()
                assertBounded(state)
            }
        }
        state.rebase(to: state.requestedDate, preservingMonthDayAnchor: true)
        assertBounded(state)
        XCTAssertNil(state.transition)
    }

    func testBackwardSlotWrappingAcrossYearNeverProducesNegativeIDs() throws {
        var state = window(2026, 1, 31)
        XCTAssertEqual(state.centerSlot, 1)
        XCTAssertEqual(state.pages.map(\.id), [0, 1, 2])
        for expectedCenterSlot in [0, 2, 1, 0] {
            let sourceMonth = state.centerMonth
            let sourceSlot = state.centerSlot
            let transition = try XCTUnwrap(state.request(direction: -1))
            let incomingSlot = try slot(for: transition.targetMonth, in: state)
            assertBounded(state)
            XCTAssertTrue(state.settle(generation: transition.generation))
            XCTAssertEqual(state.centerSlot, expectedCenterSlot)
            XCTAssertEqual(try slot(for: transition.targetMonth, in: state), incomingSlot)
            XCTAssertEqual(try slot(for: sourceMonth, in: state), sourceSlot)
            assertBounded(state)
        }
        XCTAssertEqual(state.centerMonth, date(2025, 9, 1))
        XCTAssertEqual(state.preferredDayOfMonth, 31)
    }

    func testFarJumpsUseIncomingSlotEvenWhenMonthNumbersWouldCollideModuloThree() throws {
        for target in [date(2026, 4, 12), date(2025, 10, 12), date(2032, 1, 12)] {
            var state = window(2026, 1, 31)
            let direction = target < state.centerMonth ? -1 : 1
            let incomingSlot = try XCTUnwrap(state.pages.first { $0.offset == direction }).slot
            let transition = try XCTUnwrap(state.request(to: target))
            XCTAssertEqual(try slot(for: transition.targetMonth, in: state), incomingSlot)
            assertBounded(state)
            XCTAssertTrue(state.settle(generation: transition.generation))
            XCTAssertEqual(state.centerSlot, incomingSlot)
            XCTAssertEqual(try slot(for: transition.targetMonth, in: state), incomingSlot)
            XCTAssertEqual(state.selectedDate, target)
            XCTAssertEqual(state.preferredDayOfMonth, 12)
            assertBounded(state)
        }
    }

    func testAlternatingDirectionsKeepIncomingSlotsAndRebaseRetainsCenterSlot() throws {
        var state = window(2026, 1, 31)
        for direction in [1, -1, -1, 1, 1, 1, -1, -1, -1, 1] {
            let transition = try XCTUnwrap(state.request(direction: direction))
            let incomingSlot = try slot(for: transition.targetMonth, in: state)
            assertBounded(state)
            XCTAssertTrue(state.settle(generation: transition.generation))
            XCTAssertEqual(state.centerSlot, incomingSlot)
            assertBounded(state)
        }
        let retainedSlot = state.centerSlot
        let cancelled = try XCTUnwrap(state.request(direction: 1))
        state.rebase(to: date(2030, 12, 9))
        XCTAssertEqual(state.centerSlot, retainedSlot)
        XCTAssertFalse(state.settle(generation: cancelled.generation))
        XCTAssertEqual(state.centerSlot, retainedSlot)
        assertBounded(state)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func window(_ year: Int, _ month: Int, _ day: Int) -> MobileMonthPageWindow {
        MobileMonthPageWindow(selectedDate: date(year, month, day), calendar: calendar)
    }

    private func slot(for month: Date, in state: MobileMonthPageWindow) throws -> Int {
        try XCTUnwrap(state.pages.first { $0.monthStart == month }).slot
    }

    private func assertPages(
        _ state: MobileMonthPageWindow,
        _ expected: [Date],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(state.pages.map(\.monthStart), expected, file: file, line: line)
        assertBounded(state, file: file, line: line)
    }

    private func assertBounded(
        _ state: MobileMonthPageWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(state.pages.count, 3, file: file, line: line)
        XCTAssertEqual(Set(state.pages.map(\.id)), Set([0, 1, 2]), file: file, line: line)
        XCTAssertEqual(Set(state.pages.map(\.monthStart)).count, 3, file: file, line: line)
        XCTAssertEqual(state.pages.map(\.offset), [-1, 0, 1], file: file, line: line)
        XCTAssertEqual(state.pages[1].monthStart, state.centerMonth, file: file, line: line)
        XCTAssertEqual(state.pages[1].slot, state.centerSlot, file: file, line: line)
    }
}
