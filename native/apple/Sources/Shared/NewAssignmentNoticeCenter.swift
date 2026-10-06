import Foundation
import SwiftUI
import CryptoKit

struct NewAssignmentNotice: Identifiable, Sendable {
    let id: String
    let title: String
    let course: String?
    let deadline: String?
}

struct NewAssignmentNoticeHistory: Codable {
    let scope: CourseBusinessCacheScope
    var terms: [String: Set<String>]

    mutating func accept(ids: [String], term: String, restored: Bool) -> Set<String> {
        let old = terms[term]
        guard old != nil || terms.count < 8 else { return [] }
        var seen = old ?? []
        let additions = old != nil && !restored && seen.count < 5000 ? Set(ids).subtracting(seen) : []
        for id in ids where seen.count < 5000 { seen.insert(id) }
        terms[term] = seen
        return additions
    }
}

struct NewAssignmentPresentationClaims {
    struct Lease: Equatable { let owner: UUID; let batchID: UUID }
    private(set) var lease: Lease?
    mutating func claim(owner: UUID, batchID: UUID) -> Bool {
        let requested = Lease(owner: owner, batchID: batchID)
        guard lease == nil || lease == requested else { return false }
        lease = requested
        return true
    }
    func owns(owner: UUID, batchID: UUID) -> Bool { lease == Lease(owner: owner, batchID: batchID) }
    @discardableResult mutating func release(owner: UUID, batchID: UUID? = nil) -> Bool {
        guard lease?.owner == owner, batchID == nil || lease?.batchID == batchID else { return false }
        lease = nil
        return true
    }
    @discardableResult mutating func invalidateMissing(validBatchIDs: Set<UUID>) -> Bool {
        guard let lease, !validBatchIDs.contains(lease.batchID) else { return false }
        self.lease = nil
        return true
    }
}

struct NewAssignmentNoticeBatch: Identifiable {
    let id: UUID
    let scope: CourseBusinessCacheScope
    let kind: CourseBusinessCacheKind
    let storage: CourseBusinessCacheStorage
    let items: [NewAssignmentNotice]
    let totalCount: Int

    init(id: UUID = UUID(), scope: CourseBusinessCacheScope, kind: CourseBusinessCacheKind,
         storage: CourseBusinessCacheStorage, items: [NewAssignmentNotice], totalCount: Int? = nil) {
        self.id = id; self.scope = scope; self.kind = kind; self.storage = storage
        self.items = Array(items.prefix(8)); self.totalCount = totalCount ?? items.count
    }
}

struct NewAssignmentPendingQueue {
    private(set) var batches: [NewAssignmentNoticeBatch] = []

    mutating func append(_ incoming: NewAssignmentNoticeBatch, claimedID: UUID?,
                         isCurrent: (NewAssignmentNoticeBatch) -> Bool) {
        batches.removeAll { !isCurrent($0) || ($0.kind == incoming.kind && $0.scope != incoming.scope) }
        guard incoming.totalCount > 0 else { return }
        if let index = batches.firstIndex(where: { $0.id != claimedID && $0.kind == incoming.kind && $0.scope == incoming.scope }) {
            let previous = batches[index]
            batches[index] = .init(id: previous.id, scope: previous.scope, kind: previous.kind, storage: previous.storage,
                items: previous.items + incoming.items, totalCount: previous.totalCount + incoming.totalCount)
        } else {
            batches.append(incoming)
        }
        coalesce(claimedID: claimedID)
    }

    mutating func coalesce(claimedID: UUID?) {
        var merged: [NewAssignmentNoticeBatch] = []
        for batch in batches {
            if batch.id != claimedID,
               let index = merged.firstIndex(where: { $0.id != claimedID && $0.scope == batch.scope && $0.kind == batch.kind }) {
                let previous = merged[index]
                merged[index] = .init(id: previous.id, scope: previous.scope, kind: previous.kind, storage: previous.storage,
                    items: previous.items + batch.items, totalCount: previous.totalCount + batch.totalCount)
            } else {
                merged.append(batch)
            }
        }
        batches = merged
    }

    mutating func remove(where predicate: (NewAssignmentNoticeBatch) -> Bool) { batches.removeAll(where: predicate) }
}

