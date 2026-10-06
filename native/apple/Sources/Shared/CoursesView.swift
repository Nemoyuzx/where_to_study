import SwiftUI

enum CourseQueryMode: String, QueryDestinationMode {
    case currentCourses, assignments, grades, exams
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .currentCourses: "本学期课程"
        case .assignments: "课程作业 DDL"
        case .grades: "成绩查询"
        case .exams: "考试安排"
        }
    }
    var systemImage: String {
        switch self {
        case .currentCourses: "books.vertical"
        case .assignments: "checklist"
        case .grades: "chart.bar.xaxis"
        case .exams: "doc.text.magnifyingglass"
        }
    }
}

@MainActor
final class CoursesViewSession: ObservableObject {
    @Published var selectedMode = CourseQueryMode.currentCourses
    @Published var showsOtherQMplusTerms = false
    @Published private(set) var expandedCourseKeys = Set<String>()
    let assignments = AssignmentQuerySession()
    let detailPresentation = InAppPresentationState()
    private(set) var detailSelection: CourseCatalogSelection?

    func isExpanded(source: CourseCatalogSource, courseID: String) -> Bool {
        expandedCourseKeys.contains(source.rawValue + "|" + courseID)
    }

    func toggleExpansion(source: CourseCatalogSource, courseID: String) {
        let key = source.rawValue + "|" + courseID
        if !expandedCourseKeys.insert(key).inserted { expandedCourseKeys.remove(key) }
    }

    func collapseQMplus() { expandedCourseKeys = expandedCourseKeys.filter { !$0.hasPrefix("qmplus|") } }

    func presentDetails(source: CourseCatalogSource, courseID: String) {
        detailSelection = CourseCatalogSelection(source: source, courseID: courseID)
        if !detailPresentation.isPresented { detailPresentation.isPresented = true }
    }

    func dismissDetails() {
        if detailPresentation.isPresented { detailPresentation.isPresented = false }
        detailSelection = nil
    }

    func reset() {
        dismissDetails()
        selectedMode = .currentCourses
        showsOtherQMplusTerms = false
        expandedCourseKeys.removeAll()
        assignments.query = ""
        assignments.showsEnded = false
    }
}

private struct CourseLoadKey: Equatable {
    let account: String
    let credentialRevision: Int
    let sampleMode: Bool
    let mode: CourseQueryMode
    var owner: String { "\(account)|\(credentialRevision)|\(sampleMode)" }
}

