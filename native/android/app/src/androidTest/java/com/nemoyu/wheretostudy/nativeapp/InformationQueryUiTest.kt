package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
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
    fun teachingCalendarOverflowOpensQueryOnTheUnifiedPhoneAndWideChrome() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                assertNotNull(activity.findViewById<View?>(R.id.calendar_phone_header))
                assertTrue(activity.findViewById<View>(R.id.calendar_overflow_button).performClick())
            }
            instrumentation.waitForIdleSync()
            assertTrue(
                device.wait(
                    Until.hasObject(By.text(context.uiText("班车与重要事件查询"))),
                    3_000,
                ),
            )
            device.findObject(By.text(context.uiText("班车与重要事件查询"))).click()
            instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                assertNotNull(activity.findViewById<View?>(R.id.information_query_page))
            }
        }
    }

    @Test
    fun queryPageUsesAnimatedTabsAndExposesSearchFilterAndFavorites() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
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
                    activity.openInformationQuery(InformationQueryMode.SHUTTLE)
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_mode_switch))
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_shuttle_status))
                    assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
                }
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                scenario.onActivity { activity ->
                    assertNotNull(activity.findViewById<EditText?>(R.id.information_query_search))
                    assertNotNull(
                        activity.findViewById<View?>(R.id.information_query_metadata_category_row),
                    )
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_show_ended))
                    val list = activity.findViewById<LinearLayout>(R.id.information_query_events_list)
                    assertTrue("Sample events must render in the query list", list.childCount > 0)
                    assertTrue(
                        activity.findViewById<TextView>(R.id.information_query_result_count)
                            .text.isNotBlank(),
                    )
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_event_favorite))
                    assertTrue(activity.findViewById<View>(R.id.information_query_back).performClick())
                    assertTrue(activity.findViewById<View?>(R.id.information_query_page) == null)
                }
            }
        } finally {
            AppPreferences(context).languageCode = previousLanguage
        }
    }

    @Test
    fun settingsContainsQueryEntryAndIndependentConferenceSwitch() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                assertNotNull(activity.findViewById<View?>(R.id.settings_information_query_button))
                assertNotNull(activity.findViewById<View?>(R.id.settings_conference_deadlines_switch))
                assertTrue(activity.findViewById<View>(R.id.settings_information_query_button).performClick())
                assertNotNull(activity.findViewById<View?>(R.id.information_query_page))
            }
        }
    }
}
