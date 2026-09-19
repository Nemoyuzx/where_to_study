package com.nemoyu.wheretostudy.nativeapp

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Permission is revoked externally before launch, because revoking it kills the running app. */
@RunWith(AndroidJUnit4::class)
class CourseReminderPermissionRecoveryUiTest {
    @Test fun deniedPermissionRevokesPersistedAuthorizationAndPendingPlan() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("permissionDenied") == "true")
        check(Build.HARDWARE in setOf("ranchu", "goldfish"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = AppPreferences(context)
        val state = CourseReminderStateStore(context)
        val receiver = ComponentName(context, CourseReminderAlarmReceiver::class.java)
        try {
            ensurePrivacyConsentForUiTest()
            assertFalse(CourseReminderNotificationRuntime.hasPermission(context))
            preferences.courseRemindersEnabled = true
            state.authorize(CourseReminderScheduler.accountKey(context))
            state.plan("old-plan", System.currentTimeMillis() + 86_400_000, setOf("synthetic"), false)
            context.packageManager.setComponentEnabledSetting(receiver, PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP)
            assertTrue(CourseReminderScheduler.reconcile(context))
            assertFalse(preferences.courseRemindersEnabled)
            assertFalse(state.authorized)
            assertEquals("", state.token)
            assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                context.packageManager.getComponentEnabledSetting(receiver))
        } finally { CourseReminderScheduler.revoke(context); preferences.clear() }
    }
}
