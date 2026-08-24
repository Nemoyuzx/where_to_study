package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AlmanacAdviceLayoutUiTest {
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
