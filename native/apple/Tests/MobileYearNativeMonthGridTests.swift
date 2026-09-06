#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import WhereToStudyiOS

@MainActor
final class MobileYearNativeMonthGridTests: XCTestCase {
    func testOneDrawingViewHasOnlyRealDatesAndSixFixedHeightRows() throws {
        let month = projection()
        let view = makeView(month: month)
        XCTAssertTrue(view.subviews.isEmpty)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertEqual(view.dayAccessibilityElements.count, 31)
        XCTAssertEqual(view.accessibilityElements?.count, 31)
        XCTAssertFalse(view.layer.shouldRasterize)
        let headerHeight = ceil(UIFont.systemFont(ofSize: 8, weight: .medium).lineHeight)
        XCTAssertEqual(MobileYearNativeMonthGrid.height, headerHeight + 156)
        for index in month.days.indices {
            let frame = try XCTUnwrap(view.dayRect(at: index))
            let slot = month.leadingBlankCount + index
            XCTAssertEqual(frame.width, 20, accuracy: 0.001)
            XCTAssertEqual(frame.height, 24)
            XCTAssertEqual(frame.minX, CGFloat(slot % 7) * 21)
            XCTAssertEqual(frame.minY, headerHeight + 2 + CGFloat(slot / 7) * 26)
            XCTAssertEqual(view.dayAccessibilityElements[index].accessibilityFrameInContainerSpace, frame)
        }
        XCTAssertEqual(try XCTUnwrap(view.dayRect(at: 30)).maxY, view.bounds.height)
    }

    func testWholeDateCellSelectsButHeaderSpacingAndAdjacentMonthBlanksDoNot() throws {
        let month = projection()
        var selectedDate: Date?
        let view = makeView(month: month, onSelect: { selectedDate = $0 })
        let first = try XCTUnwrap(view.dayRect(at: 0))
        let nearCorner = CGPoint(x: first.minX + 0.1, y: first.maxY - 0.1)
        XCTAssertEqual(view.dayIndex(at: nearCorner), 0)
        XCTAssertTrue(view.hitTest(nearCorner, with: nil) === view)
        XCTAssertTrue(view.selectDay(at: 0))
        XCTAssertEqual(selectedDate, month.days[0].date)
        XCTAssertNil(view.dayIndex(at: CGPoint(x: 1, y: 1)))
        XCTAssertNil(view.dayIndex(at: CGPoint(x: 1, y: first.midY)))
        XCTAssertNil(view.dayIndex(at: CGPoint(x: first.maxX + 0.5, y: first.midY)))
        XCTAssertNil(view.dayIndex(at: CGPoint(x: first.midX, y: first.maxY + 1)))
        XCTAssertNil(view.dayIndex(at: CGPoint(x: view.bounds.maxX - 1, y: view.bounds.maxY - 1)))
        XCTAssertNil(view.dayIndex(at: CGPoint(x: CGFloat.nan, y: 10)))
        XCTAssertFalse(view.selectDay(at: -1))
        XCTAssertFalse(view.selectDay(at: 31))
    }

    func testVoiceOverMetadataAndActivationFollowTheActivePage() throws {
        let month = projection()
        var selectedDate: Date?
        let view = makeView(month: month, onSelect: { selectedDate = $0 })
        let identities = view.dayAccessibilityElements.map(ObjectIdentifier.init)
        let first = try XCTUnwrap(view.dayAccessibilityElements.first)
        XCTAssertEqual(first.accessibilityIdentifier, "calendar.mobile.year-day.2026-08-01")
        XCTAssertEqual(first.accessibilityLabel, "Saturday, August 1, 2026")
        XCTAssertEqual(first.accessibilityValue, "assignment,conference")
        XCTAssertTrue(first.accessibilityTraits.contains(.button))
        XCTAssertTrue(first.accessibilityTraits.contains(.selected))
        XCTAssertFalse(view.dayAccessibilityElements[1].accessibilityTraits.contains(.selected))
        XCTAssertTrue(first.accessibilityActivate())
        XCTAssertEqual(selectedDate, month.days[0].date)

        view.update(configuration(month: month, active: false, onSelect: { selectedDate = $0 }))
        selectedDate = nil
        XCTAssertEqual(view.dayAccessibilityElements.map(ObjectIdentifier.init), identities)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertEqual(view.accessibilityElements?.count, 0)
        XCTAssertTrue(view.dayAccessibilityElements.allSatisfy { !$0.isAccessibilityElement })
        XCTAssertFalse(first.accessibilityActivate())
        XCTAssertFalse(view.selectDay(at: 0))
        XCTAssertNil(view.hitTest(try XCTUnwrap(view.dayRect(at: 0)).center, with: nil))
        XCTAssertNil(selectedDate)

        view.update(configuration(month: month, onSelect: { selectedDate = $0 }))
        XCTAssertEqual(view.dayAccessibilityElements.map(ObjectIdentifier.init), identities)
        XCTAssertEqual(view.accessibilityElements?.count, 31)
        XCTAssertTrue(first.accessibilityActivate())
        XCTAssertEqual(selectedDate, month.days[0].date)
    }

