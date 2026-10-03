package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PrivacyConsentUiTest {
    @Test
    fun firstLaunchBlocksMainFeaturesUntilConsentAndPersistsAcceptanceLocally() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val store = PrivacyConsentStore(context)
        store.clear()
        AppPreferences(context).languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(intent).use { scenario ->
                assertNotNull(
                    device.wait(
                        Until.findObject(
                            By.res(context.packageName, "privacy_consent_dialog_content"),
                        ),
                        TIMEOUT_MILLIS,
                    ),
                )
                assertNotNull(
                    device.findObject(
                        By.res(context.packageName, "privacy_consent_full_policy"),
                    ),
                )
                scenario.onActivity { activity ->
                    assertNull(
                        "Main navigation must not be created before privacy consent",
                        activity.findViewById<View?>(R.id.navigation_planner),
                    )
                }

                val accept = device.wait(
                    Until.findObject(By.text("同意并继续")),
                    TIMEOUT_MILLIS,
                )
                assertNotNull(accept)
                accept.click()
                device.waitForIdle()
                assertNotNull(
                    device.wait(
                        Until.findObject(By.res(context.packageName, "navigation_planner")),
                        TIMEOUT_MILLIS,
                    ),
                )
                assertTrue(store.hasAcceptedCurrentPolicy)
            }

            ActivityScenario.launch<MainActivity>(intent).use { scenario ->
                scenario.onActivity { activity ->
                    assertNotNull(activity.findViewById<View?>(R.id.navigation_planner))
                    assertTrue(activity.findViewById<View>(R.id.navigation_settings).performClick())
                    val accountPrivacy = activity.findViewById<View?>(
                        R.id.account_privacy_policy_button,
                    )
                    assertNotNull(accountPrivacy)
                    assertTrue(checkNotNull(accountPrivacy).isClickable)
                    assertTrue(accountPrivacy.performClick())
                }
                assertFalse(
                    device.hasObject(
                        By.res(context.packageName, "privacy_consent_dialog_content"),
                    ),
                )
                assertNotNull(
                    device.wait(
                        Until.findObject(By.res(context.packageName, "privacy_policy_content")),
                        TIMEOUT_MILLIS,
                    ),
                )
                device.pressBack()
            }
        } finally {
            store.clear()
        }
    }

    @Test
    fun settingsPrivacyKeepsCurrentStartupDisclosureAndDraftAcrossRepeatedBilingualOpens() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val preferences = AppPreferences(context)
        val previousLanguage = preferences.languageCode
        val store = PrivacyConsentStore(context)
        val previouslyAccepted = store.hasAcceptedCurrentPolicy
        val device = UiDevice.getInstance(instrumentation)
        ensurePrivacyConsentForUiTest()
        try {
            listOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.ENGLISH).forEach { language ->
                preferences.languageCode = language.code
                ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                    .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use { scenario ->
                    lateinit var settings: View
                    lateinit var account: EditText
                    scenario.onActivity { activity ->
                        activity.findViewById<View>(R.id.navigation_settings).performClick()
                        settings = activity.findViewById(R.id.page_settings)
                        fun fields(view: View): List<EditText> = if (view is EditText) listOf(view) else
                            if (view is ViewGroup) (0 until view.childCount).flatMap { fields(view.getChildAt(it)) } else emptyList()
                        account = fields(settings).first { it.hint.toString() == activity.uiText("教务账号") }
                        account.setText("synthetic-private-dialog-draft")
                    }
                    repeat(2) {
                        scenario.onActivity { activity ->
                            assertTrue(activity.findViewById<View>(R.id.account_privacy_policy_button).performClick())
                        }
                        val disclosure = if (language == AppLanguage.ENGLISH)
                            "the app refreshes the personal schedule once at launch" else "启动时会自动刷新一次个人课表"
                        assertTrue(device.wait(Until.hasObject(By.textContains(disclosure)), TIMEOUT_MILLIS))
                        assertFalse("The current policy must not be replaced with the retired request-only disclosure",
                            device.hasObject(By.textContains("used over HTTPS only when you request")))
                        device.pressBack()
                        instrumentation.waitForIdleSync()
                        scenario.onActivity { activity ->
                            assertSame(settings, activity.findViewById(R.id.page_settings))
                            assertEquals("synthetic-private-dialog-draft", account.text.toString())
                        }
                    }
                }
            }
        } finally {
            preferences.languageCode = previousLanguage
            if (!previouslyAccepted) store.clear()
        }
    }

    @Test
    fun decliningPrivacyConsentExitsWithoutEnteringMainFeatures() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val store = PrivacyConsentStore(context)
        store.clear()
        AppPreferences(context).languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)

        try {
            ActivityScenario.launch<MainActivity>(intent).use { scenario ->
                assertNotNull(
                    device.wait(
                        Until.findObject(
                            By.res(context.packageName, "privacy_consent_dialog_content"),
                        ),
                        TIMEOUT_MILLIS,
                    ),
                )
                scenario.onActivity { activity ->
                    assertNull(activity.findViewById<View?>(R.id.navigation_planner))
                }
                val decline = device.wait(
                    Until.findObject(By.text("拒绝并退出")),
                    TIMEOUT_MILLIS,
                )
                assertNotNull(decline)
                decline.click()
                device.waitForIdle()
                assertTrue(
                    device.wait(
                        Until.gone(
                            By.res(context.packageName, "privacy_consent_dialog_content"),
                        ),
                        TIMEOUT_MILLIS,
                    ),
                )
                assertFalse(store.hasAcceptedCurrentPolicy)
            }
        } finally {
            store.clear()
        }
    }

    private companion object {
        const val TIMEOUT_MILLIS = 5_000L
    }
}
