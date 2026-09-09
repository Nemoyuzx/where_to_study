package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.view.LayoutInflater
import android.view.View
import android.view.inspector.WindowInspector
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.TimePicker
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import java.io.File
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Disposable emulator fixtures only; reminder execution and authenticated network work stay disabled. */
@RunWith(AndroidJUnit4::class)
class ReminderWidgetUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)

    @Before
    fun setup() {
        ensurePrivacyConsentForUiTest()
        SecureCredentialStore(context).clear()
        AppPreferences(context).clear()
    }

    @Test
    fun oldInvalidAndClearedPreferencesUseSevenThirty() {
        val preferences = AppPreferences(context)
        val stored = context.getSharedPreferences(AppPreferences.PREFERENCES_NAME, Context.MODE_PRIVATE)
        assertEquals(450, preferences.dailyCourseNotificationMinutes)
        assertFalse(preferences.dailyCourseNotificationsEnabled)
        listOf(-1, 1440, Int.MAX_VALUE).forEach {
            stored.edit().putInt(AppPreferences.DAILY_COURSE_NOTIFICATION_MINUTES_KEY, it).commit()
            assertEquals(450, preferences.dailyCourseNotificationMinutes)
        }
        stored.edit().putString(AppPreferences.DAILY_COURSE_NOTIFICATION_MINUTES_KEY, "invalid").commit()
        assertEquals(450, preferences.dailyCourseNotificationMinutes)
        preferences.dailyCourseNotificationMinutes = 0
        assertEquals(0, AppPreferences(context).dailyCourseNotificationMinutes)
        preferences.dailyCourseNotificationMinutes = 1439
        assertEquals(1439, AppPreferences(context).dailyCourseNotificationMinutes)
        preferences.clear()
        assertEquals(450, AppPreferences(context).dailyCourseNotificationMinutes)
    }

    @Test
    fun bilingualTimePickerSavesHoursAndMinutesWithoutEnablingNotifications() {
        listOf("zh-Hans", "en").forEach { language ->
            AppPreferences(context).languageCode = language
            ActivityScenario.launch<MainActivity>(launchIntent()).use { scenario ->
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.navigation_settings).performClick()
                    val button = activity.findViewById<TextView>(R.id.settings_daily_course_notification_time)
                    assertTrue(button.text.contains("07:30"))
                    button.performClick()
                }
                instrumentation.waitForIdleSync()
                assertTrue(device.wait(Until.hasObject(By.res(context.packageName, "settings_daily_course_notification_time_picker")), 5000))
                screenshot("reminder-picker-$language")
                scenario.onActivity {
                    val picker = WindowInspector.getGlobalWindowViews().firstNotNullOf { root ->
                        root.findViewById<TimePicker?>(R.id.settings_daily_course_notification_time_picker)
                    }
                    picker.hour = 23
                    picker.minute = 59
                }
                device.findObject(By.res("android", "button1")).click()
                instrumentation.waitForIdleSync()
                assertEquals(1439, AppPreferences(context).dailyCourseNotificationMinutes)
                assertFalse(AppPreferences(context).dailyCourseNotificationsEnabled)
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<TextView>(R.id.settings_daily_course_notification_time).text.contains("23:59"))
                }
            }
            AppPreferences(context).dailyCourseNotificationMinutes = 450
        }
    }

    @Test
    fun realRemoteViewsAndPreviewShowSameTomorrowRowsInBothLanguages() {
        listOf("zh-Hans", "en").forEach { language ->
            AppPreferences(context).languageCode = language
            AppPreferences(context).widgetCourseLimit = 6
            ActivityScenario.launch<MainActivity>(launchIntent()).use { scenario ->
                scenario.onActivity { activity ->
                    val content = TodayCourseWidgetLogic.previewContent()
                    val host = LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        setPadding(activity.dp(16), activity.dp(32), activity.dp(16), activity.dp(16))
                    }
                    val preview = LayoutInflater.from(activity).inflate(R.layout.widget_today_course, host, false)
                    val remote = TodayCourseWidgetProvider.createRemoteViews(activity, content, AppPreferences(activity), 6).apply(activity, host)
                    TodayCourseWidgetPreviewBinder.bind(preview, content, true, true, 6)
                    host.addView(preview, LinearLayout.LayoutParams(-1, activity.dp(328)))
                    host.addView(remote, LinearLayout.LayoutParams(-1, activity.dp(328)))
                    AlertDialog.Builder(activity).setView(host).show()
                    listOf(R.id.widget_course_name_1, R.id.widget_course_name_4, R.id.widget_course_name_6).forEach { id ->
                        assertEquals(preview.findViewById<TextView>(id).text.toString(), remote.findViewById<TextView>(id).text.toString())
                    }
                    val prefix = if (language == "en") "Tomorrow · " else "明日 · "
                    assertTrue(remote.findViewById<TextView>(R.id.widget_course_name_4).text.startsWith(prefix))
                    if (language == "en") {
                        assertFalse(remote.findViewById<TextView>(R.id.widget_day_context).text.contains("进行中"))
                        assertFalse(remote.findViewById<TextView>(R.id.widget_day_context).text.contains("下课"))
                    }
                }
                instrumentation.waitForIdleSync()
                assertTrue(device.wait(Until.hasObject(By.res(context.packageName, "widget_course_name_6")), 5000))
                screenshot("widget-preview-and-remote-$language")
            }
        }
    }

    private fun launchIntent() = Intent(context, MainActivity::class.java)
        .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

    private fun screenshot(name: String) {
        assertTrue(device.takeScreenshot(File(context.getExternalFilesDir(null), "$name.png")))
    }
}
