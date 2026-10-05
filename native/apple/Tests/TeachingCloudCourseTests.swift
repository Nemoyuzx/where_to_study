import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

@MainActor
final class TeachingCloudCourseTests: XCTestCase {
    func testDisplayGroupingUsesTrimmedExactNamesAndLeavesSourceRecordsUnchanged() throws {
        let courses = [
            TeachingCloudCourse(id: "class-b", name: " Same course\n", teacherNames: [" Tutor B ", "Tutor A", " "]),
            TeachingCloudCourse(id: "class-a", name: "Same course", teacherNames: ["Tutor A", "Tutor C"]),
            TeachingCloudCourse(id: "case-sensitive", name: "same course", teacherNames: []),
            TeachingCloudCourse(id: "unnamed-a", name: nil),
            TeachingCloudCourse(id: "unnamed-b", name: " \n ")
        ]
        let original = try JSONEncoder().encode(courses)
        let groups = TeachingCloudCourseGrouping.groups(courses)
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups.map(\.id), ["class-a", "case-sensitive", "unnamed-a", "unnamed-b"])
        XCTAssertEqual(groups[0].name, "Same course")
        XCTAssertEqual(groups[0].courseIDs, Set(["class-a", "class-b"]))
        XCTAssertEqual(groups[0].teacherNames, ["Tutor A", "Tutor B", "Tutor C"])
        XCTAssertEqual(groups[0].courses.map(\.id), ["class-a", "class-b"])
        XCTAssertNil(groups[2].name)
        XCTAssertNil(groups[3].name)
        XCTAssertEqual(groups.flatMap(\.courses).count, courses.count)
        XCTAssertEqual(try JSONDecoder().decode([TeachingCloudCourse].self, from: original), courses,
                       "Grouping must not rewrite cached source names, teachers or IDs")
    }

    func testGroupRepresentativeAndMemberLookupDoNotDependOnRosterOrder() throws {
        let a = TeachingCloudCourse(id: "a", name: "Course", teacherNames: ["Tutor B"])
        let b = TeachingCloudCourse(id: "b", name: " Course ", teacherNames: ["Tutor A"])
        let forward = try XCTUnwrap(TeachingCloudCourseGrouping.group(containing: "a", in: [a, b]))
        let reversed = try XCTUnwrap(TeachingCloudCourseGrouping.group(containing: "b", in: [b, a]))
        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.id, "a")
        XCTAssertEqual(forward.teacherNames, ["Tutor A", "Tutor B"])
        XCTAssertNil(TeachingCloudCourseGrouping.group(containing: "missing", in: [a, b]))
        XCTAssertTrue(TeachingCloudCourseGrouping.groups([]).isEmpty)
    }

    func testDefaultCourseDestinationAndMovedAcademicModesHaveEnglishNames() {
        let session = CoursesViewSession()
        XCTAssertEqual(session.selectedMode, .currentCourses)
        XCTAssertFalse(session.showsOtherQMplusTerms)
        XCTAssertEqual(InformationQueryMode.allCases, [.shuttle, .importantEvents])
        XCTAssertEqual(CourseQueryMode.allCases, [.currentCourses, .assignments, .grades, .exams])
        for mode in CourseQueryMode.allCases {
            XCTAssertNotEqual(AppLocalization.string(mode.titleKey, language: .english), mode.titleKey)
        }
        session.selectedMode = .assignments
        session.assignments.query = "untranslated API name"
        session.assignments.showsEnded = true
        session.showsOtherQMplusTerms = true
        session.reset()
        XCTAssertEqual(session.selectedMode, .currentCourses)
        XCTAssertEqual(session.assignments.query, "")
        XCTAssertFalse(session.assignments.showsEnded)
        XCTAssertFalse(session.showsOtherQMplusTerms)
    }

    func testCourseStoreRetainsCacheAcrossReappearanceAndFailedRefresh() async {
        let client = CurrentCourseFixture()
        let store = TeachingCloudCourseStore(client: client)
        await store.load(owner: "owner", sampleMode: false)
        await store.load(owner: "owner", sampleMode: false)
        let calls = await client.calls
        XCTAssertEqual(calls, 1)
        let first = store.courses
        XCTAssertEqual(store.courseGroups?.flatMap(\.courses), first)
        await client.failNext()
        await store.load(owner: "owner", sampleMode: false, force: true)
        XCTAssertEqual(store.courses, first)
        XCTAssertFalse(store.errorMessage.isEmpty)
        store.invalidate()
        XCTAssertNil(store.courses)
        XCTAssertNil(store.courseGroups)
        await store.load(owner: "sample", sampleMode: true)
        let finalCalls = await client.calls
        XCTAssertEqual(finalCalls, 2, "Sample mode must not contact teaching cloud")
    }

    func testTeachingCloudActorSharesCurrentCourseFlightAndResetsItWithCredentials() async throws {
        let credentials = CurrentCourseCredentials()
        let recorder = CurrentCourseFixture()
        let client = UCloudAssignmentClient(credentialStore: credentials, fetchAll: { _ in [] },
                                           fetchCourses: { _ in try await recorder.fetchCurrentCourses(force: false) })
        async let first = client.fetchCurrentCourses(force: false)
        async let second = client.fetchCurrentCourses(force: false)
        let values = try await (first, second)
        XCTAssertEqual(values.0, values.1)
        _ = try await client.fetchCurrentCourses(force: false)
        let calls = await recorder.calls
        XCTAssertEqual(calls, 1)
        credentials.clear()
        do { _ = try await client.fetchCurrentCourses(force: false); XCTFail("Cleared credentials must invalidate cached courses") }
        catch { XCTAssertTrue(error is CalendarDeadlineError) }
    }
}

private actor CurrentCourseFixture: TeachingCloudCourseFetching {
    private(set) var calls = 0
    private var fails = false
    func failNext() { fails = true }
    func fetchCurrentCourses(force _: Bool) async throws -> [TeachingCloudCourse] {
        calls += 1
        await Task.yield()
        if fails { throw URLError(.timedOut) }
        return [.init(id: "synthetic-course", name: "Original API name")]
    }
    func reset() async {}
}

private final class CurrentCourseCredentials: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Credentials? = .init(account: "fixture-course-account", password: "fixture-only")
    func load() throws -> Credentials? { lock.withLock { value } }
    func save(_ credentials: Credentials) throws { lock.withLock { value = credentials } }
    func clear() { lock.withLock { value = nil } }
}
