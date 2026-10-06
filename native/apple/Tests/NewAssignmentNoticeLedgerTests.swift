import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class NewAssignmentNoticeLedgerTests: XCTestCase {
    private let scope = CourseBusinessCacheScope(owner: "ucloud", epoch: "synthetic-epoch")

    private func batch(_ count: Int, kind: CourseBusinessCacheKind = .assignments,
                       scope: CourseBusinessCacheScope? = nil) -> NewAssignmentNoticeBatch {
        .init(scope: scope ?? self.scope, kind: kind, storage: CourseBusinessCacheStorage(enabled: false),
              items: (0..<count).map { .init(id: String($0), title: "Task \($0)", course: nil, deadline: nil) })
    }

    func testPendingQueueCoalescesThousandsOfEventsWithExactCountAndBoundedPreview() {
        var queue = NewAssignmentPendingQueue()
        for _ in 0..<1000 { queue.append(batch(100), claimedID: nil, isCurrent: { _ in true }) }
        XCTAssertEqual(queue.batches.count, 1)
        XCTAssertEqual(queue.batches[0].totalCount, 100_000)
        XCTAssertEqual(queue.batches[0].items.count, 8)
    }

    func testClaimedBatchIsImmutableAndLaterEventsStayInNextBatch() {
        var queue = NewAssignmentPendingQueue()
        let claimed = batch(15)
        queue.append(claimed, claimedID: nil, isCurrent: { _ in true })
        queue.append(batch(20), claimedID: claimed.id, isCurrent: { _ in true })
        queue.append(batch(30), claimedID: claimed.id, isCurrent: { _ in true })
        queue.append(batch(5, kind: .qmplus), claimedID: claimed.id, isCurrent: { _ in true })
        XCTAssertEqual(queue.batches.count, 3)
        XCTAssertEqual(queue.batches[0].id, claimed.id)
        XCTAssertEqual(queue.batches[0].totalCount, 15)
        XCTAssertEqual(queue.batches[1].totalCount, 50)
        XCTAssertTrue(queue.batches.allSatisfy { $0.items.count <= 8 })
        queue.remove { $0.id == claimed.id }
        queue.remove { $0.id == claimed.id } // a late second acknowledgement cannot consume the next batch
        XCTAssertEqual(queue.batches.map(\.totalCount), [50, 5])
    }

    func testReleaseCoalescesPreviouslyClaimedBatchWithoutLosingCounts() {
        var queue = NewAssignmentPendingQueue()
        let claimed = batch(15)
        queue.append(claimed, claimedID: nil, isCurrent: { _ in true })
        queue.append(batch(20), claimedID: claimed.id, isCurrent: { _ in true })
        queue.coalesce(claimedID: nil)
        XCTAssertEqual(queue.batches.count, 1)
        XCTAssertEqual(queue.batches[0].totalCount, 35)
        XCTAssertEqual(queue.batches[0].items.count, 8)
    }

    func testNewOwnerPrunesExpiredBatchAndLeaseBeforePresentation() {
        var queue = NewAssignmentPendingQueue()
        var claims = NewAssignmentPresentationClaims()
        let old = batch(15), owner = UUID()
        queue.append(old, claimedID: nil, isCurrent: { _ in true })
        XCTAssertTrue(claims.claim(owner: owner, batchID: old.id))
        let replacement = batch(20, scope: .init(owner: "new-owner", epoch: "new-epoch"))
        queue.append(replacement, claimedID: old.id, isCurrent: { $0.id != old.id })
        XCTAssertTrue(claims.invalidateMissing(validBatchIDs: Set(queue.batches.map(\.id))))
        XCTAssertEqual(queue.batches.count, 1)
        XCTAssertEqual(queue.batches[0].id, replacement.id)
        XCTAssertNil(claims.lease)
    }

    func testNoticeRouteOpensItsExistingSourceSection() {
        XCTAssertEqual(NewAssignmentNotice.destination(for: .qmplus), .currentCourses)
        XCTAssertEqual(NewAssignmentNotice.destination(for: .assignments), .assignments)
    }

    func testOnlyOneWindowCanClaimABatchAndReclaimIsIdempotent() {
        var claims = NewAssignmentPresentationClaims()
        let first = UUID(), second = UUID(), batch = UUID()
        XCTAssertTrue(claims.claim(owner: first, batchID: batch))
        XCTAssertTrue(claims.claim(owner: first, batchID: batch))
        XCTAssertFalse(claims.claim(owner: second, batchID: batch))
        XCTAssertTrue(claims.owns(owner: first, batchID: batch))
    }

    func testSceneExitReleasesForAnotherWindowWithoutConsumingTheBatch() {
        var claims = NewAssignmentPresentationClaims()
        let first = UUID(), second = UUID(), batch = UUID()
        XCTAssertTrue(claims.claim(owner: first, batchID: batch))
        XCTAssertTrue(claims.release(owner: first))
        XCTAssertTrue(claims.claim(owner: second, batchID: batch))
        XCTAssertFalse(claims.release(owner: first))
        XCTAssertTrue(claims.owns(owner: second, batchID: batch))
    }

    func testLateDismissalCannotReleaseFollowingBatch() {
        var claims = NewAssignmentPresentationClaims()
        let owner = UUID(), first = UUID(), next = UUID()
        XCTAssertTrue(claims.claim(owner: owner, batchID: first))
        XCTAssertTrue(claims.release(owner: owner, batchID: first))
        XCTAssertTrue(claims.claim(owner: owner, batchID: next))
        XCTAssertFalse(claims.release(owner: owner, batchID: first))
        XCTAssertFalse(claims.owns(owner: owner, batchID: first))
        XCTAssertTrue(claims.owns(owner: owner, batchID: next))
    }

    func testInvalidScopeDropsTheLeaseAndAllowsNextBatch() {
        var claims = NewAssignmentPresentationClaims()
        let first = UUID(), second = UUID(), expired = UUID(), next = UUID()
        XCTAssertTrue(claims.claim(owner: first, batchID: expired))
        XCTAssertTrue(claims.invalidateMissing(validBatchIDs: [next]))
        XCTAssertTrue(claims.claim(owner: second, batchID: next))
        XCTAssertFalse(claims.invalidateMissing(validBatchIDs: [next]))
    }

    func testLargeBatchPreviewIsBoundedAndPreservesOrder() {
        let items = (0..<5000).map { NewAssignmentNotice(id: String($0), title: "Task \($0)", course: nil, deadline: nil) }
        XCTAssertEqual(NewAssignmentNotice.preview(items).map(\.id), (0..<8).map(String.init))
    }

    func testFirstFetchAndRestoreSeedWithoutAlerting() {
        var ledger = NewAssignmentNoticeHistory(scope: scope, terms: [:])
        XCTAssertTrue(ledger.accept(ids: ["a"], term: "2026-1", restored: false).isEmpty)
        XCTAssertTrue(ledger.accept(ids: ["a", "b"], term: "2026-1", restored: true).isEmpty)
        XCTAssertEqual(ledger.accept(ids: ["a", "b", "c", "c"], term: "2026-1", restored: false), ["c"])
    }

    func testDeletedIDsAndDuplicatePublicationDoNotRepeat() {
        var ledger = NewAssignmentNoticeHistory(scope: scope, terms: [:])
        _ = ledger.accept(ids: ["a"], term: "2026-1", restored: false)
        _ = ledger.accept(ids: [], term: "2026-1", restored: false)
        XCTAssertTrue(ledger.accept(ids: ["a"], term: "2026-1", restored: false).isEmpty)
        XCTAssertEqual(ledger.accept(ids: ["a", "b"], term: "2026-1", restored: false), ["b"])
        XCTAssertTrue(ledger.accept(ids: ["a", "b"], term: "2026-1", restored: false).isEmpty)
    }

    func testNewTermAndSaturatedHistoryStayQuiet() {
        var ledger = NewAssignmentNoticeHistory(scope: scope, terms: ["old": Set((0..<5000).map(String.init))])
        XCTAssertTrue(ledger.accept(ids: ["new"], term: "old", restored: false).isEmpty)
        XCTAssertTrue(ledger.accept(ids: ["new"], term: "2026-1", restored: false).isEmpty)
        XCTAssertEqual(ledger.terms["old"]?.count, 5000)
    }

    func testPersistenceRestartAndEpochRotationFenceOldIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wts-notices-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = CourseBusinessCacheStorage(directory: directory, enabled: true)
        let scope = try storage.scope(kind: .assignments, owner: "ucloud")
        let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
        XCTAssertTrue(try storage.recordAssignmentNoticeIDs([a], scope: scope, kind: .assignments, term: "term", restored: false).isEmpty)
        let reopened = CourseBusinessCacheStorage(directory: directory, enabled: true)
        XCTAssertEqual(try reopened.recordAssignmentNoticeIDs([a, b], scope: scope, kind: .assignments, term: "term", restored: false), [b])
        XCTAssertTrue(try storage.recordAssignmentNoticeIDs([a, b], scope: scope, kind: .assignments, term: "term", restored: false).isEmpty)
        _ = try storage.rotateUCloudEpoch()
        XCTAssertThrowsError(try reopened.recordAssignmentNoticeIDs([a], scope: scope, kind: .assignments, term: "term", restored: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("new-assignments-ucloud.json").path))
    }
}
