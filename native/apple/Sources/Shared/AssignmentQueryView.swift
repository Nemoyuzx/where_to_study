import SwiftUI

enum AssignmentQueryLogic {
    static func filtered(_ items: [AssignmentDeadlineItem], query: String, showsEnded: Bool, today: String) -> [AssignmentDeadlineItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            (showsEnded || String(item.deadline.prefix(10)) >= today)
                && (needle.isEmpty || [item.title, item.courseName ?? "", item.status ?? "", item.deadline]
                    .contains { $0.localizedCaseInsensitiveContains(needle) })
        }.sorted { ($0.deadline, $0.courseName ?? "", $0.title, $0.id) < ($1.deadline, $1.courseName ?? "", $1.title, $1.id) }
    }
}

struct AssignmentQueryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: CalendarDeadlineStore
    @State private var query = ""
    @State private var showsEnded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.localized("课程作业 DDL")).font(.title2.bold())
                Spacer()
                Button {
                    Task { await store.loadAssignmentQuery(sampleMode: model.isSampleMode, force: true) }
                } label: { Label(model.localized("刷新"), systemImage: "arrow.clockwise") }
                    .disabled(store.isLoadingAssignmentQuery)
                    .accessibilityIdentifier("assignments.refresh")
            }
            TextField(model.localized("搜索课程或作业"), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("assignments.search")
            Toggle(model.localized("显示已截止作业"), isOn: $showsEnded)
            if model.isSampleMode {
                Label(model.localized("示例作业，未连接教学云"), systemImage: "info.circle")
                    .foregroundStyle(theme.secondaryText)
            }
            if store.isLoadingAssignmentQuery { ProgressView(model.localized("正在获取课程作业…")) }
            if !store.assignmentQueryError.isEmpty {
                Text(model.localized(store.assignmentQueryError)).foregroundStyle(theme.secondaryText)
                if store.assignmentQueryItems != nil {
                    Text(model.localized("当前展示上次成功获取的作业，请留意更新时间。"))
                        .font(.caption).foregroundStyle(theme.secondaryText)
                }
                Button(model.localized("前往个人账户")) { model.navigation.selectedSection = .settings }
                    .accessibilityIdentifier("assignments.account")
            }
            if let items = store.assignmentQueryItems {
                let filtered = AssignmentQueryLogic.filtered(items, query: query, showsEnded: showsEnded,
                    today: StrictContractDateParser.string(from: .now))
                if filtered.isEmpty {
                    Text(model.localized("暂无符合条件的课程作业")).foregroundStyle(theme.secondaryText)
                }
                ForEach(filtered) { item in
                    Surface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline)
                            if let course = item.courseName { Text(course) }
                            Label(item.deadline, systemImage: "calendar.badge.clock")
                            if let status = item.status { Text(model.localized(status)).font(.caption) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if let timestamp = store.assignmentQueryFetchedAt {
                Text(model.localized("更新时间") + "：" + timestamp).font(.caption).foregroundStyle(theme.secondaryText)
            }
            Text(model.localized("作业来自教学云，与日历共享缓存；提交状态和截止时间以教学云为准。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            Link(model.localized("打开教学云"), destination: CalendarDeadlineSources.assignments)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queries.assignments")
    }
}

struct ExamQueryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.localized("考试安排")).font(.title2.bold())
                Spacer()
                Button { model.refreshSchedule() } label: {
                    Label(model.localized("刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshingSchedule || model.isSampleMode)
                .accessibilityIdentifier("exams.refresh")
            }
            if model.isSampleMode {
                Text(model.localized("示例考试，未连接学校服务")).foregroundStyle(theme.secondaryText)
            }
            if model.isRefreshingSchedule { ProgressView() }
            if let exams = model.schedule?.examSchedule {
                Text(model.localized("学期") + "：" + exams.termID)
                if !exams.message.isEmpty { Text(model.localized(exams.message)).foregroundStyle(theme.secondaryText) }
                if exams.items.isEmpty, exams.status != "failed" {
                    Text(model.localized("该学期暂无已公布考试安排")).foregroundStyle(theme.secondaryText)
                }
                ForEach(exams.items.sorted { ($0.date, $0.startTime, $0.name) < ($1.date, $1.startTime, $1.name) }) { exam in
                    Surface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(exam.name).font(.headline)
                            Text(exam.timeText.isEmpty ? model.localized("考试时间待定") : exam.timeText)
                            if !exam.room.isEmpty { Label(exam.room, systemImage: "mappin.and.ellipse") }
                            if !exam.seat.isEmpty { Text(model.localized("座位") + "：" + exam.seat) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(model.localized("更新时间") + "：" + exams.fetchedAt).font(.caption).foregroundStyle(theme.secondaryText)
            } else {
                Text(model.localized("刷新课表后可查看学校公布的考试安排。"))
                    .foregroundStyle(theme.secondaryText)
            }
            if !model.statusMessage.isEmpty { Text(model.statusMessage).font(.caption).foregroundStyle(theme.secondaryText) }
            if !model.hasSavedPassword, !model.isSampleMode {
                Button(model.localized("前往个人账户")) { model.navigation.selectedSection = .settings }
            }
            Text(model.localized("考试与个人课表共享缓存，以学校公布的安排为准。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queries.exams")
    }
}
