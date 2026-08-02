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
                HStack(alignment: .bottom) {
                    PageTitle(eyebrow: "BUPT Classroom Planner", title: "教学日历")
                    Picker("视图", selection: $mode) {
                        ForEach(CalendarMode.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }

                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
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
    private var calendarContent: some View {
        if mode == .month || mode == .year {
            monthGrid
        } else {
            let courses = coursesForSelectedDate
            VStack(spacing: 0) {
                ForEach(model.slots) { slot in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("第 \(slot.label) 节").font(.caption.bold())
                            Text("\(slot.start)-\(slot.end)").font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 92, alignment: .trailing)
                        Rectangle().fill(AppTheme.border).frame(width: 1)
                        if let course = courses.first(where: { $0.startSlot <= slot.index && $0.endSlot >= slot.index }) {
                            Text(course.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
    }

    private var monthGrid: some View {
        let interval = calendar.dateInterval(of: .month, for: selectedDate)
        let first = interval?.start ?? selectedDate
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(spacing: 8) {
            HStack {
                Text(first.formatted(.dateTime.year().month(.wide))).font(.title2.bold())
                Spacer()
                Button("今天") { selectedDate = .now }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption.bold()) }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 54) }
                ForEach(1...days, id: \.self) { day in
                    Button {
                        selectedDate = calendar.date(byAdding: .day, value: day - 1, to: first) ?? selectedDate
                        mode = .day
                    } label: {
                        Text("\(day)")
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                            .padding(6)
                            .background(AppTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var coursesForSelectedDate: [Course] {
        guard
            let schedule = model.schedule,
            let start = DateFormatter.contractDate.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.courses(on: selectedDate, termStart: start, courses: schedule.courses)
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
