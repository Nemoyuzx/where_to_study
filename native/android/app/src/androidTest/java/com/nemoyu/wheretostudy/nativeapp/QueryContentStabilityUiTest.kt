package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class QueryContentStabilityUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Before fun privacy() = ensurePrivacyConsentForUiTest()

    @Test fun activitySchedulePublicationInvalidatesOnlyTheExamBody() {
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
            scenario.onActivity { activity ->
                activity.findViewById<View>(R.id.navigation_query).performClick()
                activity.findViewById<View>(R.id.information_query_grades_tab).performClick()
                val page = activity.findViewById<ViewGroup>(R.id.information_query_page)
                val header = page.findViewWithTag<View>("information.query.header")
                val content = activity.findViewById<FrameLayout>(R.id.information_query_content)
                val body = content.getChildAt(0)
                activity.scheduleDidRefresh()
                assertSame(page, activity.findViewById(R.id.information_query_page))
                assertSame(body, content.getChildAt(0))
                activity.findViewById<View>(R.id.information_query_exams_tab).performClick()
                val examBody = content.getChildAt(0)
                activity.scheduleDidRefresh()
                assertSame(page, activity.findViewById(R.id.information_query_page))
                assertSame(header, page.findViewWithTag("information.query.header"))
                assertNotSame("A completed schedule refresh updates exam content", examBody, content.getChildAt(0))
                activity.findViewById<View>(R.id.navigation_calendar).performClick()
                activity.scheduleDidRefresh()
                assertNull(activity.findViewById<View?>(R.id.information_query_page))
            }
        }
    }

    @Test fun switchingKeepsTheShellAndScrollOwnerAndOnlyAnimatesContent() = bothLanguages { scenario, fixture ->
        fixture.loadGrades()
        settled(scenario)
        lateinit var page: ViewGroup
        lateinit var header: View
        lateinit var selector: View
        lateinit var scroll: ScrollView
        lateinit var navigation: View
        lateinit var content: FrameLayout
        scenario.onActivity { activity ->
            page = activity.findViewById(R.id.information_query_page)
            header = page.findViewWithTag("information.query.header")
            selector = activity.findViewById(R.id.information_query_mode_switch)
            content = activity.findViewById(R.id.information_query_content)
            scroll = activity.findViewById(R.id.information_query_grades_scroll)
            navigation = activity.findViewById<View?>(R.id.phone_navigation)
                ?: activity.findViewById(R.id.tablet_navigation)
            listOf(R.id.information_query_exams_tab, R.id.information_query_assignments_tab,
                R.id.information_query_shuttle_tab, R.id.information_query_events_tab,
                R.id.information_query_grades_tab).forEach { id ->
                assertTrue(activity.findViewById<View>(id).performClick())
                assertSame(page, activity.findViewById(R.id.information_query_page))
                assertSame(header, page.findViewWithTag("information.query.header"))
                assertSame(selector, activity.findViewById(R.id.information_query_mode_switch))
                assertSame(scroll, content.parent?.parent)
                assertSame(navigation, activity.findViewById(navigation.id))
                assertEquals("Rapid selection leaves exactly one current body", 1, content.childCount)
                listOf(page, header, selector, scroll, navigation).forEach { stable ->
                    assertEquals(1f, stable.alpha)
                    assertEquals(0f, stable.translationX)
                    assertEquals(0f, stable.translationY)
                }
                assertEquals("Only the replacement body starts its fade", 0f, content.getChildAt(0).alpha)
            }
            assertEquals("Selection never starts a private fetch", 1, fixture.gradeFetches.get())
            assertNull(fixture.events.allAssignments())
        }
        settled(scenario)
        var savedScroll = 0
        scenario.onActivity {
            val labels = descendants(selector).filterIsInstance<TextView>()
            labels.forEachIndexed { index, label ->
                assertTextFits(label)
                assertEquals("Query labels stay intact at the user's font scale", 1, label.layout.lineCount)
                assertEquals("Accessibility keeps the complete query name",
                    it.uiText(InformationQueryMode.entries[index].label), label.contentDescription)
            }
            val viewport = page.findViewWithTag<View>("information.query.mode.viewport")
            val visible = android.graphics.Rect().also(viewport::getGlobalVisibleRect)
            assertFalse("The fixed mode selector is never horizontally scrollable", viewport is android.widget.HorizontalScrollView)
            assertEquals("All five modes fit the viewport at every font scale", viewport.width, selector.width)
            labels.forEach { label ->
                val location = IntArray(2).also(label::getLocationOnScreen)
                assertTrue(location[0] >= visible.left && location[0] + label.width <= visible.right)
                if (it.findViewById<View?>(R.id.phone_navigation) != null) {
                    assertNotNull("Phone modes always carry a vector icon", label.compoundDrawablesRelative[0])
                }
            }
            val selected = it.findViewById<View>(R.id.information_query_grades_tab)
            val position = IntArray(2).also(selected::getLocationOnScreen)
            assertTrue("The selected complete label is revealed", position[0] >= visible.left &&
                position[0] + selected.width <= visible.right)
            scroll.scrollTo(0, 240)
            savedScroll = scroll.scrollY
            assertTrue("The long grade fixture must have a real scroll range", savedScroll > 0)
        }
        settled(scenario)
        scenario.onActivity { activity -> activity.findViewById<View>(R.id.information_query_exams_tab).performClick() }
        settled(scenario)
        scenario.onActivity { activity -> activity.findViewById<View>(R.id.information_query_grades_tab).performClick() }
        settled(scenario)
        scenario.onActivity {
            assertSame(scroll, it.findViewById(R.id.information_query_grades_scroll))
            assertEquals("Returning restores the selected query's position", savedScroll, scroll.scrollY)
            assertEquals(1f, content.getChildAt(0).alpha)
            scroll.scrollTo(0, 0)
        }
        settled(scenario)
        scenario.onActivity { activity ->
            val rows = descendants(content).filter { it.tag == "academic.grade.row" }
            val average = content.findViewWithTag<ViewGroup>("academic.grade.average")
            assertEquals(activity.dp(10), average.paddingTop)
            assertEquals(activity.dp(10), average.paddingBottom)
            assertEquals("GPA must contain one compact text row", 1, average.childCount)
            rows.forEach { row ->
                assertEquals(activity.dp(10), row.paddingTop)
                assertEquals(activity.dp(10), row.paddingBottom)
                descendants(row).filterIsInstance<TextView>().forEach(::assertTextFits)
            }
            assertTextFits(average.getChildAt(0) as TextView)
            assertTrue(text(content).contains("0"))
            assertTrue(text(content).contains("通过 / Pass"))
            assertTrue(text(content).contains(activity.uiText("未公布")))
            val shortRow = rows[1] as ViewGroup
            val labelHeights = (0 until shortRow.childCount).sumOf { shortRow.getChildAt(it).height }
            assertEquals("Compact card adds only its 20 dp vertical insets", labelHeights + activity.dp(20), shortRow.height)
            assertEquals(activity.dp(UiMetrics.controlHeightDp),
                activity.findViewById<View>(R.id.information_query_grades_refresh).minimumHeight)
        }
        capture("grades")
        scenario.onActivity { activity -> activity.findViewById<View>(R.id.information_query_exams_tab).performClick() }
        settled(scenario)
        assertGaps(scenario)
        capture("exams")
        scenario.onActivity { activity -> activity.findViewById<View>(R.id.information_query_assignments_tab).performClick() }
        settled(scenario)
        assertGaps(scenario)
        capture("assignments-empty")
        val loaded = CountDownLatch(1)
        fixture.events.addObserver(loaded) { if (fixture.events.allAssignments() != null) loaded.countDown() }
        scenario.onActivity { activity -> activity.findViewById<View>(R.id.information_query_assignments_refresh).performClick() }
        assertTrue(loaded.await(5, TimeUnit.SECONDS))
        fixture.events.removeObserver(loaded)
        settled(scenario)
        assertGaps(scenario)
        capture("assignments")
    }

    @Test fun latePrivateResultsAndUnrelatedPublicUpdatesLeaveTheSelectedBodyAlone() {
        val release = CountDownLatch(1)
        val entered = CountDownLatch(1)
        val published = CountDownLatch(1)
        withFixture("en", { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }) { scenario, fixture ->
            try {
                scenario.onActivity { fixture.grades.load() }
                assertTrue(entered.await(5, TimeUnit.SECONDS))
                lateinit var body: View
                lateinit var header: View
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.information_query_assignments_tab).performClick()
                    body = activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0)
                    header = activity.findViewById<ViewGroup>(R.id.information_query_page)
                        .findViewWithTag("information.query.header")
                    fixture.grades.addObserver { if (!fixture.grades.isLoading) published.countDown() }
                }
                release.countDown()
                assertTrue(published.await(5, TimeUnit.SECONDS))
                val publicFinished = CountDownLatch(1)
                fixture.events.loadImportantEvents(force = true) { publicFinished.countDown() }
                assertTrue(publicFinished.await(5, TimeUnit.SECONDS))
                settled(scenario)
                scenario.onActivity { activity ->
                    assertSame("Late grades and public events cannot rebuild the assignments body", body,
                        activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0))
                    assertSame(header, activity.findViewById<ViewGroup>(R.id.information_query_page)
                        .findViewWithTag("information.query.header"))
                    assertFalse(text(body).contains("Synthetic long course"))
                    activity.findViewById<View>(R.id.information_query_grades_tab).performClick()
                    assertTrue(text(activity.findViewById(R.id.information_query_content)).contains("Synthetic long course"))
                    assertEquals(1, fixture.gradeFetches.get())
                }
            } finally { release.countDown() }
        }
    }

    @Test fun assignmentPublicationAfterSwitchingCannotReplaceTheGradeBody() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        withFixture("en", {}, { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }) { scenario, fixture ->
            try {
                val published = CountDownLatch(1)
                fixture.events.addObserver(published) { if (fixture.events.allAssignments() != null) published.countDown() }
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.information_query_assignments_tab).performClick()
                    activity.findViewById<View>(R.id.information_query_assignments_refresh).performClick()
                }
                assertTrue(entered.await(5, TimeUnit.SECONDS))
                lateinit var gradeBody: View
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.information_query_grades_tab).performClick()
                    gradeBody = activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0)
                }
                release.countDown()
                assertTrue(published.await(5, TimeUnit.SECONDS))
                settled(scenario)
                scenario.onActivity { activity ->
                    assertSame(gradeBody, activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0))
                    assertFalse(text(gradeBody).contains("示例课程作业"))
                    activity.findViewById<View>(R.id.information_query_assignments_tab).performClick()
                    assertEquals(1, descendants(activity.findViewById(R.id.information_query_content))
                        .count { it.tag == "assignment.query.row" })
                    assertFalse(fixture.events.isLoadingAllAssignments())
                }
                fixture.events.removeObserver(published)
            } finally { release.countDown() }
        }
    }

    private fun assertGaps(scenario: ActivityScenario<MainActivity>) = scenario.onActivity { activity ->
        val body = activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0) as ViewGroup
        assertTrue(body.childCount >= 2)
        (1 until body.childCount).forEach { index ->
            assertEquals("Every control, notice and card keeps a visible 16 dp gap", activity.dp(16),
                body.getChildAt(index).top - body.getChildAt(index - 1).bottom)
        }
        descendants(body).filterIsInstance<TextView>().forEach(::assertTextFits)
    }

    private class Fixture(val grades: AcademicGradesRepository, val events: CalendarDailyInfoRepository,
        val shuttles: ShuttleBusRepository, val schedules: ScheduleRepository, val gradeFetches: AtomicInteger) {
        fun loadGrades() {
            val finished = CountDownLatch(1)
            val observer: () -> Unit = { if (!grades.isLoading) finished.countDown() }
            InstrumentationRegistry.getInstrumentation().runOnMainSync { grades.addObserver(observer); grades.load() }
            assertTrue(finished.await(5, TimeUnit.SECONDS))
            InstrumentationRegistry.getInstrumentation().runOnMainSync { grades.removeObserver(observer) }
        }
        fun close() { grades.close(); events.close(); shuttles.close(); schedules.close() }
    }

    private fun bothLanguages(block: (ActivityScenario<MainActivity>, Fixture) -> Unit) =
        listOf("zh-Hans", "en").forEach { withFixture(it, {}, block = block) }

    private fun withFixture(language: String, beforeGrades: () -> Unit, beforeAssignments: () -> Unit = {},
        block: (ActivityScenario<MainActivity>, Fixture) -> Unit) {
        val preferences = AppPreferences(context)
        val oldLanguage = preferences.languageCode
        preferences.languageCode = language
        val count = AtomicInteger()
        val grades = AcademicGradesRepository({ Credentials("synthetic-only", "synthetic-only") },
            { AcademicTerms("2026-2027-1", listOf(AcademicTerm("2026-2027-1", "Synthetic term"))) },
            { _, term, type -> count.incrementAndGet(); beforeGrades(); gradeFixture(term, type) })
        val fixture = Fixture(grades, CalendarDailyInfoRepository(usesSampleData = true,
            beforeAssignmentPublication = beforeAssignments),
            ShuttleBusRepository(usesSampleData = true),
            ScheduleRepository(context, SecureCredentialStore(context), preferences), count)
        // UI-only in-memory fixture. No credential or schedule cache is written.
        ScheduleRepository::class.java.getDeclaredField("schedule").apply { isAccessible = true }
            .set(fixture.schedules, ScheduleSnapshot("2026-2027-1", "2026-09-07", "synthetic", emptyList(),
                ExamSchedule("2026-2027-1", "synthetic", "synthetic", "fresh", "Synthetic exams / 合成考试示例",
                    listOf(ExamArrangement("one", "Synthetic exam / 合成考试示例", "2026-12-21", "10:07", "11:43",
                        "Synthetic room / 合成教室", "23", "2026-12-21 10:07–11:43"),
                        ExamArrangement("two", "Long exam title / 人工智能与复杂系统建模方法综合考试", "2026-12-22",
                            "", "", "Synthetic room B / 合成教室 B")))))
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                scenario.onActivity { activity -> activity.findViewById<View>(R.id.navigation_query).performClick() }
                settled(scenario)
                scenario.onActivity { activity ->
                    val original = activity.findViewById<View>(R.id.information_query_page)
                    val owner = original.parent as ViewGroup
                    val params = original.layoutParams
                    owner.removeView(original)
                    owner.addView(InformationQueryPage(activity, fixture.shuttles, fixture.events, preferences,
                        (owner.width / activity.resources.displayMetrics.density).toInt(),
                        InformationQuerySessionState(InformationQueryMode.GRADES.name),
                        activity.findViewById<View?>(R.id.phone_navigation) != null, grades, fixture.schedules).build(), params)
                }
                settled(scenario)
                block(scenario, fixture)
            }
        } finally { fixture.close(); preferences.languageCode = oldLanguage }
    }

    private fun gradeFixture(term: String, type: String) = AcademicGrades(term, type, "synthetic", "3.50", listOf(
        AcademicGrade("long", "Synthetic long course / 面向复杂工程问题的人工智能系统建模与实践", "0", "0", "DEMO-0",
            "Synthetic course metadata / 合成课程信息", "必修", "正常考试", "2026-2027-1", "已公布"),
        AcademicGrade("text", "Text / 文字", "通过 / Pass", "2", null, null, null, null),
        AcademicGrade("missing", "Not published / 尚未公布", null, null, null, null, null, null),
    ) + (1..12).map { AcademicGrade("extra-$it", "Synthetic course $it / 合成课程 $it", "92", "3", null, null, null, null) })

    private fun settled(scenario: ActivityScenario<MainActivity>) {
        instrumentation.waitForIdleSync()
        val drawn = CountDownLatch(1)
        scenario.onActivity { activity -> activity.window.decorView.postOnAnimation {
            activity.window.decorView.postOnAnimation { drawn.countDown() }
        } }
        assertTrue(drawn.await(5, TimeUnit.SECONDS))
        UiDevice.getInstance(instrumentation).waitForIdle()
    }

    private fun capture(mode: String) {
        val config = context.resources.configuration
        val stage = InstrumentationRegistry.getArguments().getString("queryStage", "phone")
            .replace(Regex("[^a-zA-Z0-9_-]"), "")
        val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "query-content-stability")
            .apply { mkdirs() }
        assertTrue(UiDevice.getInstance(instrumentation).takeScreenshot(File(directory,
            "$stage-${AppPreferences(context).languageCode}-${config.screenWidthDp}-$mode.png")))
    }

    private fun assertTextFits(label: TextView) {
        val layout = checkNotNull(label.layout) { "Unmeasured label: ${label.text}" }
        val width = label.width - label.compoundPaddingLeft - label.compoundPaddingRight
        val height = label.height - label.compoundPaddingTop - label.compoundPaddingBottom
        assertTrue("Text height must fit: ${label.text}", layout.height <= height + 1)
        repeat(layout.lineCount) { line ->
            assertEquals("No truncation: ${label.text}", 0, layout.getEllipsisCount(line))
            // getLineWidth includes the invisible trailing space at a wrap.
            assertTrue("Text width must fit: ${label.text}", layout.getLineMax(line) <= width + 1)
        }
    }

    private fun text(view: View) = descendants(view).filterIsInstance<TextView>().joinToString(" ") { it.text }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
