package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.Intent
import android.app.AlertDialog
import android.os.SystemClock
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import android.widget.LinearLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.ExecutorService
import org.json.JSONObject

/** Synthetic only: no SSO navigation, credential writes, private data or outside network. */
@RunWith(AndroidJUnit4::class)
class CoursesNavigationUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    @Before fun privacy() = ensurePrivacyConsentForUiTest()

    @Test fun publicQueryAndCourseModesAreSeparateAndLanguageRecreationRetainsCourseSelection() {
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        preferences.languageCode = "zh-Hans"
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_query).performClick())
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_shuttle_tab))
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_events_tab))
                    assertNull(activity.findViewById<View?>(R.id.information_query_grades_tab))
                    assertEquals(2, labels(activity).size)
                    activity.findViewById<View>(R.id.navigation_courses).performClick()
                    assertTrue(activity.findViewById<View>(R.id.course_current_tab).isSelected)
                    assertEquals(4, labels(activity).size)
                    assertNull(activity.findViewById<View?>(R.id.information_query_shuttle_tab))
                    listOf(R.id.information_query_assignments_tab, R.id.information_query_exams_tab,
                        R.id.information_query_grades_tab, R.id.course_current_tab).forEach { id ->
                        assertTrue(activity.findViewById<View>(id).performClick())
                    }
                    activity.updateAppLanguage(AppLanguage.ENGLISH)
                }
                val deadline = SystemClock.elapsedRealtime() + 5_000
                var english = false
                while (!english && SystemClock.elapsedRealtime() < deadline) {
                    instrumentation.waitForIdleSync()
                    scenario.onActivity { english = it.resources.configuration.locales[0].language == "en" }
                    if (!english) SystemClock.sleep(10)
                }
                assertTrue(english)
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.navigation_courses).isSelected)
                    assertTrue(activity.findViewById<View>(R.id.course_current_tab).isSelected)
                    assertEquals(InformationQueryMode.courseModes.map { activity.uiText(it.label) },
                        labels(activity).map { it.contentDescription.toString() })
                    activity.findViewById<View>(R.id.navigation_settings).performClick()
                    val page = activity.findViewById<View>(R.id.page_settings)
                    val password = uiDescendants(page).filterIsInstance<EditText>().first {
                        it.hint?.toString() == activity.uiText("教务密码")
                    }
                    password.setText("synthetic unsaved only")
                    val fields = uiDescendants(page).filterIsInstance<EditText>().toList()
                    assertTrue(fields.none {
                        val labels = it.hint?.toString().orEmpty() + " " + it.contentDescription?.toString().orEmpty()
                        "Microsoft" in labels || "QMplus" in labels
                    })
                    assertNotNull(activity.findViewById<View?>(R.id.settings_qmplus_connect))
                    assertNull(activity.findViewById<View?>(R.id.settings_qmplus_disconnect))
                    assertSame(page, activity.findViewById(R.id.page_settings))
                    assertEquals("synthetic unsaved only", password.text.toString())
                }
            }
        } finally { preferences.languageCode = previousLanguage }
    }

    @Test fun delayedReadAndQueuedWriteCannotRestoreADeletedQmplusSnapshot() {
        val prefs = context.getSharedPreferences("qmplus_ui_regression_only", Context.MODE_PRIVATE)
        assertTrue(prefs.edit().clear().putString("snapshot_v1", String(sample(), StandardCharsets.UTF_8)).commit())
        val read = CountDownLatch(1); val releaseRead = CountDownLatch(1)
        lateinit var repository: QmplusRepository
        instrumentation.runOnMainSync {
            repository = QmplusRepository(context, prefs, beforeReadPublication = {
                read.countDown(); check(releaseRead.await(5, TimeUnit.SECONDS))
            })
        }
        try {
            assertTrue(read.await(5, TimeUnit.SECONDS))
            instrumentation.runOnMainSync { repository.clear() }
            val generation = repository.generation
            releaseRead.countDown()
            repository.cookiesCleared(generation) // queued behind the delayed read: a real worker completion barrier
            await { !repository.isClearingSession }
            assertNull(repository.snapshot); assertNull(prefs.getString("snapshot_v1", null))
            assertEquals(generation, repository.generation)
        } finally { releaseRead.countDown(); repository.close(); assertTrue(prefs.edit().clear().commit()) }

        val save = CountDownLatch(1); val releaseSave = CountDownLatch(1); val finished = CountDownLatch(1)
        instrumentation.runOnMainSync {
            repository = QmplusRepository(context, prefs, beforeSavePublication = {
                save.countDown(); check(releaseSave.await(5, TimeUnit.SECONDS))
            }, afterSavePublication = { finished.countDown() })
        }
        try {
            await { !repository.isLoading }
            val oldGeneration = repository.generation
            instrumentation.runOnMainSync { repository.accept(sample(), oldGeneration) }
            assertTrue(save.await(5, TimeUnit.SECONDS))
            instrumentation.runOnMainSync { LocalDataCoordinator.clear { repository.clear() } }
            releaseSave.countDown(); assertTrue(finished.await(5, TimeUnit.SECONDS))
            instrumentation.waitForIdleSync()
            assertNull(repository.snapshot); assertNull(prefs.getString("snapshot_v1", null))
            assertFalse(repository.isLoading); assertNull(repository.error)
            instrumentation.runOnMainSync { repository.accept(sample(), oldGeneration) }
            assertFalse(repository.isLoading); assertNull(repository.snapshot)
        } finally { releaseSave.countDown(); repository.close(); assertTrue(prefs.edit().clear().commit()) }
    }

    @Test fun sameGenerationConnectionsAreSingleFlightAndOldSessionTokensDoNotTouchTheNewOwner() {
        val prefs = context.getSharedPreferences("qmplus_ui_connection_only", Context.MODE_PRIVATE)
        assertTrue(prefs.edit().clear().commit())
        lateinit var repository: QmplusRepository
        instrumentation.runOnMainSync { repository = QmplusRepository(context, prefs) }
        try {
            await { !repository.isLoading }
            lateinit var first: QmplusConnection
            lateinit var second: QmplusConnection
            instrumentation.runOnMainSync {
                first = checkNotNull(repository.beginConnection())
                assertNull(repository.beginConnection())
                assertTrue(repository.finishConnection(first.token))
                second = checkNotNull(repository.beginConnection())
                assertFalse(repository.finishConnection(first.token))
                assertSame(second, repository.connection)
                repository.clear()
                assertNull(repository.connection)
                assertFalse(repository.finishConnection(second.token))
            }
            repository.cookiesCleared(repository.generation)
            await { !repository.isClearingSession }
            instrumentation.runOnMainSync { assertNotNull(repository.beginConnection()); repository.close() }
            assertNull(repository.connection)
        } finally { repository.close(); assertTrue(prefs.edit().clear().commit()) }
    }

    @Test fun droppedCookieClearAckExitsBusyWithoutClaimingSuccessAndLateAckIsIgnored() {
        val prefs = context.getSharedPreferences("qmplus_ui_dropped_ack_only", Context.MODE_PRIVATE)
        assertTrue(prefs.edit().clear().commit())
        lateinit var repository: QmplusRepository
        instrumentation.runOnMainSync { repository = QmplusRepository(context, prefs, cookieClearDeadlineMillis = 100) }
        try {
            await { !repository.isLoading }
            lateinit var receiver: QmplusClearReceiver
            lateinit var attempt: QmplusCookieClearAttempt
            instrumentation.runOnMainSync {
                repository.clear()
                attempt = checkNotNull(repository.pendingCookieClearAttempt)
                receiver = QmplusClearReceiver(repository, attempt)
                assertTrue(repository.isClearingSession)
                assertNull(repository.beginConnection())
            }
            await { !repository.isClearingSession }
            assertTrue(repository.cookiesNeedClearing)
            assertTrue(prefs.getBoolean("cookie_clear_pending", false))
            assertNotNull(repository.error)
            assertNull(repository.pendingCookieClearAttempt)
            receiver.send(QmplusClearService.RESULT_CLEARED,
                Bundle().apply { putLong(QmplusActivity.EXTRA_GENERATION, attempt.generation) })
            instrumentation.waitForIdleSync()
            awaitWorker(repository)
            assertTrue("A lost/late service ACK cannot clear the durable retry marker", repository.cookiesNeedClearing)
            assertTrue(prefs.getBoolean("cookie_clear_pending", false))
            assertNotNull(repository.error)
            instrumentation.runOnMainSync {
                assertNotNull(repository.beginConnection())
                assertTrue("The retry must clear its own WebView session before login", repository.cookiesNeedClearing)
            }
        } finally { repository.close(); assertTrue(prefs.edit().clear().commit()) }
    }

    @Test fun replacingCookieCleanupRejectsOldAcksAndCanceledDeadlinesIncludingFinalClose() {
        val prefs = context.getSharedPreferences("qmplus_ui_cleanup_owner_only", Context.MODE_PRIVATE)
        assertTrue(prefs.edit().clear().commit())
        lateinit var repository: QmplusRepository
        instrumentation.runOnMainSync { repository = QmplusRepository(context, prefs) }
        try {
            await { !repository.isLoading }
            lateinit var first: QmplusCookieClearAttempt
            lateinit var current: QmplusCookieClearAttempt
            lateinit var oldReceiver: QmplusClearReceiver
            lateinit var receiver: QmplusClearReceiver
            lateinit var oldDeadline: Runnable
            lateinit var currentDeadline: Runnable
            instrumentation.runOnMainSync {
                repository.clear()
                first = checkNotNull(repository.pendingCookieClearAttempt)
                oldReceiver = QmplusClearReceiver(repository, first)
                oldDeadline = cookieDeadline(repository)
                repository.clear()
                current = checkNotNull(repository.pendingCookieClearAttempt)
                receiver = QmplusClearReceiver(repository, current)
                currentDeadline = cookieDeadline(repository)
                oldDeadline.run() // Simulate a callback already dequeued before cancellation.
                assertTrue(repository.isClearingSession)
                assertEquals(current, repository.pendingCookieClearAttempt)
                assertTrue(current.generation > first.generation)
            }
            oldReceiver.send(QmplusClearService.RESULT_CLEARED,
                Bundle().apply { putLong(QmplusActivity.EXTRA_GENERATION, first.generation) })
            oldReceiver.send(QmplusClearService.RESULT_FAILED,
                Bundle().apply { putLong(QmplusActivity.EXTRA_GENERATION, first.generation) })
            instrumentation.waitForIdleSync(); awaitWorker(repository)
            assertTrue(repository.isClearingSession); assertTrue(repository.cookiesNeedClearing)
            assertNull(repository.error)
            assertTrue(prefs.getBoolean("cookie_clear_pending", false))
            receiver.send(QmplusClearService.RESULT_CLEARED,
                Bundle().apply { putLong(QmplusActivity.EXTRA_GENERATION, current.generation) })
            instrumentation.waitForIdleSync(); awaitWorker(repository)
            assertFalse(repository.isClearingSession); assertFalse(repository.cookiesNeedClearing)
            assertFalse(prefs.getBoolean("cookie_clear_pending", true)); assertNull(repository.pendingCookieClearAttempt)
            instrumentation.runOnMainSync {
                currentDeadline.run()
                assertNull(repository.error)
                repository.clear()
                val finalDeadline = cookieDeadline(repository)
                repository.close()
                finalDeadline.run()
                assertNull(repository.pendingCookieClearAttempt)
                assertFalse(repository.isClearingSession)
                assertNull(repository.beginConnection())
                assertNull(repository.error)
            }
        } finally { repository.close(); assertTrue(prefs.edit().clear().commit()) }
    }

    @Test fun cachedRowsOpenInternalCourseDetailsAndReturnWithoutAuthOrAssignmentRequests() {
        val preferences = AppPreferences(context)
        val oldLanguage = preferences.languageCode
        try {
            listOf("zh-Hans", "en").forEach { language ->
                preferences.languageCode = language
                val auth = AtomicInteger(); val requests = AtomicInteger()
                val client = UCloudAssignmentClient({ Credentials("synthetic", "synthetic") }, elapsedRealtime = { 0 }, sleep = {},
                    authenticateOverride = { auth.incrementAndGet(); UCloudAssignmentClient.AuthenticatedSession("synthetic", "student", 100_000) },
                    apiRequestOverride = { _, _ -> requests.incrementAndGet(); JSONObject("""{"data":{"records":[]}}""") })
                ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                    .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                    lateinit var qm: QmplusRepository
                    scenario.onActivity { qm = it.qmplusState() }
                    // This case promises no status publication between open/close.
                    // Finish the initial local QM read before taking that UI snapshot.
                    await { !qm.isLoading }
                    instrumentation.waitForIdleSync()
                    lateinit var list: LinearLayout
                    lateinit var overview: View
                    lateinit var dialog: AlertDialog
                    var overviewScrollY = 0
                    val dismissed = CountDownLatch(1)
                    scenario.onActivity { activity ->
                        val daily = retained(activity).dailyInfo
                        field(daily, "assignmentClient", client)
                        field(daily, "queryCourseItems", listOf(TeachingCloudCourse("one", "设置", null,
                            listOf("Synthetic teacher 设置")), TeachingCloudCourse("two", "Synthetic no-status course", null)))
                        field(daily, "queryAssignmentItems", listOf(
                            AssignmentDeadlineItem("pending", "Synthetic pending assignment", "设置", "2026-10-03 10:00:00", "未提交", "one"),
                            AssignmentDeadlineItem("submitted", "Synthetic submitted assignment", "设置", "2026-10-03 11:00:00", "已提交", "one"),
                            AssignmentDeadlineItem("other", "Other course assignment", "设置", "2026-10-03 12:00:00", "未提交", "two")))
                        activity.findViewById<View>(R.id.navigation_courses).performClick()
                        list = activity.findViewById(R.id.course_current_list)
                        overview = activity.findViewById(R.id.course_current_scroll)
                        overviewScrollY = overview.scrollY
                        assertEquals(2, list.childCount)
                        val first = list.getChildAt(0)
                        val texts = uiDescendants(first).filterIsInstance<TextView>().map { it.text.toString() }.toList()
                        assertTrue("Raw API title must never become Settings", "设置" in texts)
                        assertTrue("Synthetic teacher 设置" in texts)
                        assertTrue(activity.getString(R.string.course_pending_count, 1) in texts)
                        assertTrue(activity.getString(R.string.course_submitted_count, 1) in texts)
                        assertFalse(activity.getString(R.string.course_pending_count, 0) in texts)
                        assertTrue(first.performClick())
                        dialog = checkNotNull(details(activity))
                        assertTrue(dialog.isShowing)
                        assertEquals("设置", dialog.findViewById<TextView>(R.id.course_detail_title).text.toString())
                        assertEquals(2, dialog.findViewById<LinearLayout>(R.id.course_detail_list).childCount)
                        assertTrue(uiDescendants(dialog.findViewById(R.id.course_detail_content)).filterIsInstance<TextView>()
                            .any { it.text.toString() == "Synthetic pending assignment" })
                        checkNotNull(dialog.window).decorView.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                            override fun onViewAttachedToWindow(view: View) = Unit
                            override fun onViewDetachedFromWindow(view: View) { dismissed.countDown() }
                        })
                        // AlertDialog buttons enqueue their click and dismiss messages;
                        // checking isShowing in this same UI callback races that queue.
                        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
                    }
                    assertTrue("The actual dialog window must detach", dismissed.await(5, TimeUnit.SECONDS))
                    instrumentation.waitForIdleSync()
                    scenario.onActivity { activity ->
                        assertSame(list, activity.findViewById(R.id.course_current_list))
                        assertSame(overview, activity.findViewById(R.id.course_current_scroll))
                        assertEquals(overviewScrollY, overview.scrollY)
                        assertFalse(dialog.isShowing)
                        assertEquals(0, auth.get()); assertEquals(0, requests.get())
                    }
                }
            }
        } finally { preferences.languageCode = oldLanguage }
    }

    @Test fun qmDirectoryHidesNonEbuAndCourseDetailsShowOnlyKindRelevantKnownTimes() {
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
            lateinit var repository: QmplusRepository
            scenario.onActivity { repository = it.qmplusState() }
            await { !repository.isLoading }
            scenario.onActivity { activity ->
                val course = QmplusCourse("1", "EBU5303 Synthetic course", null,
                    "https://qmplus.qmul.ac.uk/course/view.php?id=1", null, null, "current")
                val other = course.copy(id = "3", name = "Non EBU excluded", url = "https://qmplus.qmul.ac.uk/course/view.php?id=3")
                val assignment = QmplusActivityItem("2", "1", "Synthetic QM assignment", "assignment",
                    "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2", "2026-10-03T10:00:00Z", "2026-10-01T10:00:00Z",
                    "2026-10-04T10:00:00Z", null, 120, "submitted for grading", "available", "")
                val quiz = assignment.copy(id = "4", kind = "quiz", title = "Synthetic QM quiz",
                    url = "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=4", status = "finished")
                field(repository, "snapshot", QmplusSnapshot("2026-10-03T00:00:00Z", listOf(course, other), listOf(assignment, quiz), emptyList()))
                activity.findViewById<View>(R.id.navigation_courses).performClick()
                val list = activity.findViewById<LinearLayout>(R.id.course_qmplus_list)
                assertEquals(1, list.childCount)
                assertTrue(list.getChildAt(0).performClick())
                val dialog = checkNotNull(details(activity))
                val rows = dialog.findViewById<LinearLayout>(R.id.course_detail_list)
                assertEquals(2, rows.childCount)
                val assignmentText = uiDescendants(rows.getChildAt(0)).filterIsInstance<TextView>().map { it.text.toString() }.toList()
                val quizText = uiDescendants(rows.getChildAt(1)).filterIsInstance<TextView>().map { it.text.toString() }.toList()
                assertTrue(assignmentText.any { it.startsWith(activity.getString(R.string.qmplus_due) + ":") })
                assertFalse(assignmentText.any { it.startsWith(activity.getString(R.string.qmplus_opens) + ":") })
                assertFalse(assignmentText.any { it.startsWith(activity.getString(R.string.qmplus_time_limit).substringBefore('%')) })
                assertTrue(quizText.any { it.startsWith(activity.getString(R.string.qmplus_opens) + ":") })
                assertTrue(quizText.any { it.startsWith(activity.getString(R.string.qmplus_closes) + ":") })
                assertFalse(quizText.any { it.startsWith(activity.getString(R.string.qmplus_due) + ":") })
                assertFalse(quizText.any { it.startsWith(activity.getString(R.string.qmplus_cutoff) + ":") })
                assertTrue(quizText.contains(activity.getString(R.string.qmplus_time_limit, 120L)))
                dialog.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
            }
        }
    }

    private fun retained(activity: MainActivity) = MainActivity::class.java.getDeclaredMethod("getActivitySession")
        .apply { isAccessible = true }.invoke(activity) as ActivitySessionState
    private fun field(owner: Any, name: String, value: Any) { owner.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(owner, value) }
    private fun cookieDeadline(repository: QmplusRepository): Runnable = QmplusRepository::class.java
        .getDeclaredField("cookieClearDeadline").apply { isAccessible = true }.get(repository) as Runnable
    private fun awaitWorker(repository: QmplusRepository) {
        val worker = QmplusRepository::class.java.getDeclaredField("worker").apply { isAccessible = true }
            .get(repository) as ExecutorService
        worker.submit(Runnable {}).get(5, TimeUnit.SECONDS)
        instrumentation.waitForIdleSync()
    }
    private fun details(activity: MainActivity): AlertDialog? {
        val page = checkNotNull(MainActivity::class.java.getDeclaredField("coursesPage").apply { isAccessible = true }.get(activity))
        return page.javaClass.getDeclaredField("courseDetailsDialog").apply { isAccessible = true }.get(page) as? AlertDialog
    }

    private fun labels(activity: MainActivity): List<TextView> = uiDescendants(
        activity.findViewById<ViewGroup>(R.id.information_query_mode_switch)).filterIsInstance<TextView>().toList()

    private fun await(predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 5_000
        while (!predicate() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(10)
        assertTrue("The bounded asynchronous operation must finish", predicate())
    }

    private fun sample() = QmplusSnapshotCodec.encode(QmplusSnapshot("2026-10-03T00:00:00.000Z",
        listOf(QmplusCourse("1", "Synthetic only", null, "https://qmplus.qmul.ac.uk/course/view.php?id=1",
            null, null, "unknown")), emptyList(), emptyList()))
}
