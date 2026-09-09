package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ContextThemeWrapper
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import java.io.File
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real AppWidgetHost rendering. Run once at system font_scale=1 and once at font_scale=2. */
@RunWith(AndroidJUnit4::class)
class WidgetSizingUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext.applicationContext

    @Test
    fun smallestAndResizableHostsKeepTodayVisibleInBothLanguages() {
        check(Build.HARDWARE in setOf("ranchu", "goldfish"))
        ensurePrivacyConsentForUiTest()
        SecureCredentialStore(context).clear()
        val preferences = AppPreferences(context)
        preferences.clear()
        preferences.automaticTermDetectionEnabled = false
        preferences.widgetCourseLimit = 6
        val content = TodayCourseWidgetLogic.previewContent()
        val monday = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
            add(Calendar.DAY_OF_MONTH, -((get(Calendar.DAY_OF_WEEK) + 5) % 7))
        }
        val start = String.format(Locale.US, "%04d-%02d-%02d", monday.get(Calendar.YEAR),
            monday.get(Calendar.MONTH) + 1, monday.get(Calendar.DAY_OF_MONTH))
        ScheduleStore(context).save(ScheduleSnapshot("widget-fixture", start, "fixture", content.courses + content.tomorrowCourses))
        val manager = AppWidgetManager.getInstance(context)
        val provider = ComponentName(context, TodayCourseWidgetProvider::class.java)
        val providerInfo = manager.installedProviders.single { it.provider == provider }
        try {
            for (language in listOf("zh-Hans", "en")) {
                preferences.languageCode = language
                ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                    .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                    for ((width, height) in listOf(180 to 110, 250 to 205, 320 to 328)) {
                        val spec = TodayCourseWidgetLayout.forSize(context, content, width, height, 6)
                        val widgetHost = AppWidgetHost(context, 908_110)
                        var widgetID = 0
                        var dialog: AlertDialog? = null
                        var root: ViewGroup? = null
                        var preview: View? = null
                        scenario.onActivity { activity ->
                            widgetID = widgetHost.allocateAppWidgetId()
                            instrumentation.uiAutomation.adoptShellPermissionIdentity("android.permission.BIND_APPWIDGET")
                            try { assertTrue(manager.bindAppWidgetIdIfAllowed(widgetID, provider)) }
                            finally { instrumentation.uiAutomation.dropShellPermissionIdentity() }
                            widgetHost.startListening()
                            // A launcher doesn't inherit MainActivity's 0.92 typography adjustment.
                            val hostView = widgetHost.createView(ContextThemeWrapper(context, R.style.Theme_WhereToStudy), widgetID, providerInfo)
                            hostView.setPadding(0, 0, 0, 0)
                            hostView.updateAppWidgetSize(Bundle(), listOf(SizeF(width.toFloat(), height.toFloat())))
                            val remote = TodayCourseWidgetProvider.sizedRemoteViews(context, content, preferences, width, height)
                            manager.updateAppWidget(widgetID, remote)
                            val holder = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
                            val previewView = LayoutInflater.from(activity).inflate(R.layout.widget_today_course, holder, false)
                            TodayCourseWidgetPreviewBinder.bind(previewView, content, true, true, 6, spec)
                            holder.addView(hostView, LinearLayout.LayoutParams(activity.dp(width), activity.dp(height)))
                            holder.addView(previewView, LinearLayout.LayoutParams(activity.dp(width), activity.dp(height)))
                            dialog = AlertDialog.Builder(activity).setView(holder).show()
                            root = hostView
                            preview = previewView
                        }
                        instrumentation.waitForIdleSync()
                        // Provider updates run through goAsync. Wait for the actual host hierarchy.
                        val deadline = System.currentTimeMillis() + 5_000
                        while (root?.findViewById<View?>(R.id.widget_course_name_1) == null && System.currentTimeMillis() < deadline) {
                            Thread.sleep(50)
                            instrumentation.waitForIdleSync()
                        }
                        assertTrue(UiDevice.getInstance(instrumentation).wait(Until.hasObject(
                            By.res(context.packageName, "widget_course_name_1")), 5_000))
                        Thread.sleep(200) // Allow the dialog's first rendered frame before capturing it.
                        val font = context.resources.configuration.fontScale
                        assertTrue(UiDevice.getInstance(instrumentation).takeScreenshot(File(context.getExternalFilesDir(null),
                            "widget-sizing-$language-${width}x$height-font$font.png")))
                        scenario.onActivity {
                            val widget = checkNotNull(root?.findViewById<ViewGroup>(R.id.widget_root))
                            assertTrue("At least today's first course survives $width x $height", spec.capacity >= 1)
                            val first = widget.findViewById<TextView>(R.id.widget_course_name_1)
                            assertEquals(preview!!.findViewById<TextView>(R.id.widget_course_name_1).text.toString(), first.text.toString())
                            assertTrue(first.text.contains(content.courses.first().name))
                            assertFalse(first.text.startsWith(if (language == "en") "Tomorrow" else "明日"))
                            assertEquals(if (language == "en") "Today’s Courses" else "今日课程",
                                widget.findViewById<TextView>(R.id.widget_theme_title).text.toString())
                            assertNoVerticalClipping(widget, widget, "host $width x $height $spec")
                            assertNoVerticalClipping(preview as ViewGroup, preview as ViewGroup, "preview $width x $height $spec")
                        }
                        scenario.onActivity { dialog?.dismiss(); widgetHost.stopListening(); widgetHost.deleteAppWidgetId(widgetID) }
                    }
                }
            }
        } finally {
            ScheduleStore(context).clear()
            preferences.clear()
        }
    }

    private fun assertNoVerticalClipping(root: ViewGroup, view: View, label: String) {
        if (view.visibility != View.VISIBLE) return
        if (view is TextView && view.text.isNotEmpty()) {
            val bounds = Rect(0, 0, view.width, view.height)
            root.offsetDescendantRectToMyCoords(view, bounds)
            assertTrue("${view.text}: top $bounds outside ${root.height}", bounds.top >= root.paddingTop)
            assertTrue("${view.text}: bottom $bounds outside ${root.height}", bounds.bottom <= root.height - root.paddingBottom)
            val layout = checkNotNull(view.layout)
            assertTrue("$label ${view.text}: line bottom ${layout.getLineBottom(layout.lineCount - 1)} clipped inside ${view.height}, padding ${view.totalPaddingTop}/${view.totalPaddingBottom}, size ${view.textSize}, metrics ${view.paint.fontMetricsInt}",
                layout.getLineBottom(layout.lineCount - 1) <= view.height - view.totalPaddingTop - view.totalPaddingBottom)
        }
        if (view is ViewGroup) for (index in 0 until view.childCount) assertNoVerticalClipping(root, view.getChildAt(index), label)
    }
}
