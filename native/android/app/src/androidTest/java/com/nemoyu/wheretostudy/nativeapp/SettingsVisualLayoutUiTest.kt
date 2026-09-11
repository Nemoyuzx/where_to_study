package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Run only on the task's disposable phone emulator, including its large-font pass. */
@RunWith(AndroidJUnit4::class)
class SettingsVisualLayoutUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test
    fun bilingualSettingsKeepReadableTouchTargetsAndDraftsAcrossThemeChanges() {
        ensurePrivacyConsentForUiTest()
        val preferences = AppPreferences(context)
        val originalLanguage = preferences.languageCode
        val originalTheme = ColorThemePreferences(context).load()
        try {
            listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
                preferences.languageCode = language.code
                ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                    .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                    scenario.onActivity { activity ->
                        assumeTrue(activity.resources.configuration.screenWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP)
                        activity.findViewById<View>(R.id.navigation_settings).performClick()
                    }
                    instrumentation.waitForIdleSync()
                    scenario.onActivity { activity ->
                        val page = activity.findViewById<ScrollView>(R.id.page_settings)
                        val fields = descendants(page).filterIsInstance<EditText>()
                        val account = fields.first()
                        val color = activity.findViewById<EditText>(R.id.settings_color_theme_primary)
                        account.setText("unsaved visual-test account")
                        color.setText("#ABCDEF")
                        assertTrue(activity.applyColorTheme(ColorThemeSelection("ocean")))
                        assertSame(page, activity.findViewById(R.id.page_settings))
                        assertEquals("unsaved visual-test account", account.text.toString())
                        assertEquals("#ABCDEF", color.text.toString())
                        assertSettingsOrder(activity, page)
                    }
                    instrumentation.waitForIdleSync()
                    scenario.onActivity { activity ->
                        val page = activity.findViewById<ScrollView>(R.id.page_settings)
                        val content = page.getChildAt(0) as ViewGroup
                        val touchTargets = descendants(page).filterIsInstance<TextView>()
                            .filter { it.isClickable || it is EditText }
                        assertTrue("The real settings page must contain controls", touchTargets.isNotEmpty())
                        touchTargets.forEach { control ->
                            assertTrue("Below compact baseline: ${control.text}", control.height >= activity.dp(UiMetrics.controlHeightDp))
                            val bounds = Rect()
                            control.getDrawingRect(bounds)
                            content.offsetDescendantRectToMyCoords(control, bounds)
                            assertTrue("Control spills horizontally: ${control.text}", bounds.left >= 0 && bounds.right <= content.width)
                            if (control !is EditText) assertReadable(control)
                        }
                        assertTrue(activity.applyColorTheme(originalTheme))
                    }
                }
            }
        } finally {
            preferences.languageCode = originalLanguage
            ColorThemePreferences(context).save(originalTheme)
        }
    }

    private fun assertSettingsOrder(activity: MainActivity, page: ViewGroup) {
        val ordered = descendants(page)
        val language = activity.findViewById<View>(R.id.settings_language_section)
        val privacy = activity.findViewById<View>(R.id.privacy_policy_button)
        val localData = activity.findViewById<View>(R.id.settings_local_data_section)
        assertTrue(ordered.indexOf(language) < ordered.indexOf(privacy))
        assertTrue(ordered.indexOf(privacy) < ordered.indexOf(localData))
        val header = (language as ViewGroup).getChildAt(0) as TextView
        assertEquals(activity.uiText("语言"), header.text.toString())
    }

    private fun assertReadable(view: TextView) {
        val layout = view.layout ?: return
        assertTrue("Text clipped vertically: ${view.text}",
            layout.height <= view.height - view.compoundPaddingTop - view.compoundPaddingBottom + 2)
        repeat(layout.lineCount) { line ->
            assertEquals("Ellipsized setting label: ${view.text}", 0, layout.getEllipsisCount(line))
        }
    }

    private fun descendants(root: View): List<View> = buildList {
        add(root)
        if (root is ViewGroup) repeat(root.childCount) { addAll(descendants(root.getChildAt(it))) }
    }
}
