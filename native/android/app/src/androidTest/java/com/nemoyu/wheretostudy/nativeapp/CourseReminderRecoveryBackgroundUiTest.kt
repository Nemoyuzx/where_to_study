package com.nemoyu.wheretostudy.nativeapp

import android.app.PendingIntent
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

/** prepare -> kill process -> force the persisted JobScheduler job -> verify, with no Activity. */
@RunWith(AndroidJUnit4::class)
class CourseReminderRecoveryBackgroundUiTest {
    @Test fun persistedRecoveryJobRestoresAPlanInAFreshBackgroundProcess() {
        val phase = InstrumentationRegistry.getArguments().getString("phase")
        assumeTrue("Run the explicit two-phase background test", phase in setOf("prepare", "verify"))
        check(Build.HARDWARE in setOf("ranchu", "goldfish"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val state = CourseReminderStateStore(context)
        when (phase) {
            "prepare" -> {
                ensurePrivacyConsentForUiTest()
                CourseReminderScheduler.revoke(context)
                AppPreferences(context).apply { clear(); automaticTermDetectionEnabled = false }
                val credentials = Credentials("recovery-background-fixture", "fictional-password")
                SecureCredentialStore(context).save(credentials)
                val tomorrow = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
                    .apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }.format(Date(System.currentTimeMillis() + 86_400_000))
                ScheduleStore(context).save(ScheduleSnapshot("fixture", tomorrow, "fixture", emptyList(),
                    ExamSchedule("fixture", CourseDeletionLogic.accountKey(credentials.account), "fixture", "fresh", "",
                        listOf(ExamArrangement("recovery", "Synthetic recovery exam", tomorrow, "08:00", "09:00", "Room")))))
                assertTrue(CourseReminderScheduler.authorize(context))
                assertTrue(CourseReminderScheduler.reconcile(context, force = true, platform = object : CourseReminderPlatform() {
                    override fun register(context: Context, exact: Boolean, at: Long, intent: PendingIntent) {
                        error("Synthetic AlarmManager registration failure")
                    }
                }))
                assertEquals(1, state.recoveryAttempt)
                assertFalse(state.registered)
                assertTrue(state.recoveryToken.isNotEmpty())
            }
            "verify" -> try {
                assertEquals("", state.recoveryToken)
                assertEquals(0, state.recoveryAttempt)
                assertTrue(state.registered)
                assertTrue(state.scheduledAt > System.currentTimeMillis())
                assertTrue(AppPreferences(context).courseRemindersEnabled)
                assertFalse(AppPreferences(context).dailyCourseNotificationsEnabled)
            } finally {
                CourseReminderScheduler.revoke(context)
                SecureCredentialStore(context).clear(); ScheduleStore(context).clear(); AppPreferences(context).clear()
            }
            else -> error("Run the explicit prepare or verify phase on a disposable emulator")
        }
    }
}
