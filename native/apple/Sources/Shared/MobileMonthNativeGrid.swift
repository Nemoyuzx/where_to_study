#if os(iOS)
import SwiftUI
import UIKit

struct MobileMonthNativeGrid: View, @MainActor Animatable {
    let days: [MobileMonthDaySnapshot]
    let monthKey: String
    let selectedDateKey: String
    let todayKey: String
    var expansionProgress: CGFloat
    var cellHeight: CGFloat
    let dayTopInset: CGFloat
    let maximumEventRows: Int
    let active: Bool
    let language: AppLanguage
    let onSelect: (Date) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(expansionProgress, cellHeight) }
        set { expansionProgress = newValue.first; cellHeight = newValue.second }
    }

    var body: some View {
        NativeMonthRepresentable(grid: self, colorScheme: colorScheme, sizeCategory: sizeCategory)
    }
}

private struct NativeMonthRepresentable: UIViewRepresentable {
    let grid: MobileMonthNativeGrid
    let colorScheme: ColorScheme
    let sizeCategory: ContentSizeCategory

    func makeUIView(context: Context) -> MobileMonthGridUIView { MobileMonthGridUIView() }
    func updateUIView(_ view: MobileMonthGridUIView, context: Context) {
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        view.update(grid, contentSizeCategory: sizeCategory.uiCategory)
    }
    static func dismantleUIView(_ view: MobileMonthGridUIView, coordinator: ()) { view.dismantle() }
}

final class MobileMonthGridUIView: UIView {
    let cells = (0..<42).map { _ in MobileMonthDayControl() }
    private var configuration: MobileMonthNativeGrid?
    private var fontCategory: UIContentSizeCategory?
    private var dateFontPointSize: CGFloat = 15
    private var warmingGeneration: UInt64 = 0
    private var nextWarmCell: Int?

