#if os(iOS)
import SwiftUI
import UIKit

/// One drawing surface per mini month keeps the year pager's child hierarchy
/// independent of the number of dates and deadline borders on screen.
struct MobileYearNativeMonthGrid: View {
    let month: MobileYearMonthProjection
    let selectedDateKey: String
    let todayKey: String
    let active: Bool
    let rendersContent: Bool
    let language: AppLanguage
    let onSelect: (Date) -> Void
    @Environment(\.colorScheme) private var colorScheme

    static var height: CGFloat { MobileYearMonthGridUIView.contentHeight }

    var body: some View {
        NativeYearMonthRepresentable(grid: self, colorScheme: colorScheme)
            .frame(height: Self.height)
    }
}

private struct NativeYearMonthRepresentable: UIViewRepresentable {
    let grid: MobileYearNativeMonthGrid
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> MobileYearMonthGridUIView { MobileYearMonthGridUIView() }

    func updateUIView(_ view: MobileYearMonthGridUIView, context: Context) {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
        view.update(grid)
    }

    static func dismantleUIView(_ view: MobileYearMonthGridUIView, coordinator: ()) { view.dismantle() }
}

final class MobileYearMonthGridUIView: UIView {
    private static let font = UIFont.systemFont(ofSize: 8, weight: .medium)
    private static let weekdayHeight = ceil(font.lineHeight)
    private static let rowHeight: CGFloat = 24
    private static let rowSpacing: CGFloat = 2
    private static let columnSpacing: CGFloat = 1
    static var contentHeight: CGFloat { weekdayHeight + 6 * (rowHeight + rowSpacing) }

    private struct Content: Equatable {
        let month: MobileYearMonthProjection
        let selectedDateKey: String
        let todayKey: String
        let resourceName: String
    }

    private var content: Content?
    private var active = false
    private var rendersContent = false
    private var onSelect: ((Date) -> Void)?
    private var accessibilityBounds = CGRect.null
    private var renderedContent: Content?
    private var renderedPalette = [UInt32]()
    private var renderedScale: CGFloat = 0
    private var renderedSize = CGSize.zero
    private(set) var completedDisplayCount = 0
    private(set) var weekdayLabels = [String]()
    private(set) var dayAccessibilityElements = [MobileYearDayAccessibilityElement]()

