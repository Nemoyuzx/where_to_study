import Foundation
import Security
import Combine

/// Selected from the packaged app, never from preferences or a failed read.
/// The store distribution keeps its existing Data Protection namespace.
enum QMplusCredentialBackend: String, Codable, Sendable {
    case dataProtection = "data-protection"
    case publicMacOS = "public-macos-system-keychain-v1"
    case unsupported = "unsupported-distribution"

    static let distributionKey = "WTSQMplusCredentialDistribution"
    static let publicDistribution = "public-macos-v1"

    static var current: Self {
        #if os(macOS)
        resolve(distributionMarker: Bundle.main.object(forInfoDictionaryKey: distributionKey), isMacOS: true)
        #else
        .dataProtection
        #endif
    }

    static func resolve(distributionMarker: Any?, isMacOS: Bool) -> Self {
        guard isMacOS else { return .dataProtection }
        guard let distributionMarker else { return .dataProtection }
        return distributionMarker as? String == publicDistribution ? .publicMacOS : .unsupported
    }

    var isSupported: Bool { self != .unsupported }
    func preferenceKey(_ original: String) -> String {
        self == .dataProtection ? original : original + "." + rawValue
    }
    var profileIdentifierKey: String { preferenceKey("qmplusWebsiteDataStoreIdentifier") }
    var cacheDirectoryName: String {
        self == .dataProtection ? "course-business-cache-v1" : "qmplus-business-cache-" + rawValue
    }
    func businessOwner(profileIdentifier: String?) -> String {
        // The independent directory and profile preference key isolate public
        // caches. Keep owners within the shared validator's UUID/legacy format.
        profileIdentifier.flatMap(UUID.init(uuidString:))?.uuidString ?? "legacy"
    }
    func makeCredentialStore() -> any QMplusCredentialStoring {
        guard isSupported else { return QMplusUnavailableCredentialStore() }
        return QMplusKeychainCredentialStore(backend: self)
    }
    func makeBusinessCache() -> CourseBusinessCacheStorage {
        if self == .dataProtection { return .shared }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WhereToStudyNative", isDirectory: true)
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
        return CourseBusinessCacheStorage(directory: directory,
            enabled: isSupported && !AppLaunchConfiguration.isXCTestRunning && !AppLaunchConfiguration.isUITesting && !AppLaunchConfiguration.isReviewDemo)
    }
}

private struct QMplusUnavailableCredentialStore: QMplusCredentialStoring {
    func authorizationMarker() throws -> QMplusCredentialAuthorizationMarker? { throw QMplusCredentialStorageError.unsupportedDistribution }
    func load() throws -> QMplusSavedCredentials? { throw QMplusCredentialStorageError.unsupportedDistribution }
    func save(_ credentials: QMplusSavedCredentials) throws { throw QMplusCredentialStorageError.unsupportedDistribution }
    func clear() throws { throw QMplusCredentialStorageError.unsupportedDistribution }
}

struct QMplusCredentialAuthorizationMarker: Codable, Equatable, Sendable {
    let recordID: UUID
    let authorizationNonce: UUID
}

// Never used as business data, an account identity, a widget value or a log.
struct QMplusSavedCredentials: Codable, Equatable, Sendable {
    let marker: QMplusCredentialAuthorizationMarker
    let account: String
    let password: String

    var isValid: Bool {
        !account.isEmpty && account.utf8.count <= 512 && !account.contains("\n") && !account.contains("\r")
            && !password.isEmpty && password.utf8.count <= 4096 && password.utf16.count <= 2048
    }
}

protocol QMplusCredentialStoring: Sendable {
    func authorizationMarker() throws -> QMplusCredentialAuthorizationMarker?
    func load() throws -> QMplusSavedCredentials?
    func save(_ credentials: QMplusSavedCredentials) throws
    func clear() throws
}

protocol QMplusCredentialAuthorizationJournaling: Sendable {
    func load() throws -> QMplusCredentialAuthorizationMarker?
    func authorize(_ marker: QMplusCredentialAuthorizationMarker) throws
    func revoke() throws
}

enum QMplusCredentialStorageError: Error { case invalidRecord, verificationFailed, unsupportedDistribution, keychain(OSStatus) }

enum QMplusCredentialSaveDisposition: Equatable, Sendable { case unchanged, replaced, failed }

