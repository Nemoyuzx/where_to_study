import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

@MainActor
final class QMplusAutofillPipelineTests: XCTestCase {
    func testNamespaceConflictNeverReadsOrSendsCredentials() {
        let fixture = Fixture()
        fixture.evaluator.installResult = .conflict
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertEqual(fixture.credentialReads, 0)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.manualCount, 1)
    }

    func testLateInstallationAfterNativeURLOrOwnerChangesNeverReadsCredentials() {
        let fixture = Fixture()
        fixture.evaluator.holdsInstallation = true
        fixture.pipeline.start(source: "synthetic source")
        fixture.current = false
        fixture.evaluator.finishInstallation(.installed)
        XCTAssertEqual(fixture.credentialReads, 0)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.manualCount, 0, "An old callback must not reopen a cancelled session")
    }

    func testSameDocumentSPATransitionSubmitsUsernameAndMatchingPasswordExactlyOnce() async {
        let fixture = Fixture()
        let completed = expectation(description: "SPA auto-fill stops at the following manual screen")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.username), state(.manual, reason: .attempted), state(.password, match: true), state(.manual, reason: .interference)]
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.evaluator.submissions.count, 2)
        guard let first = fixture.evaluator.submissions.first, case let .username(document, account) = first else { return XCTFail("First request must be username-only") }
        XCTAssertEqual(document, "nonceA123")
        XCTAssertEqual(account, "synthetic@example.invalid")
        guard let last = fixture.evaluator.submissions.last, case let .password(passwordDocument, passwordAccount, password) = last else { return XCTFail("Second request must be the verified matching password stage") }
        XCTAssertEqual(passwordDocument, document)
        XCTAssertEqual(passwordAccount, account)
        XCTAssertEqual(password, "synthetic-password")
        XCTAssertEqual(fixture.waits, [.milliseconds(250), .milliseconds(500), .milliseconds(250)])
    }

    func testAccountSelectionBridgePayloadContainsOnlyAccountAndDocumentNonce() {
        let call = QMplusWebKitAutofillEvaluator.submissionCall(.account(document: "nonceA123", account: "synthetic@example.invalid"))
        XCTAssertEqual(Set(call.arguments.keys), ["documentNonce", "account"])
        XCTAssertEqual(call.arguments["account"] as? String, "synthetic@example.invalid")
        XCTAssertTrue(call.function.contains("stage:'account'"))
        XCTAssertFalse(call.function.contains("password"), "A password key, even null or undefined, must never enter account selection")
    }

    func testAccountSelectionAndSameDocumentMatchedPasswordSubmitExactlyOnceWithIndependentACKs() async {
        let fixture = Fixture()
        let completed = expectation(description: "Account selection and password stop at MFA")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.account, match: true), state(.manual, reason: .chooser),
                                    state(.manual, reason: .attempted),
                                    state(.password, match: true), state(.manual, reason: .interference)]
        var observedAccountACK = false
        fixture.evaluator.onInspection = {
            if fixture.evaluator.inspections == 2 {
                observedAccountACK = true
                XCTAssertEqual(fixture.ledger.accountSelectedDocument, "nonceA123")
                XCTAssertNil(fixture.ledger.usernameSubmittedDocument, "Account selection must not manufacture a username ACK")
            }
        }
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(observedAccountACK)
        XCTAssertEqual(fixture.evaluator.submissions.count, 2)
        guard case let .account(document, account) = fixture.evaluator.submissions[0] else { return XCTFail("First call must only select the saved account") }
        XCTAssertEqual(document, "nonceA123")
        XCTAssertEqual(account, "synthetic@example.invalid")
        guard case let .password(passwordDocument, passwordAccount, password) = fixture.evaluator.submissions[1] else { return XCTFail("The next call must use a separately verified password stage") }
        XCTAssertEqual(passwordDocument, document)
        XCTAssertEqual(passwordAccount, account)
        XCTAssertEqual(password, "synthetic-password")
        XCTAssertTrue(fixture.ledger.accountAttempted)
        XCTAssertFalse(fixture.ledger.usernameAttempted)
        XCTAssertTrue(fixture.ledger.passwordAttempted)
    }

    func testAccountLedgerRequiresExactMatchCurrentACKAndAllowsEachStageAtMostOnce() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        XCTAssertFalse(ledger.claim(state(.account, match: false), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.claim(state(.account, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.account, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        ledger.recordAccountSelection(document: "nonceB456", presentation: 1, credentialRevision: 1)
        ledger.recordAccountSelection(document: "nonceA123", presentation: 1, credentialRevision: 2)
        XCTAssertNil(ledger.accountSelectedDocument)
        XCTAssertFalse(ledger.claim(state(.password, match: true), presentation: 1, credentialRevision: 1))
        ledger.recordAccountSelection(document: "nonceA123", presentation: 1, credentialRevision: 1)
        XCTAssertNil(ledger.usernameSubmittedDocument)
        XCTAssertFalse(ledger.claim(state(.password, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.password, match: false), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.claim(state(.password, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.password, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.username), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.username, document: "nonceB456"), presentation: 1, credentialRevision: 1))
    }

    func testEmptyChooserAfterSelectionWaitsOnlyFinitelyAndNeverSelectsTwice() async {
        let fixture = Fixture()
        let completed = expectation(description: "Chooser settling expires")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.account, match: true)]
        fixture.evaluator.fallbackState = state(.manual, reason: .chooser)
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        XCTAssertFalse(fixture.ledger.passwordAttempted)
        XCTAssertLessThanOrEqual(fixture.evaluator.inspections, 10)
        let unmatched = Fixture()
        unmatched.evaluator.states = [state(.manual, reason: .chooser)]
        unmatched.pipeline.start(source: "synthetic source")
        XCTAssertTrue(unmatched.evaluator.submissions.isEmpty)
        XCTAssertTrue(unmatched.waits.isEmpty)
        XCTAssertEqual(unmatched.manualCount, 1)
    }

    func testAccountSelectionFromAnOlderDocumentCannotAuthorizeTheNextPasswordDocument() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        XCTAssertTrue(ledger.claim(state(.account, match: true), presentation: 1, credentialRevision: 1))
        ledger.recordAccountSelection(document: "nonceA123", presentation: 1, credentialRevision: 1)
        let fixture = Fixture(ledger: ledger, nonce: "nonceB456")
        fixture.evaluator.states = [state(.password, document: "nonceB456", match: true)]
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.manualCount, 1)
    }

    func testAccountChoiceMustPrecedeAnyUsernameOrPasswordAttempt() {
        for reachesPassword in [false, true] {
            let ledger = QMplusAutofillLedger()
            ledger.begin(presentation: 1, credentialRevision: 1)
            XCTAssertTrue(ledger.claim(state(.username), presentation: 1, credentialRevision: 1))
            if reachesPassword {
                ledger.recordUsernameSubmission(document: "nonceA123", presentation: 1, credentialRevision: 1)
                XCTAssertTrue(ledger.claim(state(.password, match: true), presentation: 1, credentialRevision: 1))
            }
            XCTAssertFalse(ledger.accountAttempted)
            XCTAssertFalse(ledger.claim(state(.account, match: true), presentation: 1, credentialRevision: 1))
        }
        let first = QMplusAutofillLedger()
        first.begin(presentation: 1, credentialRevision: 1)
        XCTAssertTrue(first.claim(state(.account, match: true), presentation: 1, credentialRevision: 1))
        first.recordAccountSelection(document: "nonceA123", presentation: 1, credentialRevision: 1)
        XCTAssertTrue(first.claim(state(.username), presentation: 1, credentialRevision: 1))
        first.recordUsernameSubmission(document: "nonceA123", presentation: 1, credentialRevision: 1)
        XCTAssertTrue(first.claim(state(.password, match: true), presentation: 1, credentialRevision: 1))
    }

    func testAccountSelectionRequiresSavedCredentialsAndExactAccountMatch() {
        let absent = Fixture()
        absent.credentialsAvailable = false
        absent.evaluator.states = [state(.account, match: true)]
        absent.pipeline.start(source: "synthetic source")
        XCTAssertTrue(absent.evaluator.submissions.isEmpty)
        XCTAssertEqual(absent.manualCount, 1)
        let mismatch = Fixture()
        mismatch.evaluator.states = [state(.account, match: false)]
        mismatch.pipeline.start(source: "synthetic source")
        XCTAssertTrue(mismatch.evaluator.submissions.isEmpty)
        XCTAssertEqual(mismatch.manualCount, 1)
    }

    func testWrongAccountACKNeverCreatesAUsernameACKOrRetriesTheAccountChoice() {
        let fixture = Fixture()
        fixture.evaluator.states = [state(.account, match: true)]
        fixture.evaluator.submissionResult = .usernameSubmitted
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        XCTAssertTrue(fixture.ledger.accountAttempted)
        XCTAssertNil(fixture.ledger.accountSelectedDocument)
        XCTAssertNil(fixture.ledger.usernameSubmittedDocument)
        XCTAssertFalse(fixture.ledger.passwordAttempted)
        XCTAssertEqual(fixture.manualCount, 1)
        let next = Fixture(ledger: fixture.ledger, nonce: "nonceB456")
        next.evaluator.states = [state(.account, document: "nonceB456", match: true)]
        next.pipeline.start(source: "synthetic source")
        XCTAssertTrue(next.evaluator.submissions.isEmpty)
    }

    func testLateAccountACKAfterOwnerRevisionOrCancellationCannotAuthorizePassword() {
        for invalidation in 0..<4 {
            let fixture = Fixture()
            fixture.evaluator.holdsSubmission = true
            fixture.evaluator.states = [state(.account, match: true)]
            fixture.pipeline.start(source: "synthetic source")
            let readsBeforeInvalidation = fixture.credentialReads
            switch invalidation {
            case 0: fixture.current = false
            case 1: fixture.ledger.begin(presentation: 1, credentialRevision: 2)
            case 2: fixture.pipeline.cancel()
            default: fixture.ledger.stop()
            }
            fixture.evaluator.finishSubmission(.accountSelected)
            XCTAssertEqual(fixture.credentialReads, readsBeforeInvalidation)
            XCTAssertNil(fixture.ledger.accountSelectedDocument)
            XCTAssertNil(fixture.ledger.usernameSubmittedDocument)
            XCTAssertFalse(fixture.ledger.passwordAttempted)
            XCTAssertEqual(fixture.manualCount, 0)
            XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        }
    }

    func testDuplicateAccountACKIsIgnoredWithoutAnotherClickOrWait() {
        let fixture = Fixture()
        fixture.evaluator.holdsSubmission = true
        fixture.evaluator.states = [state(.account, match: true)]
        fixture.pipeline.start(source: "synthetic source")
        fixture.evaluator.finishSubmission(.accountSelected)
        fixture.evaluator.replaySubmission(.accountSelected)
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        XCTAssertEqual(fixture.evaluator.inspections, 1, "A duplicate completion must not schedule another DOM inspection")
        XCTAssertEqual(fixture.progressCount, 1, "The repeated ACK must not report progress or schedule another wait")
        XCTAssertEqual(fixture.ledger.accountSelectedDocument, "nonceA123")
        XCTAssertNil(fixture.ledger.usernameSubmittedDocument)
        fixture.pipeline.cancel()
        fixture.ledger.stop()
    }

    func testAccountHintRequiredWaitIsFiniteAndNeverSelectsOrSendsPassword() async {
        let fixture = Fixture()
        let completed = expectation(description: "Missing account hints reach their finite limit")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.fallbackState = state(.account, reason: .accountHintRequired)
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.waits.count, 8)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertFalse(fixture.ledger.accountAttempted)
    }

    func testPasswordWithoutNativeUsernameSubmissionOrAccountMatchIsNeverSent() {
        for match in [false, true] {
            let fixture = Fixture()
            fixture.evaluator.states = [state(.password, match: match)]
            fixture.pipeline.start(source: "synthetic source")
            XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
            XCTAssertEqual(fixture.manualCount, 1)
        }
    }

    func testUsernameFromAnOlderDocumentCannotAuthorizeANewPasswordDocument() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        XCTAssertTrue(ledger.claim(state(.username), presentation: 1, credentialRevision: 1))
        ledger.recordUsernameSubmission(document: "nonceA123", presentation: 1, credentialRevision: 1)
        let fixture = Fixture(ledger: ledger, nonce: "nonceB456")
        fixture.evaluator.states = [state(.password, document: "nonceB456", match: true)]
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.manualCount, 1)
    }

    func testFailedUsernameAttemptNeverRetriesOnThisPresentation() {
        let fixture = Fixture()
        fixture.evaluator.states = [state(.username)]
        fixture.evaluator.submissionResult = .manual
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        XCTAssertEqual(fixture.manualCount, 1)
        let next = Fixture(ledger: fixture.ledger, nonce: "nonceB456")
        next.evaluator.states = [state(.username, document: "nonceB456")]
        next.pipeline.start(source: "synthetic source")
        XCTAssertTrue(next.evaluator.submissions.isEmpty)
    }

    func testLoadingWaitIsFiniteAndNeverClicksOrSendsPassword() async {
        let fixture = Fixture()
        let completed = expectation(description: "Loading inspection reaches its finite limit")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.fallbackState = state(.loading, reason: .loading)
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.waits.count, 8)
        XCTAssertEqual(fixture.waits.first, .milliseconds(250))
        XCTAssertTrue(fixture.waits.dropFirst().allSatisfy { $0 == .milliseconds(500) })
        XCTAssertEqual(fixture.evaluator.inspections, 9)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
    }

    func testCancelBeforeLateInspectionPreventsSubmissionAndDoesNotRevealOldWindow() {
        let fixture = Fixture()
        fixture.evaluator.holdsInspection = true
        fixture.pipeline.start(source: "synthetic source")
        fixture.pipeline.cancel()
        fixture.ledger.stop()
        fixture.evaluator.finishInspection(state(.username))
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.manualCount, 0)
    }

    func testInactiveVisibleStoreRejectsLateInstallationWithoutReadingCredentialsOrClosingMFAOwner() throws {
        let suite = "QMplusInactiveInstallTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        let fixture = Fixture()
        fixture.ownerIsCurrent = { store.hasActiveAutofillLedger }
        fixture.evaluator.holdsInstallation = true
        fixture.pipeline.start(source: "synthetic source")
        store.stopAutomaticLoginForInactiveScene()
        fixture.evaluator.finishInstallation(.installed)
        XCTAssertEqual(fixture.credentialReads, 0)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.manualCount, 0, "A late callback cannot reveal or focus the inactive page")
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertTrue(store.isShowingConnection, "The user's visible MFA owner must remain open")
        XCTAssertFalse(store.hasActiveAutofillLedger)
        XCTAssertNil(store.webView, "Synthetic tests must not open WebKit")
        store.endPresentation()
    }

    func testInactiveVisibleStoreRejectsLatePasswordInspectionAfterUsernameWasSubmitted() async throws {
        let suite = "QMplusInactivePasswordTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QMplusStore(defaults: defaults, allowsCredentialStorage: false)
        XCTAssertTrue(store.beginConnectionOwner(quiet: false))
        let fixture = Fixture()
        fixture.ownerIsCurrent = { store.hasActiveAutofillLedger }
        let held = expectation(description: "Same-document password inspection is held")
        fixture.evaluator.onInspection = { if fixture.evaluator.inspections == 2 { held.fulfill() } }
        fixture.evaluator.states = [state(.username)]
        fixture.pipeline.start(source: "synthetic source")
        fixture.evaluator.holdsInspection = true
        await fulfillment(of: [held], timeout: 2)
        let readsBeforeInactive = fixture.credentialReads
        store.stopAutomaticLoginForInactiveScene()
        fixture.evaluator.finishInspection(state(.password, match: true))
        XCTAssertEqual(fixture.credentialReads, readsBeforeInactive)
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        guard case .username = fixture.evaluator.submissions[0] else { return XCTFail("No password may be sent after inactivity") }
        XCTAssertEqual(fixture.manualCount, 0)
        XCTAssertTrue(store.isShowingConnection)
        XCTAssertTrue(store.hasActiveConnection)
        XCTAssertFalse(store.hasActiveAutofillLedger)
        store.endPresentation()
    }

    func testUnavailableViewportReadsNoCredentialAndLossDuringCallbackBecomesManual() {
        let initial = Fixture()
        initial.viewportReady = false
        initial.pipeline.start(source: "synthetic source")
        XCTAssertEqual(initial.credentialReads, 0)
        XCTAssertTrue(initial.evaluator.submissions.isEmpty)
        XCTAssertEqual(initial.manualCount, 1)
        let moved = Fixture()
        moved.evaluator.holdsInspection = true
        moved.pipeline.start(source: "synthetic source")
        moved.viewportReady = false
        moved.evaluator.finishInspection(state(.username))
        XCTAssertTrue(moved.evaluator.submissions.isEmpty)
        XCTAssertEqual(moved.manualCount, 1)
    }

    func testManualStatesAndMalformedOrMismatchedDocumentNeverSubmit() async {
        for reason in [QMplusAuthReason.chooser, .form, .absent, .interference, .mismatch, .priorUsername, .untrusted] {
            let fixture = Fixture()
            fixture.evaluator.states = [state(.manual, reason: reason)]
            let completed = expectation(description: "Manual state \(reason.rawValue) stops without submitting")
            fixture.onManual = { completed.fulfill() }
            if reason == .form || reason == .absent { fixture.evaluator.fallbackState = state(.manual, reason: reason) }
            fixture.pipeline.start(source: "synthetic source")
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
            XCTAssertEqual(fixture.manualCount, 1)
            if reason == .form || reason == .absent { XCTAssertEqual(fixture.waits.count, 8) }
        }
        let stale = Fixture()
        stale.evaluator.states = [state(.username, document: "nonceB456")]
        stale.pipeline.start(source: "synthetic source")
        XCTAssertTrue(stale.evaluator.submissions.isEmpty)
    }

    func testFixedInspectionDecoderRejectsExtraFieldsUnknownCodesAndNonBooleanAccountMatch() {
        var object: [String: Any] = ["v": 1, "stage": "username", "document": "nonceA123", "accountMatch": false, "reason": "READY"]
        XCTAssertNotNil(QMplusAuthInspection.decode(object))
        object["account"] = "synthetic@example.invalid"
        XCTAssertNil(QMplusAuthInspection.decode(object))
        object.removeValue(forKey: "account")
        object["accountMatch"] = 1
        XCTAssertNil(QMplusAuthInspection.decode(object))
        object["accountMatch"] = false; object["v"] = 1.5
        XCTAssertNil(QMplusAuthInspection.decode(object))
        object["v"] = 1; object["reason"] = "UNKNOWN"
        XCTAssertNil(QMplusAuthInspection.decode(object))
    }

    func testFixedInspectionDecoderAcceptsAccountStageAndHintRequiredWithoutExtraIdentityFields() {
        var object: [String: Any] = ["v": 1, "stage": "account", "document": "nonceA123", "accountMatch": true, "reason": "READY"]
        XCTAssertEqual(QMplusAuthInspection.decode(object)?.stage, .account)
        object["reason"] = "ACCOUNT_HINT_REQUIRED"
        object["accountMatch"] = false
        XCTAssertEqual(QMplusAuthInspection.decode(object)?.reason, .accountHintRequired)
        object["account"] = "synthetic@example.invalid"
        XCTAssertNil(QMplusAuthInspection.decode(object), "Only the fixed inspection projection may leave the page")
    }

    func testNativeTrustPolicyAndSSOEntryStayExactAndLedgerLoadsSSOOnlyOnce() {
        let prefix = "https://login.microsoftonline.com/\(QMplusAutofillPolicy.tenant)"
        XCTAssertTrue(QMplusAutofillPolicy.isTrustedMicrosoftDocument(URL(string: prefix + "/saml2?synthetic=1")))
        XCTAssertTrue(QMplusAutofillPolicy.isTrustedMicrosoftDocument(URL(string: prefix + "/login")))
        for value in [prefix + "/saml2/", prefix + "/%73aml2", prefix + "/consent",
                      "https://login.microsoftonline.com/other/login", "https://login.microsoftonline.com.evil.invalid/\(QMplusAutofillPolicy.tenant)/login",
                      "http://login.microsoftonline.com/\(QMplusAutofillPolicy.tenant)/login"] {
            XCTAssertFalse(QMplusAutofillPolicy.isTrustedMicrosoftDocument(URL(string: value)), value)
        }
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/login/index.php")))
        XCTAssertFalse(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/my/")))
        XCTAssertNil(QMplusAutofillPolicy.ssoURL.query)
        XCTAssertEqual(QMplusAutofillPolicy.ssoURL.absoluteString, "https://qmplus.qmul.ac.uk/auth/saml2/login.php")
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 2)
        XCTAssertTrue(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        XCTAssertFalse(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        ledger.stop()
        XCTAssertFalse(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        ledger.begin(presentation: 2, credentialRevision: 2)
        XCTAssertTrue(ledger.claimSSO(presentation: 2, credentialRevision: 2))
    }

    func testVerifiedQMplusGuestLandingCanUseFixedSSOEntry() {
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/?redirect=0")))
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/login/index.php")))
        XCTAssertEqual(QMplusAutofillPolicy.ssoURL.absoluteString, "https://qmplus.qmul.ac.uk/auth/saml2/login.php")
        XCTAssertNil(QMplusAutofillPolicy.ssoURL.query)
    }

    func testOtherQMplusLandingQueriesAndForeignHostsRemainManual() {
        for value in ["https://qmplus.qmul.ac.uk/", "https://qmplus.qmul.ac.uk/?redirect=1",
                      "https://qmplus.qmul.ac.uk/?redirect=0&other=1", "https://qmplus.qmul.ac.uk/?redirect=%30",
                      "https://qmplus.qmul.ac.uk/?redirect=0#other", "https://qmplus.qmul.ac.uk.evil.invalid/?redirect=0",
                      "https://qmplus.qmul.ac.uk/login/index.php?other=1"] {
            XCTAssertFalse(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: value)), value)
        }
    }

    private func state(_ stage: QMplusAuthStage, document: String = "nonceA123", match: Bool = false,
                       reason: QMplusAuthReason = .ready) -> QMplusAuthInspection {
        .init(stage: stage, document: document, accountMatch: match, reason: reason)
    }
    @MainActor private final class Fixture {
        let evaluator = FakeEvaluator()
        let ledger: QMplusAutofillLedger
        var current = true
        var credentialsAvailable = true
        var ownerIsCurrent: @MainActor () -> Bool = { true }
        var viewportReady = true
        var credentialReads = 0, manualCount = 0, progressCount = 0
        var onManual: (@MainActor () -> Void)?
        var waits: [Duration] = []
        let nonce: String
        let saved = QMplusSavedCredentials(marker: .init(recordID: UUID(), authorizationNonce: UUID()),
            account: "synthetic@example.invalid", password: "synthetic-password")
        private var pipelineCache: QMplusAutofillPipeline?
        var pipeline: QMplusAutofillPipeline {
            if let pipelineCache { return pipelineCache }
            let pipeline = QMplusAutofillPipeline(evaluator: evaluator, ledger: ledger, presentation: 1,
            credentialRevision: 1, nonce: nonce, isCurrent: { [weak self] in
                guard let self else { return false }
                return self.current && self.ownerIsCurrent()
            },
            viewportReady: { [weak self] in self?.viewportReady == true },
            credentials: { [weak self] in
                self?.credentialReads += 1
                guard let self, self.credentialsAvailable else { return nil }
                return self.saved
            }, manual: { [weak self] in self?.manualCount += 1; self?.onManual?() }, progress: { [weak self] _ in self?.progressCount += 1 }, wait: { [weak self] duration in
                self?.waits.append(duration); await Task.yield()
            })
            pipelineCache = pipeline
            return pipeline
        }
        init(ledger: QMplusAutofillLedger? = nil, nonce: String = "nonceA123") {
            self.ledger = ledger ?? QMplusAutofillLedger(); self.nonce = nonce
            if ledger == nil { self.ledger.begin(presentation: 1, credentialRevision: 1) }
        }
    }
    @MainActor private final class FakeEvaluator: QMplusAutofillEvaluating {
        var installResult = QMplusAuthInstallResult.installed
        var submissionResult: QMplusAuthSubmissionResult?
        var states: [QMplusAuthInspection] = []
        var fallbackState: QMplusAuthInspection?
        var inspections = 0
        var onInspection: (@MainActor () -> Void)?
        var submissions: [QMplusAuthSubmission] = []
        var holdsInstallation = false, holdsInspection = false, holdsSubmission = false
        private var installCallback: (@MainActor @Sendable (QMplusAuthInstallResult) -> Void)?
        private var inspectCallback: (@MainActor @Sendable (QMplusAuthInspection?) -> Void)?
        private var submitCallback: (@MainActor @Sendable (QMplusAuthSubmissionResult?) -> Void)?
        private var lastSubmitCallback: (@MainActor @Sendable (QMplusAuthSubmissionResult?) -> Void)?
        func install(_: String, completion: @escaping @MainActor @Sendable (QMplusAuthInstallResult) -> Void) {
            if holdsInstallation { installCallback = completion } else { completion(installResult) }
        }
        func inspect(nonce _: String, accountHint _: String, completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
            inspections += 1
            onInspection?()
            if holdsInspection { inspectCallback = completion }
            else { completion(states.isEmpty ? fallbackState : states.removeFirst()) }
        }
        func submit(_ submission: QMplusAuthSubmission, completion: @escaping @MainActor @Sendable (QMplusAuthSubmissionResult?) -> Void) {
            submissions.append(submission)
            lastSubmitCallback = completion
            if holdsSubmission { submitCallback = completion }
            else if let submissionResult { completion(submissionResult) }
            else {
                switch submission {
                case .account: completion(.accountSelected)
                case .username: completion(.usernameSubmitted)
                case .password: completion(.passwordSubmitted)
                }
            }
        }
        func finishInstallation(_ result: QMplusAuthInstallResult) { installCallback?(result); installCallback = nil }
        func finishInspection(_ result: QMplusAuthInspection) { inspectCallback?(result); inspectCallback = nil }
        func finishSubmission(_ result: QMplusAuthSubmissionResult) { submitCallback?(result); submitCallback = nil }
        func replaySubmission(_ result: QMplusAuthSubmissionResult) { lastSubmitCallback?(result) }
    }
}