    init() {
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        // Offsets change while paging; retain the existing backing instead of
        // asking UIKit to redraw every mini month during recentering. Explicit
        // content/size/theme checks below redraw before a changed page moves.
        contentMode = .scaleToFill
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isUserInteractionEnabled = false
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapDay(_:))))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ grid: MobileYearNativeMonthGrid) {
        let next = Content(
            month: grid.month,
            selectedDateKey: grid.selectedDateKey,
            todayKey: grid.todayKey,
            resourceName: grid.language.resolvedResourceName
        )
        let contentChanged = content != next
        let activationChanged = active != grid.active
        if content?.resourceName != next.resourceName {
            weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"].map {
                AppLocalization.string($0, language: grid.language)
            }
        }
        content = next
        active = grid.active
        rendersContent = grid.rendersContent
        onSelect = grid.onSelect
        isUserInteractionEnabled = active
        accessibilityElementsHidden = !active
        accessibilityIdentifier = active
            ? "calendar.mobile.year-native-month.\(grid.month.monthKey)"
            : "preloaded.calendar.mobile.year-native-month.\(grid.month.monthKey)"
        if contentChanged || activationChanged {
            if active {
                refreshAccessibility()
            } else {
                accessibilityElements = []
                dayAccessibilityElements.forEach { $0.isAccessibilityElement = false }
            }
        }
        let paletteIsStale = (contentChanged || activationChanged || renderedPalette.isEmpty)
            && renderedPalette != resolvedPaletteSignature()
        let displayIsStale = renderedContent != next || paletteIsStale
            || renderedScale != currentDisplayScale
            || renderedSize != bounds.size || layer.contents == nil
        if rendersContent && displayIsStale {
            displayPreparedContent()
        }
    }

    func dismantle() {
        content = nil
        renderedContent = nil
        renderedPalette.removeAll()
        renderedScale = 0
        renderedSize = .zero
        onSelect = nil
        active = false
        rendersContent = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = nil
        layer.contents = nil
        accessibilityElements = []
        dayAccessibilityElements.forEach { $0.clear() }
        dayAccessibilityElements.removeAll()
    }

    private var validGeometry: Bool {
        bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.maxX.isFinite && bounds.maxY.isFinite
            && bounds.width.isFinite && bounds.width > 6 * Self.columnSpacing
            && bounds.height.isFinite && bounds.height >= Self.contentHeight
    }

    /// The same rectangles drive drawing, touch hit testing, and VoiceOver.
    func dayRect(at index: Int) -> CGRect? {
        guard validGeometry, let month = content?.month,
              month.days.indices.contains(index), (0...6).contains(month.leadingBlankCount)
        else { return nil }
        let slot = month.leadingBlankCount + index
        guard slot < 42 else { return nil }
        let width = (bounds.width - 6 * Self.columnSpacing) / 7
        return CGRect(
            x: bounds.minX + CGFloat(slot % 7) * (width + Self.columnSpacing),
            y: bounds.minY + Self.weekdayHeight + Self.rowSpacing
                + CGFloat(slot / 7) * (Self.rowHeight + Self.rowSpacing),
            width: width, height: Self.rowHeight
        )
    }

    func dayIndex(at point: CGPoint) -> Int? {
        guard validGeometry, point.x.isFinite, point.y.isFinite,
              bounds.contains(point), let month = content?.month else { return nil }
        let width = (bounds.width - 6 * Self.columnSpacing) / 7
        let rowY = point.y - bounds.minY - Self.weekdayHeight - Self.rowSpacing
        guard rowY >= 0, rowY < 6 * (Self.rowHeight + Self.rowSpacing) else { return nil }
        let column = Int((point.x - bounds.minX) / (width + Self.columnSpacing))
        let row = Int(rowY / (Self.rowHeight + Self.rowSpacing))
        guard (0..<7).contains(column), (0..<6).contains(row) else { return nil }
        let index = row * 7 + column - month.leadingBlankCount
        guard let rect = dayRect(at: index), rect.contains(point) else { return nil }
        return index
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        active && dayIndex(at: point) != nil
    }

    @objc private func tapDay(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let index = dayIndex(at: recognizer.location(in: self)) else { return }
        _ = selectDay(at: index)
    }

    @discardableResult
    func selectDay(at index: Int) -> Bool {
        guard active, let content, content.month.days.indices.contains(index),
              dayRect(at: index) != nil, let onSelect else { return false }
        onSelect(content.month.days[index].date)
        return true
    }

    private func refreshAccessibility() {
        guard let content else { return }
        let days = content.month.days
        while dayAccessibilityElements.count > days.count {
            dayAccessibilityElements.removeLast().clear()
        }
        while dayAccessibilityElements.count < days.count {
            let element = MobileYearDayAccessibilityElement(accessibilityContainer: self)
            element.owner = self
            dayAccessibilityElements.append(element)
        }
        let prefix = active ? "calendar.mobile" : "preloaded.calendar.mobile"
        for (index, day) in days.enumerated() {
            let element = dayAccessibilityElements[index]
            element.dayIndex = index
            element.isAccessibilityElement = active
            element.accessibilityLabel = day.accessibilityLabel
            element.accessibilityValue = day.deadlineKinds.map(\.rawValue).joined(separator: ",")
            element.accessibilityIdentifier = "\(prefix).year-day.\(day.dateKey)"
            element.accessibilityTraits = day.dateKey == content.selectedDateKey ? [.button, .selected] : [.button]
            element.accessibilityFrameInContainerSpace = dayRect(at: index) ?? .zero
        }
        accessibilityBounds = bounds
        accessibilityElements = active && validGeometry ? dayAccessibilityElements : []
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if active, accessibilityBounds != bounds { refreshAccessibility() }
        if rendersContent && (renderedContent != content
            || renderedScale != currentDisplayScale
            || renderedSize != bounds.size || layer.contents == nil) {
            displayPreparedContent()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let palette = resolvedPaletteSignature()
        if rendersContent,
           renderedPalette != palette || renderedScale != currentDisplayScale {
            displayPreparedContent()
        }
    }

    private var currentDisplayScale: CGFloat {
        max(window?.screen.scale ?? traitCollection.displayScale, 1)
    }

    private func resolvedPaletteSignature() -> [UInt32] {
        let colors: [Color] = [
            AppTheme.primary, AppTheme.selectedDate, AppTheme.text, AppTheme.onPrimary,
            AppTheme.secondaryText, AppTheme.border, AppTheme.danger,
            AppTheme.assignment, AppTheme.schoolNotice, AppTheme.competitionDeadline,
            AppTheme.conferenceDeadline, AppTheme.summerCampDeadline,
            AppTheme.hackathonDeadline, AppTheme.customDeadline,
        ]
        return colors.map { value in
            let color = UIColor(value).resolvedColor(with: traitCollection)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            if !color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                var white: CGFloat = 0
                color.getWhite(&white, alpha: &alpha)
                red = white
                green = white
                blue = white
            }
            func byte(_ component: CGFloat) -> UInt32 {
                UInt32((min(max(component, 0), 1) * 255).rounded())
            }
            return byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha)
        }
    }

    private func displayPreparedContent() {
        guard rendersContent, validGeometry, let content else {
            layer.contents = nil
            renderedContent = nil
            renderedSize = .zero
            return
        }
        let scale = currentDisplayScale
        let palette = resolvedPaletteSignature()
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            renderer.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            drawContent(in: renderer.cgContext, rect: bounds, content: content)
        }
        layer.contents = image.cgImage
        layer.contentsScale = image.scale
        layer.contentsGravity = .resize
        renderedContent = content
        renderedPalette = palette
        renderedScale = scale
        renderedSize = bounds.size
        completedDisplayCount += 1
    }

    private func drawContent(in context: CGContext, rect: CGRect, content: Content) {
        func color(_ value: Color) -> UIColor { UIColor(value).resolvedColor(with: traitCollection) }
        let primary = color(AppTheme.primary)
        let selectedFill = color(AppTheme.selectedDate)
        let text = color(AppTheme.text)
        let selectedText = color(AppTheme.onPrimary)
        let secondaryText = color(AppTheme.secondaryText)
        let border = color(AppTheme.border)
        let today = color(AppTheme.danger)
        let width = (bounds.width - 6 * Self.columnSpacing) / 7
        for (index, label) in weekdayLabels.enumerated() {
            let frame = CGRect(
                x: bounds.minX + CGFloat(index) * (width + Self.columnSpacing),
                y: bounds.minY, width: width, height: Self.weekdayHeight
            )
            if frame.intersects(rect) { drawText(label, in: frame, color: secondaryText) }
        }
        for (index, day) in content.month.days.enumerated() {
            guard let frame = dayRect(at: index), frame.intersects(rect) else { continue }
            let selected = day.dateKey == content.selectedDateKey
            let outline = UIBezierPath(roundedRect: frame, cornerRadius: 4).cgPath
            context.saveGState()
            context.addPath(outline)
            context.clip()
            let fill = selected ? selectedFill : primary.withAlphaComponent(
                CGFloat(TeachingCalendarLogic.yearCourseOpacity(courseCount: day.courseCount))
            )
            context.setFillColor(fill.cgColor)
            context.fill(frame)
            drawText(day.dayNumberText, in: frame, color: selected ? selectedText : text)
            context.addPath(outline)
            context.setStrokeColor(day.deadlineKinds.first.map { color(CalendarDeadlinePresentation.tint(for: $0)) }?.cgColor ?? border.cgColor)
            context.setLineWidth(day.deadlineKinds.isEmpty ? 0.5 : 1.5)
            context.strokePath()
            let innerFrame = frame.insetBy(dx: 2, dy: 2)
            if day.deadlineKinds.count > 1, innerFrame.width > 0, innerFrame.height > 0 {
                context.addPath(UIBezierPath(roundedRect: innerFrame, cornerRadius: 2).cgPath)
                context.setStrokeColor(color(CalendarDeadlinePresentation.tint(for: day.deadlineKinds[1])).cgColor)
                context.setLineWidth(1)
                context.strokePath()
            }
            if day.dateKey == content.todayKey {
                context.setFillColor(today.cgColor)
                context.fillEllipse(in: CGRect(x: frame.maxX - 6, y: frame.minY + 2, width: 4, height: 4))
            }
            context.restoreGState()
        }
    }

    private func drawText(_ value: String, in rect: CGRect, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: color]
        let string = value as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}

final class MobileYearDayAccessibilityElement: UIAccessibilityElement {
    weak var owner: MobileYearMonthGridUIView?
    var dayIndex = 0

    override func accessibilityActivate() -> Bool { owner?.selectDay(at: dayIndex) ?? false }

    func clear() {
        owner = nil
        isAccessibilityElement = false
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityFrameInContainerSpace = .zero
    }
}
#endif
