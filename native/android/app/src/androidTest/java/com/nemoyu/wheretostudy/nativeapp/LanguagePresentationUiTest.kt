package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.app.Dialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import java.io.File
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Offline owned-package checks; pixel captures contain only the synthetic stripe host. */
@RunWith(AndroidJUnit4::class)
class LanguagePresentationUiTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val device get() = UiDevice.getInstance(instrumentation)

    @Before fun isolatedGuard() {
        assertEquals("true", InstrumentationRegistry.getArguments().getString("wtsIsolatedQa"))
        val qa = "com.nemoyu.wheretostudy.nativeapp.codexqa20261007gate"
        assertEquals(qa, context.packageName)
        assertEquals("$qa.test", instrumentation.context.packageName)
        assertTrue(BuildConfig.DEBUG)
        for (owner in listOf(qa, "$qa.test")) assertEquals(PackageManager.PERMISSION_DENIED,
            context.packageManager.checkPermission(Manifest.permission.INTERNET, owner))
        assertFalse(AppPreferences(context).qmplusEnabled)
        ensurePrivacyConsentForUiTest()
    }

    @Test fun themedPickerPreservesAllLanguagesAndTheSystemChoice() = scenario { scenario ->
        lateinit var panel: ViewGroup
        lateinit var dialog: Dialog
        var selected = ""
        scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_settings).performClick()
            assertTrue(activity.findViewById<View>(R.id.settings_language_selector).performClick())
            val page = MainActivity::class.java.getDeclaredField("settingsPage").apply { isAccessible = true }.get(activity)!!
            dialog = page.javaClass.getDeclaredField("languagePickerDialog").apply { isAccessible = true }.get(page) as Dialog
            assertFalse("The picker owns custom themed rows", dialog is android.app.AlertDialog)
            panel = dialog.window!!.decorView.findViewWithTag("settings.language.picker")
            assertNotNull(panel.background)
            assertEquals(activity.uiText("语言"), (panel.getChildAt(0) as TextView).text.toString())
            selected = AppPreferences(activity).languageCode
            AppLanguage.entries.forEach { language ->
                val row = panel.findViewWithTag<ViewGroup>("settings.language.option.${language.code}")
                assertNotNull(row)
                assertTrue(row.isClickable && row.isFocusable)
                assertEquals(language.code == selected, row.isSelected)
                assertEquals(AppLocale.displayName(activity, language), (row.getChildAt(0) as TextView).text.toString())
                assertEquals(if (row.isSelected) "✓" else "", (row.getChildAt(1) as TextView).text.toString())
            }
            assertEquals(14, AppLanguage.entries.size)
        }
        instrumentation.waitForIdleSync()
        scenario.onActivity { activity ->
            assertTrue(panel.width > 0 && panel.height > 0)
            assertTrue(panel.width <= activity.window.decorView.width)
            val image = Bitmap.createBitmap(panel.width, panel.height, Bitmap.Config.ARGB_8888)
            panel.draw(Canvas(image))
            File(context.cacheDir, "language-picker-panel.png").outputStream().use {
                image.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            image.recycle()
            println("WTS_LANGUAGE_PICKER width=${panel.width} height=${panel.height} options=14 theme=${Palette.selection.preset}")
            assertTrue(panel.findViewWithTag<View>("settings.language.option.$selected").performClick())
            assertFalse(dialog.isShowing)
            assertEquals("idle", activity.languageTransitionPhase())
        }
    }

    @Test fun nativeBlurIsVisibleUntilReadinessAndTheSuccessCoverReallyFades() =
        verifyBlur(forceLegacy = false)

    @Test fun legacyBlurUsesRealBlurredPixelsAndTheSameReadinessAndFadeSequence() =
        verifyBlur(forceLegacy = true)

    @Test fun reducedMotionKeepsReadinessAndAStaticSuccessMarkWithoutBlur() {
        val oldScale = device.executeShellCommand("settings get global animator_duration_scale").trim()
        device.executeShellCommand("settings put global animator_duration_scale 0")
        try {
            scenario { scenario ->
                val transition = LanguageChangeTransition()
                lateinit var host: FrameLayout
                var ready = false
                try {
                    scenario.onActivity { activity ->
                        host = FrameLayout(activity)
                        val content = Stripes(activity)
                        host.addView(content, FrameLayout.LayoutParams(-1, -1))
                        (activity.window.decorView as ViewGroup).addView(host, ViewGroup.LayoutParams(-1, -1))
                    }
                    instrumentation.waitForIdleSync()
                    scenario.onActivity { transition.request(host, host.getChildAt(0), "Synthetic switching", {}, { ready }) }
                    await { transition.phase == "waiting-layout" }
                    scenario.onActivity {
                        val cover = host.findViewWithTag<ViewGroup>("overlay.language-transition")
                        assertEquals("No snapshot layer is created for reduced motion", 2, cover.childCount)
                        ready = true
                    }
                    await { transition.phase == "complete" }
                    scenario.onActivity {
                        val cover = host.findViewWithTag<ViewGroup>("overlay.language-transition")
                        assertEquals(3, transition.readyFrameCount)
                        assertEquals(View.VISIBLE, (0 until cover.childCount).map(cover::getChildAt)
                            .filterIsInstance<LanguageSuccessMark>().single().visibility)
                    }
                    await { transition.phase == "idle" }
                } finally {
                    scenario.onActivity { transition.close(); (host.parent as? ViewGroup)?.removeView(host) }
                }
            }
        } finally { restoreScale(oldScale) }
    }

    @Test fun realLanguageChangeCompletesAfterLocalResourcesAndReturnsToTheSameSettingsOwner() {
        val preferences = AppPreferences(context)
        val previous = preferences.languageCode
        preferences.languageCode = AppLanguage.SIMPLIFIED_CHINESE.code
        try {
            scenario { scenario ->
                lateinit var owner: MainActivity
                scenario.onActivity {
                    owner = it
                    it.findViewById<View>(R.id.navigation_settings).performClick()
                    it.updateAppLanguage(AppLanguage.ENGLISH)
                }
                await { owner.languageTransitionPhase() == "complete" }
                scenario.onActivity {
                    assertSame(owner, it)
                    assertEquals(AppLanguage.ENGLISH, AppLocale.resolvedLanguage(it))
                    assertEquals(3, it.languageTransitionReadyFrames())
                    assertNotNull(it.findViewById<View>(R.id.settings_language_section))
                }
                await { owner.languageTransitionPhase() == "idle" }
                scenario.onActivity { activity ->
                    assertTrue(activity.findViewById<View>(R.id.settings_language_selector).performClick())
                    val page = MainActivity::class.java.getDeclaredField("settingsPage").apply { isAccessible = true }.get(activity)!!
                    val dialog = page.javaClass.getDeclaredField("languagePickerDialog").apply { isAccessible = true }.get(page) as Dialog
                    val panel = dialog.window!!.decorView.findViewWithTag<ViewGroup>("settings.language.picker")
                    assertEquals("Language", (panel.getChildAt(0) as TextView).text.toString())
                    dialog.dismiss()
                }
            }
        } finally { preferences.languageCode = previous }
    }

    private fun verifyBlur(forceLegacy: Boolean) {
        val oldScale = device.executeShellCommand("settings get global animator_duration_scale").trim()
        device.executeShellCommand("settings put global animator_duration_scale 1")
        try {
            scenario { scenario ->
                lateinit var host: FrameLayout
                lateinit var content: View
                val transition = LanguageChangeTransition(forceLegacyBlur = forceLegacy)
                var ready = false
                var applied = false
                var bounds = IntArray(4)
                try {
                scenario.onActivity { activity ->
                    host = FrameLayout(activity)
                    content = Stripes(activity)
                    host.addView(content, FrameLayout.LayoutParams(-1, -1))
                    (activity.window.decorView as ViewGroup).addView(host, ViewGroup.LayoutParams(-1, -1))
                }
                instrumentation.waitForIdleSync(); SystemClock.sleep(80)
                scenario.onActivity {
                    assertTrue(content.isHardwareAccelerated)
                    val location = IntArray(2).also(host::getLocationOnScreen)
                    bounds = intArrayOf(location[0], location[1], host.width, host.height)
                }
                val prefix = if (forceLegacy) "legacy" else "native"
                val before = captureSynthetic(bounds, "language-$prefix-clear.png")
                scenario.onActivity {
                    transition.request(host, content, "Synthetic switching", { applied = true }, { ready })
                }
                await { transition.phase == "waiting-layout" }
                assertTrue(applied)
                val after = captureSynthetic(bounds, "language-$prefix-blurred.png")
                val originalEdges = horizontalEdges(before)
                val blurredEdges = horizontalEdges(after)
                before.recycle(); after.recycle()
                assertTrue("The clear synthetic stripes must contain real edges", originalEdges > 12)
                assertTrue("Visible composed blur must reduce stripe contrast: $originalEdges -> $blurredEdges",
                    blurredEdges < originalEdges * .45)
                println("WTS_LANGUAGE_BLUR_PIXELS mode=$prefix clearEdges=$originalEdges blurredEdges=$blurredEdges")
                SystemClock.sleep(100)
                scenario.onActivity {
                    assertEquals("waiting-layout", transition.phase)
                    assertEquals(0, transition.readyFrameCount)
                    val cover = host.findViewWithTag<ViewGroup>("overlay.language-transition")
                    assertEquals(View.GONE, (0 until cover.childCount).map(cover::getChildAt)
                        .filterIsInstance<LanguageSuccessMark>().single().visibility)
                    ready = true
                }
                await { transition.phase == "complete" }
                scenario.onActivity {
                    assertEquals(3, transition.readyFrameCount)
                    val cover = host.findViewWithTag<ViewGroup>("overlay.language-transition")
                    assertEquals(View.VISIBLE, (0 until cover.childCount).map(cover::getChildAt)
                        .filterIsInstance<LanguageSuccessMark>().single().visibility)
                }
                var sampledAlpha = 1f
                await {
                    val cover = host.findViewWithTag<View>("overlay.language-transition")
                    if (transition.phase == "revealing" && cover != null && cover.alpha > 0f && cover.alpha < 1f) {
                        sampledAlpha = cover.alpha
                        true
                    } else false
                }
                assertTrue("The mark and cover fade along with blur", sampledAlpha > 0f && sampledAlpha < 1f)
                await { transition.phase == "idle" }
                scenario.onActivity {
                    assertNull(host.findViewWithTag<View?>("overlay.language-transition"))
                    transition.close(); (host.parent as ViewGroup).removeView(host)
                }
                println("WTS_LANGUAGE_BLUR mode=$prefix clearEdges=$originalEdges blurredEdges=$blurredEdges readyFrames=3 fade=PASS")
                } finally {
                    scenario.onActivity { transition.close(); (host.parent as? ViewGroup)?.removeView(host) }
                }
            }
        } finally { restoreScale(oldScale) }
    }

    private fun restoreScale(previous: String) {
        if (previous.matches(Regex("^[0-9]+(?:\\.[0-9]+)?$")))
            device.executeShellCommand("settings put global animator_duration_scale $previous")
        else device.executeShellCommand("settings delete global animator_duration_scale")
    }

    private fun captureSynthetic(bounds: IntArray, name: String): Bitmap {
        val screen = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        // A small ROI entirely inside the opaque synthetic host, away from labels and system bars.
        val sample = Bitmap.createBitmap(screen, bounds[0] + 24, bounds[1] + 120,
            minOf(320, bounds[2] - 48), 120)
        screen.recycle()
        File(context.cacheDir, name).outputStream().use { sample.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return sample
    }

    private fun horizontalEdges(image: Bitmap): Double {
        var difference = 0L
        var count = 0
        for (y in 10 until image.height - 10 step 10) for (x in 1 until image.width) {
            difference += kotlin.math.abs(Color.red(image.getPixel(x, y)) - Color.red(image.getPixel(x - 1, y)))
            count++
        }
        return difference.toDouble() / count
    }

    private fun await(predicate: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 3000
        while (SystemClock.elapsedRealtime() < until) {
            var ready = false
            instrumentation.runOnMainSync { ready = predicate() }
            if (ready) return
            SystemClock.sleep(10)
        }
        fail("LANGUAGE_PHASE_DID_NOT_SETTLE")
    }

    private fun scenario(block: (ActivityScenario<MainActivity>) -> Unit) {
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)).use(block)
    }

    private class Stripes(context: Context) : View(context) {
        private val paint = Paint()
        override fun onDraw(canvas: Canvas) {
            canvas.drawColor(Color.WHITE)
            var x = 0
            while (x < width) {
                paint.color = if (x / 12 % 2 == 0) Color.BLACK else Color.WHITE
                canvas.drawRect(x.toFloat(), 0f, (x + 12).toFloat(), height.toFloat(), paint)
                x += 12
            }
        }
    }
}
