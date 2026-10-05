package com.nemoyu.wheretostudy.nativeapp

import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Production flow, fake transport/clock/secure-store callbacks. No browser or external requests. */
class QmplusAuthFlowTest {
    @Test fun initialAccountChooserCanBecomeReadyWithoutGuessingOrReadingPasswordWhileWaiting() {
        val fixture = installed()
        repeat(3) { attempt ->
            fixture.replyStage(fixture.renderer.take(), "manual", reason = "ACCOUNT_CHOOSER")
            assertEquals(0, fixture.handoffs)
            assertEquals(0, fixture.credentials.passwordReads)
            assertTrue(fixture.renderer.pending.isEmpty())
            fixture.scheduler.advance(if (attempt == 0) 250 else 500)
        }
        fixture.replyStage(fixture.renderer.take(), "account", match = true)
        val choice = fixture.renderer.take()
        assertEquals("account", choice.options().getString("stage"))
        assertFalse(choice.options().has("password"))
        choice.reply("\"ACCOUNT_SELECTED\"")
        assertEquals(0, fixture.handoffs)
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.flow.close()
    }

    @Test fun aPersistentlyUnmatchedFirstChooserStopsAfterEightWaitsAndCannotRenewTheConnectionDeadline() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "manual", reason = "ACCOUNT_CHOOSER")
        repeat(8) { attempt ->
            fixture.scheduler.advance(if (attempt == 0) 250 else 500)
            fixture.replyStage(fixture.renderer.take(), "manual", reason = "ACCOUNT_CHOOSER")
        }
        assertEquals(1, fixture.deferrals)
        assertEquals(0, fixture.reveals)
        assertEquals(0, fixture.credentials.passwordReads)
        assertTrue(fixture.renderer.pending.isEmpty())
        fixture.flow.close()
        val deadline = installed()
        deadline.scheduler.advance(24_000)
        deadline.replyStage(deadline.renderer.take(), "manual", reason = "ACCOUNT_CHOOSER")
        deadline.scheduler.advance(1_000)
        assertEquals(1, deadline.deferrals)
        assertEquals(0, deadline.credentials.passwordReads)
        assertTrue(deadline.renderer.pending.isEmpty())
        deadline.flow.close()
    }

    @Test fun microsoftTransitDoesNotInspectOrReadSecretsAndKeepsTheOriginalDeadlineAcrossHops() {
        val fixture = Fixture(optIn = false)
        fixture.open("https://device.login.microsoftonline.com/common/intermediate")
        assertTrue(fixture.renderer.pending.isEmpty())
        fixture.scheduler.advance(20_000)
        fixture.open("https://login.microsoftonline.com/common/another-intermediate")
        assertTrue(fixture.renderer.pending.isEmpty())
        fixture.scheduler.advance(5_000)
        assertEquals(1, fixture.deferrals)
        assertEquals(0, fixture.reveals)
        assertEquals(0, fixture.credentials.authorizationChecks)
        assertEquals(0, fixture.credentials.accountReads)
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.flow.close()
    }

    @Test fun passwordAckSurvivesPassiveMicrosoftTransitUntilTheRecognizedMFA() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "password", match = true, reason = "CURRENT_ACCOUNT_VERIFIED")
        fixture.renderer.take().reply("\"PASSWORD_SUBMITTED\"")
        val reads = fixture.credentials.authorizationChecks
        fixture.open("https://device.login.microsoftonline.com/common/intermediate")
        assertTrue(fixture.renderer.pending.isEmpty())
        assertEquals(reads, fixture.credentials.authorizationChecks)
        assertEquals(0, fixture.handoffs)
        fixture.open(VERIFICATION)
        fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
        fixture.replyStage(fixture.renderer.take(), "challenge", reason = "MFA_REQUIRED")
        assertEquals(1, fixture.reveals)
        assertEquals(0, fixture.deferrals)
        assertEquals(1, fixture.credentials.passwordReads)
        fixture.flow.close()
    }

    @Test fun verificationOnlyPathDetectsMFAWithoutAnySavedAuthorizationOrSecretRead() {
        val fixture = Fixture(optIn = false)
        fixture.open(VERIFICATION)
        fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
        fixture.replyStage(fixture.renderer.take(), "challenge", reason = "MFA_REQUIRED")
        assertEquals(1, fixture.reveals)
        assertEquals(0, fixture.credentials.authorizationChecks)
        assertEquals(0, fixture.credentials.accountReads)
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.flow.close()
    }

    @Test fun verificationOnlyPathRejectsEverySubmissionStageEvenWithMatchingIdentity() {
        for (stage in listOf("account", "username", "password", "continue")) {
            val fixture = Fixture()
            fixture.open(VERIFICATION)
            fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
            fixture.replyStage(fixture.renderer.take(), stage, match = true)
            assertEquals(1, fixture.deferrals)
            assertEquals(0, fixture.reveals)
            assertEquals(0, fixture.credentials.authorizationChecks)
            assertEquals(0, fixture.credentials.accountReads)
            assertEquals(0, fixture.credentials.passwordReads)
            assertTrue(fixture.renderer.pending.isEmpty())
            fixture.flow.close()
        }
    }

    @Test fun verificationOnlyLoadingHasADeadlineAndRetiredOwnerCannotReveal() {
        val loading = Fixture(optIn = false)
        loading.open(VERIFICATION)
        loading.renderer.take().reply("\"AUTH_INSTALLED\"")
        loading.replyStage(loading.renderer.take(), "loading", reason = "LOADING")
        loading.scheduler.advance(25_000)
        assertEquals(1, loading.deferrals)
        assertEquals(0, loading.reveals)
        loading.flow.close()
        val retired = Fixture(optIn = false)
        retired.open(VERIFICATION)
        retired.renderer.take().reply("\"AUTH_INSTALLED\"")
        val old = retired.renderer.take()
        retired.flow.close()
        retired.replyStage(old, "challenge", reason = "MFA_REQUIRED")
        assertEquals(0, retired.handoffs)
    }

    @Test fun passwordAcknowledgementAllowsABoundedReadonlyWaitForTheOldFilledForm() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "password", match = true, reason = "CURRENT_ACCOUNT_VERIFIED")
        fixture.renderer.take().reply("\"PASSWORD_SUBMITTED\"")
        repeat(12) {
            fixture.scheduler.advance(350)
            fixture.replyStage(fixture.renderer.take(), "manual", reason = "INTERFERENCE")
            assertEquals(0, fixture.handoffs)
            assertEquals(1, fixture.credentials.passwordReads)
            assertTrue(fixture.renderer.pending.isEmpty())
        }
        fixture.scheduler.advance(350)
        fixture.replyStage(fixture.renderer.take(), "manual", reason = "INTERFERENCE")
        assertEquals(1, fixture.deferrals)
        assertEquals(1, fixture.credentials.passwordReads)
        fixture.flow.close()
    }

    @Test fun challengeRevealsOnlyOnceAndContinuesToKMSIWithoutAnotherPassword() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "password", match = true, reason = "CURRENT_ACCOUNT_VERIFIED")
        val signIn = fixture.renderer.take()
        assertTrue(signIn.options().getBoolean("identityAcknowledged"))
        signIn.reply("\"PASSWORD_SUBMITTED\"")
        fixture.scheduler.advance(350)
        fixture.replyStage(fixture.renderer.take(), "challenge", reason = "MFA_REQUIRED")
        assertEquals(1, fixture.reveals)
        assertEquals(0, fixture.deferrals)
        fixture.scheduler.advance(30_000)
        fixture.replyStage(fixture.renderer.take(), "challenge", reason = "MFA_REQUIRED")
        assertEquals(1, fixture.reveals)
        fixture.open("https://login.microsoftonline.com/kmsi")
        fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
        fixture.replyStage(fixture.renderer.take(), "continue", match = true)
        val keepSignedIn = fixture.renderer.take()
        assertEquals("continue", keepSignedIn.options().getString("stage"))
        assertFalse(keepSignedIn.options().has("password"))
        assertTrue(keepSignedIn.options().getBoolean("identityAcknowledged"))
        keepSignedIn.reply("\"CONTINUE_SUBMITTED\"")
        fixture.open(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(1, fixture.authenticated)
        assertEquals(1, fixture.credentials.passwordReads)
        assertEquals(0, fixture.deferrals)
        fixture.flow.close()
    }

    @Test fun unknownPageAndMalformedChallengeDeferWithoutOpeningTheOfficialWindow() {
        for (reason in listOf("UNSUPPORTED_PAGE", "MFA_REQUIRED")) {
            val fixture = installed()
            fixture.replyStage(fixture.renderer.take(), "manual", reason = reason)
            assertEquals(0, fixture.reveals)
            assertEquals(1, fixture.deferrals)
            assertEquals(0, fixture.credentials.passwordReads)
            fixture.flow.close()
        }
    }

    @Test fun directKMSICurrentAccountProofNeverReadsPasswordAndCannotRepeat() {
        val fixture = Fixture()
        fixture.open("https://login.microsoftonline.com/kmsi")
        fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
        fixture.replyStage(fixture.renderer.take(), "continue", match = true, reason = "CURRENT_ACCOUNT_VERIFIED")
        val request = fixture.renderer.take()
        assertFalse(request.options().has("password"))
        request.reply("\"CONTINUE_SUBMITTED\"")
        fixture.scheduler.advance(350)
        fixture.replyStage(fixture.renderer.take(), "continue", match = true)
        assertEquals(0, fixture.credentials.passwordReads)
        assertEquals(0, fixture.reveals)
        assertEquals(1, fixture.deferrals)
        fixture.flow.close()
    }

    @Test fun acknowledgedAccountCanContinueInANewPasswordDocumentWithFreshAuthorization() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "account", match = true)
        fixture.renderer.take().reply("\"ACCOUNT_SELECTED\"")
        fixture.open(MS)
        fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
        fixture.replyStage(fixture.renderer.take(), "password", match = true)
        assertTrue(fixture.renderer.take().options().getBoolean("identityAcknowledged"))
        assertEquals(1, fixture.credentials.passwordReads)
        assertEquals(0, fixture.handoffs)
        fixture.flow.close()
    }

    @Test fun ordinarySameDocumentSPAUsesCanonicalInstallAndEachStageOnceWithoutPasswordInUsername() {
        val fixture = Fixture()
        fixture.open(MS)
        val install = fixture.renderer.take()
        assertTrue(install.script.contains(fixture.helper))
        assertEquals(0, fixture.credentials.accountReads)
        install.reply("\"AUTH_INSTALLED\"")
        val username = fixture.renderer.take()
        fixture.replyStage(username, "username")
        val next = fixture.renderer.take()
        val usernameOptions = next.options()
        assertEquals("username", usernameOptions.getString("stage"))
        assertFalse(usernameOptions.has("password"))
        assertEquals(0, fixture.credentials.passwordReads)
        next.reply("\"USERNAME_SUBMITTED\"")
        // No pageFinished callback: the real polling pipeline handles the SPA.
        fixture.scheduler.advance(350)
        val password = fixture.renderer.take()
        fixture.replyStage(password, "password", match = true)
        val signIn = fixture.renderer.take()
        assertEquals("password", signIn.options().getString("stage"))
        assertEquals(1, fixture.credentials.passwordReads)
        assertTrue(checkNotNull(fixture.credentials.lastPassword).password.all { it == '\u0000' })
        signIn.reply("\"PASSWORD_SUBMITTED\"")
        fixture.open(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(1, fixture.authenticated)
        assertEquals(0, fixture.handoffs)
        assertTrue(fixture.phases.containsAll(listOf("installing", "username_submitted", "password_submitted", "authenticated")))
        fixture.flow.close()
    }

    @Test fun defaultOffAndInstallationConflictNeverReadSavedSecretsOrSendCredentials() {
        for (optIn in listOf(false, true)) {
            val fixture = Fixture(optIn)
            fixture.open(MS)
            if (optIn) fixture.renderer.take().reply("\"AUTH_CONFLICT\"")
            assertEquals(1, fixture.handoffs)
            assertEquals(0, fixture.credentials.accountReads)
            assertEquals(0, fixture.credentials.passwordReads)
            assertFalse(fixture.renderer.pending.any { it.script.contains("fillAndSubmit(") })
            fixture.flow.close()
        }
    }

    @Test fun canonicalPageKindsNeverTreatAnErrorUnknownGuestOrBooleanAsAuthenticated() {
        for (kind in listOf("error", "unknown", "guest")) {
            val fixture = Fixture()
            fixture.open(QmplusPolicy.START_URL)
            val request = fixture.renderer.take()
            assertTrue(request.script.contains(fixture.pageHelper))
            request.reply(JSONObject.quote(kind))
            if (kind == "guest") fixture.renderer.take().reply("\"none\"")
            assertEquals(0, fixture.authenticated)
            assertEquals(1, fixture.handoffs)
            assertTrue(fixture.renderer.navigations.isEmpty())
            assertEquals(0, fixture.credentials.passwordReads)
            if (kind == "error") assertTrue(fixture.phases.contains("QM_ERROR_PAGE"))
            fixture.flow.close()
        }
        assertEquals(QmplusPageKind.UNKNOWN, QmplusPageKind.decode("true"))
        assertEquals(QmplusPageKind.UNKNOWN, QmplusPageKind.decode("\"authenticated\"" + " ".repeat(65)))
    }

    @Test fun bareWelcomeRequiresGuestAndSafeDestinationThenFreshAuthorizationBeforeFixedSSO() {
        for (entry in listOf("https://qmplus.qmul.ac.uk/", "https://qmplus.qmul.ac.uk/?redirect=0")) {
            val fixture = Fixture(); fixture.open(entry)
            assertTrue(fixture.renderer.navigations.isEmpty())
            fixture.renderer.take().reply("\"guest\"")
            val approval = fixture.renderer.take()
            assertTrue(approval.script.contains("targets.has('${QmplusLoginPagePolicy.SSO_START_URL}')"))
            assertTrue(approval.script.contains("!u.username && !u.password && !u.search && !u.hash"))
            approval.reply("\"saml\"")
            assertEquals(listOf(QmplusLoginPagePolicy.SSO_START_URL), fixture.renderer.navigations)
            assertEquals(0, fixture.credentials.accountReads)
            assertEquals(0, fixture.credentials.passwordReads)
            fixture.flow.close()
        }
        for (revoke in listOf(false, true)) {
            val fixture = Fixture(); fixture.open("https://qmplus.qmul.ac.uk/")
            fixture.renderer.take().reply("\"guest\"")
            val approval = fixture.renderer.take()
            if (revoke) fixture.credentials.allowed = false
            approval.reply(if (revoke) "\"saml\"" else "\"none\"")
            assertTrue(fixture.renderer.navigations.isEmpty())
            assertEquals(1, fixture.handoffs)
            fixture.flow.close()
        }
    }

    @Test fun completedCredentialAttemptAndRetiredDocumentsCannotRestartSSOFromGuest() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "username")
        fixture.renderer.take().reply("\"USERNAME_SUBMITTED\"")
        fixture.open("https://qmplus.qmul.ac.uk/login/index.php")
        fixture.renderer.take().reply("\"guest\"")
        fixture.renderer.take().reply("\"saml\"")
        assertTrue(fixture.renderer.navigations.isEmpty())
        assertEquals(1, fixture.handoffs)
        fixture.flow.close()
        val late = Fixture(); late.open("https://qmplus.qmul.ac.uk/")
        late.renderer.take().reply("\"guest\"")
        val oldApproval = late.renderer.take()
        late.open(QmplusPolicy.START_URL)
        oldApproval.reply("\"saml\"")
        assertTrue(late.renderer.navigations.isEmpty())
        late.renderer.take().reply("\"authenticated\"")
        assertEquals(1, late.authenticated)
        late.flow.close()
    }

    @Test fun authenticatedWelcomeGetsOnlyOneFixedDashboardGetWithoutSSOOrCredentials() {
        val fixture = Fixture()
        fixture.open("https://qmplus.qmul.ac.uk/")
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(listOf(QmplusPolicy.START_URL), fixture.renderer.navigations)
        fixture.open(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(1, fixture.authenticated)
        fixture.open("https://qmplus.qmul.ac.uk/")
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(1, fixture.renderer.navigations.size)
        assertEquals(0, fixture.credentials.accountReads)
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.flow.close()
    }

    @Test fun approvedSSOEntryNavigatesFixedURLOnceAndCannotReplayAfterBackOrRevocation() {
        val fixture = Fixture()
        fixture.open("https://qmplus.qmul.ac.uk/login/index.php")
        fixture.renderer.take().reply("\"guest\"")
        fixture.renderer.take().reply("\"saml\"")
        assertEquals(listOf(QmplusLoginPagePolicy.SSO_START_URL), fixture.renderer.navigations)
        fixture.open(QmplusLoginPagePolicy.SSO_START_URL)
        fixture.renderer.take().reply("\"loading\"")
        fixture.open(MS)
        fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
        fixture.open("https://qmplus.qmul.ac.uk/login/index.php")
        fixture.renderer.take().reply("\"guest\"")
        fixture.renderer.take().reply("\"saml\"")
        assertEquals(1, fixture.renderer.navigations.size)
        assertEquals(1, fixture.handoffs)
        fixture.flow.close()
        val revoked = Fixture()
        revoked.credentials.allowed = false
        revoked.open("https://qmplus.qmul.ac.uk/login/index.php")
        revoked.renderer.take().reply("\"guest\"")
        assertTrue(revoked.renderer.navigations.isEmpty())
        assertEquals(1, revoked.handoffs)
        revoked.flow.close()
    }

    @Test fun verifiedDashboardGuestCanTakePlainEntryThenFixedSSOWithoutReadingCredentialsOrRepeatingEntry() {
        val fixture = Fixture()
        fixture.open(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"guest\"")
        fixture.renderer.take().reply("\"login\"")
        assertEquals(listOf(QmplusLoginPagePolicy.LOGIN_ENTRY_URL), fixture.renderer.navigations)
        fixture.open(QmplusLoginPagePolicy.LOGIN_ENTRY_URL)
        fixture.renderer.take().reply("\"guest\"")
        fixture.renderer.take().reply("\"saml\"")
        assertEquals(listOf(QmplusLoginPagePolicy.LOGIN_ENTRY_URL, QmplusLoginPagePolicy.SSO_START_URL), fixture.renderer.navigations)
        assertEquals(0, fixture.credentials.accountReads)
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.open(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"guest\"")
        fixture.renderer.take().reply("\"login\"")
        assertEquals(2, fixture.renderer.navigations.size)
        assertEquals(1, fixture.handoffs)
        fixture.flow.close()
    }

    @Test fun unknownFrameOriginPathAndManualVerificationNeverGetNativeFillOrPassword() {
        val pages = listOf("https://qmplus.qmul.ac.uk.evil.invalid/login/index.php", "http://qmplus.qmul.ac.uk/login/index.php",
            "https://login.microsoftonline.com/common/Consent", "https://qmplus.qmul.ac.uk/login/other.php")
        pages.forEach { page ->
            val fixture = Fixture(); fixture.open(page)
            if (QmplusLoginPagePolicy.isOfficialQMPage(page)) fixture.renderer.take().reply("\"unknown\"")
            if (QmplusLoginPagePolicy.isMicrosoftTransitPage(page)) {
                assertEquals(0, fixture.handoffs)
                assertTrue(fixture.renderer.pending.isEmpty())
                fixture.scheduler.advance(25_000)
            }
            assertEquals(1, fixture.handoffs)
            assertEquals(0, fixture.credentials.accountReads)
            assertEquals(0, fixture.credentials.passwordReads)
            assertTrue(fixture.renderer.pending.isEmpty()); fixture.flow.close()
        }
        listOf("ACCOUNT_CHOOSER", "INTERFERENCE", "FORM_UNTRUSTED", "ACCOUNT_MISMATCH", "UNSUPPORTED_PAGE").forEach { reason ->
            val fixture = installed()
            fixture.replyStage(fixture.renderer.take(), "manual", reason = reason)
            if (reason in listOf("FORM_UNTRUSTED", "ACCOUNT_CHOOSER")) {
                assertEquals(0, fixture.handoffs)
                repeat(8) { attempt ->
                    fixture.scheduler.advance(if (reason == "ACCOUNT_CHOOSER") { if (attempt == 0) 250 else 500 } else 350)
                    fixture.replyStage(fixture.renderer.take(), "manual", reason = reason)
                }
            }
            assertEquals(1, fixture.handoffs)
            assertEquals(0, fixture.credentials.passwordReads)
            assertTrue(fixture.renderer.pending.isEmpty()); fixture.flow.close()
        }
    }

    @Test fun firstLayoutMayWaitEightTimesThenSubmitOnlyTheKnownUsernameStageOnce() {
        for (reason in listOf("FORM_UNTRUSTED", "KNOWN_FORM_ABSENT")) {
            val fixture = installed()
            repeat(8) { attempt ->
                if (attempt > 0) fixture.scheduler.advance(350)
                fixture.replyStage(fixture.renderer.take(), "manual", reason = reason)
                assertEquals(0, fixture.handoffs)
                assertEquals(0, fixture.credentials.passwordReads)
                assertTrue(fixture.renderer.pending.isEmpty())
            }
            fixture.scheduler.advance(350)
            fixture.replyStage(fixture.renderer.take(), "username")
            val submission = fixture.renderer.take().options()
            assertEquals("username", submission.getString("stage"))
            assertFalse(submission.has("password"))
            assertEquals(0, fixture.credentials.passwordReads)
            fixture.flow.close()
        }
    }

    @Test fun anUnknownInitialLayoutAlwaysStopsAfterEightPollsWithoutSubmittingOrReadingPassword() {
        for (reason in listOf("FORM_UNTRUSTED", "KNOWN_FORM_ABSENT")) {
            val fixture = installed()
            fixture.replyStage(fixture.renderer.take(), "manual", reason = reason)
            repeat(8) { attempt ->
                assertEquals(0, fixture.handoffs)
                fixture.scheduler.advance(350)
                fixture.replyStage(fixture.renderer.take(), "manual", reason = reason)
                assertEquals(if (attempt == 7) 1 else 0, fixture.handoffs)
                assertTrue(fixture.renderer.pending.isEmpty())
            }
            assertEquals(0, fixture.credentials.passwordReads)
            assertFalse(fixture.phases.contains("username_submitted"))
            fixture.scheduler.advance(25_000)
            assertEquals(1, fixture.handoffs)
            assertTrue(fixture.renderer.pending.isEmpty())
            fixture.flow.close()
        }
    }

    @Test fun absentOrUntrustedFormAfterUsernameSubmissionNeverUsesInitialLayoutRetries() {
        for (reason in listOf("FORM_UNTRUSTED", "KNOWN_FORM_ABSENT")) {
            val fixture = installed()
            fixture.replyStage(fixture.renderer.take(), "username")
            fixture.renderer.take().reply("\"USERNAME_SUBMITTED\"")
            fixture.scheduler.advance(350)
            fixture.replyStage(fixture.renderer.take(), "manual", reason = reason)
            assertEquals(1, fixture.handoffs)
            assertEquals(0, fixture.credentials.passwordReads)
            fixture.scheduler.advance(25_000)
            assertEquals(1, fixture.handoffs)
            assertTrue(fixture.renderer.pending.isEmpty())
            fixture.flow.close()
        }
    }

    @Test fun initialLayoutWaitCannotContinueAfterCredentialRevisionURLBackgroundOrCloseChanges() {
        for (change in listOf("revision", "url", "background", "close")) {
            val fixture = installed()
            fixture.replyStage(fixture.renderer.take(), "manual", reason = "FORM_UNTRUSTED")
            when (change) {
                "revision" -> fixture.credentials.authorizedRevision = REVISION + 1
                "url" -> fixture.renderer.currentURL = "https://example.invalid/unknown"
                "background" -> fixture.flow.suspend()
                "close" -> fixture.flow.close()
            }
            fixture.scheduler.advance(350)
            assertEquals(if (change == "close") 0 else 1, fixture.handoffs)
            assertEquals(0, fixture.credentials.passwordReads)
            assertTrue(fixture.renderer.pending.isEmpty())
            fixture.scheduler.advance(25_000)
            assertEquals(if (change == "close") 0 else 1, fixture.handoffs)
            assertTrue(fixture.renderer.pending.isEmpty())
            fixture.flow.close()
        }
    }

    @Test fun passwordNeedsMatchingAccountAndAcknowledgedUsernameInThisDocument() {
        for (match in listOf(false, true)) {
            val fixture = installed()
            fixture.replyStage(fixture.renderer.take(), "password", match = match,
                reason = if (match) "USERNAME_NOT_SUBMITTED" else "ACCOUNT_MISMATCH")
            assertEquals(1, fixture.handoffs)
            assertEquals(0, fixture.credentials.passwordReads); fixture.flow.close()
        }
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "username")
        val next = fixture.renderer.take()
        fixture.open(MS)
        next.reply("\"USERNAME_SUBMITTED\"") // Late ACK from the old document.
        fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
        fixture.replyStage(fixture.renderer.take(), "password", match = true, reason = "USERNAME_NOT_SUBMITTED")
        assertEquals(0, fixture.credentials.passwordReads)
        assertEquals(1, fixture.handoffs); fixture.flow.close()
    }

    @Test fun failedUsernameSubmitIsNeverRetriedAndSPAWaitIsFinite() {
        val failed = installed()
        failed.replyStage(failed.renderer.take(), "username")
        failed.renderer.take().reply("\"MANUAL_REQUIRED\"")
        failed.scheduler.advance(25_000)
        assertEquals(1, failed.handoffs)
        assertTrue(failed.renderer.pending.isEmpty())
        assertEquals(0, failed.credentials.passwordReads); failed.flow.close()
        val pending = installed()
        pending.replyStage(pending.renderer.take(), "username")
        pending.renderer.take().reply("\"USERNAME_SUBMITTED\"")
        repeat(13) {
            pending.scheduler.advance(350)
            if (pending.renderer.pending.isNotEmpty()) pending.replyStage(pending.renderer.take(), "manual", reason = "ALREADY_ATTEMPTED")
        }
        assertEquals(1, pending.handoffs)
        assertEquals(0, pending.credentials.passwordReads); pending.flow.close()
    }

    @Test fun delayedAccountAndPasswordCallbacksCannotFillAfterURLChangeRevocationOrClose() {
        val account = Fixture()
        account.credentials.deferAccount = true
        account.open(MS); account.renderer.take().reply("\"AUTH_INSTALLED\"")
        account.renderer.currentURL = "https://example.invalid/unknown"
        account.credentials.accountCallback?.invoke(ACCOUNT)
        assertTrue(account.renderer.pending.isEmpty())
        assertEquals(1, account.handoffs); account.flow.close()
        val password = installed()
        password.replyStage(password.renderer.take(), "username")
        password.renderer.take().reply("\"USERNAME_SUBMITTED\"")
        password.credentials.deferPassword = true
        password.scheduler.advance(350)
        password.replyStage(password.renderer.take(), "password", match = true)
        password.flow.close()
        val late = QmplusSavedLogin(ACCOUNT, "synthetic-only".toCharArray(), REVISION)
        password.credentials.passwordCallback?.invoke(late)
        assertTrue(late.password.all { it == '\u0000' })
        assertTrue(password.renderer.pending.isEmpty())
        assertEquals(0, password.handoffs)
        assertTrue(password.credentials.closed)
    }

    @Test fun withdrawalBeforeStageExecutionStopsFillAndBackgroundCancelsQuietWork() {
        val revoked = installed()
        val inspect = revoked.renderer.take()
        revoked.credentials.allowed = false
        revoked.replyStage(inspect, "username")
        assertTrue(revoked.renderer.pending.isEmpty())
        assertEquals(1, revoked.handoffs)
        assertEquals(0, revoked.credentials.passwordReads); revoked.flow.close()
        val background = installed()
        val late = background.renderer.take()
        background.flow.suspend()
        background.replyStage(late, "username")
        background.scheduler.advance(25_000)
        assertEquals(1, background.handoffs)
        assertTrue(background.renderer.pending.isEmpty()); background.flow.close()
    }

    @Test fun malformedOrOversizedResultsNeverExportUnrecognizedPageData() {
        val nonce = "syntheticNonce1"
        val valid = JSONObject().put("v", 1).put("stage", "username").put("document", nonce).put("accountMatch", false).put("reason", "READY")
        assertNotNull(QmplusAuthResultCodec.observation(valid.toString(), nonce))
        assertNull(QmplusAuthResultCodec.observation(valid.put("password", "synthetic-only").toString(), nonce))
        valid.remove("password")
        assertNull(QmplusAuthResultCodec.observation(valid.put("accountMatch", "true").toString(), nonce))
        assertNull(QmplusAuthResultCodec.observation("x".repeat(1025), nonce))
        assertNull(QmplusAuthResultCodec.code("{\"account\":\"synthetic\"}"))
        assertNull(QmplusAuthResultCodec.code("\"not-a-fixed-code\""))
    }

    @Test fun droppedRendererCompletionUsesFiniteManualCleanupAndLateCompletionDoesNotLoadAccount() {
        val fixture = Fixture()
        fixture.open(MS)
        val dropped = fixture.renderer.take()
        fixture.scheduler.advance(25_000)
        assertEquals(1, fixture.handoffs)
        dropped.reply("\"AUTH_INSTALLED\"")
        assertEquals(0, fixture.credentials.accountReads)
        assertEquals(0, fixture.credentials.passwordReads)
        assertTrue(fixture.renderer.pending.isEmpty())
        fixture.flow.close()
    }

    @Test fun currentAuthorizationFailureBeforeInstallationNeverSendsEvenAccountHintToPage() {
        val fixture = Fixture()
        fixture.credentials.allowed = false
        fixture.open(MS)
        assertEquals(1, fixture.handoffs)
        assertTrue(fixture.renderer.pending.isEmpty())
        assertEquals(0, fixture.credentials.accountReads)
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.flow.close()
    }

    @Test fun explicitCourseOrModuleOpenKeepsVisibleTargetAndNeverFinishesByAutomaticSync() {
        listOf("https://qmplus.qmul.ac.uk/course/view.php?id=1", "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2",
            "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=3").forEach { target ->
            val alreadySignedIn = Fixture(quiet = false, target = target)
            alreadySignedIn.open(target)
            alreadySignedIn.renderer.take().reply("\"authenticated\"")
            assertEquals(0, alreadySignedIn.authenticated)
            assertEquals(1, alreadySignedIn.handoffs)
            assertTrue(alreadySignedIn.renderer.navigations.isEmpty())
            assertTrue(alreadySignedIn.phases.contains("detail_visible")); alreadySignedIn.flow.close()
            val afterLogin = Fixture(quiet = false, target = target)
            afterLogin.open(QmplusPolicy.START_URL)
            afterLogin.renderer.take().reply("\"authenticated\"")
            assertEquals(listOf(target), afterLogin.renderer.navigations)
            assertEquals(0, afterLogin.authenticated)
            assertEquals(1, afterLogin.handoffs)
            afterLogin.open(target)
            afterLogin.renderer.take().reply("\"authenticated\"")
            assertEquals(1, afterLogin.renderer.navigations.size)
            assertEquals(0, afterLogin.authenticated); afterLogin.flow.close()
        }
    }

    @Test fun interruptedAuthenticatedSyncMayResumeOnceWithoutReadingOrRetryingCredentials() {
        val fixture = Fixture()
        fixture.open(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(1, fixture.authenticated)
        // Activity cancels the in-flight renderer work on background and alone
        // reports that interruption. Suspending does not renew credential claims.
        fixture.flow.suspend()
        fixture.flow.interruptedSync()
        fixture.flow.pageReady(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(2, fixture.authenticated)
        fixture.flow.pageReady(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(2, fixture.authenticated)
        assertEquals(0, fixture.credentials.accountReads)
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.open(MS)
        assertTrue(fixture.renderer.pending.isEmpty())
        fixture.flow.close()
    }

    @Test fun successfulOrFailedSyncIsNotAutomaticallyRetriedOnForegroundOrAnotherDocument() {
        for (failed in listOf(false, true)) {
            val fixture = Fixture()
            fixture.open(QmplusPolicy.START_URL)
            fixture.renderer.take().reply("\"authenticated\"")
            if (failed) fixture.flow.manualRequired()
            fixture.flow.suspend()
            fixture.flow.pageReady(QmplusPolicy.START_URL)
            fixture.renderer.take().reply("\"authenticated\"")
            fixture.open(QmplusPolicy.START_URL)
            fixture.renderer.take().reply("\"authenticated\"")
            assertEquals(1, fixture.authenticated)
            assertEquals(0, fixture.credentials.accountReads)
            assertEquals(0, fixture.credentials.passwordReads)
            fixture.flow.close()
        }
    }

    @Test fun exactAccountSelectionSendsNoPasswordAndItsSameDocumentAckCanAuthorizeOneMatchingPassword() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "account", match = true)
        val select = fixture.renderer.take()
        assertEquals("account", select.options().getString("stage"))
        assertFalse(select.options().has("password"))
        assertEquals(0, fixture.credentials.passwordReads)
        select.reply("\"ACCOUNT_SELECTED\"")
        fixture.scheduler.advance(350)
        fixture.replyStage(fixture.renderer.take(), "password", match = true)
        val signIn = fixture.renderer.take()
        assertEquals("password", signIn.options().getString("stage"))
        assertEquals(1, fixture.credentials.passwordReads)
        signIn.reply("\"PASSWORD_SUBMITTED\"")
        fixture.open(QmplusPolicy.START_URL)
        fixture.renderer.take().reply("\"authenticated\"")
        assertEquals(1, fixture.authenticated)
        assertEquals(0, fixture.handoffs)
        assertTrue(fixture.phases.contains("account_selected"))
        assertFalse(fixture.phases.contains("username_submitted"))
        fixture.flow.close()
    }

    @Test fun accountSelectionDoesNotReplayAndUnknownOrUnmatchedTilesNeverReadPassword() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "account", match = true)
        fixture.renderer.take().reply("\"ACCOUNT_SELECTED\"")
        fixture.scheduler.advance(350)
        fixture.replyStage(fixture.renderer.take(), "account", match = true)
        assertEquals(1, fixture.handoffs)
        assertTrue(fixture.renderer.pending.isEmpty())
        assertEquals(0, fixture.credentials.passwordReads)
        fixture.flow.close()
        for (reason in listOf("ACCOUNT_CHOOSER", "ACCOUNT_MISMATCH", "INTERFERENCE", "UNSUPPORTED_PAGE")) {
            val manual = installed()
            manual.replyStage(manual.renderer.take(), "account", match = false, reason = reason)
            assertEquals(1, manual.handoffs)
            assertEquals(0, manual.credentials.passwordReads)
            assertTrue(manual.renderer.pending.isEmpty())
            manual.flow.close()
        }
    }

    @Test fun selectedAccountCannotAuthorizePasswordAfterNavigationOrFreshCredentialRevocation() {
        for (change in listOf("navigation", "revision")) {
            val fixture = installed()
            fixture.replyStage(fixture.renderer.take(), "account", match = true)
            fixture.renderer.take().reply("\"ACCOUNT_SELECTED\"")
            if (change == "navigation") {
                fixture.open(MS)
                fixture.renderer.take().reply("\"AUTH_INSTALLED\"")
                fixture.replyStage(fixture.renderer.take(), "password", match = true, reason = "USERNAME_NOT_SUBMITTED")
            } else {
                fixture.credentials.authorizedRevision = REVISION + 1
                fixture.scheduler.advance(350)
            }
            assertEquals(0, fixture.credentials.passwordReads)
            assertEquals(1, fixture.handoffs)
            assertTrue(fixture.renderer.pending.isEmpty())
            fixture.flow.close()
        }
    }

    @Test fun featureOffThenOnCannotReviveAnOldAccountAckOrReadSecretsFromItsRetiredOwner() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "account", match = true)
        val oldAck = fixture.renderer.take()
        fixture.featureAllowed = false
        fixture.flow.pageReady(MS)
        fixture.featureAllowed = true
        oldAck.reply("\"ACCOUNT_SELECTED\"")
        fixture.flow.pageReady(MS)
        fixture.flow.pageStarted(MS)
        fixture.scheduler.advance(25_000)
        assertTrue(fixture.credentials.closed)
        assertEquals(0, fixture.credentials.passwordReads)
        assertTrue(fixture.renderer.pending.isEmpty())
        assertEquals(0, fixture.handoffs)
    }

    @Test fun temporaryEmptyChooserAfterSelectedAckWaitsWithoutReselectingOrReadingPassword() {
        val fixture = installed()
        fixture.replyStage(fixture.renderer.take(), "account", match = true)
        fixture.renderer.take().reply("\"ACCOUNT_SELECTED\"")
        repeat(2) {
            fixture.scheduler.advance(350)
            fixture.replyStage(fixture.renderer.take(), "manual", reason = "ACCOUNT_CHOOSER")
            assertEquals(0, fixture.handoffs)
            assertEquals(0, fixture.credentials.passwordReads)
            assertTrue(fixture.renderer.pending.isEmpty())
        }
        fixture.scheduler.advance(350)
        fixture.replyStage(fixture.renderer.take(), "password", match = true)
        assertEquals("password", fixture.renderer.take().options().getString("stage"))
        assertEquals(1, fixture.credentials.passwordReads)
        assertEquals(0, fixture.handoffs)
        fixture.flow.close()
    }

    @Test fun chooserSettlingIsFiniteAndCannotWaitAfterPasswordWasAttempted() {
        val waiting = installed()
        waiting.replyStage(waiting.renderer.take(), "account", match = true)
        waiting.renderer.take().reply("\"ACCOUNT_SELECTED\"")
        repeat(7) {
            waiting.scheduler.advance(350)
            waiting.replyStage(waiting.renderer.take(), "manual", reason = "ACCOUNT_CHOOSER")
        }
        assertEquals(1, waiting.handoffs)
        assertEquals(0, waiting.credentials.passwordReads)
        assertTrue(waiting.renderer.pending.isEmpty())
        waiting.flow.close()
        val afterPassword = installed()
        afterPassword.replyStage(afterPassword.renderer.take(), "account", match = true)
        afterPassword.renderer.take().reply("\"ACCOUNT_SELECTED\"")
        afterPassword.scheduler.advance(350)
        afterPassword.replyStage(afterPassword.renderer.take(), "password", match = true)
        afterPassword.renderer.take().reply("\"PASSWORD_SUBMITTED\"")
        afterPassword.scheduler.advance(350)
        afterPassword.replyStage(afterPassword.renderer.take(), "manual", reason = "ACCOUNT_CHOOSER")
        assertEquals(1, afterPassword.handoffs)
        assertEquals(1, afterPassword.credentials.passwordReads)
        assertTrue(afterPassword.renderer.pending.isEmpty())
        afterPassword.flow.close()
    }

    private fun installed(): Fixture = Fixture().also { it.open(MS); it.renderer.take().reply("\"AUTH_INSTALLED\"") }

    private class Request(val script: String, val reply: (String) -> Unit) {
        fun nonce(): String = checkNotNull(Regex("WTSQmAuth\\.inspect\\(\"([A-Za-z0-9_-]+)\"").find(script)).groupValues[1]
        fun options(): JSONObject = JSONObject(checkNotNull(Regex("WTSQmAuth\\.fillAndSubmit\\((\\{.*\\})\\)").find(script)).groupValues[1])
    }
    private class Renderer : QmplusAuthRenderer {
        override var currentURL: String? = null
        override var active = true
        val pending = mutableListOf<Request>()
        val navigations = mutableListOf<String>()
        override fun evaluate(script: String, completion: (String) -> Unit) { pending += Request(script, completion) }
        override fun navigateToOfficialSSO() { navigations += QmplusLoginPagePolicy.SSO_START_URL }
        override fun navigateToOfficialLogin() { navigations += QmplusLoginPagePolicy.LOGIN_ENTRY_URL }
        override fun openBusinessPage(value: String) { navigations += value }
        fun take(): Request = pending.removeAt(0)
    }
    private class Credentials : QmplusAuthCredentials {
        var allowed = true; var closed = false; var accountReads = 0; var passwordReads = 0; var authorizationChecks = 0
        var authorizedRevision = REVISION
        var deferAccount = false; var deferPassword = false
        var accountCallback: ((String?) -> Unit)? = null
        var passwordCallback: ((QmplusSavedLogin?) -> Unit)? = null
        var lastPassword: QmplusSavedLogin? = null
        override fun authorized(revision: Long, completion: (Boolean) -> Unit) { authorizationChecks++; completion(allowed && revision == authorizedRevision) }
        override fun account(revision: Long, completion: (String?) -> Unit) {
            accountReads++; if (deferAccount) accountCallback = completion else completion(ACCOUNT)
        }
        override fun password(revision: Long, completion: (QmplusSavedLogin?) -> Unit) {
            passwordReads++; if (deferPassword) passwordCallback = completion
            else QmplusSavedLogin(ACCOUNT, "synthetic-only".toCharArray(), revision).also { lastPassword = it; completion(it) }
        }
        override fun close() { closed = true }
    }
    private class Scheduler : QmplusAuthScheduler {
        private data class Task(val at: Long, val action: () -> Unit, var cancelled: Boolean = false)
        private val tasks = mutableListOf<Task>()
        private var now = 0L
        override fun schedule(delayMillis: Long, action: () -> Unit): () -> Unit {
            val task = Task(now + delayMillis, action); tasks += task
            return { task.cancelled = true }
        }
        fun advance(millis: Long) {
            now += millis
            val due = tasks.filter { !it.cancelled && it.at <= now }.toList()
            tasks.removeAll(due.toSet()); due.forEach { it.action() }
        }
    }
    private class Fixture(optIn: Boolean = true, quiet: Boolean = true, target: String = QmplusPolicy.START_URL) {
        val renderer = Renderer(); val credentials = Credentials(); val scheduler = Scheduler()
        val helper = generateSequence(File(checkNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .map { File(it, "contracts/qmplus/qmplus-auth.js") }.first { it.isFile }.readText()
        val pageHelper = generateSequence(File(checkNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .map { File(it, "contracts/qmplus/qmplus-page.js") }.first { it.isFile }.readText()
        var reveals = 0; var deferrals = 0; var authenticated = 0
        val handoffs: Int get() = reveals + deferrals
        var featureAllowed = true
        val phases = mutableListOf<String>()
        val flow = QmplusAuthFlow(renderer, credentials, scheduler, optIn, REVISION, helper,
            reveal = { reveals++ }, authenticated = { authenticated++ }, reportPhase = { phases += it },
            manualContinuation = { deferrals++ },
            quietConnection = quiet, requestedTarget = target, featureEnabled = { featureAllowed }, pageScript = pageHelper)
        fun open(value: String) { renderer.currentURL = value; flow.pageStarted(value); flow.pageReady(value) }
        fun replyStage(request: Request, stage: String, match: Boolean = false, reason: String = "READY") {
            request.reply(JSONObject().put("v", 1).put("stage", stage).put("document", request.nonce())
                .put("accountMatch", match).put("reason", reason).toString())
        }
    }
    private companion object {
        const val MS = "https://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/saml2?synthetic=1"
        const val VERIFICATION = "https://login.microsoftonline.com/common/DeviceAuthTls/reprocess"
        const val ACCOUNT = "synthetic@example.invalid"
        const val REVISION = 7L
    }
}
