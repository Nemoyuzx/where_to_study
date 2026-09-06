import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class MobileYearPageWindowTests: XCTestCase {
    func testAdjacentNavigationPreservesSourceAndIncomingSlotsInBothDirections() throws {
        for direction in [-1, 1] {
            var state = window(2026, 9, 7)
            let sourceSlot = try slot(for: date(2026, 1, 1), in: state)
            let incomingSlot = try slot(for: date(2026 + direction, 1, 1), in: state)
            let originalIDs = state.pages.map(\.id)
            let transition = try XCTUnwrap(state.request(direction: direction))

            XCTAssertEqual(transition.sourceYear, date(2026, 1, 1))
            XCTAssertEqual(transition.targetYear, date(2026 + direction, 1, 1))
            XCTAssertEqual(transition.targetDate, date(2026 + direction, 9, 7))
            XCTAssertEqual(transition.direction, direction)
            XCTAssertEqual(state.centerYear, transition.sourceYear)
            XCTAssertEqual(state.selectedDate, transition.targetDate)
            XCTAssertEqual(state.pages.map(\.id), originalIDs)
            XCTAssertFalse(state.hasPendingNavigation)
            assertBounded(state)

            XCTAssertTrue(state.settle(generation: transition.generation))
            XCTAssertEqual(try slot(for: transition.sourceYear, in: state), sourceSlot)
            XCTAssertEqual(try slot(for: transition.targetYear, in: state), incomingSlot)
            XCTAssertEqual(try centerSlot(in: state), incomingSlot)
            assertPages(state, [2025 + direction, 2026 + direction, 2027 + direction])
            XCTAssertNil(state.beginPendingNavigation())
            XCTAssertFalse(state.settle(generation: transition.generation))
        }
    }

    func testFarJumpsUseIncomingSlotEvenWhenYearNumbersCollideModuloThree() throws {
        for target in [date(2023, 8, 12), date(2029, 8, 12), date(2032, 1, 31)] {
            var state = window(2026, 2, 28)
            let direction = target < state.centerYear ? -1 : 1
            let incomingSlot = try XCTUnwrap(state.pages.first { $0.offset == direction }).slot
            let transition = try XCTUnwrap(state.request(to: target))
            let targetYear = calendar.component(.year, from: target)

            XCTAssertEqual(state.centerYear, date(2026, 1, 1))
            XCTAssertEqual(state.selectedDate, target)
            XCTAssertEqual(try slot(for: transition.targetYear, in: state), incomingSlot)
            XCTAssertEqual(state.pages.first { $0.offset == 0 }?.yearStart, transition.sourceYear)
            assertBounded(state)
            XCTAssertTrue(state.settle(generation: transition.generation))
            XCTAssertEqual(try centerSlot(in: state), incomingSlot)
            assertPages(state, [targetYear - 1, targetYear, targetYear + 1])

            let next = try XCTUnwrap(state.request(direction: 1))
            XCTAssertEqual(calendar.component(.month, from: next.targetDate), calendar.component(.month, from: target))
            XCTAssertEqual(calendar.component(.day, from: next.targetDate), calendar.component(.day, from: target))
        }
    }

    func testRapidReversedRequestsCoalesceWithoutRetargetingAnActivePage() throws {
        var state = window(2026, 12, 31)
        let outward = try XCTUnwrap(state.request(direction: 1))
        let movingPages = state.pages
        for direction in [1, -1, -1, -1] {
            XCTAssertNil(state.request(direction: direction))
            XCTAssertEqual(state.transition, outward)
            XCTAssertEqual(state.pages, movingPages)
            assertBounded(state)
        }
        XCTAssertEqual(state.requestedDate, date(2025, 12, 31))
        XCTAssertEqual(state.selectedDate, date(2027, 12, 31))
        XCTAssertTrue(state.hasPendingNavigation)
        XCTAssertTrue(state.settle(generation: outward.generation))
        let returning = try XCTUnwrap(state.beginPendingNavigation())
        XCTAssertEqual(returning.sourceYear, date(2027, 1, 1))
        XCTAssertEqual(returning.targetDate, date(2025, 12, 31))
        XCTAssertEqual(returning.direction, -1)
        assertPages(state, [2025, 2027, 2028])
        XCTAssertTrue(state.settle(generation: returning.generation))
        assertPages(state, [2024, 2025, 2026])
        XCTAssertNil(state.beginPendingNavigation())
    }

    func testOppositeQueuedRequestsCancelTheirNetMovement() throws {
        var state = window(2026, 6, 30)
        let first = try XCTUnwrap(state.request(direction: 1))
        XCTAssertNil(state.request(direction: 1))
        XCTAssertNil(state.request(direction: -1))
        XCTAssertEqual(state.requestedDate, first.targetDate)
        XCTAssertFalse(state.hasPendingNavigation)
        XCTAssertTrue(state.settle(generation: first.generation))
        XCTAssertNil(state.beginPendingNavigation())
        XCTAssertEqual(state.selectedDate, date(2027, 6, 30))
    }

    func testAbsoluteABAReturnPreservesMovingPagesAndRejectsStaleCompletion() throws {
        let original = date(2026, 11, 30)
        var state = MobileYearPageWindow(selectedDate: original, calendar: calendar)
        let outward = try XCTUnwrap(state.request(to: date(2034, 8, 12)))
        let movingPages = state.pages
        XCTAssertNil(state.request(to: original))
        XCTAssertEqual(state.pages, movingPages)
        XCTAssertEqual(state.selectedDate, outward.targetDate)
        XCTAssertTrue(state.settle(generation: outward.generation))
        let returning = try XCTUnwrap(state.beginPendingNavigation())
        let current = state
        XCTAssertFalse(state.settle(generation: outward.generation))
        XCTAssertEqual(state, current)
        XCTAssertEqual(returning.targetDate, original)
        XCTAssertEqual(returning.direction, -1)
        XCTAssertTrue(state.settle(generation: returning.generation))
        XCTAssertEqual(state.selectedDate, original)
        assertPages(state, [2025, 2026, 2027])
    }

    func testReducedMotionCentersLatestRequestAndRetainsTheLeapDayAnchor() throws {
        var state = window(2028, 2, 29)
        let old = try XCTUnwrap(state.request(direction: 1))
        XCTAssertNil(state.request(direction: 1))
        XCTAssertNil(state.beginPendingNavigation(animated: false))
        XCTAssertEqual(state.selectedDate, date(2030, 2, 28))
        XCTAssertEqual(state.requestedDate, state.selectedDate)
        XCTAssertNil(state.transition)
        XCTAssertFalse(state.hasPendingNavigation)
        XCTAssertFalse(state.settle(generation: old.generation))
        assertPages(state, [2029, 2030, 2031])

        XCTAssertNil(state.request(direction: 1, animated: false))
        XCTAssertEqual(state.selectedDate, date(2031, 2, 28))
        XCTAssertNil(state.request(direction: 1, animated: false))
        XCTAssertEqual(state.selectedDate, date(2032, 2, 29))
        XCTAssertNil(state.request(to: date(2024, 12, 31), animated: false))
        XCTAssertEqual(state.selectedDate, date(2024, 12, 31))
        assertPages(state, [2023, 2024, 2025])
    }

    func testRebaseCancelsOldCompletionsAndResetsAnExplicitDayAnchor() throws {
        var state = window(2028, 2, 29)
        let old = try XCTUnwrap(state.request(direction: 1))
        XCTAssertNil(state.request(direction: 1))
        let retainedSlot = try centerSlot(in: state)
        state.rebase(to: date(2029, 2, 28))
        XCTAssertEqual(try centerSlot(in: state), retainedSlot)
        XCTAssertFalse(state.settle(generation: old.generation))
        XCTAssertNil(state.transition)
        XCTAssertFalse(state.hasPendingNavigation)
        XCTAssertEqual(state.selectionDate(in: date(2032, 1, 1)), date(2032, 2, 28))
        let next = try XCTUnwrap(state.request(direction: -1))
        XCTAssertEqual(next.targetDate, date(2028, 2, 28))
    }

    func testCancellingMotionCanPreserveTheOriginalLeapDayAnchor() throws {
        var state = window(2028, 2, 29)
        let old = try XCTUnwrap(state.request(direction: 1))
        state.rebase(to: old.targetDate, preservingYearDayAnchor: true)
        XCTAssertFalse(state.settle(generation: old.generation))
        XCTAssertEqual(state.selectionDate(in: date(2032, 1, 1)), date(2032, 2, 29))
        let returning = try XCTUnwrap(state.request(direction: -1))
        XCTAssertEqual(returning.targetDate, date(2028, 2, 29))
    }

    func testLeapDayAnchorAndTimeOfDaySurviveFourForwardAndBackwardYears() throws {
        for direction in [-1, 1] {
            let original = date(2028, 2, 29, hour: 17, minute: 42)
            var state = MobileYearPageWindow(selectedDate: original, calendar: calendar)
            for offset in 1...4 {
                let transition = try XCTUnwrap(state.request(direction: direction))
                let year = 2028 + offset * direction
                XCTAssertEqual(transition.targetDate, date(year, 2, offset == 4 ? 29 : 28, hour: 17, minute: 42))
                XCTAssertTrue(state.settle(generation: transition.generation))
                assertBounded(state)
            }
        }
    }

    func testSameYearDaySelectionKeepsMountedPagesAndChangesTheFollowingAnchor() throws {
        var state = window(2028, 2, 29)
        let pages = state.pages
        let newDate = date(2028, 3, 31, hour: 9, minute: 15)
        XCTAssertNil(state.request(to: newDate))
        XCTAssertEqual(state.selectedDate, newDate)
        XCTAssertEqual(state.requestedDate, newDate)
        XCTAssertEqual(state.pages, pages)
        XCTAssertFalse(state.hasPendingNavigation)
        let next = try XCTUnwrap(state.request(direction: 1))
        XCTAssertEqual(next.targetDate, date(2029, 3, 31, hour: 9, minute: 15))
    }

    func testYearStartAndEndMonthDayAnchorsRemainInTheRequestedYear() throws {
        for (month, day) in [(1, 1), (1, 31), (4, 30), (12, 31)] {
            var state = window(2026, month, day)
            XCTAssertEqual(state.selectionDate(in: date(2025, 1, 1)), date(2025, month, day))
            XCTAssertEqual(state.selectionDate(in: date(2027, 1, 1)), date(2027, month, day))
            let next = try XCTUnwrap(state.request(direction: 1))
            XCTAssertEqual(next.targetDate, date(2027, month, day))
            XCTAssertTrue(state.settle(generation: next.generation))
            let previous = try XCTUnwrap(state.request(direction: -1))
            XCTAssertEqual(previous.targetDate, date(2026, month, day))
        }
    }

    func testZeroDirectionIsANoopAndExtremeDirectionsNormalizeToOneYear() throws {
        var state = window(2026, 12, 31)
        let original = state
        XCTAssertNil(state.request(direction: 0))
        XCTAssertEqual(state, original)
        let forward = try XCTUnwrap(state.request(direction: .max))
        XCTAssertEqual(forward.targetDate, date(2027, 12, 31))
        XCTAssertTrue(state.settle(generation: forward.generation))
        let backward = try XCTUnwrap(state.request(direction: .min))
        XCTAssertEqual(backward.targetDate, date(2026, 12, 31))
    }

    func testMixedNavigationKeepsThreeUniqueSlotsAndStableIncomingIdentity() throws {
        var state = window(2026, 9, 7)
        for index in 0..<90 {
            if index % 5 == 0 {
                _ = state.request(to: date(2020 + index % 14, 1 + index % 12, 15))
            } else {
                _ = state.request(direction: index % 3 == 0 ? -1 : 1)
            }
            assertBounded(state)
            if index % 3 == 2, let transition = state.transition {
                let incomingSlot = try slot(for: transition.targetYear, in: state)
                XCTAssertTrue(state.settle(generation: transition.generation))
                XCTAssertEqual(try centerSlot(in: state), incomingSlot)
                assertBounded(state)
                _ = state.beginPendingNavigation()
                assertBounded(state)
            }
        }
        state.rebase(to: state.requestedDate, preservingYearDayAnchor: true)
        assertBounded(state)
        XCTAssertNil(state.transition)
    }

    private var calendar: Calendar { .shanghai }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func window(_ year: Int, _ month: Int, _ day: Int) -> MobileYearPageWindow {
        MobileYearPageWindow(selectedDate: date(year, month, day), calendar: calendar)
    }

    private func slot(for year: Date, in state: MobileYearPageWindow) throws -> Int {
        try XCTUnwrap(state.pages.first { $0.yearStart == year }).slot
    }

    private func centerSlot(in state: MobileYearPageWindow) throws -> Int {
        try XCTUnwrap(state.pages.first { $0.offset == 0 }).slot
    }

    private func assertPages(
        _ state: MobileYearPageWindow, _ years: [Int], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(state.pages.map(\.yearStart), years.map { date($0, 1, 1) }, file: file, line: line)
        assertBounded(state, file: file, line: line)
    }

    private func assertBounded(
        _ state: MobileYearPageWindow, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(state.pages.count, 3, file: file, line: line)
        XCTAssertEqual(Set(state.pages.map(\.id)), Set([0, 1, 2]), file: file, line: line)
        XCTAssertEqual(Set(state.pages.map(\.yearStart)).count, 3, file: file, line: line)
        XCTAssertEqual(state.pages.map(\.offset), [-1, 0, 1], file: file, line: line)
        XCTAssertEqual(state.pages.first { $0.offset == 0 }?.yearStart, state.centerYear, file: file, line: line)
    }
}