    init() {
        super.init(frame: .zero)
        isAccessibilityElement = false
        backgroundColor = .clear
        cells.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func dismantle() {
        warmingGeneration &+= 1
        nextWarmCell = nil
        configuration = nil
        accessibilityElements = []
        accessibilityElementsHidden = true
        isUserInteractionEnabled = false
        cells.forEach { $0.onSelect = nil; $0.setActive(false) }
    }

    func update(_ value: MobileMonthNativeGrid, contentSizeCategory: UIContentSizeCategory? = nil) {
        let previous = configuration
        let category = contentSizeCategory ?? traitCollection.preferredContentSizeCategory
        let fontChanged = fontCategory != category
        fontCategory = category
        if fontChanged {
            dateFontPointSize = UIFont.preferredFont(forTextStyle: .subheadline,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
        }
        let geometryChanged = previous?.expansionProgress != value.expansionProgress
            || previous?.cellHeight != value.cellHeight || previous?.dayTopInset != value.dayTopInset
        let contentChanged = previous == nil || previous?.days != value.days
            || previous?.monthKey != value.monthKey || previous?.selectedDateKey != value.selectedDateKey
            || previous?.todayKey != value.todayKey || previous?.language != value.language
            || previous?.maximumEventRows != value.maximumEventRows
        let activationChanged = previous?.active != value.active
        let finishWarmupNow = value.active && nextWarmCell != nil
        let warmIncrementally = contentChanged && previous != nil && !value.active
        if contentChanged || finishWarmupNow {
            warmingGeneration &+= 1
            nextWarmCell = warmIncrementally ? 0 : nil
        }
        let accessibilityChanged = previous == nil
            || (previous!.expansionProgress > 0.01) != (value.expansionProgress > 0.01)
            || (previous!.expansionProgress > 0.95) != (value.expansionProgress > 0.95)
        configuration = value
        isAccessibilityElement = false
        isUserInteractionEnabled = value.active
        accessibilityElementsHidden = !value.active
        accessibilityIdentifier = value.active ? "calendar.mobile.month-native-grid" : "preloaded.calendar.mobile.month-native-grid"

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells.enumerated() {
            cell.onSelect = value.onSelect
            cell.dateFontPointSize = dateFontPointSize
            if warmIncrementally {
                // A recycled page is outside the clipped viewport. Prepare one
                // row per run-loop slice instead of redrawing 42 cells in the
                // page-completion frame. Activation flushes any remaining rows.
                cell.isHidden = true
            } else if contentChanged || finishWarmupNow {
                cell.isHidden = index >= value.days.count
                if !cell.isHidden {
                    cell.configure(value.days[index], grid: value)
                }
            } else if fontChanged { cell.refreshAppearance() }
            if contentChanged || activationChanged || finishWarmupNow { cell.setActive(value.active) }
            if contentChanged || geometryChanged {
                cell.setGeometry(progress: value.expansionProgress, topInset: value.dayTopInset)
            }
        }
        if contentChanged || activationChanged || accessibilityChanged || finishWarmupNow { refreshAccessibility() }
        if contentChanged || geometryChanged || fontChanged || finishWarmupNow {
            setNeedsLayout()
            if bounds.width.isFinite, bounds.width > 24,
               bounds.height.isFinite, bounds.height > 0,
               value.cellHeight.isFinite, value.cellHeight > 0 {
                layoutIfNeeded()
            }
        }
        CATransaction.commit()
        if warmIncrementally { scheduleWarmRow(generation: warmingGeneration) }
    }

    private func scheduleWarmRow(generation: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) { [weak self] in
            guard let self, self.warmingGeneration == generation,
                  let start = self.nextWarmCell, let value = self.configuration, !value.active else { return }
            let end = min(start + 7, self.cells.count)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for index in start..<end {
                let cell = self.cells[index]
                cell.isHidden = index >= value.days.count
                if !cell.isHidden { cell.configure(value.days[index], grid: value) }
                cell.setActive(false)
                cell.setGeometry(progress: value.expansionProgress, topInset: value.dayTopInset)
            }
            self.nextWarmCell = end < self.cells.count ? end : nil
            self.setNeedsLayout()
            self.layoutIfNeeded()
            CATransaction.commit()
            if self.nextWarmCell != nil { self.scheduleWarmRow(generation: generation) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration,
              bounds.width.isFinite, bounds.width > 24,
              bounds.height.isFinite, bounds.height > 0,
              configuration.cellHeight.isFinite, configuration.cellHeight > 0
        else { return }
        let width = max((bounds.width - 24) / 7, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells.enumerated() {
            cell.frame = CGRect(x: CGFloat(index % 7) * (width + 4),
                                y: CGFloat(index / 7) * (configuration.cellHeight + 4),
                                width: width, height: configuration.cellHeight)
            cell.layoutIfNeeded()
        }
        CATransaction.commit()
    }

    private func refreshAccessibility() {
        accessibilityElements = configuration?.active == true
            ? cells.filter { !$0.isHidden }.flatMap(\.accessibleItems) : []
    }
}

final class MobileMonthDayControl: UIControl {
    let numberButton = UIButton(type: .custom)
    let overflowButton = UIButton(type: .custom)
    private(set) var eventLabels = [MobileMonthEventLabel]()
    private let eventContainer = UIView()
    private let compactContainer = UIView()
    private let holidayLabel = UILabel()
    private let dots = (0..<3).map { _ in UIView() }
    private let todayDot = UIView()
    private let outerBorder = CAShapeLayer()
    private let innerBorder = CAShapeLayer()
    private(set) lazy var summary = MobileMonthDayAccessibilityElement(accessibilityContainer: self)
    private var day: MobileMonthDaySnapshot?
    private var dayIsSelected = false
    private var inMonth = false
    private var active = false
    private var language = AppLanguage.system
    private var visibleEventCount = 0
    private var hiddenEventCount = 0
    private var progress: CGFloat = 1
    private var topInset: CGFloat = 4
    private var maximumRows = 0
    private var needsTextDisplay = true
    private var laidOutWidth: CGFloat = 0
    var dateFontPointSize: CGFloat = 15
    var onSelect: ((Date) -> Void)?

    init() {
        super.init(frame: .zero)
        isAccessibilityElement = false
        layer.cornerRadius = 9
        clipsToBounds = true
        [numberButton, compactContainer, eventContainer, todayDot].forEach(addSubview)
        compactContainer.addSubview(holidayLabel)
        dots.forEach { dot in dot.layer.cornerRadius = 1.5; compactContainer.addSubview(dot) }
        compactContainer.accessibilityElementsHidden = true
        compactContainer.isUserInteractionEnabled = false
        todayDot.layer.cornerRadius = 2.5
        todayDot.layer.zPosition = 1
        todayDot.isUserInteractionEnabled = false
        todayDot.isAccessibilityElement = false
        eventContainer.addSubview(overflowButton)
        overflowButton.layer.cornerRadius = 4
        overflowButton.clipsToBounds = true
        overflowButton.titleLabel?.font = .systemFont(ofSize: 9, weight: .semibold)
        holidayLabel.font = .systemFont(ofSize: 7, weight: .bold)
        [outerBorder, innerBorder].forEach { border in
            border.fillColor = UIColor.clear.cgColor
            layer.addSublayer(border)
        }
        outerBorder.lineWidth = 1.75
        innerBorder.lineWidth = 1.25
        summary.owner = self
        addTarget(self, action: #selector(selectDay), for: .touchUpInside)
        numberButton.addTarget(self, action: #selector(selectDay), for: .touchUpInside)
        overflowButton.addTarget(self, action: #selector(selectDay), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ day: MobileMonthDaySnapshot, grid: MobileMonthNativeGrid) {
        let isSelected = day.dateKey == grid.selectedDateKey
        let isInMonth = day.dateKey.hasPrefix(grid.monthKey)
        guard self.day != day || dayIsSelected != isSelected || inMonth != isInMonth
                || language != grid.language || maximumRows != grid.maximumEventRows
                || todayDot.isHidden != (day.dateKey != grid.todayKey)
        else { return }
        self.day = day
        dayIsSelected = isSelected
        inMonth = isInMonth
        language = grid.language
        maximumRows = grid.maximumEventRows
        let rows = TeachingCalendarLogic.monthEventLayout(totalCount: day.events.count, maximumRows: grid.maximumEventRows)
        visibleEventCount = rows.visibleEventCount
        hiddenEventCount = rows.hiddenEventCount
        while eventLabels.count < visibleEventCount {
            let label = MobileMonthEventLabel()
            label.font = .systemFont(ofSize: 9, weight: .semibold)
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.layer.cornerRadius = 4
            label.layer.borderWidth = 0.75
            label.clipsToBounds = true
            label.isAccessibilityElement = true
            eventLabels.append(label)
            eventContainer.addSubview(label)
        }
        numberButton.setTitle(day.dayNumberText, for: .normal)
        for (index, label) in eventLabels.enumerated() {
            label.isHidden = index >= visibleEventCount
            if !label.isHidden {
                label.text = day.events[index].title
                label.accessibilityLabel = day.events[index].title
            } else {
                label.text = nil
                label.accessibilityLabel = nil
                label.accessibilityIdentifier = nil
                label.isAccessibilityElement = false
            }
        }
        overflowButton.isHidden = hiddenEventCount == 0
        overflowButton.setTitle("+\(hiddenEventCount)", for: .normal)
        overflowButton.accessibilityLabel = String(
            format: AppLocalization.string("查看其余 %lld 项全天日程", language: language),
            locale: language.locale, arguments: [hiddenEventCount]
        )
        holidayLabel.text = day.holiday.map { AppLocalization.string($0.type == "holiday" ? "休" : "班", language: language) }
        holidayLabel.isHidden = day.holiday == nil
        for (index, dot) in dots.enumerated() { dot.isHidden = index >= min(day.courses.count, 3) }
        todayDot.isHidden = day.dateKey != grid.todayKey
        summary.accessibilityLabel = day.accessibilityLabel
        summary.accessibilityValue = day.deadlineKinds.map(\.rawValue).joined(separator: ",")
        summary.accessibilityTraits = dayIsSelected ? [.selected] : []
        refreshAppearance()
    }

    func setActive(_ active: Bool) {
        self.active = active
        isUserInteractionEnabled = active
        overflowButton.isUserInteractionEnabled = active && progress > 0.95
        accessibilityElementsHidden = !active
        summary.isAccessibilityElement = active
        numberButton.isAccessibilityElement = active
        overflowButton.isAccessibilityElement = active
        guard let day else { return }
        let prefix = active ? "calendar.mobile" : "preloaded.calendar.mobile"
        summary.accessibilityIdentifier = "\(prefix).month-day-cell.\(day.dateKey)"
        numberButton.accessibilityIdentifier = "\(prefix).month-day-number.\(day.dateKey)"
        overflowButton.accessibilityIdentifier = "\(prefix).month-overflow.\(day.dateKey)"
        for (index, label) in eventLabels.enumerated() {
            guard !label.isHidden else {
                label.isAccessibilityElement = false
                label.accessibilityIdentifier = nil
                continue
            }
            label.isAccessibilityElement = active
            label.accessibilityIdentifier = index < day.events.count
                ? "\(prefix).month-event.\(day.events[index].id)" : "\(prefix).month-event.unused.\(index)"
        }
    }

    func setGeometry(progress: CGFloat, topInset: CGFloat) {
        self.progress = min(max(progress, 0), 1)
        self.topInset = topInset
        compactContainer.alpha = 1 - self.progress
        eventContainer.alpha = self.progress
        overflowButton.isUserInteractionEnabled = active && self.progress > 0.95
        setNeedsLayout()
    }

    var accessibleItems: [Any] {
        guard active else { return [] }
        var items: [Any] = [summary, numberButton]
        if progress > 0.01 { items.append(contentsOf: eventLabels.prefix(visibleEventCount).map { $0 as Any }) }
        if hiddenEventCount > 0, progress > 0.95 { items.append(overflowButton) }
        return items
    }

    func refreshAppearance() {
        guard let day else { return }
        needsTextDisplay = true
        func color(_ value: Color) -> UIColor { UIColor(value).resolvedColor(with: traitCollection) }
        let foreground: UIColor = dayIsSelected ? color(AppTheme.onPrimary)
            : !inMonth ? color(AppTheme.secondaryText).withAlphaComponent(0.45)
            : day.holiday.map { color($0.type == "holiday" ? AppTheme.danger : AppTheme.primary) } ?? color(AppTheme.text)
        backgroundColor = dayIsSelected ? color(AppTheme.selectedDate)
            : day.courses.isEmpty ? .clear : color(AppTheme.primary).withAlphaComponent(CGFloat(min(0.08 + Double(day.courses.count) * 0.08, 0.36)))
        numberButton.titleLabel?.font = .systemFont(ofSize: dateFontPointSize, weight: dayIsSelected ? .bold : .medium)
        numberButton.setTitleColor(foreground, for: .normal)
        holidayLabel.textColor = foreground
        dots.forEach { $0.backgroundColor = foreground }
        todayDot.backgroundColor = color(AppTheme.danger)
        let eventBackground = dayIsSelected ? UIColor.black.withAlphaComponent(0.18) : color(AppTheme.surface).withAlphaComponent(0.78)
        overflowButton.backgroundColor = eventBackground
        overflowButton.setTitleColor(color(dayIsSelected ? AppTheme.onPrimary : AppTheme.secondaryText), for: .normal)
        for index in 0..<visibleEventCount {
            let tint = color(dayIsSelected ? AppTheme.onPrimary : day.events[index].tint)
            eventLabels[index].textColor = tint
            eventLabels[index].backgroundColor = eventBackground
            eventLabels[index].layer.borderColor = tint.withAlphaComponent(0.55).cgColor
        }
        outerBorder.isHidden = day.deadlineKinds.isEmpty
        innerBorder.isHidden = day.deadlineKinds.count < 2
        if let first = day.deadlineKinds.first { outerBorder.strokeColor = color(CalendarDeadlinePresentation.tint(for: first)).cgColor }
        if day.deadlineKinds.count > 1 { innerBorder.strokeColor = color(CalendarDeadlinePresentation.tint(for: day.deadlineKinds[1])).cgColor }
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            refreshAppearance()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width.isFinite, bounds.width > 0, bounds.height.isFinite, bounds.height > 0 else {
            outerBorder.path = nil
            innerBorder.path = nil
            summary.accessibilityFrameInContainerSpace = .zero
            return
        }
        let contentWidth = max(bounds.width - 4, 0)
        numberButton.frame = CGRect(x: 2, y: topInset, width: contentWidth, height: 20)
        let rowTop = topInset + 23
        let dotCount = day.map { min($0.courses.count, 3) } ?? 0
        let holidayWidth = holidayLabel.isHidden ? 0 : holidayLabel.intrinsicContentSize.width
        let count = dotCount + (holidayLabel.isHidden ? 0 : 1)
        let compactWidth = holidayWidth + CGFloat(dotCount * 3 + max(count - 1, 0) * 2)
        compactContainer.frame = CGRect(x: (bounds.width - compactWidth) / 2, y: rowTop, width: compactWidth, height: 8)
        holidayLabel.frame = CGRect(x: 0, y: 0, width: holidayWidth, height: 8)
        let dotStart = holidayLabel.isHidden ? 0 : holidayWidth + 2
        for (index, dot) in dots.enumerated() { dot.frame = CGRect(x: dotStart + CGFloat(index * 5), y: 2.5, width: 3, height: 3) }
        eventContainer.frame = CGRect(x: 2, y: rowTop - 5 * (1 - progress), width: contentWidth,
                                      height: CGFloat(visibleEventCount + (hiddenEventCount > 0 ? 1 : 0)) * 16)
        for (index, label) in eventLabels.enumerated() { label.frame = CGRect(x: 0, y: CGFloat(index * 16), width: contentWidth, height: 14) }
        overflowButton.frame = CGRect(x: 0, y: CGFloat(visibleEventCount * 16), width: contentWidth, height: 14)
        todayDot.frame = CGRect(x: bounds.width - 8, y: 3, width: 5, height: 5)
        outerBorder.path = UIBezierPath(roundedRect: bounds, cornerRadius: 9).cgPath
        let innerRect = bounds.insetBy(dx: 3, dy: 3)
        if !innerBorder.isHidden, innerRect.width > 0, innerRect.height > 0,
           !innerRect.isNull, !innerRect.isInfinite {
            innerBorder.path = UIBezierPath(roundedRect: innerRect, cornerRadius: 6).cgPath
        } else {
            innerBorder.path = nil
        }
        summary.accessibilityFrameInContainerSpace = bounds
        // Warm newly changed glyphs before the parent starts its page offset.
        // Vertical interpolation with an unchanged width does not redraw text.
        if bounds.width > 0, needsTextDisplay || laidOutWidth != bounds.width {
            numberButton.layoutIfNeeded()
            overflowButton.layoutIfNeeded()
            let labels = [numberButton.titleLabel, holidayLabel, overflowButton.titleLabel]
                .compactMap { $0 } + Array(eventLabels.prefix(visibleEventCount))
            labels.filter { !$0.isHidden }.forEach { $0.layer.displayIfNeeded() }
            needsTextDisplay = false
            laidOutWidth = bounds.width
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard active, !isHidden, alpha > 0.01, self.point(inside: point, with: event) else { return nil }
        if let hit = numberButton.hitTest(convert(point, to: numberButton), with: event) { return hit }
        if !overflowButton.isHidden, progress > 0.95,
           let hit = overflowButton.hitTest(convert(point, to: overflowButton), with: event) { return hit }
        return self
    }

    @objc func selectDay() { if active, let day { onSelect?(day.date) } }
}

final class MobileMonthEventLabel: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 3, dy: 0)) }
}

final class MobileMonthDayAccessibilityElement: UIAccessibilityElement {
    weak var owner: MobileMonthDayControl?
    override func accessibilityActivate() -> Bool {
        guard let owner, owner.isUserInteractionEnabled else { return false }
        owner.selectDay()
        return true
    }
}

private extension ContentSizeCategory {
    var uiCategory: UIContentSizeCategory {
        switch self {
        case .extraSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .extraLarge
        case .extraExtraLarge: .extraExtraLarge
        case .extraExtraExtraLarge: .extraExtraExtraLarge
        case .accessibilityMedium: .accessibilityMedium
        case .accessibilityLarge: .accessibilityLarge
        case .accessibilityExtraLarge: .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
#endif
