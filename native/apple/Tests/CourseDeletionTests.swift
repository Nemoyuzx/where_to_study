import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class CourseDeletionTests: XCTestCase {
    private let monday = StrictContractDateParser.date(from: "2026-09-07")!

    private func course(id: String = "row", sourceID: String? = "official-course", weekday: Int = 1, start: Int = 0, weeks: [Int] = [1, 2, 3]) -> Course {
        Course(id: id, name: "Course", teacher: "Teacher", room: "Room", weekText: "1-3周",
               weekNumbers: weeks, examWeekNumbers: [], weekday: weekday, startSlot: start, endSlot: start + 1,
               sectionText: "1-2节", timeRange: "08:00-09:50", sourceCourseID: sourceID)
    }

    private func snapshot(_ courses: [Course]) -> ScheduleSnapshot {
        ScheduleSnapshot(termID: "2026-2027-1", termStartDate: "2026-09-07", fetchedAt: "fixture", courses: courses)
    }

    func testOccurrenceRemovesOnlyItsDateAndSlotsAndReleasesBusyPeriods() throws {
        let selected = course()
        let sameDayOtherSlots = course(id: "afternoon", start: 4)
        let otherDay = course(id: "tuesday", weekday: 2)
        let raw = snapshot([selected, sameDayOtherSlots, otherDay])
        let deletion = CourseDeletion(account: "a", termID: raw.termID, course: selected, date: monday, scope: .occurrence)
        let effective = CourseDeletionLogic.applying([deletion], to: raw, account: "a")
        XCTAssertEqual(effective.courses[0].weekNumbers, [2, 3])
        XCTAssertEqual(effective.courses[1].weekNumbers, [1, 2, 3])
        XCTAssertEqual(effective.courses[2].weekNumbers, [1, 2, 3])
        XCTAssertEqual(ScheduleLogic.busySlots(on: monday, termStart: monday, courses: effective.courses), [4, 5])
        XCTAssertEqual(raw.courses[0].weekNumbers, [1, 2, 3])
    }

    func testWholeCourseSurvivesMeetingChangesAndIsScopedByAccountAndTerm() {
        let selected = course()
        let raw = snapshot([course(id: "fresh-row", weekday: 3), course(id: "different", sourceID: "other-course")])
        let deletion = CourseDeletion(account: "a", termID: raw.termID, course: selected, date: monday, scope: .course)
        XCTAssertEqual(CourseDeletionLogic.applying([deletion], to: raw, account: "a").courses.map(\.id), ["different"])
        XCTAssertEqual(CourseDeletionLogic.applying([deletion], to: raw, account: "b"), raw)
        let newTerm = ScheduleSnapshot(termID: "2026-2027-2", termStartDate: raw.termStartDate, fetchedAt: raw.fetchedAt, courses: raw.courses)
        XCTAssertEqual(CourseDeletionLogic.applying([deletion], to: newTerm, account: "a"), newTerm)
    }

    func testLegacyIdentityFallbackAndOptionalSourceIDDecoding() throws {
        let selected = course(sourceID: nil)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(selected)) as? [String: Any])
        data.removeValue(forKey: "source_course_id")
        let legacy = try JSONDecoder().decode(Course.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertNil(legacy.sourceCourseID)
        let deletion = CourseDeletion(account: "a", termID: "2026-2027-1", course: legacy, date: monday, scope: .course)
        XCTAssertTrue(deletion.matches(course(sourceID: "new-source-id")))
        XCTAssertTrue(CourseDeletion(account: "a", termID: "2026-2027-1", course: course(), date: monday, scope: .course).matches(legacy))
    }

    func testPersistentDeletionCanBeRestoredWithoutChangingRawSchedule() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CourseDeletionPersistence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCourseDeletionStore(fileURL: directory.appendingPathComponent("deletions.json"))
        let raw = snapshot([course()])
        let deletion = CourseDeletion(account: "a", termID: raw.termID, course: raw.courses[0], date: monday, scope: .course)
        try store.save([deletion])
        XCTAssertTrue(CourseDeletionLogic.applying(try store.load(), to: raw, account: "a").courses.isEmpty)
        try store.save([])
        XCTAssertEqual(CourseDeletionLogic.applying(try store.load(), to: raw, account: "a"), raw)
        try store.clear()
        XCTAssertEqual(try store.load(), [])
    }

    func testSerializedDeletionUsesHashScopeAndWholeCourseDoesNotNeedValidTermDate() throws {
        let selected = course()
        let deletion = CourseDeletion(account: "fake-student-account", termID: "2026-2027-1", course: selected, date: monday, scope: .course)
        let json = String(decoding: try JSONEncoder().encode(deletion), as: UTF8.self)
        XCTAssertFalse(json.contains("fake-student-account"))
        XCTAssertTrue(deletion.accountScope.hasPrefix("sha256:"))
        let invalidDate = ScheduleSnapshot(termID: "2026-2027-1", termStartDate: "invalid", fetchedAt: "fixture", courses: [selected])
        XCTAssertTrue(CourseDeletionLogic.applying([deletion], to: invalidDate, account: " fake-student-account ").courses.isEmpty)
    }

    func testDeletionFileLimitsRejectOversizedReadsWritesAndExcessRecordsWithoutReplacingSavedData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CourseDeletionLimits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCourseDeletionStore(fileURL: directory.appendingPathComponent("records.json"))
        let deletion = CourseDeletion(account: "a", termID: "2026-2027-1", course: course(), date: monday, scope: .course)
        try store.save([deletion])
        let tooMany = Array(repeating: deletion, count: FileCourseDeletionStore.maximumRecordCount + 1)
        XCTAssertThrowsError(try store.save(tooMany))
        XCTAssertEqual(try store.load(), [deletion])
        var huge = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(deletion)) as? [String: Any])
        huge["name"] = String(repeating: "x", count: FileCourseDeletionStore.maximumPayloadBytes)
        let hugeDeletion = try JSONDecoder().decode(CourseDeletion.self, from: JSONSerialization.data(withJSONObject: huge))
        XCTAssertThrowsError(try store.save([hugeDeletion]))
        XCTAssertEqual(try store.load(), [deletion])
        try JSONEncoder().encode(tooMany).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        try Data(repeating: 0x20, count: FileCourseDeletionStore.maximumPayloadBytes + 1).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }

    func testExistingInvalidDeletionFileIsNeverTreatedAsAnEmptyRecordSet() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CourseDeletionInvalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FileCourseDeletionStore(fileURL: directory.appendingPathComponent("records.json"))
        XCTAssertEqual(try store.load(), [])
        try Data("invalid JSON".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try FileCourseDeletionStore(fileURL: directory).load())
    }

    func testUnmappableCorruptWeekAndWeekdayValuesDoNotOverflow() {
        let deletion = CourseDeletion(account: "a", termID: "2026-2027-1", course: course(), date: monday, scope: .occurrence)
        let raw = snapshot([course(weeks: [1, Int.max, Int.min]), course(id: "bad-day", weekday: Int.max)])
        let effective = CourseDeletionLogic.applying([deletion], to: raw, account: "a")
        XCTAssertEqual(effective.courses[0].weekNumbers, [Int.max, Int.min])
        XCTAssertEqual(effective.courses[1].weekNumbers, [1, 2, 3])
    }
}
