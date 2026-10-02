package com.nemoyu.wheretostudy.nativeapp

import android.animation.ValueAnimator
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Sample-mode UI motion checks. Run each method in a fresh target process with animator scale 1. */
@RunWith(AndroidJUnit4::class)
class MotionLifecycleAuditUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Before fun privacy() = ensurePrivacyConsentForUiTest()

    private fun withAnimatedScenario(
        weatherEnabled: Boolean = true,
        block: (ActivityScenario<MainActivity>) -> Unit,
    ) {
        val device = UiDevice.getInstance(instrumentation)
        val originalScale = device.executeShellCommand("settings get global animator_duration_scale").trim()
        val preferences = AppPreferences(context)
        val originalWeather = preferences.weatherEnabled
        val originalLanguage = preferences.languageCode
        device.executeShellCommand("settings put global animator_duration_scale 1")
        preferences.weatherEnabled = weatherEnabled
        preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                if (Build.VERSION.SDK_INT >= 26) {
                    var enabled = false
                    scenario.onActivity { enabled = ValueAnimator.areAnimatorsEnabled() }
                    assertTrue("Animator scale 1 must be active before this UI test", enabled)
                }
                block(scenario)
            }
        } finally {
            preferences.weatherEnabled = originalWeather
            preferences.languageCode = originalLanguage
            if (originalScale.matches(Regex("^[0-9]+(?:\\.[0-9]+)?$"))) {
                device.executeShellCommand("settings put global animator_duration_scale $originalScale")
            } else {
                device.executeShellCommand("settings delete global animator_duration_scale")
            }
        }
    }

    private fun afterFrame(
        scenario: ActivityScenario<MainActivity>,
        delayMillis: Long = 80L,
        before: (MainActivity) -> Unit = {},
        check: (MainActivity) -> Unit,
    ) {
        val completed = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        scenario.onActivity { activity ->
            before(activity)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    check(activity)
                } catch (error: Throwable) {
                    failure.set(error)
                } finally {
                    completed.countDown()
                }
            }, delayMillis)
        }
        assertTrue("The animation frame callback must run", completed.await(5, TimeUnit.SECONDS))
        failure.get()?.let { throw AssertionError("Animation frame assertion failed", it) }
    }

    private fun plannerMotion(activity: MainActivity): DisclosureMotionController {
        val planner = MainActivity::class.java.getDeclaredField("plannerPage")
            .apply { isAccessible = true }.get(activity) as PlannerPage
        return PlannerPage::class.java.getDeclaredField("weatherMotion")
            .apply { isAccessible = true }.get(planner) as DisclosureMotionController
    }

    private fun queryPage(activity: MainActivity): InformationQueryPage =
        MainActivity::class.java.getDeclaredField("informationQueryPage")
            .apply { isAccessible = true }.get(activity) as InformationQueryPage

    @Test fun weatherDisclosureKeepsScrollAndViewportAcrossPublicationAndRapidReverse() =
        withAnimatedScenario(weatherEnabled = true) { scenario ->
            lateinit var scroll: ScrollView
            lateinit var surface: View
            lateinit var viewport: ViewGroup
            lateinit var toggle: View
            lateinit var motion: DisclosureMotionController
            var collapsedSurfaceHeight = 0
            scenario.onActivity { activity ->
                scroll = activity.findViewById(R.id.page_planner)
                surface = activity.findViewById(R.id.planner_weather_surface)
                viewport = activity.findViewById(R.id.planner_weather_content)
                toggle = activity.findViewById(R.id.planner_weather_toggle)
                motion = plannerMotion(activity)
                collapsedSurfaceHeight = surface.height
                assertEquals(View.GONE, viewport.visibility)
                assertTrue(toggle.performClick())
            }
            SystemClock.sleep(320L)
            instrumentation.waitForIdleSync()
            var expandedHeight = 0
            var expandedSurfaceHeight = 0
            scenario.onActivity { activity ->
                assertSame(scroll, activity.findViewById(R.id.page_planner))
                assertSame(viewport, activity.findViewById(R.id.planner_weather_content))
                expandedHeight = viewport.height
                expandedSurfaceHeight = surface.height
                assertTrue("The sample weather card needs real rows", expandedHeight > activity.dp(30))
                assertTrue(expandedSurfaceHeight > collapsedSurfaceHeight)
                assertTrue(toggle.performClick())
            }
            afterFrame(scenario) { activity ->
                val middleHeight = viewport.layoutParams.height
                assertSame(scroll, activity.findViewById(R.id.page_planner))
                assertSame(surface, activity.findViewById(R.id.planner_weather_surface))
                assertSame(viewport, activity.findViewById(R.id.planner_weather_content))
                assertTrue("Weather content height must have an intermediate frame",
                    middleHeight in 1 until expandedHeight)
                assertTrue("Weather content must fade with its height", viewport.alpha > 0f && viewport.alpha < 1f)
                assertTrue("The parent card must follow the content height",
                    surface.height in (collapsedSurfaceHeight + 1) until expandedSurfaceHeight)
                val indicator = activity.findViewById<ImageView>(R.id.planner_weather_indicator)
                assertTrue(indicator.rotation > 0f && indicator.rotation < 180f)

                // Both publications are UI-only; neither may replace the current weather viewport.
                activity.refreshPlannerWeatherIfVisible()
                activity.refreshPlannerIfVisible()
                assertTrue(toggle.performClick())
                assertEquals("Quick reversal starts at the displayed height",
                    middleHeight, viewport.layoutParams.height)
            }
            SystemClock.sleep(330L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                assertSame(scroll, activity.findViewById(R.id.page_planner))
                assertSame(surface, activity.findViewById(R.id.planner_weather_surface))
                assertSame(viewport, activity.findViewById(R.id.planner_weather_content))
                assertEquals(View.VISIBLE, viewport.visibility)
                assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, viewport.layoutParams.height)
                assertEquals(1f, viewport.alpha, 0.01f)
                assertEquals(180f,
                    activity.findViewById<ImageView>(R.id.planner_weather_indicator).rotation, 0.5f)
                assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
                assertFalse(surface.isAttachedToWindow)
                assertFalse("Detached weather animation must release its owner", motion.isRunning)
            }
            SystemClock.sleep(300L)
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_planner).performClick())
                assertNotSame(scroll, activity.findViewById(R.id.page_planner))
                assertFalse(surface.isAttachedToWindow)
            }
        }

    @Test fun queryPublicationDoesNotCutSegmentMidFrameOrReviveOldBodyAfterLeave() =
        withAnimatedScenario { scenario ->
            lateinit var root: ViewGroup
            lateinit var selector: View
            lateinit var scroll: ScrollView
            lateinit var content: FrameLayout
            lateinit var examsBody: View
            lateinit var eventsBody: View
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
                root = activity.findViewById(R.id.information_query_page)
                selector = activity.findViewById(R.id.information_query_mode_switch)
                scroll = activity.findViewById(R.id.information_query_shuttle_scroll)
                content = activity.findViewById(R.id.information_query_content)
                assertTrue(activity.findViewById<View>(R.id.information_query_exams_tab).performClick())
                examsBody = content.getChildAt(0)
                queryPage(activity).scheduleDidRefresh()
                assertSame("A publication during entry must wait for the page animation",
                    examsBody, content.getChildAt(0))
            }
            afterFrame(scenario) { activity ->
                assertSame(root, activity.findViewById(R.id.information_query_page))
                assertSame(selector, activity.findViewById(R.id.information_query_mode_switch))
                assertSame(scroll, activity.findViewById(R.id.information_query_exams_scroll))
                assertSame(examsBody, content.getChildAt(0))
                assertTrue("Exams entry needs an intermediate opacity",
                    examsBody.alpha > 0f && examsBody.alpha < 1f)
                assertTrue("Exams entry needs an intermediate offset",
                    examsBody.translationX > 0f && examsBody.translationX < activity.dp(16))
                assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
                eventsBody = content.getChildAt(0)
                assertNotSame(examsBody, eventsBody)
                assertTrue(eventsBody.translationX < 0f)
            }
            afterFrame(scenario) { activity ->
                assertSame(scroll, activity.findViewById(R.id.information_query_events_scroll))
                assertSame(eventsBody, content.getChildAt(0))
                assertTrue("Reverse entry must have an intermediate opacity",
                    eventsBody.alpha > 0f && eventsBody.alpha < 1f)
                assertTrue(eventsBody.translationX < 0f && eventsBody.translationX > -activity.dp(16))
                assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                assertFalse(root.isAttachedToWindow)
                assertFalse(eventsBody.isAttachedToWindow)
            }
            SystemClock.sleep(340L)
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
                val returned = activity.findViewById<FrameLayout>(R.id.information_query_content)
                assertEquals(1, returned.childCount)
                assertEquals(1f, returned.getChildAt(0).alpha, 0.01f)
                assertEquals(0f, returned.getChildAt(0).translationX, 0.5f)
                assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).isSelected)
                assertFalse(root.isAttachedToWindow)
            }
        }

    @Test fun monthSheetFrameIsCancelledByPagingAndViewChangeWithoutOldOwnerWrites() =
        withAnimatedScenario { scenario ->
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                assertTrue(activity.findViewById<View>(R.id.calendar_mode_month).performClick())
            }
            SystemClock.sleep(TeachingCalendarLogic.pageAnimationDurationMillis + 100L)
            instrumentation.waitForIdleSync()
            lateinit var oldMonth: ViewGroup
            var expandedViewportHeight = 0
            var detailsViewportHeight = 0
            afterFrame(scenario, before = { activity ->
                oldMonth = activity.findViewById(R.id.calendar_month_view)
                val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                expandedViewportHeight = activity.findViewById<View>(R.id.calendar_month_grid_viewport).height
                detailsViewportHeight = grid.childCount * activity.dp(
                    TeachingCalendarLogic.monthCellHeightDp(false))
                assertTrue("The fixture needs room for a month-sheet transition",
                    expandedViewportHeight > detailsViewportHeight + activity.dp(10))
                assertTrue(activity.findViewById<View>(R.id.calendar_month_drag_handle).performClick())
            }) { activity ->
                assertSame(oldMonth, activity.findViewById(R.id.calendar_month_view))
                val viewport = activity.findViewById<View>(R.id.calendar_month_grid_viewport)
                val middle = viewport.height
                val handle = activity.findViewById<View>(R.id.calendar_month_drag_handle)
                assertTrue("Month viewport must reveal a true intermediate frame: " +
                    "expanded=$expandedViewportHeight details=$detailsViewportHeight " +
                    "middle=$middle requested=${viewport.layoutParams.height} " +
                    "handle=${handle.contentDescription}",
                    middle in (detailsViewportHeight + 1) until expandedViewportHeight)
                val periodLabel = activity.findViewById<TextView>(R.id.calendar_period_label)
                val navigation = periodLabel.parent as ViewGroup
                val next = (0 until navigation.childCount).map(navigation::getChildAt)
                    .filterIsInstance<TextView>().first { it.text.toString() == "›" }
                assertTrue(next.performClick())
            }
            SystemClock.sleep(TeachingCalendarLogic.pageAnimationDurationMillis + 130L)
            instrumentation.waitForIdleSync()
            lateinit var newMonth: ViewGroup
            scenario.onActivity { activity ->
                newMonth = activity.findViewById(R.id.calendar_month_view)
                assertNotSame(oldMonth, newMonth)
                assertFalse("The prior month's animator cannot retain an attached page", oldMonth.isAttachedToWindow)
                assertEquals(View.VISIBLE,
                    newMonth.findViewById<View>(R.id.calendar_month_selected_details).visibility)
                activity.findViewById<ViewGroup?>(R.id.calendar_swipe_surface)?.let { assertEquals(1, it.childCount) }
                assertTrue(activity.findViewById<View>(R.id.calendar_month_drag_handle).performClick())
            }
            afterFrame(scenario) { activity ->
                assertSame(newMonth, activity.findViewById(R.id.calendar_month_view))
                assertTrue(activity.findViewById<View>(R.id.calendar_mode_week).performClick())
            }
            SystemClock.sleep(TeachingCalendarLogic.pageAnimationDurationMillis + 130L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                // Calendar's fixed TextView tabs expose selection through their
                // bold style, not View.isSelected. Also verify the mounted body.
                assertTrue(activity.findViewById<TextView>(R.id.calendar_mode_week).typeface.isBold)
                assertTrue(activity.findViewById<View>(R.id.calendar_day_week_agenda_toggle).isAttachedToWindow)
                assertNull(activity.findViewById<View?>(R.id.calendar_month_view))
                assertFalse("A cancelled month-sheet callback cannot reattach the old page",
                    newMonth.isAttachedToWindow)
                activity.findViewById<ViewGroup?>(R.id.calendar_swipe_surface)?.let { assertEquals(1, it.childCount) }
                assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
            }
            SystemClock.sleep(330L)
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                assertTrue(activity.findViewById<TextView>(R.id.calendar_mode_week).typeface.isBold)
                assertTrue(activity.findViewById<View>(R.id.calendar_day_week_agenda_toggle).isAttachedToWindow)
                assertNull(activity.findViewById<View?>(R.id.calendar_month_view))
                assertFalse(oldMonth.isAttachedToWindow)
                assertFalse(newMonth.isAttachedToWindow)
            }
        }

    /** Run this method only on the tablet/foldable rail fixture, not on the phone fixture. */
    @Test fun tabletRailRapidReversalKeepsCurrentWidthAndCancelledEndCannotRebuildSettings() =
        withAnimatedScenario { scenario ->
            lateinit var rail: View
            lateinit var toggle: View
            var expandedWidth = 0
            scenario.onActivity { activity ->
                rail = activity.findViewById<View?>(R.id.tablet_navigation)
                    ?: throw AssertionError("This method requires a tablet or foldable rail layout")
                assertNull(activity.findViewById<View?>(R.id.phone_navigation))
                toggle = activity.findViewById(R.id.navigation_rail_toggle)
                expandedWidth = rail.width
                assertTrue(expandedWidth > activity.dp(AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP))
                assertTrue(toggle.performClick())
            }
            var collapsingWidth = 0
            afterFrame(scenario) { activity ->
                collapsingWidth = rail.layoutParams.width
                assertTrue("Rail collapse must have an intermediate frame",
                    collapsingWidth in (activity.dp(AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP) + 1)
                        until expandedWidth)
                assertTrue(toggle.performClick())
                assertEquals("First reversal must continue from the current rail width",
                    collapsingWidth, rail.layoutParams.width)
            }
            afterFrame(scenario) { activity ->
                val expandingWidth = rail.layoutParams.width
                assertTrue("Rail expansion must progress from its reversal point",
                    expandingWidth > collapsingWidth && expandingWidth < expandedWidth)
                assertTrue(toggle.performClick())
                assertEquals("Second reversal must not reset to an endpoint",
                    expandingWidth, rail.layoutParams.width)
            }
            SystemClock.sleep(340L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                assertEquals(activity.dp(AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP), rail.width)
                assertEquals("展开导航栏", toggle.contentDescription)
                assertTrue(toggle.performClick())
            }

            // From a settled collapsed spec, reverse expansion back to that same
            // target and leave for Settings. A cancelled expansion end-action
            // must not reconstruct the newly mounted Settings page.
            lateinit var settingsPage: View
            afterFrame(scenario) { activity ->
                val expandingWidth = rail.layoutParams.width
                assertTrue(expandingWidth > activity.dp(AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP))
                assertTrue(expandingWidth < expandedWidth)
                assertTrue(toggle.performClick())
                assertEquals(expandingWidth, rail.layoutParams.width)
                assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                settingsPage = activity.findViewById(R.id.page_settings)
            }
            SystemClock.sleep(340L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                assertSame("A cancelled rail end-action must not rebuild the current page",
                    settingsPage, activity.findViewById(R.id.page_settings))
                assertEquals(activity.dp(AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP), rail.width)
                assertEquals("展开导航栏", toggle.contentDescription)
            }
        }
}
