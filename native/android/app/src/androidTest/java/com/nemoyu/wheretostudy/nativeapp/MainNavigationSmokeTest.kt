package com.nemoyu.wheretostudy.nativeapp

import android.app.NotificationManager
import android.app.job.JobScheduler
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.HorizontalScrollView
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
            assertVisible(device, "adaptive_root")
            var navigationResource = ""
            scenario.onActivity { activity ->
                navigationResource = if (
                    activity.findViewById<View?>(R.id.phone_navigation) != null
                ) {
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
            var usesCompactCalendar = false
            scenario.onActivity { activity ->
                usesCompactCalendar = activity.findViewById<View?>(
                    R.id.calendar_phone_header,
                ) != null
            }
            if (usesCompactCalendar) {
                assertVisible(device, "calendar_phone_header")
                assertVisible(device, "calendar_mode_switch")
                assertVisible(device, "calendar_date_strip")
                assertVisible(device, "calendar_timeline_scroll")

                click(device, "calendar_mode_day")
                assertVisible(device, "calendar_timeline")
                val dayBeforeSwipe = objectText(device, "calendar_period_label")
                swipeResource(device, "calendar_timeline_scroll", horizontalDirection = 1)
                assertTextChanged(device, "calendar_period_label", dayBeforeSwipe)
                swipeResource(device, "calendar_timeline_scroll", horizontalDirection = 0)
                scenario.onActivity { activity ->
                    assertTrue(
                        "Vertical timeline gestures must continue scrolling after page-swipe handling",
                        activity.findViewById<ScrollView>(R.id.calendar_timeline_scroll).scrollY > 0,
                    )
                }

                click(device, "calendar_mode_week")
                assertVisible(device, "calendar_timeline")
                scenario.onActivity { activity ->
                    val timeline = activity.findViewById<View>(R.id.calendar_timeline)
                    assertTrue(
                        "Compact week timeline must fit within its phone viewport",
                        timeline.width <= (timeline.parent as View).width,
                    )
                    assertTrue(
                        "Compact week date strip must use fixed columns instead of horizontal scrolling",
                        activity.findViewById<View>(R.id.calendar_date_strip) !is HorizontalScrollView,
                    )
                    assertTrue(
                        "Compact week timeline must not create a horizontal scroller",
                        activity.findViewById<View?>(R.id.calendar_timeline_day_scroll) == null,
                    )
                }

                click(device, "calendar_mode_month")
                assertVisible(device, "calendar_period_label")
                assertVisible(device, "calendar_month_weekday_header")
                assertVisible(device, "calendar_month_grid")
                assertVisible(device, "calendar_month_drag_handle")
                assertGone(device, "calendar_month_selected_details")
                scenario.onActivity { activity ->
                    val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                    val firstRowHeightDp = grid.getChildAt(0).height /
                        activity.resources.displayMetrics.density
                    assertTrue(
                        "Expanded month rows must stay close to the native iOS height",
                        firstRowHeightDp <= TeachingCalendarLogic.monthCellHeightDp(expanded = true) + 1,
                    )
                }
                var monthViewIdentity = 0
                var monthGridIdentity = 0
                var monthHeaderTop = 0
                var weekdayHeaderTop = 0
                scenario.onActivity { activity ->
                    val monthView = activity.findViewById<View>(R.id.calendar_month_view)
                    val monthGrid = activity.findViewById<View>(R.id.calendar_month_grid)
                    monthViewIdentity = System.identityHashCode(monthView)
                    monthGridIdentity = System.identityHashCode(monthGrid)
                    monthHeaderTop = activity.findViewById<View>(R.id.calendar_period_label).top
                    weekdayHeaderTop = activity.findViewById<View>(R.id.calendar_month_weekday_header).top
                    assertFalse(
                        "Compact month view must not be a vertical scrolling region",
                        monthView is ScrollView,
                    )
                }
                swipeResource(device, "calendar_month_grid", horizontalDirection = 0)
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = true,
                )
                scenario.onActivity { activity ->
                    assertEquals(
                        "Month expansion must animate the existing view instead of replacing it",
                        monthViewIdentity,
                        System.identityHashCode(activity.findViewById<View>(R.id.calendar_month_view)),
                    )
                    assertEquals(
                        "Month expansion must keep the existing date grid",
                        monthGridIdentity,
                        System.identityHashCode(activity.findViewById<View>(R.id.calendar_month_grid)),
                    )
                    assertEquals(
                        "Month heading must remain fixed while the date grid changes height",
                        monthHeaderTop,
                        activity.findViewById<View>(R.id.calendar_period_label).top,
                    )
                    assertEquals(
                        "Weekday header must remain fixed while the date grid changes height",
                        weekdayHeaderTop,
                        activity.findViewById<View>(R.id.calendar_month_weekday_header).top,
                    )
                }
                swipeResource(device, "calendar_month_grid", horizontalDirection = 0, reverseVertical = true)
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = false,
                )
                val monthBeforeSwipe = objectText(device, "calendar_period_label")
                swipeResource(device, "calendar_month_grid", horizontalDirection = 1)
                assertTextChanged(device, "calendar_period_label", monthBeforeSwipe)
                click(device, "calendar_mode_year")
                assertVisible(device, "calendar_period_label")
                click(device, "calendar_mode_week")
                assertVisible(device, "calendar_date_strip")
            } else {
                click(device, "calendar_mode_week")
                assertVisible(device, "calendar_timeline_day_scroll")
                scrollGestureTargetIntoView(device, "calendar_timeline_day_scroll")
                val weekBeforeTimelineSwipe = activityText(
                    scenario,
                    R.id.calendar_period_label,
                )
                assertTrue(
                    "Large-screen calendar must expose next-period navigation",
                    performAncestorAccessibilityAction(
                        scenario,
                        R.id.calendar_swipe_surface,
                        AccessibilityNodeInfo.ACTION_SCROLL_FORWARD,
                    ),
                )
                assertActivityTextChanged(
                    scenario,
                    R.id.calendar_period_label,
                    weekBeforeTimelineSwipe,
                )
                scenario.onActivity { activity ->
                    activity.findViewById<ScrollView>(R.id.page_calendar).scrollTo(0, 0)
                }
                device.waitForIdle()

                click(device, "calendar_mode_month")
                assertVisible(device, "calendar_month_weekday_header")
                assertVisible(device, "calendar_month_grid")
                assertVisible(device, "calendar_month_drag_handle")
                assertGone(device, "calendar_month_selected_details")
                var monthViewIdentity = 0
                var monthGridIdentity = 0
                scenario.onActivity { activity ->
                    monthViewIdentity = System.identityHashCode(
                        activity.findViewById<View>(R.id.calendar_month_view),
                    )
                    monthGridIdentity = System.identityHashCode(
                        activity.findViewById<View>(R.id.calendar_month_grid),
                    )
                }
                swipeResource(device, "calendar_swipe_surface", horizontalDirection = 0)
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = true,
                )
                scenario.onActivity { activity ->
                    assertEquals(
                        "Expanded month must animate the existing view on large screens",
                        monthViewIdentity,
                        System.identityHashCode(
                            activity.findViewById<View>(R.id.calendar_month_view),
                        ),
                    )
                    assertEquals(
                        "Expanded month must retain the date grid on large screens",
                        monthGridIdentity,
                        System.identityHashCode(
                            activity.findViewById<View>(R.id.calendar_month_grid),
                        ),
                    )
                }
                swipeResource(device, "page_calendar", horizontalDirection = 0)
                scenario.onActivity { activity ->
                    assertTrue(
                        "Collapsed month details must remain vertically scrollable",
                        activity.findViewById<ScrollView>(R.id.page_calendar).scrollY > 0,
                    )
                    assertNotNull(activity.findViewById<View>(R.id.calendar_month_selected_details))
                }
                swipeResource(device, "calendar_swipe_surface", horizontalDirection = 0, reverseVertical = true)
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = true,
                )
                scenario.onActivity { activity ->
                    activity.findViewById<ScrollView>(R.id.page_calendar).scrollTo(0, 0)
                }
                swipeResource(device, "calendar_swipe_surface", horizontalDirection = 0, reverseVertical = true)
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = false,
                )
                swipeResource(device, "calendar_swipe_surface", horizontalDirection = 0)
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = true,
                )
            }

            click(device, "calendar_mode_month")
            assertVisible(device, "calendar_month_grid")
            assertMonthExpansionFollowsFinger(scenario)
            var monthIsCollapsed = false
            scenario.onActivity { activity ->
                monthIsCollapsed = activity.findViewById<View?>(
                    R.id.calendar_month_selected_details,
                )?.visibility == View.VISIBLE
            }
            if (monthIsCollapsed) {
                assertTrue(
                    "The month gesture surface must expose an accessibility expand action",
                    performAncestorAccessibilityAction(
                        scenario,
                        R.id.calendar_month_grid,
                        AccessibilityNodeInfo.ACTION_EXPAND,
                    ),
                )
                device.waitForIdle()
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = false,
                )
            }
            assertTrue(
                "The month gesture surface must expose an accessibility collapse action",
                performAncestorAccessibilityAction(
                    scenario,
                    R.id.calendar_month_grid,
                    AccessibilityNodeInfo.ACTION_COLLAPSE,
                ),
            )
            device.waitForIdle()
            assertActivityViewMounted(
                scenario,
                R.id.calendar_month_selected_details,
                expected = true,
            )
            val monthBeforeRecreation = activityText(
                scenario,
                R.id.calendar_period_label,
            )
            scenario.recreate()
            device.waitForIdle()
            assertVisible(device, "page_calendar")
            assertVisible(device, "calendar_month_grid")
            assertActivityViewMounted(
                scenario,
                R.id.calendar_month_selected_details,
                expected = true,
            )
            assertEquals(
                "Activity recreation must preserve the selected month",
                monthBeforeRecreation,
                activityText(scenario, R.id.calendar_period_label),
            )

            click(device, "navigation_settings")
            assertVisible(device, "page_settings")
            scrollUntilVisible(device, "privacy_policy_button")
            scenario.onActivity { activity ->
                val about = activity.findViewById<View>(R.id.settings_about_section)
                val settingsPage = activity.findViewById<ScrollView>(R.id.page_settings)
                val settingsContent = settingsPage.getChildAt(0) as ViewGroup
                assertEquals(
                    "About section must be the final settings block",
                    about,
                    settingsContent.getChildAt(settingsContent.childCount - 1),
                )
                assertTrue(
                    "Privacy entry must remain inside the about section",
                    activity.findViewById<View>(R.id.privacy_policy_button).parent === about,
                )
            }
            click(device, "privacy_policy_button")
            assertVisible(device, "privacy_policy_content")
            scrollUntilVisible(device, "privacy_github_link")
            device.pressBack()
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

    private fun assertGone(device: UiDevice, resourceName: String) {
        val gone = device.wait(
            Until.gone(By.res(TARGET_PACKAGE, resourceName)),
            UI_TIMEOUT_MILLIS,
        )
        assertTrue("View should not be visible: $resourceName", gone)
    }

    private fun assertActivityViewMounted(
        scenario: ActivityScenario<MainActivity>,
        viewId: Int,
        expected: Boolean,
    ) {
        val deadline = System.currentTimeMillis() + UI_TIMEOUT_MILLIS
        var mounted = false
        while (System.currentTimeMillis() < deadline) {
            scenario.onActivity { activity ->
                mounted = activity.findViewById<View?>(viewId)?.visibility == View.VISIBLE
            }
            if (mounted == expected) return
            Thread.sleep(100L)
        }
        assertEquals("Unexpected visible state for view id $viewId", expected, mounted)
    }

    private fun activityText(
        scenario: ActivityScenario<MainActivity>,
        viewId: Int,
    ): String {
        var text = ""
        scenario.onActivity { activity ->
            text = activity.findViewById<TextView>(viewId).text.toString()
        }
        return text
    }

    private fun performAncestorAccessibilityAction(
        scenario: ActivityScenario<MainActivity>,
        viewId: Int,
        action: Int,
    ): Boolean {
        var performed = false
        scenario.onActivity { activity ->
            var candidate: View? = activity.findViewById(viewId)
            while (candidate != null && !performed) {
                performed = candidate.performAccessibilityAction(action, null)
                candidate = candidate.parent as? View
            }
        }
        return performed
    }

    private fun objectText(device: UiDevice, resourceName: String): String {
        val view = device.wait(
            Until.findObject(By.res(TARGET_PACKAGE, resourceName)),
            UI_TIMEOUT_MILLIS,
        )
        assertNotNull("Missing text view: $resourceName", view)
        return view.text
    }

    private fun assertTextChanged(device: UiDevice, resourceName: String, previous: String) {
        val deadline = System.currentTimeMillis() + UI_TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            val current = device.findObject(By.res(TARGET_PACKAGE, resourceName))?.text
            if (current != null && current != previous) return
            Thread.sleep(100L)
        }
        assertTrue("Text did not change for $resourceName", false)
    }

    private fun assertActivityTextChanged(
        scenario: ActivityScenario<MainActivity>,
        viewId: Int,
        previous: String,
    ) {
        val deadline = System.currentTimeMillis() + UI_TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            if (activityText(scenario, viewId) != previous) return
            Thread.sleep(100L)
        }
        assertTrue("Text did not change for view id $viewId", false)
    }

    private fun swipeResource(
        device: UiDevice,
        resourceName: String,
        horizontalDirection: Int,
        reverseVertical: Boolean = false,
    ) {
        val view = device.wait(
            Until.findObject(By.res(TARGET_PACKAGE, resourceName)),
            UI_TIMEOUT_MILLIS,
        )
        assertNotNull("Missing swipe view: $resourceName", view)
        val bounds = view.visibleBounds
        if (horizontalDirection != 0) {
            val startX = if (horizontalDirection > 0) bounds.right - bounds.width() / 6 else bounds.left + bounds.width() / 6
            val endX = if (horizontalDirection > 0) bounds.left + bounds.width() / 6 else bounds.right - bounds.width() / 6
            device.executeShellCommand(
                "input swipe $startX ${bounds.centerY()} $endX ${bounds.centerY()} 350",
            )
        } else {
            val screenMargin = (device.displayHeight / 50).coerceAtLeast(12)
            val edgeInset = (bounds.height() / 6).coerceIn(4, 32)
            val availableTravel = (bounds.height() - edgeInset * 2).coerceAtLeast(1)
            val travel = minOf(
                maxOf(bounds.height() / 2, device.displayHeight / 5),
                availableTravel,
                device.displayHeight - screenMargin * 2,
            )
            val upperY = (bounds.centerY() - travel / 2).coerceAtLeast(
                maxOf(bounds.top + edgeInset, screenMargin),
            )
            val lowerY = (upperY + travel).coerceAtMost(
                minOf(bounds.bottom - edgeInset, device.displayHeight - screenMargin),
            )
            val startY = if (reverseVertical) upperY else lowerY
            val endY = if (reverseVertical) lowerY else upperY
            device.swipe(bounds.centerX(), startY, bounds.centerX(), endY, 24)
        }
        device.waitForIdle()
    }

    private fun assertMonthExpansionFollowsFinger(
        scenario: ActivityScenario<MainActivity>,
    ) {
        scenario.onActivity { activity ->
            val swipeSurface = activity.findViewById<View>(R.id.calendar_swipe_surface)
            val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
            val firstRow = grid.getChildAt(0)
            val details = activity.findViewById<View>(R.id.calendar_month_selected_details)
            val initiallyExpanded = details.visibility != View.VISIBLE
            val density = activity.resources.displayMetrics.density
            val collapsedHeight = activity.dp(TeachingCalendarLogic.monthCellHeightDp(false))
            val expandedHeight = activity.dp(TeachingCalendarLogic.monthCellHeightDp(true))
            val direction = if (initiallyExpanded) -1f else 1f
            val startedAt = SystemClock.uptimeMillis()
            val x = swipeSurface.width / 2f
            val y = swipeSurface.height / 2f

            fun dispatch(action: Int, offsetDp: Float, elapsedMillis: Long) {
                MotionEvent.obtain(
                    startedAt,
                    startedAt + elapsedMillis,
                    action,
                    x,
                    y + offsetDp * density,
                    0,
                ).also { event ->
                    swipeSurface.dispatchTouchEvent(event)
                    event.recycle()
                }
            }

            dispatch(MotionEvent.ACTION_DOWN, 0f, 0L)
            dispatch(MotionEvent.ACTION_MOVE, direction * 16f, 32L)
            dispatch(MotionEvent.ACTION_MOVE, direction * 66f, 96L)

            assertTrue(
                "Month row height must follow an in-progress drag instead of waiting for release",
                firstRow.layoutParams.height in (collapsedHeight + 1) until expandedHeight,
            )
            dispatch(MotionEvent.ACTION_CANCEL, direction * 66f, 112L)
        }
        Thread.sleep(360L)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun scrollUntilVisible(device: UiDevice, resourceName: String) {
        repeat(8) {
            if (device.hasObject(By.res(TARGET_PACKAGE, resourceName))) return
            device.swipe(
                device.displayWidth / 2,
                device.displayHeight * 3 / 4,
                device.displayWidth / 2,
                device.displayHeight / 4,
                20,
            )
            device.waitForIdle()
        }
        assertVisible(device, resourceName)
    }

    private fun scrollGestureTargetIntoView(device: UiDevice, resourceName: String) {
        repeat(8) {
            val target = device.findObject(By.res(TARGET_PACKAGE, resourceName))
            val bounds = try {
                target?.visibleBounds
            } catch (_: androidx.test.uiautomator.StaleObjectException) {
                null
            }
            if (bounds != null &&
                bounds.height() >= maxOf(device.displayHeight / 4, 160) &&
                bounds.centerY() in (device.displayHeight / 4)..(device.displayHeight * 3 / 4)
            ) {
                return
            }
            device.swipe(
                device.displayWidth / 2,
                device.displayHeight * 3 / 4,
                device.displayWidth / 2,
                device.displayHeight / 3,
                20,
            )
            device.waitForIdle()
        }
        assertTrue("Gesture target must occupy a usable portion of the viewport", false)
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
