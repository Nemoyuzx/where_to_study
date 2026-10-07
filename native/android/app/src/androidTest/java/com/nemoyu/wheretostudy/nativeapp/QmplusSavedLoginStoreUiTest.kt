package com.nemoyu.wheretostudy.nativeapp

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.ExecutorService

/** Synthetic secrets in a separate Keystore/file domain; no browser, network, or user credentials. */
@RunWith(AndroidJUnit4::class)
class QmplusSavedLoginStoreUiTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun disablingSavedLoginRetiresTheLoginOwnerButPreservesCourseCacheAndOfficialSessionEvenAcrossFeatureOff() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val store = QmplusCredentialStore(context, "test_qm_saved_login_disable")
        store.clear()
        val prefs = context.getSharedPreferences("qm_saved_login_disable_test_only", android.content.Context.MODE_PRIVATE)
        assertTrue(prefs.edit().clear().commit())
        val cached = QmplusSnapshot("2026-10-03T10:00:00Z", emptyList(), emptyList(), emptyList())
        assertTrue(prefs.edit().putString("snapshot_v1", String(QmplusSnapshotCodec.encode(cached), StandardCharsets.UTF_8)).commit())
        val password = "synthetic-disable-only".toCharArray()
        val loaded = CountDownLatch(1); val held = CountDownLatch(1); val release = CountDownLatch(1); val completed = CountDownLatch(1)
        val result = AtomicReference<Result<Unit>>()
        lateinit var repository: QmplusRepository
        var repositoryCreated = false
        try {
            store.save("synthetic@example.invalid", password, true, store.status().revision)
            instrumentation.runOnMainSync {
                repository = QmplusRepository(context, prefs, credentialStoreOverride = store)
                repositoryCreated = true
                repository.addObserver(loaded) { if (!repository.isLoading) loaded.countDown() }
            }
            assertTrue(loaded.await(5, TimeUnit.SECONDS))
            val worker = QmplusRepository::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(repository) as ExecutorService
            worker.execute { held.countDown(); check(release.await(5, TimeUnit.SECONDS)) }
            assertTrue(held.await(5, TimeUnit.SECONDS))
            instrumentation.runOnMainSync {
                assertNotNull(repository.beginConnection())
                repository.disableSavedLogin { result.set(it); completed.countDown() }
                assertNull(repository.connection)
                assertFalse(repository.savedLoginStatus.enabled)
                assertTrue(repository.setFeatureEnabled(false))
            }
            release.countDown()
            assertTrue(completed.await(5, TimeUnit.SECONDS))
            assertTrue(result.get().isSuccess)
            assertFalse(store.status().enabled)
            instrumentation.runOnMainSync {
                assertFalse(repository.isSavingLogin)
                assertEquals(cached, repository.snapshot)
                assertFalse(repository.cookiesNeedClearing)
                assertNull(repository.pendingCookieClearAttempt)
                assertEquals(cached, QmplusSnapshotCodec.decode(prefs.getString("snapshot_v1", null)!!.toByteArray(StandardCharsets.UTF_8)))
            }
        } finally {
            release.countDown(); password.fill('\u0000')
            if (repositoryCreated) instrumentation.runOnMainSync { repository.close() }
            store.clear(); assertTrue(prefs.edit().clear().commit())
        }
    }

    @Test fun explicitOptInEncryptsBothFieldsAndFreshStoreReadsOnlyTheSavedRevision() {
        val domain = "test_qm_saved_login_crypto"
        val store = QmplusCredentialStore(context, domain)
        store.clear()
        try {
            val initial = store.status()
            assertFalse(initial.enabled)
            val secret = "synthetic-qm-secret-not-real".toCharArray()
            try {
                assertThrows(IllegalArgumentException::class.java) { store.save("synthetic@example.invalid", secret, false, initial.revision) }
                assertFalse(store.status().enabled)
                val saved = store.save("synthetic@example.invalid", secret, true, initial.revision)
                val disk = File(context.noBackupFilesDir, "$domain.bin").readBytes()
                val encoded = String(disk, StandardCharsets.ISO_8859_1)
                assertFalse(encoded.contains("synthetic@example.invalid"))
                assertFalse(encoded.contains("synthetic-qm-secret-not-real"))
                assertTrue(disk.size <= QmplusCredentialLimits.MAXIMUM_RECORD_BYTES)
                assertNull(QmplusCredentialStore(context, domain).load(initial.revision))
                val login = checkNotNull(QmplusCredentialStore(context, domain).load(saved.revision))
                try {
                    assertEquals("synthetic@example.invalid", login.account)
                    assertArrayEquals(secret, login.password)
                    assertEquals("QmplusSavedLogin([redacted])", login.toString())
                } finally { login.erase(); assertTrue(login.password.all { it == '\u0000' }) }
            } finally { secret.fill('\u0000') }
        } finally { store.clear() }
    }

    @Test fun clearTombstoneRejectsDelayedDecryptAndDelayedSaveAcrossFreshOwners() {
        val domain = "test_qm_saved_login_clear"
        val store = QmplusCredentialStore(context, domain)
        store.clear()
        val secret = "synthetic-only".toCharArray()
        try {
            val saved = store.save("synthetic@example.invalid", secret, true, store.status().revision)
            val otherOwner = QmplusCredentialStore(context, domain)
            val cleared = otherOwner.clear()
            assertFalse(cleared.enabled)
            assertTrue(cleared.revision > saved.revision)
            assertNull(store.load(saved.revision))
            assertThrows(IllegalStateException::class.java) { store.save("synthetic@example.invalid", secret, true, saved.revision) }
            assertFalse(QmplusCredentialStore(context, domain).status().enabled)
        } finally { secret.fill('\u0000'); store.clear() }
    }

    @Test fun delayedCredentialRemovalCannotDeleteAReplacementAuthorization() {
        val store = QmplusCredentialStore(context, "test_qm_expected_clear")
        store.clear()
        val password = "synthetic-generation-only".toCharArray()
        try {
            val old = store.save("old@example.invalid", password, true, store.status().revision)
            val replacement = store.save("new@example.invalid", password, true, old.revision)
            assertThrows(IllegalStateException::class.java) { store.clear(expectedRevision = old.revision) }
            assertEquals(replacement, store.status())
            assertFalse(store.clear(expectedRevision = replacement.revision).enabled)
        } finally { password.fill('\u0000'); store.clear() }
    }

    @Test fun separateDomainsNeverReuseOrClearEachOthersPasswords() {
        val first = QmplusCredentialStore(context, "test_qm_saved_login_first")
        val second = QmplusCredentialStore(context, "test_qm_saved_login_second")
        first.clear(); second.clear()
        val secret = "synthetic-second-domain".toCharArray()
        try {
            val saved = second.save("second@example.invalid", secret, true, second.status().revision)
            first.clear()
            assertFalse(first.status().enabled)
            assertTrue(second.status().enabled)
            val login = checkNotNull(second.load(saved.revision))
            try { assertArrayEquals(secret, login.password) } finally { login.erase() }
        } finally { secret.fill('\u0000'); first.clear(); second.clear() }
    }

    @Test fun queuedRepositorySaveCannotReviveAnExternallyClearedCredentialGeneration() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val store = QmplusCredentialStore(context, "test_qm_saved_login_late")
        store.clear()
        val prefs = context.getSharedPreferences("qm_saved_login_repository_test_only", android.content.Context.MODE_PRIVATE)
        assertTrue(prefs.edit().clear().commit())
        val loaded = CountDownLatch(1); val entered = CountDownLatch(1); val release = CountDownLatch(1); val completed = CountDownLatch(1)
        val success = AtomicBoolean(true)
        lateinit var repository: QmplusRepository
        instrumentation.runOnMainSync {
            repository = QmplusRepository(context, prefs, beforeSavePublication = {
                entered.countDown(); check(release.await(5, TimeUnit.SECONDS))
            }, credentialStoreOverride = store)
            repository.addObserver(loaded) { if (!repository.isLoading) loaded.countDown() }
            if (!repository.isLoading) loaded.countDown()
        }
        val password = "synthetic-late-save".toCharArray()
        try {
            assertTrue(loaded.await(5, TimeUnit.SECONDS))
            instrumentation.runOnMainSync {
                repository.saveLogin("synthetic@example.invalid", password, true) {
                    success.set(it.isSuccess); completed.countDown()
                }
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            // A fresh owner stands in for the other app process; no global test reset.
            QmplusCredentialStore(context, "test_qm_saved_login_late").clear()
            release.countDown()
            assertTrue(completed.await(5, TimeUnit.SECONDS))
            assertFalse(success.get())
            assertFalse(store.status().enabled)
            assertFalse(repository.savedLoginStatus.enabled)
        } finally {
            password.fill('\u0000'); release.countDown()
            instrumentation.runOnMainSync { repository.close() }
            store.clear(); assertTrue(prefs.edit().clear().commit())
        }
    }

    // Regression specification added after local automated testing was stopped.
    // Not executed for this change; uses only a synthetic, isolated credential domain.
    @Test fun identicalAuthorizedResavePreservesCredentialBytesAndDoesNotRequestCookieClearing() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val domain = "test_qm_identical_resave"
        val store = QmplusCredentialStore(context, domain)
        store.clear()
        val prefs = context.getSharedPreferences("qm_identical_resave_test_only", android.content.Context.MODE_PRIVATE)
        assertTrue(prefs.edit().clear().commit())
        val password = "synthetic-identical-only".toCharArray()
        val loaded = CountDownLatch(1); val completed = CountDownLatch(1)
        val result = AtomicReference<Result<Unit>>()
        var repository: QmplusRepository? = null
        try {
            val saved = store.save("synthetic@example.invalid", password, true, store.status().revision)
            val bytes = File(context.noBackupFilesDir, "$domain.bin").readBytes()
            instrumentation.runOnMainSync {
                val current = QmplusRepository(context, prefs, credentialStoreOverride = store)
                repository = current
                current.addObserver(loaded) { if (!current.isLoading) loaded.countDown() }
                if (!current.isLoading) loaded.countDown()
            }
            assertTrue(loaded.await(5, TimeUnit.SECONDS))
            instrumentation.runOnMainSync {
                assertEquals(saved, checkNotNull(repository).savedLoginStatus)
                checkNotNull(repository).saveLogin(" synthetic@example.invalid ", password, true) {
                    result.set(it); completed.countDown()
                }
            }
            assertTrue(completed.await(5, TimeUnit.SECONDS))
            assertTrue(checkNotNull(result.get()).isSuccess)
            instrumentation.runOnMainSync {
                assertEquals(saved, checkNotNull(repository).savedLoginStatus)
                assertFalse(checkNotNull(repository).cookiesNeedClearing)
                assertFalse(checkNotNull(repository).isClearingSession)
                assertNull(checkNotNull(repository).pendingCookieClearAttempt)
            }
            assertEquals(saved, store.status())
            assertArrayEquals(bytes, File(context.noBackupFilesDir, "$domain.bin").readBytes())
            assertTrue(prefs.all.isEmpty())
        } finally {
            password.fill('\u0000')
            instrumentation.runOnMainSync { repository?.close() }
            store.clear(); assertTrue(prefs.edit().clear().commit())
        }
    }

    @Test fun actualCredentialWorkerReturnsOnlyAccountAndErasesPasswordAtCallbackEnd() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val store = QmplusCredentialStore(context, "test_qm_auth_worker_delivery")
        store.clear()
        val secret = "synthetic-worker-only".toCharArray()
        val accountDelivered = CountDownLatch(1); val passwordDelivered = CountDownLatch(1)
        val account = AtomicReference<String?>(); val login = AtomicReference<QmplusSavedLogin?>()
        var worker: QmplusAuthCredentialWorker? = null
        try {
            val saved = store.save("synthetic@example.invalid", secret, true, store.status().revision)
            instrumentation.runOnMainSync {
                val current = QmplusAuthCredentialWorker(store); worker = current
                current.account(saved.revision) { account.set(it); accountDelivered.countDown() }
            }
            assertTrue(accountDelivered.await(5, TimeUnit.SECONDS))
            assertEquals("synthetic@example.invalid", account.get())
            instrumentation.runOnMainSync {
                checkNotNull(worker).password(saved.revision) { value ->
                    login.set(value)
                    assertArrayEquals(secret, checkNotNull(value).password)
                    passwordDelivered.countDown()
                }
            }
            assertTrue(passwordDelivered.await(5, TimeUnit.SECONDS))
            // A main-thread barrier observes callback completion, not an arbitrary sleep.
            instrumentation.runOnMainSync { assertTrue(checkNotNull(login.get()).password.all { it == '\u0000' }) }
        } finally { instrumentation.runOnMainSync { worker?.close() }; secret.fill('\u0000'); store.clear() }
    }

    @Test fun closeBeforeMainDeliverySuppressesCredentialCallbackAndWithdrawalDeniesAuthorization() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val store = QmplusCredentialStore(context, "test_qm_auth_worker_closed")
        store.clear()
        val secret = "synthetic-closed-only".toCharArray()
        val callbacks = AtomicInteger()
        var liveWorker: QmplusAuthCredentialWorker? = null
        try {
            val saved = store.save("synthetic@example.invalid", secret, true, store.status().revision)
            instrumentation.runOnMainSync {
                val worker = QmplusAuthCredentialWorker(store)
                worker.password(saved.revision) { callbacks.incrementAndGet() }
                // A queued callback cannot run inside this same main-thread task.
                worker.close()
            }
            instrumentation.runOnMainSync { assertEquals(0, callbacks.get()) }
            store.clear()
            val denied = CountDownLatch(1); val permitted = AtomicBoolean(true)
            instrumentation.runOnMainSync {
                val worker = QmplusAuthCredentialWorker(store); liveWorker = worker
                worker.authorized(saved.revision) { permitted.set(it); denied.countDown() }
            }
            assertTrue(denied.await(5, TimeUnit.SECONDS))
            assertFalse(permitted.get())
        } finally { instrumentation.runOnMainSync { liveWorker?.close() }; secret.fill('\u0000'); store.clear() }
    }
}
