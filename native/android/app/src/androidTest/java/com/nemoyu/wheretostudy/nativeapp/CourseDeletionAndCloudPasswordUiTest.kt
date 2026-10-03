package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.graphics.Rect
import android.os.Environment
import android.os.Looper
import android.util.AtomicFile
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
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

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
    fun asynchronousCourseRecordIoKeepsAtomicFailuresScopeAndCanceledOwners() {
        prepare(AppLanguage.SIMPLIFIED_CHINESE)
        val credentials = SecureCredentialStore(context)
        val repository = ScheduleRepository(context, credentials, AppPreferences(context))
        val deletionStore = ScheduleRepository::class.java.getDeclaredField("deletionStore")
            .apply { isAccessible = true }.get(repository) as CourseDeletionStore
        val observed = ObservedAtomicFile(File(context.filesDir, "course_deletions_v1.json"))
        CourseDeletionStore::class.java.getDeclaredField("file").apply { isAccessible = true }.set(deletionStore, observed)
        val worker = ScheduleRepository::class.java.getDeclaredField("worker")
            .apply { isAccessible = true }.get(repository) as ExecutorService
        fun awaitOperation(start: ((Result<Unit>) -> Unit) -> Unit): Result<Unit> {
            val complete = CountDownLatch(1)
            val result = AtomicReference<Result<Unit>>()
            instrumentation.runOnMainSync { start { value ->
                assertEquals(Looper.getMainLooper(), Looper.myLooper())
                result.set(value); complete.countDown()
            } }
            assertTrue("Local course operation must complete", complete.await(5, TimeUnit.SECONDS))
            return result.get()
        }
        fun holdWorker(): CountDownLatch {
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            worker.execute { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            return release
        }
        try {
            assertTrue(awaitOperation { callback -> repository.deleteCourseAsync(snapshot.courses.first(), today,
                CourseDeletionScope.SINGLE_OCCURRENCE, snapshot.termID, onComplete = callback) }.isSuccess)
            assertTrue(observed.reads.get() > 0 && observed.writes.get() > 0)
            assertFalse("Actual course record file reads/writes must run off main", observed.ioOnMain.get())
            val record = deletionStore.load().single()
            val readsBeforeLoad = observed.reads.get()
            val loaded = AtomicReference<List<CourseDeletion>>()
            val loadComplete = CountDownLatch(1)
            instrumentation.runOnMainSync {
                repository.loadDeletedCourses { result ->
                    assertEquals(Looper.getMainLooper(), Looper.myLooper())
                    loaded.set(result.getOrThrow()); loadComplete.countDown()
                }
            }
            assertTrue(loadComplete.await(5, TimeUnit.SECONDS))
            assertEquals(listOf(record), loaded.get())
            assertTrue(observed.reads.get() > readsBeforeLoad)
            assertFalse(observed.ioOnMain.get())
            val effective = repository.schedule
            val canceledCallbacks = AtomicInteger()
            val active = AtomicBoolean(true)
            val canceledRelease = holdWorker()
            instrumentation.runOnMainSync {
                repository.restoreCourseAsync(record.id, active::get) { canceledCallbacks.incrementAndGet() }
            }
            active.set(false)
            canceledRelease.countDown()
            worker.submit { }.get(5, TimeUnit.SECONDS)
            instrumentation.waitForIdleSync()
            assertEquals(0, canceledCallbacks.get())
            assertEquals(listOf(record), deletionStore.load())

            val invalidatedRelease = holdWorker()
            val invalidated = AtomicReference<Result<Unit>>()
            val invalidatedComplete = CountDownLatch(1)
            instrumentation.runOnMainSync {
                repository.restoreCourseAsync(record.id) { invalidated.set(it); invalidatedComplete.countDown() }
            }
            LocalDataCoordinator.clear { credentials.save(Credentials("another-fictional-account", "fictional")) }
            invalidatedRelease.countDown()
            assertTrue(invalidatedComplete.await(5, TimeUnit.SECONDS))
            assertTrue(invalidated.get().exceptionOrNull() is LocalDataInvalidatedException)
            assertEquals(listOf(record), deletionStore.load())
            assertEquals("A queued restoration must not change the new account's effective schedule",
                snapshot, loadUsableSchedule(context))
            LocalDataCoordinator.clear { credentials.save(Credentials("course-cloud-test-only", "fictional-academic", "fictional-cloud")) }

            assertTrue(context.filesDir.setWritable(false, true))
            val failed = try {
                awaitOperation { callback -> repository.restoreCourseAsync(record.id, onComplete = callback) }
            } finally { assertTrue(context.filesDir.setWritable(true, true)) }
            assertTrue("A failed durable write must be reported as failure", failed.isFailure)
            assertEquals(effective, repository.schedule)
            assertEquals(listOf(record), deletionStore.load())
            assertTrue(awaitOperation { callback -> repository.restoreCourseAsync(record.id, onComplete = callback) }.isSuccess)
            assertTrue(deletionStore.load().isEmpty())
            assertEquals(snapshot, repository.schedule)
            assertFalse(observed.ioOnMain.get())
        } finally {
            context.filesDir.setWritable(true, true)
            repository.close()
        }
    }

    @Test
    fun closingCourseRecordLoadingDialogPreventsLateDialogPublication() {
        prepare(AppLanguage.SIMPLIFIED_CHINESE)
        launch().use { scenario ->
            lateinit var repository: ScheduleRepository
            lateinit var worker: ExecutorService
            scenario.onActivity { activity ->
                repository = MainActivity::class.java.getDeclaredMethod("getScheduleRepository")
                    .apply { isAccessible = true }.invoke(activity) as ScheduleRepository
                worker = ScheduleRepository::class.java.getDeclaredField("worker")
                    .apply { isAccessible = true }.get(repository) as ExecutorService
                activity.findViewById<View>(R.id.navigation_settings).performClick()
            }
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            worker.execute { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            try {
                scenario.onActivity { activity -> assertTrue(button(activity, "管理已删除课程").performClick()) }
                assertTrue(device.wait(Until.hasObject(By.text("正在获取…")), 5_000))
                device.pressBack()
                scenario.onActivity { activity -> activity.findViewById<View>(R.id.navigation_planner).performClick() }
                release.countDown()
                worker.submit { }.get(5, TimeUnit.SECONDS)
                instrumentation.waitForIdleSync()
                assertFalse(device.hasObject(By.text("已删除课程")))
                assertFalse(device.hasObject(By.text("当前账号、本学期暂无课程删除记录")))
            } finally { release.countDown() }
        }
    }

    @Test
    fun loadedCourseRecordDialogsCloseWithTheirSettingsOwnerAndRejectStaleSelections() {
        listOf(false, true).forEach { hasRecords ->
            listOf(false, true).forEach { rebuildAdaptiveLayout ->
                prepare(AppLanguage.SIMPLIFIED_CHINESE)
                val records = if (hasRecords) listOf(CourseDeletionLogic.create(
                    "course-cloud-test-only", snapshot, snapshot.courses.first(), today, CourseDeletionScope.WHOLE_COURSE,
                )) else emptyList()
                CourseDeletionStore(context).save(records)
                launch().use { scenario ->
                    lateinit var source: View
                    scenario.onActivity { activity ->
                        activity.findViewById<View>(R.id.navigation_settings).performClick()
                        source = button(activity, "管理已删除课程")
                        assertTrue(source.performClick())
                    }
                    val selector = if (hasRecords) By.textStartsWith("Course deletion fixture") else
                        By.text("当前账号、本学期暂无课程删除记录")
                    val oldItem = checkNotNull(device.wait(Until.findObject(selector), 5_000))
                    scenario.onActivity { activity ->
                        if (rebuildAdaptiveLayout) {
                            // Exercise the same-Activity owner replacement used
                            // by a new adaptive layout, without resizing the AVD.
                            MainActivity::class.java.getDeclaredMethod("updateAdaptiveLayout", java.lang.Boolean.TYPE)
                                .apply { isAccessible = true }.invoke(activity, true)
                        } else activity.findViewById<View>(R.id.navigation_planner).performClick()
                        assertFalse(source.isAttachedToWindow)
                    }
                    assertTrue("Loaded records/empty dialogs must close with their owner",
                        device.wait(Until.gone(selector), 5_000))
                    if (hasRecords) {
                        // Accessibility can reject this cached node as stale;
                        // a late selection must never start an old restoration.
                        runCatching { oldItem.click() }
                    }
                    instrumentation.waitForIdleSync()
                    assertFalse(device.hasObject(By.text("恢复课程")))
                    assertFalse(device.hasObject(By.text("正在恢复…")))
                    assertEquals(records, CourseDeletionStore(context).load())
                }
            }
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

    private class ObservedAtomicFile(file: File) : AtomicFile(file) {
        val reads = AtomicInteger()
        val writes = AtomicInteger()
        val ioOnMain = AtomicBoolean(false)
        override fun openRead(): FileInputStream {
            reads.incrementAndGet()
            if (Looper.myLooper() == Looper.getMainLooper()) ioOnMain.set(true)
            return super.openRead()
        }
        override fun startWrite(): FileOutputStream {
            writes.incrementAndGet()
            if (Looper.myLooper() == Looper.getMainLooper()) ioOnMain.set(true)
            return super.startWrite()
        }
    }
}
