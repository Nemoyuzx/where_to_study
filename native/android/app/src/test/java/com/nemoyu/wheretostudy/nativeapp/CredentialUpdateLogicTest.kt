package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CredentialUpdateLogicTest {
    @Test
    fun blankPasswordPreservesOnlyTheSameSavedAccount() {
        val saved = Credentials("20260001", "local-secret")

        assertEquals(
            saved,
            CredentialUpdateLogic.resolve(saved, " 20260001 ", ""),
        )
        assertThrows(CredentialUpdateException::class.java) {
            CredentialUpdateLogic.resolve(saved, "20260002", "")
        }
    }

    @Test
    fun aNewPasswordCanReplaceOrCreateCredentials() {
        assertEquals(
            Credentials("20260002", "new-secret"),
            CredentialUpdateLogic.resolve(
                saved = Credentials("20260001", "old-secret"),
                requestedAccount = "20260002",
                enteredPassword = "new-secret",
            ),
        )
    }

    @Test
    fun clearingBothFieldsDoesNotCarryAnOldPasswordToAnEmptyAccount() {
        assertEquals(
            Credentials("", ""),
            CredentialUpdateLogic.resolve(Credentials("20260001", "old-secret"), "", ""),
        )
    }

    @Test
    fun aPasswordWithoutAnAccountIsRejected() {
        assertThrows(CredentialUpdateException::class.java) {
            CredentialUpdateLogic.resolve(null, "  ", "new-secret")
        }
    }

    @Test
    fun accountChangesAreDetectedWithoutTreatingPasswordChangesAsAnAccountChange() {
        val saved = Credentials("20260001", "old-secret")

        assertEquals(
            false,
            CredentialUpdateLogic.changesAccount(saved, Credentials("20260001", "new-secret")),
        )
        assertEquals(
            true,
            CredentialUpdateLogic.changesAccount(saved, Credentials("20260002", "new-secret")),
        )
        assertEquals(
            true,
            CredentialUpdateLogic.changesAccount(saved, Credentials("", "")),
        )
    }
}