    func testUnchangedAndActivationOnlyUpdatesReuseDrawingAndReplaceTheCallback() {
        let month = projection()
        var firstCallbackCount = 0
        var secondCallbackCount = 0
        let view = makeView(month: month, onSelect: { _ in firstCallbackCount += 1 })
        view.layer.displayIfNeeded()
        XCTAssertFalse(view.layer.needsDisplay())
        let identities = view.dayAccessibilityElements.map(ObjectIdentifier.init)
        view.update(configuration(month: month, onSelect: { _ in secondCallbackCount += 1 }))
        XCTAssertFalse(view.layer.needsDisplay())
        XCTAssertEqual(view.dayAccessibilityElements.map(ObjectIdentifier.init), identities)
        XCTAssertTrue(view.selectDay(at: 0))
        XCTAssertEqual(firstCallbackCount, 0)
        XCTAssertEqual(secondCallbackCount, 1)

        view.update(configuration(month: month, active: false))
        XCTAssertFalse(view.layer.needsDisplay())
    }

    func testInactiveNewMonthDefersAccessibilityAndFinishesSynchronouslyOnActivation() {
        let month = projection()
        let view = MobileYearMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 146, height: MobileYearNativeMonthGrid.height)
        view.layer.displayIfNeeded()
        view.update(configuration(month: month, active: false))
        view.layoutIfNeeded()

        XCTAssertTrue(view.dayAccessibilityElements.isEmpty)
        XCTAssertEqual(view.accessibilityElements?.count, 0)
        XCTAssertFalse(view.layer.needsDisplay())

