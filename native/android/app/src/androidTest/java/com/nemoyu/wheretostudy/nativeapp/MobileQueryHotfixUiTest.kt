package com.nemoyu.wheretostudy.nativeapp

import android.app.UiModeManager
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Rect
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Only synthetic data is used, including while the real Activity is recreated by system appearance changes. */
@RunWith(AndroidJUnit4::class)
class MobileQueryHotfixUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val device get() = UiDevice.getInstance(instrumentation)
    @Before fun privacy() = ensurePrivacyConsentForUiTest()

    @Test fun landscapePhonesKeepIconsAndSmallTitlesWhenNavigationBecomesARail() = inBothLanguages { language ->
        assumeTrue(context.resources.configuration.smallestScreenWidthDp < 600)
        launch().use { scenario ->
            scenario.onActivity { activity ->
                activity.findViewById<View>(R.id.navigation_query).performClick()
                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
            assertTrue(device.wait(Until.hasObject(By.res(context.packageName, "tablet_navigation")), 5_000))
            settled()
            scenario.onActivity { activity ->
                assertEquals(Configuration.ORIENTATION_LANDSCAPE, activity.resources.configuration.orientation)
                assertNotNull(activity.findViewById<View>(R.id.tablet_navigation))
                val selector = activity.findViewById<ViewGroup>(R.id.information_query_mode_switch)
                val viewport = selector.parent as View
                assertEquals(viewport.width, selector.width)
                assertFalse(viewport.canScrollHorizontally(1))
                descendants(selector).filterIsInstance<TextView>().forEachIndexed { index, tab ->
                    assertNotNull("A landscape phone still shows query icons", tab.compoundDrawablesRelative[0])
                    assertEquals(activity.uiText(InformationQueryMode.entries[index].label), tab.contentDescription)
                    assertTrue(tab.paint.measureText(tab.text.toString()) <= tab.width - tab.compoundPaddingLeft - tab.compoundPaddingRight + 1)
                }
                val title = descendants(activity.findViewById(R.id.information_query_page)).filterIsInstance<TextView>()
                    .first { it.text == activity.uiText("信息查询") }
                assertEquals(android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP,
                    26f, activity.resources.displayMetrics), title.textSize, 1f)
            }
            screenshot("$language-landscape-selector")
        }
    }

    @Test fun fixedSegmentsHaveIconsAndFullAccessibilityAndIgnoreHorizontalDrags() = inBothLanguages { language ->
        launch().use { scenario ->
            scenario.onActivity { it.findViewById<View>(R.id.navigation_query).performClick() }
            settled()
            var bounds = Rect()
            var positions = emptyList<Int>()
            scenario.onActivity { activity ->
                val page = activity.findViewById<ViewGroup>(R.id.information_query_page)
                val selector = activity.findViewById<ViewGroup>(R.id.information_query_mode_switch)
                val viewport = page.findViewWithTag<View>("information.query.mode.viewport")
                assertFalse(viewport is HorizontalScrollView)
                assertFalse(viewport.canScrollHorizontally(1))
                assertFalse(viewport.canScrollHorizontally(-1))
                assertEquals(viewport.width, selector.width)
                val tabs = descendants(selector).filterIsInstance<TextView>()
                assertEquals(5, tabs.size)
                val isPhone = activity.resources.configuration.smallestScreenWidthDp < 600
                tabs.forEachIndexed { index, tab ->
                    assertEquals(activity.uiText(InformationQueryMode.entries[index].label), tab.contentDescription)
                    assertEquals(1, tab.layout.lineCount)
                    assertEquals(0, tab.layout.getEllipsisCount(0))
                    if (isPhone) {
                        assertNotNull(tab.compoundDrawablesRelative[0])
                        if (activity.resources.configuration.screenWidthDp <= 440) assertEquals("", tab.text.toString())
                    } else {
                        assertNull(tab.compoundDrawablesRelative[0])
                        assertTrue(tab.text.isNotEmpty())
                    }
                    assertTrue(tab.width >= activity.dp(44))
                }
                val title = descendants(page).filterIsInstance<TextView>().first { it.text == activity.uiText("信息查询") }
                val expectedSp = if (isPhone) 26f else 34f
                assertEquals(android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP,
                    expectedSp, activity.resources.displayMetrics), title.textSize, 1f)
                assertTrue(title.layout.height <= title.height - title.compoundPaddingTop - title.compoundPaddingBottom)
                repeat(title.layout.lineCount) { assertEquals(0, title.layout.getEllipsisCount(it)) }
                bounds = Rect().also(selector::getGlobalVisibleRect)
                positions = tabs.map { it.left }
            }
            // Start inside the end segments, clear of Android's system back-gesture edge.
            val inset = bounds.width() / 10
            device.swipe(bounds.right - inset, bounds.centerY(), bounds.left + inset, bounds.centerY(), 20)
            device.swipe(bounds.left + inset, bounds.centerY(), bounds.right - inset, bounds.centerY(), 20)
            settled()
            scenario.onActivity { activity ->
                val selector = activity.findViewById<ViewGroup>(R.id.information_query_mode_switch)
                assertEquals(positions, descendants(selector).filterIsInstance<TextView>().map { it.left })
                assertEquals(0, (selector.parent as View).scrollX)
            }
            screenshot("$language-selector")
        }
    }

    @Test fun currentTermEmptyGapAndPrivateGradesSurviveBothSystemThemeTransitions() = inBothLanguages { language ->
        val originalMode = context.getSystemService(UiModeManager::class.java).nightMode
        val fetches = AtomicInteger()
        val grades = AcademicGradesRepository({ Credentials("synthetic-only", "synthetic-only") },
            { AcademicTerms("current", listOf(AcademicTerm("current", "2026-2027-1"), AcademicTerm("past", "2025-2026-2"))) },
            { _, term, type ->
                fetches.incrementAndGet()
                AcademicGrades(term, type, "synthetic", "3.50", if (term == "past") emptyList() else listOf(
                    AcademicGrade("synthetic", "Synthetic grades / 合成成绩示例", "92", "2", "DEMO", "Synthetic only", null, null),
                ))
            })
        try {
            device.executeShellCommand("cmd uimode night no")
            awaitGrades(grades) { grades.load() }
            launch().use { scenario ->
                scenario.onActivity { activity ->
                    // Inject a synthetic network boundary only; the actual Activity owns,
                    // retains, reattaches and closes this repository in production code.
                    repositoryDelegateField().set(activity, lazy { grades })
                    activity.findViewById<View>(R.id.navigation_query).performClick()
                    activity.findViewById<View>(R.id.information_query_grades_tab).performClick()
                }
                settled()
                screenshot("$language-grades-light")
                scenario.onActivity { it.findViewById<View>(R.id.information_query_grades_term).performClick() }
                val currentLabel = if (language == "en") "2026-2027-1 · Current semester" else "2026-2027-1 · 当前学期"
                assertTrue(device.wait(Until.hasObject(By.text(currentLabel)), 5_000))
                assertTrue(device.hasObject(By.text("2025-2026-2")))
                assertTrue(device.hasObject(By.text(if (language == "en") "All semesters" else "全部学期")))
                screenshot("$language-term-menu")
                device.pressBack()
                awaitGrades(grades) { grades.select("past", "0") }
                settled()
                val snapshot = grades.snapshot
                assertEquals(2, fetches.get())
                var previousActivity: MainActivity? = null
                scenario.onActivity { previousActivity = it; assertEmptyGap(it) }
                screenshot("$language-empty-light")
                listOf(true, false).forEach { night ->
                    device.executeShellCommand("cmd uimode night ${if (night) "yes" else "no"}")
                    device.wait(Until.hasObject(By.res(context.packageName, "information_query_grades_term")), 5_000)
                    settled()
                    scenario.onActivity { activity ->
                        assertNotSame("System appearance must recreate the Activity", previousActivity, activity)
                        previousActivity = activity
                        assertEquals(night, activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
                        assertSame(grades, (repositoryDelegateField().get(activity) as Lazy<*>).value)
                        assertSame("The cached snapshot must survive without refetching", snapshot, grades.snapshot)
                        assertEquals("past", grades.selectedTermID)
                        assertEquals("0", grades.recordType)
                        assertEquals(2, fetches.get())
                        assertTrue(activity.findViewById<View>(R.id.information_query_grades_tab).isSelected)
                        assertEmptyGap(activity)
                    }
                    screenshot("$language-empty-${if (night) "dark" else "light-restored"}")
                    scenario.onActivity { activity ->
                        grades.select("current", "1")
                        assertEquals(2, fetches.get())
                        assertEquals("92", grades.snapshot!!.items.single().score)
                        assertTrue(descendants(activity.findViewById(R.id.information_query_grades_scroll))
                            .any { it.tag == "academic.grade.row" })
                    }
                    settled()
                    screenshot("$language-grades-${if (night) "dark" else "light-restored"}")
                    scenario.onActivity { grades.select("past", "0") }
                    settled()
                }
            }
            assertNull("Finishing the Activity still clears the private cache", grades.snapshot)
        } finally {
            grades.close()
            restoreNightMode(originalMode)
        }
    }

    @Test fun everySettingsSwitchUsesDistinctEnabledAndDisabledPaletteStates() {
        val originalMode = context.getSystemService(UiModeManager::class.java).nightMode
        val colorPreferences = ColorThemePreferences(context)
        val originalSelection = colorPreferences.load()
        try {
            listOf(false, true).forEach { night ->
                device.executeShellCommand("cmd uimode night ${if (night) "yes" else "no"}")
                colorPreferences.save(ColorThemeSelection())
                launch().use { scenario ->
                    scenario.onActivity { it.findViewById<View>(R.id.navigation_settings).performClick() }
                    settled()
                    scenario.onActivity { activity ->
                        listOf(ColorThemeSelection(), ColorThemeSelection("ocean"), ColorThemeSelection()).forEach { selection ->
                            activity.applyColorTheme(selection)
                            val switches = descendants(activity.findViewById(R.id.page_settings)).filterIsInstance<Switch>()
                            assertTrue("Check all settings sections", switches.size >= 10)
                            switches.forEach { control ->
                                val checked = intArrayOf(android.R.attr.state_enabled, android.R.attr.state_checked)
                                val unchecked = intArrayOf(android.R.attr.state_enabled)
                                assertEquals(Palette.primaryFill, control.trackTintList!!.getColorForState(checked, 0))
                                assertEquals(Palette.onPrimary, control.thumbTintList!!.getColorForState(checked, 0))
                                assertEquals(Palette.border, control.trackTintList!!.getColorForState(unchecked, 0))
                                assertEquals(android.graphics.Color.WHITE, control.thumbTintList!!.getColorForState(unchecked, 0))
                                assertTrue(ColorUtils.calculateContrast(control.thumbTintList!!.getColorForState(checked, 0),
                                    control.trackTintList!!.getColorForState(checked, 0)) >= 3.0)
                                assertNotEquals(control.trackTintList!!.getColorForState(checked, 0),
                                    control.trackTintList!!.getColorForState(intArrayOf(android.R.attr.state_checked), 0))
                                assertNotEquals(control.trackTintList!!.getColorForState(unchecked, 0),
                                    control.trackTintList!!.getColorForState(intArrayOf(), 0))
                                // Check rendered pixels too: the framework's track solid
                                // has its own alpha underneath the public tint property.
                                val track = control.trackDrawable.constantState!!.newDrawable().mutate()
                                val bitmap = Bitmap.createBitmap(activity.dp(60), activity.dp(24), Bitmap.Config.ARGB_8888)
                                track.setBounds(0, 0, bitmap.width, bitmap.height)
                                track.state = checked
                                track.draw(Canvas(bitmap))
                                assertEquals(Palette.primaryFill, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
                                bitmap.eraseColor(android.graphics.Color.TRANSPARENT)
                                track.state = unchecked
                                track.draw(Canvas(bitmap))
                                assertEquals(Palette.border, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
                                bitmap.recycle()
                            }
                        }
                        val page = activity.findViewById<ScrollView>(R.id.page_settings)
                        val content = page.getChildAt(0) as ViewGroup
                        val anchor = activity.findViewById<View>(R.id.settings_competition_deadlines_switch)
                        val bounds = Rect().also(anchor::getDrawingRect)
                        content.offsetDescendantRectToMyCoords(anchor, bounds)
                        page.scrollTo(0, (bounds.top - activity.dp(120)).coerceAtLeast(0))
                    }
                    settled()
                    scenario.onActivity { activity ->
                        // Settings intentionally blocks system screenshots. Render the
                        // synthetic test view itself without changing that protection.
                        val view = activity.window.decorView
                        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                        view.draw(Canvas(bitmap))
                        screenshotFile("settings-switches-${if (night) "dark" else "light"}").outputStream().use {
                            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                        }
                        bitmap.recycle()
                    }
                }
            }
        } finally {
            colorPreferences.save(originalSelection)
            restoreNightMode(originalMode)
        }
    }

    private fun assertEmptyGap(activity: MainActivity) {
        val page = activity.findViewById<View>(R.id.information_query_grades_scroll)
        val average = page.findViewWithTag<View>("academic.grade.average")
        val empty = page.findViewWithTag<View>("academic.grade.empty")
        assertTrue("No-results card must be separated from GPA", empty.top - average.bottom >= activity.dp(10))
    }

    private fun awaitGrades(grades: AcademicGradesRepository, action: () -> Unit) {
        val finished = CountDownLatch(1)
        val observer = { if (!grades.isLoading && grades.snapshot != null) finished.countDown() }
        instrumentation.runOnMainSync { grades.addObserver(observer); action() }
        assertTrue(finished.await(5, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { grades.removeObserver(observer) }
    }

    private fun repositoryDelegateField() = MainActivity::class.java
        .getDeclaredField("academicGradesRepository\$delegate").apply { isAccessible = true }

    private fun launch() = ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
        .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true))

    private fun inBothLanguages(block: (String) -> Unit) {
        val preferences = AppPreferences(context)
        val original = preferences.languageCode
        try { listOf("zh-Hans", "en").forEach { preferences.languageCode = it; block(it) } }
        finally { preferences.languageCode = original }
    }

    private fun settled() { instrumentation.waitForIdleSync(); device.waitForIdle() }

    private fun screenshot(name: String) {
        assertTrue(device.takeScreenshot(screenshotFile(name)))
    }

    private fun screenshotFile(name: String): File {
        val config = context.resources.configuration
        val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "v031-hotfix").apply { mkdirs() }
        return File(directory, "$name-${config.screenWidthDp}-${config.fontScale}.png")
    }

    private fun restoreNightMode(mode: Int) {
        device.executeShellCommand("cmd uimode night ${when (mode) { UiModeManager.MODE_NIGHT_YES -> "yes"; UiModeManager.MODE_NIGHT_NO -> "no"; else -> "auto" }}")
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
