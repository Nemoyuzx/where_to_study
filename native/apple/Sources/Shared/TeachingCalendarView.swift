import SwiftUI

final class TeachingCalendarSessionState: ObservableObject {
    @Published var selectedDate = Date()
    @Published var modeRawValue = "周"
    @Published var isMonthExpanded = true
    @Published var isMonthDetailRaised = false
}

private enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

private struct CalendarDailyDetailsLoadID: Hashable {
    let dates: [String]
    let almanacDate: String?
    let sampleMode: Bool
    let loadsAlmanac: Bool
    let loadsPublicDeadlines: Bool
}

private struct CalendarAgendaSelection: Identifiable {
    let id = UUID()
    let date: Date
    let events: [CalendarAgendaDisplayItem]
}

private enum CalendarAgendaItemKind {
    case course
    case holiday
    case workday
    case assignment
    case schoolNotice
    case publicDeadline
}

private struct CalendarAgendaDisplayItem: Identifiable {
    let id: String
    let title: String
    let categoryKey: String
    let kind: CalendarAgendaItemKind
}

private struct CalendarMonthDeadlineEvent: Identifiable {
    let id: String
    let title: String
    let categoryKey: String
    let agendaKind: CalendarAgendaItemKind
    let tint: Color
}

#if os(macOS)
private struct DesktopMonthEvent: Identifiable {
    enum Kind: Equatable {
        case course
        case holiday
        case workday
        case assignment
        case schoolNotice
        case publicDeadline
    }

    let id: String
    let title: String
    let time: String?
    let kind: Kind
}
#endif

enum TeachingCalendarLogic {
    enum GestureAxis: Equatable {
        case horizontal
        case vertical
    }

    enum MonthExpansionAction: Equatable {
        case expand
        case collapse
    }

    enum NavigationUnit {
        case day
        case week
        case month
        case year
    }

    struct MonthEventLayout: Equatable {
        let visibleEventCount: Int
        let hiddenEventCount: Int
    }

    struct MonthGridLayout: Equatable {
        let collapsedCellHeight: CGFloat
        let expandedCellHeight: CGFloat
        let collapsedGridWidth: CGFloat
        let expandedGridWidth: CGFloat

        func cellHeight(at progress: CGFloat) -> CGFloat {
            interpolate(from: collapsedCellHeight, to: expandedCellHeight, at: progress)
        }

        func gridWidth(at progress: CGFloat) -> CGFloat {
            interpolate(from: collapsedGridWidth, to: expandedGridWidth, at: progress)
        }

        private func interpolate(from start: CGFloat, to end: CGFloat, at progress: CGFloat) -> CGFloat {
            let clampedProgress = min(max(progress, 0), 1)
            return start + (end - start) * clampedProgress
        }
    }

    #if os(macOS)
    struct DesktopYearLayout: Equatable {
        let rowSpacing: CGFloat
        let columnSpacing: CGFloat
        let monthHeight: CGFloat
        let monthTitleFontSize: CGFloat
        let monthTitleHeight: CGFloat
        let monthContentSpacing: CGFloat
        let weekdayFontSize: CGFloat
        let weekdayHeight: CGFloat
        let gridSpacing: CGFloat
        let dayCellHeight: CGFloat
        let dayFontSize: CGFloat
        let holidayFontSize: CGFloat
        let selectionDiameter: CGFloat

        var totalHeight: CGFloat {
            monthHeight * 3 + rowSpacing * 2
        }
    }
    #endif

    enum MonthPosition: Int, CaseIterable {
        case detailRaised = 0
        case collapsed = 1
        case expanded = 2
    }

    static func routesMonthDragToDetails(
        position: MonthPosition,
        verticalTranslation: CGFloat,
        detailsCanScrollBackward: Bool = false
    ) -> Bool {
        guard position == .detailRaised else { return false }
        return verticalTranslation < 0 || detailsCanScrollBackward
    }

    static func yearCourseOpacity(courseCount: Int) -> Double {
        guard courseCount > 0 else { return 0 }
        let count = Double(courseCount)
        return 0.12 + 0.72 * count / (count + 3)
    }

    #if os(macOS)
    static func desktopYearLayout(availableHeight: CGFloat) -> DesktopYearLayout {
        let height = max(availableHeight, 0)
        let rowSpacing = min(max(height * 0.025, 8), 28)
        let monthHeight = max((height - rowSpacing * 2) / 3, 0)
        let monthTitleFontSize = min(max(monthHeight * 0.095, 13), 22)
        let monthTitleHeight = monthTitleFontSize * 1.25
        let monthContentSpacing = min(max(monthHeight * 0.025, 2), 10)
        let weekdayFontSize = min(max(monthHeight * 0.052, 8), 12)
        let weekdayHeight = min(max(monthHeight * 0.075, 10), 20)
        let gridSpacing = min(max(monthHeight * 0.014, 1), 4)
        let reservedHeight = monthTitleHeight
            + monthContentSpacing
            + weekdayHeight
            + gridSpacing * 6
        let dayCellHeight = max((monthHeight - reservedHeight) / 6, 1)
        let dayFontSize = min(max(dayCellHeight * 0.4, 7), 14)
        let holidayFontSize = min(max(dayCellHeight * 0.28, 6), 10)
        let selectionDiameter = min(dayCellHeight, min(max(dayCellHeight * 0.82, 10), 40))

        return DesktopYearLayout(
            rowSpacing: rowSpacing,
            columnSpacing: min(max(monthHeight * 0.07, 12), 28),
            monthHeight: monthHeight,
            monthTitleFontSize: monthTitleFontSize,
            monthTitleHeight: monthTitleHeight,
            monthContentSpacing: monthContentSpacing,
            weekdayFontSize: weekdayFontSize,
            weekdayHeight: weekdayHeight,
            gridSpacing: gridSpacing,
            dayCellHeight: dayCellHeight,
            dayFontSize: dayFontSize,
            holidayFontSize: holidayFontSize,
            selectionDiameter: selectionDiameter
        )
    }
    #endif

