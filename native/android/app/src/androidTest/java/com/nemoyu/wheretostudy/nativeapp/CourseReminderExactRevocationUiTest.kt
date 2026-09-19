package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Two-phase external test: grant -> prepare -> revoke/kill -> wait for backup -> verify. No Activity launches. */
@RunWith(AndroidJUnit4::class)
class CourseReminderExactRevocationUiTest {
    @Test fun revokedExactPermissionStillAllowsThePairedBackupToWakeTheClosedApp() {
        val phase = InstrumentationRegistry.getArguments().getString("phase")
        assumeTrue("Run the explicit two-phase background test", phase in setOf("prepare", "verify"))
        check(Build.HARDWARE in setOf("ranchu", "goldfish"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val probe = context.getSharedPreferences("course_reminder_revocation_fixture", Context.MODE_PRIVATE)
        val state = CourseReminderStateStore(context)
        if (phase == "prepare") {
            ensurePrivacyConsentForUiTest()
            assertTrue(CourseReminderScheduler.hasExactAccess(context))
            CourseReminderScheduler.revoke(context)
            DailyCourseSummaryScheduler.revoke(context)
            AppPreferences(context).apply { clear(); automaticTermDetectionEnabled = false; courseReminderOffsets = listOf(1) }
            val credentials = Credentials("exact-revocation-fixture", "fictional-password")
            SecureCredentialStore(context).save(credentials)
            val start = ((System.currentTimeMillis() + 80_000L + 59_999L) / 60_000L) * 60_000L
            fun format(pattern: String, at: Long) = SimpleDateFormat(pattern, Locale.ROOT)
                .apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }.format(Date(at))
            val exams = listOf(start, start + 86_400_000L).mapIndexed { index, at ->
                ExamArrangement("synthetic-$index", "Synthetic backup exam", format("yyyy-MM-dd", at),
                    format("HH:mm", at), format("HH:mm", at + 60_000L), "Synthetic room")
            }
            ScheduleStore(context).save(ScheduleSnapshot("fixture", format("yyyy-MM-dd", start), "fixture", emptyList(),
                ExamSchedule("fixture", CourseDeletionLogic.accountKey(credentials.account), "fixture", "fresh", "", exams)))
            assertTrue(CourseReminderScheduler.authorize(context))
            assertTrue(state.exact)
            assertTrue(probe.edit().putString("original_token", state.token).putLong("original_at", state.scheduledAt).commit())
        } else {
            assertEquals("verify", phase)
            try {
                assertFalse(CourseReminderScheduler.hasExactAccess(context))
                assertNotEquals(probe.getString("original_token", ""), state.token)
                assertTrue(state.scheduledAt > probe.getLong("original_at", Long.MAX_VALUE))
                assertFalse(state.exact)
                assertTrue(state.registered)
                assertTrue(AppPreferences(context).courseRemindersEnabled)
                assertFalse(AppPreferences(context).dailyCourseNotificationsEnabled)
            } finally {
                CourseReminderScheduler.revoke(context)
                SecureCredentialStore(context).clear(); ScheduleStore(context).clear(); AppPreferences(context).clear()
                probe.edit().clear().commit()
            }
        }
    }
}
