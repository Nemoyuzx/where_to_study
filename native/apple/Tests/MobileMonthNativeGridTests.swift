#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import WhereToStudyiOS

@MainActor
final class MobileMonthNativeGridTests: XCTestCase {
    func testAnimationReusesFortyTwoCellsAndTheirEventLabels() {
        let days = snapshots()
        let view = MobileMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        var grid = configuration(days: days)
        view.update(grid)
        let cells = view.cells.map(ObjectIdentifier.init)
        let labels = view.cells.map { $0.eventLabels.map(ObjectIdentifier.init) }
        grid.expansionProgress = 0.6
        grid.cellHeight = 53
        view.update(grid)

        XCTAssertEqual(view.cells.count, 42)
        XCTAssertEqual(view.cells.map(ObjectIdentifier.init), cells)
        XCTAssertEqual(view.cells.map { $0.eventLabels.map(ObjectIdentifier.init) }, labels)
        for (index, cell) in view.cells.enumerated() {
            XCTAssertEqual(cell.frame.width, (350 - 24) / 7, accuracy: 0.001)
            XCTAssertEqual(cell.frame.height, 53)
            XCTAssertEqual(cell.frame.minY, CGFloat(index / 7) * 57)
            XCTAssertEqual(cell.summary.accessibilityFrameInContainerSpace, cell.bounds)
        }
    }

    func testInactivePageHasNoActiveIdentifiersOrAccessibleChildren() {
        let days = snapshots()
        let view = MobileMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        view.update(configuration(days: days))
        let fonts = view.cells.map { $0.numberButton.titleLabel!.font! }
        view.update(configuration(days: days, active: false))

        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertEqual(view.accessibilityElements?.count, 0)
        for (index, cell) in view.cells.enumerated() {
            XCTAssertTrue(cell.numberButton.titleLabel!.font === fonts[index])
            XCTAssertTrue(cell.summary.accessibilityIdentifier!.hasPrefix("preloaded."))
            XCTAssertTrue(cell.numberButton.accessibilityIdentifier!.hasPrefix("preloaded."))
            XCTAssertTrue(cell.eventLabels.allSatisfy { $0.accessibilityIdentifier!.hasPrefix("preloaded.") })
            XCTAssertFalse(cell.numberButton.isAccessibilityElement)
            XCTAssertFalse(cell.isUserInteractionEnabled)
        }
    }

    func testSummaryNumberAndEventMetadataCoexistAndWholeCellSelectsDay() {
        let days = snapshots()
        let view = MobileMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        var selectedDate: Date?
        view.update(configuration(days: days, onSelect: { selectedDate = $0 }))
        let cell = view.cells[0]
        XCTAssertEqual(cell.summary.accessibilityIdentifier, "calendar.mobile.month-day-cell.2026-09-01")
        XCTAssertEqual(cell.summary.accessibilityLabel, "September 1, two deadlines")
        XCTAssertEqual(cell.summary.accessibilityValue, "assignment,conference")
        XCTAssertTrue(cell.summary.accessibilityTraits.contains(.selected))
        XCTAssertEqual(cell.numberButton.accessibilityIdentifier, "calendar.mobile.month-day-number.2026-09-01")
        XCTAssertEqual(cell.eventLabels[0].accessibilityIdentifier, "calendar.mobile.month-event.0-first")
        XCTAssertEqual(cell.eventLabels[0].text, "Deadline one")
        XCTAssertTrue(cell.hitTest(CGPoint(x: cell.bounds.midX, y: cell.bounds.height - 2), with: nil) === cell)
        cell.sendActions(for: .touchUpInside)
        XCTAssertEqual(selectedDate, days[0].date)
        XCTAssertTrue(cell.summary.accessibilityActivate())
    }

    func testReusedHiddenEventLabelClearsItsOldContentAndIdentifier() {
        var days = snapshots()
        let view = MobileMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        view.update(configuration(days: days))
        let pooledLabel = view.cells[0].eventLabels[1]
        let original = days[0]
        days[0] = MobileMonthDaySnapshot(
            date: original.date, dateKey: original.dateKey, dayNumberText: original.dayNumberText,
            accessibilityLabel: original.accessibilityLabel, courses: original.courses, holiday: original.holiday,
            events: [original.events[0]], allDayEvents: original.allDayEvents, deadlineKinds: original.deadlineKinds
        )
        view.update(configuration(days: days))
        XCTAssertTrue(view.cells[0].eventLabels[1] === pooledLabel)
        XCTAssertTrue(pooledLabel.isHidden)
        XCTAssertNil(pooledLabel.text)
        XCTAssertNil(pooledLabel.accessibilityLabel)
        XCTAssertNil(pooledLabel.accessibilityIdentifier)
        XCTAssertFalse(pooledLabel.isAccessibilityElement)
    }

    func testDismantleReleasesTheGridAndCellCallbacks() {
        final class CallbackOwner { var selectedDate: Date? }
        let view = MobileMonthGridUIView()
        weak var retainedOwner: CallbackOwner?
        do {
            let owner = CallbackOwner()
            retainedOwner = owner
            view.update(configuration(days: snapshots(), onSelect: { [owner] in owner.selectedDate = $0 }))
        }
        XCTAssertNotNil(retainedOwner)
        view.dismantle()
        XCTAssertNil(retainedOwner)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertEqual(view.accessibilityElements?.count, 0)
    }

