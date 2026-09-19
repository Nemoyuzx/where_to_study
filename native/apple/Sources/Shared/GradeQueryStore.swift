import Foundation
import SwiftUI

@MainActor
final class GradeQueryStore: ObservableObject {
    @Published private(set) var snapshot: GradeSnapshot?
    @Published private(set) var terms: [AcademicTerm] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var isSample = false
    @Published var selectedTerm: String?
    @Published var recordType = "1"
    private let client: any GradeFetching
    private var revision = 0
    private var owner = ""
    private var cache: [String: GradeQueryResult] = [:]
    private var cacheOrder: [String] = []
    private var attemptedKeys = Set<String>()

    init(client: any GradeFetching = SJDGradeClient()) { self.client = client }

    func reset() {
        revision &+= 1
        owner = ""
        snapshot = nil
        terms = []
        cache.removeAll()
        cacheOrder.removeAll()
        attemptedKeys.removeAll()
        isLoading = false
        errorMessage = ""
        isSample = false
    }

    func fail(message: String) {
        reset()
        errorMessage = message
    }

    func load(credentials: Credentials, ownerRevision: Int, termID: String?, recordType: String, force: Bool) async {
        let nextOwner = CourseDeletionLogic.accountKey(credentials.account) + ":" + String(ownerRevision)
        if owner != nextOwner { reset(); owner = nextOwner }
        let key = "\(termID ?? "<current>")|\(recordType)"
        if !force, attemptedKeys.contains(key), cache[key] == nil { return }
        attemptedKeys.insert(key)
        revision &+= 1
        let requestRevision = revision
        if !force, let cached = cache[key] {
            snapshot = cached.snapshot; terms = cached.terms; errorMessage = ""; isLoading = false
            return
        }
        if snapshot?.termID != termID || snapshot?.recordType != recordType { snapshot = nil }
        isLoading = true
        errorMessage = ""
        do {
            let result = try await client.fetch(credentials: credentials, termID: termID, recordType: recordType)
            guard requestRevision == revision, owner == nextOwner else { return }
            snapshot = result.snapshot
            terms = result.terms
            cache[key] = result
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            while cacheOrder.count > 8 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        } catch {
            guard requestRevision == revision, owner == nextOwner else { return }
            errorMessage = "成绩获取失败，请检查账户或稍后重试。"
        }
        guard requestRevision == revision else { return }
        isLoading = false
    }

    func loadSample(termID: String?, recordType: String) async {
        reset()
        isSample = true
        let term = termID ?? "2026-2027-1"
        terms = [.init(id: "2026-2027-1", name: "2026-2027-1")]
        snapshot = GradeSnapshot(termID: term, recordType: recordType, fetchedAt: SJDClassroomClient.timestamp(.now),
            averageGradePoint: nil, items: [
                .init(id: "demo-grade", name: "示例课程（非真实成绩）", score: "优秀", credits: "2", courseCode: "DEMO",
                      courseAttribute: nil, courseNature: nil, examNature: nil)
            ])
    }
}

struct GradeQueryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: GradeQueryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.localized("成绩查询")).font(.title2.bold())
                Spacer()
                Button { load(force: true) } label: { Label(model.localized("刷新"), systemImage: "arrow.clockwise") }
                    .disabled(store.isLoading)
                    .accessibilityIdentifier("grades.refresh")
            }
            if !store.terms.isEmpty {
                Picker(model.localized("学期"), selection: $store.selectedTerm) {
                    Text(model.localized("学校当前学期")).tag(String?.none)
                    Text(model.localized("全部学期")).tag(String?.some(""))
                    ForEach(store.terms) { term in Text(term.name).tag(String?.some(term.id)) }
                }
                .accessibilityIdentifier("grades.term")
                .onChange(of: store.selectedTerm) { _ in load() }
            }
            Picker(model.localized("成绩记录"), selection: $store.recordType) {
                Text(model.localized("最好成绩")).tag("1")
                Text(model.localized("首次成绩")).tag("0")
                Text(model.localized("全部记录")).tag("")
            }
            .pickerStyle(.segmented)
            .onChange(of: store.recordType) { _ in load() }
            if store.isSample {
                Label(model.localized("示例成绩，未连接学校服务"), systemImage: "info.circle").foregroundStyle(theme.secondaryText)
            }
            if store.isLoading { ProgressView(model.localized("正在获取成绩…")) }
            if !store.errorMessage.isEmpty {
                Text(model.localized(store.errorMessage)).foregroundStyle(theme.secondaryText)
                if !model.hasSavedPassword, !model.isSampleMode {
                    Button(model.localized("前往个人账户")) { model.navigation.selectedSection = .settings }
                        .accessibilityIdentifier("grades.account")
                }
            }
            if let snapshot = store.snapshot {
                if let average = snapshot.averageGradePoint {
                    LabeledContent(model.localized("平均学分绩点"), value: average)
                }
                if snapshot.items.isEmpty {
                    Text(model.localized("该学期暂无已公布成绩")).foregroundStyle(theme.secondaryText)
                }
                ForEach(snapshot.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name).font(.headline)
                            Spacer()
                            Text(item.score ?? model.localized("未公布")).font(.title3.bold())
                        }
                        if let credits = item.credits { Text(model.localized("学分") + "：" + credits) }
                        let metadata = [item.semesterName, item.courseCode, item.courseAttribute, item.courseNature, item.examNature, item.gradeStatus].compactMap { $0 }
                        if !metadata.isEmpty { Text(metadata.joined(separator: " · ")).font(.caption).foregroundStyle(theme.secondaryText) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                Text(model.localized("成绩仅保留在本次运行内，以学校公布结果为准。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queries.grades")
    }

    private func load(force: Bool = false) {
        Task { await model.loadGrades(termID: store.selectedTerm, recordType: store.recordType, force: force) }
    }
}
