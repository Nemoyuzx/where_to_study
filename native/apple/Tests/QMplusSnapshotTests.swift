import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

@MainActor
final class QMplusSnapshotTests: XCTestCase {
    func testNavigationFailureProjectsOnlyKnownDomainAndNumericCode() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                            userInfo: [NSLocalizedDescriptionKey: "fixture-private-error-text",
                                       NSURLErrorFailingURLErrorKey: URL(string: "https://login.microsoftonline.com/?code=fixture-not-a-real-code") as Any])
        XCTAssertEqual(QMplusStore.safeNavigationFailureCode(error), "URL_ERROR_-1001")
        XCTAssertNil(QMplusStore.safeNavigationFailureCode(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertEqual(QMplusStore.safeNavigationFailureCode(NSError(domain: "fixture-private-domain", code: 1)), "WEB_NAVIGATION_FAILED")
    }

    func testDefaultCourseSelectionExcludesHistoryAndKeepsUnknownWithMatchingActivities() throws {
        let base = try QMplusSnapshotPolicy.decode(payload())
        func course(_ id: String, status: QMplusCurrentTermStatus) throws -> QMplusCourse {
            QMplusCourse(id: id, name: "EBU Original API course \(id)", shortName: nil,
                         url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/course/view.php?id=\(id)")),
                         startAt: nil, endAt: nil, currentTermStatus: status)
        }
        func activity(_ id: String, courseID: String) throws -> QMplusActivity {
            QMplusActivity(id: id, courseID: courseID, title: "Original API activity \(id)", kind: .quiz,
                           url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=\(id)")),
                           dueAt: nil, opensAt: nil, closesAt: nil, cutoffAt: nil, timeLimitSeconds: nil,
                           status: "unknown", detailStatus: "available", rawTimeText: nil)
        }
        let snapshot = QMplusSnapshot(schemaVersion: 1, source: "qmplus", fetchedAt: base.fetchedAt,
                                      courses: [try course("1", status: .unknown), try course("3", status: .current), try course("4", status: .other)],
                                      activities: [try activity("5", courseID: "1"), try activity("6", courseID: "3"),
                                                   try activity("7", courseID: "4")], warnings: [])
        let current = QMplusCourseSelection(snapshot: snapshot, showsOtherTerms: false)
        XCTAssertEqual(current.courses.map(\.id), ["1", "3"])
        XCTAssertEqual(current.courses.first?.currentTermStatus, .unknown)
        XCTAssertEqual(current.activities.map(\.id), ["5", "6"])
        let all = QMplusCourseSelection(snapshot: snapshot, showsOtherTerms: true)
        XCTAssertEqual(all.courses, snapshot.courses)
        XCTAssertEqual(all.activities, snapshot.activities)
        XCTAssertEqual(snapshot.courses.count, 3, "Presentation filters must never delete API data")
        XCTAssertNotEqual(AppLocalization.string("显示其他学期／历史课程", language: .english), "显示其他学期／历史课程")
    }

    func testCachedNonEBUCoursesAndTheirActivitiesStayExcludedEvenWithHistoryEnabled() throws {
        let base = try QMplusSnapshotPolicy.decode(payload())
        let original = try XCTUnwrap(base.courses.first)
        let included = QMplusCourse(id: "3", name: "eBu Synthetic course", shortName: nil,
                                   url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/course/view.php?id=3")),
                                   startAt: nil, endAt: nil, currentTermStatus: .current)
        let activity = QMplusActivity(id: "4", courseID: "3", title: "Original API quiz", kind: .quiz,
                                     url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=4")),
                                     dueAt: nil, opensAt: nil, closesAt: nil, cutoffAt: nil,
                                     timeLimitSeconds: nil, status: "unknown", detailStatus: "available", rawTimeText: nil)
        let snapshot = QMplusSnapshot(schemaVersion: 1, source: "qmplus", fetchedAt: base.fetchedAt,
                                      courses: [original, included], activities: base.activities + [activity], warnings: [])
        for history in [false, true] {
            let selection = QMplusCourseSelection(snapshot: snapshot, showsOtherTerms: history)
            XCTAssertEqual(selection.courses.map(\.id), ["3"])
            XCTAssertEqual(selection.activities.map(\.id), ["4"])
            XCTAssertEqual(selection.courses.first?.name, "eBu Synthetic course")
        }
        XCTAssertEqual(snapshot.courses.count, 2, "The complete old snapshot must not be rewritten")
        XCTAssertEqual(snapshot.activities.count, 2)
    }

    func testNullableDeadlinesAndUnconfirmedTermRemainExplicit() throws {
        let result = try QMplusSnapshotPolicy.decode(payload())
        XCTAssertEqual(result.courses.first?.name, "Synthetic API course 2026/27")
        XCTAssertEqual(result.courses.first?.currentTermStatus, .unknown)
        XCTAssertEqual(result.activities.count, 1)
        XCTAssertNil(result.activities.first?.dueAt)
        XCTAssertNil(result.activities.first?.closesAt)
        XCTAssertEqual(result.activities.first?.kind, .quiz)
        XCTAssertEqual(result.activities.first?.status, "unknown")
    }

    func testNativeDecoderRejectsSecretsInLinksForeignOriginsAndWrongSchema() throws {
        for url in ["http://qmplus.qmul.ac.uk/mod/quiz/view.php?id=2",
                    "https://qmplus.qmul.ac.uk.evil.invalid/mod/quiz/view.php?id=2",
                    "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=2&sesskey=synthetic",
                    "https://qmplus.qmul.ac.uk/admin/index.php?id=2"] {
            XCTAssertThrowsError(try QMplusSnapshotPolicy.decode(payload(activityURL: url)))
        }
        XCTAssertThrowsError(try QMplusSnapshotPolicy.decode(payload(schema: 2)))
        XCTAssertThrowsError(try QMplusSnapshotPolicy.decode(payload(due: "2026-10-03T12:00:00+01:00")))
        XCTAssertThrowsError(try QMplusSnapshotPolicy.decode(Data(repeating: 0x20, count: QMplusSnapshotPolicy.maximumBytes + 1)))
        XCTAssertFalse(QMplusStore.isSyncOrigin(URL(string: "https://login.microsoftonline.com/")))
        XCTAssertFalse(QMplusStore.isSyncOrigin(URL(string: "https://qmplus.qmul.ac.uk:444/my/")))
        XCTAssertTrue(QMplusStore.isSyncOrigin(URL(string: "https://qmplus.qmul.ac.uk/my/")))
    }

    func testBusinessReencodingOmitsUnrecognizedSessionFields() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [String: Any])
        object["cookie"] = "fixture-not-a-real-cookie"
        object["sesskey"] = "fixture-not-a-real-session"
        let sanitized = try QMplusSnapshotPolicy.decode(JSONSerialization.data(withJSONObject: object))
        let encoded = String(decoding: try JSONEncoder().encode(sanitized), as: UTF8.self)
        XCTAssertFalse(encoded.contains("fixture-not-a-real"))
        XCTAssertFalse(encoded.contains("sesskey"))
    }

    func testPartialRetainsPreviousSnapshotAndDisconnectRejectsLatePublication() throws {
        let suite = "QMplusSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults)
        let first = try XCTUnwrap(store.beginSynchronization())
        XCTAssertNil(store.beginSynchronization(), "Native synchronization must be single-flight")
        store.receive(try payload(), request: first)
        let original = try XCTUnwrap(store.snapshot)
        let partial = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(partial: true, title: "Incomplete new title"), request: partial)
        XCTAssertEqual(store.snapshot, original)
        XCTAssertTrue(store.isPartial)
        let late = try XCTUnwrap(store.beginSynchronization())
        store.disconnect()
        store.receive(try payload(), request: late)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isSyncing)
        XCTAssertNil(store.webView, "Pure snapshot tests must not launch a browser")
    }

    func testOriginFailureCannotEraseLastGoodSnapshot() throws {
        let suite = "QMplusFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let second = try XCTUnwrap(store.beginSynchronization())
        store.receive(Data("{\"ok\":false,\"partial\":false,\"error_code\":\"QM_LOGIN_REQUIRED\"}".utf8), request: second)
        XCTAssertEqual(store.snapshot?.activities.count, 1)
        XCTAssertEqual(store.statusKey, "请先在 QMplus 官方网页完成登录")
        XCTAssertFalse(store.isSyncing)
    }

    func testRestrictedQuizDoesNotBlockOtherNewDeadlines() throws {
        let suite = "QMplusRestrictedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(due: "2026-10-04T12:00:00Z"), request: first)
        let original = try XCTUnwrap(store.snapshot)
        var restricted = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [String: Any])
        var activities = try XCTUnwrap(restricted["activities"] as? [[String: Any]])
        activities[0]["detail_status"] = "restricted"
        var newAssignment = activities[0]
        newAssignment["id"] = "3"
        newAssignment["title"] = "New known assignment"
        newAssignment["kind"] = "assignment"
        newAssignment["url"] = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3"
        newAssignment["detail_status"] = "available"
        newAssignment["due_at"] = "2026-10-05T12:00:00Z"
        activities.append(newAssignment)
        restricted["activities"] = activities
        let second = try XCTUnwrap(store.beginSynchronization())
        store.receive(try JSONSerialization.data(withJSONObject: restricted), request: second)
        XCTAssertNotEqual(store.snapshot, original)
        XCTAssertEqual(store.snapshot?.activities.count, 2)
        XCTAssertEqual(store.snapshot?.activities.first?.detailStatus, "restricted")
        XCTAssertNil(store.snapshot?.activities.first?.dueAt, "A restricted detail remains unknown, not freshly verified")
        XCTAssertEqual(store.snapshot?.activities.last?.dueAt, "2026-10-05T12:00:00Z")
        XCTAssertFalse(store.isPartial)
    }

    func testFailedDetailWarningsRetainPreviousVerifiedDeadline() throws {
        let suite = "QMplusUnavailableTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(due: "2026-10-04T12:00:00Z"), request: first)
        let original = try XCTUnwrap(store.snapshot)
        var unavailable = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [String: Any])
        unavailable["warnings"] = ["QM_DETAIL_PARTIAL"]
        var activities = try XCTUnwrap(unavailable["activities"] as? [[String: Any]])
        activities[0]["detail_status"] = "unavailable"
        unavailable["activities"] = activities
        let second = try XCTUnwrap(store.beginSynchronization())
        store.receive(try JSONSerialization.data(withJSONObject: unavailable), request: second)
        XCTAssertEqual(store.snapshot, original)
        XCTAssertEqual(store.snapshot?.fetchedAt, original.fetchedAt)
        XCTAssertEqual(store.snapshot?.activities.first?.dueAt, "2026-10-04T12:00:00Z")
        XCTAssertTrue(store.isPartial)
    }

    private func payload(partial: Bool = false, title: String = "Synthetic quiz", schema: Int = 1,
                         activityURL: String = "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=2",
                         due: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schema_version": schema, "source": "qmplus", "fetched_at": "2026-10-03T12:00:00.000Z",
            "ok": true, "partial": partial, "warnings": partial ? ["QM_DETAIL_PARTIAL"] : [],
            "courses": [["id": "1", "name": "Synthetic API course 2026/27", "short_name": "API name",
                         "url": "https://qmplus.qmul.ac.uk/course/view.php?id=1",
                         "start_at": NSNull(), "end_at": NSNull(), "current_term_status": "unknown"]],
            "activities": [["id": "2", "course_id": "1", "title": title, "kind": "quiz", "url": activityURL,
                            "due_at": due as Any? ?? NSNull(), "opens_at": NSNull(), "closes_at": NSNull(),
                            "cutoff_at": NSNull(), "time_limit_seconds": NSNull(), "status": "unknown",
                            "detail_status": "available", "raw_time_text": "No deadline published"]]
        ])
    }
}