// Synchronous boundary permits deterministic tests without real Keychain access.
protocol QMplusKeychainAccessing: Sendable {
    func copyMatching(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

private struct QMplusSystemKeychainAccess: QMplusKeychainAccessing {
    func copyMatching(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus { SecItemCopyMatching(query, &result) }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { SecItemUpdate(query, attributes) }
    func add(_ attributes: CFDictionary) -> OSStatus { SecItemAdd(attributes, nil) }
    func delete(_ query: CFDictionary) -> OSStatus { SecItemDelete(query) }
}

struct QMplusKeychainCredentialStore: QMplusCredentialStoring {
    static let service = "com.nemoyu.wheretostudy.native.qmplus.microsoft-credentials"
    static let account = "qmplus-microsoft"
    let backend: QMplusCredentialBackend
    private let access: any QMplusKeychainAccessing

    init(backend: QMplusCredentialBackend = .dataProtection, access: (any QMplusKeychainAccessing)? = nil) {
        #if os(macOS)
        self.backend = backend
        #else
        self.backend = .dataProtection
        #endif
        self.access = access ?? QMplusSystemKeychainAccess()
    }

    var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: backend == .dataProtection ? Self.service : Self.service + "." + backend.rawValue,
         kSecAttrAccount as String: Self.account,
         kSecUseDataProtectionKeychain as String: backend == .dataProtection,
         kSecAttrSynchronizable as String: false]
    }

    private func requireSupportedBackend() throws {
        guard backend.isSupported else { throw QMplusCredentialStorageError.unsupportedDistribution }
    }

    func authorizationMarker() throws -> QMplusCredentialAuthorizationMarker? {
        try requireSupportedBackend()
        var request = query
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = access.copyMatching(request as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw QMplusCredentialStorageError.keychain(status) }
        guard let attributes = result as? [String: Any], let data = attributes[kSecAttrGeneric as String] as? Data,
              data.count <= 1024 else { throw QMplusCredentialStorageError.invalidRecord }
        return try JSONDecoder().decode(QMplusCredentialAuthorizationMarker.self, from: data)
    }

    func load() throws -> QMplusSavedCredentials? {
        try requireSupportedBackend()
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = access.copyMatching(request as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw QMplusCredentialStorageError.keychain(status) }
        guard let data = result as? Data, data.count <= 16_384 else { throw QMplusCredentialStorageError.invalidRecord }
        let record = try JSONDecoder().decode(QMplusSavedCredentials.self, from: data)
        guard record.isValid else { throw QMplusCredentialStorageError.invalidRecord }
        return record
    }

    func save(_ credentials: QMplusSavedCredentials) throws {
        try requireSupportedBackend()
        guard credentials.isValid else { throw QMplusCredentialStorageError.invalidRecord }
        let data = try JSONEncoder().encode(credentials)
        guard data.count <= 16_384 else { throw QMplusCredentialStorageError.invalidRecord }
        var updates: [String: Any] = [kSecValueData as String: data,
            kSecAttrGeneric as String: try JSONEncoder().encode(credentials.marker)]
        if backend == .dataProtection {
            updates[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        // File-based macOS Keychain keeps the system's normal item ACL. Do not
        // create an unrestricted SecAccess or modify trusted applications.
        let status = access.update(query as CFDictionary, attributes: updates as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw QMplusCredentialStorageError.keychain(status) }
        let attributes = query.merging(updates) { _, value in value }
        let added = access.add(attributes as CFDictionary)
        guard added == errSecSuccess else { throw QMplusCredentialStorageError.keychain(added) }
    }

    func clear() throws {
        try requireSupportedBackend()
        let status = access.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QMplusCredentialStorageError.keychain(status) }
    }
}

// Only two random IDs live in preferences, never an account or password.
struct QMplusDefaultsAuthorizationJournal: QMplusCredentialAuthorizationJournaling, @unchecked Sendable {
    static let key = "qmplusCredentialAutofillAuthorization"
    let defaults: UserDefaults
    var backend: QMplusCredentialBackend = .dataProtection
    private struct TaggedMarker: Codable {
        let backend: QMplusCredentialBackend
        let marker: QMplusCredentialAuthorizationMarker
    }
    private var key: String { backend.preferenceKey(Self.key) }
    func load() throws -> QMplusCredentialAuthorizationMarker? {
        guard backend.isSupported else { throw QMplusCredentialStorageError.unsupportedDistribution }
        guard let data = defaults.data(forKey: key) else { return nil }
        guard data.count <= 1024 else { throw QMplusCredentialStorageError.invalidRecord }
        if backend == .dataProtection { return try JSONDecoder().decode(QMplusCredentialAuthorizationMarker.self, from: data) }
        let record = try JSONDecoder().decode(TaggedMarker.self, from: data)
        guard record.backend == backend else { throw QMplusCredentialStorageError.verificationFailed }
        return record.marker
    }
    func authorize(_ marker: QMplusCredentialAuthorizationMarker) throws {
        guard backend.isSupported else { throw QMplusCredentialStorageError.unsupportedDistribution }
        let data = try backend == .dataProtection ? JSONEncoder().encode(marker)
            : JSONEncoder().encode(TaggedMarker(backend: backend, marker: marker))
        defaults.set(data, forKey: key)
        guard try load() == marker else { throw QMplusCredentialStorageError.verificationFailed }
    }
    func revoke() throws {
        guard backend.isSupported else { throw QMplusCredentialStorageError.unsupportedDistribution }
        defaults.removeObject(forKey: key)
        guard defaults.object(forKey: key) == nil else { throw QMplusCredentialStorageError.verificationFailed }
    }
}

@MainActor
final class QMplusCredentialAuthorization: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isTemporarilyUnavailable = false
    @Published private(set) var statusKey = ""
    private(set) var credentialRevision: UInt64 = 0
    private(set) var removalNeedsAttention = false
    private let storage: any QMplusCredentialStoring
    private let journal: any QMplusCredentialAuthorizationJournaling
    private let allowsStorage: Bool
    private var hasLoaded = false
    private var restorationBlocked = false
    private var authorizedMarker: QMplusCredentialAuthorizationMarker?
    var allowsCredentialStorage: Bool { allowsStorage }

    init(storage: any QMplusCredentialStoring, journal: any QMplusCredentialAuthorizationJournaling, allowsStorage: Bool = true) {
        self.storage = storage; self.journal = journal; self.allowsStorage = allowsStorage
    }

    func loadIfNeeded() { if !hasLoaded { restoreAuthorization() } }

    func restoreAuthorization() {
        guard allowsStorage, !restorationBlocked else { return }
        hasLoaded = true
        let previouslyEnabled = isEnabled
        let previousMarker = authorizedMarker
        isEnabled = false
        isTemporarilyUnavailable = false
        authorizedMarker = nil
        statusKey = ""
        do {
            // A preference alone cannot revive an orphaned Keychain record.
            // Reading attributes here does not bring the password into memory.
            if let marker = try journal.load() {
                if try storage.authorizationMarker() == marker {
                    isEnabled = true
                    authorizedMarker = marker
                    statusKey = "已保存 QMplus 登录信息并授权官方网页自动填写"
                } else { statusKey = "无法确认 QMplus 登录信息的保存状态，请重新保存或删除。" }
            }
        } catch { recordReadFailure(error) }
        if previouslyEnabled != isEnabled || previousMarker != authorizedMarker { credentialRevision &+= 1 }
    }

    // The guarded official pipeline and explicit unchanged-save comparison use
    // this boundary. Every read revalidates the specific opt-in record.
    func loadAuthorizedCredentials(expectedRevision: UInt64) -> QMplusSavedCredentials? {
        guard allowsStorage, isEnabled, credentialRevision == expectedRevision, let authorizedMarker else { return nil }
        do {
            guard try journal.load() == authorizedMarker, try storage.authorizationMarker() == authorizedMarker,
                  let saved = try storage.load(), saved.marker == authorizedMarker, saved.isValid else {
                throw QMplusCredentialStorageError.verificationFailed
            }
            return saved
        } catch {
            stopInMemory()
            recordReadFailure(error)
            return nil
        }
    }

    @discardableResult
    func saveAndAuthorize(account: String, password: String) -> Bool {
        saveAndAuthorizeWithDisposition(account: account, password: password) != .failed
    }

    @discardableResult
    func saveAndAuthorizeWithDisposition(account: String, password: String) -> QMplusCredentialSaveDisposition {
        guard allowsStorage else { return .failed }
        let record = QMplusSavedCredentials(marker: .init(recordID: UUID(), authorizationNonce: UUID()),
            account: account.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        guard record.isValid else { statusKey = "请填写有效的 QMplus 账号和密码。"; return .failed }
        let revision = credentialRevision
        if let saved = loadAuthorizedCredentials(expectedRevision: revision),
           saved.account == record.account, saved.password == record.password {
            do {
                // Recheck the nonsecret binding after the secure read. Ordinary
                // preferences or a saved account name never authorize this path.
                guard isEnabled, credentialRevision == revision, authorizedMarker == saved.marker,
                      try journal.load() == saved.marker, try storage.authorizationMarker() == saved.marker else {
                    throw QMplusCredentialStorageError.verificationFailed
                }
                removalNeedsAttention = false
                statusKey = "已保存 QMplus 登录信息并授权官方网页自动填写"
                return .unchanged
            } catch {
                // An unverifiable record goes through the original fresh-marker
                // replacement protocol, never through the preserved-session path.
            }
        }
        stopInMemory()
        // Withdraw old authority before replacing a secret. A fresh random
        // record/nonce pair cannot match an older journal after a crash.
        do {
            try journal.revoke()
            try storage.save(record)
            guard try storage.load() == record, try storage.authorizationMarker() == record.marker else {
                throw QMplusCredentialStorageError.verificationFailed
            }
            try journal.authorize(record.marker)
            guard try journal.load() == record.marker else { throw QMplusCredentialStorageError.verificationFailed }
            isEnabled = true
            authorizedMarker = record.marker
            restorationBlocked = false
            removalNeedsAttention = false
            statusKey = "已保存 QMplus 登录信息并授权官方网页自动填写"
            return .replaced
        } catch {
            let removed = withdrawAndDelete()
            if removed { statusKey = "无法保存 QMplus 登录信息，自动填写未启用。" }
            return .failed
        }
    }

    @discardableResult
    func disableAndDelete() -> Bool {
        restorationBlocked = true
        stopInMemory()
        guard allowsStorage else { removalNeedsAttention = false; return true }
        return withdrawAndDelete()
    }

    func suspendInMemory() {
        stopInMemory()
        hasLoaded = false
        statusKey = ""
    }

    private func stopInMemory() {
        credentialRevision &+= 1
        isEnabled = false
        isTemporarilyUnavailable = false
        authorizedMarker = nil
        hasLoaded = true
    }

    private func recordReadFailure(_ error: Error) {
        if case let QMplusCredentialStorageError.keychain(status) = error,
           status == errSecInteractionNotAllowed || status == errSecNotAvailable {
            // Readability is not authority. The next foreground preflight must
            // revalidate both markers before credentials can be returned again.
            isTemporarilyUnavailable = true
            hasLoaded = false
            statusKey = "正在确认 QMplus 登录状态…"
        } else {
            isTemporarilyUnavailable = false
            hasLoaded = true
            statusKey = "无法确认 QMplus 登录信息的保存状态，请重新保存或删除。"
        }
    }

    private func withdrawAndDelete() -> Bool {
        // A pending availability retry must never undo an explicit removal,
        // even if both durable stores currently reject their delete requests.
        restorationBlocked = true
        var journalRemoved = false, secretRemoved = false
        do { try journal.revoke(); journalRemoved = true } catch { }
        do { try storage.clear(); secretRemoved = true } catch { }
        removalNeedsAttention = !journalRemoved || !secretRemoved
        if journalRemoved && secretRemoved {
            statusKey = "已关闭 QMplus 自动填写并删除保存的登录信息"
        } else if !journalRemoved && !secretRemoved {
            statusKey = "QMplus 自动填写已在本次使用中停用；下次启动请核对保存状态。"
        } else if !secretRemoved {
            statusKey = "QMplus 自动填写已关闭，但保存的登录信息删除失败，请重试。"
        } else {
            statusKey = "QMplus 登录信息已删除，但授权记录清理失败，请重试。"
        }
        return !removalNeedsAttention
    }
}

@MainActor
final class QMplusCredentialDraft: ObservableObject {
    static let preferenceKey = "qmplusCredentialSavePreference"
    private let defaults: UserDefaults?
    private let preferenceKey: String
    private var persistsPreference = true
    @Published var account = ""
    @Published var password = ""
    // A selected editing preference is not an authorization or saved record.
    // Only the explicit save action can establish the secure-store binding.
    @Published var wantsToSave: Bool {
        didSet { if persistsPreference { defaults?.set(wantsToSave, forKey: preferenceKey) } }
    }

    init(defaults: UserDefaults? = .standard, backend: QMplusCredentialBackend = .dataProtection) {
        self.defaults = defaults
        preferenceKey = backend.preferenceKey(Self.preferenceKey)
        wantsToSave = defaults?.object(forKey: preferenceKey) as? Bool ?? true
    }

    func clear() { account = ""; password = "" }
    func disableSaving() { wantsToSave = false; clear() }
    func resetSavingPreference() {
        clear()
        defaults?.removeObject(forKey: preferenceKey)
        persistsPreference = false
        wantsToSave = true
        persistsPreference = true
    }
}
