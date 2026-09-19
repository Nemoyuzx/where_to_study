import SwiftUI

struct ExamScheduleNotice: View {
    @EnvironmentObject private var model: AppModel
    let exams: ExamSchedule

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if !exams.message.isEmpty { Text(model.localized(exams.message)) }
                ForEach(exams.items.filter { $0.date.isEmpty || $0.startTime.isEmpty || $0.endTime.isEmpty }) { exam in
                    Text(exam.name + " · " + model.localized("时间待定") + (exam.timeText.isEmpty ? "" : " · " + exam.timeText))
                }
                Button(model.localized("刷新课表和考试")) { model.refreshSchedule() }
                    .disabled(model.isRefreshingSchedule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(model.localized(exams.status == "stale" ? "考试安排使用缓存" : exams.status == "failed" ? "考试安排暂不可用" : "部分考试时间待定"), systemImage: "calendar.badge.exclamationmark")
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityIdentifier("schedule.exam-status")
    }
}