    static func periodTitle(
        for date: Date,
        modeRawValue: String,
        language: AppLanguage = .simplifiedChinese,
        calendar: Calendar = .shanghai
    ) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        if language.resolvedResourceName == "en" {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en")
            formatter.timeZone = calendar.timeZone
            switch modeRawValue {
            case CalendarMode.day.rawValue:
                formatter.dateFormat = "MMMM d, yyyy"
                return formatter.string(from: date)
            case CalendarMode.week.rawValue:
                formatter.dateFormat = "MMMM yyyy"
                return "\(formatter.string(from: date)) · Week \(calendar.component(.weekOfYear, from: date))"
            case CalendarMode.year.rawValue:
                return "\(year)"
            default:
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: date)
            }
        }
        switch modeRawValue {
        case CalendarMode.day.rawValue:
            return "\(year)年\(month)月\(calendar.component(.day, from: date))日"
        case CalendarMode.week.rawValue:
            return "\(year)年\(month)月 第 \(calendar.component(.weekOfYear, from: date)) 周"
        case CalendarMode.year.rawValue:
            return "\(year)年"
        default:
            return "\(year)年\(month)月"
        }
    }

    static func movedDate(
        from date: Date,
        unit: NavigationUnit,
        direction: Int,
        calendar: Calendar = .shanghai
    ) -> Date? {
        let component: Calendar.Component
        let amount: Int
        switch unit {
        case .day:
            component = .day
            amount = direction
        case .week:
            component = .day
            amount = direction * 7
        case .month:
            component = .month
            amount = direction
        case .year:
            component = .year
            amount = direction
        }
        return calendar.date(byAdding: component, value: amount, to: date)
    }

    static func datesInYear(
        containing date: Date,
        calendar: Calendar = .shanghai
    ) -> [Date] {
        guard let interval = calendar.dateInterval(of: .year, for: date) else { return [] }
        var dates = [Date]()
        var day = interval.start
        while day < interval.end {
            dates.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    static func swipeDirection(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        predictedHorizontalTranslation: CGFloat
    ) -> Int? {
        let projected = abs(predictedHorizontalTranslation) > abs(horizontalTranslation)
            ? predictedHorizontalTranslation
            : horizontalTranslation
        guard abs(horizontalTranslation) >= 36,
              abs(projected) >= 80,
              abs(horizontalTranslation) >= abs(verticalTranslation) * 1.35
        else { return nil }
        return projected < 0 ? 1 : -1
    }

    static func monthExpansionAction(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat
    ) -> MonthExpansionAction? {
        guard abs(verticalTranslation) >= 44,
              abs(verticalTranslation) >= abs(horizontalTranslation) * 1.25
        else { return nil }
        return verticalTranslation > 0 ? .expand : .collapse
    }

    static func gestureAxis(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        activationDistance: CGFloat = 8
    ) -> GestureAxis? {
        let horizontal = abs(horizontalTranslation)
        let vertical = abs(verticalTranslation)
        guard max(horizontal, vertical) >= activationDistance else { return nil }
        return horizontal > vertical ? .horizontal : .vertical
    }

    static func monthExpansionProgress(
        isExpanded: Bool,
        verticalTranslation: CGFloat,
        travelDistance: CGFloat
    ) -> CGFloat {
        let distance = max(travelDistance, 1)
        let base: CGFloat = isExpanded ? 1 : 0
        return min(max(base + verticalTranslation / distance, 0), 1)
    }

    static func monthPosition(
        isExpanded: Bool,
        isDetailRaised: Bool,
        verticalTranslation: CGFloat,
        travelDistance: CGFloat
    ) -> CGFloat {
        let distance = max(travelDistance, 1)
        let base = isExpanded
            ? CGFloat(MonthPosition.expanded.rawValue)
            : CGFloat(isDetailRaised ? MonthPosition.detailRaised.rawValue : MonthPosition.collapsed.rawValue)
        return min(max(base + verticalTranslation / distance, 0), 2)
    }

    static func monthGridExpansionProgress(position: CGFloat) -> CGFloat {
        min(max(position - CGFloat(MonthPosition.collapsed.rawValue), 0), 1)
    }

    static func monthDetailLiftProgress(position: CGFloat) -> CGFloat {
        min(max(CGFloat(MonthPosition.collapsed.rawValue) - position, 0), 1)
    }

    static func settledMonthPosition(
        position: CGFloat,
        verticalTranslation: CGFloat,
        predictedVerticalTranslation: CGFloat,
        allowsIntermediatePosition: Bool = true
    ) -> MonthPosition {
        let clamped = min(max(position, 0), 2)
        let projectedDelta = predictedVerticalTranslation - verticalTranslation
        if !allowsIntermediatePosition {
            if projectedDelta <= -42 { return .detailRaised }
            if projectedDelta >= 42 { return .expanded }
            return clamped < CGFloat(MonthPosition.collapsed.rawValue)
                ? .detailRaised
                : .expanded
        }
        let target: Int
        if abs(projectedDelta) >= 42 {
            target = projectedDelta > 0 ? Int(ceil(clamped)) : Int(floor(clamped))
        } else if abs(verticalTranslation) >= 24 {
            // A deliberate low-velocity drag must still cross one detent. XCTest
            // and accessibility-driven drags often have little projected
            // momentum even though the finger travelled far enough to express
            // intent; rounding here would otherwise snap the sheet backwards.
            target = verticalTranslation > 0 ? Int(ceil(clamped)) : Int(floor(clamped))
        } else {
            target = Int(clamped.rounded())
        }
        return MonthPosition(rawValue: min(max(target, 0), 2)) ?? .collapsed
    }

    static func normalizedMonthPosition(
        _ position: MonthPosition,
        allowsIntermediatePosition: Bool
    ) -> MonthPosition {
        guard !allowsIntermediatePosition, position == .collapsed else { return position }
        return .detailRaised
    }

    static func expandedMonthCellHeight(availableHeight: CGFloat) -> CGFloat {
        let weekdayHeight: CGFloat = 18
        let weekdayBottomSpacing: CGFloat = 8
        let gridSpacing: CGFloat = 4 * 5
        let handleHeight: CGFloat = 28
        let verticalPadding: CGFloat = 8 * 2
        let availableGridHeight = availableHeight
            - weekdayHeight
            - weekdayBottomSpacing
            - gridSpacing
            - handleHeight
            - verticalPadding
        return max(30, floor(availableGridHeight / 6))
    }

    static func monthGridLayout(
        contentWidth: CGFloat,
        availableHeight: CGFloat,
        columnSpacing: CGFloat = 4
    ) -> MonthGridLayout {
        let width = max(contentWidth, 0)
        let totalColumnSpacing = columnSpacing * 6
        let squareCellHeight = max(24, floor((width - totalColumnSpacing) / 7))
        let expandedCellHeight = expandedMonthCellHeight(availableHeight: availableHeight)
        let collapsedCellHeight = min(squareCellHeight, expandedCellHeight)
        return MonthGridLayout(
            collapsedCellHeight: collapsedCellHeight,
            expandedCellHeight: expandedCellHeight,
            collapsedGridWidth: width,
            expandedGridWidth: width
        )
    }

    static func monthDayTopInset(collapsedCellHeight: CGFloat) -> CGFloat {
        let compactContentHeight: CGFloat = 31
        return max(4, floor((collapsedCellHeight - compactContentHeight) / 2))
    }

    static func monthEventRowCapacity(
        cellHeight: CGFloat,
        dayTopInset: CGFloat,
        dayLabelHeight: CGFloat = 20,
        rowHeight: CGFloat = 16
    ) -> Int {
        let available = cellHeight - dayTopInset - dayLabelHeight - 5
        return max(1, Int(floor(available / max(rowHeight, 1))))
    }

    static func monthEventLayout(totalCount: Int, maximumRows: Int) -> MonthEventLayout {
        let total = max(totalCount, 0)
        let rows = max(maximumRows, 0)
        guard total > rows else {
            return MonthEventLayout(visibleEventCount: total, hiddenEventCount: 0)
        }
        guard rows > 0 else {
            return MonthEventLayout(visibleEventCount: 0, hiddenEventCount: total)
        }
        return MonthEventLayout(
            visibleEventCount: rows - 1,
            hiddenEventCount: total - rows + 1
        )
    }
}

struct TeachingCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dailyInfo: DailyInfoStore
    @EnvironmentObject private var calendarDeadlines: CalendarDeadlineStore
    @ObservedObject var session: TeachingCalendarSessionState
    @State private var yearPopoverDate: Date?
    @State private var yearPopoverLocation: CGPoint?
    @State private var showingDatePicker = false
    @State private var presentedMonthAgenda: CalendarAgendaSelection?
    @State private var presentedTimelineAgenda: CalendarAgendaSelection?

    private let calendar = Calendar.shanghai

    private var selectedDate: Date {
        get { session.selectedDate }
        nonmutating set { session.selectedDate = newValue }
    }

    private var mode: CalendarMode {
        get { CalendarMode(rawValue: session.modeRawValue) ?? .week }
        nonmutating set { session.modeRawValue = newValue.rawValue }
    }

    private var isMonthExpanded: Bool {
        get { session.isMonthExpanded }
        nonmutating set { session.isMonthExpanded = newValue }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                titleBar
                    .accessibilityIdentifier("layout.calendar.expanded")
                calendarPanelContent
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #else
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBar
                        .accessibilityIdentifier("layout.calendar.expanded")

                    Surface {
                        calendarPanelContent
                    }
                }
                .padding(20)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            #endif

            yearPopoverOverlay
            if let selection = presentedMonthAgenda {
                calendarAgendaDialog(
                    selection,
                    titleKey: "月视图全天日程",
                    accessibilityIdentifier: "calendar.regular.month-agenda-dialog",
                    dismiss: { presentedMonthAgenda = nil }
                )
            } else if let selection = presentedTimelineAgenda {
                calendarAgendaDialog(
                    selection,
                    titleKey: mode == .week ? "周视图全天日程" : "全天日程",
                    accessibilityIdentifier: "calendar.regular.week-agenda-dialog",
                    dismiss: { presentedTimelineAgenda = nil }
                )
            }
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("screen.calendar")
        .coordinateSpace(name: Self.calendarCoordinateSpace)
        .onAppear {
            ensureVisibleHolidays()
        }
        .onChange(of: selectedDate) { _ in
            ensureVisibleHolidays()
        }
        .onChange(of: mode) { _ in
            dismissYearPopover()
            presentedMonthAgenda = nil
            presentedTimelineAgenda = nil
            ensureVisibleHolidays()
        }
        .task(id: dailyDetailsLoadID) {
            await loadVisibleDailyDetails()
        }
    }

    private var calendarPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            dateControls
            if let status = holidayStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if !model.statusMessage.isEmpty {
                Text(model.localized(model.statusMessage))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if !model.calendarImportStatusMessage.isEmpty {
                Text(model.localized(model.calendarImportStatusMessage))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Divider()
            #if os(macOS)
            ZStack(alignment: .topLeading) {
                calendarContent
                    .id(mode)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .animation(Self.viewAnimation, value: mode)
            #else
            calendarContent
                .id(mode)
                .transition(.opacity.combined(with: .scale(scale: 0.995)))
                .animation(Self.viewAnimation, value: mode)
            #endif
        }
        #if os(macOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #endif
    }

    @ViewBuilder
    private var titleBar: some View {
        #if os(macOS)
        HStack(alignment: .bottom) {
            PageTitle(eyebrow: "BUPT Classroom Planner", title: periodTitle)
            modePicker.frame(maxWidth: 280)
        }
        #else
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                PageTitle(eyebrow: "BUPT Classroom Planner", title: periodTitle)
                modePicker.frame(width: 300)
            }
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(eyebrow: "BUPT Classroom Planner", title: periodTitle)
                modePicker
            }
        }
        #endif
    }

    private var modePicker: some View {
        Picker("视图", selection: modeSelection) {
            ForEach(CalendarMode.allCases) { item in
                Text(model.localized(item.rawValue)).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var dateControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dateNavigation
                Spacer(minLength: 12)
                calendarActions
            }
            VStack(alignment: .leading, spacing: 10) {
                dateNavigation
                calendarActions
            }
        }
    }

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            dateStepButton(systemName: "chevron.left", help: "上一时间段") { moveDate(-1) }
            Button {
                showingDatePicker.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(controlDateFormatter.string(from: selectedDate))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.text)
                .frame(width: 148, height: 32)
                .background(AppTheme.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDatePicker, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("选择日期")
                        .font(.headline)
                    DatePicker("日期", selection: datePickerSelection, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .environment(\.locale, model.appLanguage.locale)
                        .environment(\.timeZone, Calendar.shanghai.timeZone)
                }
                .padding(14)
                .frame(width: 310)
            }
            Button("今天") {
                withAnimation(Self.viewAnimation) { selectedDate = .now }
            }
            .frame(minWidth: 48)
            dateStepButton(systemName: "chevron.right", help: "下一时间段") { moveDate(1) }
        }
        .controlSize(.regular)
    }

    private func dateStepButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 16, height: 18)
        }
        .buttonStyle(.bordered)
        .help(help)
    }

    private var calendarActions: some View {
        HStack(spacing: 8) {
            Button {
                model.refreshSchedule()
            } label: {
                Label(
                    model.isRefreshingSchedule ? "正在获取…" : "获取/刷新个人课表",
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(model.isRefreshingSchedule || model.isImportingCalendar)
            Button {
                model.importScheduleToCalendar()
            } label: {
                Label(
                    model.isImportingCalendar ? "正在导入…" : "导入系统日历",
                    systemImage: "calendar.badge.plus"
                )
            }
            .disabled(model.schedule == nil || model.isRefreshingSchedule || model.isImportingCalendar)
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch mode {
        case .day: dayView
        case .week: weekView
        case .month: monthView
        case .year: yearView
        }
    }

    private var dayView: some View {
        return VStack(alignment: .leading, spacing: 12) {
            allDayItems(days: [selectedDate])
            CalendarTimelineView(
                days: [timelineDay(selectedDate)],
                selectedDate: selectedDate
            )
        }
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
    }

    private var weekView: some View {
        let days = weekDates()
        return VStack(alignment: .leading, spacing: 12) {
            allDayItems(days: days)
            CalendarTimelineView(
                days: days.map(timelineDay),
                selectedDate: selectedDate,
                onSelectDay: { date in
                    withAnimation(Self.viewAnimation) { selectedDate = date }
                }
            )
        }
    }

    private var monthView: some View {
        #if os(macOS)
        return desktopMonthView
        #else
        let first = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        let days = monthGridDates(containing: first)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            #if !os(macOS)
            HStack {
                Spacer()
                Button {
                    withAnimation(Self.monthExpansionAnimation) {
                        isMonthExpanded.toggle()
                    }
                } label: {
                    Label(
                        isMonthExpanded ? "折叠月历" : "展开日程",
                        systemImage: isMonthExpanded ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.bordered)
            }
            #endif
            LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(model.localized(label))
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                ForEach(days, id: \.self) { day in
                    monthDayButton(day, month: first)
                }
            }
            selectedDaySummary(selectedDate)
            assignmentSummary
            Divider()
            if model.almanacEnabled {
                almanacSummary
            }
            if model.hasEnabledPublicDeadlines {
                deadlineSummary
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
        .animation(Self.monthExpansionAnimation, value: isMonthExpanded)
        #endif
    }

    #if os(macOS)
    private var desktopMonthView: some View {
        let first = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        let days = monthGridDates(containing: first)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)

        return GeometryReader { proxy in
            let weekdayHeight: CGFloat = 30
            let availableGridHeight = max(proxy.size.height - weekdayHeight, 0)
            let cellHeight = max(floor(availableGridHeight / 6), 70)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVGrid(columns: columns, spacing: 0) {
                            ForEach(Self.weekdayLabels, id: \.self) { label in
                                Text(model.localized("周") + model.localized(label))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .frame(maxWidth: .infinity, minHeight: weekdayHeight)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(AppTheme.border)
                                            .frame(height: 0.5)
                                    }
                            }

                            ForEach(days, id: \.self) { day in
                                desktopMonthDay(day, month: first, cellHeight: cellHeight)
                            }
                        }
                        .overlay {
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: 0.5)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: max(proxy.size.height, 520), alignment: .top)

                    Surface { selectedDaySummary(selectedDate) }
                    Surface { assignmentSummary }
                    if model.almanacEnabled {
                        Surface { almanacSummary }
                    }
                    if model.hasEnabledPublicDeadlines {
                        Surface { deadlineSummary }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
        .accessibilityIdentifier("calendar.desktop.month-grid")
    }

    private func desktopMonthDay(_ day: Date, month: Date, cellHeight: CGFloat) -> some View {
        let events = desktopMonthEvents(on: day)
        let maximumRows = cellHeight >= 100 ? 4 : (cellHeight >= 80 ? 3 : 2)
        let layout = TeachingCalendarLogic.monthEventLayout(
            totalCount: events.count,
            maximumRows: maximumRows
        )
        let isSelected = sameDay(day, selectedDate)
        let isToday = sameDay(day, .now)
        let deadlineKind = CalendarDeadlinePresentation.preferredDeadlineKind(
            in: allDayEvents(on: day)
        )
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let weekNumber = calendar.component(.weekOfYear, from: day)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                if calendar.component(.weekday, from: day) == 2 {
                    Text("第 \(weekNumber) 周")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 4)
                desktopMonthDayBadge(
                    day: day,
                    isSelected: isSelected,
                    isToday: isToday,
                    inMonth: inMonth
                )
            }
            .frame(height: 22)

            ForEach(Array(events.prefix(layout.visibleEventCount))) { event in
                desktopMonthEventRow(event)
            }

            if layout.hiddenEventCount > 0 {
                Button {
                    selectedDate = day
                    if !events.isEmpty {
                        presentedMonthAgenda = CalendarAgendaSelection(
                            date: day,
                            events: events.map(calendarAgendaDisplayItem)
                        )
                    }
                } label: {
                    Text("+\(layout.hiddenEventCount) 项")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .frame(height: 15)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    model.localizedFormat("查看其余 %lld 项全天日程", layout.hiddenEventCount)
                )
                .accessibilityIdentifier(
                    "calendar.regular.month-overflow.\(StrictContractDateParser.string(from: day))"
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(
            maxWidth: .infinity,
            minHeight: cellHeight,
            maxHeight: cellHeight,
            alignment: .topLeading
        )
        .background(
            isSelected
                ? AppTheme.selectedDate.opacity(0.14)
                : (inMonth ? Color.clear : AppTheme.surface.opacity(0.28))
        )
        .overlay {
            ZStack {
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: 0.5)
                if let deadlineKind {
                    Rectangle()
                        .stroke(allDayEventTint(deadlineKind), lineWidth: 2)
                        .padding(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedDate = day }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dayAccessibilityLabel(day))
        .accessibilityValue(deadlineKind?.rawValue ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selectedDate = day }
    }

    private func desktopMonthDayBadge(
        day: Date,
        isSelected: Bool,
        isToday: Bool,
        inMonth: Bool
    ) -> some View {
        Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .medium))
            .monospacedDigit()
            .foregroundStyle(
                isSelected || isToday
                    ? AppTheme.onPrimary
                    : (inMonth ? AppTheme.text : AppTheme.secondaryText.opacity(0.55))
            )
            .frame(minWidth: 22, minHeight: 22)
            .background {
                ZStack {
                    if isSelected {
                        Circle().fill(AppTheme.selectedDate)
                    } else if isToday {
                        Circle().fill(Self.nowRed)
                    }
                    if isSelected, isToday {
                        Circle().stroke(Self.nowRed, lineWidth: 2)
                    }
                }
            }
    }

    private func desktopMonthEventRow(_ event: DesktopMonthEvent) -> some View {
        let tint = desktopMonthEventTint(event.kind)
        return HStack(spacing: 4) {
            if event.kind != .course {
                Image(systemName: desktopMonthEventSystemImage(event.kind))
                    .font(.system(size: 7, weight: .semibold))
            }
            Text(event.title)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let time = event.time {
                Text(time)
                    .font(.system(size: 8, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.82)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 15, maxHeight: 15, alignment: .leading)
        .background(tint.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func desktopMonthEvents(on day: Date) -> [DesktopMonthEvent] {
        let dateKey = StrictContractDateParser.string(from: day)
        let holidayEvents = holidayItems(on: day).map { item in
            DesktopMonthEvent(
                id: "\(dateKey)|holiday|\(item.id)",
                title: item.name,
                time: nil,
                kind: item.type == "holiday" ? .holiday : .workday
            )
        }
        let courseEvents = courses(on: day).map { course in
            DesktopMonthEvent(
                id: "\(dateKey)|course|\(course.id)",
                title: course.name,
                time: course.timeRange.split(separator: "-").first.map(String.init),
                kind: .course
            )
        }
        let assignmentEvents = assignmentItems(on: day).map { item in
            DesktopMonthEvent(
                id: "\(dateKey)|assignment|\(item.id)",
                title: item.title,
                time: deadlineTime(item.deadline),
                kind: .assignment
            )
        }
        let schoolNoticeEvents = schoolNoticeItems(on: day).map { item in
            DesktopMonthEvent(
                id: "\(dateKey)|school|\(item.id)",
                title: item.name,
                time: deadlineTime(item.deadline),
                kind: .schoolNotice
            )
        }
        let publicDeadlineEvents = otherPublicDeadlineItems(on: day).map { item in
            DesktopMonthEvent(
                id: "\(dateKey)|public|\(item.id)",
                title: item.name,
                time: deadlineTime(item.deadline),
                kind: .publicDeadline
            )
        }
        return holidayEvents + assignmentEvents + schoolNoticeEvents
            + publicDeadlineEvents + courseEvents
    }

    private func desktopMonthEventTint(_ kind: DesktopMonthEvent.Kind) -> Color {
        switch kind {
        case .course:
            return AppTheme.primary
        case .holiday:
            return Self.holidayRed
        case .workday:
            return AppTheme.accent
        case .assignment:
            return AppTheme.assignment
        case .schoolNotice:
            return AppTheme.schoolNotice
        case .publicDeadline:
            return AppTheme.publicDeadline
        }
    }

    private func desktopMonthEventSystemImage(_ kind: DesktopMonthEvent.Kind) -> String {
        switch kind {
        case .course: "book.closed.fill"
        case .holiday: "star.fill"
        case .workday: "briefcase.fill"
        case .assignment: "doc.text.fill"
        case .schoolNotice: "building.columns.fill"
        case .publicDeadline: "flag.checkered"
        }
    }
    #endif

    private func monthDayButton(_ day: Date, month: Date) -> some View {
        let dayCourses = courses(on: day)
        let holidays = holidayItems(on: day)
        let assignments = assignmentItems(on: day)
        let schoolNotices = schoolNoticeItems(on: day)
        let publicDeadlines = otherPublicDeadlineItems(on: day)
        let deadlineEvents: [CalendarMonthDeadlineEvent] = assignments.map { item in
            CalendarMonthDeadlineEvent(
                id: "assignment-\(item.id)",
                title: item.title,
                categoryKey: "课程作业 DDL",
                agendaKind: .assignment,
                tint: AppTheme.assignment
            )
        } + schoolNotices.map { item in
            CalendarMonthDeadlineEvent(
                id: "school-\(item.id)",
                title: item.name,
                categoryKey: "校内竞赛通知",
                agendaKind: .schoolNotice,
                tint: AppTheme.schoolNotice
            )
        } + publicDeadlines.map { item in
            CalendarMonthDeadlineEvent(
                id: "public-\(item.id)",
                title: item.name,
                categoryKey: item.kind.title,
                agendaKind: .publicDeadline,
                tint: AppTheme.publicDeadline
            )
        }
        let isSelected = sameDay(day, selectedDate)
        let isToday = sameDay(day, .now)
        let deadlineKind = CalendarDeadlinePresentation.preferredDeadlineKind(
            in: allDayEvents(on: day)
        )
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        #if os(macOS)
        let showsDetails = true
        #else
        let showsDetails = isMonthExpanded
        #endif
        let detail: String
        let detailTint: Color
        if let holiday = holidays.first {
            detail = "\(model.localized(holiday.type == "holiday" ? "休" : "班")) \(holiday.name)"
            detailTint = Self.holidayColor(holiday)
        } else {
            detail = dayCourses.isEmpty ? "无课" : "\(dayCourses.count) 门课"
            detailTint = monthTextColor(
                selected: isSelected,
                inMonth: inMonth,
                holidays: holidays
            )
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(isToday ? "今天 \(calendar.component(.day, from: day))" : "\(calendar.component(.day, from: day))")
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showsDetails {
                if deadlineEvents.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: holidays.isEmpty ? .regular : .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : detailTint)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(deadlineEvents.prefix(3))) { event in
                            Text(event.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? AppTheme.onPrimary : event.tint)
                                .frame(maxWidth: .infinity, minHeight: 13, alignment: .leading)
                        }
                        if deadlineEvents.count > 3 {
                            Button {
                                selectedDate = day
                                presentedMonthAgenda = CalendarAgendaSelection(
                                    date: day,
                                    events: deadlineEvents.map(calendarAgendaDisplayItem)
                                )
                            } label: {
                                Text("+\(deadlineEvents.count - 3)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(
                                        isSelected ? AppTheme.onPrimary : AppTheme.secondaryText
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                model.localizedFormat(
                                    "查看其余 %lld 项全天日程",
                                    deadlineEvents.count - 3
                                )
                            )
                        }
                    }
                }
            } else {
                HStack(spacing: 3) {
                    if !holidays.isEmpty {
                        Circle().frame(width: 4, height: 4)
                    }
                    ForEach(Array(deadlineEvents.prefix(3))) { event in
                        Circle()
                            .fill(isSelected ? AppTheme.onPrimary : event.tint)
                            .frame(width: 4, height: 4)
                    }
                    ForEach(0 ..< min(dayCourses.count, 3), id: \.self) { _ in
                        Circle().frame(width: 4, height: 4)
                    }
                }
                .frame(height: 8)
                .transition(.opacity)
            }
        }
        .foregroundStyle(monthTextColor(selected: isSelected, inMonth: inMonth, holidays: holidays))
        .padding(6)
        .frame(
            maxWidth: .infinity,
            minHeight: showsDetails ? 94 : 46,
            alignment: .topLeading
        )
        .background(monthCellColor(selected: isSelected, inMonth: inMonth, courseCount: dayCourses.count))
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        deadlineKind.map { allDayEventTint($0) }
                            ?? (isToday ? Self.nowRed : AppTheme.border),
                        lineWidth: deadlineKind != nil || isToday ? 2 : 1
                    )
                if deadlineKind != nil, isToday {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Self.nowRed, lineWidth: 1)
                        .padding(2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { selectedDate = day }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dayAccessibilityLabel(day))
        .accessibilityValue(deadlineKind?.rawValue ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selectedDate = day }
    }

    private var yearView: some View {
        #if os(macOS)
        return desktopYearView
        #else
        let year = calendar.component(.year, from: selectedDate)
        let months = (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
        let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)]
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(months, id: \.self) { month in
                    miniMonth(month)
                }
            }
        }
        #endif
    }

    #if os(macOS)
    private var desktopYearView: some View {
        let year = calendar.component(.year, from: selectedDate)
        let months = (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }

        return GeometryReader { proxy in
            let layout = TeachingCalendarLogic.desktopYearLayout(availableHeight: proxy.size.height)
            let columns = Array(
                repeating: GridItem(.flexible(minimum: 120), spacing: layout.columnSpacing),
                count: 4
            )

            LazyVGrid(columns: columns, alignment: .leading, spacing: layout.rowSpacing) {
                ForEach(months, id: \.self) { month in
                    desktopMiniMonth(month, layout: layout)
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("calendar.desktop.year-grid")
    }

    private func desktopMiniMonth(
        _ month: Date,
        layout: TeachingCalendarLogic.DesktopYearLayout
    ) -> some View {
        let days = monthGridDates(containing: month)
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: layout.gridSpacing),
            count: 7
        )

        return VStack(alignment: .leading, spacing: layout.monthContentSpacing) {
            Text(monthFormatter.string(from: month))
                .font(.system(size: layout.monthTitleFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(height: layout.monthTitleHeight, alignment: .leading)

            LazyVGrid(columns: columns, spacing: layout.gridSpacing) {
                ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(model.localized(label))
                        .font(.system(size: layout.weekdayFontSize, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: layout.weekdayHeight,
                            maxHeight: layout.weekdayHeight
                        )
                }

                ForEach(days, id: \.self) { day in
                    desktopYearDay(day, month: month, layout: layout)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: layout.monthHeight,
            maxHeight: layout.monthHeight,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func desktopYearDay(
        _ day: Date,
        month: Date,
        layout: TeachingCalendarLogic.DesktopYearLayout
    ) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        if inMonth {
            let dayCourses = courses(on: day)
            let holidays = holidayItems(on: day)
            let isToday = sameDay(day, .now)
            let deadlineKind = CalendarDeadlinePresentation.preferredDeadlineKind(
                in: allDayEvents(on: day)
            )
            let isSelected = sameDay(selectedDate, day)
            let baseColor = dayCourses.isEmpty
                ? Color.clear
                : AppTheme.primary.opacity(
                    TeachingCalendarLogic.yearCourseOpacity(courseCount: dayCourses.count)
                )

            let cell = VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: day))")
                    .monospacedDigit()
                if let item = holidays.first {
                    Text(model.localized(item.type == "holiday" ? "休" : "班"))
                        .font(.system(size: layout.holidayFontSize, weight: .semibold))
                        .foregroundStyle(
                            isSelected || isToday ? AppTheme.onPrimary : Self.holidayColor(item)
                        )
                }
            }
            .font(.system(size: layout.dayFontSize, weight: .medium))
            .foregroundStyle(
                isSelected || isToday
                    ? AppTheme.onPrimary
                    : (dayCourses.isEmpty ? AppTheme.text : AppTheme.onPrimary)
            )
            .frame(
                maxWidth: .infinity,
                minHeight: layout.dayCellHeight,
                maxHeight: layout.dayCellHeight
            )
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(baseColor)
                    if isSelected {
                        Circle()
                            .fill(AppTheme.selectedDate)
                            .frame(
                                width: layout.selectionDiameter,
                                height: layout.selectionDiameter
                            )
                    } else if isToday {
                        Circle()
                            .fill(Self.nowRed)
                            .frame(
                                width: layout.selectionDiameter,
                                height: layout.selectionDiameter
                            )
                    }
                }
            }
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            deadlineKind.map { allDayEventTint($0) } ?? Color.clear,
                            lineWidth: deadlineKind == nil ? 0 : 2
                        )
                    if isSelected, isToday {
                        Circle()
                            .stroke(Self.nowRed, lineWidth: 1)
                            .frame(
                                width: layout.selectionDiameter - 3,
                                height: layout.selectionDiameter - 3
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayAccessibilityLabel(day))
            .accessibilityValue(deadlineKind?.rawValue ?? "")
            .accessibilityAddTraits(.isButton)

            cell
                .accessibilityAction {
                    selectedDate = day
                    yearPopoverDate = day
                    yearPopoverLocation = nil
                }
                .accessibilityAction(named: Text("查看月份")) {
                    selectedDate = day
                    withAnimation(Self.viewAnimation) { mode = .month }
                }
                .gesture(
                    SpatialTapGesture(
                        count: 2,
                        coordinateSpace: .named(Self.calendarCoordinateSpace)
                    )
                    .exclusively(
                        before: SpatialTapGesture(
                            count: 1,
                            coordinateSpace: .named(Self.calendarCoordinateSpace)
                        )
                    )
                    .onEnded { value in
                        switch value {
                        case .first:
                            selectedDate = day
                            withAnimation(Self.viewAnimation) { mode = .month }
                        case let .second(tap):
                            selectedDate = day
                            yearPopoverDate = day
                            yearPopoverLocation = tap.location
                        }
                    }
                )
        } else {
            Color.clear.frame(height: layout.dayCellHeight)
        }
    }
    #endif

    private func miniMonth(_ month: Date) -> some View {
        let days = monthGridDates(containing: month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)
        return VStack(alignment: .leading, spacing: 6) {
            Text(monthFormatter.string(from: month)).font(.headline)
            LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(model.localized(label))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                ForEach(days, id: \.self) { day in
                    yearDayButton(day, month: month)
                }
            }
        }
    }

    @ViewBuilder
    private func yearDayButton(_ day: Date, month: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        if inMonth {
            let dayCourses = courses(on: day)
            let holidays = holidayItems(on: day)
            let isToday = sameDay(day, .now)
            let deadlineKind = CalendarDeadlinePresentation.preferredDeadlineKind(
                in: allDayEvents(on: day)
            )
            let isSelected = sameDay(selectedDate, day)
            let cell = VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: day))")
                if let item = holidays.first {
                    Text(model.localized(item.type == "holiday" ? "休" : "班"))
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : Self.holidayColor(item))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.text)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(yearCellColor(selected: isSelected, courseCount: dayCourses.count))
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            deadlineKind.map { allDayEventTint($0) }
                                ?? (isToday ? Self.nowRed : AppTheme.border),
                            lineWidth: deadlineKind != nil || isToday ? 2 : 1
                        )
                    if CalendarDeadlinePresentation.showsSecondaryTodayIndicator(
                        isToday: isToday,
                        deadlineKind: deadlineKind
                    ) {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(Self.nowRed, lineWidth: 1)
                            .padding(2)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayAccessibilityLabel(day))
            .accessibilityValue(deadlineKind?.rawValue ?? "")
            .accessibilityAddTraits(.isButton)
            #if os(macOS)
            cell
                .accessibilityAction {
                    selectedDate = day
                    yearPopoverDate = day
                    yearPopoverLocation = nil
                }
                .accessibilityAction(named: Text("查看月份")) {
                    selectedDate = day
                    withAnimation(Self.viewAnimation) { mode = .month }
                }
                .gesture(
                    SpatialTapGesture(
                        count: 2,
                        coordinateSpace: .named(Self.calendarCoordinateSpace)
                    )
                    .exclusively(
                        before: SpatialTapGesture(
                            count: 1,
                            coordinateSpace: .named(Self.calendarCoordinateSpace)
                        )
                    )
                    .onEnded { value in
                        switch value {
                        case .first:
                            selectedDate = day
                            withAnimation(Self.viewAnimation) { mode = .month }
                        case let .second(tap):
                            selectedDate = day
                            yearPopoverDate = day
                            yearPopoverLocation = tap.location
                        }
                    }
                )
            #else
            cell
            .accessibilityAction {
                yearPopoverDate = day
                yearPopoverLocation = nil
            }
            .gesture(
                SpatialTapGesture(coordinateSpace: .named(Self.calendarCoordinateSpace))
                    .onEnded { value in
                        yearPopoverDate = day
                        yearPopoverLocation = value.location
                    }
            )
            #endif
        } else {
            Color.clear.frame(height: 30)
        }
    }

    @ViewBuilder
    private var yearPopoverOverlay: some View {
        if let day = yearPopoverDate {
            GeometryReader { proxy in
                let panelWidth = min(300, max(220, proxy.size.width - 32))
                let panelHeight = estimatedYearPopoverHeight(day, availableHeight: proxy.size.height)
                let fallback = CGPoint(x: proxy.size.width / 2, y: min(220, proxy.size.height / 2))
                let location = yearPopoverLocation ?? fallback
                let originX = min(
                    max(16, location.x - panelWidth / 2),
                    max(16, proxy.size.width - panelWidth - 16)
                )
                let belowY = location.y + 12
                let originY = belowY + panelHeight <= proxy.size.height - 16
                    ? belowY
                    : max(16, location.y - panelHeight - 12)

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismissYearPopover)

                    ScrollView {
                        selectedDayPopover(day)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: panelWidth - 32)
                    .frame(maxHeight: panelHeight - 32, alignment: .topLeading)
                    .padding(16)
                    .background(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
                    .offset(x: originX, y: originY)
                    .contentShape(Rectangle())
                    .onTapGesture { }
                }
            }
            .zIndex(20)
        }
    }

    private func selectedDayPopover(_ day: Date) -> some View {
        let dayCourses = courses(on: day)
        let holidays = holidayItems(on: day)
        let assignments = assignmentItems(on: day)
        let schoolNotices = schoolNoticeItems(on: day)
        let publicDeadlines = otherPublicDeadlineItems(on: day)
        return VStack(alignment: .leading, spacing: 10) {
            Text(fullDateFormatter.string(from: day)).font(.headline)
            ForEach(holidays) { item in
                Text("\(model.localized(item.type == "holiday" ? "休" : "班")) \(item.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Self.holidayColor(item))
            }
            if dayCourses.isEmpty {
                Text("暂无课程").foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(dayCourses) { course in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.subheadline.weight(.semibold))
                        Text(
                            [course.timeRange, CalendarTimelineLogic.courseMetadata(course)]
                                .filter { !$0.isEmpty }
                                .joined(separator: "  ·  ")
                        )
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            if !assignments.isEmpty {
                compactAssignmentRows(assignments)
            }
            if !schoolNotices.isEmpty {
                compactSchoolNoticeRows(schoolNotices)
            }
            if !publicDeadlines.isEmpty {
                compactPublicDeadlineRows(publicDeadlines)
            }
            Divider()
            HStack(spacing: 8) {
                yearPopoverNavigationButton("日", mode: .day, day: day)
                yearPopoverNavigationButton("周", mode: .week, day: day)
                yearPopoverNavigationButton("月", mode: .month, day: day)
            }
        }
    }

    private func yearPopoverNavigationButton(
        _ title: String,
        mode targetMode: CalendarMode,
        day: Date
    ) -> some View {
        Button(model.localized("\(title)视图")) {
            withAnimation(Self.viewAnimation) {
                selectedDate = day
                mode = targetMode
            }
            dismissYearPopover()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func selectedDaySummary(_ day: Date) -> some View {
        let dayCourses = courses(on: day)
        let holidays = holidayItems(on: day)
        let assignments = assignmentItems(on: day)
        let schoolNotices = schoolNoticeItems(on: day)
        let publicDeadlines = otherPublicDeadlineItems(on: day)
        return VStack(alignment: .leading, spacing: 8) {
            Text(fullDateFormatter.string(from: day)).font(.headline)
            ForEach(holidays) { item in
                Text("\(model.localized(item.type == "holiday" ? "休" : "班")) \(item.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Self.holidayColor(item))
            }
            if dayCourses.isEmpty {
                Text("暂无课程").foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(dayCourses) { course in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(course.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(course.timeRange).font(.caption.monospacedDigit())
                        }
                        let metadata = CalendarTimelineLogic.courseMetadata(course)
                        if !metadata.isEmpty {
                            Text(metadata)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
            if !assignments.isEmpty {
                compactAssignmentRows(assignments)
            }
            if !schoolNotices.isEmpty {
                compactSchoolNoticeRows(schoolNotices)
            }
            if !publicDeadlines.isEmpty {
                compactPublicDeadlineRows(publicDeadlines)
            }
        }
        .padding(.top, 4)
    }

    private func compactAssignmentRows(_ items: [AssignmentDeadlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("课程作业 DDL", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.assignment)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(deadlineTime(item.deadline))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding(9)
        .background(AppTheme.assignment.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("calendar.regular.day-detail.assignments")
    }

    private func compactSchoolNoticeRows(_ items: [PublicDeadlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("校内竞赛通知", systemImage: "building.columns")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.schoolNotice)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(deadlineTime(item.deadline))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding(9)
        .background(AppTheme.schoolNotice.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("calendar.regular.day-detail.school-notices")
    }

    private func compactPublicDeadlineRows(_ items: [PublicDeadlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("公开活动 DDL", systemImage: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.publicDeadline)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(deadlineTime(item.deadline))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding(9)
        .background(AppTheme.publicDeadline.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("calendar.regular.day-detail.public-deadlines")
    }

    @ViewBuilder
    private var almanacSummary: some View {
        let date = StrictContractDateParser.string(from: selectedDate)
        VStack(alignment: .leading, spacing: 10) {
            Label("黄历信息", systemImage: "calendar.badge.clock")
                .font(.headline)
            if dailyInfo.loadingAlmanacDates.contains(date), dailyInfo.almanacByDate[date] == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在查询…")
                }
                .foregroundStyle(AppTheme.secondaryText)
            } else if let error = dailyInfo.almanacErrors[date], dailyInfo.almanacByDate[date] == nil {
                Button {
                    Task {
                        await dailyInfo.loadAlmanac(date: date, sampleMode: model.isSampleMode, force: true)
                    }
                } label: {
                    Label("\(error)，点击重试", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)
            } else if let info = dailyInfo.almanacByDate[date] {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        almanacDateBlock(info)
                        almanacPill("岁次", value: "\(info.ganzhiYear)年 · 肖\(info.zodiac)")
                        almanacPill("月柱", value: "\(info.ganzhiMonth)月")
                        almanacPill("日柱", value: "\(info.ganzhiDay)日")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        almanacDateBlock(info)
                        HStack(spacing: 8) {
                            almanacPill("岁次", value: "\(info.ganzhiYear)年 · 肖\(info.zodiac)")
                            almanacPill("月柱", value: "\(info.ganzhiMonth)月")
                            almanacPill("日柱", value: "\(info.ganzhiDay)日")
                        }
                    }
                }
                if let yi = info.yi {
                    almanacAdvice("宜", value: yi, color: AppTheme.primary)
                }
                if let ji = info.ji {
                    almanacAdvice("忌", value: ji, color: AppTheme.danger)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("民俗信息仅供参考")
                    Spacer()
                    Link("农历：UAPI", destination: URL(string: "https://uapis.cn/docs/api-reference/get-misc-lunartime")!)
                    Link("宜忌：Timeless", destination: URL(string: "https://api.timelessq.com/docs/api-15277838")!)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("民俗信息仅供参考")
                    HStack {
                        Link("农历：UAPI", destination: URL(string: "https://uapis.cn/docs/api-reference/get-misc-lunartime")!)
                        Link("宜忌：Timeless", destination: URL(string: "https://api.timelessq.com/docs/api-15277838")!)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
            Text("校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考。")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func almanacAdvice(_ title: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            Text(value)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var assignmentSummary: some View {
        let date = StrictContractDateParser.string(from: selectedDate)
        let items = calendarDeadlines.assignmentsByDate[date] ?? []
        VStack(alignment: .leading, spacing: 10) {
            Label("课程作业 DDL", systemImage: "checklist")
                .font(.headline)
            if items.isEmpty {
                if let reason = calendarDeadlines.assignmentUnavailableByDate[date] {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text("当天没有课程作业截止事项")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(
                                [item.courseName, item.status]
                                    .compactMap { $0 }
                                    .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Text(deadlineTime(item.deadline))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(10)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                Text("第三方来源：北京邮电大学云课堂")
                Spacer()
                Link("打开作业列表", destination: CalendarDeadlineSources.assignments)
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    @ViewBuilder
    private var deadlineSummary: some View {
        let date = StrictContractDateParser.string(from: selectedDate)
        let snapshot = calendarDeadlines.publicByDate[date]
        let items = (snapshot?.items ?? []).filter(deadlineIsEnabled)
        VStack(alignment: .leading, spacing: 10) {
            Label("活动 DDL", systemImage: "flag.checkered")
                .font(.headline)
            if calendarDeadlines.loadingPublicDates.contains(date), snapshot == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在同步竞赛、夏令营与黑客松…")
                }
                .foregroundStyle(AppTheme.secondaryText)
            } else if let error = calendarDeadlines.publicErrors[date], snapshot == nil {
                Button {
                    Task {
                        await calendarDeadlines.loadPublic(
                            date: date,
                            sampleMode: model.isSampleMode,
                            force: true
                        )
                    }
                } label: {
                    Label("\(error)，点击重试", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)
            } else if items.isEmpty {
                Text("当天没有已收录的活动截止事项")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(items) { item in
                    publicDeadlineRow(item)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("第三方来源")
                    Spacer()
                    Link("主数据：Contest DDL", destination: CalendarDeadlineSources.primaryPage)
                    Link("备用 API", destination: CalendarDeadlineSources.backup)
                    Link("校内竞赛通知", destination: CalendarDeadlineSources.schoolNotices)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("第三方来源")
                    HStack {
                        Link("主数据：Contest DDL", destination: CalendarDeadlineSources.primaryPage)
                        Link("备用 API", destination: CalendarDeadlineSources.backup)
                        Link("校内竞赛通知", destination: CalendarDeadlineSources.schoolNotices)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func publicDeadlineRow(_ item: PublicDeadlineItem) -> some View {
        if let url = item.officialURL {
            Link(destination: url) {
                publicDeadlineRowContent(item)
            }
            .buttonStyle(.plain)
        } else {
            publicDeadlineRowContent(item)
        }
    }

    private func publicDeadlineRowContent(_ item: PublicDeadlineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(
                    item.source == .schoolNotice ? AppTheme.schoolNotice : AppTheme.publicDeadline
                )
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text([deadlineCategoryTitle(item), item.organizer].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 8)
            Text(deadlineTime(item.deadline))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(10)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    private func deadlineIsEnabled(_ item: PublicDeadlineItem) -> Bool {
        CalendarDeadlinePresentation.isVisible(
            item,
            competitionEnabled: model.competitionDeadlinesEnabled,
            schoolNoticeEnabled: model.schoolContestNoticesEnabled,
            summerCampEnabled: model.summerCampDeadlinesEnabled,
            hackathonEnabled: model.hackathonDeadlinesEnabled
        )
    }

    private func deadlineCategoryTitle(_ item: PublicDeadlineItem) -> String {
        model.localized(item.source == .schoolNotice ? item.source.title : item.kind.title)
    }

    private func deadlineTime(_ value: String) -> String {
        guard value.count >= 16 else { return value }
        let start = value.index(value.startIndex, offsetBy: 11)
        return String(value[start...].prefix(5))
    }

    private func almanacDateBlock(_ info: AlmanacInfo) -> some View {
        let festival = [info.solarTerm, info.lunarFestival, info.solarFestival]
            .compactMap { $0 }
            .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            Text(info.weekday).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("农历 \(info.lunarDate)").font(.subheadline.weight(.semibold))
            if !festival.isEmpty {
                Text(festival).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
    }

    private func almanacPill(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    private func calendarAgendaDisplayItem(
        _ event: CalendarAllDayEvent
    ) -> CalendarAgendaDisplayItem {
        let kind: CalendarAgendaItemKind = switch event.kind {
        case .holiday: .holiday
        case .workday: .workday
        case .assignment: .assignment
        case .schoolNotice: .schoolNotice
        case .publicDeadline: .publicDeadline
        }
        return CalendarAgendaDisplayItem(
            id: event.id,
            title: event.title,
            categoryKey: allDayEventCategoryKey(event.kind),
            kind: kind
        )
    }

    private func calendarAgendaDisplayItem(
        _ event: CalendarMonthDeadlineEvent
    ) -> CalendarAgendaDisplayItem {
        CalendarAgendaDisplayItem(
            id: event.id,
            title: event.title,
            categoryKey: event.categoryKey,
            kind: event.agendaKind
        )
    }

    #if os(macOS)
    private func calendarAgendaDisplayItem(
        _ event: DesktopMonthEvent
    ) -> CalendarAgendaDisplayItem {
        let kind: CalendarAgendaItemKind
        let categoryKey: String
        switch event.kind {
        case .course:
            kind = .course
            categoryKey = "课程详情"
        case .holiday:
            kind = .holiday
            categoryKey = "法定节假日"
        case .workday:
            kind = .workday
            categoryKey = "调休工作日"
        case .assignment:
            kind = .assignment
            categoryKey = "课程作业 DDL"
        case .schoolNotice:
            kind = .schoolNotice
            categoryKey = "校内竞赛通知"
        case .publicDeadline:
            kind = .publicDeadline
            categoryKey = "公开活动 DDL"
        }
        return CalendarAgendaDisplayItem(
            id: event.id,
            title: event.title,
            categoryKey: categoryKey,
            kind: kind
        )
    }
    #endif

    private func calendarAgendaTint(_ kind: CalendarAgendaItemKind) -> Color {
        switch kind {
        case .course: AppTheme.primary
        case .holiday: Self.holidayRed
        case .workday: AppTheme.primary
        case .assignment: AppTheme.assignment
        case .schoolNotice: AppTheme.schoolNotice
        case .publicDeadline: AppTheme.publicDeadline
        }
    }

    private func calendarAgendaDialog(
        _ selection: CalendarAgendaSelection,
        titleKey: String,
        accessibilityIdentifier: String,
        dismiss: @escaping () -> Void
    ) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.localized(titleKey))
                                .font(.headline)
                            Text(fullDateFormatter.string(from: selection.date))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.localized("关闭全天日程"))
                    }

                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selection.events) { event in
                                let tint = calendarAgendaTint(event.kind)
                                HStack(alignment: .top, spacing: 9) {
                                    Circle()
                                        .fill(tint)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(model.localized(event.categoryKey))
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    tint.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: min(360, max(proxy.size.height - 180, 140)))
                }
                .padding(16)
                .frame(maxWidth: 400)
                .background(AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.22), radius: 20, y: 8)
                .padding(20)
                .contentShape(Rectangle())
                .onTapGesture { }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityIdentifier)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .zIndex(40)
    }

    private func allDayEventCategoryKey(_ kind: CalendarAllDayEventKind) -> String {
        switch kind {
        case .holiday: "法定节假日"
        case .workday: "调休工作日"
        case .assignment: "课程作业 DDL"
        case .schoolNotice: "校内竞赛通知"
        case .publicDeadline: "公开活动 DDL"
        }
    }

    @ViewBuilder
    private func allDayItems(days: [Date]) -> some View {
        let dayItems = days.compactMap { day -> (Date, [CalendarAllDayEvent])? in
            let items = allDayEvents(on: day)
            return items.isEmpty ? nil : (day, items)
        }
        if !dayItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("全天")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    ForEach(dayItems, id: \.0) { day, items in
                        let first = items[0]
                        let hiddenCount = items.count - 1
                        Button {
                            selectedDate = day
                            presentedTimelineAgenda = CalendarAgendaSelection(
                                date: day,
                                events: items.map(calendarAgendaDisplayItem)
                            )
                        } label: {
                            Text(
                                "\(monthDayCompactFormatter.string(from: day)) · "
                                    + first.title
                                    + (hiddenCount > 0 ? " +\(hiddenCount)" : "")
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(allDayEventTint(first.kind))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(allDayEventTint(first.kind).opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(monthDayCompactFormatter.string(from: day))，全天，"
                                + first.title
                                + (hiddenCount > 0 ? "，+\(hiddenCount)" : "")
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("calendar.regular.all-day")
        }
    }

    private func allDayEventTint(_ kind: CalendarAllDayEventKind) -> Color {
        switch kind {
        case .holiday: Self.holidayRed
        case .workday: AppTheme.primary
        case .assignment: AppTheme.assignment
        case .schoolNotice: AppTheme.schoolNotice
        case .publicDeadline: AppTheme.publicDeadline
        }
    }

    private var periodTitle: String {
        TeachingCalendarLogic.periodTitle(
            for: selectedDate,
            modeRawValue: mode.rawValue,
            language: model.appLanguage,
            calendar: calendar
        )
    }

    private func timelineDay(_ date: Date) -> CalendarTimelineDay {
        CalendarTimelineDay(
            date: date,
            courses: courses(on: date),
            holidays: holidayItems(on: date),
            allDayEvents: allDayEvents(on: date)
        )
    }

    private func courses(on date: Date) -> [Course] {
        guard
            let schedule = model.schedule,
            let start = StrictContractDateParser.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.courses(on: date, termStart: start, courses: schedule.courses)
    }

    private func holidayItems(on date: Date) -> [HolidayItem] {
        let year = calendar.component(.year, from: date)
        let target = StrictContractDateParser.string(from: date)
        return model.holidayItems(for: year).filter { $0.date == target }
    }

    private func assignmentItems(on date: Date) -> [AssignmentDeadlineItem] {
        calendarDeadlines.assignmentsByDate[StrictContractDateParser.string(from: date)] ?? []
    }

    private func schoolNoticeItems(on date: Date) -> [PublicDeadlineItem] {
        guard model.schoolContestNoticesEnabled else { return [] }
        let dateKey = StrictContractDateParser.string(from: date)
        return (calendarDeadlines.publicByDate[dateKey]?.items ?? []).filter {
            $0.source == .schoolNotice
        }
    }

    private func otherPublicDeadlineItems(on date: Date) -> [PublicDeadlineItem] {
        let dateKey = StrictContractDateParser.string(from: date)
        return (calendarDeadlines.publicByDate[dateKey]?.items ?? []).filter {
            $0.source != .schoolNotice && deadlineIsEnabled($0)
        }
    }

    private func allDayEvents(on date: Date) -> [CalendarAllDayEvent] {
        let dateKey = StrictContractDateParser.string(from: date)
        let holidays = holidayItems(on: date).map { holiday in
            CalendarAllDayEvent(
                id: "\(dateKey)-holiday-\(holiday.id)",
                title: "\(model.localized(holiday.type == "holiday" ? "休" : "班")) \(holiday.name)",
                kind: holiday.type == "holiday" ? .holiday : .workday
            )
        }
        let assignments = assignmentItems(on: date).map { assignment in
            CalendarAllDayEvent(
                id: "\(dateKey)-assignment-\(assignment.id)",
                title: assignment.title,
                kind: .assignment
            )
        }
        let schoolNotices = schoolNoticeItems(on: date).map { notice in
            CalendarAllDayEvent(
                id: "\(dateKey)-school-\(notice.id)",
                title: notice.name,
                kind: .schoolNotice
            )
        }
        let publicDeadlines = otherPublicDeadlineItems(on: date).map { item in
            CalendarAllDayEvent(
                id: "\(dateKey)-public-\(item.id)",
                title: item.name,
                kind: .publicDeadline
            )
        }
        return holidays + assignments + schoolNotices + publicDeadlines
    }

    private func weekDates() -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func monthGridDates(containing date: Date) -> [Date] {
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0 ..< 42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var visibleHolidayYears: Set<Int> {
        switch mode {
        case .day:
            return [calendar.component(.year, from: selectedDate)]
        case .week:
            return Set(weekDates().map { calendar.component(.year, from: $0) })
        case .month:
            return Set(monthGridDates(containing: selectedDate).map { calendar.component(.year, from: $0) })
        case .year:
            return [calendar.component(.year, from: selectedDate)]
        }
    }

    private var holidayStatus: String? {
        visibleHolidayYears.compactMap { model.holidayStatusByYear[$0] }.first
    }

    private func ensureVisibleHolidays() {
        visibleHolidayYears.forEach { model.ensureHolidays(for: $0) }
    }

    private var visibleDailyDetailDates: [Date] {
        switch mode {
        case .day: [selectedDate]
        case .week: weekDates()
        case .month: monthGridDates(containing: selectedDate)
        case .year: TeachingCalendarLogic.datesInYear(containing: selectedDate, calendar: calendar)
        }
    }

    private var dailyDetailsLoadID: CalendarDailyDetailsLoadID {
        CalendarDailyDetailsLoadID(
            dates: visibleDailyDetailDates.map { StrictContractDateParser.string(from: $0) },
            almanacDate: mode == .month ? StrictContractDateParser.string(from: selectedDate) : nil,
            sampleMode: model.isSampleMode,
            loadsAlmanac: model.almanacEnabled,
            loadsPublicDeadlines: model.hasEnabledPublicDeadlines
        )
    }

    @MainActor
    private func loadVisibleDailyDetails() async {
        let request = dailyDetailsLoadID
        async let events: Void = calendarDeadlines.loadCalendarEvents(
            dates: request.dates,
            sampleMode: request.sampleMode,
            includesPublicDeadlines: request.loadsPublicDeadlines
        )
        async let almanac: Void = loadVisibleAlmanac(request)
        _ = await (events, almanac)
    }

    @MainActor
    private func loadVisibleAlmanac(_ request: CalendarDailyDetailsLoadID) async {
        guard request.loadsAlmanac, let date = request.almanacDate, !Task.isCancelled else { return }
        await dailyInfo.loadAlmanac(date: date, sampleMode: request.sampleMode)
    }

    private func moveDate(_ direction: Int) {
        if let moved = TeachingCalendarLogic.movedDate(
            from: selectedDate,
            unit: navigationUnit,
            direction: direction,
            calendar: calendar
        ) {
            withAnimation(Self.viewAnimation) { selectedDate = moved }
        }
    }

    private var navigationUnit: TeachingCalendarLogic.NavigationUnit {
        switch mode {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }

    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard mode != .year,
                      let direction = TeachingCalendarLogic.swipeDirection(
                          horizontalTranslation: value.translation.width,
                          verticalTranslation: value.translation.height,
                          predictedHorizontalTranslation: value.predictedEndTranslation.width
                      )
                else { return }
                moveDate(direction)
            }
    }

    private var modeSelection: Binding<CalendarMode> {
        Binding(
            get: { mode },
            set: { newMode in
                #if os(macOS)
                mode = newMode
                #else
                withAnimation(Self.viewAnimation) { mode = newMode }
                #endif
            }
        )
    }

    private var datePickerSelection: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { newDate in
                withAnimation(Self.viewAnimation) { selectedDate = newDate }
                showingDatePicker = false
            }
        )
    }

    private func dismissYearPopover() {
        yearPopoverDate = nil
        yearPopoverLocation = nil
    }

    private func estimatedYearPopoverHeight(_ day: Date, availableHeight: CGFloat) -> CGFloat {
        let rows = max(
            1,
            holidayItems(on: day).count
                + courses(on: day).count
                + assignmentItems(on: day).count
                + schoolNoticeItems(on: day).count
                + otherPublicDeadlineItems(on: day).count
        )
        return min(max(160, CGFloat(rows * 48 + 124)), min(380, max(160, availableHeight - 32)))
    }

    private func monthCellColor(selected: Bool, inMonth: Bool, courseCount: Int) -> Color {
        if selected { return AppTheme.selectedDate }
        if !inMonth { return AppTheme.surface }
        guard courseCount > 0 else { return AppTheme.background }
        return AppTheme.primary.opacity(min(0.08 + Double(courseCount) * 0.10, 0.48))
    }

    private func monthTextColor(selected: Bool, inMonth: Bool, holidays: [HolidayItem]) -> Color {
        if selected { return AppTheme.onPrimary }
        if !inMonth { return AppTheme.secondaryText.opacity(0.55) }
        if let holiday = holidays.first { return Self.holidayColor(holiday) }
        return AppTheme.text
    }

    private func yearCellColor(selected: Bool, courseCount: Int) -> Color {
        if selected { return AppTheme.selectedDate }
        guard courseCount > 0 else { return AppTheme.background }
        return AppTheme.primary.opacity(TeachingCalendarLogic.yearCourseOpacity(courseCount: courseCount))
    }

    private func dayAccessibilityLabel(_ day: Date) -> String {
        let today = sameDay(day, .now) ? model.localized("今天") : ""
        let holidays = holidayItems(on: day).map(\.name).joined(separator: "，")
        let dayCourses = courses(on: day).map { "\($0.timeRange)\($0.name)" }.joined(separator: "，")
        return [today, fullDateFormatter.string(from: day), holidays, dayCourses.isEmpty ? "无课" : dayCourses]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
    }

    private func sameDay(_ left: Date, _ right: Date) -> Bool {
        calendar.isDate(left, inSameDayAs: right)
    }

    private static func holidayColor(_ item: HolidayItem) -> Color {
        item.type == "holiday" ? holidayRed : AppTheme.primary
    }

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    private static let nowRed = AppTheme.danger
    private static let holidayRed = AppTheme.danger
    private static let calendarCoordinateSpace = "teaching-calendar"
    private static let viewAnimation = Animation.easeInOut(duration: 0.24)
    private static let monthExpansionAnimation = Animation.easeInOut(duration: 0.28)
    private var fullDateFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "yyyy年M月d日 EEEE", englishFormat: "EEEE, MMMM d, yyyy")
    }

    private var controlDateFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "yyyy-MM-dd", englishFormat: "yyyy-MM-dd")
    }

    private var monthDayCompactFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "M月d日", englishFormat: "MMM d")
    }

    private var monthFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "M月", englishFormat: "MMM")
    }

    private func localizedDateFormatter(
        chineseFormat: String,
        englishFormat: String
    ) -> DateFormatter {
        let format = model.appLanguage.resolvedResourceName == "en"
            ? englishFormat
            : chineseFormat
        return Self.dateFormatter(format, locale: model.appLanguage.locale)
    }

    private static func dateFormatter(_ format: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }
}
