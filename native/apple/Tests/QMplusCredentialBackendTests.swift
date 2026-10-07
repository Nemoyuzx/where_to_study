import XCTest
import Security
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

@MainActor
final class QMplusCredentialBackendTests: XCTestCase {
    func testDefaultAndIOSAlwaysUseDataProtection() {
        XCTAssertEqual(QMplusCredentialBackend.resolve(distributionMarker: nil, isMacOS: true), .dataProtection)
        for marker: Any? in [nil, QMplusCredentialBackend.publicDistribution, "unknown", true] {
            XCTAssertEqual(QMplusCredentialBackend.resolve(distributionMarker: marker, isMacOS: false), .dataProtection)
        }
        let store = QMplusKeychainCredentialStore(access: BackendKeychainProbe())
        XCTAssertEqual(store.query[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertEqual(store.query[kSecAttrService as String] as? String, QMplusKeychainCredentialStore.service)
        #if os(iOS)
        XCTAssertEqual(QMplusKeychainCredentialStore(backend: .publicMacOS,
            access: BackendKeychainProbe()).backend, .dataProtection)
        #endif
    }

    func testOnlyExactPublicMacOSMarkerSelectsPublicBackend() {
        XCTAssertEqual(QMplusCredentialBackend.resolve(distributionMarker: QMplusCredentialBackend.publicDistribution,
            isMacOS: true), .publicMacOS)
        for marker: Any in ["", "unknown", "public-macos-v1 ", true, 1, ["public-macos-v1"]] {
            XCTAssertEqual(QMplusCredentialBackend.resolve(distributionMarker: marker, isMacOS: true), .unsupported)
        }
    }

    func testUnknownDistributionCannotReadSaveClearOrConnect() throws {
        let storage = QMplusCredentialBackend.unsupported.makeCredentialStore()
        XCTAssertThrowsError(try storage.authorizationMarker())
        XCTAssertThrowsError(try storage.load())
        XCTAssertThrowsError(try storage.save(fixture()))
        XCTAssertThrowsError(try storage.clear())
        let store = QMplusStore(allowsCredentialStorage: true, businessCache: .init(directory: nil, enabled: false),
            credentialBackend: .unsupported)
        XCTAssertFalse(store.credentialAuthorization.allowsCredentialStorage)
        XCTAssertFalse(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-password"))
        XCTAssertFalse(store.beginConnectionOwner(quiet: true))
        XCTAssertNil(store.beginSynchronization())
        store.connect(sampleMode: false)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView)
    }

    func testPublicIdentityMetadataAndBusinessScopeDoNotReuseStoreNamespace() {
        let dp = QMplusCredentialBackend.dataProtection, publicBackend = QMplusCredentialBackend.publicMacOS
        for key in [QMplusDefaultsAuthorizationJournal.key, QMplusCredentialDraft.preferenceKey,
                    "qmplusWebsiteDataStoreIdentifier", "qmplusEnabled"] {
            XCTAssertEqual(dp.preferenceKey(key), key)
            XCTAssertNotEqual(dp.preferenceKey(key), publicBackend.preferenceKey(key))
        }
        XCTAssertNotEqual(dp.cacheDirectoryName, publicBackend.cacheDirectoryName)
        let profile = UUID().uuidString
        XCTAssertEqual(publicBackend.businessOwner(profileIdentifier: profile), profile)
        XCTAssertEqual(publicBackend.businessOwner(profileIdentifier: nil), "legacy")
    }

    func testPublicJournalRequiresBackendTagAndNeverMigratesLegacyAuthorization() throws {
        let suite = "QMplusBackendJournal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let marker = fixture().marker
        let original = QMplusDefaultsAuthorizationJournal(defaults: defaults)
        let publicJournal = QMplusDefaultsAuthorizationJournal(defaults: defaults, backend: .publicMacOS)
        try original.authorize(marker)
        XCTAssertNil(try publicJournal.load())
        let publicKey = QMplusCredentialBackend.publicMacOS.preferenceKey(QMplusDefaultsAuthorizationJournal.key)
        defaults.set(try JSONEncoder().encode(marker), forKey: publicKey)
        XCTAssertThrowsError(try publicJournal.load(), "A copied untagged legacy marker is not public authorization")
        defaults.set(try JSONSerialization.data(withJSONObject: ["backend": "data-protection",
            "marker": ["recordID": marker.recordID.uuidString, "authorizationNonce": marker.authorizationNonce.uuidString]]),
            forKey: publicKey)
        XCTAssertThrowsError(try publicJournal.load(), "A copied marker tagged for another backend is rejected")
        try publicJournal.authorize(marker)
        XCTAssertEqual(try publicJournal.load(), marker)
        try publicJournal.revoke()
        XCTAssertNil(try publicJournal.load())
        XCTAssertEqual(try original.load(), marker, "Public deletion must retain the Store authorization")
    }

    func testPublicDraftDoesNotReadOrResetStorePreference() throws {
        let suite = "QMplusBackendDraft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: QMplusCredentialDraft.preferenceKey)
        let publicDraft = QMplusCredentialDraft(defaults: defaults, backend: .publicMacOS)
        XCTAssertTrue(publicDraft.wantsToSave)
        publicDraft.disableSaving()
        XCTAssertFalse(QMplusCredentialDraft(defaults: defaults, backend: .publicMacOS).wantsToSave)
        publicDraft.resetSavingPreference()
        XCTAssertFalse(QMplusCredentialDraft(defaults: defaults).wantsToSave)
    }

    func testIndependentPublicCacheRotationLeavesStoreEpochAndFilesIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QMplusBackendCache-" + UUID().uuidString,
            isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let originalDirectory = root.appendingPathComponent(QMplusCredentialBackend.dataProtection.cacheDirectoryName)
        let publicDirectory = root.appendingPathComponent(QMplusCredentialBackend.publicMacOS.cacheDirectoryName)
        let original = CourseBusinessCacheStorage(directory: originalDirectory, enabled: true)
        let publicCache = CourseBusinessCacheStorage(directory: publicDirectory, enabled: true)
        let originalScope = try original.scope(kind: .qmplus, owner: UUID().uuidString)
        let publicScope = try publicCache.scope(kind: .qmplus, owner: UUID().uuidString)
        let originalGuard = originalDirectory.appendingPathComponent("qmplus-guard.json")
        let originalBytes = try Data(contentsOf: originalGuard)
        try publicCache.rotateQMplusEpoch()
        XCTAssertTrue(original.isCurrent(originalScope, kind: .qmplus))
        XCTAssertFalse(publicCache.isCurrent(publicScope, kind: .qmplus))
        XCTAssertEqual(try Data(contentsOf: originalGuard), originalBytes)
    }

    func testPublicBusinessCacheSavesAndReopensCompleteSnapshotWithoutReadingOrClearingStoreCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QMplusBackendRoundTrip-" + UUID().uuidString,
            isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Both persistent named profiles and older-OS legacy owners must pass
        // the real envelope validator, not just match a scope string in memory.
        for profile: String? in [UUID().uuidString, nil] {
            let caseRoot = root.appendingPathComponent(profile ?? "legacy", isDirectory: true)
            let originalDirectory = caseRoot.appendingPathComponent(QMplusCredentialBackend.dataProtection.cacheDirectoryName)
            let publicDirectory = caseRoot.appendingPathComponent(QMplusCredentialBackend.publicMacOS.cacheDirectoryName)
            let original = CourseBusinessCacheStorage(directory: originalDirectory, enabled: true)
            let publicCache = CourseBusinessCacheStorage(directory: publicDirectory, enabled: true)
            let originalScope = try original.scope(kind: .qmplus,
                owner: QMplusCredentialBackend.dataProtection.businessOwner(profileIdentifier: profile))
            let publicScope = try publicCache.scope(kind: .qmplus,
                owner: QMplusCredentialBackend.publicMacOS.businessOwner(profileIdentifier: profile))
            let originalPayload = try businessFixture(courseName: "EBU Synthetic Store Course")
            let publicPayload = try businessFixture(courseName: "EBU Synthetic Public Course")
            let maximum = CourseBusinessCacheValidation.maximumQMplusEnvelopeBytes
            let originalValue = CourseBusinessCachedValue(schemaVersion: 1, scope: originalScope,
                fetchedAt: originalPayload.fetchedAt, partial: true, payload: originalPayload)
            try original.save(originalValue, kind: .qmplus, maximumBytes: maximum)
            XCTAssertNil(try publicCache.load(kind: .qmplus, scope: publicScope, maximumBytes: maximum,
                as: QMplusSnapshot.self), "The public directory must never import the Store snapshot")
            let publicValue = CourseBusinessCachedValue(schemaVersion: 1, scope: publicScope,
                fetchedAt: publicPayload.fetchedAt, partial: true, payload: publicPayload)
            let rejectedScope = CourseBusinessCacheScope(
                owner: QMplusCredentialBackend.publicMacOS.rawValue + ":" + publicScope.owner, epoch: publicScope.epoch)
            XCTAssertThrowsError(try publicCache.save(CourseBusinessCachedValue(schemaVersion: 1, scope: rejectedScope,
                fetchedAt: publicPayload.fetchedAt, partial: true, payload: publicPayload), kind: .qmplus,
                maximumBytes: maximum), "The generic validator must continue rejecting the old invalid prefixed owner")
            try publicCache.save(publicValue, kind: .qmplus, maximumBytes: maximum)
            let reopened = CourseBusinessCacheStorage(directory: publicDirectory, enabled: true)
            let reopenedScope = try reopened.scope(kind: .qmplus,
                owner: QMplusCredentialBackend.publicMacOS.businessOwner(profileIdentifier: profile))
            XCTAssertEqual(reopenedScope, publicScope)
            let restored = try XCTUnwrap(reopened.load(kind: .qmplus, scope: reopenedScope,
                maximumBytes: maximum, as: QMplusSnapshot.self))
            XCTAssertEqual(restored.schemaVersion, publicValue.schemaVersion)
            XCTAssertEqual(restored.scope, publicValue.scope)
            XCTAssertEqual(restored.fetchedAt, publicValue.fetchedAt)
            XCTAssertEqual(restored.partial, publicValue.partial)
            XCTAssertEqual(restored.payload, publicPayload, "Every course, activity and optional DTO field survives reopening")
            let otherOwnerScope = try reopened.scope(kind: .qmplus, owner: UUID().uuidString)
            XCTAssertNil(try reopened.load(kind: .qmplus, scope: otherOwnerScope, maximumBytes: maximum,
                as: QMplusSnapshot.self), "A different profile cannot restore this snapshot")
            try reopened.rotateQMplusEpoch()
            let originalReopened = CourseBusinessCacheStorage(directory: originalDirectory, enabled: true)
            let preserved = try XCTUnwrap(originalReopened.load(kind: .qmplus, scope: originalScope,
                maximumBytes: maximum, as: QMplusSnapshot.self))
            XCTAssertEqual(preserved.payload, originalPayload, "Public rotation must retain the Store directory and DTO")
        }
    }

