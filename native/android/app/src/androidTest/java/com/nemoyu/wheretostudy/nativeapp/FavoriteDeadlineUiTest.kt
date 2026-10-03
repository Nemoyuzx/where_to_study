package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.os.SystemClock
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.ImageView
import android.widget.TextView
import android.widget.EditText
import android.widget.ScrollView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

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
                        "Favorite management covers the mounted phone navigation with an overlay",
                        View.VISIBLE,
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

    @Test
    fun removingADeepFavoriteKeepsTheOverlayScrollSettingsDraftAndBilingualCount() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        val storage = context.getSharedPreferences(AppPreferences.PREFERENCES_NAME, android.content.Context.MODE_PRIVATE)
        val previousPayload = storage.getString(AppPreferences.FAVORITE_DEADLINES_KEY, null)
        val items = (1..AppPreferences.maximumFavoriteDeadlines).map { index -> PublicDeadlineItem(
            id = "deep-favorite-$index", name = "Synthetic favorite $index / 合成收藏",
            kind = PublicDeadlineKind.CUSTOM, source = PublicDeadlineSource.CUSTOM,
            deadline = "2035-01-01T23:59:00+08:00", organizer = null, officialURL = null,
            description = "Complete synthetic snapshot $index",
        ) }
        try {
            listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
                preferences.languageCode = language.code
                assertTrue(storage.edit().putString(AppPreferences.FAVORITE_DEADLINES_KEY,
                    PublicDeadlineItemJsonCodec.encode(items)).commit())
                ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                    .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                    lateinit var settings: View
                    lateinit var account: EditText
                    lateinit var overlay: ScrollView
                    lateinit var rows: ViewGroup
                    lateinit var survivor: View
                    var oldScrollY = 0
                    var openStartedAt = 0L
                    var buildReturnedAt = 0L
                    val nextFrameAt = AtomicLong()
                    val firstLayoutAt = AtomicLong()
                    var initiallyRenderedRows = 0
                    val timingComplete = CountDownLatch(2)
                    scenario.onActivity { activity ->
                        activity.findViewById<View>(R.id.navigation_settings).performClick()
                        settings = activity.findViewById(R.id.page_settings)
                        account = descendants(settings).filterIsInstance<EditText>().first {
                            it.hint.toString() == activity.uiText("教务账号")
                        }
                        account.setText("unsaved-favorite-draft")
                        account.requestFocus()
                        openStartedAt = SystemClock.elapsedRealtimeNanos()
                        activity.findViewById<View>(R.id.settings_favorite_deadlines_button).performClick()
                        buildReturnedAt = SystemClock.elapsedRealtimeNanos()
                        overlay = activity.findViewById(R.id.favorite_deadlines_page)
                        rows = activity.findViewById(R.id.favorite_deadlines_list)
                        overlay.postOnAnimation {
                            nextFrameAt.set(SystemClock.elapsedRealtimeNanos())
                            timingComplete.countDown()
                        }
                        overlay.viewTreeObserver.addOnPreDrawListener(object : ViewTreeObserver.OnPreDrawListener {
                            override fun onPreDraw(): Boolean {
                                firstLayoutAt.set(SystemClock.elapsedRealtimeNanos())
                                initiallyRenderedRows = rows.childCount
                                overlay.viewTreeObserver.removeOnPreDrawListener(this)
                                timingComplete.countDown()
                                return true
                            }
                        })
                    }
                    assertTrue("The opening must reach its actual frame/layout callbacks", timingComplete.await(5, TimeUnit.SECONDS))
                    val timing = String.format(java.util.Locale.ROOT,
                        "FavoriteOpenTiming language=%s rows=%d total=500 buildReturnMs=%.3f nextFrameMs=%.3f firstLayoutMs=%.3f layoutAfterBuildMs=%.3f",
                        language.code, initiallyRenderedRows, (buildReturnedAt - openStartedAt) / 1_000_000.0,
                        (nextFrameAt.get() - openStartedAt) / 1_000_000.0,
                        (firstLayoutAt.get() - openStartedAt) / 1_000_000.0,
                        (firstLayoutAt.get() - buildReturnedAt) / 1_000_000.0)
                    Log.i("FavoriteOpenTiming", timing)
                    instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$timing\n") })
                    instrumentation.waitForIdleSync()
                    lateinit var firstRow: View
                    scenario.onActivity { activity ->
                        assertEquals(20, rows.childCount)
                        firstRow = rows.getChildAt(0)
                        val more = activity.findViewById<TextView>(R.id.favorite_deadlines_load_more)
                        assertEquals(View.VISIBLE, more.visibility)
                        assertTrue(more.isEnabled)
                        assertEquals(if (language == AppLanguage.ENGLISH) "Load More" else "加载更多", more.text.toString())
                        overlay.scrollTo(0, overlay.getChildAt(0).height)
                    }
                    awaitFavoriteRowCount(scenario, 40)
                    scenario.onActivity { activity ->
                        assertSame(overlay, activity.findViewById(R.id.favorite_deadlines_page))
                        assertSame(firstRow, rows.getChildAt(0))
                    }
                    (60..300 step 20).forEach { expected ->
                        scenario.onActivity { activity ->
                            assertTrue(activity.findViewById<View>(R.id.favorite_deadlines_load_more).performClick())
                        }
                        awaitFavoriteRowCount(scenario, expected)
                        scenario.onActivity { assertSame(firstRow, rows.getChildAt(0)) }
                    }
                    scenario.onActivity {
                        assertTrue("Batches must reach the actual 251st saved snapshot",
                            descendants(rows.getChildAt(250)).filterIsInstance<TextView>().any { it.text.toString() == items[250].name })
                    }
                    (320..500 step 20).forEach { expected ->
                        scenario.onActivity { activity ->
                            assertTrue(activity.findViewById<View>(R.id.favorite_deadlines_load_more).performClick())
                        }
                        awaitFavoriteRowCount(scenario, expected)
                        scenario.onActivity { assertSame(firstRow, rows.getChildAt(0)) }
                    }
                    scenario.onActivity { activity ->
                        assertEquals(View.GONE, activity.findViewById<View>(R.id.favorite_deadlines_load_more).visibility)
                        assertEquals(500, rows.childCount)
                        assertTrue(descendants(rows.getChildAt(499)).filterIsInstance<TextView>().any {
                            it.text.toString() == items.last().name
                        })
                        overlay.scrollTo(0, rows.getChildAt(250).top + rows.top)
                    }
                    instrumentation.waitForIdleSync()
                    scenario.onActivity {
                        oldScrollY = overlay.scrollY
                        assertTrue("The canceled favorite must be deep in the list", oldScrollY > 0)
                        survivor = rows.getChildAt(251)
                        assertTrue(descendants(rows.getChildAt(250)).filterIsInstance<ImageView>().single().performClick())
                    }
                    instrumentation.waitForIdleSync()
                    scenario.onActivity { activity ->
                        assertSame(overlay, activity.findViewById(R.id.favorite_deadlines_page))
                        assertSame(rows, activity.findViewById(R.id.favorite_deadlines_list))
                        assertSame(survivor, rows.getChildAt(250))
                        assertEquals(oldScrollY, overlay.scrollY)
                        assertEquals(499, rows.childCount)
                        assertEquals(499, AppPreferences(activity).favoriteDeadlines.size)
                        assertEquals("Removing one row must preserve every remaining complete snapshot",
                            items.filterNot { it.favoriteID == items[250].favoriteID }, AppPreferences(activity).favoriteDeadlines)
                    }
                    scenario.onActivity { activity ->
                        assertEquals(View.GONE, activity.findViewById<View>(R.id.favorite_deadlines_load_more).visibility)
                        assertEquals(499, rows.childCount)
                        assertTrue(descendants(rows.getChildAt(498)).filterIsInstance<TextView>().any {
                            it.text.toString() == items.last().name
                        })
                        activity.findViewById<View>(R.id.favorite_deadlines_back).performClick()
                        assertSame(settings, activity.findViewById(R.id.page_settings))
                        assertEquals("unsaved-favorite-draft", account.text.toString())
                        assertTrue(account.hasFocus())
                        val label = activity.findViewById<TextView>(R.id.settings_favorite_deadlines_button)
                        assertEquals(if (language == AppLanguage.ENGLISH) "Favorite Management (499)" else "收藏管理（499）",
                            label.text.toString())
                    }
                    lateinit var retiredOverlay: ScrollView
                    lateinit var retiredRows: ViewGroup
                    val canceledFrame = CountDownLatch(1)
                    scenario.onActivity { activity ->
                        activity.openFavoriteManagement()
                        retiredOverlay = activity.findViewById(R.id.favorite_deadlines_page)
                        retiredRows = activity.findViewById(R.id.favorite_deadlines_list)
                        assertEquals(20, retiredRows.childCount)
                        assertTrue(activity.findViewById<View>(R.id.favorite_deadlines_load_more).performClick())
                        activity.closeFavoriteManagement()
                        assertFalse(retiredOverlay.isAttachedToWindow)
                        activity.window.decorView.postOnAnimation {
                            activity.window.decorView.postOnAnimation { canceledFrame.countDown() }
                        }
                    }
                    assertTrue(canceledFrame.await(5, TimeUnit.SECONDS))
                    scenario.onActivity { activity ->
                        assertEquals("An append queued before owner detachment must not render later", 20, retiredRows.childCount)
                        assertSame(settings, activity.findViewById(R.id.page_settings))
                        assertEquals(499, AppPreferences(activity).favoriteDeadlines.size)
                    }
                }
            }
        } finally {
            preferences.languageCode = previousLanguage
            assertTrue(storage.edit().putString(AppPreferences.FAVORITE_DEADLINES_KEY, previousPayload).commit())
        }
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun awaitFavoriteRowCount(scenario: ActivityScenario<MainActivity>, expected: Int) {
        val deadline = SystemClock.elapsedRealtime() + 5_000
        var count = 0
        while (count < expected && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { activity -> count = activity.findViewById<ViewGroup>(R.id.favorite_deadlines_list).childCount }
            if (count < expected) SystemClock.sleep(10)
        }
        assertEquals("Favorites must append exactly one bounded batch", expected, count)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun clearFavorites(preferences: AppPreferences) {
        preferences.favoriteDeadlines.forEach { preferences.setFavorite(it, favorite = false) }
    }
}
