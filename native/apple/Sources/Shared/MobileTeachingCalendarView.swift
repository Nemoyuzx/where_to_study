#if os(iOS)
import SwiftUI
import UIKit

private enum MobileCalendarHaptics {
    @MainActor
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

private enum MobileCalendarMode: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

private struct MobileCalendarDetailSelection: Identifiable {
    enum Content {
        case day
        case course(Course)
        case holiday(HolidayItem)
    }

    let id = UUID()
    let date: Date
    let content: Content
}

private struct MobileMonthEvent: Identifiable {
    let id: String
    let title: String
    let tint: Color
    let detail: MobileCalendarDetailSelection.Content
}

struct MobileTeachingCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TeachingCalendarSessionState
    @State private var presentedDetail: MobileCalendarDetailSelection?
    @State private var pageDirection = 1
    @State private var isHorizontalPaging = false
    @State private var suppressesEventSelection = false
    @State private var monthDragTranslation: CGFloat = 0
    @State private var monthDragAxis: TeachingCalendarLogic.GestureAxis?

    private let calendar = Calendar.shanghai

    private var selectedDate: Date {
        get { session.selectedDate }
        nonmutating set { session.selectedDate = newValue }
    }

    private var mode: MobileCalendarMode {
        get { MobileCalendarMode(rawValue: session.modeRawValue) ?? .week }
        nonmutating set { session.modeRawValue = newValue.rawValue }
    }

