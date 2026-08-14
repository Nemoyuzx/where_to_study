import SwiftUI

struct PlannerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var slotColumns: [GridItem] {
        [GridItem(
            .adaptive(
                minimum: PlannerLayoutMetrics.slotMinimumWidth,
                maximum: PlannerLayoutMetrics.slotMaximumWidth
            ),
            spacing: PlannerLayoutMetrics.slotSpacing
        )]
    }

    private var buildingColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 128, maximum: 220), spacing: 8)]
    }

    var body: some View {
        GeometryReader { proxy in
            let columnCount = AdaptiveLayoutPolicy.contentColumnCount(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 12) {
                            plannerTitle
                            Spacer(minLength: 0)
                            todayLabel
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            plannerTitle
                            todayLabel
                        }
                    }

                    if columnCount == 2 {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                querySurface
                                slotSurface
                                buildingsSurface
                            }
                            .frame(maxWidth: .infinity, alignment: .top)

                            VStack(spacing: 16) {
                                todayCoursesSurface
                                resultsSurface
                                summarySurface
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        VStack(spacing: 16) {
                            querySurface
                            slotSurface
                            todayCoursesSurface
                            buildingsSurface
                            resultsSurface
                            summarySurface
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("screen.planner")
    }

    private var plannerTitle: some View {
        PageTitle(eyebrow: "BUPT Classroom Planner", title: "空教室与个人课表联动查询")
    }

    private var todayLabel: some View {
        Label(Self.todayLabel, systemImage: "clock")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize()
    }

    private var querySurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label("查询条件", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Picker(
                    "校区",
                    selection: Binding(
                        get: { model.queryCampusID },
                        set: { model.selectQueryCampus($0) }
                    )
                ) {
                    Text("西土城").tag("01")
                    Text("沙河").tag("04")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                Button {
                    model.refreshClassrooms()
                } label: {
                    HStack(spacing: 8) {
                        if model.isRefreshingClassrooms {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(model.isRefreshingClassrooms ? "正在获取当天空教室…" : "获取空教室信息")
                    }
                    .foregroundStyle(AppTheme.onPrimary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryFill)
                .disabled(model.isRefreshingClassrooms)

                if !model.classroomStatusMessage.isEmpty {
                    Text(model.classroomStatusMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else if let cache = model.classroomsCache {
                    Text(model.isSampleMode
                        ? "数据源：内置示例数据 · \(cache.targetDate)"
                        : "数据源：移动教务实时接口 · \(cache.targetDate)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var slotSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("节次筛选", systemImage: "clock")
                    .font(.headline)
                Toggle(
                    "使用个人课表排除已有课程",
                    isOn: Binding(
                        get: { model.usePersonalSchedule },
                        set: { model.setUsePersonalSchedule($0) }
                    )
                )
                .toggleStyle(.switch)
                .tint(AppTheme.primary)

                HStack(spacing: 8) {
                    Button("选中空闲") { model.selectFreeSlots() }
                        .buttonStyle(.bordered)
                    Button("清空") { model.clearSelectedSlots() }
                        .buttonStyle(.bordered)
                }

                LazyVGrid(columns: slotColumns, spacing: PlannerLayoutMetrics.slotSpacing) {
                    ForEach(model.slots) { slot in
                        slotButton(slot)
                    }
                }
            }
        }
    }

    private func slotButton(_ slot: SlotMetadata) -> some View {
        let busy = model.usePersonalSchedule && model.personalBusySlots.contains(slot.index)
        let selected = model.selectedSlots.contains(slot.index)
        return Button {
            model.toggleSlot(slot.index)
        } label: {
            VStack(spacing: 3) {
                Text("第 \(slot.label) 节")
                    .font(.subheadline.bold())
                Text("\(slot.start)-\(slot.end)")
                    .font(.caption.monospacedDigit())
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(selected ? AppTheme.onPrimary : AppTheme.text)
            .background(
                selected ? AppTheme.primaryFill : (busy ? AppTheme.accent.opacity(0.45) : AppTheme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? AppTheme.primaryFill : AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityHint(busy ? "与当天个人课程冲突" : "切换此节次")
    }

    private var todayCoursesSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("当天课程", systemImage: "calendar")
                    .font(.headline)
                if model.todayCourses.isEmpty {
                    emptyMessage("暂无本地课程，请在设置中获取/刷新个人课表")
                } else {
                    ForEach(Array(model.todayCourses.enumerated()), id: \.element.id) { index, course in
                        courseRow(course)
                        if index < model.todayCourses.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func courseRow(_ course: Course) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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
            Spacer(minLength: 8)
            Text(course.timeRange)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize()
        }
        .padding(.vertical, 2)
    }

    private var buildingsSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("教学楼", systemImage: "building.2")
                    .font(.headline)
                if model.campusBuildings.isEmpty {
                    emptyMessage("暂无教学楼，请先获取当天空教室")
                } else {
                    LazyVGrid(columns: buildingColumns, spacing: 8) {
                        ForEach(model.campusBuildings, id: \.self) { building in
                            let selected = model.selectedBuildings.contains(building)
                            Button {
                                model.toggleBuilding(building)
                            } label: {
                                Label(building, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline.bold())
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .foregroundStyle(selected ? AppTheme.onPrimary : AppTheme.text)
                                    .background(selected ? AppTheme.primaryFill : AppTheme.background)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(selected ? AppTheme.primaryFill : AppTheme.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var resultsSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("空教室结果", systemImage: "checkmark.circle")
                    .font(.headline)
                if model.classroomsCache == nil {
                    emptyMessage("暂无本地空教室数据")
                } else if model.selectedBuildings.isEmpty {
                    emptyMessage("请选择教学楼")
                } else if model.selectedSlots.isEmpty {
                    emptyMessage("请选择节次")
                } else if model.matchingRooms.isEmpty {
                    emptyMessage("暂无匹配空教室")
                } else {
                    let rooms = model.matchingRooms
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rooms.indices, id: \.self) { index in
                            classroomRow(rooms[index])
                            if index < rooms.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func classroomRow(_ room: Classroom) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name).font(.headline)
                Text(selectedRanges)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.primary)
            }
            Spacer(minLength: 8)
            Text(room.size.map { "\($0) 座" } ?? "座位未知")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize()
        }
        .padding(.vertical, 2)
    }

    private var summarySurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("查询概览", systemImage: "chart.bar")
                    .font(.headline)
                summaryItems
            }
        }
    }

    @ViewBuilder
    private var summaryItems: some View {
        let freeSlots = model.usePersonalSchedule ? model.slots.count - model.personalBusySlots.count : model.slots.count
        let values = [
            ("当天课程", model.todayCourses.count),
            ("个人空闲节次", freeSlots),
            ("匹配教室", model.matchingRooms.count)
        ]

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.0)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .accessibilityIdentifier("planner.summary.label.\(index)")
                        Spacer(minLength: 12)
                        Text("\(item.1)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.text)
                    }
                    .padding(.vertical, 10)
                    if index < values.count - 1 { Divider() }
                }
            }
        } else {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 4) {
                        Text(item.0)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
                            .accessibilityIdentifier("planner.summary.label.\(index)")
                        Text("\(item.1)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.text)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)

                    if index < values.count - 1 {
                        Divider()
                            .frame(height: 64)
                    }
                }
            }
        }
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 72)
    }

    private var selectedRanges: String {
        let slots = model.selectedSlots.sorted()
        guard let first = slots.first else { return "未选择" }
        var ranges: [ClosedRange<Int>] = []
        var start = first
        var end = first
        for slot in slots.dropFirst() {
            if slot == end + 1 {
                end = slot
            } else {
                ranges.append(start ... end)
                start = slot
                end = slot
            }
        }
        ranges.append(start ... end)
        return ranges.map { range in
            let firstSlot = model.slots[range.lowerBound]
            let lastSlot = model.slots[range.upperBound]
            let label = range.lowerBound == range.upperBound
                ? "第 \(firstSlot.label) 节"
                : "第 \(firstSlot.label)-\(lastSlot.label) 节"
            return "\(label) \(firstSlot.start)-\(lastSlot.end)"
        }.joined(separator: " / ")
    }

    private static var todayLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}

enum PlannerLayoutMetrics {
    static let slotMinimumWidth: CGFloat = 104
    static let slotMaximumWidth: CGFloat = 156
    static let slotSpacing: CGFloat = 6
}
