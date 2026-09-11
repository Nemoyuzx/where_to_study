package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CompactControlDensityUiTest {
    @Test fun defaultFontControlsAreActually32RatherThanOnlyDeclaringAMinimum() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assumeTrue(context.resources.configuration.fontScale <= 1.05f)
        ensurePrivacyConsentForUiTest()
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)
        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            val device = UiDevice.getInstance(instrumentation)
            assertNotNull(device.wait(Until.findObject(By.res(context.packageName, "planner_fetch_button")), 10_000))
            device.waitForIdle()
            scenario.onActivity { activity ->
                assumeTrue(activity.resources.configuration.screenWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP)
                val page = activity.findViewById<View>(R.id.page_planner)
                assertEquals(activity.dp(32), activity.findViewById<View>(R.id.planner_fetch_button).height)
                assertEquals(activity.dp(32), page.findViewWithTag<View>("planner.campus.control").height)
                val slots = page.findViewWithTag<LinearLayout>("planner.slot.controls")
                val first = (slots.getChildAt(0) as LinearLayout).getChildAt(0) as TextView
                assertEquals(activity.dp(46), first.height)
                assertEquals(0, first.paddingTop)
                assertEquals(0, first.paddingBottom)
                val params = first.layoutParams as LinearLayout.LayoutParams
                assertEquals(activity.dp(4), params.bottomMargin)
                assertEquals(activity.dp(4), params.marginEnd)
            }
        }
    }
}
