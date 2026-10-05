package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.*
import org.junit.Test

class QmplusLoginAutomationTest {
    @Test fun plainGuestEntryIsOnceAndCannotBeClaimedAfterSSOOrCredentialSubmission() {
        val gate = QmplusLoginAutomationGate()
        val document = gate.beginDocument()
        assertFalse(gate.claimLoginEntry(document, false))
        assertTrue(gate.claimLoginEntry(document, true))
        val next = gate.beginDocument()
        assertFalse(gate.claimLoginEntry(next, true))
        assertTrue(gate.claimSSO(next, true))
        assertFalse(gate.claimLoginEntry(next, true))
        assertTrue(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/my"))
        assertTrue(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/my/"))
        assertFalse(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/my/?next=other"))
        assertFalse(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/my/#fragment"))
        assertEquals("login", QmplusAuthResultCodec.guestEntry("\"login\""))
        assertNull(QmplusAuthResultCodec.guestEntry("true"))
        assertNull(QmplusAuthResultCodec.guestEntry("\"https://qmplus.qmul.ac.uk/login/index.php?wants=other\""))
    }

    @Test fun ordinaryFormsRequireSavedOptInAndEachCanBeClaimedOnlyOnce() {
        val gate = QmplusLoginAutomationGate()
        val first = gate.beginDocument()
        assertFalse(gate.claimFill(first, "username", false))
        assertFalse(gate.claimFill(first, "username", true))
        assertFalse(gate.installed(first, "AUTH_CONFLICT"))
        assertTrue(gate.installed(first, "AUTH_INSTALLED"))
        assertTrue(gate.claimFill(first, "username", true))
        assertFalse(gate.claimFill(first, "username", true))
        assertFalse(gate.claimFill(first, "password", true, true))
        assertTrue(gate.submitted(first, "username", "USERNAME_SUBMITTED"))
        assertTrue(gate.claimFill(first, "password", true, true))
        assertFalse(gate.claimFill(first, "password", true, true))
        val password = gate.beginDocument()
        assertFalse(gate.claimFill(first, "password", true))
        assertTrue(gate.installed(password, "AUTH_INSTALLED"))
        assertFalse("A new document cannot inherit an account submission", gate.claimFill(password, "password", true, true))
        assertFalse(gate.claimFill(password, "password", true))
    }

    @Test fun unknownAndManualStagesNeverAuthorizeAutofillAndLogoutRejectsLateResults() {
        val gate = QmplusLoginAutomationGate()
        val document = gate.beginDocument()
        listOf("unknown", "manual", "mfa", "captcha", "account-choice", "consent", "risk", "stay-signed-in")
            .forEach { assertFalse(gate.claimFill(document, it, true)) }
        gate.manualInteractionRequired()
        assertFalse(gate.claimFill(document, "password", true))
        // Manual verification can finish on QMplus and still perform one read-only sync.
        assertFalse(gate.claimAutomaticSync(document, false))
        assertTrue(gate.claimAutomaticSync(document, true))
        assertFalse(gate.claimAutomaticSync(document, true))
        gate.close()
        assertFalse(gate.accepts(document))
        assertFalse(gate.claimAutomaticSync(document, true))
    }

    @Test fun interruptedSyncDoesNotRenewCredentialsAndClosedOwnersCannotResume() {
        val gate = QmplusLoginAutomationGate()
        val document = gate.beginDocument()
        assertTrue(gate.installed(document, "AUTH_INSTALLED"))
        assertTrue(gate.claimFill(document, "username", true))
        assertTrue(gate.submitted(document, "username", "USERNAME_SUBMITTED"))
        assertTrue(gate.claimFill(document, "password", true, true))
        assertTrue(gate.claimAutomaticSync(document, true))
        gate.interruptedSync()
        assertFalse(gate.claimFill(document, "username", true))
        assertFalse(gate.claimFill(document, "password", true, true))
        assertTrue(gate.claimAutomaticSync(document, true))
        assertFalse(gate.claimAutomaticSync(document, true))
        gate.close()
        gate.interruptedSync()
        assertFalse(gate.claimAutomaticSync(document, true))
    }

    @Test fun accountSelectionHasItsOwnOnceOnlyAckAndPasswordProofCannotCrossDocuments() {
        val gate = QmplusLoginAutomationGate()
        val document = gate.beginDocument()
        assertTrue(gate.installed(document, "AUTH_INSTALLED"))
        assertFalse(gate.claimFill(document, "account", true, false))
        assertTrue(gate.claimFill(document, "account", true, true))
        assertFalse(gate.claimFill(document, "account", true, true))
        assertFalse(gate.claimFill(document, "password", true, true))
        assertFalse(gate.submitted(document, "account", "USERNAME_SUBMITTED"))
        assertTrue(gate.submitted(document, "account", "ACCOUNT_SELECTED"))
        assertTrue(gate.accountSelected(document))
        assertFalse(gate.usernameSubmitted(document))
        assertFalse(gate.claimFill(document, "password", true, false))
        assertTrue(gate.claimFill(document, "password", true, true))
        assertFalse(gate.claimFill(document, "password", true, true))
        assertFalse(gate.claimFill(document, "username", true))
        assertFalse(gate.claimFill(document, "username", true))
        val next = gate.beginDocument()
        assertTrue(gate.installed(next, "AUTH_INSTALLED"))
        assertFalse(gate.accountSelected(next))
        assertFalse(gate.submitted(next, "account", "ACCOUNT_SELECTED"))
        assertFalse(gate.claimFill(next, "account", true, true))
        assertFalse(gate.claimFill(next, "password", true, true))
    }

    @Test fun accountSelectionIsUnavailableAfterAnyUsernameOrPasswordAttempt() {
        val gate = QmplusLoginAutomationGate()
        val document = gate.beginDocument()
        assertTrue(gate.installed(document, "AUTH_INSTALLED"))
        assertTrue(gate.claimFill(document, "username", true))
        assertFalse(gate.claimFill(document, "account", true, true))
        assertTrue(gate.submitted(document, "username", "USERNAME_SUBMITTED"))
        assertTrue(gate.claimFill(document, "password", true, true))
        assertFalse(gate.claimFill(document, "account", true, true))
    }

    @Test fun officialOriginAndPathAreBothRequiredBeforeAnyAuthenticationInspection() {
        assertTrue(QmplusLoginPagePolicy.canInspectAuthenticationPage("https://qmplus.qmul.ac.uk/login/index.php"))
        assertTrue(QmplusLoginPagePolicy.canInspectAuthenticationPage("https://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/saml2"))
        listOf("http://qmplus.qmul.ac.uk/login/index.php", "https://qmplus.qmul.ac.uk.evil.invalid/login/index.php",
            "https://user:secret@qmplus.qmul.ac.uk/login/index.php", "https://qmplus.qmul.ac.uk:444/login/index.php",
            "https://qmplus.qmul.ac.uk/login/index.php#password", "https://qmplus.qmul.ac.uk/course/view.php?id=1",
            "https://login.microsoftonline.com/common/Consent", "https://login.microsoftonline.com/other-tenant/saml2",
            "https://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/SAS/ProcessAuth")
            .forEach { assertFalse(it.substringBefore('?'), QmplusLoginPagePolicy.canInspectAuthenticationPage(it)) }
    }

    @Test fun confirmedSSONavigationIsOptInOnceAndDoesNotRepeatAfterBackOrRevocation() {
        val gate = QmplusLoginAutomationGate()
        val first = gate.beginDocument()
        assertFalse(gate.claimSSO(first, false))
        assertTrue(gate.claimSSO(first, true))
        assertFalse(gate.claimSSO(first, true))
        val back = gate.beginDocument()
        assertFalse(gate.claimSSO(back, true))
        gate.manualInteractionRequired()
        assertFalse(gate.claimSSO(back, true))
        gate.close()
        assertFalse(gate.claimSSO(back, true))
        assertTrue(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/login/index.php"))
        assertTrue(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/?redirect=0"))
        assertTrue(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/"))
        assertFalse(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/login/index.php?next=other"))
        assertFalse(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/?redirect=0&next=other"))
        assertFalse(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/?redirect=1"))
        assertFalse(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk.evil.invalid/login/index.php"))
        assertFalse(QmplusLoginPagePolicy.isSSOEntry("https://qmplus.qmul.ac.uk/login/other.php"))
        assertEquals("https://qmplus.qmul.ac.uk/auth/saml2/login.php", QmplusLoginPagePolicy.SSO_START_URL)
    }

    @Test fun guestFallbackCannotStartSSOAfterAnyCredentialAttemptAndDashboardGetIsOnceOnly() {
        val gate = QmplusLoginAutomationGate()
        val first = gate.beginDocument()
        assertTrue(gate.installed(first, "AUTH_INSTALLED"))
        assertTrue(gate.claimFill(first, "username", true))
        val back = gate.beginDocument()
        assertFalse(gate.claimSSO(back, true))
        assertTrue(gate.claimDashboard(back))
        assertFalse(gate.claimDashboard(back))
        assertFalse(gate.claimDashboard(gate.beginDocument()))
        gate.close()
    }
}
