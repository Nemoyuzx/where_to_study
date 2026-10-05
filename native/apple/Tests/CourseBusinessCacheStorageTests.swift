import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class CourseBusinessCacheStorageTests: XCTestCase {
    func testFirstLaunchCreatesGuardAndMissingPayloadIsACacheMiss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wts-course-cache-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = CourseBusinessCacheStorage(directory: directory, enabled: true)
        let scope = try storage.scope(kind: .courses, owner: "ucloud")
        XCTAssertEqual(scope, try storage.scope(kind: .assignments, owner: "ucloud"))
        let missing = try storage.load(kind: .courses, scope: scope, maximumBytes: 4096,
                                       as: [TeachingCloudCourse].self)
        XCTAssertNil(missing)
        let courses = [TeachingCloudCourse(id: "synthetic-course", name: "Synthetic course")]
        let value = CourseBusinessCachedValue(schemaVersion: 1, scope: scope,
            fetchedAt: ISO8601DateFormatter().string(from: Date()), partial: false, payload: courses)
        try storage.save(value, kind: .courses, maximumBytes: 4096)
        let reopened = CourseBusinessCacheStorage(directory: directory, enabled: true)
        let reopenedScope = try reopened.scope(kind: .courses, owner: "ucloud")
        XCTAssertEqual(reopenedScope, scope)
        let restored = try reopened.load(kind: .courses, scope: reopenedScope, maximumBytes: 4096,
                                         as: [TeachingCloudCourse].self)
        XCTAssertEqual(restored?.payload, courses)
    }

    func testExistingPendingOrCorruptGuardIsNeverRecreatedAsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wts-course-cache-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let guardURL = directory.appendingPathComponent("ucloud-guard.json")
        let pending = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "epoch": UUID().uuidString, "pending": true,
        ])
        for bytes in [pending, Data("not-json".utf8)] {
            try bytes.write(to: guardURL)
            let storage = CourseBusinessCacheStorage(directory: directory, enabled: true)
            XCTAssertThrowsError(try storage.scope(kind: .courses, owner: "ucloud"))
            XCTAssertEqual(try Data(contentsOf: guardURL), bytes)
        }
    }
}
