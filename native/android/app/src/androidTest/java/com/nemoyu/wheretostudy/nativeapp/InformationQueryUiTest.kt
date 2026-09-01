package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InformationQueryUiTest {
    @Test
    fun importantEventsAppendAutomaticallyNearTheBottomWithoutALoadMoreButton() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val preferences = AppPreferences(context)
        val previousFavorites = preferences.favoriteDeadlines
        previousFavorites.forEach { preferences.setFavorite(it, favorite = false) }
        val pagingFavorites = (1..25).map { index ->
            PublicDeadlineItem(
                id = "paging-$index",
                name = "Paging event $index",
                kind = PublicDeadlineKind.COMPETITION,
                source = PublicDeadlineSource.CONTEST_DDL,
                deadline = "2035-01-${index.toString().padStart(2, '0')}T12:00:00+08:00",
                organizer = "Paging test",
                officialURL = null,
            )
        }
        pagingFavorites.forEach { preferences.setFavorite(it, favorite = true) }
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(intent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
                    assertTrue(
                        activity.findViewById<View>(R.id.information_query_events_tab).performClick(),
                    )
                }
                instrumentation.waitForIdleSync()
                assertTrue(
                    UiDevice.getInstance(instrumentation).wait(
                        Until.hasObject(By.text(context.uiText("示例学术会议"))),
                        5_000,
                    ),
                )

                scenario.onActivity { activity ->
                    val list = activity.findViewById<LinearLayout>(
                        R.id.information_query_events_list,
                    )
                    assertEquals(InformationQuerySessionState.INITIAL_EVENT_COUNT, list.childCount)
                    assertTrue("A load-more button must not be rendered", "加载更多" !in descendantText(list))
                    activity.findViewById<ScrollView>(R.id.information_query_events_scroll)
                        .fullScroll(View.FOCUS_DOWN)
                }
                instrumentation.waitForIdleSync()

                scenario.onActivity { activity ->
                    val list = activity.findViewById<LinearLayout>(
                        R.id.information_query_events_list,
                    )
                    assertEquals(30, list.childCount)
                    assertTrue("加载更多" !in descendantText(list))
                    assertTrue(
                        activity.findViewById<ImageView>(R.id.information_query_event_favorite)
                            .performClick(),
                    )
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals(
                        "A favorite-triggered view rebuild must preserve the loaded batch",
                        30,
                        activity.findViewById<LinearLayout>(
                            R.id.information_query_events_list,
                        ).childCount,
                    )
                }
            }
        } finally {
            val restoredPreferences = AppPreferences(context)
            restoredPreferences.favoriteDeadlines.forEach {
                restoredPreferences.setFavorite(it, favorite = false)
            }
            previousFavorites.reversed().forEach {
                restoredPreferences.setFavorite(it, favorite = true)
            }
        }
    }

    @Test
    fun queryIsAnIndependentPrimaryDestinationInTheRequiredNavigationOrder() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                val navigation = checkNotNull(
                    activity.findViewById<ViewGroup?>(R.id.phone_navigation)
                        ?: activity.findViewById<ViewGroup?>(R.id.tablet_navigation),
                )
                val navigationIDs = listOf(
                    R.id.navigation_planner,
                    R.id.navigation_calendar,
                    R.id.navigation_query,
                    R.id.navigation_settings,
                )
                val indices = navigationIDs.map { id ->
                    navigation.indexOfChild(activity.findViewById<View>(id))
                }
                assertTrue(indices.all { it >= 0 })
                assertEquals(indices.sorted(), indices)
                assertEquals(
                    listOf("空教室", "教学日历", "查询", "设置").map(activity::uiText),
                    navigationIDs.map { id -> activity.findViewById<TextView>(id).text.toString() },
                )
                assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
                assertNotNull(activity.findViewById<View?>(R.id.page_query))
                assertNotNull(activity.findViewById<View?>(R.id.information_query_page))
            }

            instrumentation.waitForIdleSync()
            assertTrue(device.wait(Until.hasObject(By.text(context.uiText("班车查询"))), 5_000))

            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                if (activity.findViewById<View?>(R.id.calendar_phone_header) != null) {
                    assertTrue(activity.findViewById<View>(R.id.calendar_overflow_button).performClick())
                }
            }
            instrumentation.waitForIdleSync()
            if (device.hasObject(By.text(context.uiText("导入手机日历")))) {
                assertTrue(!device.hasObject(By.text(context.uiText("班车与重要事件查询"))))
                device.pressBack()
            }
        }
    }

    @Test
    fun queryPageUsesAnimatedTabsAndExposesSearchFilterAndFavorites() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        val previousFavorites = preferences.favoriteDeadlines
        previousFavorites.forEach { preferences.setFavorite(it, favorite = false) }
        preferences.languageCode = AppLanguage.ENGLISH.code
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(intent).use { scenario ->
                scenario.onActivity { activity ->
                    assertEquals(
                        "Unable to load shuttle information",
                        activity.uiText("班车数据版本不受支持。"),
                    )
                    assertEquals(
                        "Unable to load important events",
                        activity.uiText("重要事件数据暂时不可用。"),
                    )
                    assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_mode_switch))
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_shuttle_status))
                    assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
                }
                instrumentation.waitForIdleSync()
                assertTrue(
                    UiDevice.getInstance(instrumentation).wait(
                        Until.hasObject(By.text(context.uiText("学术会议"))),
                        5_000,
                    ),
                )
                scenario.onActivity { activity ->
                    assertNotNull(activity.findViewById<EditText?>(R.id.information_query_search))
                    assertNotNull(
                        activity.findViewById<View?>(R.id.information_query_metadata_category_row),
                    )
                    val typeRow = activity.findViewById<LinearLayout>(
                        R.id.information_query_category_row,
                    )
                    assertEquals(
                        listOf("全部", "学科竞赛", "学术会议", "黑客松", "夏令营", "校内通知")
                            .map(activity::uiText),
                        childTexts(typeRow),
                    )
                    assertTrue(activity.uiText("期刊专题") !in childTexts(typeRow))
                    assertTrue(activity.uiText("预推免") !in childTexts(typeRow))
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_show_ended))
                    val list = activity.findViewById<LinearLayout>(R.id.information_query_events_list)
                    assertTrue("Sample events must render in the query list", list.childCount > 0)
                    assertTrue(
                        activity.findViewById<TextView>(R.id.information_query_result_count)
                            .text.isNotBlank(),
                    )
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_event_favorite))

                    assertTrue(
                        findTextChild(typeRow, activity.uiText("学术会议")).performClick(),
                    )
                    val conferenceMetadata = activity.findViewById<LinearLayout>(
                        R.id.information_query_metadata_category_row,
                    )
                    assertTrue("计算机" in childTexts(conferenceMetadata))
                    assertTrue(findTextChild(conferenceMetadata, "计算机").performClick())
                    val refreshedTypeRow = activity.findViewById<LinearLayout>(
                        R.id.information_query_category_row,
                    )
                    assertTrue(
                        findTextChild(refreshedTypeRow, activity.uiText("学科竞赛")).performClick(),
                    )
                    assertTrue(
                        activity.findViewById<View?>(R.id.information_query_metadata_category_row) ==
                            null,
                    )
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                    assertTrue(activity.findViewById<View?>(R.id.information_query_page) == null)
                }
            }
        } finally {
            val restoredPreferences = AppPreferences(context)
            restoredPreferences.favoriteDeadlines.forEach {
                restoredPreferences.setFavorite(it, favorite = false)
            }
            previousFavorites.reversed().forEach {
                restoredPreferences.setFavorite(it, favorite = true)
            }
            restoredPreferences.languageCode = previousLanguage
        }
    }

    @Test
    fun settingsKeepsIndependentConferenceSwitchWithoutADuplicateQueryEntry() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                assertNotNull(activity.findViewById<View?>(R.id.settings_conference_deadlines_switch))
                assertLegendColor(
                    activity,
                    R.id.settings_assignment_deadline_legend_dot,
                    Palette.assignment,
                )
                assertLegendColor(
                    activity,
                    R.id.settings_competition_deadlines_dot,
                    Palette.publicDeadline,
                )
                assertLegendColor(
                    activity,
                    R.id.settings_conference_deadlines_dot,
                    Palette.conferenceDeadline,
                )
                assertLegendColor(
                    activity,
                    R.id.settings_school_contest_notices_dot,
                    Palette.schoolNotice,
                )
                assertLegendColor(
                    activity,
                    R.id.settings_summer_camp_deadlines_dot,
                    Palette.summerCampDeadline,
                )
                assertLegendColor(
                    activity,
                    R.id.settings_hackathon_deadlines_dot,
                    Palette.hackathonDeadline,
                )
                assertLegendColor(
                    activity,
                    R.id.settings_custom_deadlines_dot,
                    Palette.customDeadline,
                )
                val settingsPage = activity.findViewById<View>(R.id.page_settings)
                assertTrue(!descendantText(settingsPage).contains(activity.uiText("班车与重要事件查询")))
                assertNotNull(activity.findViewById<View?>(R.id.navigation_query))
            }
        }
    }

    private fun descendantText(view: View): String {
        if (view is TextView) return view.text.toString()
        if (view !is ViewGroup) return ""
        return (0 until view.childCount).joinToString(" ") { index ->
            descendantText(view.getChildAt(index))
        }
    }

    private fun childTexts(row: ViewGroup): List<String> = (0 until row.childCount).mapNotNull {
        (row.getChildAt(it) as? TextView)?.text?.toString()
    }

    private fun findTextChild(row: ViewGroup, text: String): TextView = (0 until row.childCount)
        .mapNotNull { row.getChildAt(it) as? TextView }
        .first { it.text.toString() == text }

    private fun assertLegendColor(activity: MainActivity, viewID: Int, expected: Int) {
        val background = activity.findViewById<View>(viewID).background as GradientDrawable
        assertEquals(expected, background.color?.defaultColor)
    }

}
