import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

// Test source only: not executed while local automation is prohibited.
@MainActor
final class QMplusCredentialSavePolicyTests: XCTestCase {
    func testVerifiedSameInputSaveKeepsMarkerRevisionAndSecureRecordWithoutWriting() throws {
        let vault = SavePolicyVault(), journal = SavePolicyJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertEqual(authorization.saveAndAuthorizeWithDisposition(account: "synthetic@example.invalid", password: " synthetic-password "), .replaced)
        let record = try XCTUnwrap(vault.record)
        let revision = authorization.credentialRevision
        let saves = vault.saves, authorizations = journal.authorizations, revocations = journal.revocations
        XCTAssertEqual(authorization.saveAndAuthorizeWithDisposition(account: " synthetic@example.invalid ", password: " synthetic-password "), .unchanged)
        XCTAssertEqual(vault.record, record)
        XCTAssertEqual(journal.marker, record.marker)
        XCTAssertEqual(authorization.credentialRevision, revision)
        XCTAssertEqual(vault.saves, saves)
        XCTAssertEqual(journal.authorizations, authorizations)
        XCTAssertEqual(journal.revocations, revocations)
    }

    func testChangedPasswordWhitespaceOrAccountUsesFreshAuthorization() throws {
        for accountChange in [false, true] {
            let vault = SavePolicyVault(), journal = SavePolicyJournal()
            let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
            XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
            let first = try XCTUnwrap(vault.record)
            let disposition = authorization.saveAndAuthorizeWithDisposition(
                account: accountChange ? "other@example.invalid" : first.account,
                password: accountChange ? first.password : " synthetic-password ")
            XCTAssertEqual(disposition, .replaced)
            XCTAssertNotEqual(vault.record?.marker, first.marker)
            XCTAssertEqual(journal.marker, vault.record?.marker)
        }
    }

    func testOrphanedSameRecordRequiresFreshExplicitAuthorization() throws {
        let vault = SavePolicyVault(), journal = SavePolicyJournal()
        let old = fixture()
        vault.record = old
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        authorization.restoreAuthorization()
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertEqual(authorization.saveAndAuthorizeWithDisposition(account: old.account, password: old.password), .replaced)
        XCTAssertNotEqual(vault.record?.marker, old.marker)
        XCTAssertEqual(journal.marker, vault.record?.marker)
    }

    func testMarkerReadFailureCannotBeReportedAsUnchanged() {
        let vault = SavePolicyVault(), journal = SavePolicyJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        vault.markerReadFails = true
        XCTAssertEqual(authorization.saveAndAuthorizeWithDisposition(account: "synthetic@example.invalid", password: "synthetic-password"), .failed)
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertNil(journal.marker)
        XCTAssertNil(vault.record)
    }

    func testMetadataChangingDuringSecureReadCannotUseTheUnchangedDisposition() throws {
        let vault = SavePolicyVault(), journal = SavePolicyJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        let prior = try XCTUnwrap(vault.record)
        vault.onNextLoad = { journal.marker = nil }
        XCTAssertEqual(authorization.saveAndAuthorizeWithDisposition(account: prior.account, password: prior.password), .replaced)
        XCTAssertNotEqual(vault.record?.marker, prior.marker)
    }

    func testUnchangedStoreSaveRetiresCallbacksButKeepsProfileIdentifierAndVerifiedSnapshot() throws {
        let suite = "QMplusSavePolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = SavePolicyVault(), journal = SavePolicyJournal()
        let store = QMplusStore(defaults: defaults, credentialStore: vault, authorizationJournal: journal, allowsCredentialStorage: true)
        XCTAssertTrue(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-password"))
        let first = try XCTUnwrap(store.beginSynchronization())
        store.receive(try payload(), request: first)
        let snapshot = try XCTUnwrap(store.snapshot)
        let profile = UUID().uuidString
        defaults.set(profile, forKey: "qmplusWebsiteDataStoreIdentifier")
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        let late = try XCTUnwrap(store.beginSynchronization())
        store.credentialDraft.account = "synthetic@example.invalid"
        store.credentialDraft.password = "synthetic-password"
        XCTAssertTrue(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-password"))
        store.receive(try payload(), request: late)
        XCTAssertEqual(defaults.string(forKey: "qmplusWebsiteDataStoreIdentifier"), profile)
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.isSyncing)
        XCTAssertTrue(store.credentialDraft.account.isEmpty)
        XCTAssertTrue(store.credentialDraft.password.isEmpty)
        XCTAssertNil(store.webView, "No test loads a webpage or reads a real Keychain record")
    }

    func testFailedStoreSaveDoesNotRetainAnUnverifiedProfileIdentifier() throws {
        let suite = "QMplusFailedSavePolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = SavePolicyVault(), journal = SavePolicyJournal()
        let store = QMplusStore(defaults: defaults, credentialStore: vault, authorizationJournal: journal, allowsCredentialStorage: true)
        XCTAssertTrue(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-password"))
        defaults.set(UUID().uuidString, forKey: "qmplusWebsiteDataStoreIdentifier")
        vault.markerReadFails = true
        XCTAssertFalse(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-password"))
        XCTAssertNil(defaults.string(forKey: "qmplusWebsiteDataStoreIdentifier"))
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.credentialAuthorization.isEnabled)
    }

    func testStorageProhibitedSaveCannotClearAnExistingProfileIdentifier() throws {
        let suite = "QMplusProhibitedSavePolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = UUID().uuidString
        defaults.set(profile, forKey: "qmplusWebsiteDataStoreIdentifier")
        let vault = SavePolicyVault(), journal = SavePolicyJournal()
        let store = QMplusStore(defaults: defaults, credentialStore: vault, authorizationJournal: journal, allowsCredentialStorage: false)
        XCTAssertFalse(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-password"))
        XCTAssertEqual(defaults.string(forKey: "qmplusWebsiteDataStoreIdentifier"), profile)
        XCTAssertEqual(vault.saves, 0)
        XCTAssertEqual(journal.authorizations, 0)
        XCTAssertNil(store.webView)
    }

    private func fixture() -> QMplusSavedCredentials {
        .init(marker: .init(recordID: UUID(), authorizationNonce: UUID()),
              account: "synthetic@example.invalid", password: "synthetic-password")
    }

    private func payload() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "source": "qmplus", "fetched_at": "2026-10-05T12:00:00.000Z",
            "ok": true, "partial": false, "warnings": [], "courses": [], "activities": [],
        ])
    }
}

private final class SavePolicyVault: QMplusCredentialStoring, @unchecked Sendable {
    var record: QMplusSavedCredentials?
    var saves = 0
    var markerReadFails = false
    var onNextLoad: (() -> Void)?
    func authorizationMarker() throws -> QMplusCredentialAuthorizationMarker? {
        if markerReadFails { throw QMplusCredentialStorageError.verificationFailed }
        return record?.marker
    }
    func load() throws -> QMplusSavedCredentials? {
        let saved = record
        let work = onNextLoad
        onNextLoad = nil
        work?()
        return saved
    }
    func save(_ credentials: QMplusSavedCredentials) throws { saves += 1; record = credentials }
    func clear() throws { record = nil }
}

private final class SavePolicyJournal: QMplusCredentialAuthorizationJournaling, @unchecked Sendable {
    var marker: QMplusCredentialAuthorizationMarker?
    var authorizations = 0, revocations = 0
    func load() throws -> QMplusCredentialAuthorizationMarker? { marker }
    func authorize(_ marker: QMplusCredentialAuthorizationMarker) throws { authorizations += 1; self.marker = marker }
    func revoke() throws { revocations += 1; marker = nil }
}