    #if os(macOS)
    func testPublicSaveReadAndClearUseOnlyIndependentSystemKeychainRecordAndNormalACL() throws {
        let probe = BackendKeychainProbe(), record = fixture()
        let dp = QMplusKeychainCredentialStore(access: probe)
        try dp.save(record)
        probe.queries.removeAll()
        let publicStore = QMplusKeychainCredentialStore(backend: .publicMacOS, access: probe)
        XCTAssertNil(try publicStore.authorizationMarker())
        XCTAssertNil(try publicStore.load(), "Existing Store credentials must never be copied")
        let publicRecord = fixture()
        try publicStore.save(publicRecord)
        XCTAssertEqual(try publicStore.load(), publicRecord)
        XCTAssertEqual(try publicStore.authorizationMarker(), publicRecord.marker)
        XCTAssertNotEqual(publicStore.query[kSecAttrService as String] as? String, QMplusKeychainCredentialStore.service)
        XCTAssertEqual(probe.lastAdded?[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertNil(probe.lastAdded?[kSecAttrAccess as String], "No unrestricted ACL or trusted-app list is installed")
        XCTAssertNil(probe.lastAdded?[kSecAttrAccessible as String], "File-based Keychain uses its normal protection")
        try publicStore.clear()
        XCTAssertNil(try publicStore.load())
        XCTAssertTrue(probe.queries.allSatisfy {
            $0[kSecUseDataProtectionKeychain as String] as? Bool == false &&
                $0[kSecAttrService as String] as? String == publicStore.query[kSecAttrService as String] as? String
        })
        XCTAssertEqual(try dp.load(), record)
    }

    func testDataProtectionErrorDoesNotTriggerPublicFallback() throws {
        let probe = BackendKeychainProbe()
        probe.readStatus = errSecAuthFailed
        let store = QMplusKeychainCredentialStore(access: probe)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(probe.queries.count, 1)
        XCTAssertEqual(probe.queries.first?[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }

    func testPublicExplicitSaveRequiresNewAuthorizationAndLeavesStoreSessionMetadataUntouched() throws {
        let suite = "QMplusBackendStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = fixture(), probe = BackendKeychainProbe()
        try QMplusKeychainCredentialStore(access: probe).save(old)
        let originalJournal = QMplusDefaultsAuthorizationJournal(defaults: defaults)
        try originalJournal.authorize(old.marker)
        let profile = UUID().uuidString
        defaults.set(profile, forKey: QMplusCredentialBackend.dataProtection.profileIdentifierKey)
        let store = QMplusStore(defaults: defaults,
            credentialStore: QMplusKeychainCredentialStore(backend: .publicMacOS, access: probe),
            allowsCredentialStorage: true, businessCache: .init(directory: nil, enabled: false), credentialBackend: .publicMacOS)
        store.credentialAuthorization.restoreAuthorization()
        XCTAssertFalse(store.credentialAuthorization.isEnabled)
        XCTAssertTrue(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-new-password"))
        let publicJournal = QMplusDefaultsAuthorizationJournal(defaults: defaults, backend: .publicMacOS)
        XCTAssertNotEqual(try publicJournal.load(), old.marker)
        store.disconnect()
        XCTAssertEqual(defaults.string(forKey: QMplusCredentialBackend.dataProtection.profileIdentifierKey), profile)
        XCTAssertEqual(try originalJournal.load(), old.marker)
        XCTAssertEqual(try QMplusKeychainCredentialStore(access: probe).load(), old)
        XCTAssertNil(store.webView)
    }

    func testPublicMarkerIsInsertedOnlyInPackageCopyBeforeSigningWithSourceAndSignedGates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/native-macos-package.sh"), encoding: .utf8)
        let insert = try XCTUnwrap(script.range(of: "plutil -insert \"$QMPLUS_DISTRIBUTION_KEY\" -string \"$QMPLUS_PUBLIC_DISTRIBUTION\" \"$INFO_PLIST\""))
        let signing = try XCTUnwrap(script.range(of: "codesign --force"))
        XCTAssertLessThan(insert.lowerBound, signing.lowerBound)
        XCTAssertTrue(script.contains("plutil -extract \"$QMPLUS_DISTRIBUTION_KEY\" raw \"$SOURCE_APP/Contents/Info.plist\""))
        XCTAssertTrue(script.contains("QMPLUS_DISTRIBUTION_KEY=\"\(QMplusCredentialBackend.distributionKey)\""))
        XCTAssertTrue(script.contains("QMPLUS_PUBLIC_DISTRIBUTION=\"\(QMplusCredentialBackend.publicDistribution)\""))
        XCTAssertEqual(script.components(separatedBy: "plutil -extract \"$QMPLUS_DISTRIBUTION_KEY\" raw \"$INFO_PLIST\"").count, 3)
        for path in ["native/apple/project.yml", "scripts/native-apple-app-store.sh", "scripts/native-ios-package.sh"] {
            XCTAssertFalse(try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                .contains(QMplusCredentialBackend.distributionKey), path)
        }
    }
    #endif

    private func fixture() -> QMplusSavedCredentials {
        .init(marker: .init(recordID: UUID(), authorizationNonce: UUID()),
              account: "synthetic@example.invalid", password: "synthetic-password")
    }

    private func businessFixture(courseName: String) throws -> QMplusSnapshot {
        let fetchedAt = ISO8601DateFormatter().string(from: Date())
        let snapshot = QMplusSnapshot(schemaVersion: 1, source: "qmplus", fetchedAt: fetchedAt,
            courses: [
                .init(id: "101", name: courseName, shortName: "EBU Synthetic", url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/course/view.php?id=101")),
                    startAt: "2026-09-01T00:00:00Z", endAt: "2027-01-31T23:59:00Z", currentTermStatus: .current),
                .init(id: "102", name: "EBU Synthetic Unknown Term", shortName: nil, url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/course/view.php?id=102")),
                    startAt: nil, endAt: nil, currentTermStatus: .unknown)
            ], activities: [
                .init(id: "201", courseID: "101", title: "Synthetic Assignment", kind: .assignment,
                    url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=201")),
                    dueAt: "2026-10-09T12:00:00Z", opensAt: "2026-10-01T00:00:00Z", closesAt: nil,
                    cutoffAt: "2026-10-10T12:00:00Z", timeLimitSeconds: nil, status: "Not submitted",
                    detailStatus: "available", rawTimeText: "Synthetic due date"),
                .init(id: "202", courseID: "102", title: "Synthetic Quiz", kind: .quiz,
                    url: try XCTUnwrap(URL(string: "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=202")),
                    dueAt: nil, opensAt: "2026-10-10T09:00:00Z", closesAt: "2026-10-11T09:00:00Z",
                    cutoffAt: nil, timeLimitSeconds: 1800, status: "Not attempted", detailStatus: "restricted", rawTimeText: nil)
            ], warnings: ["Synthetic restricted activity"])
        // Exercise the same DTO policy used by receive() before disk storage.
        return try QMplusSnapshotPolicy.decode(JSONEncoder().encode(snapshot))
    }
}

private final class BackendKeychainProbe: QMplusKeychainAccessing, @unchecked Sendable {
    var queries = [[String: Any]]()
    var records = [String: [String: Any]]()
    var lastAdded: [String: Any]?
    var readStatus: OSStatus?
    private func key(_ query: [String: Any]) -> String { query[kSecAttrService as String] as? String ?? "invalid" }
    func copyMatching(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus {
        let query = query as! [String: Any]
        queries.append(query)
        if let readStatus { return readStatus }
        guard let record = records[key(query)] else { return errSecItemNotFound }
        if query[kSecReturnData as String] as? Bool == true { result = record[kSecValueData as String] as CFTypeRef? }
        else { result = [kSecAttrGeneric as String: record[kSecAttrGeneric as String]!] as CFDictionary }
        return errSecSuccess
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        let query = query as! [String: Any]
        queries.append(query)
        guard let record = records[key(query)] else { return errSecItemNotFound }
        records[key(query)] = record.merging(attributes as! [String: Any]) { _, new in new }
        return errSecSuccess
    }
    func add(_ attributes: CFDictionary) -> OSStatus {
        let attributes = attributes as! [String: Any]
        queries.append(attributes); lastAdded = attributes
        records[key(attributes)] = attributes
        return errSecSuccess
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        let query = query as! [String: Any]
        queries.append(query)
        records.removeValue(forKey: key(query))
        return errSecSuccess
    }
}