@MainActor final class NewAssignmentNoticeCenter: ObservableObject {
    static let shared = NewAssignmentNoticeCenter()
    typealias Batch = NewAssignmentNoticeBatch
    private var pending = NewAssignmentPendingQueue()
    private func enqueue(_ batch: Batch) {
        pending.append(batch, claimedID: claims.lease?.batchID) { $0.storage.isCurrent($0.scope, kind: $0.kind) }
        if claims.invalidateMissing(validBatchIDs: Set(pending.batches.map(\.id))) { presentationRevision &+= 1 }
        batches = pending.batches
    }
    @Published private(set) var batches: [Batch] = []
    @Published private(set) var presentationRevision: UInt64 = 0
    private var claims = NewAssignmentPresentationClaims()

    nonisolated static func publish(_ items: [NewAssignmentNotice], scope: CourseBusinessCacheScope,
                                    kind: CourseBusinessCacheKind, storage: CourseBusinessCacheStorage, restored: Bool) {
        let hashed = items.map { SHA256.hash(data: Data($0.id.utf8)).map { String(format: "%02x", $0) }.joined() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let year = calendar.component(.year, from: .now), month = calendar.component(.month, from: .now)
        let term = month >= 8 ? "\(year)-1" : month >= 2 ? "\(year - 1)-2" : "\(year - 1)-1"
        guard let newIDs = try? storage.recordAssignmentNoticeIDs(hashed, scope: scope, kind: kind, term: term, restored: restored),
              !newIDs.isEmpty else { return }
        var emitted = Set<String>()
        let additions = zip(items, hashed).compactMap { item, hash -> NewAssignmentNotice? in
            guard newIDs.contains(hash), emitted.insert(hash).inserted else { return nil }
            return item
        }
        Task { @MainActor in
            guard storage.isCurrent(scope, kind: kind) else { return }
            shared.enqueue(Batch(scope: scope, kind: kind, storage: storage, items: additions))
        }
    }

    func claim(owner: UUID) -> Batch? {
        let valid = batches.filter { $0.storage.isCurrent($0.scope, kind: $0.kind) }
        if claims.invalidateMissing(validBatchIDs: Set(valid.map(\.id))) { presentationRevision &+= 1 }
        if valid.count != batches.count {
            pending.remove { !$0.storage.isCurrent($0.scope, kind: $0.kind) }
            batches = pending.batches
        }
        guard let next = valid.first else { return nil }
        let previous = claims.lease
        guard claims.claim(owner: owner, batchID: next.id) else { return nil }
        if previous != claims.lease { presentationRevision &+= 1 }
        return next
    }

    func isClaimCurrent(owner: UUID, batchID: UUID) -> Bool {
        claims.owns(owner: owner, batchID: batchID) && batches.contains {
            $0.id == batchID && $0.storage.isCurrent($0.scope, kind: $0.kind)
        }
    }

    func release(owner: UUID, batchID: UUID? = nil) {
        if claims.release(owner: owner, batchID: batchID) {
            pending.coalesce(claimedID: nil)
            batches = pending.batches
            presentationRevision &+= 1
        }
    }

    func acknowledge(owner: UUID, batchID: UUID?) {
        guard let batchID, claims.owns(owner: owner, batchID: batchID) else { return }
        claims.release(owner: owner, batchID: batchID)
        pending.remove { $0.id == batchID || !$0.storage.isCurrent($0.scope, kind: $0.kind) }
        pending.coalesce(claimedID: nil)
        batches = pending.batches
        presentationRevision &+= 1
    }
}

extension NewAssignmentNotice {
    static func destination(for kind: CourseBusinessCacheKind) -> CourseQueryMode {
        kind == .qmplus ? .currentCourses : .assignments
    }
    static func preview(_ items: [Self]) -> [Self] { Array(items.prefix(8)) }
    static func cloud(_ items: [AssignmentDeadlineItem]) -> [Self] {
        items.map { .init(id: "\($0.courseID ?? ""):\($0.id)", title: $0.title, course: $0.courseName, deadline: $0.deadline) }
    }
    static func qmplus(_ snapshot: QMplusSnapshot) -> [Self] {
        let selection = QMplusCourseSelection(snapshot: snapshot, showsOtherTerms: false)
        return selection.activities.map { item in
            .init(id: "\(item.courseID):\(item.kind.rawValue):\(item.id)", title: item.title,
                  course: selection.courses.first { $0.id == item.courseID }?.name,
                  deadline: item.dueAt ?? item.closesAt ?? item.cutoffAt)
        }
    }
}
