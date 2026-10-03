package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Switch
import android.view.inputmethod.InputMethodManager
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Only synthetic credentials and injected transport; run on the isolated UI-test emulator. */
@RunWith(AndroidJUnit4::class)
class LateQueryPublicationUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private enum class Source { SETTINGS_SAVE, SETTINGS_REFRESH, STARTUP, EXAMS, CLASSROOMS }

    @Before fun privacy() = ensurePrivacyConsentForUiTest()

    @Test fun lateScheduleSuccessFromEveryEntryPreservesTheUnrelatedQueryBody() {
        Source.entries.filter { it != Source.CLASSROOMS }.forEach { source ->
            delayedRequest(source, fails = false) { scenario, request ->
                lateinit var shell: QueryShell
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.navigation_query).performClick()
                    activity.findViewById<View>(R.id.information_query_grades_tab).performClick()
                    shell = QueryShell(activity, R.id.information_query_grades_scroll)
                }
                request.finish(scenario)
                scenario.onActivity { activity ->
                    shell.assertUnchanged(activity, R.id.information_query_grades_scroll)
                    assertSame("$source must not replace Grades with a schedule publication", shell.body,
                        activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0))
                }
            }
        }
    }

    @Test fun failedScheduleCompletionFromEveryEntryReenablesTheCurrentExamControl() {
        Source.entries.filter { it != Source.CLASSROOMS }.forEach { source ->
            delayedRequest(source, fails = true) { scenario, request ->
                lateinit var shell: QueryShell
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.navigation_query).performClick()
                    activity.findViewById<View>(R.id.information_query_exams_tab).performClick()
                    shell = QueryShell(activity, R.id.information_query_exams_scroll)
                    assertFalse("$source is still in flight", activity.findViewById<View>(R.id.information_query_exams_refresh).isEnabled)
                }
                request.finish(scenario)
                // A completion during the 220ms incoming mode transition is
                // published only after its end-action. Wait for that actual
                // body publication rather than assuming two frames settle it.
                val publicationDeadline = android.os.SystemClock.elapsedRealtime() + 5_000
                var published = false
                while (!published && android.os.SystemClock.elapsedRealtime() < publicationDeadline) {
                    scenario.onActivity { activity ->
                        published = activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0) !== shell.body
                    }
                    if (!published) android.os.SystemClock.sleep(10)
                }
                assertTrue("$source must publish its completed exam state after the mode transition", published)
                scenario.onActivity { activity ->
                    shell.assertUnchanged(activity, R.id.information_query_exams_scroll)
                    val refresh = activity.findViewById<TextView>(R.id.information_query_exams_refresh)
                    assertTrue("$source failure must finish the exam loading state", refresh.isEnabled)
                    assertEquals(activity.uiText("刷新课表与考试"), refresh.text.toString())
                    assertNotSame("Only exam content updates after failure", shell.body,
                        activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0))
                }
            }
        }
    }

    @Test fun lateClassroomSuccessKeepsTheCurrentQueryShellAndBody() =
        delayedRequest(Source.CLASSROOMS, fails = false) { scenario, request ->
            lateinit var shell: QueryShell
            scenario.onActivity { activity ->
                activity.findViewById<View>(R.id.navigation_query).performClick()
                activity.findViewById<View>(R.id.information_query_exams_tab).performClick()
                shell = QueryShell(activity, R.id.information_query_exams_scroll)
            }
            request.finish(scenario)
            scenario.onActivity { activity ->
                shell.assertUnchanged(activity, R.id.information_query_exams_scroll)
                assertSame("Classrooms are not a source for exam content", shell.body,
                    activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0))
            }
        }

    @Test fun lateScheduleSuccessFromEveryEntryPreservesSettingsDraftFocusAndScroll() {
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        try {
            listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
                preferences.languageCode = language.code
                Source.entries.filter { it != Source.CLASSROOMS }.forEach { source ->
                    delayedRequest(source, fails = false) { scenario, request ->
                        lateinit var settings: View
                        lateinit var account: EditText
                        lateinit var password: EditText
                        lateinit var cloudPassword: EditText
                        lateinit var scroll: ScrollView
                        var oldScrollY = 0
                        scenario.onActivity { activity ->
                            activity.findViewById<View>(R.id.navigation_settings).performClick()
                            settings = activity.findViewById(R.id.page_settings)
                            scroll = settings as ScrollView
                            val fields = descendants(settings).filterIsInstance<EditText>()
                            account = fields.first { it.hint.toString() == activity.uiText("教务账号") }
                            password = fields.first { it.hint.toString() == activity.uiText("教务密码") }
                            cloudPassword = fields.first { it.hint.toString() == activity.uiText("教学云平台密码（可选）") }
                            account.setText("unsaved-draft-only")
                            password.setText("synthetic-unsaved-password")
                            cloudPassword.setText("synthetic-unsaved-cloud-password")
                            assertTrue(account.requestFocus())
                            account.setSelection(3)
                            (activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                                .showSoftInput(account, InputMethodManager.SHOW_IMPLICIT)
                        }
                        instrumentation.waitForIdleSync()
                        scenario.onActivity { activity -> scroll.scrollTo(0, activity.dp(80)); oldScrollY = scroll.scrollY }
                        request.finish(scenario)
                        scenario.onActivity { activity ->
                            assertSame("$source must not reconstruct Settings", settings,
                                activity.findViewById(R.id.page_settings))
                            assertEquals("unsaved-draft-only", account.text.toString())
                            assertEquals("synthetic-unsaved-password", password.text.toString())
                            assertEquals("synthetic-unsaved-cloud-password", cloudPassword.text.toString())
                            assertTrue("The draft editor keeps keyboard focus", account.hasFocus())
                            assertEquals(3, account.selectionStart)
                            assertEquals(oldScrollY, scroll.scrollY)
                            assertTrue((activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as InputMethodManager).isActive(account))
                            val school = repository<ScheduleRepository>(activity, "getScheduleRepository").schedule!!
                            assertEquals(school.termID, AppPreferences(activity).termID)
                            assertEquals(school.termStartDate, AppPreferences(activity).termStartDate)
                            val automaticTerm = descendants(settings).filterIsInstance<EditText>().first {
                                it.hint.toString() == activity.uiText("学期编号")
                            }
                            assertEquals(school.termID, automaticTerm.text.toString())
                            val manual = descendants(settings).filterIsInstance<Switch>().first {
                                it.text.toString() == activity.uiText("自动检测当前学期")
                            }
                            val manualStart = descendants(settings).filterIsInstance<EditText>().first {
                                it.hint.toString() == activity.uiText("第一周周一（YYYY-MM-DD）")
                            }
                            manual.isChecked = false
                            automaticTerm.setText("2030-2031-1")
                            manualStart.setText("2030-08-26")
                            activity.personalScheduleWasEdited()
                            assertSame(settings, activity.findViewById(R.id.page_settings))
                            assertEquals("synthetic-unsaved-password", password.text.toString())
                            assertTrue(account.hasFocus())
                            assertFalse(manual.isChecked)
                            assertEquals("2030-2031-1", automaticTerm.text.toString())
                            assertEquals("2030-08-26", manualStart.text.toString())
                            assertEquals(school.termID, AppPreferences(activity).termID)
                        }
                    }
                }
            }
        } finally { preferences.languageCode = previousLanguage }
    }

    @Test fun returningToSettingsDuringARefreshKeepsTheCurrentControlAndDraftAfterEitherResult() {
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        try {
            listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
                preferences.languageCode = language.code
                listOf(false, true).forEach { fails ->
                    delayedRequest(Source.SETTINGS_REFRESH, fails) { scenario, request ->
                        lateinit var settings: View
                        lateinit var refresh: TextView
                        lateinit var account: EditText
                        lateinit var password: EditText
                        scenario.onActivity { activity ->
                            activity.findViewById<View>(R.id.navigation_query).performClick()
                            activity.findViewById<View>(R.id.navigation_settings).performClick()
                            settings = activity.findViewById(R.id.page_settings)
                            val loading = activity.uiText("正在获取…")
                            val ready = activity.uiText("获取/刷新个人课表")
                            refresh = descendants(settings).filterIsInstance<TextView>().single {
                                it.isClickable && it.text.toString() in setOf(loading, ready)
                            }
                            assertEquals("A new Settings owner must show the in-flight request", loading, refresh.text.toString())
                            assertFalse(refresh.isEnabled)
                            val fields = descendants(settings).filterIsInstance<EditText>()
                            account = fields.first { it.hint.toString() == activity.uiText("教务账号") }
                            password = fields.first { it.hint.toString() == activity.uiText("教务密码") }
                            val persisted = SecureCredentialStore(activity).load()
                            account.setText("unsaved-return-draft")
                            password.setText("synthetic-return-password")
                            assertTrue(account.requestFocus())
                            refresh.performClick()
                            assertEquals("A duplicate busy click must not save drafts", persisted, SecureCredentialStore(activity).load())
                            assertEquals("synthetic-return-password", password.text.toString())
                        }
                        request.finish(scenario)
                        scenario.onActivity { activity ->
                            assertSame(settings, activity.findViewById(R.id.page_settings))
                            assertTrue("Both results must finish the current Settings loading control", refresh.isEnabled)
                            assertEquals(activity.uiText("获取/刷新个人课表"), refresh.text.toString())
                            assertEquals("unsaved-return-draft", account.text.toString())
                            assertEquals("synthetic-return-password", password.text.toString())
                            assertTrue(account.hasFocus())
                        }
                    }
                }
            }
        } finally { preferences.languageCode = previousLanguage }
    }

    private class QueryShell(activity: MainActivity, scrollID: Int) {
        val page = activity.findViewById<ViewGroup>(R.id.information_query_page)
        val header = page.findViewWithTag<View>("information.query.header")
        val selector = activity.findViewById<View>(R.id.information_query_mode_switch)
        val scroll = activity.findViewById<ScrollView>(scrollID)
        val body = activity.findViewById<FrameLayout>(R.id.information_query_content).getChildAt(0)
        fun assertUnchanged(activity: MainActivity, scrollID: Int) {
            assertSame(page, activity.findViewById(R.id.information_query_page))
            assertSame(header, page.findViewWithTag("information.query.header"))
            assertSame(selector, activity.findViewById(R.id.information_query_mode_switch))
            assertSame(scroll, activity.findViewById(scrollID))
        }
    }

    private class PendingRequest(val isRefreshing: () -> Boolean) {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        fun finish(scenario: ActivityScenario<MainActivity>) {
            release.countDown()
            val deadline = android.os.SystemClock.elapsedRealtime() + 8_000
            while (isRefreshing() && android.os.SystemClock.elapsedRealtime() < deadline) {
                android.os.SystemClock.sleep(10)
            }
            assertFalse("The injected request must finish", isRefreshing())
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            val drawn = CountDownLatch(1)
            scenario.onActivity { activity -> activity.window.decorView.postOnAnimation {
                activity.window.decorView.postOnAnimation { drawn.countDown() }
            } }
            assertTrue(drawn.await(5, TimeUnit.SECONDS))
        }
    }

    private fun delayedRequest(source: Source, fails: Boolean,
        block: (ActivityScenario<MainActivity>, PendingRequest) -> Unit) {
        val credentials = SecureCredentialStore(context)
        val previousCredentials = credentials.load()
        val preferences = AppPreferences(context)
        val previousAutomatic = preferences.automaticTermDetectionEnabled
        val previousTerm = preferences.termID
        val previousTermStart = preferences.termStartDate
        val previousSchedule = ScheduleStore(context).load()
        val previousClassrooms = ClassroomStore(context).load()
        credentials.clear()
        preferences.automaticTermDetectionEnabled = false
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                instrumentation.waitForIdleSync()
                lateinit var schedule: ScheduleRepository
                lateinit var classrooms: ClassroomRepository
                scenario.onActivity { activity ->
                    schedule = repository(activity, "getScheduleRepository")
                    classrooms = repository(activity, "getClassroomRepository")
                }
                val startupDeadline = android.os.SystemClock.elapsedRealtime() + 5_000
                while ((schedule.isRefreshing || classrooms.isRefreshing) &&
                    android.os.SystemClock.elapsedRealtime() < startupDeadline
                ) android.os.SystemClock.sleep(10)
                assertFalse("The credential-free startup must finish first", schedule.isRefreshing || classrooms.isRefreshing)
                instrumentation.waitForIdleSync()
                lateinit var pending: PendingRequest
                scenario.onActivity { activity ->
                    pending = PendingRequest { if (source == Source.CLASSROOMS) classrooms.isRefreshing else schedule.isRefreshing }
                    val api = SjdApiClient(AuthenticatedSessionCache(), { "synthetic-token" }) { _, path, _ ->
                        if (pending.calls.incrementAndGet() == 1) {
                            pending.entered.countDown()
                            check(pending.release.await(10, TimeUnit.SECONDS))
                        }
                        if (fails) throw ScheduleClientException("Synthetic request failed")
                        if (path.contains("curriculum")) {
                            JSONObject("""{"code":"1","data":[{"semesterId":"2026-2027-1","item":[]}]}""")
                        } else JSONObject("""{"code":"1","data":[]}""")
                    }
                    ScheduleRepository::class.java.getDeclaredField("client").apply { isAccessible = true }
                        .set(schedule, SjdScheduleClient(api))
                    ClassroomRepository::class.java.getDeclaredField("client").apply { isAccessible = true }
                        .set(classrooms, SjdClassroomClient(api))
                    credentials.save(Credentials("late-${source.name}-${System.nanoTime()}", "synthetic-only"))
                    preferences.automaticTermDetectionEnabled = true
                    when (source) {
                        Source.SETTINGS_SAVE, Source.SETTINGS_REFRESH -> {
                            activity.findViewById<View>(R.id.navigation_settings).performClick()
                            val label = activity.uiText(if (source == Source.SETTINGS_SAVE) "保存设置" else "获取/刷新个人课表")
                            assertTrue(descendants(activity.findViewById(R.id.page_settings)).filterIsInstance<TextView>()
                                .first { it.text.toString() == label }.performClick())
                        }
                        Source.STARTUP -> MainActivity::class.java.getDeclaredMethod("refreshScheduleAtStartup")
                            .apply { isAccessible = true }.invoke(activity)
                        Source.EXAMS -> {
                            activity.findViewById<View>(R.id.navigation_query).performClick()
                            activity.findViewById<View>(R.id.information_query_exams_tab).performClick()
                            assertTrue(activity.findViewById<View>(R.id.information_query_exams_refresh).performClick())
                        }
                        Source.CLASSROOMS -> {
                            activity.findViewById<View>(R.id.navigation_planner).performClick()
                            assertTrue(activity.findViewById<View>(R.id.planner_fetch_button).performClick())
                        }
                    }
                }
                try {
                    assertTrue("$source must enter the injected transport", pending.entered.await(5, TimeUnit.SECONDS))
                    block(scenario, pending)
                } finally { pending.release.countDown() }
            }
        } finally {
            if (previousCredentials == null) credentials.clear() else credentials.save(previousCredentials)
            preferences.automaticTermDetectionEnabled = previousAutomatic
            preferences.termID = previousTerm
            preferences.termStartDate = previousTermStart
            if (previousSchedule == null) ScheduleStore(context).clear() else ScheduleStore(context).save(previousSchedule)
            if (previousClassrooms == null) ClassroomStore(context).clear() else ClassroomStore(context).save(previousClassrooms)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> repository(activity: MainActivity, getter: String): T =
        MainActivity::class.java.getDeclaredMethod(getter).apply { isAccessible = true }.invoke(activity) as T

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
