package com.nemoyu.wheretostudy.nativeapp

import android.animation.ValueAnimator
import android.content.Intent
import android.os.Build
import android.view.View
import android.view.ViewGroup
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.Condition
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Only app-owned synthetic UI, no authentication or screen-capture API. */
@RunWith(AndroidJUnit4::class)
class LanguageTransitionUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val device get() = UiDevice.getInstance(instrumentation)

    @Test fun realBlurCoversWholeAppAndWaitsForReadyBeforeRevealOnNativeAndLegacyPaths() {
        assumeTrue(Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled())
        ensurePrivacyConsentForUiTest()
        listOf(false, true).forEach { legacy ->
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                val transition = LanguageChangeTransition(forceLegacyBlur = legacy)
                val ready = AtomicBoolean(false)
                val commits = AtomicInteger()
                try {
                    scenario.onActivity { activity ->
                        val host = activity.window.decorView as ViewGroup
                        transition.request(host, activity.findViewById(R.id.adaptive_root), "Synthetic language transition",
                            { commits.incrementAndGet() }, { ready.get() })
                    }
                    await(scenario) { transition.phase == "waiting-layout" }
                    scenario.onActivity { activity ->
                        val host = activity.window.decorView as ViewGroup
                        val cover = checkNotNull(host.findViewWithTag<View>("overlay.language-transition"))
                        assertEquals(host.width, cover.width); assertEquals(host.height, cover.height)
                        assertTrue(cover.isClickable)
                        assertEquals(1, commits.get()); assertEquals(0, transition.readyFrameCount)
                        assertEquals("waiting-layout", transition.phase)
                        ready.set(true)
                        host.postInvalidateOnAnimation()
                    }
                    await(scenario) { transition.phase == "idle" }
                    scenario.onActivity { activity ->
                        assertNull(activity.window.decorView.findViewWithTag<View>("overlay.language-transition"))
                        assertEquals(2, transition.readyFrameCount)
                        assertEquals(1, commits.get())
                    }
                } finally { instrumentation.runOnMainSync { transition.close() } }
            }
        }
    }

    @Test fun realLocaleRoundTripKeepsTheSameActivityAndRetainedOwner() {
        ensurePrivacyConsentForUiTest()
        val preferences = AppPreferences(context)
        val original = preferences.languageCode
        preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        try {
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                lateinit var first: MainActivity
                lateinit var retained: Any
                scenario.onActivity { activity ->
                    first = activity
                    retained = session(activity)
                    activity.findViewById<View>(R.id.navigation_settings).performClick()
                }
                listOf(AppLanguage.ENGLISH, AppLanguage.SIMPLIFIED_CHINESE).forEach { language ->
                    scenario.onActivity { it.updateAppLanguage(language) }
                    await(scenario) { it.languageTransitionPhase() == "idle" &&
                        AppLocale.isEnglish(it) == (language == AppLanguage.ENGLISH) }
                    scenario.onActivity { activity ->
                        assertSame(first, activity); assertSame(retained, session(activity))
                        assertTrue(activity.findViewById<View>(R.id.navigation_settings).isSelected)
                        assertEquals(language.code, AppPreferences(activity).languageCode)
                    }
                }
            }
        } finally { preferences.languageCode = original }
    }

    private fun session(activity: MainActivity): Any = checkNotNull(MainActivity::class.java
        .getDeclaredMethod("getActivitySession").apply { isAccessible = true }.invoke(activity))

    private fun await(scenario: ActivityScenario<MainActivity>, predicate: (MainActivity) -> Boolean) {
        assertTrue(device.wait(object : Condition<UiDevice, Boolean> {
            override fun apply(args: UiDevice): Boolean {
                var ready = false
                scenario.onActivity { ready = predicate(it) }
                return ready
            }
        }, 5_000) == true)
    }
}
