import SwiftUI

struct CourseDeletionControl: View {
    @EnvironmentObject private var model: AppModel
    let course: Course
    let date: Date
    var onDeleted: () -> Void = {}
    @State private var selectedScope: CourseDeletionScope?
    @State private var showingConfirmation = false
    @State private var showingFailure = false

    var body: some View {
        if !model.isSampleMode {
            Menu {
                Button("仅删除本次课程", role: .destructive) { confirm(.occurrence) }
                Button("删除本学期整门课程", role: .destructive) { confirm(.course) }
            } label: {
                Label("删除课程", systemImage: "trash")
            }
            .accessibilityIdentifier("action.delete-course.\(course.id)")
            .confirmationDialog(
                model.localized(selectedScope == .course ? "删除本学期整门课程？" : "仅删除本次课程？"),
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("确认删除", role: .destructive) {
                    guard let selectedScope else { return }
                    if model.deleteCourse(course, on: date, scope: selectedScope) {
                        onDeleted()
                    } else {
                        showingFailure = true
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("仅修改此账号本学期的本地课表，刷新后仍保持，可在个人账户中恢复。不会退选学校课程、删除作业 DDL 或已导出的系统日历事件。")
            }
            .alert("操作未完成", isPresented: $showingFailure) {
                Button("完成", role: .cancel) { }
            } message: {
                Text(model.localized(model.statusMessage))
            }
        }
    }

    private func confirm(_ scope: CourseDeletionScope) {
        selectedScope = scope
        showingConfirmation = true
    }
}

/// Gives desktop timeline blocks and the planner the same editable detail as
/// the mobile calendar without changing their existing layout or data sources.
struct CourseManagementModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let course: Course
    let date: Date
    @State private var showingDetail = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { showingDetail = true }
            .sheet(isPresented: $showingDetail) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(course.name).font(.title2.weight(.semibold))
                    Text(StrictContractDateParser.string(from: date))
                    Text(course.timeRange)
                    Text(course.room)
                    Text(course.teacher)
                    CourseDeletionControl(course: course, date: date) { showingDetail = false }
                    HStack {
                        Spacer()
                        Button("完成") { showingDetail = false }
                    }
                }
                .padding(24)
                .frame(minWidth: 280)
                .environmentObject(model)
            }
    }
}
