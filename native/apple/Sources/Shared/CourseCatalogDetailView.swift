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
        case .teachingCloud: return teachingCloud.courses?.contains { $0.id == selected.courseID } == true
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
        if let course = teachingCloud.courses?.first(where: { $0.id == selection.courseID }) {
            Text(model.isSampleMode ? model.localized(course.name ?? course.id) : course.name ?? course.id)
                .font(.title2.weight(.semibold))
            Text(model.localized("教学云本学期课程")).font(.caption).foregroundStyle(theme.secondaryText)
            Text("ID: \(course.id)").font(.caption).foregroundStyle(theme.secondaryText)
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
            let items = CourseListEvidence.teachingCloudAssignments(course: course, roster: teachingCloud.courses ?? [], cached: cached)
            if items.isEmpty {
                Text(model.localized("当前缓存没有可关联的本课作业。"))
                    .font(.callout).foregroundStyle(theme.secondaryText)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isSampleMode ? model.localized(item.title) : item.title).font(.headline)
                    Label(item.deadline, systemImage: "calendar.badge.clock").font(.caption)
                    if let status = item.status { Text(model.localized(status)).font(.caption).foregroundStyle(theme.secondaryText) }
                    Divider()
                }.accessibilityIdentifier("course-detail.assignment.\(item.id)")
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

private struct QMplusCachedActivityRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    let activity: QMplusActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(activity.title, destination: activity.url).font(.headline)
            Text(activity.kind == .assignment ? "Assignment" : "Quiz").font(.caption)
            switch activity.kind {
            case .assignment:
                timeRow("截止时间", value: activity.dueAt)
                if let cutoff = activity.cutoffAt { timeRow("最终提交时间", value: cutoff) }
            case .quiz:
                timeRow("开放时间", value: activity.opensAt)
                timeRow("关闭时间", value: activity.closesAt)
                if let seconds = activity.timeLimitSeconds { Text(model.localized("时间限制（秒）") + ": \(seconds)").font(.caption) }
                Text(model.localized("Quiz 开放区间不是固定考试时段。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
            }
            if let status = activity.status, status != "unknown" { Text(status).font(.caption) }
            if activity.detailStatus != "available" {
                Text(model.localized("活动详情受限或暂不可用，请以官方页面为准。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
            }
            if let raw = activity.rawTimeText, !raw.isEmpty { Text(raw).font(.caption).foregroundStyle(theme.secondaryText) }
            Divider()
        }.accessibilityIdentifier("courses.qmplus.activity.\(activity.id)")
    }

    private func timeRow(_ key: String, value: String?) -> some View {
        Text(model.localized(key) + ": " + (CourseListEvidence.qmplusShanghaiTime(value) ?? model.localized("未公布")))
            .font(.caption).foregroundStyle(theme.secondaryText)
    }
}
