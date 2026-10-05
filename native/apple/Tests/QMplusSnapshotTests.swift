import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

@MainActor
final class QMplusSnapshotTests: XCTestCase {
    func testWarmStartupRechecksSceneEligibilityAfterAwaitAndDoesNotStartAHiddenLogin() async throws {
        let suite = "QMplusWarmSceneRace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        var checks = 0
        await store.launchWarmOnce(sampleMode: false, canStart: { checks += 1; return false })
        XCTAssertEqual(checks, 1)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertFalse(store.requiresManualContinuation)
        XCTAssertNil(store.webView, "A scene which became inactive during cache restoration must not open a login page")
    }

    func testCancelledWarmStartupDoesNotConsumeTheLoginOwner() async throws {
        let suite = "QMplusCancelledWarm.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let task = Task { @MainActor in await store.launchWarmOnce(sampleMode: false) }
        task.cancel()
        await task.value
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true), "The cancelled startup must leave the sole owner available")
        store.endPresentation()
    }

    func testReconnectionRequestsFreshDashboardWithoutReplayingCallbackOrAttachingSecrets() {
        let request = QMplusStore.dashboardRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://qmplus.qmul.ac.uk/my/")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }
    func testLiveErrorReportedBySyncRevokesButtonAndPreservesPriorSnapshot() throws {
        for code in ["QM_LOGIN_REQUIRED", "QM_ERROR_PAGE"] {
            let suite = "QMLivePageError.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
            let seed = try XCTUnwrap(store.beginSynchronization())
            store.receive(try payload(), request: seed)
            let previous = store.snapshot
            XCTAssertTrue(store.beginConnectionOwner(quiet: false))
            XCTAssertTrue(store.acceptOfficialPageStatus(.authenticated, context: store.currentConnectionContext))
            let flight = try XCTUnwrap(store.beginSynchronization())
            store.receive(Data("{\"ok\":false,\"partial\":false,\"error_code\":\"\(code)\"}".utf8), request: flight)
            XCTAssertFalse(store.canSynchronize)
            XCTAssertFalse(store.isSyncing)
            XCTAssertEqual(store.snapshot, previous)
            XCTAssertTrue(store.isRetainingPreviousSnapshot)
        }
    }
    func testGuestErrorAndLateProofCannotEnableSynchronizationOrReplacePriorData() throws {
        let suite = "QMPageProof.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let seed = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: seed)
        let prior = store.snapshot
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        let context = store.currentConnectionContext
        XCTAssertTrue(store.acceptOfficialPageStatus(.guest, context: context))
        XCTAssertFalse(store.canSynchronize)
        XCTAssertTrue(store.acceptOfficialPageStatus(.authenticated, context: context))
        XCTAssertTrue(store.canSynchronize)
        let late = try XCTUnwrap(store.beginSynchronization())
        XCTAssertTrue(store.acceptOfficialPageStatus(.error, context: context))
        XCTAssertFalse(store.canSynchronize)
        XCTAssertFalse(store.isSyncing)
        XCTAssertEqual(store.navigationFailureCode, "QM_OFFICIAL_EXCEPTION")
        XCTAssertEqual(store.statusKey, "QMplus 官方网页登录失败，请重试")
        store.receive(try payload(title: "Late rejected result"), request: late)
        XCTAssertEqual(store.snapshot, prior)
        store.endPresentation()
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        XCTAssertFalse(store.acceptOfficialPageStatus(.authenticated, context: context))
        XCTAssertFalse(store.canSynchronize)
    }
    func testVerifiedSynchronizationHidesVisibleSheetWithoutCancellingOwnerOrResult() throws {
        let suite = "QMSyncHide.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        let request = try XCTUnwrap(store.beginSynchronization())
        store.hideVerifiedConnectionForSynchronization()
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.isSyncing)
        store.connectionSheetDidDismiss()
        XCTAssertTrue(store.isSyncing, "Automatic dismissal must not cancel the flight")
        store.receive(try payload(), request: request)
        XCTAssertNotNil(store.snapshot)
        XCTAssertFalse(store.isSyncing)
        XCTAssertFalse(store.hasActiveConnection)
    }

    func testDisabledFeaturePreservesCacheAndSessionMetadataButRejectsLateResults() throws {
        let suite = "QMFeatureOff.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("synthetic-profile-id", forKey: "qmplusWebsiteDataStoreIdentifier")
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let prior = try XCTUnwrap(store.snapshot)
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        let late = try XCTUnwrap(store.beginSynchronization())
        store.setFeatureEnabled(false)
        store.receive(try payload(title: "Late result"), request: late)
        XCTAssertEqual(store.snapshot, prior)
        XCTAssertEqual(defaults.string(forKey: "qmplusWebsiteDataStoreIdentifier"), "synthetic-profile-id")
        XCTAssertNil(store.beginSynchronization())
        XCTAssertFalse(store.beginConnectionOwner(quiet: false))
        store.setFeatureEnabled(true)
        store.receive(try payload(title: "Still stale"), request: late)
        XCTAssertEqual(store.snapshot, prior)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        store.endPresentation()
    }

    func testOldSheetDismissalCannotCancelAReplacementVisibleOrQuietOwner() throws {
        let suite = "QMOldDismissal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        _ = try XCTUnwrap(store.beginSynchronization())
        store.hideVerifiedConnectionForSynchronization()
        store.endPresentation()
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        store.connectionSheetDidDismiss()
        XCTAssertTrue(store.hasActiveConnection)
        store.endPresentation()
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        store.connectionSheetDidDismiss()
        XCTAssertTrue(store.hasActiveConnection)
        store.endPresentation()
    }
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

    func testAdministrativeItemIsValidatedBeforeTheDecoderExcludesIt() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [String: Any])
        let quiz = try XCTUnwrap((object["activities"] as? [[String: Any]])?.first)
        var review = quiz
        review["id"] = "3"
        review["kind"] = "assignment"
        review["title"] = "COURSEWORK MARK REVIEW REQUEST"
        review["url"] = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3"
        object["activities"] = [quiz, review]
        let decoded = try QMplusSnapshotPolicy.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.activities.map(\.id), ["2"])
        for invalidURL in ["https://foreign.invalid/mod/assign/view.php?id=3",
                           "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3&sesskey=synthetic",
                           "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=3"] {
            var invalid = review
            invalid["url"] = invalidURL
            object["activities"] = [quiz, invalid]
            XCTAssertThrowsError(try QMplusSnapshotPolicy.decode(JSONSerialization.data(withJSONObject: object)))
        }
        object["activities"] = [quiz, review, review]
        XCTAssertThrowsError(try QMplusSnapshotPolicy.decode(JSONSerialization.data(withJSONObject: object)),
                             "Duplicate IDs must not be concealed by administrative filtering")
        var invalidDate = review
        invalidDate["due_at"] = "not-a-date"
        object["activities"] = [quiz, invalidDate]
        XCTAssertThrowsError(try QMplusSnapshotPolicy.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testPartialRetentionCannotRestoreReviewRequestsOrDropRealHomeworkWithoutDueDates() throws {
        let suite = "QMplusAdministrativePartialTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [String: Any])
        var courses = try XCTUnwrap(object["courses"] as? [[String: Any]])
        courses[0]["name"] = "EBU Original course"
        object["courses"] = courses
        let quiz = try XCTUnwrap((object["activities"] as? [[String: Any]])?.first)
        var review = quiz
        review["id"] = "3"
        review["kind"] = "assignment"
        review["title"] = "COURSEWORK MARK REVIEW REQUEST"
        review["url"] = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3"
        review["status"] = "not submitted"
        var homework = review
        homework["id"] = "4"
        homework["title"] = "Real homework without a deadline"
        homework["url"] = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=4"
        homework["status"] = "submitted"
        object["activities"] = [quiz, review, homework]
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try JSONSerialization.data(withJSONObject: object), request: first)
        let verified = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(verified.activities.map(\.id), ["2", "4"])
        XCTAssertNil(verified.activities.last?.dueAt)

        object["partial"] = true
        object["warnings"] = ["QM_DETAIL_PARTIAL"]
        object["fetched_at"] = "2026-10-04T12:00:00.000Z"
        homework["title"] = "Incomplete replacement title"
        object["activities"] = [quiz, review, homework]
        let partial = try XCTUnwrap(store.beginSynchronization())
        store.receive(try JSONSerialization.data(withJSONObject: object), request: partial)
        let retained = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(retained, verified)
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        XCTAssertEqual(CourseListEvidence.qmplusActivities(courseID: "1", snapshot: retained).map(\.id), ["2", "4"])
        XCTAssertEqual(QMplusCourseSelection(snapshot: retained, showsOtherTerms: false).activities.map(\.id), ["2", "4"])
        XCTAssertEqual(CourseListEvidence.qmplusCounts(activities: retained.activities), CourseSubmissionCounts(pending: 0, submitted: 1))
        XCTAssertNil(store.webView, "The partial regression uses only synthetic business snapshots")
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
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        let late = try XCTUnwrap(store.beginSynchronization())
        store.disconnect()
        store.receive(try payload(), request: late)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isSyncing)
        XCTAssertFalse(store.isRetainingPreviousSnapshot)
        XCTAssertNil(store.webView, "Pure snapshot tests must not launch a browser")
    }

    func testOriginFailureCannotEraseLastGoodSnapshot() throws {
        let suite = "QMplusFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let previous = try XCTUnwrap(store.snapshot)
        let second = try XCTUnwrap(store.beginSynchronization())
        store.receive(Data("{\"ok\":false,\"partial\":false,\"error_code\":\"QM_LOGIN_REQUIRED\"}".utf8), request: second)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        XCTAssertEqual(store.statusKey, "QMplus 官方网页登录失败，请重试")
        XCTAssertFalse(store.isSyncing)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.isShowingConnection)
        store.receive(try payload(title: "Retired failure callback"), request: second)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertNil(store.webView, "A synthetic expired-session result must not launch a browser or read a real session")
    }

    func testCompletedVisibleAndQuietFlightsRejectLateFailureAndDuplicateResult() throws {
        for quiet in [false, true] {
            let suite = "QMplusLateFailureTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
            XCTAssertTrue(store.beginConnectionOwner(quiet: quiet))
            let completed = try XCTUnwrap(store.beginSynchronization())
            store.receive(try payload(), request: completed)
            let verified = try XCTUnwrap(store.snapshot)

            // Directly drive the same boundary used by a WebKit failure callback.
            // The visible owner keeps its generation, so the active-flight guard
            // must reject this even when the request ID still matches.
            store.finishFailure(request: completed)
            store.receive(try payload(title: "Late synthetic title"), request: completed)
            store.receive(Data("{\"ok\":false,\"partial\":false,\"error_code\":\"QM_LOGIN_REQUIRED\"}".utf8), request: completed)
            XCTAssertEqual(store.snapshot, verified)
            XCTAssertEqual(store.statusKey, "QMplus 同步完成")
            XCTAssertFalse(store.isSyncing)
            XCTAssertFalse(store.isPartial)
            XCTAssertFalse(store.isRetainingPreviousSnapshot)
            XCTAssertEqual(store.hasActiveConnection, !quiet)
            XCTAssertEqual(store.isShowingConnection, !quiet)
            XCTAssertNil(store.webView, "Fake terminal callbacks must not open WebKit or use a real session")
            store.endPresentation()
        }
    }

    func testCancelledFlightCannotReviveAnOwnerOrFinishAReplacementRequest() throws {
        let suite = "QMplusCancelledReplacementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let verified = try XCTUnwrap(store.snapshot)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        let cancelled = try XCTUnwrap(store.beginSynchronization())
        store.cancelQuietConnection()
        store.finishFailure(request: cancelled)
        store.receive(try payload(title: "Cancelled late title"), request: cancelled)
        XCTAssertEqual(store.snapshot, verified)
        XCTAssertEqual(store.statusKey, "QMplus 同步已取消，可重新连接后重试")
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertFalse(store.isSyncing)

        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        let replacement = try XCTUnwrap(store.beginSynchronization())
        store.finishFailure(request: cancelled)
        store.receive(try payload(title: "Superseded late title"), request: cancelled)
        XCTAssertTrue(store.isSyncing, "An obsolete callback must not finish the new flight")
        XCTAssertEqual(store.statusKey, "正在同步 QMplus 课程与活动…")
        XCTAssertEqual(store.snapshot, verified)
        store.receive(try payload(title: "Replacement verified title", fetchedAt: "2026-10-04T12:00:00.000Z"), request: replacement)
        XCTAssertEqual(store.snapshot?.fetchedAt, "2026-10-04T12:00:00.000Z")
        XCTAssertEqual(store.snapshot?.activities.first?.title, "Replacement verified title")
        XCTAssertEqual(store.statusKey, "QMplus 同步完成")
        XCTAssertFalse(store.isRetainingPreviousSnapshot)
        XCTAssertFalse(store.isSyncing)
        XCTAssertNil(store.webView)
        store.endPresentation()
    }

    func testNewRefreshFailureMarksRetainedSnapshotAndOnlyAValidatedRefreshClearsIt() throws {
        let suite = "QMplusRetainedRefreshTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(due: "2026-10-04T12:00:00Z"), request: first)
        let verified = try XCTUnwrap(store.snapshot)
        let failed = try XCTUnwrap(store.beginSynchronization())
        store.finishFailure(request: failed)
        XCTAssertEqual(store.snapshot, verified)
        XCTAssertEqual(store.snapshot?.fetchedAt, verified.fetchedAt)
        XCTAssertEqual(store.snapshot?.activities.first?.dueAt, "2026-10-04T12:00:00Z")
        XCTAssertEqual(store.statusKey, "QMplus 同步失败，请检查官方网页登录状态后重试")
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        XCTAssertFalse(store.isSyncing)

        let retry = try XCTUnwrap(store.beginSynchronization())
        XCTAssertTrue(store.isRetainingPreviousSnapshot, "Starting a retry cannot relabel old data as freshly verified")
        store.receive(try payload(title: "New verified title", fetchedAt: "2026-10-04T12:00:00.000Z"), request: retry)
        XCTAssertEqual(store.snapshot?.fetchedAt, "2026-10-04T12:00:00.000Z")
        XCTAssertFalse(store.isRetainingPreviousSnapshot)
        XCTAssertEqual(store.statusKey, "QMplus 同步完成")
        let abandoned = try XCTUnwrap(store.beginSynchronization())
        store.endPresentation()
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        store.disconnect()
        store.finishFailure(request: abandoned)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isRetainingPreviousSnapshot)
        XCTAssertEqual(store.statusKey, "QMplus 尚未连接")
        XCTAssertNil(store.webView)
    }

    func testClosingConnectionCancelsPendingFlightAndRejectsLateResultWithoutClaimingSuccess() throws {
        let suite = "QMplusPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults)
        let request = try XCTUnwrap(store.beginSynchronization())
        store.endPresentation()
        store.receive(try payload(), request: request)
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertFalse(store.isSyncing)
        XCTAssertFalse(store.canSynchronize)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.statusKey, "QMplus 同步已取消，可重新连接后重试")
        XCTAssertNil(store.webView, "The lifecycle regression must not open a website or real account")
    }

    func testQuietSyncCanPublishValidatedSnapshotWithoutASheetAndCannotPublishAfterCancellation() throws {
        let suite = "QMplusQuietTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        XCTAssertFalse(store.beginConnectionOwner(quiet: true), "Only one logical connection owner may be active")
        XCTAssertFalse(store.isShowingConnection)
        let completed = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: completed)
        let previous = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(store.statusKey, "QMplus 同步完成")
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        let cancelled = try XCTUnwrap(store.beginSynchronization())
        store.cancelQuietConnection()
        store.receive(try payload(title: "Late synthetic title"), request: cancelled)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView, "Pure quiet-owner tests must not open WebKit or touch a real session")
    }

    func testQuietFailureKeepsSameOwnerHiddenUntilExplicitManualRetryWithoutErasingPreviousSnapshot() throws {
        let suite = "QMplusQuietFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let previous = try XCTUnwrap(store.snapshot)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        let failed = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(activityURL: "https://evil.invalid/mod/quiz/view.php?id=2"), request: failed)
        XCTAssertFalse(store.isShowingConnection, "An ordinary sync failure must not automatically reveal a login page")
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.requiresManualContinuation)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.beginConnectionOwner(quiet: false), "Failure must preserve the same session, not create another owner")
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        XCTAssertEqual(store.statusKey, "QMplus 同步失败，请检查官方网页登录状态后重试")
        XCTAssertFalse(store.isSyncing)
        store.receive(try payload(title: "Retired failure callback"), request: failed)
        XCTAssertEqual(store.snapshot, previous)
        store.continueManually(sampleMode: false)
        XCTAssertTrue(store.isShowingConnection, "Only the explicit manual action may reveal this non-MFA page")
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertFalse(store.requiresManualContinuation)
        XCTAssertFalse(store.beginConnectionOwner(quiet: true))
        XCTAssertFalse(store.isSyncing)
        XCTAssertNil(store.webView, "Showing the existing synthetic owner must not create WebKit")
        store.endPresentation()
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertNil(store.webView)
    }

    func testInactiveSceneSuspendsQuietWorkButPreservesItsOwnerAndLastVerifiedSnapshot() throws {
        let suite = "QMplusInactiveQuietTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let previous = try XCTUnwrap(store.snapshot)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        let late = try XCTUnwrap(store.beginSynchronization())
        store.stopAutomaticLoginForInactiveScene()
        store.receive(try payload(title: "Late synthetic title"), request: late)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertTrue(store.hasActiveConnection, "Switching to an authenticator app must preserve the same connection owner")
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertFalse(store.isSyncing)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.beginConnectionOwner(quiet: false), "Inactivity must not permit a second owner")
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
        XCTAssertNil(store.webView)
        store.endPresentation()
        store.resumeAuthenticationRecognitionForActiveScene()
        store.receive(try payload(title: "After explicit close"), request: late)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.isShowingConnection)
    }

    func testInactiveSceneRetainsVisibleManualOwnerAndRejectsOldSyncWithoutErasingLastGoodData() throws {
        let suite = "QMplusInactiveVisibleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let previous = try XCTUnwrap(store.snapshot)
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        XCTAssertTrue(store.hasActiveAutofillLedger)
        let late = try XCTUnwrap(store.beginSynchronization())
        store.stopAutomaticLoginForInactiveScene()
        store.receive(try payload(title: "Late synthetic title"), request: late)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.isShowingConnection)
        XCTAssertFalse(store.isSyncing)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.beginConnectionOwner(quiet: true), "Inactivity must not create a second login owner")
        XCTAssertNil(store.webView)
        store.endPresentation()
    }

    func testForegroundRecognitionResumesVisibleOwnerAndPreservedLedgerWithoutCreatingARequest() throws {
        let suite = "QMplusForegroundRecognitionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        XCTAssertTrue(store.hasActiveAuthenticationRecognition)
        XCTAssertTrue(store.hasActiveAutofillLedger)
        let oldRequest = try XCTUnwrap(store.beginSynchronization())
        store.stopAutomaticLoginForInactiveScene()
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.isShowingConnection)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        let manualStatus = store.statusKey

        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertTrue(store.hasActiveAuthenticationRecognition)
        XCTAssertTrue(store.hasActiveAutofillLedger, "Foregrounding restores access to the same once-only ledger, not fresh stage budgets")
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.isShowingConnection, "The user's visible MFA presentation must remain open")
        XCTAssertFalse(store.beginConnectionOwner(quiet: true))
        XCTAssertFalse(store.isSyncing, "Foregrounding alone must not construct a synthetic sync request")
        XCTAssertEqual(store.statusKey, manualStatus)
        store.receive(try payload(title: "Retired callback"), request: oldRequest)
        XCTAssertNil(store.snapshot)
        let recognized = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(title: "Verified after foreground"), request: recognized)
        XCTAssertEqual(store.statusKey, "QMplus 同步完成")
        XCTAssertEqual(store.snapshot?.activities.first?.title, "Verified after foreground")
        XCTAssertTrue(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.isSyncing)
        XCTAssertNil(store.webView, "This lifecycle test must not load a webpage or real session")

        store.endPresentation()
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.isShowingConnection)
    }

    func testForegroundRecognitionResumesThePreservedQuietOwnerButCannotReviveAnExplicitlyClosedOwner() throws {
        let suite = "QMplusQuietForegroundTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        let late = try XCTUnwrap(store.beginSynchronization())
        store.stopAutomaticLoginForInactiveScene()
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.hasActiveAuthenticationRecognition)
        XCTAssertTrue(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.beginConnectionOwner(quiet: false), "Foregrounding must reuse the existing owner")
        XCTAssertFalse(store.isSyncing)
        XCTAssertFalse(store.isShowingConnection)
        store.receive(try payload(title: "Retired quiet callback"), request: late)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.webView)
        store.endPresentation()
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertNil(store.webView)
    }

    func testRepeatedConnectKeepsExistingQuietFlightHiddenWithoutStartingAnotherBrowserOrRequest() throws {
        let suite = "QMplusRepeatedConnectTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: true))
        XCTAssertEqual(store.statusKey, "正在确认 QMplus 登录状态…")
        let request = try XCTUnwrap(store.beginSynchronization())
        store.connect(sampleMode: false)
        XCTAssertFalse(store.isShowingConnection, "Repeating Connect must not reveal an ordinary in-flight page")
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.requiresManualContinuation)
        XCTAssertFalse(store.beginConnectionOwner(quiet: false))
        XCTAssertTrue(store.isSyncing)
        XCTAssertNil(store.beginSynchronization())
        XCTAssertNil(store.webView)
        store.endPresentation()
        store.resumeAuthenticationRecognitionForActiveScene()
        store.receive(try payload(), request: request)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.hasActiveAuthenticationRecognition)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertFalse(store.isShowingConnection)
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
        XCTAssertTrue(store.isRetainingPreviousSnapshot)
    }

    private func payload(partial: Bool = false, title: String = "Synthetic quiz", schema: Int = 1,
                         activityURL: String = "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=2",
                         due: String? = nil, fetchedAt: String = "2026-10-03T12:00:00.000Z") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schema_version": schema, "source": "qmplus", "fetched_at": fetchedAt,
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
