import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

@MainActor
final class QMplusCredentialAuthorizationTests: XCTestCase {
    func testDefaultOffAndRestoreOnlyReadsNonsecretMatchingMetadata() throws {
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        authorization.loadIfNeeded()
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertEqual(vault.secretReads, 0)
        let record = fixture()
        vault.record = record
        let orphan = QMplusCredentialAuthorization(storage: vault, journal: journal)
        orphan.restoreAuthorization()
        XCTAssertFalse(orphan.isEnabled, "A Keychain record without explicit opt-in cannot authorize autofill")
        journal.marker = record.marker
        let restored = QMplusCredentialAuthorization(storage: vault, journal: journal)
        restored.restoreAuthorization()
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(vault.secretReads, 0, "Settings restoration must not read an account or password")
    }

    func testSaveWithdrawsAuthorityBeforeSecretAndAuthorizesOnlyAfterReadback() throws {
        let calls = FakeQMCalls(), vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        vault.calls = calls; journal.calls = calls
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertTrue(authorization.saveAndAuthorize(account: " synthetic@example.invalid ", password: " synthetic-password "))
        XCTAssertTrue(authorization.isEnabled)
        XCTAssertEqual(calls.values, ["journal.revoke", "vault.save", "vault.load", "vault.marker", "journal.authorize", "journal.load"])
        let first = try XCTUnwrap(vault.record)
        XCTAssertEqual(first.account, "synthetic@example.invalid")
        XCTAssertEqual(first.password, " synthetic-password ", "Password whitespace must not be silently changed")
        XCTAssertEqual(journal.marker, first.marker)
        XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "replacement-synthetic"))
        XCTAssertNotEqual(vault.record?.marker, first.marker)
        XCTAssertEqual(journal.marker, vault.record?.marker)
    }

    func testInterruptedReplacementCannotMatchOldJournal() {
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        journal.marker = fixture().marker
        vault.record = fixture()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        authorization.restoreAuthorization()
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertEqual(vault.secretReads, 0)
    }

    func testAuthorizedReadRejectsChangedRecordBeforeReadingPasswordAndRefreshChangesRevision() {
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        let revision = authorization.credentialRevision
        let reads = vault.secretReads
        let replacement = fixture()
        vault.record = replacement; journal.marker = replacement.marker
        XCTAssertNil(authorization.loadAuthorizedCredentials(expectedRevision: revision))
        XCTAssertEqual(vault.secretReads, reads)
        XCTAssertFalse(authorization.isEnabled)
        authorization.restoreAuthorization()
        XCTAssertTrue(authorization.isEnabled)
        XCTAssertGreaterThan(authorization.credentialRevision, revision)
        XCTAssertNil(authorization.loadAuthorizedCredentials(expectedRevision: revision))
    }

    func testPasswordBoundMatchesSharedHelper2048CharactersAnd4096UTF8Bytes() {
        func record(_ password: String) -> QMplusSavedCredentials {
            .init(marker: .init(recordID: UUID(), authorizationNonce: UUID()), account: "synthetic@example.invalid", password: password)
        }
        XCTAssertTrue(record(String(repeating: "a", count: 2048)).isValid)
        XCTAssertFalse(record(String(repeating: "a", count: 2049)).isValid)
        XCTAssertTrue(record(String(repeating: "😀", count: 1024)).isValid)
        XCTAssertFalse(record(String(repeating: "😀", count: 1025)).isValid)
    }

    func testFailedReadbackOrJournalAuthorizationNeverEnablesAutofill() {
        for failure in ["readback", "journal"] {
            let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
            vault.failRead = failure == "readback"
            journal.failAuthorize = failure == "journal"
            let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
            XCTAssertFalse(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
            XCTAssertFalse(authorization.isEnabled)
            XCTAssertNil(journal.marker)
            XCTAssertNil(vault.record)
        }
    }

    func testDisableRevokesMemoryThenJournalBeforeSecretDeletionAndRemainsOffAfterRestart() {
        let calls = FakeQMCalls(), vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        let revision = authorization.credentialRevision
        vault.calls = calls; journal.calls = calls
        vault.onClear = { [weak authorization] in XCTAssertFalse(authorization?.isEnabled ?? true) }
        XCTAssertTrue(authorization.disableAndDelete())
        XCTAssertGreaterThan(authorization.credentialRevision, revision)
        XCTAssertEqual(calls.values, ["journal.revoke", "vault.clear"])
        let restarted = QMplusCredentialAuthorization(storage: vault, journal: journal)
        restarted.restoreAuthorization()
        XCTAssertFalse(restarted.isEnabled)
    }

    func testSingleStorageFailureCannotReviveOldAuthority() {
        for failedStorage in ["journal", "vault"] {
            let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
            let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
            XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
            vault.failClear = failedStorage == "vault"; journal.failRevoke = failedStorage == "journal"
            XCTAssertFalse(authorization.disableAndDelete())
            XCTAssertFalse(authorization.isEnabled)
            XCTAssertTrue(authorization.removalNeedsAttention)
            let restarted = QMplusCredentialAuthorization(storage: vault, journal: journal)
            restarted.restoreAuthorization()
            XCTAssertFalse(restarted.isEnabled)
        }
    }

    func testBothStorageFailuresWarnAboutNextLaunchInsteadOfClaimingDurableDeletion() {
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        vault.failClear = true; journal.failRevoke = true
        XCTAssertFalse(authorization.disableAndDelete())
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertEqual(authorization.statusKey, "QMplus 自动填写已在本次使用中停用；下次启动请核对保存状态。")
        XCTAssertNotNil(vault.record)
        XCTAssertNotNil(journal.marker)
    }

    func testSampleAndSuspendDoNotReadOrDeleteRealStorage() {
        let calls = FakeQMCalls(), vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        vault.calls = calls; journal.calls = calls
        let sample = QMplusCredentialAuthorization(storage: vault, journal: journal, allowsStorage: false)
        sample.restoreAuthorization()
        XCTAssertFalse(sample.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        XCTAssertTrue(sample.disableAndDelete())
        XCTAssertTrue(calls.values.isEmpty)
        let live = QMplusCredentialAuthorization(storage: vault, journal: journal)
        XCTAssertTrue(live.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        calls.values = []
        live.suspendInMemory()
        XCTAssertFalse(live.isEnabled)
        XCTAssertTrue(calls.values.isEmpty)
        live.restoreAuthorization()
        XCTAssertTrue(live.isEnabled)
    }

    func testNonsecretPreferencesContainOnlyRandomMatchingMarkerAndDefaultOff() throws {
        let suite = "QMplusJournalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = QMplusDefaultsAuthorizationJournal(defaults: defaults)
        XCTAssertNil(try journal.load())
        let marker = fixture().marker
        try journal.authorize(marker)
        XCTAssertEqual(try journal.load(), marker)
        let encoded = String(decoding: try XCTUnwrap(defaults.data(forKey: QMplusDefaultsAuthorizationJournal.key)), as: UTF8.self)
        XCTAssertFalse(encoded.contains("account"))
        XCTAssertFalse(encoded.contains("password"))
        XCTAssertFalse(encoded.contains("synthetic"))
        try journal.revoke()
        XCTAssertNil(try journal.load())
        XCTAssertNotEqual(QMplusKeychainCredentialStore.account, "bupt-jwgl")
        XCTAssertNotEqual(QMplusKeychainCredentialStore.service, "com.nemoyu.wheretostudy.native.credentials")
    }

    func testExplicitDisconnectDeletesDedicatedCredentialsAndClearsPendingDraft() throws {
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let suite = "QMplusCredentialDisconnectTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, credentialStore: vault, authorizationJournal: journal, allowsCredentialStorage: true)
        XCTAssertTrue(store.saveCredentials(account: "synthetic@example.invalid", password: "synthetic-password"))
        store.credentialDraft.account = "draft@example.invalid"; store.credentialDraft.password = "synthetic-draft"
        store.disconnect()
        XCTAssertFalse(store.credentialAuthorization.isEnabled)
        XCTAssertNil(vault.record)
        XCTAssertNil(journal.marker)
        XCTAssertEqual(store.credentialDraft.account, "")
        XCTAssertEqual(store.credentialDraft.password, "")
        XCTAssertNil(store.webView, "Credential tests must not construct WebKit or request any website")
    }

    private func fixture() -> QMplusSavedCredentials {
        .init(marker: .init(recordID: UUID(), authorizationNonce: UUID()), account: "synthetic@example.invalid", password: "synthetic-password")
    }
}

private enum FakeQMFailure: Error { case injected }
private final class FakeQMCalls: @unchecked Sendable { var values: [String] = [] }
private final class FakeQMCredentialVault: QMplusCredentialStoring, @unchecked Sendable {
    var record: QMplusSavedCredentials?
    var calls: FakeQMCalls?
    var secretReads = 0
    var failRead = false, failClear = false
    var onClear: (@MainActor () -> Void)?
    func authorizationMarker() throws -> QMplusCredentialAuthorizationMarker? { calls?.values.append("vault.marker"); return record?.marker }
    func load() throws -> QMplusSavedCredentials? {
        calls?.values.append("vault.load"); secretReads += 1
        if failRead { throw FakeQMFailure.injected }
        return record
    }
    func save(_ credentials: QMplusSavedCredentials) throws { calls?.values.append("vault.save"); record = credentials }
    func clear() throws {
        calls?.values.append("vault.clear")
        MainActor.assumeIsolated { onClear?() }
        if failClear { throw FakeQMFailure.injected }
        record = nil
    }
}
private final class FakeQMAuthorizationJournal: QMplusCredentialAuthorizationJournaling, @unchecked Sendable {
    var marker: QMplusCredentialAuthorizationMarker?
    var calls: FakeQMCalls?
    var failAuthorize = false, failRevoke = false
    func load() throws -> QMplusCredentialAuthorizationMarker? { calls?.values.append("journal.load"); return marker }
    func authorize(_ marker: QMplusCredentialAuthorizationMarker) throws {
        calls?.values.append("journal.authorize")
        if failAuthorize { throw FakeQMFailure.injected }
        self.marker = marker
    }
    func revoke() throws {
        calls?.values.append("journal.revoke")
        if failRevoke { throw FakeQMFailure.injected }
        marker = nil
    }
}
