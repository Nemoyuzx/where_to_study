package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobScheduler
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic fixtures on a disposable emulator. Run separately from tests enabling UI_TEST_MODE. */
@RunWith(AndroidJUnit4::class)
class CourseReminderSchedulingUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val preferences get() = AppPreferences(context)
    private lateinit var snapshot: ScheduleSnapshot

    @Before fun setup() {
        assumeFalse(DailyCourseNotificationRuntimeMode.isUiTesting)
        ensurePrivacyConsentForUiTest()
        instrumentation.uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS").close()
        CourseReminderScheduler.revoke(context)
        DailyCourseSummaryScheduler.revoke(context)
        preferences.clear()
        preferences.automaticTermDetectionEnabled = false
        SecureCredentialStore(context).save(Credentials("course-reminder-fixture", "fictional-password"))
        val target = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply { add(Calendar.DAY_OF_MONTH, 7) }
        val weekday = (target.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
        val monday = (target.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1 - weekday) }
        snapshot = ScheduleSnapshot("2099-2100-1", AcademicScheduleLogic.dateText(monday), "fixture",
            listOf(Course("synthetic", "Synthetic class", "Teacher", "Room", "1–2", listOf(1, 2),
                emptyList(), weekday, 0, 3, "1–4", "08:00-11:25", "source")))
        ScheduleStore(context).save(snapshot)
    }

    @After fun cleanup() {
        CourseReminderScheduler.revoke(context)
        DailyCourseSummaryScheduler.revoke(context)
        SecureCredentialStore(context).clear()
        ScheduleStore(context).clear()
        CourseDeletionStore(context).clear()
        preferences.clear()
    }

    @Test fun malformedStoredOffsetsRecoverAndInvalidEditsDoNotMutateAnything() {
        val storage = context.getSharedPreferences(AppPreferences.PREFERENCES_NAME, Context.MODE_PRIVATE)
        storage.edit().putInt(AppPreferences.COURSE_REMINDER_OFFSETS_KEY, 5).commit()
        assertEquals(listOf(10), preferences.courseReminderOffsets)
        assertFalse(preferences.courseRemindersEnabled)
        assertTrue(CourseReminderScheduler.updateOffsets(context, listOf(10, 5)))
        assertFalse(CourseReminderScheduler.updateOffsets(context, listOf(0)))
        assertEquals(listOf(10, 5), preferences.courseReminderOffsets)
        assertFalse(preferences.dailyCourseNotificationsEnabled)
        assertFalse(preferences.courseRemindersEnabled)
    }

    @Test fun independentEnableReplacesOnlyItsPlanAndOldBroadcastCannotDeliver() {
        assertTrue(DailyCourseSummaryScheduler.authorize(context))
        assertTrue(DailyCourseSummaryScheduler.reconcile(context))
        val dailyToken = preferences.dailyCourseNotificationScheduleToken
        assertTrue(CourseReminderScheduler.authorize(context))
        val old = CourseReminderStateStore(context)
        val token = old.token
        val at = old.scheduledAt
        val revision = CourseReminderScheduler.executionRevision()
        assertTrue(token.isNotEmpty())
        assertTrue(CourseReminderScheduler.updateOffsets(context, listOf(10, 5)))
        assertNotEquals(token, CourseReminderStateStore(context).token)
        assertFalse(CourseReminderScheduler.isExecutionCurrent(revision))
        assertFalse(CourseReminderScheduler.deliver(context, token, at, at))
        assertEquals(dailyToken, preferences.dailyCourseNotificationScheduleToken)
        assertTrue(preferences.dailyCourseNotificationsEnabled)
        assertTrue(CourseReminderScheduler.revoke(context))
        assertFalse(preferences.courseRemindersEnabled)
        assertTrue(preferences.dailyCourseNotificationsEnabled)
        assertEquals("", CourseReminderStateStore(context).token)
    }

    @Test fun refreshDeletionAndClockReconciliationInvalidateOldWorkAndDeliveryIsDeduplicated() {
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        val oldToken = state.token
        val at = state.scheduledAt
        val firstKeys = state.keys
        assertTrue(CourseReminderScheduler.reconcile(context, force = true))
        assertFalse(CourseReminderScheduler.deliver(context, oldToken, at, at))
        val refreshedToken = state.token
        assertTrue(CourseReminderScheduler.deliver(context, refreshedToken, at, at))
        assertTrue(state.delivered.containsAll(firstKeys))
        assertFalse(CourseReminderScheduler.deliver(context, refreshedToken, at, at))
        assertTrue(CourseReminderScheduler.reconcile(context, nowMillis = at - 60_000, force = true))
        assertTrue(state.keys.intersect(firstKeys).isEmpty())
        ScheduleStore(context).save(snapshot.copy(courses = emptyList()))
        assertTrue(CourseReminderScheduler.reconcile(context, force = true))
        assertEquals("", state.token)
        ScheduleStore(context).save(snapshot)
        assertTrue(CourseReminderScheduler.reconcile(context, force = true))
        assertTrue(state.token.isNotEmpty())
    }

    @Test fun accountChangeFailsClosed() {
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        val oldToken = state.token
        val at = state.scheduledAt
        SecureCredentialStore(context).save(Credentials("another-fixture", "fictional-password"))
        assertFalse(CourseReminderScheduler.deliver(context, oldToken, at, at))
        assertTrue(CourseReminderScheduler.reconcile(context))
        assertFalse(preferences.courseRemindersEnabled)
        assertFalse(state.authorized)
        assertEquals("", state.token)
    }

    @Test fun aSinglePostingFailureStillSchedulesTheNextOffsetAndPreservesBothSettings() {
        assertTrue(DailyCourseSummaryScheduler.authorize(context))
        assertTrue(DailyCourseSummaryScheduler.reconcile(context))
        val dailyToken = preferences.dailyCourseNotificationScheduleToken
        assertTrue(CourseReminderScheduler.updateOffsets(context, listOf(10, 5)))
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        val firstAt = state.scheduledAt
        val firstToken = state.token
        assertTrue(CourseReminderScheduler.deliver(context, firstToken, firstAt, firstAt,
            post = { throw IllegalStateException("Synthetic posting failure") }))
        assertEquals(firstAt + 5 * 60_000L, state.scheduledAt)
        assertNotEquals(firstToken, state.token)
        assertTrue(preferences.courseRemindersEnabled)
        assertTrue(preferences.dailyCourseNotificationsEnabled)
        assertEquals(dailyToken, preferences.dailyCourseNotificationScheduleToken)
        var laterPosted = false
        assertTrue(CourseReminderScheduler.deliver(context, state.token, state.scheduledAt, state.scheduledAt,
            post = { laterPosted = true }))
        assertTrue(laterPosted)
    }

    @Test fun temporaryCacheAndKeystoreFailuresRecoverWithoutLosingTheExistingAlarmOrSettings() {
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        val faults = listOf(
            object : CourseReminderPlatform() {
                override fun drafts(context: Context): List<CourseReminderDraft> = error("Synthetic cache read failure")
            },
            object : CourseReminderPlatform() {
                override fun ownerKey(context: Context): String = error("Synthetic keystore unavailable")
            },
        )
        faults.forEach { platform ->
            val original = state.token
            assertTrue(CourseReminderScheduler.reconcile(context, force = true, platform = platform))
            assertEquals(original, state.token)
            assertEquals(1, state.recoveryAttempt)
            assertTrue(context.getSystemService(JobScheduler::class.java).allPendingJobs.any { CourseReminderScheduler.isRecoveryJob(it.id) })
            assertTrue(preferences.courseRemindersEnabled)
            assertTrue(CourseReminderScheduler.recover(context, state.recoveryToken, state.recoveryAttempt, state.recoveryAt))
            assertEquals("", state.recoveryToken)
            assertTrue(state.registered)
        }
    }

    @Test fun actualUnreadableCacheAndEncryptedCredentialFailuresUseRecoveryInsteadOfBeingTreatedAsMissing() {
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        context.openFileOutput("schedule.json", Context.MODE_PRIVATE).bufferedWriter().use { it.write("invalid fixture JSON") }
        assertTrue(CourseReminderScheduler.reconcile(context, force = true))
        assertEquals(1, state.recoveryAttempt)
        assertTrue(preferences.courseRemindersEnabled)
        ScheduleStore(context).save(snapshot)
        assertTrue(CourseReminderScheduler.recover(context, state.recoveryToken, 1, state.recoveryAt))
        context.getSharedPreferences("secure_credentials_v1", Context.MODE_PRIVATE).edit()
            .putString("payload", "invalid fixture ciphertext").commit()
        assertTrue(CourseReminderScheduler.reconcile(context, force = true))
        assertTrue(preferences.courseRemindersEnabled)
        assertTrue(state.authorized)
        assertEquals(1, state.recoveryAttempt)
        SecureCredentialStore(context).save(Credentials("course-reminder-fixture", "fictional-password"))
        assertTrue(CourseReminderScheduler.recover(context, state.recoveryToken, 1, state.recoveryAt))
        assertTrue(state.registered)
    }

    @Test fun alarmRegistrationFailureUsesIndependentRecoveryAndStopsAfterThreeRetries() {
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        val broken = object : CourseReminderPlatform() {
            override fun register(context: Context, exact: Boolean, at: Long, intent: PendingIntent) {
                error("Synthetic alarm registration failure")
            }
        }
        assertTrue(CourseReminderScheduler.reconcile(context, force = true, platform = broken))
        assertFalse(state.registered)
        val campaign = state.recoveryToken
        for (attempt in 1..3) {
            assertEquals(attempt, state.recoveryAttempt)
            val recovered = CourseReminderScheduler.recover(context, campaign, attempt,
                state.recoveryAt - 30_000, platform = broken)
            assertEquals(attempt < 3, recovered)
        }
        assertEquals(3, state.recoveryAttempt)
        assertEquals(0L, state.recoveryAt)
        assertTrue(context.getSystemService(JobScheduler::class.java).allPendingJobs.none { CourseReminderScheduler.isRecoveryJob(it.id) })
        assertTrue(preferences.courseRemindersEnabled)
        assertFalse(preferences.dailyCourseNotificationsEnabled)
        assertTrue(CourseReminderScheduler.reconcile(context, force = true))
        assertTrue(state.registered)
        assertEquals(0, state.recoveryAttempt)
    }

    @Test fun deliveryReadFailureSkipsTheExpiredOffsetAndContinuesWithTheNextFutureSlot() {
        assertTrue(CourseReminderScheduler.updateOffsets(context, listOf(10, 5)))
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        val firstAt = state.scheduledAt
        val originalToken = state.token
        val broken = object : CourseReminderPlatform() {
            override fun drafts(context: Context): List<CourseReminderDraft> = error("Synthetic delivery cache failure")
        }
        assertTrue(CourseReminderScheduler.deliver(context, originalToken, firstAt, firstAt, platform = broken))
        assertEquals(originalToken, state.token)
        assertTrue(state.delivered.isEmpty())
        assertTrue(CourseReminderScheduler.recover(context, state.recoveryToken, state.recoveryAttempt, state.recoveryAt))
        assertEquals(firstAt + 5 * 60_000, state.scheduledAt)
        assertTrue(state.delivered.isEmpty())
        assertFalse(CourseReminderScheduler.deliver(context, originalToken, firstAt, firstAt + 60_000))
    }

    @Test fun disabledOrChangedPreferencesAndAccountsInvalidateRecoveryTokens() {
        val broken = object : CourseReminderPlatform() {
            override fun drafts(context: Context): List<CourseReminderDraft> = error("Synthetic cache failure")
        }
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        assertTrue(CourseReminderScheduler.reconcile(context, force = true, platform = broken))
        var token = state.recoveryToken
        assertTrue(CourseReminderScheduler.updateOffsets(context, listOf(5)))
        assertFalse(CourseReminderScheduler.recover(context, token, 1))
        assertTrue(CourseReminderScheduler.reconcile(context, force = true, platform = broken))
        token = state.recoveryToken
        assertTrue(CourseReminderScheduler.revoke(context))
        assertFalse(CourseReminderScheduler.recover(context, token, 1))
        assertTrue(CourseReminderScheduler.authorize(context))
        assertTrue(CourseReminderScheduler.reconcile(context, force = true, platform = broken))
        token = state.recoveryToken
        SecureCredentialStore(context).save(Credentials("changed-fixture", "fictional-password"))
        assertTrue(CourseReminderScheduler.recover(context, token, 1, state.recoveryAt))
        assertFalse(preferences.courseRemindersEnabled)
        assertFalse(state.authorized)
        assertEquals("", state.recoveryToken)
    }

    @Test fun concurrentClearAndDeliveryCannotLeaveAnOldAccountNotificationOrPlan() {
        assertTrue(CourseReminderScheduler.authorize(context))
        val state = CourseReminderStateStore(context)
        val token = state.token
        val at = state.scheduledAt
        val begin = CountDownLatch(1)
        val workers = Executors.newFixedThreadPool(2)
        try {
            val delivery = workers.submit<Boolean> { begin.await(); CourseReminderScheduler.deliver(context, token, at, at) }
            val clear = workers.submit<Boolean> {
                begin.await()
                val revoked = CourseReminderScheduler.revoke(context)
                LocalDataCoordinator.clear { SecureCredentialStore(context).clear(); ScheduleStore(context).clear() }
                revoked
            }
            begin.countDown()
            delivery.get(5, TimeUnit.SECONDS)
            assertTrue(clear.get(5, TimeUnit.SECONDS))
            assertFalse(CourseReminderScheduler.deliver(context, token, at, at))
            assertEquals("", state.token)
            assertFalse(preferences.courseRemindersEnabled)
            assertTrue(context.getSystemService(NotificationManager::class.java).activeNotifications
                .none { it.tag?.startsWith("course_reminder:") == true })
        } finally { workers.shutdownNow() }
    }

    @Test fun permissionResultRoutesToPreClassOnlyAndSurvivesActivityRecreation() {
        // The pending request is restored exactly as it is after an OS permission dialog recreation.
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)).use { scenario ->
            scenario.onActivity { activity ->
                val pending = MainActivity::class.java.getDeclaredField("notificationPermissionRequestPending").apply { isAccessible = true }
                val kind = MainActivity::class.java.getDeclaredField("notificationPermissionKind").apply { isAccessible = true }
                val account = MainActivity::class.java.getDeclaredField("notificationPermissionAccountKey").apply { isAccessible = true }
                pending.setBoolean(activity, true)
                kind.set(activity, CourseNotificationKind.PRE_CLASS)
                account.set(activity, CourseReminderScheduler.accountKey(context))
            }
            scenario.recreate()
            scenario.onActivity { activity ->
                activity.onRequestPermissionsResult(4108, arrayOf(Manifest.permission.POST_NOTIFICATIONS), intArrayOf(0))
                assertTrue(preferences.courseRemindersEnabled)
                assertFalse(preferences.dailyCourseNotificationsEnabled)
                assertTrue(activity.clearDailyCourseNotificationsForAccountChange())
                activity.onRequestPermissionsResult(4108, arrayOf(Manifest.permission.POST_NOTIFICATIONS), intArrayOf(0))
                assertFalse(preferences.courseRemindersEnabled)
                assertFalse(preferences.dailyCourseNotificationsEnabled)
            }
        }
    }
}
