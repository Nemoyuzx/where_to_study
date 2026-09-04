package com.nemoyu.wheretostudy.nativeapp

import android.app.NotificationManager
import android.app.job.JobScheduler
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.TransitionDrawable
import android.os.SystemClock
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

@RunWith(AndroidJUnit4::class)
class MainNavigationSmokeTest {
    @Before
    fun acceptPrivacyConsent() = ensurePrivacyConsentForUiTest()

    @Test
    fun appTypographyFontScaleAppliesToActivityAndSpText() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val systemFontScale = context.resources.configuration.fontScale
        val launchIntent = Intent(
            context,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        assertEquals(0.92f, AppTypography.adjustedFontScale(1f), 0.0001f)
        assertEquals(0.46f, AppTypography.adjustedFontScale(0.5f), 0.0001f)

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                assertEquals(
                    "Activity resources must apply the shared one-step-smaller typography scale",
                    AppTypography.adjustedFontScale(systemFontScale),
                    activity.resources.configuration.fontScale,
                    0.0001f,
                )
                val text = TextView(activity).apply { textSize = 15f }
                assertEquals(
                    "Programmatic TextViews must consume the scaled SP density",
                    TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_SP,
                        15f,
                        activity.resources.displayMetrics,
                    ),
                    text.textSize,
                    0.5f,
                )
            }
        }
    }

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
    fun compactMonthDragHandsOffToDetailsAndKeepsScrollAcrossRefresh() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val launchIntent = Intent(
            instrumentation.targetContext,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                assertTrue(activity.findViewById<View>(R.id.calendar_mode_month).performClick())
            }
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                assertNotNull(
                    "This regression runs against the compact phone month layout",
                    activity.findViewById<View?>(R.id.calendar_phone_header),
                )
                val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                assertTrue((grid.getChildAt(1) as ViewGroup).getChildAt(3).performClick())
            }
            Thread.sleep(500L)
            instrumentation.waitForIdleSync()

            val longDragPoints = IntArray(4)
            scenario.onActivity { activity ->
                val surface = activity.findViewById<View>(R.id.calendar_swipe_surface)
                val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                val details = activity.findViewById<View>(R.id.calendar_month_selected_details)
                assertEquals(
                    "Selecting a day must commit the middle anchor before rendering",
                    activity.dp(TeachingCalendarLogic.monthCellHeightDp(expanded = false)),
                    grid.getChildAt(0).height,
                )
                assertEquals(
                    "月历与当日日程",
                    surface.createAccessibilityNodeInfo().contentDescription?.toString(),
                )
                val detailsLocation = IntArray(2).also(details::getLocationOnScreen)
                val surfaceLocation = IntArray(2).also(surface::getLocationOnScreen)
                val longDragDistancePx = activity.dp(420)
                longDragPoints[0] = detailsLocation[0] + details.width / 2
                val detailsBottom = detailsLocation[1] + details.height - activity.dp(16)
                val navigationTop = activity.findViewById<View?>(R.id.phone_navigation)?.let { navigation ->
                    IntArray(2).also(navigation::getLocationOnScreen)[1] - activity.dp(16)
                } ?: detailsBottom
                longDragPoints[1] = minOf(detailsBottom, navigationTop)
                longDragPoints[2] = longDragPoints[0]
                longDragPoints[3] = (longDragPoints[1] - longDragDistancePx).coerceAtLeast(
                    surfaceLocation[1] + 16,
                )
                assertTrue(longDragPoints[1] - longDragPoints[3] > longDragDistancePx / 2)
            }
            device.swipe(
                longDragPoints[0],
                longDragPoints[1],
                longDragPoints[2],
                longDragPoints[3],
                60,
            )
            device.waitForIdle()
            Thread.sleep(400L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                val details = activity.findViewById<ScrollView>(
                    R.id.calendar_month_selected_details,
                )
                assertSelectedWeekMonthViewport(activity, expectedWeekIndex = 1)
                assertTrue(
                    "Drag distance beyond the third anchor must continue into detail scrolling",
                    details.scrollY > 0,
                )
            }

            scenario.onActivity { activity ->
                val scrollBeforeRefresh = activity.findViewById<ScrollView>(
                    R.id.calendar_month_selected_details,
                ).scrollY
                assertTrue(scrollBeforeRefresh > 0)
                activity.refreshCalendarIfVisible()
            }
            Thread.sleep(500L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                val details = activity.findViewById<ScrollView>(
                    R.id.calendar_month_selected_details,
                )
                assertTrue(
                    "Async card refresh must preserve the user's detail scroll position",
                    details.scrollY > 0,
                )
            }

            scenario.recreate()
            device.waitForIdle()
            instrumentation.waitForIdleSync()
            var lockedPullDownX = 0
            var lockedPullDownStartY = 0
            var lockedPullDownEndY = 0
            scenario.onActivity { activity ->
                val details = activity.findViewById<ScrollView>(
                    R.id.calendar_month_selected_details,
                )
                assertSelectedWeekMonthViewport(activity, expectedWeekIndex = 1)
                assertTrue(
                    "Activity recreation must retain the detail scroll position",
                    details.scrollY > 0,
                )
                assertFalse(
                    "The month detail area must not show a vertical scroll bar",
                    details.isVerticalScrollBarEnabled,
                )
                assertTrue(
                    "The month detail viewport must clip cards to its rounded outer edge",
                    details.clipToOutline,
                )
                assertTrue(
                    "The month detail viewport padding must mask content at its edges",
                    details.clipToPadding,
                )
                assertNotNull(
                    "The month detail viewport needs an opaque rounded mask background",
                    details.background,
                )
                assertEquals(
                    "The detail area must not stretch when a top-edge pull changes detents",
                    View.OVER_SCROLL_NEVER,
                    details.overScrollMode,
                )
                val maximumScrollY = (details.getChildAt(0).height - details.height)
                    .coerceAtLeast(0)
                assertTrue(maximumScrollY > 0)
                details.scrollTo(0, activity.dp(4).coerceAtMost(maximumScrollY))
                assertTrue(details.canScrollVertically(-1))
                val detailsLocation = IntArray(2).also(details::getLocationOnScreen)
                lockedPullDownX = detailsLocation[0] + details.width / 2
                lockedPullDownStartY = detailsLocation[1] + activity.dp(40)
                lockedPullDownEndY = (lockedPullDownStartY + activity.dp(120)).coerceAtMost(
                    detailsLocation[1] + details.height - activity.dp(20),
                )
            }
            Thread.sleep(150L)
            instrumentation.waitForIdleSync()

            device.swipe(
                lockedPullDownX,
                lockedPullDownStartY,
                lockedPullDownX,
                lockedPullDownEndY,
                30,
            )
            device.waitForIdle()
            Thread.sleep(300L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                val details = activity.findViewById<ScrollView>(
                    R.id.calendar_month_selected_details,
                )
                assertSelectedWeekMonthViewport(activity, expectedWeekIndex = 1)
                assertFalse(
                    "The delegated pull should be allowed to finish at the top",
                    details.canScrollVertically(-1),
                )
            }

            var pullDownX = 0
            var pullDownStartY = 0
            var pullDownEndY = 0
            scenario.onActivity { activity ->
                val details = activity.findViewById<ScrollView>(
                    R.id.calendar_month_selected_details,
                )
                val detailsLocation = IntArray(2).also(details::getLocationOnScreen)
                pullDownX = detailsLocation[0] + details.width / 2
                pullDownStartY = detailsLocation[1] + activity.dp(40)
                pullDownEndY = (pullDownStartY + activity.dp(180)).coerceAtMost(
                    detailsLocation[1] + details.height - activity.dp(20),
                )
            }
            device.swipe(pullDownX, pullDownStartY, pullDownX, pullDownEndY, 30)
            device.waitForIdle()
            Thread.sleep(400L)
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                assertFullMonthViewport(activity)
                assertEquals(
                    View.VISIBLE,
                    activity.findViewById<View>(R.id.calendar_month_selected_details).visibility,
                )
            }
        }
    }

    @Test
    fun compactMonthSelectionAndFirstLoadDoNotInterruptMonthPager() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val launchIntent = Intent(
            instrumentation.targetContext,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        device.executeShellCommand("settings put global animator_duration_scale 1")
        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                    assertTrue(activity.findViewById<View>(R.id.calendar_mode_month).performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                    val today = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
                    val selectedDescription = "${today.get(Calendar.MONTH) + 1}月" +
                        "${today.get(Calendar.DAY_OF_MONTH)}日"
                    val selectedCell = (0 until grid.childCount).asSequence()
                        .map { rowIndex -> grid.getChildAt(rowIndex) as ViewGroup }
                        .flatMap { row ->
                            (0 until row.childCount).asSequence().map(row::getChildAt)
                        }
                        .first { cell ->
                            cell.contentDescription?.toString()?.contains(selectedDescription) == true
                        }
                    assertTrue(selectedCell.performClick())
                    val surface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    val selectedPage = surface.getChildAt(0)
                    assertEquals(
                        "Selecting a date inside the current month must leave the page on the horizontal origin",
                        0f,
                        selectedPage.translationX,
                        0.01f,
                    )
                    assertEquals(1f, selectedPage.alpha, 0.01f)
                }
                SystemClock.sleep(380L)
                instrumentation.waitForIdleSync()

                // The sample repositories complete well before the 300 ms pager.
                // If a completion rebuilds the page, this two-page transition is
                // cut down to one child and the incoming animation visibly jumps.
                var incomingPageIdentity = 0
                scenario.onActivity { activity ->
                    val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                    val lastRow = grid.getChildAt(grid.childCount - 1) as ViewGroup
                    val adjacentNextMonthCell = lastRow.getChildAt(lastRow.childCount - 1)
                    assertTrue(adjacentNextMonthCell.performClick())
                    val surface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    assertEquals(
                        "First-load callbacks must not interrupt the month pager",
                        2,
                        surface.childCount,
                    )
                    val incomingPage = surface.getChildAt(1)
                    incomingPageIdentity = System.identityHashCode(incomingPage)
                    assertEquals(1f, incomingPage.alpha, 0.01f)
                    assertEquals(0f, incomingPage.translationY, 0.01f)
                    assertTrue(
                        "Only a month-page change may use a horizontal transform",
                        incomingPage.translationX > 0f,
                    )
                }

                SystemClock.sleep(360L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val surface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    assertEquals(1, surface.childCount)
                    val settledPage = surface.getChildAt(0)
                    assertEquals(incomingPageIdentity, System.identityHashCode(settledPage))
                    assertEquals(1f, settledPage.alpha, 0.01f)
                    assertEquals(0f, settledPage.translationX, 0.01f)
                    assertEquals(0f, settledPage.translationY, 0.01f)
                }
            }
        } finally {
            device.executeShellCommand("settings put global animator_duration_scale 0")
        }
    }

    @Test
    fun compactModePagerMovesForwardThenBackwardWithTheIndicator() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val launchIntent = Intent(
            instrumentation.targetContext,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        device.executeShellCommand("settings put global animator_duration_scale 1")
        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                    assertTrue(activity.findViewById<View>(R.id.calendar_mode_day).performClick())
                }
                SystemClock.sleep(TeachingCalendarLogic.pageAnimationDurationMillis + 80L)
                instrumentation.waitForIdleSync()

                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.calendar_mode_year).performClick())
                    val surface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    assertEquals(2, surface.childCount)
                    assertTrue(
                        "Forward mode changes must mount the incoming page on the right",
                        surface.getChildAt(1).translationX > 0f,
                    )
                    assertTrue(
                        "The mode indicator must animate in the same render transaction",
                        activity.findViewById<View>(R.id.calendar_mode_year).background is
                            TransitionDrawable,
                    )
                }
                SystemClock.sleep(TeachingCalendarLogic.pageAnimationDurationMillis + 80L)
                instrumentation.waitForIdleSync()

                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.calendar_mode_day).performClick())
                    val surface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    assertEquals(2, surface.childCount)
                    assertTrue(
                        "Backward mode changes must mount the incoming page on the left",
                        surface.getChildAt(1).translationX < 0f,
                    )
                    assertTrue(
                        "The reverse indicator transition must start with the page transition",
                        activity.findViewById<View>(R.id.calendar_mode_day).background is
                            TransitionDrawable,
                    )
                }
            }
        } finally {
            device.executeShellCommand("settings put global animator_duration_scale 0")
        }
    }

    @Test
    fun dayWeekAgendaShowsSupplementaryItemsAndKeepsCollapsedState() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val preferences = AppPreferences(context)
        val previousDeadlineSettings = listOf(
            preferences.competitionDeadlinesEnabled,
            preferences.schoolContestNoticesEnabled,
            preferences.summerCampDeadlinesEnabled,
            preferences.hackathonDeadlinesEnabled,
        )
        preferences.apply {
            competitionDeadlinesEnabled = true
            schoolContestNoticesEnabled = true
            summerCampDeadlinesEnabled = true
            hackathonDeadlinesEnabled = true
        }
        val scheduleStore = ScheduleStore(context)
        val previousSchedule = runCatching(scheduleStore::load).getOrNull()
        scheduleStore.save(dayWeekAgendaTestSchedule())
        val launchIntent = Intent(
            context,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                }
                SystemClock.sleep(700L)
                instrumentation.waitForIdleSync()

                var weekCourseSummary: CourseSummaryPresentation? = null
                var selectedDateLabelBeforeWeekDialog = ""
                scenario.onActivity { activity ->
                    val content = activity.findViewById<ViewGroup>(R.id.calendar_day_week_agenda_content)
                    assertEquals(View.VISIBLE, content.visibility)
                    assertTrue(activity.findViewById<View>(R.id.calendar_day_week_course_area).isShown)
                    activity.findViewById<TextView?>(R.id.calendar_week_number)?.let { weekLabel ->
                        assertTrue(
                            "Week view must show the schedule's teaching week when available",
                            weekLabel.text.contains("教学 1"),
                        )
                    }
                    weekCourseSummary = courseSummaryPresentation(activity)
                    assertCourseSummaryMatchesIosMobileStyle(activity, checkNotNull(weekCourseSummary))
                    assertEquals(
                        "The deterministic selected day must expose every course row without +N truncation",
                        4,
                        checkNotNull(weekCourseSummary).rows.size,
                    )

                    val allDay = activity.findViewById<ViewGroup>(R.id.calendar_all_day_strip)
                    assertFalse("Week all-day layout must use seven fixed columns", allDay is HorizontalScrollView)
                    assertEquals(2, allDay.childCount)
                    val dayRow = allDay.getChildAt(1) as ViewGroup
                    assertEquals("Week all-day layout must expose Monday through Sunday", 7, dayRow.childCount)
                    val cells = List(dayRow.childCount) { index -> dayRow.getChildAt(index) as TextView }
                    cells.forEach { cell ->
                        val label = cell.text.toString()
                        assertTrue("Each week column must show its first item and +N: $label", label.isNotBlank())
                        assertTrue("Each week column must end with +N: $label", Regex("\\+\\d+$").containsMatchIn(label))
                        assertEquals("Each week column must expose one overflow count", 1, label.count { it == '+' })
                        assertEquals(1, cell.maxLines)
                        assertTrue(cell.isClickable)
                    }

                    selectedDateLabelBeforeWeekDialog = courseSummaryTitle(activity)
                    val targetCell = cells.firstOrNull { cell ->
                        val date = cell.contentDescription?.toString()
                            ?.substringBefore("，全天")
                            .orEmpty()
                        date.isNotEmpty() && !selectedDateLabelBeforeWeekDialog.contains(date)
                    } ?: cells.last()
                    assertTrue(targetCell.performClick())
                }
                assertTrue(
                    "The week dialog must expose the complete school-notice item",
                    device.wait(Until.hasObject(By.textContains("校内竞赛")), UI_TIMEOUT_MILLIS),
                )
                assertTrue(
                    "The week dialog must expose enabled public deadlines",
                    device.wait(Until.hasObject(By.textContains("示例高校夏令营")), UI_TIMEOUT_MILLIS),
                )
                val weekDialogBounds = checkNotNull(
                    device.wait(
                        Until.findObject(By.desc("周视图全天日程弹窗")),
                        UI_TIMEOUT_MILLIS,
                    ),
                ).visibleBounds
                assertTrue(
                    "Week all-day dialog must be horizontally centered",
                    abs(weekDialogBounds.centerX() - device.displayWidth / 2) <= 24,
                )
                assertTrue(
                    "Week all-day dialog must be vertically centered",
                    abs(weekDialogBounds.centerY() - device.displayHeight / 2) <= 80,
                )
                scenario.onActivity { activity ->
                    assertEquals(
                        "Opening a week all-day dialog must not change the selected date",
                        selectedDateLabelBeforeWeekDialog,
                        courseSummaryTitle(activity),
                    )
                }
                device.findObject(By.text("完成")).click()
                instrumentation.waitForIdleSync()

                click(device, "calendar_mode_day")
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val dayCourseSummary = courseSummaryPresentation(activity)
                    assertCourseSummaryMatchesIosMobileStyle(activity, dayCourseSummary)
                    assertEquals(
                        "Day and week must render identical selected-day course content and styles",
                        weekCourseSummary,
                        dayCourseSummary,
                    )

                    val allDay = activity.findViewById<View>(R.id.calendar_all_day_strip)
                    assertTrue("Day all-day layout must be horizontally scrollable", allDay is HorizontalScrollView)
                    val row = (allDay as HorizontalScrollView).getChildAt(0) as ViewGroup
                    assertEquals("全天", (row.getChildAt(0) as TextView).text.toString())
                    val itemViews = List(row.childCount - 1) { index -> row.getChildAt(index + 1) as TextView }
                    val overflow = itemViews.singleOrNull { it.text.toString().startsWith("+") }
                    val capsules = itemViews.filterNot { it.text.toString().startsWith("+") }
                    assertEquals("Day all-day layout must expose at most the first three independent capsules", 3, capsules.size)
                    assertNotNull("Sample all-day data must expose a +N overflow control", overflow)
                    assertTrue(capsules.all { it.isClickable && it.background != null && it.maxLines == 1 })
                    assertTrue(
                        "Independent day capsules must retain per-kind accent colors",
                        capsules.map { it.currentTextColor }.distinct().size >= 2,
                    )
                    assertTrue(capsules.first().performClick())
                }
                val dayDialogBounds = checkNotNull(
                    device.wait(
                        Until.findObject(By.desc("日视图全天日程弹窗")),
                        UI_TIMEOUT_MILLIS,
                    ),
                ).visibleBounds
                assertTrue(
                    "Day all-day dialog must be horizontally centered",
                    abs(dayDialogBounds.centerX() - device.displayWidth / 2) <= 24,
                )
                assertTrue(
                    "Day all-day dialog must be vertically centered",
                    abs(dayDialogBounds.centerY() - device.displayHeight / 2) <= 80,
                )
                device.findObject(By.text("完成")).click()
                instrumentation.waitForIdleSync()

                click(device, "calendar_mode_month")
                SystemClock.sleep(700L)
                instrumentation.waitForIdleSync()
                val monthOverflow = checkNotNull(
                    device.wait(Until.findObject(By.textStartsWith("+")), UI_TIMEOUT_MILLIS),
                )
                assertFalse("Month +N must remain display-only", monthOverflow.isClickable)
                monthOverflow.click()
                assertTrue(
                    "Month content must stay inline and never open an agenda dialog",
                    device.wait(
                        Until.gone(By.desc("月视图溢出日程弹窗")),
                        500L,
                    ),
                )
                val weekMode = checkNotNull(
                    device.wait(
                        Until.findObject(By.res(TARGET_PACKAGE, "calendar_mode_week")),
                        UI_TIMEOUT_MILLIS,
                    ),
                )
                assertTrue("Week mode control must accept the transition click", weekMode.isClickable)
                weekMode.click()
                device.waitForIdle()
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_day_week_agenda_toggle,
                    expected = true,
                )
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertTrue(
                        checkNotNull(
                            activity.findViewById<View?>(R.id.calendar_day_week_agenda_toggle),
                        ).performClick(),
                    )
                }
                SystemClock.sleep(TeachingCalendarLogic.agendaAnimationDurationMillis + 80L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals(
                        "Collapsing the selected-day summary must hide only course rows",
                        View.GONE,
                        activity.findViewById<View>(R.id.calendar_day_week_agenda_content).visibility,
                    )
                    assertTrue(
                        "All-day events must remain visible when courses are collapsed",
                        activity.findViewById<View>(R.id.calendar_all_day_strip).isShown,
                    )
                }
                click(device, "calendar_mode_month")
                click(device, "calendar_mode_week")
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_day_week_agenda_toggle,
                    expected = true,
                )
                scenario.onActivity { activity ->
                    assertEquals(
                        "Course collapse must survive calendar mode changes",
                        View.GONE,
                        activity.findViewById<View>(R.id.calendar_day_week_agenda_content).visibility,
                    )
                    assertTrue(activity.findViewById<View>(R.id.calendar_all_day_strip).isShown)
                }
                scenario.recreate()
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals(
                        "Course collapse must survive activity recreation",
                        View.GONE,
                        activity.findViewById<View>(R.id.calendar_day_week_agenda_content).visibility,
                    )
                    assertTrue(activity.findViewById<View>(R.id.calendar_all_day_strip).isShown)
                }
            }
        } finally {
            if (previousSchedule == null) scheduleStore.clear() else scheduleStore.save(previousSchedule)
            preferences.competitionDeadlinesEnabled = previousDeadlineSettings[0]
            preferences.schoolContestNoticesEnabled = previousDeadlineSettings[1]
            preferences.summerCampDeadlinesEnabled = previousDeadlineSettings[2]
            preferences.hackathonDeadlinesEnabled = previousDeadlineSettings[3]
        }
    }

    @Test
    fun android025CourseSummaryAndSettingsControlsUseNativeAnimatedGeometry() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val scheduleStore = ScheduleStore(context)
        val previousSchedule = runCatching(scheduleStore::load).getOrNull()
        scheduleStore.save(dayWeekAgendaTestSchedule())
        val launchIntent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                }
                SystemClock.sleep(700L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val toggle = activity.findViewById<ViewGroup>(
                        R.id.calendar_day_week_agenda_toggle,
                    )
                    val indicator = activity.findViewById<ImageView>(
                        R.id.calendar_day_week_agenda_indicator,
                    )
                    assertEquals(
                        activity.dp(TeachingCalendarLogic.compactAgendaHeaderHeightDp),
                        toggle.height,
                    )
                    assertNotNull(indicator.drawable)
                    assertEquals(180f, indicator.rotation, 0.5f)
                    assertTrue(toggle.performClick())
                }
                SystemClock.sleep(TeachingCalendarLogic.agendaAnimationDurationMillis + 80L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals(
                        View.GONE,
                        activity.findViewById<View>(R.id.calendar_day_week_agenda_content)
                            .visibility,
                    )
                    assertEquals(
                        0f,
                        activity.findViewById<ImageView>(
                            R.id.calendar_day_week_agenda_indicator,
                        ).rotation,
                        0.5f,
                    )
                    assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val settings = activity.findViewById<ScrollView>(R.id.page_settings)
                    assertFalse(containsSpinner(settings))
                    assertEquals(12, countSwitches(settings))
                    listOf(
                        R.id.settings_language_selector,
                        R.id.settings_campus_selector,
                        R.id.settings_widget_course_limit_selector,
                        R.id.settings_widget_preview_size_selector,
                    ).forEach { selectorID ->
                        val selector = activity.findViewById<View>(selectorID)
                        assertTrue(selector.width > 0 && selector.height > 0)
                        assertTrue(selector is ViewGroup)
                        assertFalse(selector is Switch)
                    }
                }
            }
        } finally {
            if (previousSchedule == null) scheduleStore.clear() else scheduleStore.save(previousSchedule)
        }
    }

    @Test
    fun android025AdjacentMonthSelectionEntersFromTheCorrectDirection() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val launchIntent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        device.executeShellCommand("settings put global animator_duration_scale 1")
        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                    assertTrue(activity.findViewById<View>(R.id.calendar_mode_month).performClick())
                }
                instrumentation.waitForIdleSync()
                var incomingIdentity = 0
                scenario.onActivity { activity ->
                    val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                    val firstCell = (grid.getChildAt(0) as ViewGroup).getChildAt(0)
                    val firstDay = firstCell.findViewById<TextView>(R.id.calendar_month_day_label)
                        .text.toString().toInt()
                    val selectingPreviousMonth = firstDay > 14
                    val adjacentCell = if (selectingPreviousMonth) {
                        firstCell
                    } else {
                        val lastRow = grid.getChildAt(grid.childCount - 1) as ViewGroup
                        lastRow.getChildAt(lastRow.childCount - 1)
                    }
                    assertTrue(adjacentCell.performClick())
                    val surface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    assertEquals(2, surface.childCount)
                    val incoming = surface.getChildAt(1)
                    incomingIdentity = System.identityHashCode(incoming)
                    assertTrue(
                        if (selectingPreviousMonth) {
                            incoming.translationX < 0f
                        } else {
                            incoming.translationX > 0f
                        },
                    )
                    assertEquals(0f, incoming.translationY, 0.01f)
                }
                SystemClock.sleep(TeachingCalendarLogic.agendaAnimationDurationMillis + 160L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val surface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    assertEquals(1, surface.childCount)
                    assertEquals(incomingIdentity, System.identityHashCode(surface.getChildAt(0)))
                    assertEquals(0f, surface.getChildAt(0).translationX, 0.01f)
                }
            }
        } finally {
            device.executeShellCommand("settings put global animator_duration_scale 0")
        }
    }

    @Test
    fun android025EnglishCompactControlsAreNotEllipsized() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val preferences = AppPreferences(context)
        preferences.languageCode = AppLanguage.ENGLISH.code
        val launchIntent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val selector = activity.findViewById<ViewGroup>(R.id.settings_language_selector)
                    val row = selector.getChildAt(1) as ViewGroup
                    repeat(row.childCount) { index ->
                        assertTextIsNotEllipsized(row.getChildAt(index) as TextView)
                    }
                    assertTextIsNotEllipsized(
                        activity.findViewById<Switch>(R.id.settings_custom_deadlines_switch),
                    )
                    assertTextIsNotEllipsized(
                        activity.findViewById(R.id.settings_custom_deadlines_save),
                    )
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    listOf(
                        R.id.calendar_mode_day,
                        R.id.calendar_mode_week,
                        R.id.calendar_mode_month,
                        R.id.calendar_mode_year,
                    ).forEach { id ->
                        assertTextIsNotEllipsized(activity.findViewById(id))
                    }
                    val toggle = activity.findViewById<ViewGroup>(
                        R.id.calendar_day_week_agenda_toggle,
                    )
                    assertTextIsNotEllipsized(toggle.getChildAt(0) as TextView)
                    assertTextIsNotEllipsized(toggle.getChildAt(1) as TextView)
                }
            }
        } finally {
            preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        }
    }

    @Test
    fun yearSelectionSurvivesPopoverDismissAndModeRoundTrip() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val launchIntent = Intent(
            instrumentation.targetContext,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            click(device, "navigation_calendar")
            click(device, "calendar_mode_year")
            assertActivityViewMounted(scenario, R.id.calendar_year_view, expected = true)

            var expectedSelection = ""
            scenario.onActivity { activity ->
                val yearView = activity.findViewById<YearCalendarView>(R.id.calendar_year_view)
                val initialSelection = checkNotNull(yearView.selectedDateKey()) {
                    "Year view must initialize from TeachingCalendarSession selectedDate"
                }
                val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
                    timeZone = TimeZone.getTimeZone("Asia/Shanghai")
                }
                val targetDate = Calendar.getInstance(formatter.timeZone).apply {
                    time = checkNotNull(formatter.parse(initialSelection))
                    if (get(Calendar.DAY_OF_MONTH) < getActualMaximum(Calendar.DAY_OF_MONTH)) {
                        add(Calendar.DAY_OF_MONTH, 1)
                    } else {
                        add(Calendar.DAY_OF_MONTH, -1)
                    }
                }
                expectedSelection = formatter.format(targetDate.time)
                val center = checkNotNull(yearView.dateCenter(targetDate))
                val downTime = SystemClock.uptimeMillis()
                listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP).forEachIndexed { index, action ->
                    MotionEvent.obtain(
                        downTime,
                        downTime + index * 16L,
                        action,
                        center.first,
                        center.second,
                        0,
                    ).also { event ->
                        assertTrue(yearView.dispatchTouchEvent(event))
                        event.recycle()
                    }
                }
            }
            assertTrue(
                "Selecting a year date must open its detail popover",
                device.wait(Until.hasObject(By.text("跳转到")), UI_TIMEOUT_MILLIS),
            )
            device.pressBack()
            assertTrue(
                "Back must dismiss the year popover before changing pages",
                device.wait(Until.gone(By.text("跳转到")), UI_TIMEOUT_MILLIS),
            )
            scenario.onActivity { activity ->
                assertEquals(
                    "Dismissing the popover must retain the session-backed blue date selection",
                    expectedSelection,
                    activity.findViewById<YearCalendarView>(R.id.calendar_year_view)
                        .selectedDateKey(),
                )
            }

            click(device, "calendar_mode_month")
            assertActivityViewMounted(scenario, R.id.calendar_month_grid, expected = true)
            click(device, "calendar_mode_year")
            assertActivityViewMounted(scenario, R.id.calendar_year_view, expected = true)
            scenario.onActivity { activity ->
                assertEquals(
                    "Rebuilding year view after a month round-trip must restore the same selection",
                    expectedSelection,
                    activity.findViewById<YearCalendarView>(R.id.calendar_year_view)
                        .selectedDateKey(),
                )
            }
        }
    }

    @Test
    fun englishPreferenceLocalizesStaticUiAndPreservesReturnedContent() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val preferences = AppPreferences(context)
        val previousDeadlineSettings = listOf(
            preferences.competitionDeadlinesEnabled,
            preferences.schoolContestNoticesEnabled,
            preferences.summerCampDeadlinesEnabled,
            preferences.hackathonDeadlinesEnabled,
        )
        preferences.apply {
            languageCode = AppLanguage.ENGLISH.code
            competitionDeadlinesEnabled = true
            schoolContestNoticesEnabled = true
            summerCampDeadlinesEnabled = true
            hackathonDeadlinesEnabled = true
        }
        val device = UiDevice.getInstance(instrumentation)
        val launchIntent = Intent(
            context,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertEquals(
                        "Empty Classrooms",
                        activity.findViewById<TextView>(R.id.navigation_planner).text.toString(),
                    )
                    val returnedContestName = "北邮校内创新竞赛通知"
                    assertEquals(
                        "Third-party and academic content must remain verbatim",
                        returnedContestName,
                        UiText.resolve(activity, returnedContestName),
                    )
                    listOf("高等数学", "数据挖掘", "体育", "体育 · 体育馆").forEach { value ->
                        assertEquals(
                            "Known course/API values must never collide with static translations",
                            value,
                            UiText.resolve(activity, value),
                        )
                    }
                }
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val page = checkNotNull(activity.findViewById<View?>(R.id.page_settings))
                    val text = descendantText(page)
                    assertTrue(text.contains("App Settings"))
                    assertTrue(text.contains("Language"))
                    assertTrue(text.contains("Account"))
                    assertTrue(text.contains("protected by Android Keystore"))
                    val languageSelector = activity.findViewById<ViewGroup>(
                        R.id.settings_language_selector,
                    )
                    val languageRow = languageSelector.getChildAt(1) as ViewGroup
                    val selectedLanguage = (0 until languageRow.childCount)
                        .map { index -> languageRow.getChildAt(index) as TextView }
                        .single { it.isSelected }
                    assertEquals("English", selectedLanguage.text.toString())
                    (0 until languageRow.childCount).forEach { index ->
                        assertTextIsNotEllipsized(languageRow.getChildAt(index) as TextView)
                    }
                }
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                }
                SystemClock.sleep(700L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    listOf(
                        R.id.calendar_mode_day,
                        R.id.calendar_mode_week,
                        R.id.calendar_mode_month,
                        R.id.calendar_mode_year,
                    ).forEach { id ->
                        assertTextIsNotEllipsized(activity.findViewById<TextView>(id))
                    }
                    val allDay = activity.findViewById<ViewGroup>(R.id.calendar_all_day_strip)
                    assertTrue(
                        "English assignment labels must be read from the always-visible all-day strip",
                        descendantText(allDay).contains("Assignment DDL"),
                    )
                    assertTrue((allDay.getChildAt(1) as ViewGroup).getChildAt(0).performClick())
                }
                assertTrue(
                    device.wait(
                        Until.hasObject(By.textContains("Campus Contest Notices")),
                        UI_TIMEOUT_MILLIS,
                    ),
                )
                device.pressBack()
            }
        } finally {
            preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
            preferences.competitionDeadlinesEnabled = previousDeadlineSettings[0]
            preferences.schoolContestNoticesEnabled = previousDeadlineSettings[1]
            preferences.summerCampDeadlinesEnabled = previousDeadlineSettings[2]
            preferences.hackathonDeadlinesEnabled = previousDeadlineSettings[3]
        }
    }

    @Test
    fun phoneNavigationGeometrySurvivesChineseEnglishChineseRoundTrip() {
        clearCredentialRecord()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val preferences = AppPreferences(context)
        preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        val launchIntent = Intent(
            context,
            MainActivity::class.java,
        ).putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                var usesPhoneNavigation = false
                scenario.onActivity { activity ->
                    usesPhoneNavigation = activity.findViewById<View?>(R.id.phone_navigation) != null
                }
                assumeTrue(
                    "Language geometry round-trip only applies to the compact phone navigation",
                    usesPhoneNavigation,
                )
                var originalGeometry: PhoneNavigationGeometry? = null
                scenario.onActivity { activity ->
                    originalGeometry = phoneNavigationGeometry(activity)
                    assertEquals(
                        listOf("空教室", "教学日历", "查询", "设置"),
                        phoneNavigationLabels(activity),
                    )
                    activity.updateAppLanguage(AppLanguage.ENGLISH)
                }
                SystemClock.sleep(600L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals(
                        "English labels must not alter the fixed navigation geometry",
                        originalGeometry,
                        phoneNavigationGeometry(activity),
                    )
                    assertEquals(
                        listOf("Empty Classrooms", "Teaching Calendar", "Query", "Settings"),
                        phoneNavigationLabels(activity),
                    )
                    activity.updateAppLanguage(AppLanguage.SIMPLIFIED_CHINESE)
                }
                SystemClock.sleep(600L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals(
                        "Chinese navigation geometry must be restored after a language round trip",
                        originalGeometry,
                        phoneNavigationGeometry(activity),
                    )
                    assertEquals(
                        listOf("空教室", "教学日历", "查询", "设置"),
                        phoneNavigationLabels(activity),
                    )
                }
            }
        } finally {
            preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
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
            scenario.onActivity { activity ->
                val fetchButton = activity.findViewById<LinearLayout>(R.id.planner_fetch_button)
                assertNull(
                    "Planner fetch action must not restore the removed refresh icon",
                    activity.findViewById<View?>(R.id.planner_fetch_icon),
                )
                assertEquals(
                    "Planner fetch action must contain only its centered label",
                    1,
                    fetchButton.childCount,
                )
                val fetchLabel = fetchButton.getChildAt(0) as TextView
                assertTrue(
                    "Planner fetch label must be horizontally centered without an icon offset",
                    kotlin.math.abs(
                        (fetchLabel.left + fetchLabel.right) - fetchButton.width,
                    ) <= activity.dp(2),
                )
                assertTrue(
                    "Planner fetch label must not carry an icon as a compound drawable",
                    fetchLabel.compoundDrawables.all { it == null },
                )

                val resultsSurface = activity.findViewById<ViewGroup>(
                    R.id.planner_results_surface,
                )
                val resultsContent = activity.findViewById<ViewGroup>(
                    R.id.planner_results_content,
                )
                assertTrue(
                    "Planner results content must remain inside the dedicated results surface",
                    resultsContent.parent === resultsSurface,
                )
                assertTrue(
                    "Planner results surface must render an initial empty or room result state",
                    resultsContent.childCount > 0,
                )

                assertNotNull(
                    "Planner must expose the campus weather card",
                    activity.findViewById<View?>(R.id.planner_weather_surface),
                )
                assertNull(
                    "Campus weather details must be absent before the user expands the card",
                    activity.findViewById<View?>(R.id.planner_weather_details),
                )
                val weatherToggle = activity.findViewById<View>(R.id.planner_weather_toggle)
                assertTrue(weatherToggle.performClick())
                assertNotNull(
                    "Campus weather details must appear after the user expands the card",
                    activity.findViewById<View?>(R.id.planner_weather_details),
                )

                val query = activity.findViewById<ViewGroup>(R.id.planner_query_surface)
                val campusControl = findClickableText(
                    query,
                    AppMetadata.campuses.mapTo(mutableSetOf()) { it.name },
                )
                assertNotNull("Planner query must expose a clickable campus control", campusControl)
                val hapticsBeforeCampusSelection = activity.controlHapticEventCount
                assertTrue(campusControl!!.performClick())
                assertEquals(
                    "Planner controls must report haptic feedback while UI testing",
                    hapticsBeforeCampusSelection + 1,
                    activity.controlHapticEventCount,
                )

                activity.findViewById<View?>(R.id.phone_navigation)?.let {
                    assertTrue(
                        "Compact query conditions must not consume excessive vertical space",
                        query.height <= activity.dp(180),
                    )
                    val summary = activity.findViewById<ViewGroup>(R.id.planner_summary)
                    val metrics = summary.getChildAt(1) as LinearLayout
                    assertEquals(
                        "Planner summary metrics must remain in one horizontal row on phones",
                        LinearLayout.HORIZONTAL,
                        metrics.orientation,
                    )
                    val buildings = activity.findViewById<ViewGroup>(R.id.planner_buildings_surface)
                    val firstRow = buildings.getChildAt(1) as LinearLayout
                    val firstButton = firstRow.getChildAt(0) as LinearLayout
                    val buildingIcon = firstButton.getChildAt(0)
                    val buildingLabel = firstButton.getChildAt(1)
                    assertTrue(
                        "Building icon must remain adjacent to its label",
                        buildingLabel.left - buildingIcon.right <= activity.dp(4),
                    )
                }
            }
            assertCollapsibleNavigationRailWhenAvailable(scenario, device)

            val hapticsBeforeQueryNavigation = hapticCount(scenario)
            click(device, "navigation_query")
            assertEquals(
                "Query primary navigation must report haptic feedback while UI testing",
                hapticsBeforeQueryNavigation + 1,
                hapticCount(scenario),
            )
            assertVisible(device, "page_query")
            assertVisible(device, "information_query_page")

            val hapticsBeforeCalendarNavigation = hapticCount(scenario)
            click(device, "navigation_calendar")
            assertEquals(
                "Primary navigation must report haptic feedback while UI testing",
                hapticsBeforeCalendarNavigation + 1,
                hapticCount(scenario),
            )
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
                assertVisible(device, "calendar_week_number")
                scenario.onActivity { activity ->
                    val header = activity.findViewById<View>(R.id.calendar_phone_header)
                    val overflow = activity.findViewById<View>(R.id.calendar_overflow_button)
                    val period = activity.findViewById<TextView>(R.id.calendar_period_label)
                    val strip = activity.findViewById<View>(R.id.calendar_date_strip)
                    val weekNumber = activity.findViewById<TextView>(R.id.calendar_week_number)
                    assertTrue(
                        "Calendar overflow control must be vertically centered in the phone header",
                        kotlin.math.abs(
                            (overflow.top + overflow.bottom) - (header.height),
                        ) <= activity.dp(2),
                    )
                    assertEquals(
                        activity.dp(TeachingCalendarLogic.phoneDateStripHeightDp),
                        strip.height,
                    )
                    assertEquals(
                        "Compact week heading must remain fully visible",
                        0,
                        period.layout?.getEllipsisCount(0) ?: 0,
                    )
                    assertTrue(weekNumber.text.contains("公历"))
                    assertTrue(weekNumber.text.contains("教学"))
                }
                click(device, "calendar_overflow_button")
                assertTrue(
                    "Calendar overflow menu must expose an explicit phone-calendar import action",
                    device.wait(Until.hasObject(By.text("导入手机日历")), UI_TIMEOUT_MILLIS),
                )
                device.findObject(By.text("导入手机日历")).click()
                assertTrue(
                    "Calendar import must require a second confirmation",
                    device.wait(Until.hasObject(By.text("确认导入")), UI_TIMEOUT_MILLIS),
                )
                device.findObject(By.text("取消")).click()
                device.waitForIdle()

                click(device, "calendar_mode_day")
                assertVisible(device, "calendar_timeline")
                assertVisible(device, "calendar_all_day_strip")
                scenario.onActivity { activity ->
                    val strip = activity.findViewById<ViewGroup>(R.id.calendar_date_strip)
                    val swipeSurface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                    assertTrue(
                        "Day/week date strip must stay outside the horizontally animated page",
                        strip.parent !== swipeSurface,
                    )
                    repeat(strip.childCount) { index ->
                        val date = strip.getChildAt(index) as TextView
                        assertTrue(
                            "Compact day labels must not show holiday work/rest markers",
                            date.maxLines <= 2,
                        )
                    }
                    val selectedDates = (0 until strip.childCount)
                        .map { index -> strip.getChildAt(index) as TextView }
                        .filter { date -> gradientFillColor(date) == Palette.selectedDate }
                    assertEquals("Exactly one compact date must be selected", 1, selectedDates.size)
                    assertEquals(
                        "Compact day/week selection must use the independent selected-date token",
                        Palette.selectedDate,
                        gradientFillColor(selectedDates.single()),
                    )
                    val summary = activity.findViewById<LinearLayout>(
                        R.id.calendar_day_week_agenda_toggle,
                    )
                    assertEquals(
                        "Compact course summary toggle must stay on one low-height row",
                        LinearLayout.HORIZONTAL,
                        summary.orientation,
                    )
                    assertEquals(3, summary.childCount)
                    assertTrue((summary.getChildAt(0) as TextView).text.isNotBlank())
                    assertTrue((summary.getChildAt(1) as TextView).text.isNotBlank())
                    assertTrue(
                        "Compact timeline axis must leave more width for course content",
                        (activity.findViewById<ViewGroup>(R.id.calendar_timeline)
                            .getChildAt(0) as ViewGroup)
                            .getChildAt(0).width <= activity.dp(56),
                    )
                }
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
                    val monthView = activity.findViewById<View>(R.id.calendar_month_view)
                    val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                    val dragHandle = activity.findViewById<View>(R.id.calendar_month_drag_handle)
                    val body = activity.findViewById<View>(R.id.calendar_page_body)
                    val firstRowHeightDp = grid.getChildAt(0).height /
                        activity.resources.displayMetrics.density
                    assertTrue(
                        "Expanded month rows must stay close to the native iOS height",
                        firstRowHeightDp <= TeachingCalendarLogic.monthCellHeightDp(expanded = true) + 1,
                    )
                    assertTrue(
                        "Expanded month handle must remain inside the measured month viewport",
                        dragHandle.bottom <= monthView.height - monthView.paddingBottom,
                    )
                    activity.findViewById<View?>(R.id.phone_navigation)?.let { phoneNavigation ->
                        assertEquals(
                            "Month view must reserve only the floating navigation height and gap",
                            activity.dp(TeachingCalendarLogic.bottomNavigationContentInsetDp),
                            body.paddingBottom,
                        )
                        val handleLocation = IntArray(2).also(dragHandle::getLocationOnScreen)
                        val navigationLocation = IntArray(2).also(phoneNavigation::getLocationOnScreen)
                        assertTrue(
                            "Expanded month handle must remain fully above bottom navigation",
                            handleLocation[1] + dragHandle.height <= navigationLocation[1],
                        )
                    }
                    repeat(grid.childCount) { rowIndex ->
                        val row = grid.getChildAt(rowIndex) as ViewGroup
                        repeat(row.childCount) { cellIndex ->
                            val dayLabel = row.getChildAt(cellIndex)
                                .findViewById<TextView>(R.id.calendar_month_day_label)
                            assertTrue(
                                "Month day labels must match iOS and contain only the date number",
                                dayLabel.text.matches(Regex("\\d{1,2}")),
                            )
                            assertTrue(
                                "Month day labels must use the iOS-equivalent 15sp size",
                                kotlin.math.abs(
                                    dayLabel.textSize - TypedValue.applyDimension(
                                        TypedValue.COMPLEX_UNIT_SP,
                                        15f,
                                        activity.resources.displayMetrics,
                                    ),
                                ) < 0.5f,
                            )
                        }
                    }
                }
                assertMonthDaySelectionOpensDetailsAndEntriesAreDisplayOnly(scenario)
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
                    val monthView = activity.findViewById<View>(R.id.calendar_month_view)
                    if (activity.findViewById<View?>(R.id.phone_navigation) != null) {
                        assertEquals(
                            "Phone month content must span edge to edge",
                            0,
                            monthView.paddingLeft,
                        )
                        assertEquals(
                            "Phone month content must span edge to edge",
                            0,
                            monthView.paddingRight,
                        )
                    }
                }
                swipeMountedActivityView(
                    scenario,
                    device,
                    R.id.calendar_month_selected_details,
                    reverseVertical = false,
                )
                scenario.onActivity { activity ->
                    assertSelectedWeekMonthViewport(activity)
                    assertEquals(
                        "Month detail surface must declare a borderless style",
                        0f,
                        TeachingCalendarLogic.monthDetailsBorderWidthDp(),
                        0f,
                    )
                    // This assertion block verifies anchor transitions, while the
                    // dedicated ownership regression above covers non-top pulls.
                    // Remove any drag overflow so the next pull starts at the edge.
                    activity.findViewById<ScrollView>(
                        R.id.calendar_month_selected_details,
                    ).scrollTo(0, 0)
                }
                assertTrue(
                    "Accessibility expansion must move exactly one month-sheet anchor",
                    performAncestorAccessibilityAction(
                        scenario,
                        R.id.calendar_month_selected_details,
                        AccessibilityNodeInfo.ACTION_EXPAND,
                    ),
                )
                Thread.sleep(360L)
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                assertActivityViewMounted(
                    scenario,
                    R.id.calendar_month_selected_details,
                    expected = true,
                )
                scenario.onActivity { activity ->
                    assertFullMonthViewport(activity)
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
                val yearBeforeSwipe = objectText(device, "calendar_period_label")
                swipeResource(device, "calendar_year_view", horizontalDirection = 1)
                assertTextChanged(device, "calendar_period_label", yearBeforeSwipe)
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
                assertMonthDaySelectionOpensDetailsAndEntriesAreDisplayOnly(scenario)
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
                scenario.onActivity { activity ->
                    val surface = activity.findViewById<View>(R.id.calendar_swipe_surface)
                    if (activity.findViewById<View>(R.id.calendar_month_selected_details).visibility == View.VISIBLE) {
                        surface.performAccessibilityAction(AccessibilityNodeInfo.ACTION_EXPAND, null)
                    }
                }
                device.waitForIdle()
                assertActivityViewMounted(scenario, R.id.calendar_month_selected_details, expected = false)
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

            val hapticsBeforeSettingsNavigation = hapticCount(scenario)
            click(device, "navigation_settings")
            assertEquals(
                "Settings navigation must report haptic feedback while UI testing",
                hapticsBeforeSettingsNavigation + 1,
                hapticCount(scenario),
            )
            assertVisible(device, "page_settings")
            scrollUntilVisible(device, "widget_root")
            assertVisible(device, "widget_root")
            scenario.onActivity { activity ->
                val preview = activity.findViewById<View>(R.id.widget_root)
                assertEquals(activity.dp(205), preview.height)
                assertTrue(
                    activity.findViewById<TextView>(R.id.widget_day_context).text.isNotBlank(),
                )
                assertTrue(
                    activity.findViewById<TextView>(R.id.widget_course_details_1)
                        .text.contains("示例教师"),
                )

                val assignmentRow = activity.findViewById<ViewGroup>(
                    R.id.settings_assignment_deadline_legend_row,
                )
                assertFalse(
                    "Course assignments must remain a read-only legend row",
                    containsSwitch(assignmentRow),
                )
                assertLegendDot(
                    activity,
                    R.id.settings_assignment_deadline_legend_dot,
                    Palette.assignment,
                )
                val settingsPage = activity.findViewById<ScrollView>(R.id.page_settings)
                assertFalse(
                    "Settings must not use dropdown Spinners for segmented multi-value choices",
                    containsSpinner(settingsPage),
                )
                listOf(
                    R.id.settings_language_selector,
                    R.id.settings_campus_selector,
                    R.id.settings_widget_course_limit_selector,
                    R.id.settings_widget_preview_size_selector,
                ).forEach { selectorID ->
                    val selector = activity.findViewById<View>(selectorID)
                    assertTrue("Multi-value settings must use sliding segmented controls", selector is ViewGroup)
                    assertFalse("Multi-value selectors must not be Boolean switches", selector is Switch)
                }
                assertEquals(
                    "Every Boolean setting must remain a native animated Switch",
                    12,
                    countSwitches(settingsPage),
                )

                val preferences = AppPreferences(activity)
                listOf(
                    Triple(
                        R.id.settings_competition_deadlines_switch,
                        R.id.settings_competition_deadlines_dot,
                        Palette.publicDeadline to preferences.competitionDeadlinesEnabled,
                    ),
                    Triple(
                        R.id.settings_conference_deadlines_switch,
                        R.id.settings_conference_deadlines_dot,
                        Palette.conferenceDeadline to preferences.conferenceDeadlinesEnabled,
                    ),
                    Triple(
                        R.id.settings_school_contest_notices_switch,
                        R.id.settings_school_contest_notices_dot,
                        Palette.schoolNotice to preferences.schoolContestNoticesEnabled,
                    ),
                    Triple(
                        R.id.settings_summer_camp_deadlines_switch,
                        R.id.settings_summer_camp_deadlines_dot,
                        Palette.summerCampDeadline to preferences.summerCampDeadlinesEnabled,
                    ),
                    Triple(
                        R.id.settings_hackathon_deadlines_switch,
                        R.id.settings_hackathon_deadlines_dot,
                        Palette.hackathonDeadline to preferences.hackathonDeadlinesEnabled,
                    ),
                    Triple(
                        R.id.settings_custom_deadlines_switch,
                        R.id.settings_custom_deadlines_dot,
                        Palette.customDeadline to preferences.customDeadlinesEnabled,
                    ),
                ).forEach { (switchID, dotID, expected) ->
                    val toggle = activity.findViewById<View>(switchID)
                    assertTrue("Deadline controls must remain native Android Switches", toggle is Switch)
                    toggle as Switch
                    assertTrue("Legend Switches must leave their labels in the adjacent label group", toggle.text.isEmpty())
                    assertTrue(toggle.contentDescription?.isNotBlank() == true)
                    assertEquals(expected.second, toggle.isChecked)
                    assertLegendDot(activity, dotID, expected.first)
                }
            }
            scrollUntilVisible(device, "settings_app_filing_link")
            assertVisible(device, "settings_app_filing_link")
            scrollUntilVisible(device, "privacy_policy_button")
            assertVisible(device, "settings_github_link")
            scenario.onActivity { activity ->
                val about = activity.findViewById<View>(R.id.settings_about_section)
                val accountPrivacy = activity.findViewById<TextView>(
                    R.id.account_privacy_policy_button,
                )
                val filing = activity.findViewById<TextView>(R.id.settings_app_filing_link)
                val language = activity.findViewById<View>(R.id.settings_language_section)
                val localData = activity.findViewById<View>(R.id.settings_local_data_section)
                val settingsPage = activity.findViewById<ScrollView>(R.id.page_settings)
                val settingsContent = settingsPage.getChildAt(0) as ViewGroup
                assertTrue(
                    "Privacy entry must remain inside the about section",
                    activity.findViewById<View>(R.id.privacy_policy_button).parent === about,
                )
                assertTrue(
                    "The account area must always expose a prominent privacy-policy entry",
                    accountPrivacy.isClickable && accountPrivacy.text.isNotBlank(),
                )
                assertTrue("APP filing entry must remain inside About", filing.parent === about)
                assertEquals("APP 备案：琼ICP备2026012322号-2A", filing.text.toString())
                assertTrue("APP filing entry must open the MIIT registry", filing.isClickable)
                assertTrue(
                    "Language section must precede the privacy entry",
                    depthFirstIndex(settingsContent, language) <
                        depthFirstIndex(settingsContent, activity.findViewById(R.id.privacy_policy_button)),
                )
                assertTrue(
                    "Privacy entry must precede local data",
                    depthFirstIndex(settingsContent, activity.findViewById(R.id.privacy_policy_button)) <
                        depthFirstIndex(settingsContent, localData),
                )
            }
            scenario.onActivity { activity -> activity.openFavoriteManagement() }
            instrumentation.waitForIdleSync()
            assertVisible(device, "favorite_deadlines_page")
            scenario.onActivity { activity ->
                val adaptiveRoot = activity.findViewById<ViewGroup>(R.id.adaptive_root)
                val overlay = activity.findViewById<View>(R.id.favorite_deadlines_page)
                assertTrue(
                    "Favorite management must be mounted as an adaptive-root overlay",
                    overlay.parent === adaptiveRoot,
                )
                assertEquals(adaptiveRoot.paddingLeft, overlay.left)
                assertEquals(adaptiveRoot.paddingTop, overlay.top)
                assertEquals(adaptiveRoot.width - adaptiveRoot.paddingRight, overlay.right)
                assertEquals(adaptiveRoot.height - adaptiveRoot.paddingBottom, overlay.bottom)
                activity.findViewById<View?>(R.id.phone_navigation)?.let { phoneNavigation ->
                    assertEquals(
                        "The underlying phone navigation stays mounted and visible under the overlay",
                        View.VISIBLE,
                        phoneNavigation.visibility,
                    )
                    assertTrue(overlay.left <= phoneNavigation.left)
                    assertTrue(overlay.top <= phoneNavigation.top)
                    assertTrue(overlay.right >= phoneNavigation.right)
                    assertTrue(overlay.bottom >= phoneNavigation.bottom)
                }
            }
            device.pressBack()
            assertVisible(device, "page_settings")
            scenario.onActivity { activity ->
                assertNull(activity.findViewById<View?>(R.id.favorite_deadlines_page))
            }
            scrollUntilVisible(device, "privacy_policy_button")
            val hapticsBeforePrivacy = hapticCount(scenario)
            click(device, "privacy_policy_button")
            assertEquals(
                "Settings controls must report haptic feedback while UI testing",
                hapticsBeforePrivacy + 1,
                hapticCount(scenario),
            )
            assertVisible(device, "privacy_policy_content")
            assertNotNull(
                "Privacy policy must disclose the project's fixed public-data endpoints",
                device.wait(
                    Until.findObject(
                        By.textContains("本项目只运营用于整理公开班车与活动数据的固定接口"),
                    ),
                    UI_TIMEOUT_MILLIS,
                ),
            )
            assertNull(
                "Privacy policy must not claim that the project operates no backend",
                device.findObject(By.textContains("项目不运营应用后端")),
            )
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
        assertTrue("View is mounted but not clickable: $resourceName", view.isClickable)
        view.click()
        device.waitForIdle()
    }

    private fun depthFirstIndex(root: View, target: View): Int {
        var nextIndex = 0
        fun visit(view: View): Int? {
            val currentIndex = nextIndex++
            if (view === target) return currentIndex
            if (view is ViewGroup) {
                repeat(view.childCount) { childIndex ->
                    visit(view.getChildAt(childIndex))?.let { return it }
                }
            }
            return null
        }
        return requireNotNull(visit(root)) { "Target view is outside the settings hierarchy" }
    }

    private data class PhoneNavigationGeometry(
        val width: Int,
        val height: Int,
        val childBounds: List<List<Int>>,
    )

    private data class CourseRowPresentation(
        val title: String,
        val subtitle: String,
        val titleSizePx: Float,
        val subtitleSizePx: Float,
        val titleTypefaceStyle: Int,
        val titleMaxLines: Int,
        val subtitleMaxLines: Int,
        val paddingTop: Int,
        val paddingBottom: Int,
    )

    private data class CourseSummaryPresentation(
        val title: String,
        val count: String,
        val indicatorRotation: Float,
        val indicatorHasDrawable: Boolean,
        val toggleHeight: Int,
        val titleSizePx: Float,
        val countSizePx: Float,
        val areaPadding: List<Int>,
        val rows: List<CourseRowPresentation>,
    )

    private fun courseSummaryPresentation(activity: MainActivity): CourseSummaryPresentation {
        val toggle = activity.findViewById<ViewGroup>(R.id.calendar_day_week_agenda_toggle)
        assertEquals("Course summary toggle must expose title, count, and indicator", 3, toggle.childCount)
        val title = toggle.getChildAt(0) as TextView
        val count = toggle.getChildAt(1) as TextView
        val indicator = toggle.getChildAt(2) as ImageView
        assertEquals(R.id.calendar_day_week_agenda_indicator, indicator.id)
        val area = activity.findViewById<ViewGroup>(R.id.calendar_day_week_course_area)
        val rows = List(area.childCount) { index ->
            val row = area.getChildAt(index) as ViewGroup
            assertEquals("Each selected-day course row must expose title and metadata", 2, row.childCount)
            val courseTitle = row.getChildAt(0) as TextView
            val courseSubtitle = row.getChildAt(1) as TextView
            CourseRowPresentation(
                title = courseTitle.text.toString(),
                subtitle = courseSubtitle.text.toString(),
                titleSizePx = courseTitle.textSize,
                subtitleSizePx = courseSubtitle.textSize,
                titleTypefaceStyle = courseTitle.typeface?.style ?: Typeface.NORMAL,
                titleMaxLines = courseTitle.maxLines,
                subtitleMaxLines = courseSubtitle.maxLines,
                paddingTop = row.paddingTop,
                paddingBottom = row.paddingBottom,
            )
        }
        return CourseSummaryPresentation(
            title = title.text.toString(),
            count = count.text.toString(),
            indicatorRotation = indicator.rotation,
            indicatorHasDrawable = indicator.drawable != null,
            toggleHeight = toggle.height,
            titleSizePx = title.textSize,
            countSizePx = count.textSize,
            areaPadding = listOf(area.paddingLeft, area.paddingTop, area.paddingRight, area.paddingBottom),
            rows = rows,
        )
    }

    private fun courseSummaryTitle(activity: MainActivity): String =
        (activity.findViewById<ViewGroup>(R.id.calendar_day_week_agenda_toggle)
            .getChildAt(0) as TextView).text.toString()

    private fun assertCourseSummaryMatchesIosMobileStyle(
        activity: MainActivity,
        summary: CourseSummaryPresentation,
    ) {
        fun sp(value: Float): Float = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            value,
            activity.resources.displayMetrics,
        )

        assertEquals(activity.dp(TeachingCalendarLogic.compactAgendaHeaderHeightDp), summary.toggleHeight)
        assertEquals(sp(12f), summary.titleSizePx, 0.5f)
        assertEquals(sp(10f), summary.countSizePx, 0.5f)
        assertTrue(summary.title.isNotBlank())
        assertTrue(summary.count.isNotBlank())
        assertTrue(summary.indicatorHasDrawable)
        assertEquals(180f, summary.indicatorRotation, 0.5f)
        summary.rows.forEach { row ->
            assertEquals(sp(12f), row.titleSizePx, 0.5f)
            assertEquals(sp(10f), row.subtitleSizePx, 0.5f)
            assertEquals(Typeface.BOLD, row.titleTypefaceStyle)
            assertEquals(1, row.titleMaxLines)
            assertEquals(1, row.subtitleMaxLines)
            assertEquals(activity.dp(2), row.paddingTop)
            assertEquals(activity.dp(2), row.paddingBottom)
        }
        assertEquals(0, summary.areaPadding[1])
        assertEquals(activity.dp(3), summary.areaPadding[3])
    }

    private fun assertTextIsNotEllipsized(view: TextView) {
        assertTrue("Text view must have measurable width: ${view.text}", view.width > 0)
        val layout = checkNotNull(view.layout) { "Missing text layout for ${view.text}" }
        repeat(layout.lineCount) { line ->
            assertEquals(
                "English label must not be ellipsized: ${view.text}",
                0,
                layout.getEllipsisCount(line),
            )
        }
    }

    private fun dayWeekAgendaTestSchedule(): ScheduleSnapshot {
        val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
        val selectedDate = Calendar.getInstance(shanghai).apply {
            set(Calendar.HOUR_OF_DAY, 12)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val weekday = ((selectedDate.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        val weekStart = (selectedDate.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, -(weekday - 1))
        }
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = shanghai
        }
        val starts = listOf(0, 2, 4, 6)
        val courses = starts.mapIndexed { index, startSlot ->
            val slot = AppMetadata.slots[startSlot]
            Course(
                id = "day-week-test-$index",
                name = "测试课程 ${index + 1}",
                teacher = "测试教师 ${index + 1}",
                room = "测试教室 ${index + 1}",
                weekText = "1周",
                weekNumbers = listOf(1),
                examWeekNumbers = emptyList(),
                weekday = weekday,
                startSlot = startSlot,
                endSlot = startSlot,
                sectionText = "第${slot.label}节",
                timeRange = "${slot.start}-${slot.end}",
            )
        }
        return ScheduleSnapshot(
            termID = "day-week-ui-test",
            termStartDate = formatter.format(weekStart.time),
            fetchedAt = "2026-08-24T00:00:00+08:00",
            courses = courses,
        )
    }

    private fun phoneNavigationGeometry(activity: MainActivity): PhoneNavigationGeometry {
        val navigation = checkNotNull(
            activity.findViewById<ViewGroup?>(R.id.phone_navigation),
        ) { "Language round-trip regression requires the phone navigation layout" }
        return PhoneNavigationGeometry(
            width = navigation.width,
            height = navigation.height,
            childBounds = List(navigation.childCount) { index ->
                navigation.getChildAt(index).let { child ->
                    listOf(child.left, child.top, child.right, child.bottom)
                }
            },
        )
    }

    private fun phoneNavigationLabels(activity: MainActivity): List<String> = listOf(
        R.id.navigation_planner,
        R.id.navigation_calendar,
        R.id.navigation_query,
        R.id.navigation_settings,
    ).map { id -> activity.findViewById<TextView>(id).text.toString() }

    private fun hapticCount(scenario: ActivityScenario<MainActivity>): Int {
        var count = 0
        scenario.onActivity { activity -> count = activity.controlHapticEventCount }
        return count
    }

    private fun findClickableText(root: View, candidates: Set<String>): TextView? {
        if (root is TextView && root.isClickable && root.text.toString() in candidates) return root
        if (root !is ViewGroup) return null
        repeat(root.childCount) { index ->
            findClickableText(root.getChildAt(index), candidates)?.let { return it }
        }
        return null
    }

    private fun descendantText(root: View): String {
        if (root is TextView) return root.text.toString()
        if (root !is ViewGroup) return ""
        return (0 until root.childCount)
            .joinToString(" ") { index -> descendantText(root.getChildAt(index)) }
    }

    private fun containsSwitch(root: View): Boolean {
        if (root is Switch) return true
        if (root !is ViewGroup) return false
        return (0 until root.childCount).any { index -> containsSwitch(root.getChildAt(index)) }
    }

    private fun countSwitches(root: View): Int {
        if (root is Switch) return 1
        if (root !is ViewGroup) return 0
        return (0 until root.childCount).sumOf { index -> countSwitches(root.getChildAt(index)) }
    }

    private fun containsSpinner(root: View): Boolean {
        if (root is android.widget.Spinner) return true
        if (root !is ViewGroup) return false
        return (0 until root.childCount).any { index -> containsSpinner(root.getChildAt(index)) }
    }

    private fun gradientFillColor(view: View): Int? {
        val gradient = when (val background = view.background) {
            is GradientDrawable -> background
            is LayerDrawable -> background.getDrawable(0) as? GradientDrawable
            else -> null
        }
        return gradient?.color?.defaultColor
    }

    private fun assertLegendDot(activity: MainActivity, dotID: Int, expectedColor: Int) {
        val dot = activity.findViewById<View>(dotID)
        assertEquals(expectedColor, gradientFillColor(dot))
        assertEquals(activity.dp(10), dot.layoutParams.width)
        assertEquals(activity.dp(10), dot.layoutParams.height)
        val labelGroup = dot.parent as ViewGroup
        val label = labelGroup.getChildAt(0) as TextView
        assertTrue(label.text.isNotBlank())
        assertEquals(
            "Legend dots must sit immediately after their text instead of at the card edge",
            activity.dp(8),
            dot.left - label.right,
        )
    }

    private fun assertCollapsibleNavigationRailWhenAvailable(
        scenario: ActivityScenario<MainActivity>,
        device: UiDevice,
    ) {
        var hasNavigationRail = false
        scenario.onActivity { activity ->
            hasNavigationRail = activity.findViewById<View?>(R.id.tablet_navigation) != null
            if (!hasNavigationRail) {
                assertNull(
                    "Phone layouts must not expose the navigation rail toggle",
                    activity.findViewById<View?>(R.id.navigation_rail_toggle),
                )
            }
        }
        if (!hasNavigationRail) return

        var expandedWidth = 0
        var hapticsBeforeCollapse = 0
        scenario.onActivity { activity ->
            expandedWidth = activity.findViewById<View>(R.id.tablet_navigation).width
            hapticsBeforeCollapse = activity.controlHapticEventCount
            assertEquals(
                "Expanded navigation rail must expose its collapse action",
                "收起导航栏",
                activity.findViewById<View>(R.id.navigation_rail_toggle).contentDescription,
            )
        }
        click(device, "navigation_rail_toggle")
        SystemClock.sleep(400L)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()

        var collapsedWidth = 0
        scenario.onActivity { activity ->
            val rail = activity.findViewById<View>(R.id.tablet_navigation)
            collapsedWidth = rail.width
            assertTrue(
                "Collapsing the navigation rail must reduce its width",
                collapsedWidth < expandedWidth,
            )
            assertEquals(
                "Collapsed navigation rail must expose its expand action",
                "展开导航栏",
                activity.findViewById<View>(R.id.navigation_rail_toggle).contentDescription,
            )
            assertEquals(
                "Navigation rail collapse must report haptic feedback while UI testing",
                hapticsBeforeCollapse + 1,
                activity.controlHapticEventCount,
            )
            assertEquals(
                "Collapsed 72dp rail must not inset its icon containers",
                0,
                rail.paddingLeft,
            )
            val railLocation = IntArray(2).also(rail::getLocationOnScreen)
            val railCenterX = railLocation[0] + rail.width / 2
            val toggle = activity.findViewById<View>(R.id.navigation_rail_toggle)
            val toggleLocation = IntArray(2).also(toggle::getLocationOnScreen)
            assertTrue(
                "Collapsed rail toggle must be horizontally centered",
                kotlin.math.abs(toggleLocation[0] + toggle.width / 2 - railCenterX) <= activity.dp(1),
            )
            listOf(
                R.id.navigation_planner,
                R.id.navigation_calendar,
                R.id.navigation_query,
                R.id.navigation_settings,
            ).forEach { navigationID ->
                val navigation = activity.findViewById<TextView>(navigationID)
                val location = IntArray(2).also(navigation::getLocationOnScreen)
                assertEquals(
                    "Collapsed rail navigation backgrounds must be square",
                    navigation.width,
                    navigation.height,
                )
                assertEquals(
                    activity.dp(AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_ITEM_SIZE_DP),
                    navigation.width,
                )
                assertTrue(
                    "Collapsed rail navigation icons must be centered in the 72dp container",
                    kotlin.math.abs(location[0] + navigation.width / 2 - railCenterX) <= activity.dp(1),
                )
                assertTrue(
                    "Collapsed rail must not retain compound-drawable text metrics",
                    navigation.compoundDrawablesRelative.all { it == null },
                )
                val icon = navigation.foreground
                assertNotNull(
                    "Collapsed rail must render its icon as a centered foreground",
                    icon,
                )
                val iconBounds = checkNotNull(icon).bounds
                assertTrue(
                    "Collapsed rail icon must be horizontally centered in its selected square",
                    kotlin.math.abs(iconBounds.centerX() - navigation.width / 2) <= activity.dp(1),
                )
                assertTrue(
                    "Collapsed rail icon must be vertically centered in its selected square",
                    kotlin.math.abs(iconBounds.centerY() - navigation.height / 2) <= activity.dp(1),
                )
            }
        }

        click(device, "navigation_rail_toggle")
        SystemClock.sleep(400L)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        scenario.onActivity { activity ->
            assertTrue(
                "Expanding the navigation rail must restore its width",
                activity.findViewById<View>(R.id.tablet_navigation).width > collapsedWidth,
            )
            assertEquals(
                "Expanded navigation rail must restore its collapse action",
                "收起导航栏",
                activity.findViewById<View>(R.id.navigation_rail_toggle).contentDescription,
            )
        }
    }

    private fun assertMonthDaySelectionOpensDetailsAndEntriesAreDisplayOnly(
        scenario: ActivityScenario<MainActivity>,
    ) {
        var selectedPageIdentity = 0
        var selectedMonthViewIdentity = 0
        scenario.onActivity { activity ->
            val body = activity.findViewById<View>(R.id.calendar_page_body)
            if (activity.findViewById<View?>(R.id.tablet_navigation) != null) {
                assertNull(
                    "Side-navigation layouts must not retain the phone bottom navigation",
                    activity.findViewById<View?>(R.id.phone_navigation),
                )
                assertEquals(
                    "Side-navigation calendar content must not reserve phone navigation space",
                    0,
                    body.paddingBottom,
                )
            }

            val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
            val firstCell = (grid.getChildAt(0) as ViewGroup).getChildAt(0)
            val firstDay = firstCell.findViewById<TextView>(R.id.calendar_month_day_label)
                .text.toString().toInt()
            val selectingPreviousMonth = firstDay > 14
            val adjacentCell = if (selectingPreviousMonth) {
                firstCell
            } else {
                val lastRow = grid.getChildAt(grid.childCount - 1) as ViewGroup
                lastRow.getChildAt(lastRow.childCount - 1)
            }
            assertTrue(adjacentCell.performClick())
            if (activity.findViewById<View?>(R.id.phone_navigation) != null) {
                val pageSurface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                assertTrue(
                    "Adjacent-month selection may retain only one outgoing page during its transition",
                    pageSurface.childCount in 1..2,
                )
                val incomingPage = pageSurface.getChildAt(pageSurface.childCount - 1)
                selectedPageIdentity = System.identityHashCode(incomingPage)
                selectedMonthViewIdentity = System.identityHashCode(
                    incomingPage.findViewById<View>(R.id.calendar_month_view),
                )
                if (pageSurface.childCount == 2) {
                    assertTrue(
                        "Adjacent-month selection must enter from the tapped month's direction",
                        if (selectingPreviousMonth) {
                            incomingPage.translationX < 0f
                        } else {
                            incomingPage.translationX > 0f
                        },
                    )
                } else {
                    assertEquals(0f, incomingPage.translationX, 0.01f)
                }
                assertEquals(0f, incomingPage.translationY, 0.01f)
                assertEquals(1f, incomingPage.alpha, 0.01f)
            }
        }
        Thread.sleep(360L)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        scenario.onActivity { activity ->
            val details = activity.findViewById<View>(R.id.calendar_month_selected_details)
            assertEquals(View.VISIBLE, details.visibility)
            if (activity.findViewById<View?>(R.id.phone_navigation) != null) {
                val pageSurface = activity.findViewById<ViewGroup>(R.id.calendar_swipe_surface)
                assertEquals(
                    "Phone date selection transition must remove the outgoing page",
                    1,
                    pageSurface.childCount,
                )
                pageSurface.getChildAt(0).let { settledPage ->
                    assertEquals(
                        "Async daily-info completion must not replace the selected month page",
                        selectedPageIdentity,
                        System.identityHashCode(settledPage),
                    )
                    assertEquals(
                        "Async daily-info completion must not replace the selected month grid",
                        selectedMonthViewIdentity,
                        System.identityHashCode(
                            settledPage.findViewById<View>(R.id.calendar_month_view),
                        ),
                    )
                    assertEquals(1f, settledPage.alpha, 0.01f)
                    assertEquals(0f, settledPage.translationX, 0.01f)
                    assertEquals(0f, settledPage.translationY, 0.01f)
                }
            }
            TextView(activity).apply {
                isClickable = true
                isFocusable = true
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                disableMonthGridEntryInteraction()
                assertFalse("Month entry interaction helper must disable clicks", isClickable)
                assertFalse("Month entry interaction helper must disable focus", isFocusable)
                assertEquals(
                    View.IMPORTANT_FOR_ACCESSIBILITY_YES,
                    importantForAccessibility,
                )
            }
            assertFullMonthViewport(activity)
            val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
            val selectedCells = buildList {
                repeat(grid.childCount) { rowIndex ->
                    val row = grid.getChildAt(rowIndex) as ViewGroup
                    repeat(row.childCount) { cellIndex ->
                        val cell = row.getChildAt(cellIndex)
                        if (gradientFillColor(cell) == Palette.selectedDate) add(cell)
                    }
                }
            }
            assertEquals(
                "Month selection must use the independent selected-date token exactly once",
                1,
                selectedCells.size,
            )
            repeat(grid.childCount) { rowIndex ->
                val row = grid.getChildAt(rowIndex) as ViewGroup
                repeat(row.childCount) { cellIndex ->
                    val entries = row.getChildAt(cellIndex)
                        .findViewById<ViewGroup>(R.id.calendar_month_expanded_entries)
                    repeat(entries.childCount) { entryIndex ->
                        val entry = entries.getChildAt(entryIndex)
                        assertFalse("Month entries are display-only", entry.isClickable)
                        assertFalse("Month entries cannot receive focus", entry.isFocusable)
                        assertEquals(
                            "Month entries must remain available to accessibility services",
                            View.IMPORTANT_FOR_ACCESSIBILITY_YES,
                            entry.importantForAccessibility,
                        )
                        assertTrue(
                            "Month entries must retain readable display text",
                            (entry as TextView).text.isNotBlank(),
                        )
                    }
                }
            }
        }
        assertTrue(
            performAncestorAccessibilityAction(
                scenario,
                R.id.calendar_month_grid,
                AccessibilityNodeInfo.ACTION_EXPAND,
            ),
        )
        Thread.sleep(360L)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        assertActivityViewMounted(
            scenario,
            R.id.calendar_month_selected_details,
            expected = false,
        )
        var assignmentColor: Int? = null
        var schoolNoticeColor: Int? = null
        var concentricDeadlineBorderFound = false
        val colorDeadline = System.currentTimeMillis() + UI_TIMEOUT_MILLIS
        while (System.currentTimeMillis() < colorDeadline &&
            (assignmentColor == null || schoolNoticeColor == null ||
                !concentricDeadlineBorderFound)
        ) {
            scenario.onActivity { activity ->
                val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                repeat(grid.childCount) { rowIndex ->
                    val row = grid.getChildAt(rowIndex) as ViewGroup
                    repeat(row.childCount) { cellIndex ->
                        val cell = row.getChildAt(cellIndex)
                        val entries = cell
                            .findViewById<ViewGroup>(R.id.calendar_month_expanded_entries)
                        var hasAssignment = false
                        var hasSchoolNotice = false
                        repeat(entries.childCount) entryLoop@ { entryIndex ->
                            val entry = entries.getChildAt(entryIndex) as? TextView
                                ?: return@entryLoop
                            when {
                                entry.text.startsWith("作 ") -> {
                                    assignmentColor = entry.currentTextColor
                                    hasAssignment = true
                                }
                                entry.text.startsWith("校 ") -> {
                                    schoolNoticeColor = entry.currentTextColor
                                    hasSchoolNotice = true
                                }
                            }
                        }
                        if (hasAssignment && hasSchoolNotice) {
                            val layers = cell.background as? LayerDrawable
                            concentricDeadlineBorderFound = layers?.numberOfLayers == 2
                        }
                    }
                }
            }
            if (assignmentColor == null || schoolNoticeColor == null ||
                !concentricDeadlineBorderFound
            ) {
                SystemClock.sleep(100L)
            }
        }
        assertNotNull("Month grid must render assignment DDL entries", assignmentColor)
        assertNotNull("Month grid must render school notice entries", schoolNoticeColor)
        assertTrue(
            "Assignment and school-notice entries need distinguishable colors",
            assignmentColor != schoolNoticeColor,
        )
        assertTrue(
            "A date with multiple DDL kinds must retain all entries and use two drawable borders",
            concentricDeadlineBorderFound,
        )
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
            val current = try {
                device.findObject(By.res(TARGET_PACKAGE, resourceName))?.text
            } catch (_: StaleObjectException) {
                // Page changes replace the native view tree. Retry against the
                // newly mounted accessibility node instead of retaining a stale one.
                null
            }
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

    private fun swipeMountedActivityView(
        scenario: ActivityScenario<MainActivity>,
        device: UiDevice,
        viewID: Int,
        reverseVertical: Boolean,
    ) {
        val points = IntArray(4)
        scenario.onActivity { activity ->
            val view = activity.findViewById<View>(viewID)
            assertEquals(View.VISIBLE, view.visibility)
            assertTrue("Swipe target must have non-zero geometry", view.width > 0 && view.height > 0)
            val location = IntArray(2).also(view::getLocationOnScreen)
            val x = location[0] + view.width / 2
            val inset = (view.height / 6).coerceIn(8, 32)
            val upperY = location[1] + inset
            val lowerY = location[1] + view.height - inset
            points[0] = x
            points[1] = if (reverseVertical) upperY else lowerY
            points[2] = x
            points[3] = if (reverseVertical) lowerY else upperY
        }
        device.swipe(points[0], points[1], points[2], points[3], 24)
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

    private fun assertSelectedWeekMonthViewport(
        activity: MainActivity,
        expectedWeekIndex: Int? = null,
    ) {
        val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
        val viewport = activity.findViewById<View>(R.id.calendar_month_grid_viewport)
        val collapsedRowHeight = activity.dp(TeachingCalendarLogic.monthCellHeightDp(false))
        val selectedWeekIndex = grid.tag as Int
        expectedWeekIndex?.let {
            assertEquals("The tapped non-first week must remain selected", it, selectedWeekIndex)
        }
        repeat(grid.childCount) { rowIndex ->
            assertEquals(
                "Raising details must preserve every month row's compact height",
                collapsedRowHeight,
                grid.getChildAt(rowIndex).height,
            )
        }
        assertEquals(
            "The clipped viewport must not constrain the intact month grid's measured height",
            collapsedRowHeight * grid.childCount,
            grid.height,
        )
        assertEquals(grid.height, grid.measuredHeight)
        assertEquals(
            "The raised-details detent must clip the month to one week",
            collapsedRowHeight,
            viewport.height,
        )
        assertEquals(
            "The intact month grid must move upward until the selected week reaches the viewport",
            (-selectedWeekIndex * collapsedRowHeight).toFloat(),
            grid.translationY,
            1f,
        )
        val viewportRect = Rect()
        assertTrue(viewport.getGlobalVisibleRect(viewportRect))
        repeat(grid.childCount) { rowIndex ->
            val row = grid.getChildAt(rowIndex)
            val location = IntArray(2).also(row::getLocationOnScreen)
            val rowRect = Rect(
                location[0],
                location[1],
                location[0] + row.width,
                location[1] + row.height,
            )
            val intersection = Rect(rowRect)
            val intersectsViewport = intersection.intersect(viewportRect)
            if (rowIndex == selectedWeekIndex) {
                assertTrue(intersectsViewport)
                assertEquals(
                    "The selected week must be the row positioned inside the viewport",
                    viewportRect,
                    intersection,
                )
            } else {
                assertFalse(
                    "Only the selected week may intersect the viewport at the highest detent",
                    intersectsViewport,
                )
            }
        }
    }

    private fun assertFullMonthViewport(activity: MainActivity) {
        val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
        val viewport = activity.findViewById<View>(R.id.calendar_month_grid_viewport)
        val rowHeight = grid.getChildAt(0).height
        assertTrue(rowHeight > 0)
        repeat(grid.childCount) { rowIndex ->
            assertEquals(rowHeight, grid.getChildAt(rowIndex).height)
        }
        assertEquals(
            "The middle detent must expose the full month without compressing individual weeks",
            rowHeight * grid.childCount,
            viewport.height,
        )
        assertEquals(0f, grid.translationY, 1f)
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
        AppPreferences(context).languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
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
