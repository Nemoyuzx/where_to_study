package com.nemoyu.wheretostudy.nativeapp

import android.app.NotificationManager
import android.app.job.JobScheduler
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainNavigationSmokeTest {
    @Test
    fun dailyClassroomRefreshCanBeScheduledWithSavedCredentials() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scheduler = context.getSystemService(JobScheduler::class.java)
        DailyClassroomRefreshScheduler.cancel(context)
        SecureCredentialStore(context).save(Credentials("test-account", "test-password"))

        try {
            assertTrue(
                "Daily classroom refresh must be accepted by JobScheduler",
                DailyClassroomRefreshScheduler.ensureScheduled(context),
            )
            assertTrue(
                "Daily classroom refresh job must remain pending after scheduling",
                scheduler.allPendingJobs.any { job ->
                    DailyClassroomRefreshScheduler.isManagedJob(job.id)
                },
            )
        } finally {
            DailyClassroomRefreshScheduler.cancel(context)
            SecureCredentialStore(context).clear()
        }
    }

    @Test
    fun primaryPagesCanBeNavigatedWithoutCredentials() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        clearManagedNotificationState()
        val launchIntent = Intent(
            instrumentation.targetContext,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            var navigationResource = ""
            scenario.onActivity { activity ->
                navigationResource = if (activity.resources.configuration.screenWidthDp < 700) {
                    "phone_navigation"
                } else {
                    "tablet_navigation"
                }
                assertTrue(
                    "Target app must explicitly enter notification UI test mode",
                    DailyCourseNotificationRuntimeMode.isUiTesting,
                )
                DailyCourseSummaryScheduler.reconcile(activity)
                DailyCourseSummaryNotificationRuntime.show(
                    activity,
                    DailyCourseSummaryDraft("UI 测试", "不应创建系统通知"),
                )
            }

            assertNoManagedNotificationState()

            assertVisible(device, navigationResource)
            assertVisible(device, "page_planner")

            click(device, "navigation_calendar")
            assertVisible(device, "page_calendar")
            if (navigationResource == "phone_navigation") {
                assertVisible(device, "calendar_phone_header")
                assertVisible(device, "calendar_mode_switch")
                assertVisible(device, "calendar_date_strip")
                assertVisible(device, "calendar_timeline_scroll")
                assertVisible(device, "phone_navigation")

                click(device, "calendar_mode_day")
                assertVisible(device, "calendar_timeline")
                click(device, "calendar_mode_month")
                assertVisible(device, "calendar_period_label")
                click(device, "calendar_mode_year")
                assertVisible(device, "calendar_period_label")
                click(device, "calendar_mode_week")
                assertVisible(device, "calendar_date_strip")
            }

            click(device, "navigation_settings")
            assertVisible(device, "page_settings")

            click(device, "navigation_planner")
            assertVisible(device, "page_planner")
        }
        assertNoManagedNotificationState()
    }

    private fun click(device: UiDevice, resourceName: String) {
        val view = device.wait(
            Until.findObject(By.res(TARGET_PACKAGE, resourceName)),
            UI_TIMEOUT_MILLIS,
        )
        assertNotNull("Missing clickable view: $resourceName", view)
        view.click()
        device.waitForIdle()
    }

    private fun assertVisible(device: UiDevice, resourceName: String) {
        val visible = device.wait(
            Until.hasObject(By.res(TARGET_PACKAGE, resourceName)),
            UI_TIMEOUT_MILLIS,
        )
        assertTrue("Missing visible view: $resourceName", visible)
    }

    private fun clearCredentialRecord() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val cleared = context
            .getSharedPreferences(CREDENTIAL_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        assertTrue("Test fixture must start without saved credentials", cleared)
    }

    private fun clearManagedNotificationState() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scheduler = context.getSystemService(JobScheduler::class.java)
        DailyCourseSummaryScheduler.managedJobIDs().forEach(scheduler::cancel)
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.activeNotifications
            .filter { DailyCourseSummaryNotificationRuntime.isManagedNotification(it.id) }
            .forEach { manager.cancel(it.id) }
    }

    private fun assertNoManagedNotificationState() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scheduler = context.getSystemService(JobScheduler::class.java)
        assertFalse(
            "UI testing must not create a managed course-summary job",
            scheduler.allPendingJobs.any { DailyCourseSummaryScheduler.isManagedJob(it.id) },
        )
        val manager = context.getSystemService(NotificationManager::class.java)
        assertFalse(
            "UI testing must not publish the managed course-summary notification",
            manager.activeNotifications.any {
                DailyCourseSummaryNotificationRuntime.isManagedNotification(it.id)
            },
        )
    }

    private companion object {
        const val CREDENTIAL_PREFERENCES = "secure_credentials_v1"
        const val TARGET_PACKAGE = "com.nemoyu.wheretostudy.nativeapp"
        const val UI_TIMEOUT_MILLIS = 5_000L
    }
}
