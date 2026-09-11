package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.graphics.Rect
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** Uses fictional credentials on a disposable emulator with network disabled. */
@RunWith(AndroidJUnit4::class)
class CourseDeletionAndCloudPasswordUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val device get() = UiDevice.getInstance(instrumentation)
    private val today = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
    private val snapshot: ScheduleSnapshot get() {
        val weekday = ((today.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        val monday = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1 - weekday) }
        val course = Course("fixture-a", "Course deletion fixture", "Demo teacher", "Demo room", "1-2",
            listOf(1, 2), emptyList(), weekday, 0, 1, "1-2节", "08:00-09:35", "fixture-source")
        return ScheduleSnapshot("2026-2027-1", SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
            .apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }.format(monday.time), "ui-fixture",
            listOf(course, course.copy(id = "fixture-b", weekday = weekday % 7 + 1),
                course.copy(id = "fixture-other", name = "Unrelated fixture", sourceCourseID = "other-source", startSlot = 3, endSlot = 4)))
    }

    private fun prepare(language: AppLanguage) {
        ensurePrivacyConsentForUiTest()
        DailyClassroomRefreshScheduler.cancel(context)
        DailyCourseSummaryScheduler.revoke(context)
        CourseDeletionStore(context).clear()
        AppPreferences(context).apply {
            clear()
            languageCode = language.code
            automaticTermDetectionEnabled = false
            termID = snapshot.termID
            termStartDate = snapshot.termStartDate
        }
        SecureCredentialStore(context).save(Credentials("course-cloud-test-only", "fictional-academic", "fictional-cloud"))
        ScheduleStore(context).save(snapshot)
    }

    private fun launch() = ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
        .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true))

    @Test
    fun persistentRulesRecoverAfterRestartStayAccountScopedAndDoNotReportFailedWritesAsSuccess() {
        prepare(AppLanguage.SIMPLIFIED_CHINESE)
        val store = CourseDeletionStore(context)
        store.save(emptyList())
        val repository = ScheduleRepository(context, SecureCredentialStore(context), AppPreferences(context))
        try {
            assertTrue(context.filesDir.setWritable(false, true))
            try {
                assertThrows(Exception::class.java) {
                    repository.deleteCourse(snapshot.courses.first(), today, CourseDeletionScope.SINGLE_OCCURRENCE, snapshot.termID)
                }
            } finally {
                assertTrue(context.filesDir.setWritable(true, true))
            }
            assertEquals(snapshot, repository.schedule)
            assertTrue(store.load().isEmpty())
            repository.deleteCourse(snapshot.courses.first(), today, CourseDeletionScope.SINGLE_OCCURRENCE, snapshot.termID)
            val effective = repository.schedule
            assertNotEquals(snapshot, effective)
            val reloaded = ScheduleRepository(context, SecureCredentialStore(context), AppPreferences(context))
            try { assertEquals(effective, reloaded.schedule) } finally { reloaded.close() }
            SecureCredentialStore(context).save(Credentials("another-fictional-account", "fictional"))
            assertEquals(snapshot, loadUsableSchedule(context))
            SecureCredentialStore(context).save(Credentials("course-cloud-test-only", "fictional"))
            assertEquals(effective, loadUsableSchedule(context))
            val committed = File(context.filesDir, "course_deletions_v1.json")
            assertTrue(committed.renameTo(File(committed.path + ".bak")))
            assertEquals(1, store.load().size)
            repository.clearLocalDataCoordinated(clearCourseDeletions = false)
            assertEquals(1, store.load().size)
            repository.clearLocalDataCoordinated()
            assertTrue(store.load().isEmpty())
        } finally {
            context.filesDir.setWritable(true, true)
            repository.close()
        }
    }

    @Test
    fun bothDeletionScopesAndSettingsRestorationWorkInBothLanguages() {
        listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
            prepare(language)
            launch().use { scenario ->
                openCourseDetails(scenario)
                screenshot("${language.code}-course-details")
                clickLocalized(scenario, "仅删除这一次")
                assertTrue(device.wait(Until.hasObject(By.res("android", "button1")), 5_000))
                screenshot("${language.code}-single-confirm")
                clickLocalized(scenario, "删除")
                instrumentation.waitForIdleSync()
                val single = checkNotNull(loadUsableSchedule(context))
                assertEquals(listOf("Unrelated fixture"), ScheduleLogic.courses(single, today).map { it.name })
                val nextWeek = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 7) }
                assertTrue(ScheduleLogic.courses(single, nextWeek).any { it.sourceCourseID == "fixture-source" })
                assertEquals(snapshot, ScheduleStore(context).load())
                restoreUsingSettings(scenario, "${language.code}-single-recovery")
                assertEquals(snapshot, loadUsableSchedule(context))

                openCourseDetails(scenario)
                clickLocalized(scenario, "删除本学期整门课程")
                assertTrue(device.wait(Until.hasObject(By.res("android", "button1")), 5_000))
                screenshot("${language.code}-whole-confirm")
                clickLocalized(scenario, "删除")
                instrumentation.waitForIdleSync()
                assertTrue(checkNotNull(loadUsableSchedule(context)).courses.none { it.sourceCourseID == "fixture-source" })
                assertEquals(snapshot, ScheduleStore(context).load())
                restoreUsingSettings(scenario, "${language.code}-whole-recovery")
                assertEquals(snapshot, loadUsableSchedule(context))
                scenario.onActivity { activity -> activity.findViewById<View>(R.id.navigation_calendar).performClick() }
                screenshot("${language.code}-restored-calendar")
            }
        }
    }

    @Test
    fun cloudSecretFieldsStayBlankRetainEditsAndSupportExplicitAcademicFallback() {
        listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
            prepare(language)
            launch().use { scenario ->
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.navigation_settings).performClick()
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    assertEquals("", field(activity, "教务密码").text.toString())
                    assertEquals("", field(activity, "教学云平台密码（可选）").text.toString())
                    assertFalse(field(activity, "教学云平台密码（可选）").isSaveEnabled)
                }
                screenshot("${language.code}-cloud-saved")
                scenario.onActivity { activity ->
                    field(activity, "教学云平台密码（可选）").setText("fictional-cloud-replacement")
                    button(activity, "保存设置").performClick()
                }
                assertEquals("fictional-cloud-replacement", SecureCredentialStore(context).load()?.teachingCloudPassword)
                scenario.onActivity { activity ->
                    assertEquals("", field(activity, "教学云平台密码（可选）").text.toString())
                    button(activity, "保存设置").performClick()
                }
                assertEquals("fictional-cloud-replacement", SecureCredentialStore(context).load()?.teachingCloudPassword)
                scenario.onActivity { activity ->
                    button(activity, "使用教务密码").performClick()
                }
                screenshot("${language.code}-cloud-fallback-pending")
                scenario.onActivity { activity -> button(activity, "保存设置").performClick() }
                val fallback = checkNotNull(SecureCredentialStore(context).load())
                assertNull(fallback.teachingCloudPassword)
                assertEquals("fictional-academic", fallback.effectiveTeachingCloudPassword)
                scenario.onActivity { activity ->
                    field(activity, "教学云平台密码（可选）").setText("fictional-cloud-other")
                    button(activity, "保存设置").performClick()
                    field(activity, "教务账号").setText("another-fictional-account")
                    field(activity, "教务密码").setText("another-fictional-academic")
                    button(activity, "保存设置").performClick()
                }
                assertNull(SecureCredentialStore(context).load()?.teachingCloudPassword)
                val stored = context.getSharedPreferences("secure_credentials_v1", 0).all.values.joinToString()
                assertFalse(stored.contains("fictional"))
            }
        }
    }

    private fun openCourseDetails(scenario: ActivityScenario<MainActivity>) {
        scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_calendar).performClick()
            activity.findViewById<View>(R.id.calendar_mode_day).performClick()
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        instrumentation.waitForIdleSync()
        scenario.onActivity { activity ->
            val area = activity.findViewById<ViewGroup>(R.id.calendar_day_week_course_area)
            assertEquals(2, area.childCount)
            area.getChildAt(0).performClick()
        }
        assertTrue(device.wait(Until.hasObject(By.textContains("Course deletion fixture")), 5_000))
    }

    private fun restoreUsingSettings(scenario: ActivityScenario<MainActivity>, capture: String) {
        scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_settings).performClick()
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            val control = button(activity, "管理已删除课程")
            val page = activity.findViewById<ScrollView>(R.id.page_settings)
            val bounds = Rect().also(control::getDrawingRect)
            (page.getChildAt(0) as ViewGroup).offsetDescendantRectToMyCoords(control, bounds)
            page.scrollTo(0, bounds.top.coerceAtLeast(0))
            control.performClick()
        }
        screenshot(capture)
        checkNotNull(device.wait(Until.findObject(By.textStartsWith("Course deletion fixture")), 5_000)).click()
        clickLocalized(scenario, "恢复")
        instrumentation.waitForIdleSync()
        assertTrue(CourseDeletionStore(context).load().isEmpty())
    }

    private fun clickLocalized(scenario: ActivityScenario<MainActivity>, label: String) {
        var localized = label
        scenario.onActivity { localized = it.uiText(label) }
        val labelPattern = java.util.regex.Pattern.compile(java.util.regex.Pattern.quote(localized), java.util.regex.Pattern.CASE_INSENSITIVE)
        checkNotNull(device.wait(Until.findObject(By.text(labelPattern)), 5_000)).click()
        device.waitForIdle()
    }

    private fun field(activity: MainActivity, hint: String) = descendants(activity.window.decorView)
        .filterIsInstance<EditText>().first { it.hint.toString() == activity.uiText(hint) }

    private fun button(activity: MainActivity, label: String) = descendants(activity.window.decorView)
        .filterIsInstance<TextView>().first { it.isClickable && it.text.toString() == activity.uiText(label) }

    private fun screenshot(name: String) {
        instrumentation.waitForIdleSync()
        android.os.SystemClock.sleep(2_200)
        device.waitForIdle()
        val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "course-cloud-ui").apply { mkdirs() }
        assertTrue(device.takeScreenshot(File(directory, "$name.png")))
    }

    private fun descendants(root: View): List<View> = buildList {
        add(root)
        if (root is ViewGroup) repeat(root.childCount) { addAll(descendants(root.getChildAt(it))) }
    }
}
