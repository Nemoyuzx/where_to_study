package com.nemoyu.wheretostudy.nativeapp

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Run only on a disposable emulator. No real credentials or authenticated network requests. */
@RunWith(AndroidJUnit4::class)
class DailyCourseSchedulingRecoveryUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val scheduler = context.getSystemService(JobScheduler::class.java)

    private fun fixture(operation: (AppPreferences) -> Unit) {
        check(Build.HARDWARE in setOf("ranchu", "goldfish"))
        instrumentation.uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS").close()
        instrumentation.runOnMainSync {
            val preferences = AppPreferences(context)
            try {
                ensurePrivacyConsentForUiTest()
                preferences.clear()
                preferences.automaticTermDetectionEnabled = false
                SecureCredentialStore(context).save(Credentials("widget-scheduling-fixture", "not-a-real-password"))
                ScheduleStore(context).save(ScheduleSnapshot("fixture", "2026-08-31", "fixture", emptyList()))
                assertTrue(DailyCourseSummaryScheduler.authorize(context))
                operation(preferences)
            } finally {
                DailyCourseSummaryScheduler.revoke(context)
                SecureCredentialStore(context).clear()
                ScheduleStore(context).clear()
                preferences.clear()
            }
        }
    }

    private fun jobs() = scheduler.allPendingJobs.filter { DailyCourseSummaryScheduler.isManagedJob(it.id) }
    private fun token(job: JobInfo) = job.extras.getString(DailyCourseSummaryScheduler.JOB_TOKEN).orEmpty()
    private fun at(job: JobInfo) = job.extras.getLong(DailyCourseSummaryScheduler.JOB_SCHEDULED_AT)

    @Test
    fun savingUnchangedTimeKeepsExecutionAndStaleCompletionCannotReplaceNewJob() = fixture { preferences ->
        preferences.dailyCourseNotificationMinutes = 450
        assertTrue(DailyCourseSummaryScheduler.reconcile(context))
        val original = jobs().single()
        val revision = DailyCourseSummaryScheduler.executionRevision()
        val generation = LocalDataCoordinator.snapshot()
        assertTrue(DailyCourseSummaryScheduler.updateTime(context, 450))
        assertEquals(revision, DailyCourseSummaryScheduler.executionRevision())
        assertEquals(token(original), token(jobs().single()))
        assertTrue(DailyCourseSummaryScheduler.updateTime(context, 451))
        val changed = jobs().single()
        var staleDelivered = false
        DailyCourseSummaryScheduler.withCurrentExecution(context, token(original), revision, generation) { staleDelivered = true }
        assertFalse(staleDelivered)
        assertTrue(DailyCourseSummaryScheduler.scheduleAfterCompletion(context, original.id,
            token(original), revision, generation))
        assertEquals(token(changed), token(jobs().single()))
    }

    @Test
    fun midnightResumeAndDateReconciliationKeepTodaysJobAndToken() = fixture { preferences ->
        val midnight = midnight()
        preferences.dailyCourseNotificationMinutes = 0
        assertTrue(DailyCourseSummaryScheduler.reconcileAt(context, midnight - 1_000))
        val original = jobs().single()
        assertTrue(DailyCourseSummaryScheduler.reconcileAt(context, midnight))
        assertTrue(DailyCourseSummaryScheduler.reconcileAt(context, midnight + 20 * 60_000))
        assertEquals(token(original), token(jobs().single()))
        assertEquals(midnight, at(jobs().single()))
        // A real wall-clock adjustment changes elapsed-time constraints even for the same date.
        assertTrue(DailyCourseSummaryScheduler.reconcileAt(context, midnight + 10 * 60_000, forceReschedule = true))
        assertNotEquals(token(original), token(jobs().single()))
        assertEquals(midnight, at(jobs().single()))
        preferences.dailyCourseNotificationDeliveredDay = DailyCourseSummaryLogic.dayKey(midnight)
        assertTrue(DailyCourseSummaryScheduler.reconcileAt(context, midnight + 10 * 60_000))
        assertEquals(midnight + 86_400_000, at(jobs().single()))
    }

    @Test
    fun endOfDayDeadlineAndSystemStopRetainDailyChainWithoutRevivingOldPlan() = fixture { preferences ->
        val midnight = midnight()
        val late = midnight - 60_000
        preferences.dailyCourseNotificationMinutes = 1439
        assertTrue(DailyCourseSummaryScheduler.reconcileAt(context, late + 20_000))
        val old = jobs().single()
        assertEquals(late, at(old))
        assertEquals(39_999L, old.maxExecutionDelayMillis)
        val revision = DailyCourseSummaryScheduler.executionRevision()
        val generation = LocalDataCoordinator.snapshot()
        assertTrue(DailyCourseSummaryScheduler.retryAfterStop(context, old.id, 1439, late,
            token(old), revision, generation, false, late + 30_000))
        assertFalse(DailyCourseSummaryScheduler.retryAfterStop(context, old.id, 1439, late,
            token(old), revision, generation, false, midnight))
        scheduler.cancel(old.id) // Emulate JobScheduler removing the stopped one-shot after onStopJob returns.
        val next = jobs().single()
        assertEquals(midnight + 86_340_000, at(next))
        assertTrue(DailyCourseSummaryScheduler.updateTime(context, 60))
        val changed = jobs().single()
        assertFalse(DailyCourseSummaryScheduler.retryAfterStop(context, next.id, 1439, at(next),
            token(next), revision, generation, false, midnight))
        assertEquals(token(changed), token(jobs().single()))
        assertTrue(DailyCourseSummaryScheduler.revoke(context))
        assertFalse(DailyCourseSummaryScheduler.retryAfterStop(context, changed.id, 60, at(changed),
            token(changed), DailyCourseSummaryScheduler.executionRevision(), generation, false, midnight))
        assertTrue(jobs().isEmpty())
    }

    private fun midnight(): Long = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).run {
        set(2030, Calendar.JANUARY, 1, 0, 0, 0)
        set(Calendar.MILLISECOND, 0)
        timeInMillis
    }
}
