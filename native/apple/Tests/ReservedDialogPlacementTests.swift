import XCTest
#if !DIALOG_PLACEMENT_STANDALONE
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif
#endif

final class ReservedDialogPlacementTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func region(_ frame: CGRect, top: CGFloat = 0, leading: CGFloat = 0,
                        bottom: CGFloat = 0, trailing: CGFloat = 0, active: Bool = true) -> DialogReservedArea {
        DialogReservedArea(frame: frame, top: top, leading: leading, bottom: bottom,
                           trailing: trailing, isActive: active)
    }

    func testNoRegionPreservesOriginalCenteredBounds() {
        XCTAssertEqual(ReservedDialogPlacement.pane(in: bounds, regions: []), bounds)
    }

    func testInactiveAndNonIntersectingRegionsDoNotMoveTheCard() {
        XCTAssertEqual(ReservedDialogPlacement.pane(in: bounds, regions: [
            region(CGRect(x: 390, y: 0, width: 20, height: 600), active: false),
            region(CGRect(x: 900, y: 0, width: 20, height: 600))
        ]), bounds)
    }

    func testVerticalDivisionIncludesMarginsAndKeepsATrailingPaneOnEqualArea() {
        let divider = region(CGRect(x: 390, y: 0, width: 20, height: 600), leading: 6, trailing: 6)
        let pane = ReservedDialogPlacement.pane(in: bounds, regions: [divider])
        XCTAssertEqual(pane, CGRect(x: 416, y: 0, width: 384, height: 600))
        XCTAssertTrue(pane.intersection(divider.exclusion).isEmpty)
    }

    func testHorizontalDivisionChoosesTheLargestAvailablePane() {
        let divider = region(CGRect(x: 0, y: 250, width: 800, height: 20), top: 8, bottom: 12)
        let pane = ReservedDialogPlacement.pane(in: bounds, regions: [divider])
        XCTAssertEqual(pane, CGRect(x: 0, y: 282, width: 800, height: 318))
        XCTAssertTrue(pane.intersection(divider.exclusion).isEmpty)
    }

    func testSmallOcclusionKeepsFullLengthAvailableStrips() {
        let camera = region(CGRect(x: 380, y: 250, width: 40, height: 40))
        let pane = ReservedDialogPlacement.pane(in: bounds, regions: [camera])
        XCTAssertEqual(pane, CGRect(x: 0, y: 290, width: 800, height: 310))
        XCTAssertTrue(pane.intersection(camera.exclusion).isEmpty)
    }

    func testMarginsCanBringAnOutsideRegionInsideTheBounds() {
        let camera = region(CGRect(x: -10, y: 0, width: 5, height: 600), trailing: 20)
        XCTAssertEqual(ReservedDialogPlacement.pane(in: bounds, regions: [camera]),
                       CGRect(x: 15, y: 0, width: 785, height: 600))
    }

    func testSeveralRegionsProduceAContainedNonIntersectingPane() {
        let regions = [region(CGRect(x: 390, y: 0, width: 20, height: 600)),
                       region(CGRect(x: 600, y: 200, width: 50, height: 70), top: 8, trailing: 12)]
        let pane = ReservedDialogPlacement.pane(in: bounds, regions: regions)
        XCTAssertTrue(bounds.contains(pane))
        for value in regions { XCTAssertTrue(pane.intersection(value.exclusion).isEmpty) }
        XCTAssertGreaterThanOrEqual(pane.width, ReservedDialogPlacement.minimumPane.width)
        XCTAssertGreaterThanOrEqual(pane.height, ReservedDialogPlacement.minimumPane.height)
    }

    func testExtremelyNarrowAndFullyCoveredPanesHaveFiniteAccessibleFallbacks() {
        let small = CGRect(x: 0, y: 0, width: 320, height: 200)
        XCTAssertEqual(ReservedDialogPlacement.pane(in: small, regions: [
            region(CGRect(x: 80, y: 0, width: 160, height: 200))
        ]), small)
        XCTAssertEqual(ReservedDialogPlacement.pane(in: bounds, regions: [region(bounds)]), bounds)
        XCTAssertEqual(ReservedDialogPlacement.pane(in: .zero, regions: [region(bounds)]), .zero)
    }

    func testManyOcclusionsRemainBoundedAndDoNotIntersectTheSelectedPane() {
        let regions = (0..<40).map { index in
            region(CGRect(x: CGFloat(index % 10) * 30, y: CGFloat(index / 10) * 30, width: 10, height: 10))
        }
        let pane = ReservedDialogPlacement.pane(in: bounds, regions: regions)
        XCTAssertTrue(bounds.contains(pane))
        for value in regions { XCTAssertTrue(pane.intersection(value.exclusion).isEmpty) }
    }
}
