import SwiftUI

struct PlannerView: View {
    @EnvironmentObject private var model: AppModel

    private var slotColumns: [GridItem] {
        #if os(macOS)
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
        #else
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(eyebrow: "BUPT Classroom Planner", title: "空教室与个人课表联动查询")

                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("查询条件", systemImage: "calendar.badge.clock")
                            .font(.headline)
                        Picker("校区", selection: $model.campusID) {
                            Text("西土城").tag("01")
                            Text("沙河").tag("04")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("节次筛选", systemImage: "clock")
                            .font(.headline)
                        LazyVGrid(columns: slotColumns, spacing: 8) {
                            ForEach(model.slots) { slot in
                                Button {
                                    model.toggleSlot(slot.index)
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(slot.label).font(.headline)
                                        Text("\(slot.start)-\(slot.end)")
                                            .font(.caption2)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundStyle(model.selectedSlots.contains(slot.index) ? Color.white : AppTheme.text)
                                    .background(model.selectedSlots.contains(slot.index) ? AppTheme.primary : AppTheme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("当天课程", systemImage: "calendar")
                            .font(.headline)
                        if model.todayCourses.isEmpty {
                            Text("暂无课程")
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 72)
                        } else {
                            ForEach(model.todayCourses) { course in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            if !course.examWeekNumbers.isEmpty {
                                                Text("试")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 3)
                                                    .background(AppTheme.accent)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            Text(course.name).font(.headline)
                                        }
                                        Text(course.room.isEmpty ? "地点未标注" : course.room)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    Spacer()
                                    Text(course.timeRange)
                                        .font(.subheadline.monospacedDigit())
                                }
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }
}
