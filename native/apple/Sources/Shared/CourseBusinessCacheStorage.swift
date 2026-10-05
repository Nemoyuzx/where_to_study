import Foundation
import Darwin

enum CourseBusinessCacheKind: String, Sendable {
    case courses, assignments, qmplus
    var domain: String { self == .qmplus ? "qmplus" : "ucloud" }
    var fileName: String { rawValue + ".json" }
}

struct CourseBusinessCacheScope: Codable, Hashable, Sendable {
    let owner: String
    let epoch: String
}

struct CourseBusinessCachedValue<Payload: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let scope: CourseBusinessCacheScope
    let fetchedAt: String
    let partial: Bool
    let payload: Payload
}

/// Only typed business DTOs enter this store. The durable guards contain only
/// schema + random epoch: no account, password, password hash or web secret.
/// Rotating a guard precedes credential mutation and fences even an old writer.
final class CourseBusinessCacheStorage: @unchecked Sendable {
    static let shared = CourseBusinessCacheStorage()
    private struct Guard: Codable { let schemaVersion: Int; let epoch: String; let pending: Bool }
    private let lock = NSLock()
    private let directory: URL?
    private let enabled: Bool
    private var ephemeralEpochs = [String: String]()
    private var blockedDomains = Set<String>()

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WhereToStudyNative", isDirectory: true)
            .appendingPathComponent("course-business-cache-v1", isDirectory: true),
         enabled: Bool = !AppLaunchConfiguration.isXCTestRunning && !AppLaunchConfiguration.isUITesting && !AppLaunchConfiguration.isReviewDemo) {
        self.directory = directory
        self.enabled = enabled
    }

    func scope(kind: CourseBusinessCacheKind, owner: String) throws -> CourseBusinessCacheScope {
        try lock.withLock { .init(owner: owner, epoch: try epochLocked(domain: kind.domain)) }
    }

    func isCurrent(_ scope: CourseBusinessCacheScope, kind: CourseBusinessCacheKind) -> Bool {
        lock.withLock { (try? epochLocked(domain: kind.domain)) == scope.epoch }
    }

    @discardableResult
    func rotateUCloudEpoch() throws -> String { try rotate(domain: "ucloud") }

    @discardableResult
    func rotateQMplusEpoch() throws -> String { try rotate(domain: "qmplus") }

    // Keep epoch publication and the secure-record mutation indivisible to
    // in-process readers. Otherwise a same-account password change could pair
    // the new epoch with the still-old Keychain record in a concurrent worker.
    func mutateUCloudCredentials(_ mutation: () throws -> Void) throws {
        try lock.withLock {
            _ = try rotateLocked(domain: "ucloud", afterPurge: mutation)
        }
    }

    func ucloudCredentialBinding(store: any CredentialStoring) throws -> (Credentials, CourseBusinessCacheScope) {
        try lock.withLock {
            guard let credentials = try store.load(),
                  !credentials.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !credentials.effectiveTeachingCloudPassword.isEmpty else {
                throw CalendarDeadlineError.service("请先在设置中保存教务账号和密码。")
            }
            let scope = CourseBusinessCacheScope(owner: "ucloud",
                                                epoch: try epochLocked(domain: "ucloud"))
            return (credentials, scope)
        }
    }

    private func rotate(domain: String) throws -> String {
        try lock.withLock { try rotateLocked(domain: domain) }
    }

    private func rotateLocked(domain: String, afterPurge: () throws -> Void = {}) throws -> String {
        let epoch = UUID().uuidString
        if !enabled { ephemeralEpochs[domain] = epoch; try afterPurge(); return epoch }
        blockedDomains.insert(domain)
        let root = try prepareDirectoryLocked()
        let url = root.appendingPathComponent(domain + "-guard.json")
        let pending = try JSONEncoder().encode(Guard(schemaVersion: 1, epoch: epoch, pending: true))
        do {
            try durableWrite(pending, to: url)
            for kind in [CourseBusinessCacheKind.courses, .assignments, .qmplus] where kind.domain == domain {
                do { try FileManager.default.removeItem(at: root.appendingPathComponent(kind.fileName)) }
                catch let error as CocoaError where error.code == .fileNoSuchFile { continue }
            }
            try synchronizeDirectory(root)
            try afterPurge()
            try durableWrite(try JSONEncoder().encode(Guard(schemaVersion: 1, epoch: epoch, pending: false)), to: url)
            blockedDomains.remove(domain)
            return epoch
        } catch {
            // Even a post-mutation commit failure must leave durable quarantine.
            // In-memory blocking covers an I/O failure that prevents this retry.
            try? durableWrite(pending, to: url)
            throw error
        }
    }

    func load<Payload: Codable & Sendable>(kind: CourseBusinessCacheKind, scope: CourseBusinessCacheScope,
                                          maximumBytes: Int, as: Payload.Type) throws -> CourseBusinessCachedValue<Payload>? {
        guard enabled else { return nil }
        let limit = min(maximumBytes, kind == .qmplus ? CourseBusinessCacheValidation.maximumQMplusEnvelopeBytes
                        : CourseBusinessCacheValidation.maximumCloudBytes)
        let data: Data? = try lock.withLock {
            guard try epochLocked(domain: kind.domain) == scope.epoch else { throw CancellationError() }
            let root = try prepareDirectoryLocked()
            let url = root.appendingPathComponent(kind.fileName)
            do { return try boundedData(url, maximumBytes: limit) }
            catch let error as CocoaError where error.code == .fileNoSuchFile { return nil }
        }
        guard let data else { return nil }
        try CourseBusinessCacheValidation.validate(data: data, kind: kind)
        let value = try JSONDecoder().decode(CourseBusinessCachedValue<Payload>.self, from: data)
        guard value.schemaVersion == 1, value.scope == scope,
              QMplusSnapshotPolicy.utcDate(value.fetchedAt) != nil, isCurrent(scope, kind: kind) else { return nil }
        return value
    }

    func save<Payload: Codable & Sendable>(_ value: CourseBusinessCachedValue<Payload>, kind: CourseBusinessCacheKind,
                                          maximumBytes: Int) throws {
        guard enabled else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteUnknown) }
        try CourseBusinessCacheValidation.validate(data: data, kind: kind)
        try lock.withLock {
            guard try epochLocked(domain: kind.domain) == value.scope.epoch else { throw CancellationError() }
            let root = try prepareDirectoryLocked()
            try durableWrite(data, to: root.appendingPathComponent(kind.fileName))
        }
    }

    private func epochLocked(domain: String) throws -> String {
        if !enabled {
            if let epoch = ephemeralEpochs[domain] { return epoch }
            let epoch = UUID().uuidString; ephemeralEpochs[domain] = epoch; return epoch
        }
        guard !blockedDomains.contains(domain) else { throw CocoaError(.fileReadCorruptFile) }
        let root = try prepareDirectoryLocked()
        let url = root.appendingPathComponent(domain + "-guard.json")
        let data: Data
        do { data = try boundedData(url, maximumBytes: 256) }
        catch let error as CocoaError where error.code == .fileNoSuchFile {
            let epoch = UUID().uuidString
            try durableWrite(try JSONEncoder().encode(Guard(schemaVersion: 1, epoch: epoch, pending: false)), to: url)
            return epoch // A fresh guard never accepts any older payload.
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object, Set(object.keys) == ["schemaVersion", "epoch", "pending"] else { throw CocoaError(.fileReadCorruptFile) }
        let value = try JSONDecoder().decode(Guard.self, from: data)
        guard value.schemaVersion == 1, !value.pending, UUID(uuidString: value.epoch)?.uuidString == value.epoch else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value.epoch
    }

    private func prepareDirectoryLocked() throws -> URL {
        guard let directory else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var root = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        return root
    }

    private func boundedData(_ url: URL, maximumBytes: Int) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue >= 0,
              size.intValue <= maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    private func durableWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        try synchronizeDirectory(url.deletingLastPathComponent())
        guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
