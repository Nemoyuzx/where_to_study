import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

// Synthetic specification source only. Do not execute while local tests and GUI are prohibited.
@MainActor
final class QMplusAutofillPipelineTests: XCTestCase {
    func testSlowFirstPickerCompletesInBackgroundWithoutManualContinuation() async {
        let fixture = Fixture()
        fixture.evaluator.holdsSubmission = true
        fixture.evaluator.states = Array(repeating: state(.loading, reason: .loading), count: 16)
            + [state(.account, match: true), state(.manual, match: true, reason: .attempted), state(.password, match: true)]
        let selected = expectation(description: "The slow picker becomes ready after the old four-second limit")
        let password = expectation(description: "The remaining password step also runs without manual continuation")
        fixture.evaluator.onInspection = {
            if fixture.evaluator.inspections == 17 { selected.fulfill() }
            if fixture.evaluator.inspections == 19 { password.fulfill() }
        }
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [selected], timeout: 2)
        XCTAssertEqual(fixture.manualCount, 0)
        XCTAssertEqual(fixture.challengeCount, 0)
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        XCTAssertNil(fixture.ledger.accountSelectedDocument)
        fixture.evaluator.finishSubmission(.accountSelected)
        await fulfillment(of: [password], timeout: 2)
        XCTAssertEqual(fixture.manualCount, 0)
        XCTAssertEqual(fixture.challengeCount, 0)
        XCTAssertEqual(fixture.evaluator.submissions.count, 2)
        guard case .account = fixture.evaluator.submissions[0], case .password = fixture.evaluator.submissions[1] else {
            return XCTFail("Only the matched account and one subsequent password submission are permitted")
        }
        XCTAssertEqual(fixture.ledger.accountSelectedDocument, "nonceA123")
        fixture.pipeline.cancel()
        fixture.ledger.stop()
    }

    func testCredentialRevalidationFailureBeforeSubmitDoesNotConsumeAnAccountClaim() {
        let fixture = Fixture()
        fixture.evaluator.states = [state(.account, match: true)]
        fixture.evaluator.onInspection = { fixture.credentialsAvailable = false }
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertEqual(fixture.manualCount, 1)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertFalse(fixture.ledger.accountAttempted)
        XCTAssertNil(fixture.ledger.accountSelectedDocument)
    }

    func testResumptionRequiresANewRealCommitAndAnOfficialPausedSource() {
        let previous = NSObject(), next = NSObject(), unrelated = NSObject()
        XCTAssertTrue(QMplusAutofillPolicy.isNewCommittedNavigation(next, active: next, paused: previous))
        XCTAssertFalse(QMplusAutofillPolicy.isNewCommittedNavigation(previous, active: previous, paused: previous))
        XCTAssertFalse(QMplusAutofillPolicy.isNewCommittedNavigation(next, active: unrelated, paused: previous))
        XCTAssertFalse(QMplusAutofillPolicy.isNewCommittedNavigation(nil, active: next, paused: previous))
        XCTAssertFalse(QMplusAutofillPolicy.isNewCommittedNavigation(next, active: next, paused: nil))
        for value in ["https://qmplus.qmul.ac.uk/login/index.php", "https://login.microsoftonline.com/\(QMplusAutofillPolicy.tenant)/saml2",
                      "https://device.login.microsoftonline.com/"] {
            XCTAssertTrue(QMplusAutofillPolicy.isResumableOfficialDocument(URL(string: value)))
        }
        for value in ["http://qmplus.qmul.ac.uk/", "https://qmplus.qmul.ac.uk.evil.invalid/", "https://example.invalid/",
                      "https://login.microsoftonline.com:444/", "https://user@login.microsoftonline.com/"] {
            XCTAssertFalse(QMplusAutofillPolicy.isResumableOfficialDocument(URL(string: value)))
        }
    }

    func testSuspendedOwnerCanResumeOnceAndStillAutoSelectAnUnclaimedExactAccount() async {
        let first = Fixture()
        let paused = expectation(description: "The known picker reaches its finite layout wait")
        first.onManual = { paused.fulfill() }
        first.evaluator.fallbackState = state(.manual, reason: .chooser)
        first.pipeline.start(source: "synthetic source")
        await fulfillment(of: [paused], timeout: 2)
        XCTAssertEqual(first.manualCount, 1)
        XCTAssertFalse(first.ledger.accepts(presentation: 1, credentialRevision: 1))
        XCTAssertFalse(first.ledger.resume(presentation: 2, credentialRevision: 1))
        XCTAssertFalse(first.ledger.resume(presentation: 1, credentialRevision: 2))
        XCTAssertTrue(first.ledger.resume(presentation: 1, credentialRevision: 1))
        let next = Fixture(ledger: first.ledger, nonce: "nonceB456")
        let selected = expectation(description: "The next verified document auto-selects the saved account")
        next.evaluator.states = [state(.account, document: "nonceB456", match: true)]
        next.evaluator.holdsSubmission = true
        next.evaluator.onInspection = { selected.fulfill() }
        next.pipeline.start(source: "synthetic source")
        await fulfillment(of: [selected], timeout: 2)
        XCTAssertEqual(next.evaluator.submissions.count, 1)
        guard case .account = next.evaluator.submissions[0] else { return XCTFail("Only the exact account selection is allowed") }
        XCTAssertNil(first.ledger.accountSelectedDocument)
        next.evaluator.finishSubmission(.accountSelected)
        XCTAssertEqual(first.ledger.accountSelectedDocument, "nonceB456")
        next.pipeline.cancel()
        first.ledger.suspend()
        XCTAssertFalse(first.ledger.resume(presentation: 1, credentialRevision: 1), "Repeated pauses cannot refresh the connection budget")
    }

    func testSuspensionPreservesRealACKAndCannotReplayAlreadyClaimedSteps() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        XCTAssertTrue(ledger.claim(state(.account, match: true), presentation: 1, credentialRevision: 1))
        ledger.recordAccountSelection(document: "nonceA123", presentation: 1, credentialRevision: 1)
        ledger.suspend()
        XCTAssertFalse(ledger.claim(state(.password, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.resume(presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.hasIdentityAcknowledgement(for: "nonceB456"))
        XCTAssertFalse(ledger.claim(state(.account, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.claim(state(.password, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        ledger.recordPasswordSubmission(document: "nonceB456", presentation: 1, credentialRevision: 1)
        ledger.suspend()
        XCTAssertFalse(ledger.resume(presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.password, document: "nonceC789", match: true), presentation: 1, credentialRevision: 1))
    }

    func testHardStopRevokesSuspendedOwnerAndCannotBeResumed() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        ledger.suspend()
        ledger.stop()
        XCTAssertFalse(ledger.resume(presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.accepts(presentation: 1, credentialRevision: 1))
        ledger.begin(presentation: 2, credentialRevision: 2)
        XCTAssertFalse(ledger.resume(presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.accepts(presentation: 2, credentialRevision: 2))
    }

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
        guard let last = fixture.evaluator.submissions.last, case let .password(passwordDocument, passwordAccount, password, _) = last else { return XCTFail("Second request must be the verified matching password stage") }
        XCTAssertEqual(passwordDocument, document)
        XCTAssertEqual(passwordAccount, account)
        XCTAssertEqual(password, "synthetic-password")
        XCTAssertEqual(fixture.waits, [.milliseconds(250), .milliseconds(500), .milliseconds(250), .milliseconds(500)])
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
        let completed = expectation(description: "Account selection and password eventually stop at an unknown screen")
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
        guard case let .password(passwordDocument, passwordAccount, password, _) = fixture.evaluator.submissions[1] else { return XCTFail("The next call must use a separately verified password stage") }
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
        XCTAssertFalse(ledger.claim(state(.password, match: false), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.hasIdentityAcknowledgement(for: "nonceB456"))
        XCTAssertTrue(ledger.claim(state(.password, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
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
        XCTAssertLessThanOrEqual(fixture.evaluator.inspections, QMplusAutofillPolicy.maximumPageWaits + 2)
        XCTAssertEqual(fixture.identityMismatchCount, 0)
        let unmatched = Fixture()
        let expired = expectation(description: "An initially unknown picker reaches its bounded read-only retry limit")
        unmatched.onManual = { expired.fulfill() }
        unmatched.evaluator.fallbackState = state(.manual, reason: .chooser)
        unmatched.pipeline.start(source: "synthetic source")
        XCTAssertEqual(unmatched.manualCount, 0, "The first picker inspection must not stop before its tiles can mount")
        XCTAssertFalse(unmatched.ledger.hasIdentityAcknowledgement(for: "nonceA123"))
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertTrue(unmatched.evaluator.submissions.isEmpty)
        XCTAssertEqual(unmatched.waits.count, QMplusAutofillPolicy.maximumPageWaits)
        XCTAssertEqual(unmatched.evaluator.inspections, QMplusAutofillPolicy.maximumPageWaits + 1)
        XCTAssertTrue(unmatched.evaluator.identityAcknowledgements.allSatisfy { !$0 })
        XCTAssertFalse(unmatched.ledger.accountAttempted)
        XCTAssertFalse(unmatched.ledger.usernameAttempted)
        XCTAssertFalse(unmatched.ledger.passwordAttempted)
        XCTAssertEqual(unmatched.manualCount, 1)
        XCTAssertEqual(unmatched.identityMismatchCount, 0, "An unknown picker is not proof that the cached business identity is wrong")
    }

    func testInitialPickerRechecksUntilReadyWithoutCreatingIdentityBeforeTheRealAccountACK() async {
        let fixture = Fixture()
        let ready = expectation(description: "A delayed exact account tile becomes ready")
        fixture.evaluator.holdsSubmission = true
        fixture.evaluator.states = [state(.manual, reason: .chooser), state(.manual, reason: .chooser), state(.account, match: true)]
        fixture.evaluator.onInspection = {
            XCTAssertNil(fixture.ledger.accountSelectedDocument)
            XCTAssertNil(fixture.ledger.usernameSubmittedDocument)
            XCTAssertFalse(fixture.ledger.hasIdentityAcknowledgement(for: "nonceA123"))
            if fixture.evaluator.inspections == 3 { ready.fulfill() }
        }
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(fixture.waits, [.milliseconds(250), .milliseconds(500)])
        XCTAssertEqual(fixture.evaluator.identityAcknowledgements, [false, false, false])
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        guard case .account = fixture.evaluator.submissions[0] else { return XCTFail("Only the matched account tile may be selected") }
        XCTAssertTrue(fixture.ledger.accountAttempted)
        XCTAssertNil(fixture.ledger.accountSelectedDocument, "A pending click result is not an identity acknowledgement")
        XCTAssertEqual(fixture.identityMismatchCount, 0)
        XCTAssertEqual(fixture.manualCount, 0)
        fixture.evaluator.finishSubmission(.accountSelected)
        XCTAssertEqual(fixture.ledger.accountSelectedDocument, "nonceA123")
        XCTAssertTrue(fixture.ledger.hasIdentityAcknowledgement(for: "nonceB456"))
        fixture.pipeline.cancel()
    }

    func testPickerWaitingOnlySignalsBusinessIdentityMismatchWhenThePageExplicitlyConfirmsIt() async {
        let fixture = Fixture()
        let completed = expectation(description: "An explicit account mismatch terminates picker observation")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.manual, reason: .chooser), state(.manual, reason: .mismatch)]
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertEqual(fixture.identityMismatchCount, 0)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.identityMismatchCount, 1)
        XCTAssertEqual(fixture.manualCount, 1)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.waits, [.milliseconds(250)])
    }

    func testAccountSelectionACKFromTheSameOwnerAuthorizesTheNextMatchedPasswordDocument() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        XCTAssertTrue(ledger.claim(state(.account, match: true), presentation: 1, credentialRevision: 1))
        ledger.recordAccountSelection(document: "nonceA123", presentation: 1, credentialRevision: 1)
        let fixture = Fixture(ledger: ledger, nonce: "nonceB456")
        fixture.evaluator.states = [state(.password, document: "nonceB456", match: true)]
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        guard case let .password(document, _, _, identityAcknowledged) = fixture.evaluator.submissions[0] else {
            return XCTFail("A real account-selection ACK should survive navigation")
        }
        XCTAssertEqual(document, "nonceB456")
        XCTAssertTrue(identityAcknowledged)
        XCTAssertEqual(fixture.evaluator.identityAcknowledgements, [true])
        XCTAssertEqual(fixture.manualCount, 0)
        XCTAssertFalse(ledger.claim(state(.password, document: "nonceC789", match: true), presentation: 1, credentialRevision: 1))
        fixture.pipeline.cancel()
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

    func testLateAccountACKAfterOwnerOrCredentialRevisionRetirementCannotAuthorizePassword() {
        for invalidation in 0..<3 {
            let fixture = Fixture()
            fixture.evaluator.holdsSubmission = true
            fixture.evaluator.states = [state(.account, match: true)]
            fixture.pipeline.start(source: "synthetic source")
            let readsBeforeInvalidation = fixture.credentialReads
            switch invalidation {
            case 0: fixture.ledger.begin(presentation: 2, credentialRevision: 1)
            case 1: fixture.ledger.begin(presentation: 1, credentialRevision: 2)
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

    func testLateAccountACKAfterDocumentRetirementPreservesIdentityWithoutResumingOldUIWork() {
        for retireDocument in [true, false] {
            let fixture = Fixture()
            fixture.evaluator.holdsSubmission = true
            fixture.evaluator.states = [state(.account, match: true)]
            fixture.pipeline.start(source: "synthetic source")
            let reads = fixture.credentialReads
            if retireDocument { fixture.current = false } else { fixture.pipeline.cancel() }
            fixture.evaluator.finishSubmission(.accountSelected)
            XCTAssertEqual(fixture.ledger.accountSelectedDocument, "nonceA123")
            XCTAssertTrue(fixture.ledger.hasIdentityAcknowledgement(for: "nonceB456"))
            XCTAssertEqual(fixture.credentialReads, reads)
            XCTAssertEqual(fixture.evaluator.submissions.count, 1)
            XCTAssertEqual(fixture.evaluator.inspections, 1)
            XCTAssertTrue(fixture.waits.isEmpty)
            XCTAssertEqual(fixture.manualCount, 0)
            XCTAssertEqual(fixture.progressCount, 0)
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
        XCTAssertEqual(fixture.waits.count, QMplusAutofillPolicy.maximumPageWaits)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertFalse(fixture.ledger.accountAttempted)
    }

    func testReadyPasswordWithoutNativeIdentityAcknowledgementOrAccountMatchIsNeverSent() {
        for match in [false, true] {
            let fixture = Fixture()
            fixture.evaluator.states = [state(.password, match: match)]
            fixture.pipeline.start(source: "synthetic source")
            XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
            XCTAssertEqual(fixture.manualCount, 1)
        }
    }

    func testUsernameACKFromTheSameOwnerAuthorizesANewMatchedPasswordDocument() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        XCTAssertTrue(ledger.claim(state(.username), presentation: 1, credentialRevision: 1))
        ledger.recordUsernameSubmission(document: "nonceA123", presentation: 1, credentialRevision: 1)
        let fixture = Fixture(ledger: ledger, nonce: "nonceB456")
        fixture.evaluator.states = [state(.password, document: "nonceB456", match: true)]
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        guard case let .password(document, _, _, identityAcknowledged) = fixture.evaluator.submissions[0] else {
            return XCTFail("A real username ACK should survive navigation")
        }
        XCTAssertEqual(document, "nonceB456")
        XCTAssertTrue(identityAcknowledged)
        XCTAssertEqual(fixture.evaluator.identityAcknowledgements, [true])
        XCTAssertEqual(fixture.manualCount, 0)
        fixture.pipeline.cancel()
    }

    func testCurrentPageIdentityRequiresFreshInspectionBeforePasswordAndDoesNotInventUsernameACK() async {
        let fixture = Fixture()
        let completed = expectation(description: "Fresh direct-password inspection completes before an unknown page")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.password, match: true, reason: .currentAccountVerified),
                                    state(.password, match: true), state(.manual, reason: .unsupported)]
        fixture.pipeline.start(source: "synthetic source")
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty, "The first account proof must be re-inspected before releasing a password")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.evaluator.identityAcknowledgements, [false, true, true])
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        guard case let .password(document, _, password, identityAcknowledged) = fixture.evaluator.submissions[0] else {
            return XCTFail("Only the newly verified password stage may receive the password")
        }
        XCTAssertEqual(document, "nonceA123")
        XCTAssertEqual(password, "synthetic-password")
        XCTAssertTrue(identityAcknowledged)
        XCTAssertFalse(fixture.ledger.accountAttempted)
        XCTAssertFalse(fixture.ledger.usernameAttempted)
    }

    func testCurrentPageIdentityStaysDocumentScopedUntilTheClaimedPasswordReturnsItsRealACK() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        let proof = state(.password, match: true, reason: .currentAccountVerified)
        XCTAssertFalse(ledger.recordVerifiedIdentity(proof, presentation: 2, credentialRevision: 1))
        XCTAssertFalse(ledger.recordVerifiedIdentity(proof, presentation: 1, credentialRevision: 2))
        XCTAssertFalse(ledger.recordVerifiedIdentity(state(.password, match: false, reason: .currentAccountVerified), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.recordVerifiedIdentity(state(.username, match: true, reason: .currentAccountVerified), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.recordVerifiedIdentity(proof, presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.hasIdentityAcknowledgement(for: "nonceA123"))
        XCTAssertFalse(ledger.hasIdentityAcknowledgement(for: "nonceB456"))
        XCTAssertNil(ledger.accountSelectedDocument)
        XCTAssertNil(ledger.usernameSubmittedDocument)
        XCTAssertFalse(ledger.claim(state(.password, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.claim(state(.password, match: true), presentation: 1, credentialRevision: 1))
        ledger.recordPasswordSubmission(document: "nonceB456", presentation: 1, credentialRevision: 1)
        ledger.recordPasswordSubmission(document: "nonceA123", presentation: 2, credentialRevision: 1)
        ledger.recordPasswordSubmission(document: "nonceA123", presentation: 1, credentialRevision: 2)
        XCTAssertFalse(ledger.hasIdentityAcknowledgement(for: "nonceB456"))
        ledger.recordPasswordSubmission(document: "nonceA123", presentation: 1, credentialRevision: 1)
        XCTAssertTrue(ledger.hasIdentityAcknowledgement(for: "nonceB456"))
        XCTAssertTrue(ledger.isAwaitingNavigation(from: "nonceA123"))
        XCTAssertFalse(ledger.isAwaitingNavigation(from: "nonceB456"))
        XCTAssertFalse(ledger.claim(state(.password, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.claim(state(.continuation, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        ledger.stop()
        XCTAssertFalse(ledger.hasIdentityAcknowledgement(for: "nonceB456"))
    }

    func testContinuationHasItsOwnOnceOnlyBudgetAndCannotReturnToCredentialsOrSSO() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 1)
        XCTAssertFalse(ledger.claim(state(.continuation, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.recordVerifiedIdentity(state(.continuation, match: true, reason: .currentAccountVerified),
            presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.hasIdentityAcknowledgement(for: "nonceB456"))
        XCTAssertFalse(ledger.claim(state(.continuation, match: false), presentation: 1, credentialRevision: 1))
        XCTAssertTrue(ledger.claim(state(.continuation, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.continuation, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.continuation, document: "nonceB456", match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.password, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.username), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claim(state(.account, match: true), presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.claimSSO(presentation: 1, credentialRevision: 1))
        XCTAssertFalse(ledger.canNavigateLoginEntry(presentation: 1, credentialRevision: 1))
        ledger.recordContinuationSubmission(document: "nonceB456", presentation: 1, credentialRevision: 1)
        XCTAssertFalse(ledger.isAwaitingNavigation(from: "nonceA123"))
        ledger.recordContinuationSubmission(document: "nonceA123", presentation: 1, credentialRevision: 1)
        XCTAssertTrue(ledger.isAwaitingNavigation(from: "nonceA123"))
        XCTAssertFalse(ledger.hasIdentityAcknowledgement(for: "nonceB456"), "A continuation ACK is not a password or username ACK")
    }

    func testContinuationBridgeNeverContainsAPasswordAndIncludesOnlyExplicitIdentityAcknowledgement() {
        let call = QMplusWebKitAutofillEvaluator.submissionCall(
            .continuation(document: "nonceA123", account: "synthetic@example.invalid", identityAcknowledged: true))
        XCTAssertEqual(Set(call.arguments.keys), ["documentNonce", "account", "identityAcknowledged"])
        XCTAssertEqual(call.arguments["identityAcknowledged"] as? Bool, true)
        XCTAssertTrue(call.function.contains("stage:'continue'"))
        XCTAssertFalse(call.function.contains("password"))
    }

    func testRepeatedChallengeIsReadOnlyAndCanContinueIntoAFreshlyVerifiedKMSIPage() async {
        let fixture = Fixture()
        let completed = expectation(description: "User challenge completion resumes the remaining continuation stage")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.challenge, reason: .mfaRequired), state(.challenge, reason: .mfaRequired),
                                    state(.continuation, match: true, reason: .currentAccountVerified),
                                    state(.continuation, match: true), state(.manual, reason: .unsupported)]
        fixture.evaluator.onInspection = {
            if fixture.evaluator.inspections <= 3 {
                XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
                XCTAssertFalse(fixture.ledger.passwordAttempted)
            }
        }
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.challengeCount, 1, "Repeated observations must not reopen the same challenge")
        XCTAssertEqual(Array(fixture.waits.prefix(2)), [.seconds(1), .seconds(1)])
        XCTAssertEqual(fixture.evaluator.identityAcknowledgements, [false, false, false, true, true])
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        guard case let .continuation(document, _, identityAcknowledged) = fixture.evaluator.submissions[0] else {
            return XCTFail("Completing MFA must not send or replay a password")
        }
        XCTAssertEqual(document, "nonceA123")
        XCTAssertTrue(identityAcknowledged)
        XCTAssertFalse(fixture.ledger.accountAttempted)
        XCTAssertFalse(fixture.ledger.usernameAttempted)
        XCTAssertFalse(fixture.ledger.passwordAttempted)
        XCTAssertTrue(fixture.ledger.continuationAttempted)
    }

    func testLoadingAndVisibleCaptchaAreObservedWithoutSavedCredentials() async {
        let fixture = Fixture()
        fixture.credentialsAvailable = false
        let completed = expectation(description: "Read-only CAPTCHA detection can outlive missing saved credentials")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.loading, reason: .loading), state(.challenge, reason: .captchaRequired),
                                    state(.challenge, reason: .captchaRequired), state(.manual, reason: .unsupported)]
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.challengeCount, 1)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertFalse(fixture.ledger.accountAttempted)
        XCTAssertFalse(fixture.ledger.passwordAttempted)
        XCTAssertEqual(fixture.waits, [.milliseconds(250), .seconds(1), .seconds(1)])
    }

    func testVerificationOnlyPipelineObservesMFAWithAnEmptyHintWithoutReadingSavedCredentials() async {
        let fixture = Fixture(verificationOnly: true)
        let completed = expectation(description: "Read-only verification observation reaches an unrecognized successor")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.loading, reason: .loading), state(.challenge, reason: .mfaRequired),
                                    state(.challenge, reason: .mfaRequired), state(.manual, reason: .unsupported)]
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.credentialReads, 0, "Even an available secure-store record must not be read for the verification route")
        XCTAssertEqual(fixture.evaluator.accountHints, ["", "", "", ""])
        XCTAssertEqual(fixture.challengeCount, 1)
        XCTAssertEqual(fixture.manualCount, 1)
        XCTAssertEqual(fixture.identityMismatchCount, 0)
        XCTAssertEqual(fixture.progressCount, 0)
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertFalse(fixture.ledger.accountAttempted)
        XCTAssertFalse(fixture.ledger.usernameAttempted)
        XCTAssertFalse(fixture.ledger.passwordAttempted)
        XCTAssertFalse(fixture.ledger.continuationAttempted)
        XCTAssertEqual(fixture.waits, [.milliseconds(250), .seconds(1), .seconds(1)])
    }

    func testVerificationOnlyLoadingHasABoundedReadOnlyBudgetWithoutCredentialsOrSubmissions() async {
        let fixture = Fixture(verificationOnly: true)
        let completed = expectation(description: "Verification title mounting reaches its finite native budget")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.fallbackState = state(.loading, reason: .loading)
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.waits.count, 36)
        XCTAssertEqual(fixture.evaluator.inspections, 37)
        XCTAssertEqual(fixture.waits.first, .milliseconds(250))
        XCTAssertTrue(fixture.waits.dropFirst().allSatisfy { $0 == .milliseconds(500) })
        XCTAssertEqual(fixture.credentialReads, 0)
        XCTAssertTrue(fixture.evaluator.accountHints.allSatisfy(\.isEmpty))
        XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
        XCTAssertEqual(fixture.challengeCount, 0)
        XCTAssertEqual(fixture.manualCount, 1)
    }

    func testVerificationOnlyPipelineRejectsAllCredentialAndContinuationReportsWithoutClaimingAStage() {
        let forbidden = [state(.account, match: true), state(.username), state(.password, match: true),
                         state(.continuation, match: true), state(.password, match: true, reason: .currentAccountVerified),
                         state(.continuation, match: true, reason: .currentAccountVerified),
                         state(.authenticated, reason: .authenticated), state(.challenge, reason: .ready),
                         state(.loading, reason: .ready), state(.manual, reason: .mismatch)]
        for report in forbidden {
            let fixture = Fixture(verificationOnly: true)
            fixture.evaluator.states = [report]
            fixture.pipeline.start(source: "synthetic source")
            XCTAssertEqual(fixture.credentialReads, 0, report.stage.rawValue)
            XCTAssertEqual(fixture.evaluator.accountHints, [""])
            XCTAssertTrue(fixture.evaluator.submissions.isEmpty, report.stage.rawValue)
            XCTAssertTrue(fixture.waits.isEmpty)
            XCTAssertEqual(fixture.manualCount, 1)
            XCTAssertEqual(fixture.challengeCount, 0)
            XCTAssertEqual(fixture.identityMismatchCount, 0, "A read-only verification document cannot invalidate the saved business identity")
            XCTAssertFalse(fixture.ledger.accountAttempted)
            XCTAssertFalse(fixture.ledger.usernameAttempted)
            XCTAssertFalse(fixture.ledger.passwordAttempted)
            XCTAssertFalse(fixture.ledger.continuationAttempted)
        }
    }

    func testSuccessfulPasswordACKWaitsFinitelyForTheOldSPADOMWithoutSubmittingTwice() async {
        let fixture = Fixture()
        let completed = expectation(description: "Post-submit old DOM has a bounded observation budget")
        fixture.onManual = { completed.fulfill() }
        fixture.evaluator.states = [state(.password, match: true, reason: .currentAccountVerified), state(.password, match: true)]
        fixture.evaluator.fallbackState = state(.manual, reason: .interference)
        fixture.pipeline.start(source: "synthetic source")
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(fixture.evaluator.submissions.count, 1)
        XCTAssertTrue(fixture.ledger.passwordAttempted)
        XCTAssertEqual(fixture.challengeCount, 0)
        XCTAssertEqual(fixture.manualCount, 1)
        XCTAssertEqual(fixture.waits.count, 37)
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
        XCTAssertEqual(fixture.waits.count, QMplusAutofillPolicy.maximumPageWaits)
        XCTAssertEqual(fixture.waits.first, .milliseconds(250))
        XCTAssertTrue(fixture.waits.dropFirst().allSatisfy { $0 == .milliseconds(500) })
        XCTAssertEqual(fixture.evaluator.inspections, QMplusAutofillPolicy.maximumPageWaits + 1)
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

    func testUnavailableViewportReadsNoCredentialAndLossDuringCallbackWaitsOnlyFinitely() async {
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
        let completed = expectation(description: "Viewport recovery has a finite read-only wait budget")
        moved.onManual = { completed.fulfill() }
        moved.evaluator.finishInspection(state(.username))
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(moved.evaluator.submissions.isEmpty)
        XCTAssertEqual(moved.manualCount, 1)
        XCTAssertEqual(moved.waits.count, QMplusAutofillPolicy.maximumViewportWaits)
        XCTAssertTrue(moved.waits.allSatisfy { $0 == .milliseconds(250) })
    }

    func testManualStatesAndMalformedOrMismatchedDocumentNeverSubmit() async {
        for reason in [QMplusAuthReason.chooser, .form, .absent, .interference, .mismatch, .priorUsername, .untrusted] {
            let fixture = Fixture()
            fixture.evaluator.states = [state(.manual, reason: reason)]
            let completed = expectation(description: "Manual state \(reason.rawValue) stops without submitting")
            fixture.onManual = { completed.fulfill() }
            if [.chooser, .form, .absent].contains(reason) { fixture.evaluator.fallbackState = state(.manual, reason: reason) }
            fixture.pipeline.start(source: "synthetic source")
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertTrue(fixture.evaluator.submissions.isEmpty)
            XCTAssertEqual(fixture.manualCount, 1)
            XCTAssertEqual(fixture.identityMismatchCount, reason == .mismatch ? 1 : 0)
            if [.chooser, .form, .absent].contains(reason) { XCTAssertEqual(fixture.waits.count, QMplusAutofillPolicy.maximumPageWaits) }
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
        XCTAssertTrue(QMplusAutofillPolicy.isTrustedMicrosoftDocument(URL(string: "https://login.microsoftonline.com/kmsi")))
        for value in [prefix + "/saml2/", prefix + "/%73aml2", prefix + "/consent",
                      "https://login.microsoftonline.com/other/login", "https://login.microsoftonline.com.evil.invalid/\(QMplusAutofillPolicy.tenant)/login",
                      "http://login.microsoftonline.com/\(QMplusAutofillPolicy.tenant)/login",
                      "https://login.microsoftonline.com/kmsi/", "https://login.microsoftonline.com/%6bmsi",
                      "https://login.microsoftonline.com/common/kmsi"] {
            XCTAssertFalse(QMplusAutofillPolicy.isTrustedMicrosoftDocument(URL(string: value)), value)
        }
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/login/index.php")))
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/my/")))
        XCTAssertNil(QMplusAutofillPolicy.ssoURL.query)
        XCTAssertEqual(QMplusAutofillPolicy.ssoURL.absoluteString, "https://qmplus.qmul.ac.uk/auth/saml2/login.php")
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 2)
        XCTAssertTrue(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        XCTAssertTrue(ledger.canNavigateLoginEntry(presentation: 1, credentialRevision: 2),
                      "A previously attempted SSO must not consume the independent Login GET budget")
        XCTAssertFalse(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        ledger.stop()
        XCTAssertFalse(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        ledger.begin(presentation: 2, credentialRevision: 2)
        XCTAssertTrue(ledger.claimSSO(presentation: 2, credentialRevision: 2))
    }

    func testDeviceAuthenticationIsPassiveWithoutCredentialOrVerificationAuthority() {
        for path in ["/", "/common/DeviceAuthTls/reprocess", "/kmsi", "/\(QMplusAutofillPolicy.tenant)/login"] {
            let url = URL(string: "https://device.login.microsoftonline.com" + path)
            XCTAssertTrue(QMplusAutofillPolicy.isPassiveMicrosoftTransit(url))
            XCTAssertFalse(QMplusAutofillPolicy.isTrustedMicrosoftDocument(url))
            XCTAssertFalse(QMplusAutofillPolicy.isInspectableMicrosoftDocument(url))
        }
        for value in ["http://device.login.microsoftonline.com", "https://device.login.microsoftonline.com:444",
                      "https://device.login.microsoftonline.com.evil.invalid", "https://device.login.microsoftonline.com@evil.invalid",
                      "https://untrusted@device.login.microsoftonline.com"] {
            XCTAssertFalse(QMplusAutofillPolicy.isPassiveMicrosoftTransit(URL(string: value)), value)
        }
    }

    func testVerificationInspectionWhitelistNeverBecomesACredentialWhitelist() {
        for value in ["https://login.microsoftonline.com/common/DeviceAuthTls/reprocess",
                      "https://login.microsoftonline.com/COMMON/DEVICEAUTHTLS/REPROCESS?synthetic=1"] {
            let url = URL(string: value)
            XCTAssertTrue(QMplusAutofillPolicy.isMicrosoftVerificationDocument(url), value)
            XCTAssertTrue(QMplusAutofillPolicy.isInspectableMicrosoftDocument(url), value)
            XCTAssertFalse(QMplusAutofillPolicy.isTrustedMicrosoftDocument(url), "An inspectable verification route must never authorize credential reads")
        }
        for path in ["/\(QMplusAutofillPolicy.tenant)/saml2", "/\(QMplusAutofillPolicy.tenant)/login", "/kmsi"] {
            let url = URL(string: "https://login.microsoftonline.com" + path)
            XCTAssertTrue(QMplusAutofillPolicy.isTrustedMicrosoftDocument(url))
            XCTAssertTrue(QMplusAutofillPolicy.isInspectableMicrosoftDocument(url))
            XCTAssertFalse(QMplusAutofillPolicy.isMicrosoftVerificationDocument(url))
        }
        for value in ["https://login.microsoftonline.com/common/DeviceAuthTls/reprocess/",
                      "https://login.microsoftonline.com/common/DeviceAuthTls/other",
                      "https://login.microsoftonline.com/common/%44eviceAuthTls/reprocess",
                      "https://login.microsoftonline.com/other/DeviceAuthTls/reprocess",
                      "https://login.microsoftonline.com.evil.invalid/common/DeviceAuthTls/reprocess",
                      "http://login.microsoftonline.com/common/DeviceAuthTls/reprocess",
                      "https://login.microsoftonline.com:444/common/DeviceAuthTls/reprocess",
                      "https://synthetic@login.microsoftonline.com/common/DeviceAuthTls/reprocess",
                      "https://login.microsoftonline.com/\(QMplusAutofillPolicy.tenant)/LOGIN"] {
            let url = URL(string: value)
            XCTAssertFalse(QMplusAutofillPolicy.isMicrosoftVerificationDocument(url), value)
            XCTAssertFalse(QMplusAutofillPolicy.isInspectableMicrosoftDocument(url), value)
            XCTAssertFalse(QMplusAutofillPolicy.isTrustedMicrosoftDocument(url), value)
        }
    }

    func testVerifiedQMplusGuestLandingCanUseFixedSSOEntry() {
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/")))
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/?redirect=0")))
        XCTAssertTrue(QMplusAutofillPolicy.isQMplusLoginDocument(URL(string: "https://qmplus.qmul.ac.uk/login/index.php")))
        XCTAssertEqual(QMplusAutofillPolicy.ssoURL.absoluteString, "https://qmplus.qmul.ac.uk/auth/saml2/login.php")
        XCTAssertNil(QMplusAutofillPolicy.ssoURL.query)
    }

    func testOfficialGuestEntryCannotRestartAfterAccountOrCredentialSteps() {
        let ledger = QMplusAutofillLedger()
        ledger.begin(presentation: 1, credentialRevision: 2)
        XCTAssertTrue(ledger.canStartOfficialLogin(presentation: 1, credentialRevision: 2))
        XCTAssertTrue(ledger.claim(state(.account, match: true), presentation: 1, credentialRevision: 2))
        XCTAssertFalse(ledger.canStartOfficialLogin(presentation: 1, credentialRevision: 2))
        XCTAssertFalse(ledger.canNavigateLoginEntry(presentation: 1, credentialRevision: 2))
        XCTAssertFalse(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        ledger.recordAccountSelection(document: "nonceA123", presentation: 1, credentialRevision: 2)
        XCTAssertTrue(ledger.claim(state(.password, match: true), presentation: 1, credentialRevision: 2))
        XCTAssertFalse(ledger.claimSSO(presentation: 1, credentialRevision: 2))
        ledger.begin(presentation: 2, credentialRevision: 2)
        XCTAssertTrue(ledger.claim(state(.username), presentation: 2, credentialRevision: 2))
        XCTAssertFalse(ledger.canNavigateLoginEntry(presentation: 2, credentialRevision: 2))
        XCTAssertFalse(ledger.claimSSO(presentation: 2, credentialRevision: 2))
    }

    func testOtherQMplusLandingQueriesAndForeignHostsRemainManual() {
        for value in ["https://qmplus.qmul.ac.uk/?redirect=1",
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
        var credentialReads = 0, manualCount = 0, progressCount = 0, challengeCount = 0, identityMismatchCount = 0
        var onManual: (@MainActor () -> Void)?
        var waits: [Duration] = []
        let nonce: String
        let verificationOnly: Bool
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
            verificationOnly: verificationOnly,
            credentials: { [weak self] in
                self?.credentialReads += 1
                guard let self, self.credentialsAvailable else { return nil }
                return self.saved
            }, manual: { [weak self] in self?.manualCount += 1; self?.onManual?() },
            challenge: { [weak self] in self?.challengeCount += 1 },
            identityMismatch: { [weak self] in self?.identityMismatchCount += 1 },
            progress: { [weak self] _ in self?.progressCount += 1 }, wait: { [weak self] duration in
                self?.waits.append(duration); await Task.yield()
            })
            pipelineCache = pipeline
            return pipeline
        }
        init(ledger: QMplusAutofillLedger? = nil, nonce: String = "nonceA123", verificationOnly: Bool = false) {
            self.ledger = ledger ?? QMplusAutofillLedger(); self.nonce = nonce
            self.verificationOnly = verificationOnly
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
        var identityAcknowledgements: [Bool] = []
        var accountHints: [String] = []
        var holdsInstallation = false, holdsInspection = false, holdsSubmission = false
        private var installCallback: (@MainActor @Sendable (QMplusAuthInstallResult) -> Void)?
        private var inspectCallback: (@MainActor @Sendable (QMplusAuthInspection?) -> Void)?
        private var submitCallback: (@MainActor @Sendable (QMplusAuthSubmissionResult?) -> Void)?
        private var lastSubmitCallback: (@MainActor @Sendable (QMplusAuthSubmissionResult?) -> Void)?
        func install(_: String, completion: @escaping @MainActor @Sendable (QMplusAuthInstallResult) -> Void) {
            if holdsInstallation { installCallback = completion } else { completion(installResult) }
        }
        func inspect(nonce _: String, accountHint: String, completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
            accountHints.append(accountHint)
            inspections += 1
            onInspection?()
            if holdsInspection { inspectCallback = completion }
            else { completion(states.isEmpty ? fallbackState : states.removeFirst()) }
        }
        func inspect(nonce: String, accountHint: String, identityAcknowledged: Bool,
                     completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
            identityAcknowledgements.append(identityAcknowledged)
            inspect(nonce: nonce, accountHint: accountHint, completion: completion)
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
                case .continuation: completion(.continuationSubmitted)
                }
            }
        }
        func finishInstallation(_ result: QMplusAuthInstallResult) { installCallback?(result); installCallback = nil }
        func finishInspection(_ result: QMplusAuthInspection) { inspectCallback?(result); inspectCallback = nil }
        func finishSubmission(_ result: QMplusAuthSubmissionResult) { submitCallback?(result); submitCallback = nil }
        func replaySubmission(_ result: QMplusAuthSubmissionResult) { lastSubmitCallback?(result) }
    }
}
