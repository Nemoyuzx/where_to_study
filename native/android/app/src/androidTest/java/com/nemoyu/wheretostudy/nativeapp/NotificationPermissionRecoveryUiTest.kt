package com.nemoyu.wheretostudy.nativeapp

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Launch after externally revoking POST_NOTIFICATIONS on the disposable emulator. */
@RunWith(AndroidJUnit4::class)
class NotificationPermissionRecoveryUiTest {
    @Test
    fun deniedPermissionCancelsPersistedReminderAndRevokesAuthorization() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("permissionDenied") == "true")
        check(Build.HARDWARE in setOf("ranchu", "goldfish"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = AppPreferences(context)
        val scheduler = context.getSystemService(JobScheduler::class.java)
        val service = ComponentName(context, DailyCourseSummaryJobService::class.java)
        try {
            ensurePrivacyConsentForUiTest()
            assertFalse(DailyCourseSummaryNotificationRuntime.hasPermission(context))
            preferences.dailyCourseNotificationsEnabled = true
            DailyCourseNotificationAuthorizationStore(context).authorize()
            context.packageManager.setComponentEnabledSetting(service, PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP)
            val job = JobInfo.Builder(DailyCourseSummaryScheduler.managedJobIDs().first(), service)
                .setMinimumLatency(86_400_000).setPersisted(true).build()
            assertEquals(JobScheduler.RESULT_SUCCESS, scheduler.schedule(job))
            assertTrue(DailyCourseSummaryScheduler.reconcile(context))
            assertFalse(preferences.dailyCourseNotificationsEnabled)
            assertFalse(DailyCourseNotificationAuthorizationStore(context).isAuthorized)
            assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                context.packageManager.getComponentEnabledSetting(service))
            assertFalse(scheduler.allPendingJobs.any { DailyCourseSummaryScheduler.isManagedJob(it.id) })
        } finally {
            DailyCourseSummaryScheduler.revoke(context)
            preferences.clear()
        }
    }
}
