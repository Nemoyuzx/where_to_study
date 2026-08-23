package com.nemoyu.wheretostudy.nativeapp

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

data class YearCalendarDay(
    val date: Calendar,
    val courseCount: Int,
    val holidays: List<HolidayItem>,
)

object YearCalendarLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun columns(screenWidthDp: Int): Int = when {
        screenWidthDp >= 1100 -> 4
        screenWidthDp >= 700 -> 3
        else -> 2
    }

    fun dayNumber(year: Int, month: Int, row: Int, column: Int): Int? {
        if (month !in 1..12 || row !in 0..5 || column !in 0..6) return null
        val first = Calendar.getInstance(shanghai).apply {
            set(year, month - 1, 1, 12, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val leadingDays = (first.get(Calendar.DAY_OF_WEEK) + 5) % 7
        val candidate = row * 7 + column - leadingDays + 1
        return candidate.takeIf { it in 1..first.getActualMaximum(Calendar.DAY_OF_MONTH) }
    }
}

@SuppressLint("ViewConstructor")
class YearCalendarView(
    context: Context,
    private val year: Int,
    days: List<YearCalendarDay>,
    private val availableWidthDp: Int,
    private val onDateSelected: (YearCalendarView, Calendar, Float, Float) -> Unit,
    private val onMonthSelected: (Calendar) -> Unit,
) : View(context) {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val dayByKey = days.associateBy { key(it.date) }
    private val columns = YearCalendarLogic.columns(availableWidthDp)
    private val monthTitleHeight = dp(28).toFloat()
    private val weekdayHeight = dp(14).toFloat()
    private val dayCellHeight = dp(26).toFloat()
    private val monthGap = dp(16).toFloat()
    private val monthBottomGap = dp(18).toFloat()
    private val monthHeight = monthTitleHeight + weekdayHeight + dayCellHeight * 6 + monthBottomGap
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Palette.border
        style = Paint.Style.STROKE
        strokeWidth = dp(1).toFloat()
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Palette.text
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
    private val boldPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Palette.text
        textAlign = Paint.Align.LEFT
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private var selectedDate: Calendar? = null
    private var downX = 0f
    private var downY = 0f

    init {
        isClickable = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        val courseCount = days.sumOf(YearCalendarDay::courseCount)
        contentDescription = if (AppLocale.isEnglish(context)) {
            "$year course distribution, $courseCount course occurrences; tap a date for details"
        } else {
            "$year 年课程分布，共 $courseCount 门次；点击日期查看日程"
        }
    }

    fun selectDate(date: Calendar?) {
        selectedDate = date?.clone() as? Calendar
        invalidate()
    }

    fun clearSelection() {
        if (selectedDate == null) return
        selectedDate = null
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val preferredWidth = dp(availableWidthDp - 40)
        val measuredWidth = resolveSize(preferredWidth.coerceAtLeast(dp(280)), widthMeasureSpec)
        val rowCount = (12 + columns - 1) / columns
        val preferredHeight = (monthHeight * rowCount).toInt()
        setMeasuredDimension(measuredWidth, resolveSize(preferredHeight, heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val monthWidth = monthWidth()
        repeat(12) { monthIndex ->
            val column = monthIndex % columns
            val row = monthIndex / columns
            drawMonth(
                canvas = canvas,
                month = monthIndex + 1,
                left = column * (monthWidth + monthGap),
                top = row * monthHeight,
                monthWidth = monthWidth,
            )
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                return true
            }

            MotionEvent.ACTION_UP -> {
                if (abs(event.x - downX) <= touchSlop && abs(event.y - downY) <= touchSlop) {
                    val date = dateAt(event.x, event.y)
                    if (date != null) {
                        performClick()
                        onDateSelected(this, date, event.x, event.y)
                    } else {
                        monthAtHeader(event.x, event.y)?.let { month ->
                            performClick()
                            onMonthSelected(month)
                        }
                    }
                }
                return true
            }

            MotionEvent.ACTION_CANCEL -> return false
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    private fun drawMonth(
        canvas: Canvas,
        month: Int,
        left: Float,
        top: Float,
        monthWidth: Float,
    ) {
        boldPaint.textSize = sp(17f)
        boldPaint.color = Palette.text
        boldPaint.textAlign = Paint.Align.LEFT
        val monthTitle = if (AppLocale.isEnglish(context)) {
            java.text.DateFormatSymbols(Locale.US).shortMonths[month - 1]
        } else {
            "$month 月"
        }
        drawCenteredText(canvas, monthTitle, left, top + monthTitleHeight / 2f, boldPaint)

        textPaint.textSize = sp(8f)
        textPaint.color = Palette.muted
        textPaint.textAlign = Paint.Align.CENTER
        val cellWidth = monthWidth / 7f
        val weekdays = if (AppLocale.isEnglish(context)) WEEKDAYS_EN else WEEKDAYS_ZH
        weekdays.forEachIndexed { index, label ->
            drawCenteredText(
                canvas,
                label,
                left + cellWidth * (index + 0.5f),
                top + monthTitleHeight + weekdayHeight / 2f,
                textPaint,
            )
        }

        val gridTop = top + monthTitleHeight + weekdayHeight
        repeat(6) { row ->
            repeat(7) dayColumn@{ column ->
                val dayNumber = YearCalendarLogic.dayNumber(year, month, row, column) ?: return@dayColumn
                val date = calendar(month, dayNumber)
                val day = dayByKey[key(date)] ?: YearCalendarDay(date, 0, emptyList())
                val rect = RectF(
                    left + column * cellWidth + dp(1),
                    gridTop + row * dayCellHeight + dp(1),
                    left + (column + 1) * cellWidth - dp(1),
                    gridTop + (row + 1) * dayCellHeight - dp(1),
                )
                drawDay(canvas, rect, day)
            }
        }
    }

    private fun drawDay(canvas: Canvas, rect: RectF, day: YearCalendarDay) {
        val selected = selectedDate?.let { sameDay(it, day.date) } == true
        val today = sameDay(day.date, Calendar.getInstance(shanghai))
        fillPaint.color = when {
            selected -> Palette.primaryFill
            day.courseCount <= 0 -> Palette.background
            else -> blend(
                foreground = Palette.primary,
                background = Palette.background,
                amount = TeachingCalendarLogic.yearCourseOpacity(day.courseCount),
            )
        }
        canvas.drawRoundRect(rect, dp(4).toFloat(), dp(4).toFloat(), fillPaint)

        borderPaint.color = if (today) Palette.primary else Palette.border
        borderPaint.strokeWidth = resources.displayMetrics.density * if (today) 1.5f else 0.32f
        canvas.drawRoundRect(rect, dp(4).toFloat(), dp(4).toFloat(), borderPaint)

        textPaint.textAlign = Paint.Align.CENTER
        textPaint.color = if (selected) Palette.onPrimary else Palette.text
        textPaint.textSize = sp(8f)
        textPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        drawCenteredText(
            canvas,
            day.date.get(Calendar.DAY_OF_MONTH).toString(),
            rect.centerX(),
            rect.centerY(),
            textPaint,
        )
    }

    private fun dateAt(x: Float, y: Float): Calendar? {
        if (x !in 0f..width.toFloat() || y !in 0f..height.toFloat()) return null
        val monthWidth = monthWidth()
        val monthStride = monthWidth + monthGap
        val monthColumn = (x / monthStride).toInt().coerceAtMost(columns - 1)
        val monthRow = (y / monthHeight).toInt()
        val monthIndex = monthRow * columns + monthColumn
        if (monthIndex !in 0..11) return null

        val localX = x - monthColumn * monthStride
        if (localX < 0f || localX >= monthWidth) return null
        val localY = y - monthRow * monthHeight - monthTitleHeight - weekdayHeight
        if (localY < 0f || localY >= dayCellHeight * 6f) return null
        val column = (localX / (monthWidth / 7f)).toInt().coerceAtMost(6)
        val row = (localY / dayCellHeight).toInt().coerceAtMost(5)
        val day = YearCalendarLogic.dayNumber(year, monthIndex + 1, row, column) ?: return null
        return calendar(monthIndex + 1, day)
    }

    private fun monthAtHeader(x: Float, y: Float): Calendar? {
        if (x !in 0f..width.toFloat() || y !in 0f..height.toFloat()) return null
        val monthWidth = monthWidth()
        val monthStride = monthWidth + monthGap
        val monthColumn = (x / monthStride).toInt().coerceAtMost(columns - 1)
        val monthRow = (y / monthHeight).toInt()
        val monthIndex = monthRow * columns + monthColumn
        if (monthIndex !in 0..11) return null
        val localX = x - monthColumn * monthStride
        val localY = y - monthRow * monthHeight
        if (localX !in 0f..monthWidth || localY !in 0f..monthTitleHeight) return null
        return calendar(monthIndex + 1, 1)
    }

    private fun monthWidth(): Float =
        (width.toFloat() - monthGap * (columns - 1)) / columns

    private fun calendar(month: Int, day: Int): Calendar = Calendar.getInstance(shanghai).apply {
        set(year, month - 1, day, 12, 0, 0)
        set(Calendar.MILLISECOND, 0)
    }

    private fun key(date: Calendar): String = String.format(
        Locale.US,
        "%04d-%02d-%02d",
        date.get(Calendar.YEAR),
        date.get(Calendar.MONTH) + 1,
        date.get(Calendar.DAY_OF_MONTH),
    )

    private fun sameDay(left: Calendar, right: Calendar): Boolean =
        left.get(Calendar.ERA) == right.get(Calendar.ERA) &&
            left.get(Calendar.YEAR) == right.get(Calendar.YEAR) &&
            left.get(Calendar.DAY_OF_YEAR) == right.get(Calendar.DAY_OF_YEAR)

    private fun drawCenteredText(canvas: Canvas, value: String, x: Float, y: Float, paint: Paint) {
        canvas.drawText(value, x, y - (paint.ascent() + paint.descent()) / 2f, paint)
    }

    private fun blend(foreground: Int, background: Int, amount: Float): Int = Color.rgb(
        (Color.red(background) + (Color.red(foreground) - Color.red(background)) * amount).toInt(),
        (Color.green(background) + (Color.green(foreground) - Color.green(background)) * amount).toInt(),
        (Color.blue(background) + (Color.blue(foreground) - Color.blue(background)) * amount).toInt(),
    )

    private fun dp(value: Int): Int = context.dp(value)

    private fun sp(value: Float): Float = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP,
        value,
        resources.displayMetrics,
    )

    private companion object {
        val WEEKDAYS_ZH = listOf("一", "二", "三", "四", "五", "六", "日")
        val WEEKDAYS_EN = listOf("M", "T", "W", "T", "F", "S", "S")
    }
}
