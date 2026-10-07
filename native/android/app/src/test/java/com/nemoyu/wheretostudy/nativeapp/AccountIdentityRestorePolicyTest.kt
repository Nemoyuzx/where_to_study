package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountIdentityRestorePolicyTest {
    @Test fun pristineEmptyFieldReceivesSavedIdentityEvenWhenFocused() {
        // Focus deliberately is not an input: focusing an empty cold-start field must not clear Save's identity.
        assertTrue(AccountIdentityRestorePolicy("").replace("", "20260001"))
    }

    @Test fun actualAccountEditIsNeverOverwritten() {
        val policy = AccountIdentityRestorePolicy("")
        policy.onTextChanged("20260002", applyingLoadedIdentity = false)
        assertFalse(policy.replace("20260002", "20260001"))
    }

    @Test fun explicitClearIsNeverOverwritten() {
        val policy = AccountIdentityRestorePolicy("20260001")
        policy.onTextChanged("", applyingLoadedIdentity = false)
        assertFalse(policy.replace("", "20260001"))
    }

    @Test fun typingThenReturningToInitialEmptyTextStillOwnsTheField() {
        val policy = AccountIdentityRestorePolicy("")
        policy.onTextChanged("2", applyingLoadedIdentity = false)
        policy.onTextChanged("", applyingLoadedIdentity = false)
        // Attach callbacks reuse this policy; originalText equality cannot discard the prior edit.
        assertFalse(policy.replace("", "20260001"))
        assertFalse(policy.replace("", "20260001"))
    }

    @Test fun restoredDraftIncludingAnEmptyDraftIsNeverOverwritten() {
        assertFalse(AccountIdentityRestorePolicy("").replace("20260002", "20260001", draft = true))
        assertFalse(AccountIdentityRestorePolicy("").replace("", "20260001", draft = true))
    }

    @Test fun matchingIdentityDoesNotResetTextOrSelection() {
        val policy = AccountIdentityRestorePolicy("20260001")
        policy.onTextChanged("20260001", applyingLoadedIdentity = false)
        assertFalse(policy.replace("20260001", "20260001"))
        assertTrue(policy.replace("20260001", "20260002"))
        assertFalse(AccountIdentityRestorePolicy("").replace("", ""))
    }

    @Test fun laterIdentityCanRefreshAnUneditedMetadataValue() {
        val policy = AccountIdentityRestorePolicy("")
        assertTrue(policy.replace("", "20260001"))
        policy.onTextChanged("20260001", applyingLoadedIdentity = true)
        assertTrue(policy.replace("20260001", "20260002"))
    }

    private fun AccountIdentityRestorePolicy.replace(current: String, restored: String, draft: Boolean = false) =
        shouldReplaceText(current, restored, draft)
}