        view.update(configuration(month: month, active: true))
        XCTAssertEqual(view.dayAccessibilityElements.count, 31)
        XCTAssertEqual(view.accessibilityElements?.count, 31)
        XCTAssertFalse(view.layer.needsDisplay(), "The target page is pre-drawn before horizontal motion")
    }

    func testVisibleDepartingMonthDrawsWhileRemainingNonInteractive() {
        let month = projection()
        let view = MobileYearMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 146, height: MobileYearNativeMonthGrid.height)
        view.update(configuration(month: month, active: false, rendersContent: true))
        view.layoutIfNeeded()

        XCTAssertEqual(view.completedDisplayCount, 1)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertEqual(view.accessibilityElements?.count, 0)
        XCTAssertFalse(view.selectDay(at: 0))
    }

    func testInvalidatedRetainedBackingRedrawsBeforeReactivation() {
        let month = projection()
        let view = makeView(month: month)
        view.update(configuration(month: month, active: false, rendersContent: false))
        let displayCount = view.completedDisplayCount
        view.layer.contents = nil
        XCTAssertEqual(view.completedDisplayCount, displayCount)

        view.update(configuration(month: month, active: true, rendersContent: true))
        XCTAssertGreaterThan(view.completedDisplayCount, displayCount)
        XCTAssertEqual(view.accessibilityElements?.count, 31)
    }

    func testMonthAndLanguageReuseClearRemovedDateElements() throws {
        let view = makeView(month: projection())
        let retainedFirst = try XCTUnwrap(view.dayAccessibilityElements.first)
        let removedLast = try XCTUnwrap(view.dayAccessibilityElements.last)
        view.update(configuration(month: projection(monthKey: "2027-02", count: 28, leading: 0), language: .simplifiedChinese))
        XCTAssertTrue(view.dayAccessibilityElements.first === retainedFirst)
        XCTAssertEqual(view.dayAccessibilityElements.count, 28)
        XCTAssertEqual(retainedFirst.accessibilityIdentifier, "calendar.mobile.year-day.2027-02-01")
        XCTAssertFalse(retainedFirst.accessibilityTraits.contains(.selected))
        XCTAssertNil(removedLast.accessibilityIdentifier)
        XCTAssertFalse(removedLast.accessibilityActivate())
        XCTAssertEqual(view.weekdayLabels, ["一", "二", "三", "四", "五", "六", "日"])
        view.update(configuration(month: projection(), language: .english))
        // Preserve the existing localization key, which is shared with day mode.
        XCTAssertEqual(view.weekdayLabels, ["M", "T", "W", "T", "F", "S", "Day"])
    }

    func testInvalidBoundsExposeNoDateGeometryAndRecoverWithoutReplacingElements() {
        let view = makeView(month: projection())
        let identities = view.dayAccessibilityElements.map(ObjectIdentifier.init)
        for size in [CGSize.zero, CGSize(width: 6, height: MobileYearNativeMonthGrid.height), CGSize(width: 146, height: 1)] {
            view.bounds = CGRect(origin: .zero, size: size)
            view.layoutSubviews()
            XCTAssertNil(view.dayRect(at: 0))
            XCTAssertNil(view.dayIndex(at: .zero))
            XCTAssertFalse(view.selectDay(at: 0))
            XCTAssertEqual(view.accessibilityElements?.count, 0)
            XCTAssertTrue(view.dayAccessibilityElements.allSatisfy { $0.accessibilityFrameInContainerSpace == .zero })
            let image = draw(view, size: CGSize(width: 146, height: MobileYearNativeMonthGrid.height))
            XCTAssertEqual(pixel(image, at: CGPoint(x: 110, y: 20)).alpha, 0)
        }
        view.bounds = CGRect(x: 0, y: 0, width: 146, height: MobileYearNativeMonthGrid.height)
        view.layoutSubviews()
        XCTAssertNotNil(view.dayRect(at: 0))
        XCTAssertEqual(view.accessibilityElements?.count, 31)
        XCTAssertEqual(view.dayAccessibilityElements.map(ObjectIdentifier.init), identities)
        let displayCount = view.completedDisplayCount
        view.bounds.size.width = 160
        view.layoutSubviews()
        XCTAssertGreaterThan(view.completedDisplayCount, displayCount)
        XCTAssertEqual(view.dayAccessibilityElements[0].accessibilityFrameInContainerSpace, view.dayRect(at: 0))
    }

    func testDrawingPreservesSelectedFillCourseOpacityDoubleBordersAndTodayDotInBothThemes() throws {
        let month = projection()
        let view = makeView(month: month)
        for style in [UIUserInterfaceStyle.light, .dark] {
            view.overrideUserInterfaceStyle = style
            if #available(iOS 17.0, *) { view.updateTraitsIfNeeded() }
            XCTAssertEqual(view.traitCollection.userInterfaceStyle, style)
            let traits = UITraitCollection(userInterfaceStyle: style)
            let image = draw(view, size: view.bounds.size)
            let first = try XCTUnwrap(view.dayRect(at: 0))
            assertPixel(image, at: CGPoint(x: first.minX + 6, y: first.minY + 6), matches: AppTheme.selectedDate, traits: traits)
            assertPixel(image, at: CGPoint(x: first.midX, y: first.minY + 0.25), matches: AppTheme.assignment, traits: traits)
            assertPixel(image, at: CGPoint(x: first.midX, y: first.minY + 2), matches: AppTheme.conferenceDeadline, traits: traits)
            assertPixel(image, at: CGPoint(x: first.maxX - 4, y: first.minY + 4), matches: AppTheme.danger, traits: traits)
            let third = try XCTUnwrap(view.dayRect(at: 2))
            assertPixel(
                image, at: CGPoint(x: third.minX + 6, y: third.minY + 6),
                matches: AppTheme.primary, traits: traits,
                alpha: TeachingCalendarLogic.yearCourseOpacity(courseCount: month.days[2].courseCount)
            )
            XCTAssertEqual(pixel(image, at: CGPoint(x: 10, y: first.midY)).alpha, 0)
        }
    }

    func testDismantleReleasesCallbackAndDisablesPreviouslyRetainedAccessibilityElements() throws {
        final class CallbackOwner { var date: Date? }
        let view = MobileYearMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 146, height: MobileYearNativeMonthGrid.height)
        weak var retainedOwner: CallbackOwner?
        do {
            let owner = CallbackOwner()
            retainedOwner = owner
            view.update(configuration(month: projection(), onSelect: { [owner] in owner.date = $0 }))
        }
        let first = try XCTUnwrap(view.dayAccessibilityElements.first)
        XCTAssertNotNil(retainedOwner)
        view.dismantle()
        XCTAssertNil(retainedOwner)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertEqual(view.accessibilityElements?.count, 0)
        XCTAssertFalse(first.accessibilityActivate())
        XCTAssertNil(first.accessibilityIdentifier)
    }

    private func makeView(month: MobileYearMonthProjection, onSelect: @escaping (Date) -> Void = { _ in }) -> MobileYearMonthGridUIView {
        let view = MobileYearMonthGridUIView()
        view.frame = CGRect(x: 0, y: 0, width: 146, height: MobileYearNativeMonthGrid.height)
        view.update(configuration(month: month, onSelect: onSelect))
        view.layoutIfNeeded()
        return view
    }

    private func configuration(
        month: MobileYearMonthProjection,
        active: Bool = true,
        rendersContent: Bool? = nil,
        language: AppLanguage = .english,
        onSelect: @escaping (Date) -> Void = { _ in }
    ) -> MobileYearNativeMonthGrid {
        MobileYearNativeMonthGrid(
            month: month, selectedDateKey: "2026-08-01", todayKey: "2026-08-01",
            active: active, rendersContent: rendersContent ?? active,
            language: language, onSelect: onSelect
        )
    }

    private func projection(monthKey: String = "2026-08", count: Int = 31, leading: Int = 5) -> MobileYearMonthProjection {
        let first = StrictContractDateParser.date(from: "\(monthKey)-01")!
        let days = (0..<count).map { index in
            let date = Calendar.shanghai.date(byAdding: .day, value: index, to: first)!
            return MobileYearDayProjection(
                date: date, dateKey: StrictContractDateParser.string(from: date), dayNumberText: String(index + 1),
                accessibilityLabel: index == 0 ? "Saturday, August 1, 2026" : "Day \(index + 1)",
                courseCount: index % 5, deadlineKinds: index == 0 ? [.assignment, .conference] : []
            )
        }
        return MobileYearMonthProjection(monthStart: first, monthKey: monthKey, monthTitle: "Month", leadingBlankCount: leading, days: days)
    }

    private func draw(_ view: MobileYearMonthGridUIView, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            view.layer.render(in: renderer.cgContext)
        }
    }

    private func pixel(_ image: UIImage, at point: CGPoint) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let source = image.cgImage!
            let x = floor(point.x * image.scale)
            let y = floor(point.y * image.scale)
            context.draw(source, in: CGRect(
                x: -x, y: -(CGFloat(source.height) - y - 1),
                width: CGFloat(source.width), height: CGFloat(source.height)
            ))
        }
        let alpha = Double(bytes[3]) / 255
        guard alpha > 0 else { return (0, 0, 0, 0) }
        return (Double(bytes[0]) / 255 / alpha, Double(bytes[1]) / 255 / alpha, Double(bytes[2]) / 255 / alpha, alpha)
    }

    private func assertPixel(
        _ image: UIImage, at point: CGPoint, matches color: Color, traits: UITraitCollection,
        alpha: Double = 1, file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = pixel(image, at: point)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, colorAlpha: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &colorAlpha)
        XCTAssertEqual(actual.red, Double(red), accuracy: 0.03, file: file, line: line)
        XCTAssertEqual(actual.green, Double(green), accuracy: 0.03, file: file, line: line)
        XCTAssertEqual(actual.blue, Double(blue), accuracy: 0.03, file: file, line: line)
        XCTAssertEqual(actual.alpha, alpha, accuracy: 0.03, file: file, line: line)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
#endif