struct CoursesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @ObservedObject var session: CoursesViewSession
    @ObservedObject var teachingCloud: TeachingCloudCourseStore
    @ObservedObject var assignmentStore: CalendarDeadlineStore
    private var loadKey: CourseLoadKey {
        CourseLoadKey(account: model.account, credentialRevision: model.assignmentCredentialRevision,
                      sampleMode: model.isSampleMode, mode: session.selectedMode)
    }

    var body: some View {
        GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        PageTitle(eyebrow: "Where To Study", title: model.localized("课程"), compact: proxy.size.height < 560)
                            .accessibilityIdentifier("courses.page-title")
                        QueryDestinationPicker(selection: $session.selectedMode, language: model.appLanguage,
                                               availableWidth: max(0, min(proxy.size.width, 1180) - 32),
                                               identifier: "courses.mode", titleKey: "课程类型")
                        switch session.selectedMode {
                        case .currentCourses:
                            teachingCloudSection
                            if model.qmplusEnabled {
                                QMplusCourseSection(store: model.qmplus, session: session)
                            }
                        case .assignments: AssignmentQueryView(store: assignmentStore, session: session.assignments)
                        case .grades: GradeQueryView(store: model.gradeStore)
                        case .exams: ExamQueryView()
                        }
                    }
                    .padding(16).frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
            }
            .background(theme.background)
            #if os(macOS)
            .navigationTitle(model.localized("课程"))
            #endif
        .accessibilityIdentifier("screen.courses")
        .onAppear { dismissDisabledQMplusDetails() }
        .onChange(of: model.qmplusEnabled) { _ in dismissDisabledQMplusDetails() }
        .task(id: loadKey) {
            switch session.selectedMode {
            case .currentCourses:
                await teachingCloud.restoreCachedCourses(owner: loadKey.owner, sampleMode: model.isSampleMode)
                await assignmentStore.restoreCachedAssignments(sampleMode: model.isSampleMode)
                await assignmentStore.loadAssignmentQuery(sampleMode: model.isSampleMode)
                await teachingCloud.load(owner: loadKey.owner, sampleMode: model.isSampleMode)
            case .assignments:
                await assignmentStore.loadAssignmentQuery(sampleMode: model.isSampleMode)
            case .grades:
                await model.loadGrades(termID: model.gradeStore.selectedTerm, recordType: model.gradeStore.recordType)
            case .exams: break
            }
        }
    }

    private func dismissDisabledQMplusDetails() {
        if !model.qmplusEnabled { session.collapseQMplus() }
        if !model.qmplusEnabled, session.detailSelection?.source == .qmplus { session.dismissDetails() }
    }

    private var teachingCloudSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.localized("教学云本学期课程")).font(.headline)
                        if let courses = teachingCloud.courseGroups {
                            Text(model.localizedFormat("%d 门课程", courses.count)).font(.caption).foregroundStyle(theme.secondaryText)
                        }
                    }
                    Spacer()
                    Button(model.localized("刷新")) {
                        Task {
                            await assignmentStore.loadAssignmentQuery(sampleMode: model.isSampleMode, force: true)
                            await teachingCloud.restoreCachedCourses(owner: loadKey.owner, sampleMode: model.isSampleMode)
                            await teachingCloud.load(owner: loadKey.owner, sampleMode: model.isSampleMode)
                        }
                    }.disabled(teachingCloud.isRefreshing || assignmentStore.isRefreshingAssignmentQuery)
                        .accessibilityIdentifier("courses.ucloud.refresh")
                }
                if model.isSampleMode {
                    Text(model.localized("示例课程，未连接教学云")).font(.caption).foregroundStyle(theme.secondaryText)
                }
                if teachingCloud.isLoading { ProgressView(model.localized("正在获取本学期课程…")) }
                if !teachingCloud.errorMessage.isEmpty {
                    Text(model.localized(teachingCloud.errorMessage)).foregroundStyle(theme.secondaryText)
                    if teachingCloud.courses != nil {
                        Text(model.localized("当前展示上次成功获取的课程，请留意更新时间。"))
                            .font(.caption).foregroundStyle(theme.secondaryText)
                    }
                    if teachingCloud.showsAccountAction {
                        PersonalAccountQueryButton(identifier: "courses.ucloud.account")
                    }
                }
                if let courses = teachingCloud.courseGroups {
                    let cached = CourseListEvidence.cachedAssignments(query: assignmentStore.assignmentQueryItems,
                                                                     byDate: assignmentStore.assignmentsByDate)
                    if courses.isEmpty { Text(model.localized("本学期暂无教学云课程")).foregroundStyle(theme.secondaryText) }
                    ForEach(courses) { course in
                        let assignments = CourseListEvidence.teachingCloudAssignments(group: course, cached: cached)
                        CourseCatalogRow(title: model.isSampleMode ? model.localized(course.name ?? course.id) : course.name ?? course.id,
                                         metadata: course.teacherNames.map { model.isSampleMode ? model.localized($0) : $0 }.joined(separator: " · "),
                                         metadataSymbol: "person", counts: CourseListEvidence.submissionCounts(statuses: assignments.map(\.status)),
                                         identifier: "courses.ucloud.course.\(course.id)",
                                         isExpanded: session.isExpanded(source: .teachingCloud, courseID: course.id),
                                         toggle: { session.toggleExpansion(source: .teachingCloud, courseID: course.id) }, details: {
                            session.presentDetails(source: .teachingCloud, courseID: course.id)
                        }) {
                            VStack(alignment: .leading, spacing: 10) {
                                if assignments.isEmpty {
                                    Text(model.localized("当前缓存没有可关联的本课作业。"))
                                        .font(.caption).foregroundStyle(theme.secondaryText)
                                }
                                ForEach(assignments, id: \.teachingCloudDisplayID) { TeachingCloudCachedAssignmentRow(item: $0) }
                                Button(model.localized("刷新教学云作业")) {
                                    Task { await assignmentStore.loadAssignmentQuery(sampleMode: model.isSampleMode, force: true) }
                                }
                                .disabled(assignmentStore.isLoadingAssignmentQuery)
                                .accessibilityIdentifier("courses.ucloud.course.\(course.id).refresh-assignments")
                                Text(model.localized("以下内容仅来自本机已同步缓存；未列出不代表已经提交或没有作业。"))
                                    .font(.caption).foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                    Text(model.localized("待交／已交仅统计已同步且提交状态明确的作业。"))
                        .font(.caption).foregroundStyle(theme.secondaryText)
                }
                if let fetchedAt = teachingCloud.fetchedAt {
                    Text(fetchedAt, style: .time).font(.caption).foregroundStyle(theme.secondaryText)
                }
                Link(model.localized("打开教学云平台"), destination: CalendarDeadlineSources.assignments)
            }
    }
}

