package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit offline QA only. Synthetic business DTOs; no credential or auth-window action. */
@RunWith(AndroidJUnit4::class)
class IsolatedQmCourseLayoutUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun independentCardsAndOtherTermSwitchRetainExpandedLocalCourseState() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wtsIsolatedQa") == "true")
        assertTrue(BuildConfig.DEBUG)
        val qaPackage = "com.nemoyu.wheretostudy.nativeapp.codexqa20261007gate"
        assertEquals(qaPackage, context.packageName)
        assertEquals("$qaPackage.test", instrumentation.context.packageName)
        for (packageName in listOf(qaPackage, "$qaPackage.test")) {
            assertEquals(PackageManager.PERMISSION_DENIED,
                context.packageManager.checkPermission(Manifest.permission.INTERNET, packageName))
        }
        ensurePrivacyConsentForUiTest()
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        preferences.languageCode = AppLanguage.ENGLISH.code
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                lateinit var repository: QmplusRepository
                val restored = CountDownLatch(1); val observer = Any()
                scenario.onActivity { activity ->
                    repository = activity.qmplusState()
                    repository.addObserver(observer) { if (!repository.isLoading) restored.countDown() }
                    if (!repository.isLoading) restored.countDown()
                }
                assertTrue(restored.await(5, TimeUnit.SECONDS))
                val raw = "Opened: Friday, 9 October 2026, 10:00 AM Due: Friday, 9 October 2026, 12:00 PM"
                val course = QmplusCourse("1", "EBU1000 Synthetic current", null,
                    "https://qmplus.qmul.ac.uk/course/view.php?id=1", null, null, "current")
                val snapshot = QmplusSnapshot("2026-10-07T00:00:00Z", listOf(course,
                    course.copy(id = "2", name = "EBU2000 Synthetic unknown", currentTermStatus = "unknown",
                        url = "https://qmplus.qmul.ac.uk/course/view.php?id=2"),
                    course.copy(id = "3", name = "EBU3000 Synthetic other", currentTermStatus = "other",
                        url = "https://qmplus.qmul.ac.uk/course/view.php?id=3")), listOf(
                    QmplusActivityItem("101", "1", "HW1 synthetic", "assignment",
                        "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=101", "2026-10-09T10:00:00Z",
                        null, null, null, null, "Submitted for grading", "available", raw),
                    QmplusActivityItem("102", "1", "HW2 synthetic", "assignment",
                        "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=102", null,
                        null, null, null, null, "Not submitted", "available", null)), emptyList())
                scenario.onActivity { activity ->
                    repository.removeObserver(observer)
                    // UI-only injection cannot launch a warm owner or touch persistent credentials/profile.
                    field(repository, "warmRefreshStarted", true)
                    field(repository, "isFeatureEnabled", true)
                    field(repository, "snapshot", snapshot)
                    val daily = retained(activity).dailyInfo
                    field(daily, "assignmentClient", null)
                    field(daily, "queryCourseItems", listOf(TeachingCloudCourse("cloud", "Synthetic cloud course", null)))
                    field(daily, "queryAssignmentItems", listOf(
                        AssignmentDeadlineItem("c1", "Cloud HW1 synthetic", "Synthetic cloud course", "2026-10-09 10:00:00", "未提交", "cloud"),
                        AssignmentDeadlineItem("c2", "Cloud HW2 synthetic", "Synthetic cloud course", "2026-10-10 10:00:00", "已提交", "cloud")))
                    courseSession(activity).apply {
                        selectedMode = InformationQueryMode.COURSES
                        automaticCourseLoadAttempted = true
                        showsOtherQmCourses = false
                        expandedCourseKeys.clear(); inlineCourseCounts.clear()
                    }
                    activity.findViewById<View>(R.id.navigation_courses).performClick()
                    assertEquals(2, activity.findViewById<LinearLayout>(R.id.course_qmplus_list).childCount)
                    for (key in listOf("teaching-cloud.course.cloud", "qmplus.course.1")) {
                        activity.window.decorView.findViewWithTag<View>("$key.disclosure.header").performClick()
                    }
                }
                awaitFrame(scenario) { activity ->
                    listOf("teaching-cloud.course.cloud", "qmplus.course.1").all { key ->
                        val body = activity.window.decorView.findViewWithTag<LinearLayout?>("$key.assignments")
                        body != null && body.isShown && body.childCount == 2 && body.getChildAt(0).height > 0 &&
                            body.getChildAt(1).top - body.getChildAt(0).bottom == activity.dp(10)
                    }
                }
                lateinit var overview: ScrollView
                var scrollY = 0
                scenario.onActivity { activity ->
                    fun assertGap(key: String) {
                        val body = activity.window.decorView.findViewWithTag<LinearLayout>("$key.assignments")
                        assertEquals(0, (body.getChildAt(0).layoutParams as LinearLayout.LayoutParams).topMargin)
                        assertEquals(activity.dp(10), (body.getChildAt(1).layoutParams as LinearLayout.LayoutParams).topMargin)
                        assertEquals(activity.dp(10), body.getChildAt(1).top - body.getChildAt(0).bottom)
                    }
                    assertGap("teaching-cloud.course.cloud"); assertGap("qmplus.course.1")
                    val body = activity.window.decorView.findViewWithTag<LinearLayout>("qmplus.course.1.assignments")
                    val first = body.getChildAt(0) as ViewGroup
                    val caption = first.getChildAt(1) as TextView
                    assertTrue(caption.text.toString().startsWith("Assignment · "))
                    assertTrue(caption.text.toString().contains("2026-10-09 18:00"))
                    assertTrue(caption.text.toString().endsWith("Submitted for grading"))
                    assertEquals(Int.MAX_VALUE, caption.maxLines)
                    assertTrue(descendants(first).filterIsInstance<TextView>().any { it.text.toString() == raw })
                    val toggle = activity.findViewById<Switch>(R.id.course_qmplus_other_terms)
                    assertEquals(activity.uiText("显示其他学期／历史课程"), toggle.text.toString())
                    assertFalse(toggle.isChecked)
                    assertNotNull(toggle.trackTintList); assertNotNull(toggle.thumbTintList)
                    val parent = toggle.parent as ViewGroup
                    assertTrue(parent.indexOfChild(toggle) < parent.indexOfChild(activity.findViewById(R.id.course_qmplus_list)))
                    overview = activity.findViewById(R.id.course_current_scroll)
                    overview.scrollTo(0, activity.dp(37)); scrollY = overview.scrollY
                    courseSession(activity).inlineCourseCounts["qmplus.course.1"] = 40
                    courseSession(activity).visibleQmplusRowCount = 40
                    toggle.performClick() // CompoundButton's handled return does not describe checked state.
                }
                awaitFrame(scenario) { activity -> activity.findViewById<LinearLayout>(R.id.course_qmplus_list).childCount == 3 &&
                    activity.window.decorView.findViewWithTag<LinearLayout>("qmplus.course.1.assignments").childCount == 2 }
                scenario.onActivity { activity ->
                    val session = courseSession(activity)
                    assertTrue(activity.findViewById<Switch>(R.id.course_qmplus_other_terms).isChecked)
                    assertTrue(session.expandedCourseKeys.containsAll(listOf("qmplus.course.1", "teaching-cloud.course.cloud")))
                    assertEquals(40, session.inlineCourseCounts["qmplus.course.1"])
                    assertEquals(40, session.visibleQmplusRowCount)
                    assertSame(overview, activity.findViewById(R.id.course_current_scroll))
                    assertEquals(scrollY, overview.scrollY)
                    assertSame(snapshot, repository.snapshot); assertNull(repository.connection)
                    activity.findViewById<Switch>(R.id.course_qmplus_other_terms).performClick()
                }
                awaitFrame(scenario) { it.findViewById<LinearLayout>(R.id.course_qmplus_list).childCount == 2 }
                scenario.onActivity { activity ->
                    assertFalse(activity.findViewById<Switch>(R.id.course_qmplus_other_terms).isChecked)
                    assertTrue(activity.window.decorView.findViewWithTag<LinearLayout>("qmplus.course.1.assignments").isShown)
                    assertEquals(2, activity.findViewById<LinearLayout>(R.id.course_qmplus_list).childCount) // Includes unknown, hides only other.
                    assertEquals(40, courseSession(activity).visibleQmplusRowCount)
                    assertSame(snapshot, repository.snapshot); assertNull(repository.connection)
                }
            }
        } finally { preferences.languageCode = previousLanguage }
    }

    private fun field(owner: Any, name: String, value: Any?) = owner.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(owner, value)
    private fun retained(activity: MainActivity) = MainActivity::class.java.getDeclaredMethod("getActivitySession")
        .apply { isAccessible = true }.invoke(activity) as ActivitySessionState
    private fun courseSession(activity: MainActivity) = MainActivity::class.java.getDeclaredField("courseSessionState")
        .apply { isAccessible = true }.get(activity) as InformationQuerySessionState
    private fun descendants(root: View): Sequence<View> = sequence {
        yield(root)
        if (root is ViewGroup) repeat(root.childCount) { yieldAll(descendants(root.getChildAt(it))) }
    }
    private fun awaitFrame(scenario: ActivityScenario<MainActivity>, condition: (MainActivity) -> Boolean) {
        val done = CountDownLatch(1); val deadline = SystemClock.elapsedRealtime() + 5_000
        var matched = false
        lateinit var root: View; lateinit var pulse: Runnable
        scenario.onActivity { activity ->
            root = activity.window.decorView
            pulse = Runnable {
                if (condition(activity)) { matched = true; done.countDown() }
                else if (SystemClock.elapsedRealtime() >= deadline) done.countDown()
                else root.postOnAnimation(pulse)
            }
            root.postOnAnimation(pulse)
        }
        val finished = done.await(6, TimeUnit.SECONDS)
        scenario.onActivity { root.removeCallbacks(pulse) }
        assertTrue("Synthetic layout did not reach its bounded stable frame", finished && matched)
    }
}
