package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FavoriteDeadlineUiTest {
    @Before
    fun acceptPrivacyConsent() = ensurePrivacyConsentForUiTest()

    @Test
    fun deadlineStarAndIndependentFavoriteManagementKeepLinkClicksSeparate() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val setupPreferences = AppPreferences(context)
        val previousFavorites = setupPreferences.favoriteDeadlines
        clearFavorites(AppPreferences(context))
        val today = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
        val date = String.format(
            java.util.Locale.US,
            "%04d-%02d-%02d",
            today.get(Calendar.YEAR),
            today.get(Calendar.MONTH) + 1,
            today.get(Calendar.DAY_OF_MONTH),
        )
        val customFavorite = PublicDeadlineItem(
            id = "ui-custom-favorite",
            name = "收藏管理测试日程",
            kind = PublicDeadlineKind.CUSTOM,
            source = PublicDeadlineSource.CUSTOM,
            deadline = "${date}T23:59:00+08:00",
            organizer = "测试组织方",
            officialURL = "https://example.com/item",
            sourceName = "测试自定义来源",
            sourceHomepage = "https://example.com",
        )
        AppPreferences(context).setFavorite(customFavorite, favorite = true)
        val launchIntent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_calendar).performClick())
                    assertTrue(activity.findViewById<View>(R.id.calendar_mode_month).performClick())
                }
                SystemClock.sleep(700L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val grid = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
                    val selectedCell = (0 until grid.childCount).asSequence()
                        .map { rowIndex -> grid.getChildAt(rowIndex) as ViewGroup }
                        .flatMap { row ->
                            (0 until row.childCount).asSequence().map(row::getChildAt)
                        }
                        .first { cell ->
                            val label = cell.findViewById<TextView>(R.id.calendar_month_day_label)
                            label.text.toString() == today.get(Calendar.DAY_OF_MONTH).toString() &&
                                label.currentTextColor == Palette.onPrimary
                        }
                    assertTrue(selectedCell.performClick())
                }
                SystemClock.sleep(700L)
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val star = activity.window.decorView.findViewWithTag<View>(
                        customFavorite.favoriteID,
                    ) as? ImageView
                    assertNotNull("Favorite deadline must expose a real star ImageView", star)
                    checkNotNull(star)
                    assertEquals(R.id.calendar_deadline_favorite, star.id)
                    assertTrue(star.isClickable)
                    val row = star.parent as ViewGroup
                    assertTrue(
                        "The original-link region must be a sibling of the star button",
                        row.getChildAt(0).isClickable,
                    )
                    assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val manager = activity.findViewById<TextView>(
                        R.id.settings_favorite_deadlines_button,
                    )
                    assertTrue(manager.text.contains("1"))
                    assertTrue(manager.performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertNotNull(activity.findViewById<View?>(R.id.favorite_deadlines_page))
                    assertEquals(
                        "Favorite management is an independent phone page and must hide navigation",
                        View.GONE,
                        activity.findViewById<View>(R.id.phone_navigation).visibility,
                    )
                    val star = activity.window.decorView.findViewWithTag<View>(
                        customFavorite.favoriteID,
                    ) as ImageView
                    assertTrue(star.performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertNotNull(activity.findViewById<View?>(R.id.favorite_deadlines_empty))
                    assertFalse(AppPreferences(activity).isFavorite(customFavorite))
                    assertTrue(activity.findViewById<View>(R.id.favorite_deadlines_back).performClick())
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertNotNull(
                        activity.findViewById<View?>(R.id.settings_favorite_deadlines_button),
                    )
                    assertEquals(View.VISIBLE, activity.findViewById<View>(R.id.phone_navigation).visibility)
                }
            }
        } finally {
            val restored = AppPreferences(context)
            clearFavorites(restored)
            previousFavorites.reversed().forEach { restored.setFavorite(it, favorite = true) }
        }
    }

    private fun clearFavorites(preferences: AppPreferences) {
        preferences.favoriteDeadlines.forEach { preferences.setFavorite(it, favorite = false) }
    }
}
