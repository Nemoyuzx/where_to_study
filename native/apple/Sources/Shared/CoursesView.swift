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
    let assignments = AssignmentQuerySession()
    let detailPresentation = InAppPresentationState()
    private(set) var detailSelection: CourseCatalogSelection?

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
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        PageTitle(eyebrow: "Where To Study", title: model.localized("课程"), compact: proxy.size.height < 560)
                        QueryDestinationPicker(selection: $session.selectedMode, language: model.appLanguage,
                                               availableWidth: max(0, min(proxy.size.width, 1180) - 32),
                                               identifier: "courses.mode", titleKey: "课程类型")
                        switch session.selectedMode {
                        case .currentCourses:
                            teachingCloudSection
                            QMplusCourseSection(store: model.qmplus, session: session)
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
            .navigationTitle(model.localized("课程"))
        }
        .accessibilityIdentifier("screen.courses")
        .task(id: loadKey) {
            switch session.selectedMode {
            case .currentCourses:
                await teachingCloud.load(owner: loadKey.owner, sampleMode: model.isSampleMode)
            case .assignments:
                await assignmentStore.loadAssignmentQuery(sampleMode: model.isSampleMode)
            case .grades:
                await model.loadGrades(termID: model.gradeStore.selectedTerm, recordType: model.gradeStore.recordType)
            case .exams: break
            }
        }
    }

    private var teachingCloudSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.localized("教学云本学期课程")).font(.headline)
                        if let courses = teachingCloud.courses {
                            Text(model.localizedFormat("%d 门课程", courses.count)).font(.caption).foregroundStyle(theme.secondaryText)
                        }
                    }
                    Spacer()
                    Button(model.localized("刷新")) {
                        Task { await teachingCloud.load(owner: loadKey.owner, sampleMode: model.isSampleMode, force: true) }
                    }.disabled(teachingCloud.isLoading).accessibilityIdentifier("courses.ucloud.refresh")
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
                    PersonalAccountQueryButton(identifier: "courses.ucloud.account")
                }
                if let courses = teachingCloud.courses {
                    let cached = CourseListEvidence.cachedAssignments(query: assignmentStore.assignmentQueryItems,
                                                                     byDate: assignmentStore.assignmentsByDate)
                    if courses.isEmpty { Text(model.localized("本学期暂无教学云课程")).foregroundStyle(theme.secondaryText) }
                    ForEach(courses) { course in
                        let assignments = CourseListEvidence.teachingCloudAssignments(course: course, roster: courses, cached: cached)
                        CourseCatalogRow(title: model.isSampleMode ? model.localized(course.name ?? course.id) : course.name ?? course.id,
                                         metadata: course.teacherNames.map { model.isSampleMode ? model.localized($0) : $0 }.joined(separator: " · "),
                                         metadataSymbol: "person", counts: CourseListEvidence.submissionCounts(statuses: assignments.map(\.status)),
                                         identifier: "courses.ucloud.course.\(course.id)") {
                            session.presentDetails(source: .teachingCloud, courseID: course.id)
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
                    Text(model.localized("QMplus 课程与活动")).font(.headline)
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
            Text(model.localized("QMplus 使用独立的官方网页登录，与北邮教务账号无关。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            if let snapshot = store.snapshot {
                let selected = QMplusCourseSelection(snapshot: snapshot, showsOtherTerms: session.showsOtherQMplusTerms)
                Text((CourseListEvidence.qmplusShanghaiTime(snapshot.fetchedAt) ?? snapshot.fetchedAt) + " · Asia/Shanghai")
                    .font(.caption).foregroundStyle(theme.secondaryText)
                if snapshot.courses.contains(where: { QMplusCourseSelection.includesCourse($0) && $0.currentTermStatus == .other }) {
                    Toggle(model.localized("显示其他学期／历史课程"), isOn: $session.showsOtherQMplusTerms)
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
                                     identifier: "courses.qmplus.course.\(course.id)") {
                        session.presentDetails(source: .qmplus, courseID: course.id)
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
