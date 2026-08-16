import SwiftUI

final class TeachingCalendarSessionState: ObservableObject {
    @Published var selectedDate = Date()
    @Published var modeRawValue = "周"
    @Published var isMonthExpanded = true
}

private enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

enum TeachingCalendarLogic {
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

    static func yearCourseOpacity(courseCount: Int) -> Double {
        guard courseCount > 0 else { return 0 }
        let count = Double(courseCount)
        return 0.12 + 0.72 * count / (count + 3)
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
    @ObservedObject var session: TeachingCalendarSessionState
    @State private var yearPopoverDate: Date?
    @State private var yearPopoverLocation: CGPoint?
    @State private var showingDatePicker = false

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
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBar
                        .accessibilityIdentifier("layout.calendar.expanded")

                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            dateControls
                            if let status = holidayStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            if !model.statusMessage.isEmpty {
                                Text(model.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            if !model.calendarImportStatusMessage.isEmpty {
                                Text(model.calendarImportStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Divider()
                            calendarContent
                                .id(mode)
                                .transition(.opacity.combined(with: .scale(scale: 0.995)))
                                .animation(Self.viewAnimation, value: mode)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }

            yearPopoverOverlay
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("screen.calendar")
        .coordinateSpace(name: Self.calendarCoordinateSpace)
        .onAppear(perform: ensureVisibleHolidays)
        .onChange(of: selectedDate) { _ in ensureVisibleHolidays() }
        .onChange(of: mode) { _ in
            dismissYearPopover()
            ensureVisibleHolidays()
        }
    }

    @ViewBuilder
    private var titleBar: some View {
        #if os(macOS)
        HStack(alignment: .bottom) {
            PageTitle(eyebrow: "BUPT Classroom Planner", title: "教学日历")
            modePicker.frame(maxWidth: 280)
        }
        #else
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                PageTitle(eyebrow: "BUPT Classroom Planner", title: "教学日历")
                modePicker.frame(width: 300)
            }
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(eyebrow: "BUPT Classroom Planner", title: "教学日历")
                modePicker
            }
        }
        #endif
    }

