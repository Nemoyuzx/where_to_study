import Foundation
import Combine

struct TeachingCloudCourse: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String?
    let teacherNames: [String]

    init(id: String, name: String?, teacherNames: [String] = []) {
        self.id = id
        self.name = name
        self.teacherNames = teacherNames
    }
}

protocol TeachingCloudCourseFetching: Sendable {
    func fetchCurrentCourses(force: Bool) async throws -> [TeachingCloudCourse]
    func reset() async
    func cachedCourseResult() async throws -> TeachingCloudCourseResult?
    func fetchCourseResult(force: Bool) async throws -> TeachingCloudCourseResult
    func isCourseScopeCurrent(_ scope: CourseBusinessCacheScope) -> Bool
}

struct TeachingCloudCourseResult: Sendable {
    let courses: [TeachingCloudCourse]
    let fetchedAt: Date
    var scope: CourseBusinessCacheScope? = nil
    var retainingPrevious = false
    var cachePersistenceFailed = false
    var ownerAccount: String? = nil // Ephemeral binding, never Codable/disk data.
}

extension TeachingCloudCourseFetching {
    func cachedCourseResult() async throws -> TeachingCloudCourseResult? { nil }
    func isCourseScopeCurrent(_: CourseBusinessCacheScope) -> Bool { true }
    func fetchCourseResult(force: Bool) async throws -> TeachingCloudCourseResult {
        let courses = try await fetchCurrentCourses(force: force)
        return .init(courses: courses, fetchedAt: .now)
    }
}

@MainActor
final class TeachingCloudCourseStore: ObservableObject {
    @Published private(set) var courses: [TeachingCloudCourse]?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isRetainingPreviousSnapshot = false
    private let client: any TeachingCloudCourseFetching
    private var owner: String?
    private var generation: UInt64 = 0
    private var flight: Task<TeachingCloudCourseResult, Error>?
    private var attempted = false

    init(client: any TeachingCloudCourseFetching) { self.client = client }

    func restoreCachedCourses(owner nextOwner: String, sampleMode: Bool) async {
        guard !sampleMode else { return }
        if owner != nextOwner { invalidate(); owner = nextOwner }
        let revision = generation
        guard let cached = try? await client.cachedCourseResult(), revision == generation,
              owner == nextOwner, !Task.isCancelled, accepts(cached, owner: nextOwner) else { return }
        // A startup warm completed elsewhere may have newer data even when this
        // surface already holds a nonnil old snapshot.
        if fetchedAt == nil || cached.fetchedAt >= fetchedAt! {
            courses = cached.courses; fetchedAt = cached.fetchedAt
            isRetainingPreviousSnapshot = cached.retainingPrevious
            if cached.cachePersistenceFailed {
                errorMessage = "本次课程数据已读取，但本地缓存未更新。重启后可能显示此前缓存。"
            } else if !cached.retainingPrevious { errorMessage = "" }
        }
    }

    func load(owner nextOwner: String, sampleMode: Bool, force: Bool = false) async {
        if owner != nextOwner { invalidate(); owner = nextOwner }
        if sampleMode {
            courses = [TeachingCloudCourse(id: "sample-course", name: "示例课程（非真实课程）", teacherNames: ["示例教师"])]
            return
        }
        if attempted, !force, flight == nil {
            await restoreCachedCourses(owner: nextOwner, sampleMode: sampleMode)
            return
        }
        attempted = true
        let revision = generation
        if courses == nil {
            if let cached = try? await client.cachedCourseResult(), revision == generation, owner == nextOwner,
               !Task.isCancelled, accepts(cached, owner: nextOwner) {
                courses = cached.courses; fetchedAt = cached.fetchedAt
            }
        }
        guard revision == generation, owner == nextOwner, !Task.isCancelled else {
            if revision == generation, owner == nextOwner { attempted = false }
            return
        }
        let selected: Task<TeachingCloudCourseResult, Error>
        if let flight { selected = flight } else {
            let client = client
            selected = Task { try await client.fetchCourseResult(force: force) }
            flight = selected
            isRefreshing = true
            isLoading = courses == nil
            errorMessage = ""
        }
        do {
            let result = try await selected.value
            guard revision == generation, owner == nextOwner, !Task.isCancelled,
                  accepts(result, owner: nextOwner) else {
                if revision == generation { flight = nil; isLoading = false; isRefreshing = false; attempted = false }
                return
            }
            courses = result.courses
            fetchedAt = result.fetchedAt
            isRetainingPreviousSnapshot = result.retainingPrevious
            errorMessage = result.cachePersistenceFailed
                ? "本次课程数据已读取，但本地缓存未更新。重启后可能显示此前缓存。" : ""
        } catch is CancellationError {
            // A cleared/switched owner must never publish a late result.
        } catch {
            guard revision == generation, owner == nextOwner, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            isRetainingPreviousSnapshot = courses != nil
        }
        if revision == generation { flight = nil; isLoading = false; isRefreshing = false }
    }

    private func accepts(_ result: TeachingCloudCourseResult, owner: String) -> Bool {
        guard let scope = result.scope else { return true }
        let account = String(owner.split(separator: "|", omittingEmptySubsequences: false).first ?? "")
        let parts = owner.split(separator: "|", omittingEmptySubsequences: false)
        return client.isCourseScopeCurrent(scope) && (parts.count != 3 || result.ownerAccount == nil ||
            CredentialSettingsLogic.normalizedAccount(account) == CredentialSettingsLogic.normalizedAccount(result.ownerAccount ?? ""))
    }

    func invalidate() {
        generation &+= 1
        flight?.cancel()
        flight = nil
        courses = nil
        fetchedAt = nil
        isRetainingPreviousSnapshot = false
        errorMessage = ""
        isLoading = false
        isRefreshing = false
        attempted = false
    }
}
