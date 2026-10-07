package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AlmanacAdviceLayoutUiTest {
    @Before
    fun acceptPrivacyConsent() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val qaPackage = "com.nemoyu.wheretostudy.nativeapp.codexqa20261007gate"
        assumeTrue(InstrumentationRegistry.getArguments().getString("wtsIsolatedQa") == "true")
        assertTrue(BuildConfig.DEBUG)
        assertEquals(qaPackage, context.packageName)
        assertEquals("$qaPackage.test", instrumentation.context.packageName)
        for (packageName in listOf(qaPackage, "$qaPackage.test")) {
            assertEquals(PackageManager.PERMISSION_DENIED,
                context.packageManager.checkPermission(Manifest.permission.INTERNET, packageName))
        }
        ensurePrivacyConsentForUiTest()
    }

    @Test
    fun englishLabelsAndRawAdviceFitNarrowWidthsAndLargeFontsWithoutEllipsis() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val rawAdvice = "Study together, review coursework, prepare materials. API 原文保持完整。"
        instrumentation.runOnMainSync {
            for (fontScale in listOf(1f, 1.6f, 2f)) {
                val base = instrumentation.targetContext
                val context = base.createConfigurationContext(Configuration(base.resources.configuration).apply {
                    setLocale(Locale.ENGLISH)
                    this.fontScale = fontScale
                })
                for ((source, expected) in listOf("宜" to "Recommended", "忌" to "Avoid")) {
                    val row = buildAlmanacAdviceRow(context, source, rawAdvice, Palette.primaryText)
                    // Reuse the same native views across narrow/wide remeasurement.
                    for (widthDp in listOf(300, 160, 120, 300)) {
                        measureRow(row, context.dp(widthDp))
                        val label = row.findViewById<TextView>(R.id.calendar_almanac_advice_label)
                        val body = row.findViewById<TextView>(R.id.calendar_almanac_advice_text)
                        assertEquals(expected, label.text.toString())
                        assertEquals(rawAdvice, body.text.toString())
                        assertFullTextFits(row, label)
                        assertFullTextFits(row, body)
                        if (row.orientation == LinearLayout.HORIZONTAL) {
                            assertEquals(1, label.lineCount)
                            assertTrue(body.left >= label.right || body.right <= label.left)
                        } else {
                            assertTrue(body.top >= label.bottom)
                            assertEquals(row.width - row.paddingLeft - row.paddingRight, body.width)
                        }
                    }
                }
            }
        }
    }

    @Test
    fun labelTextChangesRecomputeTheNaturalWidthInsteadOfKeepingThePreviousLocaleWidth() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val row = buildAlmanacAdviceRow(context, "宜", "Synthetic unchanged API text", Palette.primaryText)
            val label = row.findViewById<TextView>(R.id.calendar_almanac_advice_label)
            label.text = "Avoid"
            measureRow(row, context.dp(300))
            val shortWidth = label.width
            label.text = "Recommended"
            measureRow(row, context.dp(300))
            assertTrue(label.width > shortWidth)
            assertEquals(1, label.lineCount)
            assertFullTextFits(row, label)
            label.text = "Avoid"
            measureRow(row, context.dp(300))
            assertEquals(shortWidth, label.width)
        }
    }

    private fun measureRow(row: LinearLayout, width: Int) {
        row.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        row.layout(0, 0, width, row.measuredHeight)
    }

    private fun assertFullTextFits(row: LinearLayout, text: TextView) {
        val layout = checkNotNull(text.layout)
        assertTrue(layout.lineCount > 0)
        assertEquals(text.text.length, layout.getLineEnd(layout.lineCount - 1))
        for (line in 0 until layout.lineCount) assertEquals(0, layout.getEllipsisCount(line))
        assertTrue(layout.height <= text.height - text.compoundPaddingTop - text.compoundPaddingBottom)
        assertTrue(text.left >= row.paddingLeft)
        assertTrue(text.right <= row.width - row.paddingRight)
        assertTrue(text.top >= row.paddingTop)
        assertTrue(text.bottom <= row.height - row.paddingBottom)
    }

    @Test
    fun longYiAndJiKeepEveryMeasuredLineInsideTheRoundedRow() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)
        val longAdvice =
            "学习交流制定计划复习课程整理资料开展团队协作准备竞赛材料完成阶段总结"

        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                listOf("宜" to Palette.primaryText, "忌" to Palette.danger).forEach { (label, color) ->
                    val row = buildAlmanacAdviceRow(activity, label, longAdvice, color)
                    val width = activity.dp(300)
                    row.measure(
                        View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                    )
                    row.layout(0, 0, width, row.measuredHeight)

                    val body = row.findViewById<TextView>(R.id.calendar_almanac_advice_text)
                    val textLayout = checkNotNull(body.layout)
                    assertTrue("$label advice must wrap to at least two real lines", body.lineCount >= 2)
                    assertTrue(
                        "$label second line must be inside the TextView layout",
                        textLayout.getLineBottom(1) <= textLayout.height,
                    )
                    assertTrue(
                        "$label full text layout must fit between TextView compound paddings",
                        textLayout.height <=
                            body.height - body.compoundPaddingTop - body.compoundPaddingBottom,
                    )
                    assertTrue(
                        "$label body top must stay below the rounded-row top padding",
                        body.top >= row.paddingTop,
                    )
                    assertTrue(
                        "$label body bottom must stay above the rounded-row bottom padding",
                        body.bottom <= row.height - row.paddingBottom,
                    )
                    assertTrue(
                        "$label row must measure enough height for body and vertical padding",
                        row.measuredHeight >= row.paddingTop + body.measuredHeight + row.paddingBottom,
                    )
                }
            }
        }
    }
}
