import AppKit
import SwiftUI

struct MacMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var requestedInitialWindow = false

    var body: some View {
        Image(systemName: "calendar.badge.clock")
            .accessibilityLabel("Where To Study")
            .task {
                guard !requestedInitialWindow else { return }
                requestedInitialWindow = true
                await Task.yield()
                openWindow(id: "main")
            }
    }
}

struct MacMenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private let calendar = Calendar.shanghai

    var body: some View {
        Button("打开主窗口") { showMainWindow() }
            .keyboardShortcut("o")
        Divider()
        courseSection(label: "今日", date: .now, courses: model.todayCourses)
        Divider()
        courseSection(label: "明日", date: tomorrow, courses: model.tomorrowCourses)
        Divider()
        Button("查看空教室") { showMainWindow(section: .planner) }
        Button("教学日历") { showMainWindow(section: .calendar) }
        Button("设置…") { showMainWindow(section: .settings) }
            .keyboardShortcut(",")
        Divider()
        Button(model.isRefreshingSchedule ? "正在获取个人课表…" : "获取/刷新个人课表") {
            model.refreshSchedule()
        }
        .disabled(model.isRefreshingSchedule)
        Button(model.isRefreshingClassrooms ? "正在获取当天空教室…" : "获取当天空教室") {
            model.refreshClassrooms(force: true)
        }
        .disabled(model.isRefreshingClassrooms)
        Divider()
        Button("退出 Where To Study") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func courseSection(label: String, date: Date, courses: [Course]) -> some View {
        let week = model.weekNumber(on: date)
        Button(sectionTitle(label: label, date: date, week: week)) {
            showMainWindow(section: .calendar)
        }
        if model.schedule == nil {
            Button("尚未获取个人课表") { showMainWindow(section: .settings) }
        } else if courses.isEmpty {
            Button("\(label)暂无课程") { showMainWindow(section: .calendar) }
        } else {
            ForEach(courses.prefix(8)) { course in
                Button(courseLine(course)) {
                    showMainWindow(section: .calendar)
                }
            }
            if courses.count > 8 {
                Text("还有 \(courses.count - 8) 门课，请打开教学日历查看")
            }
        }
    }

    private var tomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
    }

    private func sectionTitle(label: String, date: Date, week: Int?) -> String {
        let dateLabel = Self.dateFormatter.string(from: date)
        let weekContext = TeachingCalendarLogic.weekContext(
            for: date,
            teachingWeekNumber: week,
            calendar: calendar,
            compact: true
        )
        return "\(label)课程 · \(dateLabel) · \(weekContext)"
    }

    private func courseLine(_ course: Course) -> String {
        let room = course.room.isEmpty ? "地点未标注" : course.room
        return "\(timeLabel(course))  \(course.name)  @ \(room)"
    }

    private func timeLabel(_ course: Course) -> String {
        if !course.timeRange.isEmpty { return course.timeRange }
        guard
            SlotMetadata.defaults.indices.contains(course.startSlot),
            SlotMetadata.defaults.indices.contains(course.endSlot)
        else { return "--:--" }
        return "\(SlotMetadata.defaults[course.startSlot].start)-\(SlotMetadata.defaults[course.endSlot].end)"
    }

    private func showMainWindow(section: AppSection? = nil) {
        if let section { model.selectedSection = section }
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = Calendar.shanghai.timeZone
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()
}
