package com.nemoyu.wheretostudy.nativeapp

import android.app.job.JobScheduler
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test
import org.junit.runner.RunWith

/** Run on a disposable emulator, before tests that activate UI_TEST_MODE. Never uses a real account. */
@RunWith(AndroidJUnit4::class)
class DailyCourseTimeSchedulingUiTest {
    @Test
    fun timeChangeReplacesPendingJobAndInvalidatesOldExecutionWhileKeepingDeduplication() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assumeFalse("Run this scheduler test in its own instrumentation process", DailyCourseNotificationRuntimeMode.isUiTesting)
        ensurePrivacyConsentForUiTest()
        instrumentation.uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS").close()
        val preferences = AppPreferences(context)
        val scheduler = context.getSystemService(JobScheduler::class.java)
        try {
            preferences.clear()
            preferences.automaticTermDetectionEnabled = false
            SecureCredentialStore(context).save(Credentials("reminder-test-only", "fictional-password"))
            ScheduleStore(context).save(ScheduleSnapshot("test-term", "2026-09-07", "test", emptyList()))
            assertTrue(DailyCourseSummaryScheduler.authorize(context))
            assertTrue(DailyCourseSummaryScheduler.reconcile(context))
            val original = scheduler.allPendingJobs.single { DailyCourseSummaryScheduler.isManagedJob(it.id) }
            assertEquals(450, original.extras.getInt(DailyCourseSummaryScheduler.JOB_MINUTES))
            val revision = DailyCourseSummaryScheduler.executionRevision()
            val delivered = DailyCourseSummaryLogic.dayKey(System.currentTimeMillis())
            preferences.dailyCourseNotificationDeliveredDay = delivered
            assertTrue(DailyCourseSummaryScheduler.updateTime(context, 1439))
            val updated = scheduler.allPendingJobs.single { DailyCourseSummaryScheduler.isManagedJob(it.id) }
            assertEquals(1439, updated.extras.getInt(DailyCourseSummaryScheduler.JOB_MINUTES))
            assertNotEquals(original.extras.getString(DailyCourseSummaryScheduler.JOB_TOKEN), updated.extras.getString(DailyCourseSummaryScheduler.JOB_TOKEN))
            assertFalse(DailyCourseSummaryScheduler.isExecutionCurrent(revision))
            assertEquals(delivered, preferences.dailyCourseNotificationDeliveredDay)
            assertTrue(preferences.dailyCourseNotificationsEnabled)
            assertTrue(DailyCourseSummaryScheduler.revoke(context))
            assertFalse(scheduler.allPendingJobs.any { DailyCourseSummaryScheduler.isManagedJob(it.id) })
        } finally {
            DailyCourseSummaryScheduler.revoke(context)
            SecureCredentialStore(context).clear()
            ScheduleStore(context).clear()
            preferences.clear()
        }
    }
}
