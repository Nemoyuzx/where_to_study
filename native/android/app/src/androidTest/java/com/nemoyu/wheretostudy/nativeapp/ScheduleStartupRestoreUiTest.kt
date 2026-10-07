package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.ContextWrapper
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Local synthetic cache only. No browser, network, password writes, or real account changes. */
@RunWith(AndroidJUnit4::class)
class ScheduleStartupRestoreUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun mainThreadConstructionReturnsWhileCacheIoIsBlockedAndPublishesOnMainAfterward() = fixture { context ->
        val cached = seed(context)
        val reading = CountDownLatch(1); val release = CountDownLatch(1); val restored = CountDownLatch(1)
        val readOnMain = AtomicBoolean(true)
        lateinit var repository: ScheduleRepository
        instrumentation.runOnMainSync {
            repository = ScheduleRepository(context, SecureCredentialStore(context), AppPreferences(context), beforeCacheRead = {
                readOnMain.set(Looper.myLooper() == Looper.getMainLooper())
                reading.countDown(); check(release.await(5, TimeUnit.SECONDS))
            })
            repository.whenCacheRestored {
                assertEquals(Looper.getMainLooper(), Looper.myLooper())
                assertEquals(cached, repository.schedule)
                restored.countDown()
            }
            assertNull(repository.schedule)
        }
        try {
            assertTrue(reading.await(5, TimeUnit.SECONDS))
            assertFalse(readOnMain.get())
            assertEquals(1L, restored.count)
            release.countDown()
            assertTrue(restored.await(5, TimeUnit.SECONDS))
        } finally { release.countDown(); instrumentation.runOnMainSync { repository.close() } }
    }

    @Test fun localClearDuringQueuedRestoreCannotPublishTheEarlierSchedule() = fixture { context ->
        seed(context)
        val reading = CountDownLatch(1); val release = CountDownLatch(1); val restored = CountDownLatch(1)
        lateinit var repository: ScheduleRepository
        instrumentation.runOnMainSync {
            repository = ScheduleRepository(context, SecureCredentialStore(context), AppPreferences(context), beforeCacheRead = {
                reading.countDown(); check(release.await(5, TimeUnit.SECONDS))
            })
            repository.whenCacheRestored { assertNull(repository.schedule); restored.countDown() }
        }
        try {
            assertTrue(reading.await(5, TimeUnit.SECONDS))
            repository.clearLocalData()
            release.countDown()
            assertTrue(restored.await(5, TimeUnit.SECONDS))
            assertNull(ScheduleStore(context).load())
        } finally { release.countDown(); instrumentation.runOnMainSync { repository.close() } }
    }

    @Test fun classroomConstructionAndRefreshWaitForCacheOffMainBeforeConsideringNetwork() = fixture { context ->
        val cached = ClassroomsCache(AppMetadata.classroomsCacheVersion, ClassroomRepository.today(), "synthetic-cache", true, "synthetic", emptyList())
        ClassroomStore(context).save(cached)
        val reading = CountDownLatch(1); val release = CountDownLatch(1); val completed = CountDownLatch(1)
        val readOnMain = AtomicBoolean(true)
        lateinit var repository: ClassroomRepository
        instrumentation.runOnMainSync {
            repository = ClassroomRepository(context, SecureCredentialStore(context), beforeCacheRead = {
                readOnMain.set(Looper.myLooper() == Looper.getMainLooper())
                reading.countDown(); check(release.await(5, TimeUnit.SECONDS))
            })
            assertNull(repository.cache)
            repository.refresh(force = false) { result ->
                assertEquals(Looper.getMainLooper(), Looper.myLooper())
                // This fixture has no credentials. Success proves a current
                // restored cache was considered before any network attempt.
                assertEquals(cached, result.getOrThrow())
                assertEquals(cached, repository.cache)
                completed.countDown()
            }
        }
        try {
            assertTrue(reading.await(5, TimeUnit.SECONDS)); assertFalse(readOnMain.get())
            assertEquals(1L, completed.count)
            release.countDown()
            assertTrue(completed.await(5, TimeUnit.SECONDS))
        } finally { release.countDown(); instrumentation.runOnMainSync { repository.close() } }
    }

    @Test fun clearingWhileClassroomCacheIsQueuedInvalidatesTheDeferredRefreshToo() = fixture { context ->
        ClassroomStore(context).save(ClassroomsCache(AppMetadata.classroomsCacheVersion, ClassroomRepository.today(), "synthetic-cache", true, "synthetic", emptyList()))
        val reading = CountDownLatch(1); val release = CountDownLatch(1); val completed = CountDownLatch(1)
        lateinit var repository: ClassroomRepository
        instrumentation.runOnMainSync {
            repository = ClassroomRepository(context, SecureCredentialStore(context), beforeCacheRead = {
                reading.countDown(); check(release.await(5, TimeUnit.SECONDS))
            })
            repository.refresh(force = false) { result ->
                assertTrue(result.exceptionOrNull() is LocalDataInvalidatedException)
                assertNull(repository.cache)
                completed.countDown()
            }
        }
        try {
            assertTrue(reading.await(5, TimeUnit.SECONDS))
            repository.clearLocalData()
            release.countDown()
            assertTrue(completed.await(5, TimeUnit.SECONDS))
        } finally { release.countDown(); instrumentation.runOnMainSync { repository.close() } }
    }

    @Test fun aCanceledSessionCannotReachClassroomSchedulerCredentialOrDiskReads() = fixture { context ->
        val noIo = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int): android.content.SharedPreferences =
                error("Canceled scheduling must not read preferences or credentials")
        }
        assertFalse(DailyClassroomRefreshScheduler.ensureScheduled(noIo, isActive = { false }))
    }

    private fun seed(context: Context): ScheduleSnapshot {
        val cached = ScheduleSnapshot("2026-2027-1", "2026-09-07", "synthetic-cache", emptyList())
        AppPreferences(context).automaticTermDetectionEnabled = false
        ScheduleStore(context).save(cached)
        return cached
    }

    private fun fixture(operation: (Context) -> Unit) {
        val base = instrumentation.targetContext
        val directory = Files.createTempDirectory(base.cacheDir.toPath(), "schedule-startup-test-").toFile()
        val prefix = directory.name
        val preferences = mutableSetOf<String>()
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir(): File = directory
            override fun getSharedPreferences(name: String, mode: Int): android.content.SharedPreferences {
                preferences += "$prefix.$name"
                return base.getSharedPreferences("$prefix.$name", mode)
            }
        }
        try { operation(context) } finally {
            preferences.forEach { base.getSharedPreferences(it, Context.MODE_PRIVATE).edit().clear().commit() }
            directory.deleteRecursively()
        }
    }
}