    private var modePicker: some View {
        Picker("视图", selection: modeSelection) {
            ForEach(CalendarMode.allCases) { item in
                Text(item.rawValue).tag(item)
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
                    Text(Self.controlDateFormatter.string(from: selectedDate))
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
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .environment(\.timeZone, Self.shanghaiTimeZone)
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
        let courses = courses(on: selectedDate)
        return VStack(alignment: .leading, spacing: 12) {
            calendarHeading(title: Self.fullDateFormatter.string(from: selectedDate), count: courses.count)
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
        let weekStart = days.first ?? selectedDate
        return VStack(alignment: .leading, spacing: 12) {
            calendarHeading(
                title: "\(Self.monthDayFormatter.string(from: weekStart)) 起的一周",
                count: days.reduce(0) { $0 + courses(on: $1).count }
            )
            .contentShape(Rectangle())
            .simultaneousGesture(periodSwipeGesture)
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
        let first = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        let days = monthGridDates(containing: first)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Self.yearMonthFormatter.string(from: first)).font(.title2.bold())
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
                Button("今天") { selectedDate = .now }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                ForEach(days, id: \.self) { day in
                    monthDayButton(day, month: first)
                }
            }
            selectedDaySummary(selectedDate)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
        .animation(Self.monthExpansionAnimation, value: isMonthExpanded)
    }

    private func monthDayButton(_ day: Date, month: Date) -> some View {
        let dayCourses = courses(on: day)
        let holidays = holidayItems(on: day)
        let isSelected = sameDay(day, selectedDate)
        let isToday = sameDay(day, .now)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let detail = holidays.first.map {
            "\($0.type == "holiday" ? "休" : "班") \($0.name)"
        } ?? (dayCourses.isEmpty ? "无课" : "\(dayCourses.count) 门课")
        return Button {
            selectedDate = day
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? "今天 \(calendar.component(.day, from: day))" : "\(calendar.component(.day, from: day))")
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isMonthExpanded {
                    Text(detail)
                        .font(.system(size: 10, weight: holidays.isEmpty ? .regular : .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack(spacing: 3) {
                        if !holidays.isEmpty {
                            Circle().frame(width: 4, height: 4)
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
                minHeight: isMonthExpanded ? 76 : 46,
                alignment: .topLeading
            )
            .background(monthCellColor(selected: isSelected, inMonth: inMonth, courseCount: dayCourses.count))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isToday ? Self.nowRed : AppTheme.border, lineWidth: isToday ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(day))
    }

    private var yearView: some View {
        let year = calendar.component(.year, from: selectedDate)
        let months = (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
        let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)]
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(year) 年课程分布").font(.title2.bold())
            Text("颜色越深表示当天课程越多；点击日期查看日程")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(months, id: \.self) { month in
                    miniMonth(month)
                }
            }
        }
    }

    private func miniMonth(_ month: Date) -> some View {
        let days = monthGridDates(containing: month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)
        return VStack(alignment: .leading, spacing: 6) {
            Text(Self.monthFormatter.string(from: month)).font(.headline)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(label)
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
            let isSelected = yearPopoverDate.map { sameDay($0, day) } ?? false
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: day))")
                if let item = holidays.first {
                    Text(item.type == "holiday" ? "休" : "班")
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : Self.holidayColor(item))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.text)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(yearCellColor(selected: isSelected, courseCount: dayCourses.count))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isToday ? Self.nowRed : AppTheme.border, lineWidth: isToday ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayAccessibilityLabel(day))
            .accessibilityAddTraits(.isButton)
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
        } else {
            Color.clear.frame(height: 30)
        }
    }

    @ViewBuilder
    private var yearPopoverOverlay: some View {
        if mode == .year, let day = yearPopoverDate {
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
        return VStack(alignment: .leading, spacing: 10) {
            Text(Self.fullDateFormatter.string(from: day)).font(.headline)
            ForEach(holidays) { item in
                Text("\(item.type == "holiday" ? "休" : "班") \(item.name)")
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
        Button("\(title)视图") {
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
        return VStack(alignment: .leading, spacing: 8) {
            Text(Self.fullDateFormatter.string(from: day)).font(.headline)
            ForEach(holidays) { item in
                Text("\(item.type == "holiday" ? "休" : "班") \(item.name)")
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
        }
        .padding(.top, 4)
    }

    private func calendarHeading(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            Text(count == 0 ? "暂无课程" : "\(count) 门课")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.bottom, 2)
    }

    private func timelineDay(_ date: Date) -> CalendarTimelineDay {
        CalendarTimelineDay(
            date: date,
            courses: courses(on: date),
            holidays: holidayItems(on: date)
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
                withAnimation(Self.viewAnimation) { mode = newMode }
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
        let rows = max(1, holidayItems(on: day).count + courses(on: day).count)
        return min(max(160, CGFloat(rows * 48 + 124)), min(380, max(160, availableHeight - 32)))
    }

    private func monthCellColor(selected: Bool, inMonth: Bool, courseCount: Int) -> Color {
        if selected { return AppTheme.primaryFill }
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
        if selected { return AppTheme.primaryFill }
        guard courseCount > 0 else { return AppTheme.background }
        return AppTheme.primary.opacity(TeachingCalendarLogic.yearCourseOpacity(courseCount: courseCount))
    }

    private func dayAccessibilityLabel(_ day: Date) -> String {
        let holidays = holidayItems(on: day).map(\.name).joined(separator: "，")
        let dayCourses = courses(on: day).map { "\($0.timeRange)\($0.name)" }.joined(separator: "，")
        return [Self.fullDateFormatter.string(from: day), holidays, dayCourses.isEmpty ? "无课" : dayCourses]
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
    private static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static let calendarCoordinateSpace = "teaching-calendar"
    private static let viewAnimation = Animation.easeInOut(duration: 0.24)
    private static let monthExpansionAnimation = Animation.easeInOut(duration: 0.28)
    private static let fullDateFormatter = dateFormatter("yyyy年M月d日 EEEE")
    private static let controlDateFormatter = dateFormatter("yyyy-MM-dd")
    private static let monthDayFormatter = dateFormatter("yyyy年M月d日")
    private static let yearMonthFormatter = dateFormatter("yyyy年M月")
    private static let monthFormatter = dateFormatter("M月")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }
}
