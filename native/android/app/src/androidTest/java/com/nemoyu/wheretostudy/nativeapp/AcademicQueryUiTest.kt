package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class AcademicQueryUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    @Before fun privacy() = ensurePrivacyConsentForUiTest()

    @Test fun gradesAreReadableInBothLanguagesWithThreeQuerySegments() {
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        try {
            listOf("zh-Hans", "en").forEach { language ->
                preferences.languageCode = language
                val grades = AcademicGradesRepository({ Credentials("synthetic-only", "synthetic-only") },
                    { AcademicTerms("2026-2027-1", listOf(AcademicTerm("2026-2027-1", "2026-2027-1"))) },
                    { _, term, type -> fixture(term, type) })
                val shuttles = ShuttleBusRepository(usesSampleData = true)
                val events = CalendarDailyInfoRepository(usesSampleData = true)
                try {
                    ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                        .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                        scenario.onActivity { activity ->
                            activity.findViewById<View>(R.id.navigation_query).performClick()
                        }
                        instrumentation.waitForIdleSync()
                        scenario.onActivity { activity ->
                            val original = activity.findViewById<View>(R.id.information_query_page)
                            val parent = original.parent as ViewGroup
                            val params = original.layoutParams
                            parent.removeView(original)
                            parent.addView(InformationQueryPage(activity, shuttles, events, AppPreferences(activity),
                                (parent.width / activity.resources.displayMetrics.density).toInt(),
                                InformationQuerySessionState(InformationQueryMode.GRADES.name),
                                activity.findViewById<View?>(R.id.phone_navigation) != null, grades).build(), params)
                        }
                        val device = UiDevice.getInstance(instrumentation)
                        assertTrue(device.wait(Until.hasObject(By.text("Synthetic grades / 合成成绩示例")), 5_000))
                        instrumentation.waitForIdleSync()
                        scenario.onActivity { activity ->
                            val selector = activity.findViewById<ViewGroup>(R.id.information_query_mode_switch)
                            assertTrue("Three segments must remain a compact control", selector.height <= activity.dp(100))
                            assertEquals(3, (selector.getChildAt(1) as ViewGroup).childCount)
                            descendants(selector).filterIsInstance<TextView>().forEach { label ->
                                assertTrue("Query labels must not be clipped", label.layout.height <= label.height - label.compoundPaddingTop - label.compoundPaddingBottom)
                            }
                            val rows = descendants(activity.findViewById(R.id.information_query_grades_scroll))
                                .filter { it.tag == "academic.grade.row" }
                            assertEquals(3, rows.size)
                            assertTrue(descendants(rows[0]).filterIsInstance<TextView>().any { it.text.contains("0") })
                            val thumb = activity.findViewById<View>(R.id.information_query_mode_thumb)
                            assertTrue(thumb.right + thumb.translationX <= selector.width - selector.paddingRight + 1)
                        }
                        val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "academic-query").apply { mkdirs() }
                        assertTrue(device.takeScreenshot(File(directory, "$language-${context.resources.configuration.screenWidthDp}.png")))
                    }
                } finally { grades.close(); shuttles.close(); events.close() }
            }
        } finally { preferences.languageCode = previousLanguage }
    }

    @Test fun changedPasswordRejectsLatePrivateGradesAndClearsMemory() {
        val credentials = AtomicReference(Credentials("synthetic-account", "first-password"))
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val completed = CountDownLatch(1)
        val repository = AcademicGradesRepository(credentials::get,
            { AcademicTerms("2026-2027-1", listOf(AcademicTerm("2026-2027-1", "Synthetic term"))) },
            { _, term, type -> entered.countDown(); release.await(5, TimeUnit.SECONDS); fixture(term, type) })
        try {
            instrumentation.runOnMainSync { repository.load() }
            assertTrue(entered.await(3, TimeUnit.SECONDS))
            instrumentation.runOnMainSync {
                credentials.set(Credentials("synthetic-account", "changed-password"))
                repository.reconcile()
                repository.addObserver { if (!repository.isLoading) completed.countDown() }
            }
            release.countDown()
            assertTrue(completed.await(3, TimeUnit.SECONDS))
            instrumentation.runOnMainSync { assertNull(repository.snapshot); assertNull(repository.terms) }
        } finally { release.countDown(); repository.close() }
    }

    @Test fun exactExamTimeRendersWithoutTheConflictingCourse() {
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
            scenario.onActivity { activity ->
                val day = AcademicScheduleLogic.parseDate("2026-09-07")!!
                val regular = Course("conflicting", "Hidden synthetic course", "", "", "1", listOf(1), emptyList(),
                    1, 2, 3, "3-4", "09:50-11:25")
                val exam = ExamArrangement("synthetic", "Synthetic exam / 合成考试示例", "2026-09-07", "10:07", "11:43", "Synthetic room")
                val schedule = ScheduleSnapshot("2026-2027-1", "2026-09-07", "synthetic", listOf(regular),
                    ExamSchedule("2026-2027-1", "synthetic", "synthetic", "fresh", "", listOf(exam)))
                val courses = ScheduleLogic.courses(schedule, day)
                assertEquals(1, courses.size)
                assertEquals("10:07-11:43", courses.single().timeRange)
                val body = ScrollView(activity).apply {
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(TextView(activity).apply {
                            text = "Synthetic exam fixture / 合成考试示例"; textSize = 18f
                            setPadding(activity.dp(16), activity.dp(16), activity.dp(16), activity.dp(16))
                        })
                        addView(CalendarTimelineView(activity, listOf(TimelineDay(day, courses, emptyList())), day, compact = true))
                    })
                }
                android.app.Dialog(activity).apply {
                    setContentView(body)
                    show()
                    window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                }
            }
            instrumentation.waitForIdleSync()
            assertTrue(UiDevice.getInstance(instrumentation).wait(
                Until.hasObject(By.text("Synthetic exam fixture / 合成考试示例")), 5_000))
            val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "academic-query").apply { mkdirs() }
            assertTrue(UiDevice.getInstance(instrumentation).takeScreenshot(File(directory,
                "exam-${context.resources.configuration.screenWidthDp}.png")))
        }
    }

    private fun fixture(term: String, type: String) = AcademicGrades(term, type, "synthetic", "3.50", listOf(
        AcademicGrade("zero", "Synthetic grades / 合成成绩示例", "0", "0", "DEMO-0", "Synthetic data", null, null),
        AcademicGrade("text", "Text result / 文字成绩示例", "通过 / Pass", "2", "DEMO-1", null, null, null),
        AcademicGrade("missing", "Not published / 尚未公布示例", null, null, null, null, null, null),
    ))
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
