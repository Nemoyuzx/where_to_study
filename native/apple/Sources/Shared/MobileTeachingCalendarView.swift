#if os(iOS)
import SwiftUI

private enum MobileCalendarMode: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

private struct MobileCalendarSelection: Identifiable {
    let date: Date
    var id: Date { date }
}

struct MobileTeachingCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDate = Date()
    @State private var mode: MobileCalendarMode = .week
    @State private var presentedDay: MobileCalendarSelection?

    private let calendar = Calendar.shanghai

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactHeader
                    .accessibilityIdentifier("layout.calendar.compact")
                statusArea
                content
            }
            .background(AppTheme.background)
            .accessibilityIdentifier("screen.calendar")
            .navigationBarHidden(true)
        }
        .sheet(item: $presentedDay) { selection in
            dayDetailSheet(selection.date)
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: ensureVisibleHolidays)
        .onChange(of: selectedDate) { _ in ensureVisibleHolidays() }
        .onChange(of: mode) { _ in ensureVisibleHolidays() }
    }

    private var compactHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.yearMonthFormatter.string(from: selectedDate))
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.text)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("calendar.mobile.header")

                Spacer(minLength: 8)

                Button("今天") { selectedDate = .now }
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

            Picker("日历视图", selection: $mode) {
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
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
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
                .frame(width: MobileCalendarTimelineLayout.axisWidth, height: 62)
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
    }

    private func dateStripButton(_ day: Date) -> some View {
        let selected = sameDay(day, selectedDate)
        let today = sameDay(day, .now)
        let dayCourses = courses(on: day)
        let holiday = holidayItems(on: day).first

        return Button {
            selectedDate = day
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
            .frame(maxWidth: .infinity, minHeight: 62)
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
            allDayItems(days: days)
            MobileCalendarTimelineView(
                days: days.map(timelineDay),
                selectedDate: selectedDate,
                showsWeekColumns: mode == .week,
                onSelectDay: { selectedDate = $0 }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.mobile.timeline")
        }
    }

    private var selectedDateSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.fullDateFormatter.string(from: selectedDate))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            let count = courses(on: selectedDate).count
            Text(count == 0 ? "暂无课程" : "\(count) 门课")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
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
                            selectedDate = day
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
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7)

        return ScrollView {
            VStack(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Self.weekdayLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(days, id: \.self) { day in
                        monthDayButton(day, month: first)
                    }
                }
                .padding(.top, 8)

                daySummaryCard(selectedDate)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.mobile.month")
    }

    private func monthDayButton(_ day: Date, month: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let selected = sameDay(day, selectedDate)
        let today = sameDay(day, .now)
        let dayCourses = courses(on: day)
        let holiday = holidayItems(on: day).first

        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(selected ? .bold : .medium))
                HStack(spacing: 2) {
                    if holiday != nil {
                        Text(holiday?.type == "holiday" ? "休" : "班")
                            .font(.system(size: 8, weight: .bold))
                    }
                    ForEach(0 ..< min(dayCourses.count, 3), id: \.self) { _ in
                        Circle().frame(width: 3, height: 3)
                    }
                }
                .frame(height: 7)
            }
            .foregroundStyle(monthForeground(selected: selected, inMonth: inMonth, holiday: holiday))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(monthBackground(selected: selected, courseCount: dayCourses.count))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(today && !selected ? AppTheme.primary : Color.clear, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(day))
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
            Text(Self.monthFormatter.string(from: month))
                .font(.headline)
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
                selectedDate = day
                presentedDay = MobileCalendarSelection(date: day)
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
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.primary)
                            .frame(width: 4, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.subheadline.weight(.semibold))
                            Text([course.timeRange, course.room].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
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

    private func dayDetailSheet(_ day: Date) -> some View {
        NavigationStack {
            ScrollView {
                daySummaryCard(day)
                    .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(Self.monthDayCompactFormatter.string(from: day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { presentedDay = nil }
                }
            }
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .day:
            return Self.fullDateFormatter.string(from: selectedDate)
        case .week:
            return "第 \(calendar.component(.weekOfYear, from: selectedDate)) 周"
        case .month:
            return "月视图"
        case .year:
            return "\(calendar.component(.year, from: selectedDate)) 年课程分布"
        }
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
        let component: Calendar.Component
        let amount: Int
        switch mode {
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
        if let date = calendar.date(byAdding: component, value: amount, to: selectedDate) {
            selectedDate = date
        }
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
    private static let fullDateFormatter = formatter("yyyy年M月d日 EEEE")
    private static let yearMonthFormatter = formatter("yyyy年M月")
    private static let monthFormatter = formatter("M月")
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
