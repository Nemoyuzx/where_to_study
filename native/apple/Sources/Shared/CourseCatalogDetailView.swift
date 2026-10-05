import SwiftUI

struct CourseCatalogDetailPresentationHost: View {
    let session: CoursesViewSession
    @ObservedObject private var presentation: InAppPresentationState
    @ObservedObject var teachingCloud: TeachingCloudCourseStore
    @ObservedObject var assignments: CalendarDeadlineStore
    @ObservedObject var qmplus: QMplusStore

    init(session: CoursesViewSession, teachingCloud: TeachingCloudCourseStore,
         assignments: CalendarDeadlineStore, qmplus: QMplusStore) {
        self.session = session
        presentation = session.detailPresentation
        self.teachingCloud = teachingCloud
        self.assignments = assignments
        self.qmplus = qmplus
    }

    private var selectionIsAvailable: Bool {
        guard let selected = session.detailSelection else { return false }
        switch selected.source {
        case .teachingCloud:
            return TeachingCloudCourseGrouping.group(containing: selected.courseID, in: teachingCloud.courses ?? []) != nil
        case .qmplus: return qmplus.snapshot?.courses.contains {
            $0.id == selected.courseID && QMplusCourseSelection.includesCourse($0)
        } == true
        }
    }

    var body: some View {
        InAppSheetPresentationHost(presentation: presentation) {
            if let selected = session.detailSelection {
                CourseCatalogDetailView(selection: selected, teachingCloud: teachingCloud,
                                        assignments: assignments, qmplus: qmplus, dismiss: session.dismissDetails)
            }
        }
        .onChange(of: selectionIsAvailable) { available in
            if !available { session.dismissDetails() }
        }
    }
}