private struct QMplusCourseSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: QMplusStore
    @ObservedObject var session: CoursesViewSession

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.localized("QMplus 课程与活动")).font(.headline)
                        Text(model.localized("仅适用国院")).font(.caption).foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let snapshot = store.snapshot {
                        Text(model.localizedFormat("%d 门课程", QMplusCourseSelection(snapshot: snapshot,
                             showsOtherTerms: session.showsOtherQMplusTerms).courses.count))
                            .font(.caption).foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer()
                Button(model.localized("连接 QMplus")) { store.connect(sampleMode: model.isSampleMode) }
                    .disabled(model.isSampleMode).accessibilityIdentifier("courses.qmplus.connect")
            }
            Text(model.localized(store.statusKey)).font(.caption).foregroundStyle(theme.secondaryText)
            if store.requiresManualContinuation {
                Button { store.continueManually(sampleMode: model.isSampleMode) } label: {
                    Label(model.localized("手动继续"), systemImage: "arrow.up.forward.app")
                }.buttonStyle(.bordered).disabled(model.isSampleMode)
            }
            if store.isRetainingPreviousSnapshot {
                Text(model.localized("当前展示上次成功获取的课程，请留意更新时间。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("courses.qmplus.retained-cache")
            }
            Text(model.localized("QMplus 使用独立的官方网页登录，与北邮教务账号无关。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            if let snapshot = store.snapshot {
                let selected = QMplusCourseSelection(snapshot: snapshot, showsOtherTerms: session.showsOtherQMplusTerms)
                Text((CourseListEvidence.qmplusShanghaiTime(snapshot.fetchedAt) ?? snapshot.fetchedAt) + model.localized("（北京时间）"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                if snapshot.courses.contains(where: { QMplusCourseSelection.includesCourse($0) && $0.currentTermStatus == .other }) {
                    Toggle(model.localized("显示其他学期／历史课程"), isOn: $session.showsOtherQMplusTerms)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("courses.qmplus.other-terms")
                }
                if selected.courses.isEmpty {
                    Text(model.localized("当前筛选没有本学期或学期未确认的课程。"))
                        .font(.caption).foregroundStyle(theme.secondaryText)
                }
                ForEach(selected.courses) { course in
                    let activities = CourseListEvidence.qmplusActivities(courseID: course.id, snapshot: snapshot)
                    CourseCatalogRow(title: course.name, metadata: model.localized(termKey(course.currentTermStatus)),
                                     metadataSymbol: "calendar", counts: CourseListEvidence.qmplusCounts(activities: activities),
                                     identifier: "courses.qmplus.course.\(course.id)",
                                     isExpanded: session.isExpanded(source: .qmplus, courseID: course.id),
                                     toggle: { session.toggleExpansion(source: .qmplus, courseID: course.id) }, details: {
                        session.presentDetails(source: .qmplus, courseID: course.id)
                    }) {
                        VStack(alignment: .leading, spacing: 10) {
                            if activities.isEmpty {
                                Text(model.localized("当前缓存没有本课活动；无截止日期的活动也会保留。"))
                                    .font(.caption).foregroundStyle(theme.secondaryText)
                            }
                            ForEach(activities) { QMplusCachedActivityRow(activity: $0) }
                            Text(model.localized("以下内容仅来自本机已同步缓存；未列出不代表已经提交或没有作业。"))
                                .font(.caption).foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                Text(model.localized("待交／已交仅统计已同步且提交状态明确的作业。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                if selected.activities.isEmpty {
                    Text(model.localized("当前筛选没有活动；不代表所有作业已完成。"))
                        .font(.caption).foregroundStyle(theme.secondaryText)
                }
            } else {
                Text(model.localized("在官方网页登录后同步本学期课程、Assignment 与 Quiz。"))
                    .font(.callout).foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func termKey(_ status: QMplusCurrentTermStatus) -> String {
        switch status {
        case .current: "本学期"
        case .other: "其他学期"
        case .unknown: "学期状态未确认"
        }
    }

}
