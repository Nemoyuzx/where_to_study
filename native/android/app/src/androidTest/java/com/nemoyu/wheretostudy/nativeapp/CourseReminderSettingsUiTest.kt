package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.graphics.Rect
import android.view.View
import android.view.WindowManager
import android.widget.EditText
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CourseReminderSettingsUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun bilingualRowsValidatePersistAndKeepNotificationsOff() {
        ensurePrivacyConsentForUiTest()
        CourseReminderScheduler.revoke(context)
        DailyCourseSummaryScheduler.revoke(context)
        SecureCredentialStore(context).clear()
        listOf("zh-Hans", "en").forEach { language ->
            val preferences = AppPreferences(context)
            preferences.clear()
            preferences.languageCode = language
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.navigation_settings).performClick()
                    val root = activity.window.decorView
                    val count = activity.findViewById<TextView>(R.id.settings_course_reminder_count)
                    assertTrue(count.text.contains("1"))
                    assertEquals("10", root.findViewWithTag<EditText>("course-reminder-offset-0").text.toString())
                    assertEquals(activity.dp(UiMetrics.controlHeightDp), root.findViewWithTag<EditText>("course-reminder-offset-0").layoutParams.height)
                    activity.findViewById<View>(R.id.settings_course_reminder_add).performClick()
                    assertTrue(count.text.contains("2"))
                    val first = root.findViewWithTag<EditText>("course-reminder-offset-0")
                    first.setText("0")
                    activity.findViewById<View>(R.id.settings_course_reminder_save).performClick()
                    assertEquals(listOf(10), preferences.courseReminderOffsets)
                    first.setText("10")
                    root.findViewWithTag<EditText>("course-reminder-offset-1").setText("5")
                    activity.findViewById<View>(R.id.settings_course_reminder_save).performClick()
                    assertEquals(listOf(10, 5), preferences.courseReminderOffsets)
                    assertFalse(preferences.courseRemindersEnabled)
                    assertFalse(preferences.dailyCourseNotificationsEnabled)
                    repeat(3) { activity.findViewById<View>(R.id.settings_course_reminder_add).performClick() }
                    assertTrue(count.text.contains("5"))
                    assertFalse(activity.findViewById<View>(R.id.settings_course_reminder_add).isEnabled)
                    root.findViewWithTag<View>("course-reminder-remove-4").performClick()
                    assertTrue(count.text.contains("4"))
                    assertTrue(activity.findViewById<TextView>(R.id.settings_daily_course_notification_time).text.contains("07:30"))
                }
                scenario.onActivity { activity ->
                    activity.refreshCurrentPage()
                    // Synthetic fixtures only, matching existing settings visual tests.
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    val toggle = activity.findViewById<View>(R.id.settings_course_reminder_toggle)
                    toggle.post { toggle.requestRectangleOnScreen(Rect(0, 0, toggle.width, activity.dp(360)), true) }
                }
                instrumentation.waitForIdleSync()
                assertTrue(UiDevice.getInstance(instrumentation).wait(Until.hasObject(By.res(context.packageName,
                    "settings_course_reminder_save")), 5000))
                UiDevice.getInstance(instrumentation).wait(Until.gone(By.textContains("请设置 1–5")), 5000)
                UiDevice.getInstance(instrumentation).wait(Until.gone(By.textContains("Set 1–5")), 5000)
                // Toast windows are not always in the accessibility tree; let queued feedback finish.
                android.os.SystemClock.sleep(6000)
                val directory = File(context.getExternalFilesDir(null), "course-reminder-ui").apply { mkdirs() }
                assertTrue(UiDevice.getInstance(instrumentation).takeScreenshot(File(directory, "$language.png")))
                scenario.onActivity { activity ->
                    val permission = activity.findViewById<View>(R.id.settings_course_reminder_exact_access)
                    permission.requestRectangleOnScreen(Rect(0, 0, permission.width, permission.height + activity.dp(100)), true)
                }
                instrumentation.waitForIdleSync()
                assertTrue(UiDevice.getInstance(instrumentation).takeScreenshot(File(directory, "$language-access.png")))
            }
        }
        AppPreferences(context).clear()
    }
}