    func testZeroSizedGridDefersPathsAndRecoversUsingTheSameCells() {
        let view = MobileMonthGridUIView()
        let cells = view.cells.map(ObjectIdentifier.init)
        view.update(configuration(days: snapshots()))
        for size in [CGSize.zero, CGSize(width: 24, height: 500), CGSize(width: 350, height: 0)] {
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutSubviews()
            XCTAssertTrue(view.cells.allSatisfy { $0.bounds == .zero })
            XCTAssertTrue(view.cells.allSatisfy { cell in
                cell.layer.sublayers!.compactMap { $0 as? CAShapeLayer }.allSatisfy { $0.path == nil }
            })
        }

        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(view.cells.map(ObjectIdentifier.init), cells)
        XCTAssertEqual(view.cells[0].frame.width, (350 - 24) / 7, accuracy: 0.001)
        XCTAssertEqual(view.cells[0].numberButton.title(for: .normal), "1")
        XCTAssertTrue(view.cells[0].layer.sublayers!.compactMap { $0 as? CAShapeLayer }.allSatisfy { $0.path != nil })
    }

    func testSmallAndEmptyCellsClearInnerPathThenRestoreItAtValidSize() {
        let view = MobileMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        view.update(configuration(days: snapshots()))
        let cell = view.cells[0]
        let borders = cell.layer.sublayers!.compactMap { $0 as? CAShapeLayer }
        XCTAssertEqual(borders.count, 2)
        XCTAssertNotNil(borders[1].path)

        for size in [CGSize(width: 5, height: 80), CGSize(width: 50, height: 5), .zero] {
            cell.bounds = CGRect(origin: .zero, size: size)
            cell.layoutSubviews()
            XCTAssertNil(borders[1].path)
        }
        cell.bounds = CGRect(x: 0, y: 0, width: 50, height: 80)
        cell.layoutSubviews()
        XCTAssertNotNil(borders[0].path)
        XCTAssertNotNil(borders[1].path)
        XCTAssertEqual(cell.summary.accessibilityFrameInContainerSpace, cell.bounds)
    }

    func testRecycledInactivePageFinishesBeforeBecomingInteractive() async throws {
        let view = MobileMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        var days = snapshots()
        view.update(configuration(days: days))
        let original = days[0]
        days[0] = MobileMonthDaySnapshot(
            date: original.date, dateKey: original.dateKey, dayNumberText: "Updated",
            accessibilityLabel: "Updated day", courses: [], holiday: nil,
            events: [], allDayEvents: [], deadlineKinds: []
        )
        view.update(configuration(days: days, active: false))
        XCTAssertTrue(view.cells.allSatisfy(\.isHidden))
        XCTAssertEqual(view.accessibilityElements?.count, 0)
        // A rapid reversal must not expose a partially warmed page.
        view.update(configuration(days: days, active: true))
        XCTAssertTrue(view.cells.allSatisfy { !$0.isHidden })
        XCTAssertEqual(view.cells[0].numberButton.title(for: .normal), "Updated")
        XCTAssertEqual(view.cells[0].summary.accessibilityLabel, "Updated day")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(view.cells.allSatisfy { $0.isUserInteractionEnabled && !$0.isHidden })
        XCTAssertEqual(view.cells[0].numberButton.title(for: .normal), "Updated")
    }

    func testInactiveWarmupCompletesWithoutExposingAccessibilityElements() async throws {
        let view = MobileMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 500)
        let days = snapshots()
        view.update(configuration(days: days))
        // Alter a content key while keeping all original cells reusable.
        let recycled = MobileMonthNativeGrid(
            days: days, monthKey: "2026-10", selectedDateKey: "2026-10-01", todayKey: "2026-09-05",
            expansionProgress: 1, cellHeight: 75, dayTopInset: 4, maximumEventRows: 2,
            active: false, language: .english, onSelect: { _ in }
        )
        view.update(recycled)
        for _ in 0..<100 {
            if view.cells.allSatisfy({ !$0.isHidden }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(view.cells.allSatisfy { !$0.isHidden && !$0.isUserInteractionEnabled })
        XCTAssertEqual(view.accessibilityElements?.count, 0)
        XCTAssertTrue(view.cells.allSatisfy { $0.frame.height == 75 })
    }

    private func configuration(
        days: [MobileMonthDaySnapshot], active: Bool = true, onSelect: @escaping (Date) -> Void = { _ in }
    ) -> MobileMonthNativeGrid {
        MobileMonthNativeGrid(
            days: days, monthKey: "2026-09", selectedDateKey: "2026-09-01", todayKey: "2026-09-05",
            expansionProgress: 1, cellHeight: 80, dayTopInset: 4, maximumEventRows: 2,
            active: active, language: .english, onSelect: onSelect
        )
    }

    private func snapshots() -> [MobileMonthDaySnapshot] {
        let first = StrictContractDateParser.date(from: "2026-09-01")!
        return (0..<42).map { index in
            let date = Calendar.shanghai.date(byAdding: .day, value: index, to: first)!
            return MobileMonthDaySnapshot(
                date: date, dateKey: StrictContractDateParser.string(from: date),
                dayNumberText: String(Calendar.shanghai.component(.day, from: date)),
                accessibilityLabel: "September 1, two deadlines", courses: [], holiday: nil,
                events: [MobileMonthEvent(id: "\(index)-first", title: "Deadline one", categoryKey: "DDL", tint: AppTheme.assignment),
                         MobileMonthEvent(id: "\(index)-second", title: "Deadline two", categoryKey: "DDL", tint: AppTheme.conferenceDeadline)],
                allDayEvents: [], deadlineKinds: [.assignment, .conference]
            )
        }
    }
}
#endif
