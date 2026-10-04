package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger
import java.io.File

/** Disposable UI-test target; fictional drafts only, no request or save action. */
@RunWith(AndroidJUnit4::class)
class LanguageSessionUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun languageRoundTripKeepsSettingsAnchorAndUnsubmittedDraftsInMemory() {
        ensurePrivacyConsentForUiTest()
        val preferences = AppPreferences(context)
        val credentials = SecureCredentialStore(context)
        val oldCredentials = credentials.load()
        val oldLanguage = preferences.languageCode
        val oldAutomatic = preferences.automaticTermDetectionEnabled
        val oldReminder = preferences.courseReminderOffsets
        credentials.clear()
        preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        preferences.automaticTermDetectionEnabled = false
        val initialTheme = ColorThemePreferences(context).load()
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                lateinit var retained: Any
                scenario.onActivity { activity ->
                    activity.findViewById<View>(R.id.navigation_settings).performClick()
                    retained = session(activity)
                    val page = activity.findViewById<ScrollView>(R.id.page_settings)
                    field(page, "settings.field/教务账号").setText("设置")
                    field(page, "settings.field/教务密码").setText("synthetic-password-draft-only")
                    field(page, "settings.field/教务密码").requestFocus()
                    field(page, "settings.field/教务密码").setSelection(7)
                    field(page, "settings.field/教学云平台密码（可选）").setText("synthetic-cloud-draft-only")
                    field(page, "settings.field/学期编号").setText("2030-2031-1")
                    field(page, "settings.field/第一周周一（YYYY-MM-DD）").setText("2030-08-26")
                    activity.findViewById<EditText>(R.id.settings_custom_deadlines_url).setText("https://example.org/unsaved-feed.json")
                    activity.findViewById<Switch>(R.id.settings_custom_deadlines_switch).isChecked = true
                    page.findViewWithTag<EditText>("course-reminder-offset-0").setText("17")
                    activity.findViewById<View>(R.id.settings_course_reminder_add).performClick()
                    page.findViewWithTag<EditText>("course-reminder-offset-1").setText("41")
                    activity.findViewById<EditText>(R.id.settings_color_theme_primary).setText("#ABCDEF")
                    val bundle = Bundle()
                    MainActivity::class.java.getDeclaredMethod("onSaveInstanceState", Bundle::class.java)
                        .apply { isAccessible = true }.invoke(activity, bundle)
                    assertFalse(bundle.toString().contains("synthetic-password-draft-only"))
                    assertFalse(bundle.toString().contains("synthetic-cloud-draft-only"))
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    val page = activity.findViewById<ScrollView>(R.id.page_settings)
                    val section = activity.findViewById<View>(R.id.settings_language_section)
                    val bounds = android.graphics.Rect(0, 0, section.width, section.height)
                    (page.getChildAt(0) as ViewGroup).offsetDescendantRectToMyCoords(section, bounds)
                    page.scrollTo(0, bounds.top)
                }
                instrumentation.waitForIdleSync()
                var expectedAnchor: ScrollAnchor? = null
                scenario.onActivity { activity -> expectedAnchor = activity.findViewById<ScrollView>(R.id.page_settings).captureAnchor() }
                listOf(AppLanguage.ENGLISH, AppLanguage.SIMPLIFIED_CHINESE).forEach { language ->
                    scenario.onActivity { it.updateAppLanguage(language) }
                    awaitLanguage(scenario, language)
                    scenario.onActivity { activity ->
                        assertSame(retained, session(activity))
                        val page = activity.findViewById<ScrollView>(R.id.page_settings)
                        assertEquals(expectedAnchor!!.key, page.captureAnchor().key)
                        assertTrue(page.scrollY > 0)
                        assertEquals("设置", field(page, "settings.field/教务账号").text.toString())
                        assertEquals("synthetic-password-draft-only", field(page, "settings.field/教务密码").text.toString())
                        assertTrue(field(page, "settings.field/教务密码").hasFocus())
                        assertEquals(7, field(page, "settings.field/教务密码").selectionStart)
                        assertEquals("synthetic-cloud-draft-only", field(page, "settings.field/教学云平台密码（可选）").text.toString())
                        assertEquals("2030-2031-1", field(page, "settings.field/学期编号").text.toString())
                        assertEquals("2030-08-26", field(page, "settings.field/第一周周一（YYYY-MM-DD）").text.toString())
                        assertEquals("https://example.org/unsaved-feed.json", activity.findViewById<EditText>(R.id.settings_custom_deadlines_url).text.toString())
                        assertTrue(activity.findViewById<Switch>(R.id.settings_custom_deadlines_switch).isChecked)
                        assertEquals("17", page.findViewWithTag<EditText>("course-reminder-offset-0").text.toString())
                        assertEquals("41", page.findViewWithTag<EditText>("course-reminder-offset-1").text.toString())
                        assertEquals("#ABCDEF", activity.findViewById<EditText>(R.id.settings_color_theme_primary).text.toString())
                        assertEquals(language == AppLanguage.ENGLISH, AppLocale.isEnglish(activity))
                        if (language == AppLanguage.ENGLISH) assertEquals("Add a reminder", activity.getString(R.string.course_reminder_add))
                        assertTrue(field(page, "settings.field/教务密码").isSaveEnabled == false)
                        assertNull(SecureCredentialStore(activity).load())
                    }
                    if (language == AppLanguage.ENGLISH) {
                        scenario.onActivity { activity ->
                            assertTrue(activity.findViewById<View>(R.id.settings_language_section)
                                .getGlobalVisibleRect(android.graphics.Rect()))
                            val page = activity.findViewById<View>(R.id.page_settings)
                            assertFalse(field(page, "settings.field/教务密码").getGlobalVisibleRect(android.graphics.Rect()))
                            assertFalse(field(page, "settings.field/教学云平台密码（可选）").getGlobalVisibleRect(android.graphics.Rect()))
                            // Disposable synthetic fixture; capture only the
                            // current language card, never either password area.
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        val visibleFrame = java.util.concurrent.CountDownLatch(1)
                        scenario.onActivity { activity -> activity.window.decorView.postOnAnimation {
                            activity.window.decorView.postOnAnimation { visibleFrame.countDown() }
                        } }
                        assertTrue(visibleFrame.await(5, java.util.concurrent.TimeUnit.SECONDS))
                        assertTrue(UiDevice.getInstance(instrumentation).takeScreenshot(
                            File(context.cacheDir, "language-settings-english.png")))
                        scenario.onActivity { it.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                    }
                }
                assertEquals(oldReminder, AppPreferences(context).courseReminderOffsets)
                assertEquals(initialTheme, ColorThemePreferences(context).load())
            }
        } finally {
            preferences.languageCode = oldLanguage
            preferences.automaticTermDetectionEnabled = oldAutomatic
            if (oldCredentials == null) credentials.clear() else credentials.save(oldCredentials)
        }
    }

    @Test fun languageRecreationRetainsCalendarQueryAndCachedResourceOwners() {
        ensurePrivacyConsentForUiTest()
        val preferences = AppPreferences(context)
        val oldLanguage = preferences.languageCode
        val credentials = SecureCredentialStore(context)
        val oldCredentials = credentials.load()
        val oldAutomatic = preferences.automaticTermDetectionEnabled
        val oldClassrooms = ClassroomStore(context).load()
        lateinit var retained: ActivitySessionState
        val authCalls = AtomicInteger()
        val apiCalls = AtomicInteger()
        val termCalls = AtomicInteger()
        val gradeCalls = AtomicInteger()
        credentials.clear(); preferences.automaticTermDetectionEnabled = false
        preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                scenario.onActivity { activity ->
                    retained = session(activity) as ActivitySessionState
                    activity.findViewById<View>(R.id.navigation_courses).performClick()
                    activity.findViewById<View>(R.id.information_query_assignments_tab).performClick()
                    activity.findViewById<View>(R.id.information_query_assignments_refresh).performClick()
                }
                val deadline = SystemClock.elapsedRealtime() + 5_000
                while (retained.dailyInfo.isLoadingAllAssignments() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(10)
                assertNotNull(retained.dailyInfo.allAssignments())
                val idleDeadline = SystemClock.elapsedRealtime() + 5_000
                while (retained.classrooms.isRefreshing && SystemClock.elapsedRealtime() < idleDeadline) SystemClock.sleep(10)
                assertFalse(retained.classrooms.isRefreshing)
                scenario.onActivity { activity ->
                    val api = SjdApiClient(AuthenticatedSessionCache(), { authCalls.incrementAndGet(); "synthetic-token" }) { _, path, _ ->
                        apiCalls.incrementAndGet()
                        if (path.contains("curriculum")) JSONObject("""{"code":"1","data":[{"semesterId":"2026-2027-1","item":[]}]}""")
                        else JSONObject("""{"code":"1","data":[]}""")
                    }
                    ClassroomRepository::class.java.getDeclaredField("client").apply { isAccessible = true }
                        .set(retained.classrooms, SjdClassroomClient(api))
                    ScheduleRepository::class.java.getDeclaredField("client").apply { isAccessible = true }
                        .set(retained.schedule, SjdScheduleClient(api))
                    retained.credentials.save(Credentials("synthetic-language-only", "synthetic-only"))
                    val fetchTerms: (Credentials) -> AcademicTerms = {
                        termCalls.incrementAndGet()
                        AcademicTerms("2026-2027-1", listOf(AcademicTerm("2026-2027-1", "Raw synthetic term")))
                    }
                    val fetchGrades: (Credentials, String, String) -> AcademicGrades = { _, term, type ->
                        gradeCalls.incrementAndGet()
                        AcademicGrades(term, type, "synthetic", "3.0", listOf(AcademicGrade("raw", "设置", "0", "2", null, null, null, null)))
                    }
                    AcademicGradesRepository::class.java.getDeclaredField("fetchTerms").apply { isAccessible = true }.set(retained.grades, fetchTerms)
                    AcademicGradesRepository::class.java.getDeclaredField("fetchGrades").apply { isAccessible = true }.set(retained.grades, fetchGrades)
                    retained.grades.load()
                    retained.classrooms.refresh(force = true, onComplete = activity.classroomCompletionCallback())
                }
                val fetchedDeadline = SystemClock.elapsedRealtime() + 5_000
                while ((retained.classrooms.isRefreshing || retained.grades.isLoading) && SystemClock.elapsedRealtime() < fetchedDeadline) SystemClock.sleep(10)
                assertNotNull(retained.grades.snapshot)
                assertTrue(apiCalls.get() > 0 && authCalls.get() > 0)
                val initialApiCalls = apiCalls.get()
                val initialAuthCalls = authCalls.get()
                scenario.onActivity { activity ->
                    retained.query!!.query = "raw keyword 设置"
                    retained.query!!.visibleEventCount = 80
                    activity.findViewById<View>(R.id.navigation_calendar).performClick()
                    retained.calendar!!.selectedMode = TeachingCalendarMode.YEAR
                    retained.calendar!!.selectedDate.set(2030, java.util.Calendar.JUNE, 17)
                    activity.updateAppLanguage(AppLanguage.ENGLISH)
                }
                awaitLanguage(scenario, AppLanguage.ENGLISH)
                scenario.onActivity { activity ->
                    assertSame(retained, session(activity))
                    assertEquals(TeachingCalendarMode.YEAR, retained.calendar!!.selectedMode)
                    assertEquals(2030, retained.calendar!!.selectedDate.get(java.util.Calendar.YEAR))
                    assertEquals("raw keyword 设置", retained.query!!.query)
                    assertEquals(80, retained.query!!.visibleEventCount)
                    assertNotNull(retained.dailyInfo.allAssignments())
                    assertEquals(initialApiCalls, apiCalls.get())
                    assertEquals(initialAuthCalls, authCalls.get())
                    assertEquals(1, termCalls.get())
                    assertEquals(1, gradeCalls.get())
                    assertEquals("设置", retained.grades.snapshot!!.items.single().name)
                    assertNotNull(activity.findViewById<View?>(R.id.page_calendar))
                    activity.findViewById<View>(R.id.navigation_courses).performClick()
                    activity.findViewById<View>(R.id.information_query_grades_tab).performClick()
                    assertTrue(uiDescendants(activity.findViewById(R.id.information_query_grades_scroll)).filterIsInstance<TextView>()
                        .any { it.text.toString() == "设置" })
                }
            }
            assertNull(retained.uiOwner.current())
            assertNull(retained.settings)
            assertTrue(ScheduleRepository::class.java.getDeclaredField("closed").apply { isAccessible = true }
                .get(retained.schedule).let { it as java.util.concurrent.atomic.AtomicBoolean }.get())
            assertTrue(AcademicGradesRepository::class.java.getDeclaredField("closed").apply { isAccessible = true }.getBoolean(retained.grades))
        } finally {
            preferences.languageCode = oldLanguage; preferences.automaticTermDetectionEnabled = oldAutomatic
            if (oldCredentials == null) credentials.clear() else credentials.save(oldCredentials)
            if (oldClassrooms == null) ClassroomStore(context).clear() else ClassroomStore(context).save(oldClassrooms)
        }
    }

    @Test fun rapidLanguageReversalAndLeavingSettingsCancelTheDelayedCommand() {
        ensurePrivacyConsentForUiTest()
        val preferences = AppPreferences(context)
        val credentials = SecureCredentialStore(context)
        val oldCredentials = credentials.load()
        val oldLanguage = preferences.languageCode
        val oldAutomatic = preferences.automaticTermDetectionEnabled
        credentials.clear(); preferences.automaticTermDetectionEnabled = false
        preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                lateinit var original: MainActivity
                val reversalSettled = java.util.concurrent.CountDownLatch(1)
                scenario.onActivity { activity ->
                    original = activity
                    activity.findViewById<View>(R.id.navigation_settings).performClick()
                    selectInterfaceLanguage(activity, AppLanguage.ENGLISH)
                    selectInterfaceLanguage(activity, AppLanguage.SIMPLIFIED_CHINESE)
                    // Observe beyond the bounded commit delay; this is an owner
                    // cancellation assertion, not a rendering performance test.
                    activity.window.decorView.postDelayed({ reversalSettled.countDown() }, 300)
                }
                assertTrue(reversalSettled.await(5, java.util.concurrent.TimeUnit.SECONDS))
                scenario.onActivity { activity ->
                    assertSame(original, activity)
                    assertEquals(AppLanguage.SIMPLIFIED_CHINESE.code, AppPreferences(activity).languageCode)
                    assertFalse(AppLocale.isEnglish(activity))
                }
                val navigationSettled = java.util.concurrent.CountDownLatch(1)
                scenario.onActivity { activity ->
                    selectInterfaceLanguage(activity, AppLanguage.ENGLISH)
                    activity.findViewById<View>(R.id.navigation_query).performClick()
                    activity.window.decorView.postDelayed({ navigationSettled.countDown() }, 300)
                }
                assertTrue(navigationSettled.await(5, java.util.concurrent.TimeUnit.SECONDS))
                scenario.onActivity { activity ->
                    assertSame(original, activity)
                    assertEquals(AppLanguage.SIMPLIFIED_CHINESE.code, AppPreferences(activity).languageCode)
                    assertNotNull(activity.findViewById<View?>(R.id.information_query_page))
                }
            }
        } finally {
            preferences.languageCode = oldLanguage; preferences.automaticTermDetectionEnabled = oldAutomatic
            if (oldCredentials == null) credentials.clear() else credentials.save(oldCredentials)
        }
    }

    private fun field(root: View, tag: String): EditText = root.findViewWithTag(tag)
    private fun selectInterfaceLanguage(activity: MainActivity, language: AppLanguage) {
        assertTrue(activity.findViewById<View>(R.id.settings_language_selector).performClick())
        val page = checkNotNull(MainActivity::class.java.getDeclaredField("settingsPage")
            .apply { isAccessible = true }.get(activity))
        val dialog = checkNotNull(page.javaClass.getDeclaredField("languagePickerDialog")
            .apply { isAccessible = true }.get(page)) as android.app.AlertDialog
        assertTrue(dialog.isShowing)
        assertEquals(14, dialog.listView.adapter.count)
        val position = AppLanguage.entries.indexOf(language)
        assertTrue(dialog.listView.performItemClick(null, position, dialog.listView.adapter.getItemId(position)))
    }
    private fun session(activity: MainActivity): Any = checkNotNull(MainActivity::class.java.getDeclaredMethod("getActivitySession")
        .apply { isAccessible = true }.invoke(activity))
    private fun awaitLanguage(scenario: ActivityScenario<MainActivity>, language: AppLanguage) {
        val deadline = SystemClock.elapsedRealtime() + 5_000
        var ready = false
        while (!ready && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { ready = AppLocale.resolvedLanguage(it) == language }
            if (!ready) SystemClock.sleep(10)
        }
        assertTrue("The recreated Activity must use the requested localized Context", ready)
        val frames = java.util.concurrent.CountDownLatch(1)
        scenario.onActivity { activity -> activity.window.decorView.postOnAnimation {
            activity.window.decorView.postOnAnimation { activity.window.decorView.postOnAnimation { frames.countDown() } }
        } }
        assertTrue(frames.await(5, java.util.concurrent.TimeUnit.SECONDS))
        instrumentation.waitForIdleSync()
    }
}
