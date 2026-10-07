import XCTest
import Security
import Combine
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

// Pure specification source only; no real credentials or WebKit are used.
// These tests are not executed while local automation is prohibited.
@MainActor
final class QMplusCredentialAuthorizationTests: XCTestCase {
    func testActivationRearmsAnExpiredPreparationWithoutCreatingAnOwnerOrReadingSecrets() async throws {
        let suite = "QMplusExpiredPreparation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let saved = fixture(); vault.record = saved; journal.marker = saved.marker
        vault.markerError = .keychain(errSecNotAvailable)
        let store = QMplusStore(defaults: defaults, credentialStore: vault,
            authorizationJournal: journal, allowsCredentialStorage: true,
            businessCache: .init(directory: nil, enabled: false), preparationWait: { await Task.yield() })
        let expired = expectation(description: "The requested startup preparation exhausts its bounded wait")
        let observation = store.$statusKey.sink { if $0 == "QMplus 官方网页登录失败，请重试" { expired.fulfill() } }
        store.connect(sampleMode: false, background: true)
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertFalse(store.isPreparingConnection)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView)
        // This is also the macOS application-activation consumer; a scene ID
        // change is not required to retry an unstarted preparation.
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertTrue(store.isPreparingConnection)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertEqual(vault.secretReads, 0)
        XCTAssertEqual(vault.record, saved)
        XCTAssertEqual(journal.marker, saved.marker)
        store.endPresentation()
        withExtendedLifetime(observation) {}
    }

    func testExplicitCloseAfterPreparationExpiryCannotBeRevivedByActivation() async throws {
        let suite = "QMplusClosedPreparation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        journal.marker = fixture().marker; vault.markerError = .keychain(errSecNotAvailable)
        let store = QMplusStore(defaults: defaults, credentialStore: vault,
            authorizationJournal: journal, allowsCredentialStorage: true,
            businessCache: .init(directory: nil, enabled: false), preparationWait: { await Task.yield() })
        let expired = expectation(description: "Preparation expires before an explicit close")
        let observation = store.$statusKey.sink { if $0 == "QMplus 官方网页登录失败，请重试" { expired.fulfill() } }
        store.connect(sampleMode: false, background: true)
        await fulfillment(of: [expired], timeout: 2)
        store.endPresentation()
        let reads = vault.markerReads
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertFalse(store.isPreparingConnection)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView)
        XCTAssertEqual(vault.markerReads, reads)
        XCTAssertEqual(vault.secretReads, 0)
        withExtendedLifetime(observation) {}
    }

    func testInactiveSceneCancelsPreparationButItsRequestedIntentCanResumeOnceActive() throws {
        let suite = "QMplusResumedPreparation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        journal.marker = fixture().marker; vault.markerError = .keychain(errSecNotAvailable)
        let store = QMplusStore(defaults: defaults, credentialStore: vault,
            authorizationJournal: journal, allowsCredentialStorage: true,
            businessCache: .init(directory: nil, enabled: false))
        store.connect(sampleMode: false, background: true)
        XCTAssertTrue(store.isPreparingConnection)
        store.stopAutomaticLoginForInactiveScene()
        XCTAssertFalse(store.isPreparingConnection)
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertTrue(store.isPreparingConnection)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView)
        XCTAssertEqual(vault.secretReads, 0)
        store.setFeatureEnabled(false)
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertFalse(store.isPreparingConnection)
    }

    func testActivationWithoutAPreviousPreparationRequestDoesNotStartAConnection() throws {
        let suite = "QMplusUnrequestedActivation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let store = QMplusStore(defaults: defaults, credentialStore: vault,
            authorizationJournal: journal, allowsCredentialStorage: true,
            businessCache: .init(directory: nil, enabled: false))
        store.resumeAuthenticationRecognitionForActiveScene()
        XCTAssertFalse(store.isPreparingConnection)
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView)
        XCTAssertEqual(vault.markerReads, 0)
        XCTAssertEqual(vault.secretReads, 0)
    }

    func testInactiveSceneCancelsPreparationBeforeItCanCreateALoginOwner() async throws {
        let suite = "QMplusInactivePreparation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        journal.marker = .init(recordID: UUID(), authorizationNonce: UUID())
        vault.markerError = .keychain(errSecInteractionNotAllowed)
        let store = QMplusStore(defaults: defaults, credentialStore: vault,
            authorizationJournal: journal, allowsCredentialStorage: true)
        store.connect(sampleMode: false, background: true)
        XCTAssertTrue(store.isPreparingConnection)
        XCTAssertFalse(store.hasActiveConnection)
        store.stopAutomaticLoginForInactiveScene()
        XCTAssertFalse(store.isPreparingConnection)
        await Task.yield()
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertFalse(store.requiresManualContinuation)
        XCTAssertFalse(store.isShowingConnection)
        XCTAssertNil(store.webView)
        XCTAssertEqual(vault.secretReads, 0, "Waiting for startup availability must inspect metadata only")
        store.endPresentation()
    }

    func testFeatureOffCancelsPendingPreparationAndCannotLaterOpenAWebView() async throws {
        let suite = "QMplusDisabledPreparation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        journal.marker = .init(recordID: UUID(), authorizationNonce: UUID())
        vault.markerError = .keychain(errSecNotAvailable)
        let store = QMplusStore(defaults: defaults, credentialStore: vault,
            authorizationJournal: journal, allowsCredentialStorage: true)
        store.connect(sampleMode: false, background: true)
        XCTAssertTrue(store.isPreparingConnection)
        store.setFeatureEnabled(false)
        XCTAssertFalse(store.isPreparingConnection)
        await Task.yield()
        XCTAssertFalse(store.hasActiveConnection)
        XCTAssertNil(store.webView)
        XCTAssertEqual(vault.secretReads, 0)
    }

    func testTemporaryMetadataUnavailabilityRetriesWithoutReadingSecretsOrChangingSavedAuthority() {
        for status in [errSecInteractionNotAllowed, errSecNotAvailable] {
            let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
            let saved = fixture()
            vault.record = saved; journal.marker = saved.marker
            vault.markerError = .keychain(status)
            let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
            authorization.loadIfNeeded()
            XCTAssertTrue(authorization.isTemporarilyUnavailable)
            XCTAssertFalse(authorization.isEnabled)
            XCTAssertNil(authorization.loadAuthorizedCredentials(expectedRevision: authorization.credentialRevision))
            XCTAssertEqual(vault.secretReads, 0)
            XCTAssertEqual(vault.record, saved)
            XCTAssertEqual(journal.marker, saved.marker)
            let reads = vault.markerReads
            authorization.loadIfNeeded()
            XCTAssertEqual(vault.markerReads, reads + 1, "A temporary failure must not latch hasLoaded")
            vault.markerError = nil
            authorization.loadIfNeeded()
            XCTAssertTrue(authorization.isEnabled)
            XCTAssertFalse(authorization.isTemporarilyUnavailable)
            XCTAssertEqual(vault.secretReads, 0, "Availability recovery still restores metadata only")
        }
    }

    func testTemporaryRestoreWithdrawsOldAuthorityAndRechecksChangedMarkers() {
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let saved = fixture()
        vault.record = saved; journal.marker = saved.marker
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        authorization.restoreAuthorization()
        let revision = authorization.credentialRevision
        vault.markerError = .keychain(errSecNotAvailable)
        authorization.restoreAuthorization()
        XCTAssertTrue(authorization.isTemporarilyUnavailable)
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertGreaterThan(authorization.credentialRevision, revision)
        XCTAssertNil(authorization.loadAuthorizedCredentials(expectedRevision: revision))
        vault.markerError = nil
        journal.marker = fixture().marker
        authorization.loadIfNeeded()
        XCTAssertFalse(authorization.isEnabled, "A prior marker cannot authorize the changed record")
        XCTAssertFalse(authorization.isTemporarilyUnavailable)
        let reads = vault.markerReads
        journal.marker = saved.marker
        authorization.loadIfNeeded()
        XCTAssertEqual(vault.markerReads, reads, "A real mismatch is not an availability retry")
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertEqual(vault.secretReads, 0)
    }

    func testOnlyTheTwoExplicitKeychainAvailabilityErrorsAutomaticallyRetry() {
        for error in [QMplusCredentialStorageError.keychain(errSecAuthFailed), .keychain(errSecUserCanceled),
                      .invalidRecord, .verificationFailed] {
            let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
            let saved = fixture()
            vault.record = saved; journal.marker = saved.marker; vault.markerError = error
            let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
            authorization.loadIfNeeded()
            XCTAssertFalse(authorization.isTemporarilyUnavailable)
            XCTAssertFalse(authorization.isEnabled)
            let reads = vault.markerReads
            vault.markerError = nil
            authorization.loadIfNeeded()
            XCTAssertEqual(vault.markerReads, reads)
            XCTAssertFalse(authorization.isEnabled)
            XCTAssertEqual(vault.secretReads, 0)
        }
    }

    func testTemporarySecretReadReturnsNothingAndInvalidatesThePreviousRevision() {
        for status in [errSecInteractionNotAllowed, errSecNotAvailable] {
            let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
            let saved = fixture()
            vault.record = saved; journal.marker = saved.marker
            let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
            authorization.restoreAuthorization()
            let revision = authorization.credentialRevision
            vault.readError = .keychain(status)
            XCTAssertNil(authorization.loadAuthorizedCredentials(expectedRevision: revision))
            XCTAssertTrue(authorization.isTemporarilyUnavailable)
            XCTAssertFalse(authorization.isEnabled)
            XCTAssertGreaterThan(authorization.credentialRevision, revision)
            vault.readError = nil
            authorization.loadIfNeeded()
            XCTAssertTrue(authorization.isEnabled)
            XCTAssertFalse(authorization.isTemporarilyUnavailable)
            XCTAssertEqual(vault.secretReads, 1, "Metadata retry must not repeat the failed secret read")
            XCTAssertNil(authorization.loadAuthorizedCredentials(expectedRevision: revision))
            XCTAssertEqual(authorization.loadAuthorizedCredentials(expectedRevision: authorization.credentialRevision), saved)
        }
    }

    func testExplicitDisableCancelsAvailabilityRetryEvenWhenDurableDeletionFails() {
        for failDeletion in [false, true] {
            let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
            let saved = fixture()
            vault.record = saved; journal.marker = saved.marker
            vault.markerError = .keychain(errSecInteractionNotAllowed)
            let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
            authorization.loadIfNeeded()
            XCTAssertTrue(authorization.isTemporarilyUnavailable)
            vault.failClear = failDeletion; journal.failRevoke = failDeletion
            XCTAssertEqual(authorization.disableAndDelete(), !failDeletion)
            XCTAssertFalse(authorization.isTemporarilyUnavailable)
            vault.markerError = nil
            let reads = vault.markerReads
            authorization.loadIfNeeded()
            authorization.restoreAuthorization()
            authorization.suspendInMemory()
            authorization.loadIfNeeded()
            XCTAssertFalse(authorization.isEnabled)
            XCTAssertFalse(authorization.isTemporarilyUnavailable)
            XCTAssertEqual(vault.markerReads, reads, "Foreground recovery cannot undo the user's disable")
            XCTAssertEqual(vault.secretReads, 0)
            vault.failClear = false; journal.failRevoke = false
            XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-new-password"))
            authorization.suspendInMemory()
            authorization.loadIfNeeded()
            XCTAssertTrue(authorization.isEnabled, "Only a successful explicit save may grant authority again")
        }
    }

    func testAuthorizationDefaultsOffAndRestoreOnlyReadsNonsecretMatchingMetadata() throws {
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

    func testInitialSaveChoiceIsOnWithoutCreatingSavedCredentialsOrAuthorization() throws {
        let suite = "QMplusInitialSaveChoice.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = QMplusCredentialDraft(defaults: defaults)
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        authorization.loadIfNeeded()
        XCTAssertTrue(draft.wantsToSave)
        XCTAssertTrue(draft.account.isEmpty)
        XCTAssertTrue(draft.password.isEmpty)
        XCTAssertNil(defaults.object(forKey: QMplusCredentialDraft.preferenceKey), "The first-use default is not a saved opt-in record")
        XCTAssertFalse(authorization.isEnabled)
        XCTAssertNil(vault.record)
        XCTAssertNil(journal.marker)
        XCTAssertEqual(vault.secretReads, 0)
    }

    func testExplicitOffChoiceSurvivesDraftClearingAndReconstructionUntilPreferencesReset() throws {
        let suite = "QMplusExplicitSaveChoice.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = QMplusCredentialDraft(defaults: defaults)
        draft.account = "synthetic@example.invalid"
        draft.password = "synthetic-draft-password"
        draft.disableSaving()
        XCTAssertFalse(draft.wantsToSave)
        XCTAssertTrue(draft.account.isEmpty)
        XCTAssertTrue(draft.password.isEmpty)
        XCTAssertEqual(defaults.object(forKey: QMplusCredentialDraft.preferenceKey) as? Bool, false)
        draft.clear()
        let reconstructed = QMplusCredentialDraft(defaults: defaults)
        XCTAssertFalse(reconstructed.wantsToSave)
        XCTAssertTrue(reconstructed.account.isEmpty)
        XCTAssertTrue(reconstructed.password.isEmpty)
        reconstructed.resetSavingPreference()
        XCTAssertTrue(reconstructed.wantsToSave)
        XCTAssertNil(defaults.object(forKey: QMplusCredentialDraft.preferenceKey))
        XCTAssertTrue(QMplusCredentialDraft(defaults: defaults).wantsToSave)
    }

    func testVerifiedSavedStateSurvivesEmptyEditingFieldsAndAnUnrelatedValidationStatus() {
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let authorization = QMplusCredentialAuthorization(storage: vault, journal: journal)
        let draft = QMplusCredentialDraft(defaults: nil)
        XCTAssertTrue(authorization.saveAndAuthorize(account: "synthetic@example.invalid", password: "synthetic-password"))
        let saved = vault.record
        let reads = vault.secretReads
        draft.account = "synthetic@example.invalid"
        draft.password = "synthetic-edit"
        draft.clear()
        XCTAssertTrue(draft.wantsToSave)
        XCTAssertTrue(draft.account.isEmpty)
        XCTAssertTrue(draft.password.isEmpty, "The editor must not reload the saved password")
        XCTAssertTrue(authorization.isEnabled, "The persistent saved badge depends on verified authorization, not editable input")
        XCTAssertFalse(authorization.saveAndAuthorize(account: "", password: ""))
        XCTAssertEqual(authorization.statusKey, "请填写有效的 QMplus 账号和密码。")
        XCTAssertTrue(authorization.isEnabled, "A transient validation message does not replace the verified saved state")
        XCTAssertEqual(vault.record, saved)
        let restored = QMplusCredentialAuthorization(storage: vault, journal: journal)
        restored.restoreAuthorization()
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(vault.secretReads, reads, "Checking the saved state must read metadata only")
    }

    func testStorageProhibitedDraftChoiceNeverTouchesTheProvidedDefaults() throws {
        let suite = "QMplusSampleSaveChoice.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = FakeQMCredentialVault(), journal = FakeQMAuthorizationJournal()
        let store = QMplusStore(defaults: defaults, credentialStore: vault, authorizationJournal: journal, allowsCredentialStorage: false)
        XCTAssertTrue(store.credentialDraft.wantsToSave)
        store.credentialDraft.disableSaving()
        XCTAssertNil(defaults.object(forKey: QMplusCredentialDraft.preferenceKey))
        XCTAssertFalse(store.credentialAuthorization.isEnabled)
        XCTAssertEqual(vault.secretReads, 0)
        XCTAssertNil(store.webView)
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
        XCTAssertFalse(store.credentialDraft.wantsToSave)
        XCTAssertFalse(QMplusCredentialDraft(defaults: defaults).wantsToSave)
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
    var markerReads = 0
    var markerError: QMplusCredentialStorageError?
    var readError: QMplusCredentialStorageError?
    var failRead = false, failClear = false
    var onClear: (@MainActor () -> Void)?
    func authorizationMarker() throws -> QMplusCredentialAuthorizationMarker? {
        calls?.values.append("vault.marker"); markerReads += 1
        if let markerError { throw markerError }
        return record?.marker
    }
    func load() throws -> QMplusSavedCredentials? {
        calls?.values.append("vault.load"); secretReads += 1
        if let readError { throw readError }
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
