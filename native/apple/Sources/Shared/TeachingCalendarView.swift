import SwiftUI

private enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

struct TeachingCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDate = Date()
    @State private var mode: CalendarMode = .week

    private let calendar = Calendar.shanghai

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBar

                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        dateControls
                        if !model.statusMessage.isEmpty {
                            Text(model.statusMessage)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Divider()
                        calendarContent
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }

    @ViewBuilder
    private var titleBar: some View {
        #if os(macOS)
        HStack(alignment: .bottom) {
            PageTitle(eyebrow: "BUPT Classroom Planner", title: "教学日历")
            modePicker.frame(maxWidth: 280)
        }
        #else
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(eyebrow: "BUPT Classroom Planner", title: "教学日历")
            modePicker
        }
        #endif
    }

    private var modePicker: some View {
        Picker("视图", selection: $mode) {
            ForEach(CalendarMode.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var dateControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                datePicker
                Spacer(minLength: 16)
                refreshButton
            }
            VStack(alignment: .leading, spacing: 10) {
                datePicker
                refreshButton
            }
        }
    }

    private var datePicker: some View {
        DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
            .datePickerStyle(.compact)
    }

    private var refreshButton: some View {
        Button {
            model.refreshSchedule()
        } label: {
            Label(
                model.isRefreshingSchedule ? "正在获取…" : "获取/刷新个人课表",
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(model.isRefreshingSchedule)
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch mode {
        case .day:
            dayView
        case .week:
            weekView
        case .month:
            monthView
        case .year:
            yearView
        }
    }

    private var dayView: some View {
        let courses = courses(on: selectedDate)
        return VStack(alignment: .leading, spacing: 0) {
            calendarHeading(title: Self.fullDateFormatter.string(from: selectedDate), count: courses.count)
            ForEach(model.slots) { slot in
                let course = courses.first { slot.index >= $0.startSlot && slot.index <= $0.endSlot }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("第 \(slot.label) 节").font(.caption.bold())
                        Text("\(slot.start)-\(slot.end)").font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 92, alignment: .trailing)
                    Rectangle().fill(AppTheme.border).frame(width: 1)
                    if let course {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.startSlot == slot.index ? course.name : "\(course.name)（延续）")
                                .font(.subheadline.weight(.semibold))
                            if course.startSlot == slot.index {
                                Text([course.timeRange, course.room].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(Color.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(AppTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        Text("暂无课程")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .padding(.vertical, 5)
                Divider()
            }
        }
    }

    private var weekView: some View {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]
        return VStack(alignment: .leading, spacing: 12) {
            calendarHeading(
                title: "\(Self.monthDayFormatter.string(from: weekStart)) 起的一周",
                count: days.reduce(0) { $0 + courses(on: $1).count }
            )
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let dayCourses = courses(on: day)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Self.weekDayFormatter.string(from: day))
                                .font(.subheadline.bold())
                            Spacer()
                            Text(dayCourses.isEmpty ? "无课" : "\(dayCourses.count) 门")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        if dayCourses.isEmpty {
                            Text("暂无课程")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            ForEach(dayCourses) { course in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                    Text(course.timeRange)
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundStyle(AppTheme.primary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .background(sameDay(day, selectedDate) ? AppTheme.primary.opacity(0.10) : AppTheme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(sameDay(day, Date()) ? AppTheme.accent : AppTheme.border, lineWidth: sameDay(day, Date()) ? 2 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .onTapGesture { selectedDate = day }
                }
            }
        }
    }

    private var monthView: some View {
        let first = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        let days = dates(inMonthContaining: first)
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Self.yearMonthFormatter.string(from: first)).font(.title2.bold())
                Spacer()
                Button("今天") { selectedDate = .now }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0).font(.caption.bold()).foregroundStyle(AppTheme.secondaryText)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 64) }
                ForEach(days, id: \.self) { day in
                    let dayCourses = courses(on: day)
                    Button {
                        selectedDate = day
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.subheadline.bold())
                            if dayCourses.isEmpty {
                                Text("无课")
                                    .font(.caption2)
                                    .foregroundStyle(sameDay(day, selectedDate) ? Color.white.opacity(0.85) : AppTheme.secondaryText)
                            } else {
                                Text("\(dayCourses.count) 门课")
                                    .font(.caption2.bold())
                            }
                        }
                        .foregroundStyle(sameDay(day, selectedDate) ? Color.white : AppTheme.text)
                        .padding(7)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                        .background(sameDay(day, selectedDate) ? AppTheme.primary : AppTheme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(sameDay(day, Date()) ? AppTheme.accent : AppTheme.border, lineWidth: sameDay(day, Date()) ? 2 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            selectedDaySummary
        }
    }

    private var yearView: some View {
        let year = calendar.component(.year, from: selectedDate)
        let months = (1...12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
        let columns = [GridItem(.adaptive(minimum: 170), spacing: 8)]
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(year) 年").font(.title2.bold())
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(months, id: \.self) { month in
                    let count = dates(inMonthContaining: month).reduce(0) { $0 + courses(on: $1).count }
                    Button {
                        selectedDate = month
                        mode = .month
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Self.monthFormatter.string(from: month))
                                .font(.headline)
                            Text(count == 0 ? "暂无课程" : "\(count) 门课")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                        .background(
                            calendar.isDate(month, equalTo: selectedDate, toGranularity: .month)
                                ? AppTheme.primary.opacity(0.10) : AppTheme.background
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    calendar.isDate(month, equalTo: Date(), toGranularity: .month)
                                        ? AppTheme.accent : AppTheme.border,
                                    lineWidth: calendar.isDate(month, equalTo: Date(), toGranularity: .month) ? 2 : 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedDaySummary: some View {
        let dayCourses = courses(on: selectedDate)
        return VStack(alignment: .leading, spacing: 8) {
            Text(Self.fullDateFormatter.string(from: selectedDate)).font(.headline)
            if dayCourses.isEmpty {
                Text("暂无课程").foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(dayCourses) { course in
                    HStack {
                        Text(course.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(course.timeRange).font(.caption.monospacedDigit())
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
        .padding(.bottom, 8)
    }

    private func courses(on date: Date) -> [Course] {
        guard
            let schedule = model.schedule,
            let start = DateFormatter.contractDate.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.courses(on: date, termStart: start, courses: schedule.courses)
    }

    private func dates(inMonthContaining date: Date) -> [Date] {
        guard
            let interval = calendar.dateInterval(of: .month, for: date),
            let dayRange = calendar.range(of: .day, in: .month, for: interval.start)
        else { return [] }
        return dayRange.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: interval.start)
        }
    }

    private func sameDay(_ left: Date, _ right: Date) -> Bool {
        calendar.isDate(left, inSameDayAs: right)
    }

    private static let fullDateFormatter = dateFormatter("yyyy年M月d日 EEEE")
    private static let weekDayFormatter = dateFormatter("M月d日 E")
    private static let monthDayFormatter = dateFormatter("yyyy年M月d日")
    private static let yearMonthFormatter = dateFormatter("yyyy年M月")
    private static let monthFormatter = dateFormatter("M月")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }
}

extension DateFormatter {
    static let contractDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
