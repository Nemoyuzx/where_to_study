package com.nemoyu.wheretostudy.nativeapp

import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsetsController
import android.view.ContextThemeWrapper
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ThemeModeSmokeTest {
    @Test
    fun systemThemeResolvesDistinctSurfacesAndStatusBarAppearance() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val lightContext = base.createConfigurationContext(configuration(Configuration.UI_MODE_NIGHT_NO))
        val darkContext = base.createConfigurationContext(configuration(Configuration.UI_MODE_NIGHT_YES))

        assertNotEquals(
            lightContext.getColor(R.color.background),
            darkContext.getColor(R.color.background),
        )
        assertNotEquals(lightContext.getColor(R.color.surface), darkContext.getColor(R.color.surface))
        assertTrue(lightStatusBar(ContextThemeWrapper(lightContext, R.style.Theme_WhereToStudy)))
        assertFalse(lightStatusBar(ContextThemeWrapper(darkContext, R.style.Theme_WhereToStudy)))
    }

    @Test
    @SdkSuppress(minSdkVersion = 30)
    fun primaryPagesAndSystemBarsFollowSystemLightAndDarkModes() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        try {
            verifyMode(device, night = false, ThemePalettes.light)
            verifyMode(device, night = true, ThemePalettes.dark)
        } finally {
            device.executeShellCommand("cmd uimode night auto")
        }
    }

    private fun verifyMode(device: UiDevice, night: Boolean, colors: ThemeColors) {
        device.executeShellCommand("cmd uimode night ${if (night) "yes" else "no"}")
        device.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val intent = instrumentation.targetContext.packageManager
            .getLaunchIntentForPackage(instrumentation.targetContext.packageName)
            ?.putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)
        assertNotNull("Missing launch intent", intent)

        ActivityScenario.launch<MainActivity>(intent!!).use { scenario ->
            scenario.onActivity { activity ->
                val actualNight = activity.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
                assertEquals(night, actualNight)
                assertPageTheme(activity, R.id.page_planner, R.id.navigation_planner, "联动查询", colors)

                activity.findViewById<View>(R.id.navigation_calendar).performClick()
                assertPageTheme(
                    activity,
                    R.id.page_calendar,
                    R.id.navigation_calendar,
                    title = null,
                    colors = colors,
                )

                activity.findViewById<View>(R.id.navigation_query).performClick()
                assertPageTheme(activity, R.id.page_query, R.id.navigation_query, "查询", colors)

                activity.findViewById<View>(R.id.navigation_settings).performClick()
                assertPageTheme(activity, R.id.page_settings, R.id.navigation_settings, "设置", colors)

                val appearance = activity.window.insetsController?.systemBarsAppearance ?: 0
                val lightStatus = appearance and WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS != 0
                val lightNavigation = appearance and
                    WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS != 0
                assertEquals(!night, lightStatus)
                assertEquals(!night, lightNavigation)
            }
        }
    }

    private fun assertPageTheme(
        activity: MainActivity,
        pageID: Int,
        navigationID: Int,
        title: String?,
        colors: ThemeColors,
    ) {
        val page = activity.findViewById<View>(pageID)
        assertNotNull("Missing page $pageID", page)
        assertEquals(colors.background, (page.background as ColorDrawable).color)
        assertEquals(colors.primaryText, activity.findViewById<TextView>(navigationID).currentTextColor)
        val titleView = title?.let { findText(page, activity.uiText(it)) }
            ?: page.findViewById(R.id.calendar_period_label)
        assertNotNull("Missing page title: ${title ?: "calendar period"}", titleView)
        assertEquals(colors.text, titleView?.currentTextColor)
    }

    private fun findText(view: View, value: String): TextView? {
        if (view is TextView && view.text.toString() == value) return view
        if (view !is ViewGroup) return null
        repeat(view.childCount) { index ->
            findText(view.getChildAt(index), value)?.let { return it }
        }
        return null
    }

    private fun configuration(nightMode: Int): Configuration = Configuration().apply {
        uiMode = nightMode
    }

    private fun lightStatusBar(context: ContextThemeWrapper): Boolean = context.theme
        .obtainStyledAttributes(intArrayOf(android.R.attr.windowLightStatusBar))
        .let { values ->
            try {
                values.getBoolean(0, false)
            } finally {
                values.recycle()
            }
        }
}