    private var isMonthExpanded: Bool {
        get { session.isMonthExpanded }
        nonmutating set { session.isMonthExpanded = newValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactHeader
                    .accessibilityIdentifier("layout.calendar.compact")
                statusArea
                ZStack {
                    content
                        .id(contentIdentity)
                        .transition(pageTransition)
                }
                .clipped()
                .animation(Self.pageAnimation, value: contentIdentity)
            }
            .background(AppTheme.background)
            .ignoresSafeArea(.container, edges: .bottom)
            .accessibilityIdentifier("screen.calendar")
            .navigationBarHidden(true)
        }
        .sheet(item: $presentedDetail) { selection in
            detailSheet(selection)
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: ensureVisibleHolidays)
        .onChange(of: selectedDate) { _ in ensureVisibleHolidays() }
        .onChange(of: mode) { _ in ensureVisibleHolidays() }
    }

    private var compactHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(periodTitle)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(periodTitle)
                .accessibilityIdentifier("calendar.mobile.period-label")

                Spacer(minLength: 8)

                Button("今天") {
                    navigate(to: .now)
                }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityIdentifier("calendar.mobile.today")

                Button { moveDate(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 36)
                }
                .accessibilityLabel("上一时间段")

                Button { moveDate(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 36)
                }
                .accessibilityLabel("下一时间段")

                actionMenu
            }

            Picker("日历视图", selection: modeSelection) {
                ForEach(MobileCalendarMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("calendar.mobile.mode")

            if mode == .day || mode == .week {
                weekDateStrip
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, mode == .day || mode == .week ? 8 : 6)
        .background(AppTheme.surface)
    }

    private var actionMenu: some View {
        Menu {
            Button {
                model.refreshSchedule()
            } label: {
                Label(
                    model.isRefreshingSchedule ? "正在获取…" : "获取/刷新个人课表",
                    systemImage: "arrow.clockwise"
                )
                .contentTransition(.opacity)
            }
            .disabled(model.isRefreshingSchedule || model.isImportingCalendar)

            Button {
                model.importScheduleToCalendar()
            } label: {
                Label(
                    model.isImportingCalendar ? "正在导入…" : "导入系统日历",
                    systemImage: "calendar.badge.plus"
                )
                .contentTransition(.opacity)
            }
            .disabled(model.schedule == nil || model.isRefreshingSchedule || model.isImportingCalendar)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("课表操作")
    }

    private var weekDateStrip: some View {
        let days = weekDates()
        return HStack(spacing: 0) {
            if mode == .week {
                VStack(spacing: 0) {
                    Text("\(calendar.component(.weekOfYear, from: selectedDate))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text("周")
                        .font(.caption2)
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: MobileCalendarTimelineLayout.axisWidth, height: 56)
                .accessibilityLabel(
                    "第 \(calendar.component(.weekOfYear, from: selectedDate)) 周"
                )
            }
            ForEach(days, id: \.self) { day in
                dateStripButton(day)
            }
        }
        .padding(.horizontal, -16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.mobile.date-strip")
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
    }

    private func dateStripButton(_ day: Date) -> some View {
        let selected = sameDay(day, selectedDate)
        let today = sameDay(day, .now)
        let dayCourses = courses(on: day)
        let holiday = holidayItems(on: day).first

        return Button {
            guard !suppressesEventSelection else { return }
            navigate(to: day)
        } label: {
            VStack(spacing: 3) {
                Text(Self.weekdayFormatter.string(from: day))
                    .font(.caption2.weight(.semibold))
                Text("\(calendar.component(.day, from: day))")
                    .font(.headline.monospacedDigit())
                HStack(spacing: 2) {
                    if holiday != nil {
                        Text(holiday?.type == "holiday" ? "休" : "班")
                            .font(.system(size: 8, weight: .bold))
                    }
                    if !dayCourses.isEmpty {
                        Circle().frame(width: 4, height: 4)
                    }
                }
                .frame(height: 8)
            }
            .foregroundStyle(selected ? AppTheme.onPrimary : dateStripForeground(holiday: holiday))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? AppTheme.primaryFill : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(today && !selected ? AppTheme.primary : Color.clear, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(day))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var statusArea: some View {
        let messages = [holidayStatus, model.statusMessage, model.calendarImportStatusMessage]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.primary.opacity(0.08))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .day:
            timelineContent(days: [selectedDate])
        case .week:
            timelineContent(days: weekDates())
        case .month:
            monthView
        case .year:
            yearView
        }
    }

    private func timelineContent(days: [Date]) -> some View {
        VStack(spacing: 0) {
            selectedDateSummary
                .contentShape(Rectangle())
                .simultaneousGesture(periodSwipeGesture)
            allDayItems(days: days)
            MobileCalendarTimelineView(
                days: days.map(timelineDay),
                selectedDate: selectedDate,
                showsWeekColumns: mode == .week,
                isScrollEnabled: !isHorizontalPaging,
                onSelectDay: { date in
                    guard !suppressesEventSelection else { return }
                    navigate(to: date)
                },
                onSelectCourse: { date, course in
                    presentCourse(course, on: date)
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.mobile.timeline")
            .contentShape(Rectangle())
            .simultaneousGesture(periodSwipeGesture)
        }
    }

    private var selectedDateSummary: some View {
        let dayCourses = courses(on: selectedDate)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.fullDateFormatter.string(from: selectedDate))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(dayCourses.isEmpty ? "暂无课程" : "\(dayCourses.count) 门课")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(dayCourses) { course in
                Button {
                    presentCourse(course, on: selectedDate)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(
                            [course.timeRange, CalendarTimelineLogic.courseMetadata(course)]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                        )
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
    }

    @ViewBuilder
    private func allDayItems(days: [Date]) -> some View {
        let items = days.flatMap { day in
            holidayItems(on: day).map { (day, $0) }
        }
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("全天")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    ForEach(items, id: \.1.id) { day, item in
                        Button {
                            presentHoliday(item, on: day)
                        } label: {
                            Text("\(Self.monthDayCompactFormatter.string(from: day)) · \(item.name)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.type == "holiday" ? AppTheme.danger : AppTheme.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(AppTheme.surface)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var monthView: some View {
        let first = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        let days = monthGridDates(containing: first)

        return GeometryReader { proxy in
            let usableHeight = max(
                proxy.size.height - MobileCalendarTimelineLayout.bottomContentInset,
                0
            )
            let expansionProgress = TeachingCalendarLogic.monthExpansionProgress(
                isExpanded: isMonthExpanded,
                verticalTranslation: monthDragTranslation,
                travelDistance: max(usableHeight * 0.34, 150)
            )
            let expandedCellHeight = TeachingCalendarLogic.expandedMonthCellHeight(
                availableHeight: usableHeight
            )
            let cellHeight = 46 + (expandedCellHeight - 46) * expansionProgress
            let gridHeight = cellHeight * 6 + 20
            let summaryHeight = max(usableHeight - 18 - 8 - gridHeight - 28 - 16, 0)

            VStack(spacing: 0) {
                monthWeekdayHeader
                    .padding(.bottom, 8)
                monthDateGrid(
                    days: days,
                    month: first,
                    expansionProgress: expansionProgress,
                    dayCellHeight: cellHeight
                )
                monthExpansionHandle
                if expansionProgress < 0.999, summaryHeight > 0 {
                    ScrollView(.vertical, showsIndicators: false) {
                        daySummaryCard(selectedDate)
                    }
                    .scrollDisabled(monthDragAxis != nil)
                    .frame(height: summaryHeight)
                    .opacity(1 - expansionProgress)
                    .allowsHitTesting(expansionProgress < 0.25 && monthDragAxis == nil)
                    .accessibilityIdentifier("calendar.mobile.month-day-summary")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: usableHeight, maxHeight: usableHeight, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(monthNavigationGesture)
            .animation(Self.monthExpansionAnimation, value: isMonthExpanded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.mobile.month")
            .accessibilityValue(isMonthExpanded ? "已展开" : "已收起")
            .accessibilityAction(named: Text(isMonthExpanded ? "收起月历" : "展开月历")) {
                changeMonthExpansion(to: !isMonthExpanded)
            }
        }
    }

    private var monthWeekdayHeader: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.weekdayLabels, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .accessibilityIdentifier("calendar.mobile.month-weekday.\(label)")
            }
        }
    }

    private func monthDateGrid(
        days: [Date],
        month: Date,
        expansionProgress: CGFloat,
        dayCellHeight: CGFloat
    ) -> some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { day in
                monthDayButton(
                    day,
                    month: month,
                    expansionProgress: expansionProgress,
                    cellHeight: dayCellHeight
                )
            }
        }
    }

    private var monthExpansionHandle: some View {
        Button {
            changeMonthExpansion(to: !isMonthExpanded)
        } label: {
            ZStack {
                Capsule()
                    .fill(AppTheme.secondaryText.opacity(0.55))
                    .frame(width: 21, height: 4)
                    .rotationEffect(.degrees(isMonthExpanded ? -24 : 0))
                    .offset(x: -9, y: isMonthExpanded ? 2 : 0)
                Capsule()
                    .fill(AppTheme.secondaryText.opacity(0.55))
                    .frame(width: 21, height: 4)
                    .rotationEffect(.degrees(isMonthExpanded ? 24 : 0))
                    .offset(x: 9, y: isMonthExpanded ? 2 : 0)
            }
                .frame(width: 42, height: 12)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMonthExpanded ? "收起月历" : "展开月历")
        .accessibilityValue(isMonthExpanded ? "已展开" : "已收起")
        .accessibilityIdentifier("calendar.mobile.month-state")
    }

    private func monthDayButton(
        _ day: Date,
        month: Date,
        expansionProgress: CGFloat,
        cellHeight: CGFloat
    ) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let selected = sameDay(day, selectedDate)
        let today = sameDay(day, .now)
        let dayCourses = courses(on: day)
        let holiday = holidayItems(on: day).first
        let events = monthEvents(on: day)
        let eventLayout = TeachingCalendarLogic.monthEventLayout(
            totalCount: events.count,
            maximumRows: expandedMonthEventRowLimit(cellHeight: cellHeight)
        )

        return VStack(spacing: 3) {
            Button {
                guard !suppressesEventSelection else { return }
                navigate(to: day)
            } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(selected ? .bold : .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 3 * expansionProgress)
            }
            .buttonStyle(.plain)

            ZStack(alignment: .top) {
                HStack(spacing: 2) {
                    if holiday != nil {
                        Text(holiday?.type == "holiday" ? "休" : "班")
                            .font(.system(size: 8, weight: .bold))
                    }
                    ForEach(0 ..< min(dayCourses.count, 3), id: \.self) { _ in
                        Circle().frame(width: 3, height: 3)
                    }
                }
                .frame(height: 14)
                .opacity(1 - expansionProgress)

                VStack(spacing: 2) {
                    ForEach(Array(events.prefix(eventLayout.visibleEventCount))) { event in
                        monthEventItem(
                            event,
                            tint: selected ? AppTheme.onPrimary : event.tint,
                            day: day
                        )
                    }
                    if eventLayout.hiddenEventCount > 0 {
                        Text("+\(eventLayout.hiddenEventCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(selected ? AppTheme.onPrimary : AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
                            .background(AppTheme.surface.opacity(0.78))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .opacity(expansionProgress)
                .offset(y: (1 - expansionProgress) * -5)
                .allowsHitTesting(expansionProgress > 0.75 && monthDragAxis == nil)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .foregroundStyle(monthForeground(selected: selected, inMonth: inMonth, holiday: holiday))
        .padding(.horizontal, 2 + (1 - expansionProgress))
        .padding(.vertical, 2 + (1 - expansionProgress) * 2)
        .frame(
            maxWidth: .infinity,
            minHeight: cellHeight,
            maxHeight: cellHeight,
            alignment: expansionProgress > 0.5 ? .top : .center
        )
        .background(monthBackground(selected: selected, courseCount: dayCourses.count))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(today && !selected ? AppTheme.primary : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dayAccessibilityLabel(day))
    }

    private func monthEventItem(_ event: MobileMonthEvent, tint: Color, day: Date) -> some View {
        Button {
            guard !suppressesEventSelection else { return }
            present(event.detail, on: day)
        } label: {
            Text(event.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(tint)
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .center)
                .background(AppTheme.surface.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(tint.opacity(0.55), lineWidth: 0.75)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func monthEvents(on day: Date) -> [MobileMonthEvent] {
        let holidays = holidayItems(on: day).map { item in
            MobileMonthEvent(
                id: "holiday-\(item.id)",
                title: "\(item.type == "holiday" ? "休" : "班") \(item.name)",
                tint: item.type == "holiday" ? AppTheme.danger : AppTheme.primary,
                detail: .holiday(item)
            )
        }
        let dayCourses = courses(on: day).map { course in
            MobileMonthEvent(
                id: "course-\(course.id)",
                title: course.name,
                tint: AppTheme.primary,
                detail: .course(course)
            )
        }
        return holidays + dayCourses
    }

    private func expandedMonthEventRowLimit(cellHeight: CGFloat) -> Int {
        cellHeight >= 58 ? 2 : 1
    }

    private var yearView: some View {
        let year = calendar.component(.year, from: selectedDate)
        let months = (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
        let columns = [GridItem(.adaptive(minimum: 152, maximum: 220), spacing: 16)]

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("颜色越深表示当天课程越多")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(months, id: \.self) { month in
                        miniMonth(month)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.mobile.year")
    }

    private func miniMonth(_ month: Date) -> some View {
        let days = monthGridDates(containing: month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 1), count: 7)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                jumpToMonth(month)
            } label: {
                HStack {
                    Text(Self.monthFormatter.string(from: month))
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(Self.monthFormatter.string(from: month))")
            .accessibilityIdentifier(
                "calendar.mobile.year-month.\(Self.yearMonthKeyFormatter.string(from: month))"
            )
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
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
        if calendar.isDate(day, equalTo: month, toGranularity: .month) {
            let count = courses(on: day).count
            let today = sameDay(day, .now)
            Button {
                MobileCalendarHaptics.selection()
                withAnimation(Self.pageAnimation) {
                    selectedDate = day
                    presentedDetail = MobileCalendarDetailSelection(date: day, content: .day)
                }
            } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(AppTheme.text)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(AppTheme.primary.opacity(TeachingCalendarLogic.yearCourseOpacity(courseCount: count)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(today ? AppTheme.primary : AppTheme.border, lineWidth: today ? 2 : 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dayAccessibilityLabel(day))
            .accessibilityIdentifier(
                "calendar.mobile.year-day.\(StrictContractDateParser.string(from: day))"
            )
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private func daySummaryCard(_ day: Date) -> some View {
        let dayCourses = courses(on: day)
        let holidays = holidayItems(on: day)
        return VStack(alignment: .leading, spacing: 10) {
            Text(Self.fullDateFormatter.string(from: day))
                .font(.headline)
            ForEach(holidays) { item in
                Label(item.name, systemImage: item.type == "holiday" ? "calendar.badge.exclamationmark" : "briefcase")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.type == "holiday" ? AppTheme.danger : AppTheme.primary)
            }
            if dayCourses.isEmpty {
                Text("暂无课程")
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(dayCourses) { course in
                    Button {
                        presentCourse(course, on: day)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppTheme.primary)
                                .frame(width: 4, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).font(.subheadline.weight(.semibold))
                                Text(
                                    [course.timeRange, CalendarTimelineLogic.courseMetadata(course)]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                )
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func detailSheet(_ selection: MobileCalendarDetailSelection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    switch selection.content {
                    case .day:
                        yearNavigationCommands(selection.date)
                        fullDayDetail(selection.date)
                    case let .course(course):
                        courseDetailCard(course, on: selection.date)
                    case let .holiday(holiday):
                        holidayDetailCard(holiday, on: selection.date)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(detailTitle(selection))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { presentedDetail = nil }
                }
            }
        }
    }

    private func fullDayDetail(_ day: Date) -> some View {
        let holidays = holidayItems(on: day)
        let dayCourses = courses(on: day)
        return VStack(alignment: .leading, spacing: 12) {
            Text(Self.fullDateFormatter.string(from: day))
                .font(.headline)
            ForEach(holidays) { holiday in
                holidayDetailCard(holiday, on: day)
            }
            ForEach(dayCourses) { course in
                courseDetailCard(course, on: day)
            }
            if holidays.isEmpty, dayCourses.isEmpty {
                Text("暂无日程")
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func courseDetailCard(_ course: Course, on day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(course.name, systemImage: "book.closed")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            detailRow("日期", Self.fullDateFormatter.string(from: day))
            detailRow("时间", course.timeRange)
            detailRow("节次", course.sectionText)
            detailRow("地点", course.room.isEmpty ? "未标注" : course.room)
            detailRow("教师", course.teacher.isEmpty ? "未标注" : course.teacher)
            detailRow("教学周", course.weekText)
            if !course.examWeekNumbers.isEmpty {
                detailRow("考试周", course.examWeekNumbers.map(String.init).joined(separator: "、"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func holidayDetailCard(_ holiday: HolidayItem, on day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                holiday.name,
                systemImage: holiday.type == "holiday" ? "calendar.badge.exclamationmark" : "briefcase"
            )
            .font(.headline)
            .foregroundStyle(holiday.type == "holiday" ? AppTheme.danger : AppTheme.primary)
            detailRow("日期", Self.fullDateFormatter.string(from: day))
            detailRow("类型", holiday.type == "holiday" ? "法定节假日" : "调休工作日")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 52, alignment: .leading)
            Text(value.isEmpty ? "未标注" : value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailTitle(_ selection: MobileCalendarDetailSelection) -> String {
        switch selection.content {
        case .day:
            Self.monthDayCompactFormatter.string(from: selection.date)
        case .course:
            "课程详情"
        case .holiday:
            "日程详情"
        }
    }

    private func yearNavigationCommands(_ day: Date) -> some View {
        HStack(spacing: 8) {
            yearNavigationButton("日", mode: .day, day: day)
            yearNavigationButton("周", mode: .week, day: day)
            yearNavigationButton("月", mode: .month, day: day)
        }
        .frame(maxWidth: .infinity)
    }

    private func yearNavigationButton(
        _ title: String,
        mode targetMode: MobileCalendarMode,
        day: Date
    ) -> some View {
        Button("\(title)视图") {
            MobileCalendarHaptics.selection()
            withAnimation(Self.viewAnimation) {
                selectedDate = day
                mode = targetMode
            }
            presentedDetail = nil
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("calendar.mobile.year-jump.\(targetMode.rawValue)")
    }

    private func jumpToMonth(_ month: Date) {
        MobileCalendarHaptics.selection()
        pageDirection = month > selectedDate ? 1 : -1
        withAnimation(Self.pageAnimation) {
            selectedDate = month
            mode = .month
        }
    }

    private func presentCourse(_ course: Course, on day: Date) {
        guard !suppressesEventSelection else { return }
        present(.course(course), on: day)
    }

    private func presentHoliday(_ holiday: HolidayItem, on day: Date) {
        guard !suppressesEventSelection else { return }
        present(.holiday(holiday), on: day)
    }

    private func present(_ content: MobileCalendarDetailSelection.Content, on day: Date) {
        MobileCalendarHaptics.selection()
        presentedDetail = MobileCalendarDetailSelection(date: day, content: content)
    }

    private var periodTitle: String {
        TeachingCalendarLogic.periodTitle(
            for: selectedDate,
            modeRawValue: mode.rawValue,
            calendar: calendar
        )
    }

    private func timelineDay(_ date: Date) -> CalendarTimelineDay {
        CalendarTimelineDay(date: date, courses: courses(on: date), holidays: holidayItems(on: date))
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

    private func weekDates() -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func monthGridDates(containing date: Date) -> [Date] {
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0 ..< 42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
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

    private func moveDate(_ direction: Int) {
        if let date = TeachingCalendarLogic.movedDate(
            from: selectedDate,
            unit: navigationUnit,
            direction: direction,
            calendar: calendar
        ) {
            pageDirection = direction
            MobileCalendarHaptics.selection()
            withAnimation(Self.pageAnimation) { selectedDate = date }
        }
    }

    private func navigate(to date: Date) {
        guard !sameDay(date, selectedDate) else { return }
        MobileCalendarHaptics.selection()
        if !sameDay(date, selectedDate) {
            pageDirection = date > selectedDate ? 1 : -1
        }
        withAnimation(Self.pageAnimation) { selectedDate = date }
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
            .onChanged { value in
                trackPeriodDrag(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height
                )
            }
            .onEnded { value in
                defer { finishTrackedDrag() }
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

    private var monthNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                let axis = monthDragAxis ?? TeachingCalendarLogic.gestureAxis(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height
                )
                guard let axis else { return }
                monthDragAxis = axis
                suppressesEventSelection = true
                switch axis {
                case .horizontal:
                    isHorizontalPaging = true
                case .vertical:
                    monthDragTranslation = value.translation.height
                }
            }
            .onEnded { value in
                defer { finishTrackedDrag() }
                if monthDragAxis == .horizontal,
                   let direction = TeachingCalendarLogic.swipeDirection(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height,
                    predictedHorizontalTranslation: value.predictedEndTranslation.width
                ) {
                    moveDate(direction)
                    return
                }

                guard monthDragAxis == .vertical else {
                    withAnimation(Self.monthExpansionAnimation) { monthDragTranslation = 0 }
                    return
                }
                guard let action = TeachingCalendarLogic.monthExpansionAction(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height
                ) else {
                    withAnimation(Self.monthExpansionAnimation) { monthDragTranslation = 0 }
                    return
                }
                settleMonthExpansion(to: action == .expand)
            }
    }

    private func trackPeriodDrag(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat
    ) {
        guard let axis = TeachingCalendarLogic.gestureAxis(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation
        ) else { return }
        suppressesEventSelection = true
        if axis == .horizontal {
            isHorizontalPaging = true
        }
    }

    private func finishTrackedDrag() {
        isHorizontalPaging = false
        monthDragAxis = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            suppressesEventSelection = false
        }
    }

    private var modeSelection: Binding<MobileCalendarMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                let currentIndex = MobileCalendarMode.allCases.firstIndex(of: mode) ?? 0
                let newIndex = MobileCalendarMode.allCases.firstIndex(of: newMode) ?? currentIndex
                pageDirection = newIndex > currentIndex ? 1 : -1
                MobileCalendarHaptics.selection()
                withAnimation(Self.pageAnimation) { mode = newMode }
            }
        )
    }

    private func changeMonthExpansion(to expanded: Bool) {
        guard expanded != isMonthExpanded else { return }
        MobileCalendarHaptics.selection()
        withAnimation(Self.monthExpansionAnimation) {
            monthDragTranslation = 0
            isMonthExpanded = expanded
        }
    }

    private func settleMonthExpansion(to expanded: Bool) {
        if expanded != isMonthExpanded {
            MobileCalendarHaptics.selection()
        }
        withAnimation(Self.monthExpansionAnimation) {
            monthDragTranslation = 0
            isMonthExpanded = expanded
        }
    }

    private var contentIdentity: String {
        let referenceDate: Date
        switch mode {
        case .day:
            referenceDate = calendar.startOfDay(for: selectedDate)
        case .week:
            referenceDate = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        case .month:
            referenceDate = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        case .year:
            referenceDate = calendar.dateInterval(of: .year, for: selectedDate)?.start ?? selectedDate
        }
        return "\(mode.rawValue)-\(referenceDate.timeIntervalSinceReferenceDate)"
    }

    private var pageTransition: AnyTransition {
        if pageDirection >= 0 {
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        }
        return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }

    private func dateStripForeground(holiday: HolidayItem?) -> Color {
        guard let holiday else { return AppTheme.text }
        return holiday.type == "holiday" ? AppTheme.danger : AppTheme.primary
    }

    private func monthForeground(selected: Bool, inMonth: Bool, holiday: HolidayItem?) -> Color {
        if selected { return AppTheme.onPrimary }
        if !inMonth { return AppTheme.secondaryText.opacity(0.45) }
        return dateStripForeground(holiday: holiday)
    }

    private func monthBackground(selected: Bool, courseCount: Int) -> Color {
        if selected { return AppTheme.primaryFill }
        guard courseCount > 0 else { return Color.clear }
        return AppTheme.primary.opacity(min(0.08 + Double(courseCount) * 0.08, 0.36))
    }

    private func dayAccessibilityLabel(_ day: Date) -> String {
        let holidays = holidayItems(on: day).map(\.name).joined(separator: "，")
        let dayCourses = courses(on: day).map { "\($0.timeRange)\($0.name)" }.joined(separator: "，")
        return [Self.fullDateFormatter.string(from: day), holidays, dayCourses.isEmpty ? "无课" : dayCourses]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
    }

    private func sameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    private static let viewAnimation = Animation.easeInOut(duration: 0.24)
    private static let pageAnimation = Animation.easeInOut(duration: 0.3)
    private static let monthExpansionAnimation = Animation.easeInOut(duration: 0.28)
    private static let fullDateFormatter = formatter("yyyy年M月d日 EEEE")
    private static let yearMonthFormatter = formatter("yyyy年M月")
    private static let monthFormatter = formatter("M月")
    private static let yearMonthKeyFormatter = formatter("yyyy-MM")
    private static let monthDayCompactFormatter = formatter("M月d日")
    private static let weekdayFormatter = formatter("E")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }
}
#endif
