import Foundation
import Combine

struct TeachingCloudCourse: Identifiable, Equatable, Sendable {
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
}

@MainActor
final class TeachingCloudCourseStore: ObservableObject {
    @Published private(set) var courses: [TeachingCloudCourse]?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var fetchedAt: Date?
    private let client: any TeachingCloudCourseFetching
    private var owner: String?
    private var generation: UInt64 = 0
    private var flight: Task<[TeachingCloudCourse], Error>?
    private var attempted = false

    init(client: any TeachingCloudCourseFetching) { self.client = client }

    func load(owner nextOwner: String, sampleMode: Bool, force: Bool = false) async {
        if owner != nextOwner { invalidate(); owner = nextOwner }
        if sampleMode {
            courses = [TeachingCloudCourse(id: "sample-course", name: "示例课程（非真实课程）", teacherNames: ["示例教师"])]
            return
        }
        if attempted, !force, flight == nil { return }
        attempted = true
        let revision = generation
        let selected: Task<[TeachingCloudCourse], Error>
        if let flight { selected = flight } else {
            let client = client
            selected = Task { try await client.fetchCurrentCourses(force: force) }
            flight = selected
            isLoading = true
            errorMessage = ""
        }
        do {
            let result = try await selected.value
            guard revision == generation, owner == nextOwner, !Task.isCancelled else { return }
            courses = result
            fetchedAt = .now
        } catch is CancellationError {
            // A cleared/switched owner must never publish a late result.
        } catch {
            guard revision == generation, owner == nextOwner, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if revision == generation { flight = nil; isLoading = false }
    }

    func invalidate() {
        generation &+= 1
        flight?.cancel()
        flight = nil
        courses = nil
        fetchedAt = nil
        errorMessage = ""
        isLoading = false
        attempted = false
    }
}
