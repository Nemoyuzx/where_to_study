package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ImageView
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
            assertEquals(activity.dp(12), query.paddingLeft)
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
        awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
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
            awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
            UiDevice.getInstance(instrumentation).waitForIdle()
            scenario.onActivity { activity ->
                val scroll = activity.findViewById<ScrollView>(R.id.information_query_shuttle_scroll)
                val selector = scroll.findViewById<View>(R.id.information_query_mode_switch)
                assertNotNull("The shuttle selector must scroll with the page title", selector)
                val status = scroll.findViewById<ViewGroup>(R.id.information_query_shuttle_status)
                val refresh = status.findViewById<View>(R.id.information_query_shuttle_refresh)
                assertShuttleActionIcons(activity)
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
                assertShuttleActionIcons(activity)
                assertSame(cards.first(), descendants(routes).first { it.tag == "information.query.shuttle.route" })
                assertTrue(refresh.performClick())
            }
            awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
            UiDevice.getInstance(instrumentation).waitForIdle()
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.information_query_events_tab).performClick())
            }
            awaitView(R.id.information_query_search)
            scenario.onActivity { activity ->
                activity.findViewById<android.widget.EditText>(R.id.information_query_search).setText("test query")
                assertTrue(activity.findViewById<View>(R.id.information_query_shuttle_tab).performClick())
            }
            awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
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
        awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
        val closeFixture = installShuttleVisualFixture(scenario)
        try {
            awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
            val device = UiDevice.getInstance(instrumentation)
            device.waitForIdle()
            scenario.onActivity { activity ->
                assertShuttleActionIcons(activity)
                val scroll = activity.findViewById<ViewGroup>(R.id.information_query_shuttle_scroll)
                val tiles = descendants(scroll).filterIsInstance<LinearLayout>().filter {
                    it.tag == "information.query.shuttle.departure"
                }.toList()
                assertEquals(10, tiles.size)
                val nextTiles = tiles.filter { it.isSelected }
                assertEquals("A holiday must not advertise a next departure", 0, nextTiles.size)
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
            val timetableFrame = CountDownLatch(1)
            scenario.onActivity { activity ->
                val scroll = activity.findViewById<ScrollView>(R.id.information_query_shuttle_scroll)
                val timetable = scroll.findViewWithTag<ViewGroup>("information.query.shuttle.full-timetable")
                val warning = scroll.findViewWithTag<ViewGroup>("information.query.shuttle.holiday.warning")
                assertNotNull("Full timetable must be present", timetable)
                assertNotNull("The holiday fixture must show the conditional warning", warning)
                val routes = descendants(timetable).filterIsInstance<TextView>().count {
                    it.text.contains('→')
                }
                assertEquals("Both directions in both periods must be rendered", 4, routes)
                val periodMetadata = descendants(timetable).filterIsInstance<TextView>().filter {
                    it.tag == "information.query.shuttle.full-period.meta"
                }.map { it.text.toString() }.toList()
                assertEquals(4, periodMetadata.size)
                assertTrue(periodMetadata.any { it.contains(todayFromFixture()) &&
                    it.contains(activity.uiText("当前生效")) })
                assertTrue(periodMetadata.any { it.contains("2099-01-01") &&
                    it.contains(activity.uiText("即将生效")) })
                descendants(timetable).filterIsInstance<TextView>().forEach(::assertTextFits)
                descendants(warning).filterIsInstance<TextView>().forEach(::assertTextFits)
                val timetableLocation = IntArray(2).also(timetable::getLocationOnScreen)
                val scrollLocation = IntArray(2).also(scroll::getLocationOnScreen)
                val range = (scroll.getChildAt(0).bottom + scroll.paddingBottom - scroll.height)
                    .coerceAtLeast(0)
                val target = (scroll.scrollY + timetableLocation[1] - scrollLocation[1])
                    .coerceIn(0, range)
                scroll.scrollTo(0, target)
                scroll.postOnAnimation { scroll.postOnAnimation { timetableFrame.countDown() } }
            }
            assertTrue("The timetable scroll frame must be drawn", timetableFrame.await(5, TimeUnit.SECONDS))
            device.waitForIdle()
            assertTrue(device.takeScreenshot(File(directory, "$stage-$language-timetable.png")))
            scrollToEndAndWaitForFrame(scenario, R.id.information_query_shuttle_scroll)
            assertTrue(device.takeScreenshot(File(directory, "$stage-$language-bottom.png")))
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
        } finally { closeFixture() }
    }

    @Test
    fun shuttleContentIconsAndInformationalHintsFollowThemesWithAndWithoutDepartures() =
        inBothLanguages(phonesOnly = false) { scenario ->
            scenario.onActivity { activity ->
                assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
            }
            awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
            listOf(true, false).forEach { hasDepartures ->
                val closeFixture = installShuttleVisualFixture(scenario, stale = true, hasDepartures = hasDepartures)
                try {
                    awaitViewInHierarchy(scenario, R.id.information_query_shuttle_routes)
                    scenario.onActivity { activity ->
                        val scroll = activity.findViewById<ViewGroup>(R.id.information_query_shuttle_scroll)
                        val status = scroll.findViewById<ViewGroup>(R.id.information_query_shuttle_status)
                        val statusIcon = descendants(status).filterIsInstance<ImageView>().first()
                        val footer = scroll.findViewById<ViewGroup>(R.id.information_query_shuttle_source_footer)
                        val footerIcon = descendants(footer).filterIsInstance<ImageView>().first()
                        val routeIcon = descendants(scroll).first { it.tag == "information.query.shuttle.route" }
                            .let { descendants(it).filterIsInstance<ImageView>().first() }
                        assertTrue("Every service state must retain its bus silhouette",
                            sameIconSilhouette(checkNotNull(activity.getDrawable(R.drawable.ic_shuttle_bus)), statusIcon.drawable))
                        val unrelatedIcons = InformationQueryMode.entries.filter { it != InformationQueryMode.SHUTTLE }
                            .map { it.iconResource } + R.drawable.ic_settings_info
                        listOf(statusIcon, routeIcon, footerIcon).forEach { contentIcon ->
                            unrelatedIcons.forEach { resource ->
                                assertFalse("Shuttle content must not reuse another query's content glyph",
                                    sameIconSilhouette(contentIcon.drawable, checkNotNull(activity.getDrawable(resource))))
                            }
                        }
                        val departureTiles = descendants(scroll).count { it.tag == "information.query.shuttle.departure" }
                        assertEquals(if (hasDepartures) 10 else 0, departureTiles)
                        val cached = descendants(status).filterIsInstance<TextView>().single {
                            it.text.toString() == activity.uiText("当前展示最近一次成功同步的缓存")
                        }
                        val holiday = scroll.findViewWithTag<ViewGroup>("information.query.shuttle.holiday.warning")
                        val holidayNote = descendants(holiday).filterIsInstance<TextView>().single()
                        listOf(ColorThemeSelection(), ColorThemeSelection("ocean"), ColorThemeSelection("rose"),
                            ColorThemeSelection("custom", ThemeSeeds("#FFFFFF", "#000000", "#000000"))).forEach { selection ->
                            assertTrue(activity.applyColorTheme(selection))
                            listOf(cached, holidayNote).forEach { note ->
                                val expected = if (selection.preset == "default") Palette.muted else
                                    ColorThemeLogic.readableText(Palette.muted, note.themeSurfaceColor())
                                assertEquals("Informational shuttle hints must follow secondary theme text", expected, note.currentTextColor)
                                assertTrue("Shuttle hints must remain readable on their actual surface",
                                    ColorThemeLogic.contrast(note.currentTextColor, note.themeSurfaceColor()) >= 4.5)
                            }
                            listOf(statusIcon, routeIcon, footerIcon).forEach { icon ->
                                assertEquals(Palette.primaryText, icon.imageTintList!!.defaultColor)
                            }
                            assertSame(status, activity.findViewById<ViewGroup>(R.id.information_query_shuttle_status))
                        }
                    }
                } finally { closeFixture() }
            }
        }

    @Test
    fun captureAccountPasswordHintsAndIconButton() = inBothLanguages(phonesOnly = false) { scenario ->
        scenario.onActivity { activity ->
            assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        awaitViewInHierarchy(scenario, R.id.page_settings)
        val stage = InstrumentationRegistry.getArguments().getString("shuttleStage", "phone-light")
            .replace(Regex("[^a-zA-Z0-9_-]"), "")
        val language = AppPreferences(context).languageCode
        val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "shuttle-alignment")
            .apply { mkdirs() }
        scenario.onActivity { activity ->
            val page = activity.findViewById<ScrollView>(R.id.page_settings)
            val texts = descendants(page).filterIsInstance<TextView>().toList()
            val academicHint = texts.firstOrNull {
                it.text.toString().contains(if (language == "en") "mobile academic" else "移动教务登录")
            }
            val cloudHint = texts.firstOrNull {
                it.text.toString().contains(if (language == "en") "unified identity password" else "统一身份认证密码")
            }
            val switch = texts.firstOrNull { it.contentDescription == activity.uiText("改用教务密码") }
            assertNotNull(academicHint)
            assertNotNull(cloudHint)
            assertNotNull(switch)
            assertNotNull("Switch action must have an icon", switch?.compoundDrawablesRelative?.get(0))
            assertTrue("Switch action must be clickable", switch?.isClickable == true)
            assertTextFits(checkNotNull(academicHint))
            assertTextFits(checkNotNull(cloudHint))
            assertTextFits(checkNotNull(switch))
        }
        val device = UiDevice.getInstance(instrumentation)
        device.waitForIdle()
        assertTrue(device.takeScreenshot(File(directory, "$stage-$language-account-top.png")))
        scenario.onActivity { activity ->
            val scroll = activity.findViewById<ScrollView>(R.id.page_settings)
            val switch = descendants(scroll).filterIsInstance<TextView>().first {
                it.contentDescription == activity.uiText("改用教务密码")
            }
            val bounds = Rect(0, 0, switch.width, switch.height)
            (scroll.getChildAt(0) as ViewGroup).offsetDescendantRectToMyCoords(switch, bounds)
            scroll.scrollTo(0, (bounds.top - scroll.height / 2).coerceAtLeast(0))
        }
        device.waitForIdle()
        assertTrue(device.takeScreenshot(File(directory, "$stage-$language-account-cloud.png")))
    }

    private fun installShuttleVisualFixture(
        scenario: ActivityScenario<MainActivity>,
        stale: Boolean = false,
        hasDepartures: Boolean = true,
    ): () -> Unit {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(Date())
        val services = listOf("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
            .joinToString(",") { "\"$it\":{\"vehicle\":\"大巴\",\"count\":1}" }
        val rows = listOf("07:00", "08:30", "13:30", "17:30", "23:59").joinToString(",") {
            """{"departure_time":"$it","services":{${if (hasDepartures) services else ""}}}"""
        }
        val schedules = listOf("视觉回归现行时段" to today, "视觉回归后续时段" to "2099-01-01")
            .flatMap { (period, starts) ->
                listOf("西土城路校区" to "沙河校区", "沙河校区" to "西土城路校区")
                    .map { (from, to) ->
                        """{"period":{"label":"$period","start_date":"$starts"},"from":"$from","to":"$to","parse_status":"parsed","rows":[$rows]}"""
                    }
            }
            .joinToString(",")
        val payload = """{"schema_version":"1.0","generated_at":"${today}T00:00:00+08:00","status":"${if (stale) "stale" else "healthy"}",
            "source":{"name":"示例数据","page_url":"https://hq.bupt.edu.cn/tzgg.htm"},"items":[{
            "id":"visual-only","title":"班车布局视觉回归示例（非真实时刻表）","published_at":"$today",
            "source_url":"https://hq.bupt.edu.cn/tzgg.htm","kind":"regular_schedule","parse_status":"parsed",
            "stops":[{"campus":"西土城路校区","location":"教三楼西侧"},{"campus":"沙河校区","location":"学生活动中心南侧"}],
            "notes":["视觉回归示例，请勿作为实际乘车依据。"],"schedules":[$schedules]}]}"""
        val shuttles = ShuttleBusRepository(ShuttleBusClient { _, _, _, _ -> payload }, usesSampleData = false)
        val events = CalendarDailyInfoRepository(usesSampleData = true)
        val grades = AcademicGradesRepository({ null })
        val academicSchedules = ScheduleRepository(context, SecureCredentialStore(context), AppPreferences(context))
        scenario.onActivity { activity ->
            val original = activity.findViewById<View>(R.id.information_query_page)
            val parent = original.parent as ViewGroup
            val index = parent.indexOfChild(original)
            val params = original.layoutParams
            parent.removeView(original)
            val page = InformationQueryPage(activity, shuttles, events, AppPreferences(activity),
                (parent.width / activity.resources.displayMetrics.density).toInt(), InformationQuerySessionState(),
                activity.findViewById<View?>(R.id.phone_navigation) != null, grades, academicSchedules,
                holidaySnapshotForYear = { year -> HolidaysSnapshot(
                    year, HolidayMetadata.fallbackSource, "2026-10-02T00:00:00+08:00",
                    listOf(HolidayItem(today, "视觉回归节日", "holiday")),
                ) }).build()
            parent.addView(page, index, params)
        }
        return { shuttles.close(); events.close(); grades.close(); academicSchedules.close() }
    }

    private fun todayFromFixture(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(Date())

    private fun iconMask(drawable: Drawable): List<Boolean> {
        val bitmap = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
        return try {
            checkNotNull(drawable.constantState).newDrawable().mutate().apply {
                setBounds(0, 0, bitmap.width, bitmap.height)
                draw(Canvas(bitmap))
            }
            List(bitmap.width * bitmap.height) { index ->
                Color.alpha(bitmap.getPixel(index % bitmap.width, index / bitmap.width)) >= 64
            }
        } finally { bitmap.recycle() }
    }

    private fun sameIconSilhouette(first: Drawable, second: Drawable): Boolean {
        val a = iconMask(first)
        val b = iconMask(second)
        val union = a.indices.count { a[it] || b[it] }
        assertTrue("A content glyph must have a visible silhouette", union > 0)
        val intersection = a.indices.count { a[it] && b[it] }
        // A displayed vector can retain a raster cache at a different density.
        // Four boundary pixels differed for the same bus at 48x48; compare its
        // silhouette, not exact anti-alias edges. The same tolerance also makes
        // the unrelated-glyph rejection robust to density/tint differences.
        return intersection.toDouble() / union >= 0.99
    }

    private fun assertShuttleActionIcons(activity: MainActivity) {
        listOf(
            R.id.information_query_shuttle_refresh to "刷新班车信息",
            R.id.information_query_shuttle_notice_link to "查看班车通知原文",
            R.id.information_query_shuttle_source_link to "查看数据来源",
        ).forEach { (id, label) ->
            val action = activity.findViewById<ImageView>(id)
            assertTrue("$label must retain the v0.2.9 touch target", action.width >=
                activity.dp(ShuttleQueryLayoutLogic.ACTION_TOUCH_SIZE_DP) && action.height >=
                activity.dp(ShuttleQueryLayoutLogic.ACTION_TOUCH_SIZE_DP))
            assertTrue(action.isClickable && action.isFocusable)
            assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, action.importantForAccessibility)
            assertEquals(activity.uiText(label), action.contentDescription.toString())
            assertEquals(Palette.primaryText, action.imageTintList!!.defaultColor)

            val drawableBounds = RectF(action.drawable.bounds)
            action.imageMatrix.mapRect(drawableBounds)
            drawableBounds.offset(action.paddingLeft.toFloat(), action.paddingTop.toFloat())
            assertEquals("$label artwork viewport width",
                activity.dp(ShuttleQueryLayoutLogic.ACTION_ICON_SIZE_DP).toFloat(), drawableBounds.width(), 1f)
            assertEquals("$label artwork viewport height",
                activity.dp(ShuttleQueryLayoutLogic.ACTION_ICON_SIZE_DP).toFloat(), drawableBounds.height(), 1f)
            assertEquals(action.width / 2f, drawableBounds.centerX(), 1f)
            assertEquals(action.height / 2f, drawableBounds.centerY(), 1f)

            // Draw just the real vector using its actual ImageView transform: a
            // large hit area alone must never allow tiny or clipped artwork.
            val bitmap = Bitmap.createBitmap(action.width, action.height, Bitmap.Config.ARGB_8888)
            try {
                val canvas = Canvas(bitmap)
                canvas.translate(action.paddingLeft.toFloat(), action.paddingTop.toFloat())
                canvas.concat(action.imageMatrix)
                action.drawable.draw(canvas)
                val ink = Rect()
                for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
                    if (Color.alpha(bitmap.getPixel(x, y)) >= 64) ink.union(x, y, x + 1, y + 1)
                }
                assertTrue("$label must render visible glyph strokes, not just a large button: $ink",
                    ink.width() >= activity.dp(ShuttleQueryLayoutLogic.ACTION_MINIMUM_INK_DP) &&
                        ink.height() >= activity.dp(ShuttleQueryLayoutLogic.ACTION_MINIMUM_INK_DP))
                assertTrue("$label must not draw outside its centered icon viewport",
                    ink.left >= drawableBounds.left - 1 && ink.top >= drawableBounds.top - 1 &&
                        ink.right <= drawableBounds.right + 1 && ink.bottom <= drawableBounds.bottom + 1)
                assertEquals("$label visible strokes must be horizontally centered",
                    drawableBounds.centerX(), ink.exactCenterX(), activity.dp(1).toFloat())
                assertEquals("$label visible strokes must be vertically centered",
                    drawableBounds.centerY(), ink.exactCenterY(), activity.dp(1).toFloat())
            } finally { bitmap.recycle() }
        }
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

    private fun awaitViewInHierarchy(scenario: ActivityScenario<MainActivity>, id: Int) {
        // Large text in landscape can put the routes below the fold. They must
        // be laid out, but need not appear in the visible accessibility tree.
        val deadline = android.os.SystemClock.elapsedRealtime() + 5_000
        var ready = false
        while (!ready && android.os.SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { activity ->
                val view = activity.findViewById<View?>(id)
                ready = view != null && view.isLaidOut && view.width > 0 && view.height > 0
            }
            if (!ready) android.os.SystemClock.sleep(30)
        }
        assertTrue("The requested view must finish layout", ready)
        instrumentation.waitForIdleSync()
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
            // Android permits a wrapped line's trailing space beyond its width;
            // getLineMax measures the visible text rather than that whitespace.
            assertTrue("Text must fit its column: ${label.text}; line=$line width=${layout.getLineMax(line)} available=$contentWidth",
                layout.getLineMax(line) <= contentWidth + 1)
        }
        assertTrue("Text must fit its control height: ${label.text}", layout.height <= contentHeight + 1)
    }

    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) repeat(view.childCount) { yieldAll(descendants(view.getChildAt(it))) }
    }
}
