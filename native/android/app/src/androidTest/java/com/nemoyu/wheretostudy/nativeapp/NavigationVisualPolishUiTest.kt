package com.nemoyu.wheretostudy.nativeapp

import android.graphics.Rect
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class NavigationVisualPolishUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val device get() = UiDevice.getInstance(instrumentation)
    private val navigationNames = listOf("navigation_planner", "navigation_calendar", "navigation_query", "navigation_settings")

    private fun id(name: String): Int = context.resources.getIdentifier(name, "id", context.packageName)
    private fun launch(): ActivityScenario<MainActivity> {
        ensurePrivacyConsentForUiTest()
        return ActivityScenario.launch(context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .putExtra("com.nemoyu.wheretostudy.nativeapp.extra.UI_TEST_MODE", true))
    }

    @Test fun capturePrimaryPages() {
        // Resource names (not generated integer IDs) permit the same test APK to
        // capture the preserved pre-polish target APK without changing user data.
        val arguments = InstrumentationRegistry.getArguments()
        val stage = arguments.getString("visualStage", "after").replace(Regex("[^a-zA-Z0-9_-]"), "")
        val language = arguments.getString("visualLanguage", "zh-Hans")
        val prefs = AppPreferences(context)
        val previousLanguage = prefs.languageCode
        prefs.languageCode = language
        val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "visual-polish").apply { mkdirs() }
        try {
            launch().use { scenario ->
                navigationNames.forEachIndexed { index, navigation ->
                    scenario.onActivity { activity ->
                        activity.findViewById<View>(id(navigation)).performClick()
                        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    device.waitForIdle()
                    assertTrue(device.takeScreenshot(File(directory, "$stage-$language-$index.png")))
                }
                scenario.onActivity { activity ->
                    activity.findViewById<View>(id("navigation_query")).performClick()
                    activity.findViewById<View>(id("information_query_events_tab")).performClick()
                }
                device.waitForIdle()
                assertTrue(device.takeScreenshot(File(directory, "$stage-$language-events.png")))
                scenario.onActivity { activity ->
                    activity.findViewById<View>(id("navigation_settings")).performClick()
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                device.waitForIdle()
                scenario.onActivity { activity ->
                    val page = activity.findViewById<android.widget.ScrollView>(id("page_settings"))
                    val theme = activity.findViewById<View>(id("settings_color_theme_section"))
                    val bounds = Rect().also(theme::getDrawingRect)
                    (page.getChildAt(0) as ViewGroup).offsetDescendantRectToMyCoords(theme, bounds)
                    page.scrollTo(0, bounds.top.coerceAtLeast(0))
                }
                device.waitForIdle()
                assertTrue(device.takeScreenshot(File(directory, "$stage-$language-theme.png")))
            }
        } finally { prefs.languageCode = previousLanguage }
    }

    @Test fun capsuleSelectionMovesWithoutScalingLabelsOrRebuildingReselectedPage() {
        launch().use { scenario ->
            listOf(1, 3, 0, 2, 3, 1).forEach { index ->
                scenario.onActivity { activity -> activity.findViewById<View>(id(navigationNames[index])).performClick() }
                device.waitForIdle()
                scenario.onActivity { activity ->
                    val nav = activity.findViewById<ViewGroup>(id("phone_navigation"))
                    val indicator = activity.findViewById<View>(id("phone_navigation_indicator"))
                    val selected = activity.findViewById<TextView>(id(navigationNames[index]))
                    assertTrue(selected.isSelected)
                    assertTrue(selected.height >= activity.dp(48))
                    val indicatorRect = Rect().also(indicator::getGlobalVisibleRect)
                    val selectedRect = Rect().also(selected::getGlobalVisibleRect)
                    val navRect = Rect().also(nav::getGlobalVisibleRect)
                    assertEquals(selectedRect.exactCenterX(), indicatorRect.exactCenterX(), 1f)
                    assertEquals(selectedRect.exactCenterY(), indicatorRect.exactCenterY(), 1f)
                    assertTrue(navRect.contains(indicatorRect))
                    navigationNames.forEach { name ->
                        val tab = activity.findViewById<TextView>(id(name))
                        assertEquals(1f, tab.scaleX, 0f)
                        assertEquals(1f, tab.scaleY, 0f)
                        assertEquals(1, tab.maxLines)
                        assertEquals("Only the active destination should stay bold",
                            tab.isSelected, tab.typeface.isBold)
                    }
                    val pageName = listOf("page_planner", "page_calendar", "page_query", "page_settings")[index]
                    val page = activity.findViewById<View>(id(pageName))
                    selected.performClick()
                    if (index == 3) assertSame(page, activity.findViewById(id(pageName)))
                }
            }
        }
    }

    @Test fun selectionAnimationSurvivesLayoutAndRtlUsesPhysicalCoordinates() {
        org.junit.Assume.assumeTrue(android.animation.ValueAnimator.areAnimatorsEnabled())
        launch().use { scenario ->
            scenario.onActivity { activity ->
                activity.findViewById<View>(id("phone_navigation")).layoutDirection = View.LAYOUT_DIRECTION_LTR
                activity.findViewById<View>(id("navigation_planner")).performClick()
            }
            device.waitForIdle()
            data class FrameSample(
                val elapsedMillis: Long,
                val centerX: Float,
                val selectedIndex: Int,
                val layoutCount: Int,
                val originalBarMounted: Boolean,
            )
            val animationFinished = CountDownLatch(1)
            val samples = mutableListOf<FrameSample>()
            var start = 0f
            var target = 0f
            var durationScale = 1f
            var cleanup: () -> Unit = {}
            scenario.onActivity { activity ->
                val nav = activity.findViewById<PhoneNavigationBar>(id("phone_navigation"))
                val indicator = activity.findViewById<View>(id("phone_navigation_indicator"))
                val destination = activity.findViewById<TextView>(id("navigation_settings"))
                val destinationBounds = Rect().also(destination::getDrawingRect)
                nav.offsetDescendantRectToMyCoords(destination, destinationBounds)
                start = indicator.x + indicator.width / 2f
                target = destinationBounds.exactCenterX()
                durationScale = android.provider.Settings.Global.getFloat(
                    activity.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f,
                )
                var layouts = 0
                val layoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> layouts++ }
                nav.addOnLayoutChangeListener(layoutListener)
                val choreographer = android.view.Choreographer.getInstance()
                val startedAt = android.os.SystemClock.uptimeMillis()
                var settledFrames = 0
                val frameCallback = object : android.view.Choreographer.FrameCallback {
                    override fun doFrame(frameTimeNanos: Long) {
                        val center = indicator.x + indicator.width / 2f
                        val mounted = activity.findViewById<View>(id("phone_navigation")) === nav && nav.isAttachedToWindow
                        val selected = navigationNames.indexOfFirst { activity.findViewById<View>(id(it)).isSelected }
                        samples += FrameSample(android.os.SystemClock.uptimeMillis() - startedAt,
                            center, selected, layouts, mounted)
                        settledFrames = if (kotlin.math.abs(center - target) <= 1f) settledFrames + 1 else 0
                        if (settledFrames >= 2 || !mounted || selected != 3) {
                            animationFinished.countDown()
                        } else {
                            choreographer.postFrameCallback(this)
                        }
                    }
                }
                cleanup = {
                    choreographer.removeFrameCallback(frameCallback)
                    nav.removeOnLayoutChangeListener(layoutListener)
                }
                // Keep Activity state consistent with the animated selection. A direct
                // nav.select call leaves background page refreshes targeting Planner.
                destination.performClick()
                nav.requestLayout()
                choreographer.postFrameCallback(frameCallback)
            }
            val completed = try {
                animationFinished.await(5, TimeUnit.SECONDS)
            } finally {
                instrumentation.runOnMainSync { cleanup() }
            }
            val diagnostics = "start=$start target=$target scale=$durationScale frames=" + samples.joinToString {
                "${it.elapsedMillis}ms:${it.centerX}(selected=${it.selectedIndex},layouts=${it.layoutCount},mounted=${it.originalBarMounted})"
            }
            println("Navigation animation samples: $diagnostics")
            android.util.Log.i("NavigationVisualPolish", diagnostics)
            assertTrue("Animation must finish on the original destination: $diagnostics", completed)
            assertTrue("The target must differ from the starting selection: $diagnostics", target > start + 1f)
            assertTrue("Every frame must retain the real Settings destination and original bar: $diagnostics",
                samples.isNotEmpty() && samples.all { it.selectedIndex == 3 && it.originalBarMounted })
            val intermediate = samples.filter { it.centerX > start + 1f && it.centerX < target - 1f }
            assertTrue("Selection needs multiple distinct intermediate frames, not a jump: $diagnostics",
                intermediate.size >= 2 && intermediate.maxOf { it.centerX } - intermediate.minOf { it.centerX } > 1f)
            assertTrue("A content layout must occur before the animation finishes: $diagnostics",
                intermediate.any { it.layoutCount > 0 })
            assertTrue("Animation must move monotonically toward its destination: $diagnostics",
                samples.zipWithNext().all { (previous, next) -> next.centerX >= previous.centerX - 1f })
            assertEquals("Selection must settle at the measured target: $diagnostics", target, samples.last().centerX, 1f)
            device.waitForIdle()
            scenario.onActivity { activity ->
                activity.findViewById<View>(id("phone_navigation")).layoutDirection = View.LAYOUT_DIRECTION_RTL
            }
            device.waitForIdle()
            scenario.onActivity { activity ->
                activity.findViewById<View>(id("navigation_planner")).performClick()
            }
            device.waitForIdle()
            scenario.onActivity { activity ->
                val indicator = activity.findViewById<View>(id("phone_navigation_indicator"))
                val tab = activity.findViewById<View>(id("navigation_planner"))
                val indicatorRect = Rect().also(indicator::getGlobalVisibleRect)
                val tabRect = Rect().also(tab::getGlobalVisibleRect)
                assertEquals(tabRect.exactCenterX(), indicatorRect.exactCenterX(), 1f)
                assertEquals(tabRect.exactCenterY(), indicatorRect.exactCenterY(), 1f)
                assertTrue(tab.isSelected)
                val navRect = Rect().also(activity.findViewById<View>(id("phone_navigation"))::getGlobalVisibleRect)
                assertTrue("RTL selection must remain entirely within the capsule", navRect.contains(indicatorRect))
            }
        }
    }

    @Test fun captionsFitOrIconsRemainCenteredWithAccessibleLabels() {
        launch().use { scenario ->
            device.waitForIdle()
            scenario.onActivity { activity ->
                navigationNames.forEach { name ->
                    val tab = activity.findViewById<TextView>(id(name))
                    assertFalse(tab.contentDescription.isNullOrBlank())
                    if (tab.text.isNullOrBlank()) {
                        assertNotNull(tab.foreground)
                        assertEquals(android.view.Gravity.CENTER, tab.foregroundGravity)
                        assertTrue(tab.compoundDrawables.all { it == null })
                    } else {
                        assertTrue("Caption must fit vertically", tab.layout.height <=
                            tab.height - tab.compoundPaddingTop - tab.compoundPaddingBottom + 2)
                        assertEquals("Caption must not be truncated", 0, tab.layout.getEllipsisCount(0))
                    }
                }
            }
        }
    }
}