private struct CourseCatalogDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    let selection: CourseCatalogSelection
    @ObservedObject var teachingCloud: TeachingCloudCourseStore
    @ObservedObject var assignments: CalendarDeadlineStore
    @ObservedObject var qmplus: QMplusStore
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    switch selection.source {
                    case .teachingCloud: teachingCloudDetail
                    case .qmplus: qmplusDetail
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.background)
            .navigationTitle(model.localized("课程详情"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.localized("完成"), action: dismiss)
                        .accessibilityIdentifier("course-detail.close")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, idealWidth: 520, minHeight: 400, idealHeight: 600)
        #endif
        .accessibilityIdentifier("course-detail.page")
    }

    @ViewBuilder private var teachingCloudDetail: some View {
        if let course = TeachingCloudCourseGrouping.group(containing: selection.courseID, in: teachingCloud.courses ?? []) {
            Text(model.isSampleMode ? model.localized(course.name ?? course.id) : course.name ?? course.id)
                .font(.title2.weight(.semibold))
            Text(model.localized("教学云本学期课程")).font(.caption).foregroundStyle(theme.secondaryText)
            Text("ID: \(course.courseIDs.sorted().joined(separator: ", "))").font(.caption).foregroundStyle(theme.secondaryText)
            if !course.teacherNames.isEmpty {
                Text(model.localized("教师") + ": " + course.teacherNames.map { model.isSampleMode ? model.localized($0) : $0 }.joined(separator: " · "))
            }
            if let fetchedAt = teachingCloud.fetchedAt { Text(fetchedAt, style: .date).font(.caption) }
            Link(model.localized("打开教学云平台"), destination: CalendarDeadlineSources.assignments)
                .accessibilityIdentifier("course-detail.open-official")
            HStack {
                Text(model.localized("本课已同步作业")).font(.headline)
                Spacer()
                Button(model.localized("刷新教学云作业")) {
                    Task { await assignments.loadAssignmentQuery(sampleMode: model.isSampleMode, force: true) }
                }
                .disabled(assignments.isLoadingAssignmentQuery)
                .accessibilityIdentifier("course-detail.refresh-assignments")
            }
            if assignments.isLoadingAssignmentQuery { ProgressView() }
            if !assignments.assignmentQueryError.isEmpty {
                Text(model.localized(assignments.assignmentQueryError)).font(.caption).foregroundStyle(theme.secondaryText)
            }
            Text(model.localized("以下内容仅来自本机已同步缓存；未列出不代表已经提交或没有作业。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            let cached = CourseListEvidence.cachedAssignments(query: assignments.assignmentQueryItems, byDate: assignments.assignmentsByDate)
            let items = CourseListEvidence.teachingCloudAssignments(group: course, cached: cached)
            if items.isEmpty {
                Text(model.localized("当前缓存没有可关联的本课作业。"))
                    .font(.callout).foregroundStyle(theme.secondaryText)
            }
            ForEach(items, id: \.teachingCloudDisplayID) { item in
                TeachingCloudCachedAssignmentRow(item: item)
            }
        } else { unavailableContent }
    }

    @ViewBuilder private var qmplusDetail: some View {
        if let course = qmplus.snapshot?.courses.first(where: {
            $0.id == selection.courseID && QMplusCourseSelection.includesCourse($0)
        }) {
            Text(course.name).font(.title2.weight(.semibold))
            if let shortName = course.shortName, !shortName.isEmpty { Text(shortName) }
            Text("QMplus · ID: \(course.id)").font(.caption).foregroundStyle(theme.secondaryText)
            Text(model.localized(termKey(course.currentTermStatus))).font(.caption).foregroundStyle(theme.secondaryText)
            Text(model.localized("时间按上海时区显示；原网页的伦敦时间说明保留。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            if let start = CourseListEvidence.qmplusShanghaiTime(course.startAt) { Text(model.localized("课程开始") + ": " + start).font(.caption) }
            if let end = CourseListEvidence.qmplusShanghaiTime(course.endAt) { Text(model.localized("课程结束") + ": " + end).font(.caption) }
            if let fetchedAt = CourseListEvidence.qmplusShanghaiTime(qmplus.snapshot?.fetchedAt) { Text(fetchedAt).font(.caption).foregroundStyle(theme.secondaryText) }
            Text(model.localized(qmplus.statusKey)).font(.caption).foregroundStyle(theme.secondaryText)
            if qmplus.isRetainingPreviousSnapshot {
                Text(model.localized("当前展示上次成功获取的课程，请留意更新时间。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("course-detail.qmplus.retained-cache")
            }
            Link(model.localized("打开官方课程页面"), destination: course.url)
                .accessibilityIdentifier("course-detail.open-official")
            Text(model.localized("本课已同步活动")).font(.headline)
            Text(model.localized("以下内容仅来自本机已同步缓存；未列出不代表已经提交或没有作业。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            let activities = CourseListEvidence.qmplusActivities(courseID: course.id, snapshot: qmplus.snapshot)
            if activities.isEmpty {
                Text(model.localized("当前缓存没有本课活动；无截止日期的活动也会保留。"))
                    .font(.callout).foregroundStyle(theme.secondaryText)
            }
            ForEach(activities) { item in
                QMplusCachedActivityRow(activity: item)
            }
        } else { unavailableContent }
    }

    private var unavailableContent: some View {
        Text(model.localized("本课缓存已清除或不再可用。"))
            .foregroundStyle(theme.secondaryText)
    }

    private func termKey(_ status: QMplusCurrentTermStatus) -> String {
        switch status {
        case .current: "本学期"
        case .other: "其他学期"
        case .unknown: "学期状态未确认"
        }
    }
}

struct TeachingCloudCachedAssignmentRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    let item: AssignmentDeadlineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.isSampleMode ? model.localized(item.title) : item.title).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text([item.deadline, item.status.map { model.localized($0) }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.assignment.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("course-detail.assignment.\(item.id)")
    }
}

struct QMplusCachedActivityRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    let activity: QMplusActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(activity.title, destination: activity.url).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(metadata.joined(separator: " · ")).font(.caption).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if activity.kind == .quiz {
                Text(model.localized("Quiz 开放区间不是固定考试时段。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if activity.detailStatus != "available" {
                Text(model.localized("活动详情受限或暂不可用，请以官方页面为准。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
            }
            if let raw = activity.rawTimeText, !raw.isEmpty { Text(raw).font(.caption).foregroundStyle(theme.secondaryText) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.assignment.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("courses.qmplus.activity.\(activity.id)")
    }

    private var metadata: [String] {
        var values = [activity.kind == .assignment ? "Assignment" : "Quiz"]
        switch activity.kind {
        case .assignment:
            values.append(timeText("截止时间", activity.dueAt))
            if let cutoff = activity.cutoffAt { values.append(timeText("最终提交时间", cutoff)) }
        case .quiz:
            values.append(timeText("开放时间", activity.opensAt))
            values.append(timeText("关闭时间", activity.closesAt))
            if let seconds = activity.timeLimitSeconds { values.append(model.localized("时间限制（秒）") + ": \(seconds)") }
        }
        if let status = activity.status, status != "unknown" { values.append(status) }
        return values
    }

    private func timeText(_ key: String, _ value: String?) -> String {
        model.localized(key) + ": " + (CourseListEvidence.qmplusShanghaiTime(value) ?? model.localized("未公布"))
    }
}
