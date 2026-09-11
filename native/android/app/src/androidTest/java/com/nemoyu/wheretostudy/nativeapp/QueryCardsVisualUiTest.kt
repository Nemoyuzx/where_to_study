package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class QueryCardsVisualUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Before
    fun acceptPrivacyConsent() = ensurePrivacyConsentForUiTest()

    @Test
    fun plannerControlsShareCardEdgesAndLeaveRoomForBothLanguages() = inBothLanguages { scenario ->
        scenario.onActivity { activity ->
            val page = activity.findViewById<ViewGroup>(R.id.page_planner)
            val query = activity.findViewById<ViewGroup>(R.id.planner_query_surface)
            val campus = page.findViewWithTag<ViewGroup>("planner.campus.control")
            val fetch = activity.findViewById<ViewGroup>(R.id.planner_fetch_button)
            assertTextFits(page.findViewWithTag("planner.page.title"))
            assertEquals(activity.dp(UiMetrics.surfacePaddingDp), query.paddingLeft)
            assertEquals(query.paddingLeft, query.paddingRight)
            assertEquals(campus.left, fetch.left)
            assertEquals(campus.right, fetch.right)
            assertTrue(fetch.height >= activity.dp(UiMetrics.phoneControlMinHeightDp))
            assertTextFits(fetch.getChildAt(0) as TextView)

            val slots = page.findViewWithTag<LinearLayout>("planner.slot.controls")
            repeat(slots.childCount) { index ->
                val row = slots.getChildAt(index) as LinearLayout
                assertRowEdges(row)
                repeat(row.childCount) slotColumn@{ column ->
                    val label = row.getChildAt(column) as? TextView ?: return@slotColumn
                    if (label.text.isNotEmpty()) {
                        assertTrue(label.height >= activity.dp(UiMetrics.phoneControlMinHeightDp))
                        assertTextFits(label)
                    }
                }
            }
            val buildings = activity.findViewById<ViewGroup>(R.id.planner_buildings_surface)
            (1 until buildings.childCount).forEach { index ->
                val row = buildings.getChildAt(index) as? LinearLayout ?: return@forEach
                assertRowEdges(row)
                repeat(row.childCount) { column ->
                    val button = row.getChildAt(column) as? LinearLayout ?: return@repeat
                    assertTrue("A building control must keep its minimum touch height",
                        button.height >= activity.dp(UiMetrics.phoneControlMinHeightDp))
                    assertTextFits(button.getChildAt(1) as TextView)
                }
            }
            assertTrue(activity.findViewById<View?>(R.id.planner_weather_details) == null)
            assertTrue(activity.findViewById<View>(R.id.planner_weather_toggle).performClick())
            assertNotNull(activity.findViewById<View?>(R.id.planner_weather_details))
        }
    }

    @Test
    fun shuttleTimeTilesAndBothSourceFootersRemainReadableAboveNavigation() = inBothLanguages { scenario ->
        scenario.onActivity { activity ->
            assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
        }
        awaitView(R.id.information_query_shuttle_routes)
        scenario.onActivity { activity ->
            val page = activity.findViewById<ViewGroup>(R.id.information_query_page)
            assertFalse(descendants(page).filterIsInstance<TextView>().any {
                it.text.toString() == "校区班车与重要事件"
            })
            val grids = descendants(page).filterIsInstance<LinearLayout>().filter {
                it.tag == "information.query.shuttle.departures"
            }.toList()
            assertTrue("Sample shuttle routes must expose their departure tiles", grids.isNotEmpty())
            grids.forEach { grid ->
                repeat(grid.childCount) { index ->
                    val row = grid.getChildAt(index) as LinearLayout
                    assertRowEdges(row)
                    assertTrue("A departure row must render its time and vehicle labels",
                        row.height >= activity.dp(44))
                    descendants(row).filterIsInstance<TextView>().forEach(::assertTextFits)
                }
            }
        }
        assertFooterClearsNavigation(scenario, R.id.information_query_shuttle_scroll)
        scenario.onActivity { activity ->
            assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
        }
        awaitView(R.id.information_query_event_favorite)
        assertFooterClearsNavigation(scenario, R.id.information_query_events_scroll)
    }

    @Test
    fun shuttleReferenceStructureAdaptsAcrossWidthsAndPreservesModeState() =
        inBothLanguages(phonesOnly = false) { scenario ->
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
            }
            awaitView(R.id.information_query_shuttle_routes)
            UiDevice.getInstance(instrumentation).waitForIdle()
            scenario.onActivity { activity ->
                val scroll = activity.findViewById<ScrollView>(R.id.information_query_shuttle_scroll)
                val selector = scroll.findViewById<View>(R.id.information_query_mode_switch)
                assertNotNull("The shuttle selector must scroll with the page title", selector)
                val status = scroll.findViewById<ViewGroup>(R.id.information_query_shuttle_status)
                val refresh = status.findViewById<View>(R.id.information_query_shuttle_refresh)
                assertTrue(refresh.width >= activity.dp(48) && refresh.height >= activity.dp(48))
                assertTrue(refresh.isClickable)
                assertTrue(status.findViewById<View>(R.id.information_query_shuttle_notice_link).isClickable)
                listOf("status.title", "status.summary", "notice.title", "notice.date").forEach { suffix ->
                    assertTextFits(status.findViewWithTag("information.query.shuttle.$suffix"))
                }
                assertTrue(descendants(status).any { it.tag == "information.query.shuttle.status.note" })
                val routes = scroll.findViewById<LinearLayout>(R.id.information_query_shuttle_routes)
                val cards = descendants(routes).filterIsInstance<LinearLayout>().filter {
                    it.tag == "information.query.shuttle.route"
                }.toList()
                assertEquals(2, cards.size)
                val columns = if (routes.width >= activity.dp(576)) 2 else 1
                assertEquals(columns, (routes.getChildAt(0) as LinearLayout).childCount)
                cards.forEach { card ->
                    assertNotNull(card.findViewWithTag<View>("information.query.shuttle.route.pickup"))
                    assertNotNull(card.findViewWithTag<View>("information.query.shuttle.departures"))
                    descendants(card).filterIsInstance<TextView>().forEach(::assertTextFits)
                }
                assertTrue(activity.applyColorTheme(ColorThemeSelection("ocean")))
                assertSame(cards.first(), descendants(routes).first { it.tag == "information.query.shuttle.route" })
                assertTrue(refresh.performClick())
            }
            awaitView(R.id.information_query_shuttle_routes)
            UiDevice.getInstance(instrumentation).waitForIdle()
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
            }
            awaitView(R.id.information_query_search)
            scenario.onActivity { activity ->
                activity.findViewById<android.widget.EditText>(R.id.information_query_search).setText("test query")
                assertTrue(activity.findViewById<View>(R.id.information_query_shuttle_tab).performClick())
            }
            awaitView(R.id.information_query_shuttle_routes)
            UiDevice.getInstance(instrumentation).waitForIdle()
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
            }
            awaitView(R.id.information_query_search)
            scenario.onActivity { activity ->
                assertEquals("test query", activity.findViewById<TextView>(R.id.information_query_search).text.toString())
            }
        }

    @Test
    fun captureShuttleReferenceLayouts() = inBothLanguages(phonesOnly = false) { scenario ->
        scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_query).performClick()
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        awaitView(R.id.information_query_shuttle_routes)
        val closeFixture = installShuttleVisualFixture(scenario)
        try {
            awaitView(R.id.information_query_shuttle_routes)
            val device = UiDevice.getInstance(instrumentation)
            device.waitForIdle()
            scenario.onActivity { activity ->
                val scroll = activity.findViewById<ViewGroup>(R.id.information_query_shuttle_scroll)
                val tiles = descendants(scroll).filterIsInstance<LinearLayout>().filter {
                    it.tag == "information.query.shuttle.departure"
                }.toList()
                assertEquals(10, tiles.size)
                val nextTiles = tiles.filter { it.isSelected }
                val currentTime = SimpleDateFormat("HH:mm", Locale.ROOT).apply {
                    timeZone = TimeZone.getTimeZone("Asia/Shanghai")
                }.format(Date())
                assertEquals("Each direction marks only its next future departure",
                    if (currentTime < "23:59") 2 else 0, nextTiles.size)
                nextTiles.forEach { tile ->
                    val dot = tile.findViewWithTag<View>("information.query.shuttle.next.dot")
                    assertEquals(activity.dp(5), dot.width)
                    assertEquals(activity.dp(5), dot.height)
                    assertEquals(ColorUtils.blendARGB(Palette.surface, Palette.primaryFill, 0.12f),
                        (tile.background as GradientDrawable).color!!.defaultColor)
                    descendants(tile).filterIsInstance<TextView>().forEach(::assertTextFits)
                }
                tiles.filterNot { it.isSelected }.forEach { tile ->
                    assertEquals(Palette.background, (tile.background as GradientDrawable).color!!.defaultColor)
                }
            }
            val stage = InstrumentationRegistry.getArguments().getString("shuttleStage", "phone-light")
                .replace(Regex("[^a-zA-Z0-9_-]"), "")
            val language = AppPreferences(context).languageCode
            val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "shuttle-alignment")
                .apply { mkdirs() }
            assertTrue(device.takeScreenshot(File(directory, "$stage-$language-top.png")))
            scrollToEndAndWaitForFrame(scenario, R.id.information_query_shuttle_scroll)
            scenario.onActivity { activity ->
                val footer = activity.findViewById<View>(R.id.information_query_shuttle_source_footer)
                val footerLocation = IntArray(2).also(footer::getLocationOnScreen)
                val navigation = activity.findViewById<View?>(R.id.phone_navigation)
                if (navigation != null) {
                    val navigationLocation = IntArray(2).also(navigation::getLocationOnScreen)
                    assertTrue("The captured fixture footer must completely clear the navigation",
                        footerLocation[1] + footer.height <= navigationLocation[1])
                }
                descendants(footer).filterIsInstance<TextView>().forEach(::assertTextFits)
            }
            assertTrue(device.takeScreenshot(File(directory, "$stage-$language-bottom.png")))
        } finally { closeFixture() }
    }

    private fun installShuttleVisualFixture(scenario: ActivityScenario<MainActivity>): () -> Unit {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(Date())
        val services = listOf("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
            .joinToString(",") { "\"$it\":{\"vehicle\":\"大巴\",\"count\":1}" }
        val rows = listOf("07:00", "08:30", "13:30", "17:30", "23:59").joinToString(",") {
            """{"departure_time":"$it","services":{$services}}"""
        }
        val schedules = listOf("西土城路校区" to "沙河校区", "沙河校区" to "西土城路校区")
            .joinToString(",") { (from, to) ->
                """{"period":{"label":"视觉回归示例","start_date":"$today"},"from":"$from","to":"$to","parse_status":"parsed","rows":[$rows]}"""
            }
        val payload = """{"schema_version":"1.0","generated_at":"${today}T00:00:00+08:00","status":"healthy",
            "source":{"name":"示例数据","page_url":"https://hq.bupt.edu.cn/tzgg.htm"},"items":[{
            "id":"visual-only","title":"班车布局视觉回归示例（非真实时刻表）","published_at":"$today",
            "source_url":"https://hq.bupt.edu.cn/tzgg.htm","kind":"regular_schedule","parse_status":"parsed",
            "stops":[{"campus":"西土城路校区","location":"教三楼西侧"},{"campus":"沙河校区","location":"学生活动中心南侧"}],
            "notes":["视觉回归示例，请勿作为实际乘车依据。"],"schedules":[$schedules]}]}"""
        val shuttles = ShuttleBusRepository(ShuttleBusClient { _, _, _, _ -> payload }, usesSampleData = false)
        val events = CalendarDailyInfoRepository(usesSampleData = true)
        scenario.onActivity { activity ->
            val original = activity.findViewById<View>(R.id.information_query_page)
            val parent = original.parent as ViewGroup
            val index = parent.indexOfChild(original)
            val params = original.layoutParams
            parent.removeView(original)
            val page = InformationQueryPage(activity, shuttles, events, AppPreferences(activity),
                (parent.width / activity.resources.displayMetrics.density).toInt(), InformationQuerySessionState(),
                activity.findViewById<View?>(R.id.phone_navigation) != null).build()
            parent.addView(page, index, params)
        }
        return { shuttles.close(); events.close() }
    }

    @Test
    fun eventFiltersStayTogetherAndSemanticDeadlinesFollowThemeChanges() = inBothLanguages { scenario ->
        scenario.onActivity { activity ->
            assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
            assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
        }
        awaitView(R.id.information_query_event_favorite)
        UiDevice.getInstance(instrumentation).waitForIdle()
        scenario.onActivity { activity ->
            val shuttleTab = activity.findViewById<TextView>(R.id.information_query_shuttle_tab)
            val eventsTab = activity.findViewById<TextView>(R.id.information_query_events_tab)
            assertFalse(shuttleTab.isSelected)
            assertFalse(shuttleTab.typeface.isBold)
            assertTrue(eventsTab.isSelected)
            assertTrue(eventsTab.typeface.isBold)
            val thumb = activity.findViewById<View>(R.id.information_query_mode_thumb)
            val thumbBounds = android.graphics.Rect().also(thumb::getGlobalVisibleRect)
            val tabBounds = android.graphics.Rect().also(eventsTab::getGlobalVisibleRect)
            assertEquals("Mode highlight must follow even a pre-layout selection",
                tabBounds.exactCenterX(), thumbBounds.exactCenterX(), 1f)
            val page = activity.findViewById<ViewGroup>(R.id.information_query_page)
            val filters = page.findViewWithTag<ViewGroup>("information.query.events.filters")
            val search = activity.findViewById<View>(R.id.information_query_search)
            val toggle = activity.findViewById<View>(R.id.information_query_show_ended)
            assertSame(filters, search.parent)
            assertSame(filters, toggle.parent)
            assertEquals(filters.paddingLeft, search.left)
            assertEquals(filters.width - filters.paddingRight, search.right)
            assertTrue(search.height >= activity.dp(UiMetrics.phoneControlMinHeightDp))
            assertTrue(toggle.height >= activity.dp(UiMetrics.phoneControlMinHeightDp))
            assertTrue(activity.findViewById<TextView>(R.id.information_query_result_count).text.isNotBlank())

            val list = activity.findViewById<ViewGroup>(R.id.information_query_events_list)
            assertTrue(list.childCount > 0)
            val firstCard = list.getChildAt(0)
            val cardText = descendants(firstCard).filterIsInstance<TextView>().map { it.text.toString() }.toList()
            val deadlines = descendants(list).filterIsInstance<TextView>().filter {
                it.tag == "information.query.event.deadline"
            }.toList()
            assertTrue(deadlines.isNotEmpty())
            val supportedSemanticColors = setOf(
                Palette.publicDeadline, Palette.conferenceDeadline, Palette.schoolNotice,
                Palette.summerCampDeadline, Palette.hackathonDeadline,
            )
            deadlines.forEach { assertTrue(it.currentTextColor in supportedSemanticColors) }
            listOf(ColorThemeSelection("ocean"), ColorThemeSelection("rose")).forEach { selection ->
                assertTrue(activity.applyColorTheme(selection))
                assertSame(firstCard, list.getChildAt(0))
                assertEquals(cardText, descendants(firstCard).filterIsInstance<TextView>().map { it.text.toString() }.toList())
                assertEquals(Palette.surface, (firstCard.background as GradientDrawable).color!!.defaultColor)
                deadlines.forEach { label ->
                    assertTrue("Deadline text must stay readable on the current card surface",
                        ColorThemeLogic.contrast(label.currentTextColor, label.themeSurfaceColor()) >= 4.5)
                }
            }
        }
    }

    private fun inBothLanguages(phonesOnly: Boolean = true, block: (ActivityScenario<MainActivity>) -> Unit) {
        val preferences = AppPreferences(context)
        val originalLanguage = preferences.languageCode
        val originalWeather = preferences.weatherEnabled
        val originalTheme = ColorThemePreferences(context).load()
        try {
            preferences.weatherEnabled = true
            listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
                preferences.languageCode = language.code
                ColorThemePreferences(context).save(ColorThemeSelection())
                val intent = Intent(context, MainActivity::class.java)
                    .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)
                ActivityScenario.launch<MainActivity>(intent).use { scenario ->
                    instrumentation.waitForIdleSync()
                    var phone = false
                    scenario.onActivity { activity ->
                        phone = activity.findViewById<View?>(R.id.phone_navigation) != null
                    }
                    if (phonesOnly) assumeTrue("These regressions cover phone card layouts", phone)
                    block(scenario)
                }
            }
        } finally {
            preferences.languageCode = originalLanguage
            preferences.weatherEnabled = originalWeather
            ColorThemePreferences(context).save(originalTheme)
        }
    }

    private fun awaitView(id: Int) {
        assertTrue(UiDevice.getInstance(instrumentation).wait(Until.hasObject(By.res(
            context.packageName, context.resources.getResourceEntryName(id),
        )), 5_000))
        instrumentation.waitForIdleSync()
    }

    private fun assertFooterClearsNavigation(scenario: ActivityScenario<MainActivity>, scrollID: Int) {
        scrollToEndAndWaitForFrame(scenario, scrollID)
        scenario.onActivity { activity ->
            val scroll = activity.findViewById<ScrollView>(scrollID)
            val footer = scroll.findViewWithTag<View>("information.query.source.footer")
            val navigation = activity.findViewById<View>(R.id.phone_navigation)
            val footerLocation = IntArray(2).also(footer::getLocationOnScreen)
            val navigationLocation = IntArray(2).also(navigation::getLocationOnScreen)
            assertTrue("A fully scrolled source notice must clear the floating navigation",
                footerLocation[1] + footer.height <= navigationLocation[1])
            assertTrue(footer.isClickable)
            descendants(footer).filterIsInstance<TextView>().forEach(::assertTextFits)
        }
    }

    private fun scrollToEndAndWaitForFrame(scenario: ActivityScenario<MainActivity>, scrollID: Int) {
        val drawn = CountDownLatch(1)
        scenario.onActivity { activity ->
            val scroll = activity.findViewById<ScrollView>(scrollID)
            scroll.post {
                scroll.scrollTo(0, (scroll.getChildAt(0).bottom + scroll.paddingBottom - scroll.height).coerceAtLeast(0))
                // Accessibility-idle alone can precede the rendered scroll frame.
                // Cross two real display callbacks before taking the screenshot.
                scroll.postOnAnimation { scroll.postOnAnimation { drawn.countDown() } }
            }
        }
        assertTrue("The scrolled frame must be drawn", drawn.await(5, TimeUnit.SECONDS))
        instrumentation.waitForIdleSync()
        scenario.onActivity { activity ->
            val scroll = activity.findViewById<ScrollView>(scrollID)
            val range = (scroll.getChildAt(0).bottom + scroll.paddingBottom - scroll.height).coerceAtLeast(0)
            assertEquals("Capture only the actual end of the scroll range", range, scroll.scrollY)
        }
    }

    private fun assertRowEdges(row: LinearLayout) {
        assertTrue(row.childCount > 0)
        assertEquals(row.paddingLeft, row.getChildAt(0).left)
        assertEquals(row.width - row.paddingRight, row.getChildAt(row.childCount - 1).right)
        val widths = (0 until row.childCount).map { row.getChildAt(it).width }
        assertTrue("Columns must share available space evenly", abs(widths.max() - widths.min()) <= 1)
    }

    private fun assertTextFits(label: TextView) {
        assertTrue("Text must have visible width: ${label.text}", label.width > 0)
        assertTrue("Text must have visible height: ${label.text}", label.height > 0)
        val layout = label.layout
        assertNotNull("Text must be laid out: ${label.text}", layout)
        assertTrue("Text must render at least one line: ${label.text}", layout.lineCount > 0)
        val contentWidth = label.width - label.compoundPaddingLeft - label.compoundPaddingRight
        val contentHeight = label.height - label.compoundPaddingTop - label.compoundPaddingBottom
        repeat(layout.lineCount) { line ->
            assertEquals("Text must not ellipsize: ${label.text}", 0, layout.getEllipsisCount(line))
            assertTrue("Text must fit its column: ${label.text}", layout.getLineWidth(line) <= contentWidth + 1)
        }
        assertTrue("Text must fit its control height: ${label.text}", layout.height <= contentHeight + 1)
    }

    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) repeat(view.childCount) { yieldAll(descendants(view.getChildAt(it))) }
    }
}
