package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import kotlin.math.ceil

data class WidgetLayoutSpec(
    val capacity: Int,
    val paddingDp: Int,
    val showsDate: Boolean,
    val showsCount: Boolean,
    val showsDetails: Boolean,
    val showsMore: Boolean,
)

/** Measure the same sp text used by the launcher; Android 14's non-linear scaling is respected. */
internal object TodayCourseWidgetLayout {
    fun textPixels(context: Context, sp: Float): Float = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP, sp, context.resources.displayMetrics,
    )

    fun forSize(context: Context, content: TodayCourseWidgetContent, widthDp: Int, heightDp: Int,
        courseLimit: Int): WidgetLayoutSpec {
        val density = context.resources.displayMetrics.density
        val localized = AppLocale.wrap(context, AppPreferences(context).languageCode)
        fun paint(sp: Float, bold: Boolean = false) = TextPaint().apply {
            textSize = textPixels(context, sp)
            typeface = Typeface.create("sans", if (bold) Typeface.BOLD else Typeface.NORMAL)
        }
        fun line(sp: Float, bold: Boolean = false): Int {
            // CJK course/location names can use a taller fallback font than the Latin base face.
            val probe = "课程 Ag"
            val builder = StaticLayout.Builder.obtain(probe, 0, probe.length, paint(sp, bold), 10_000)
                .setIncludePad(false).setMaxLines(1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) builder.setUseLineSpacingFromFallbacks(true)
            return ceil(builder.build().height / density).toInt()
        }
        val height = heightDp.takeIf { it > 0 } ?: 205
        val width = widthDp.takeIf { it > 0 } ?: 250
        val padding = if (height < 160) 8 else 12
        val header = maxOf(24, line(14f, true), line(11f, true))
        val available = height - padding * 2 - header - 4
        val fullRow = maxOf(40, line(13f, true) + line(10f) + 2)
        val details = fullRow <= available
        val row = if (details) fullRow else maxOf(40, line(13f, true) + 2)
        val date = available - line(10f) - 2 >= row
        val rowSpace = available - if (date) line(10f) + 2 else 0
        val capacity = (rowSpace / row).coerceIn(1, courseLimit.coerceIn(1, 6))
        val displayedToday = minOf(content.courses.size, capacity)
        val more = content.courses.size > displayedToday && rowSpace >= capacity * row + line(10f) + 2
        val titleWidth = paint(14f, true).measureText(localized.getString(R.string.widget_today_course_title)) / density
        val count = localized.getString(R.string.widget_today_tomorrow_count_format,
            content.courses.size, content.tomorrowCourses.size)
        val countWidth = paint(11f, true).measureText(count) / density
        return WidgetLayoutSpec(capacity, padding, date,
            width - padding * 2 - 25 >= titleWidth + countWidth + 8, details, more)
    }
}
