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
        screenWidthDp >= 480 -> 2
        else -> 1
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
) : View(context) {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val dayByKey = days.associateBy { key(it.date) }
    private val columns = YearCalendarLogic.columns(availableWidthDp)
    private val monthTitleHeight = dp(28).toFloat()
    private val weekdayHeight = dp(20).toFloat()
    private val dayCellHeight = dp(34).toFloat()
    private val monthGap = dp(12).toFloat()
    private val monthBottomGap = dp(16).toFloat()
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
        contentDescription = "$year 年课程分布，共 $courseCount 门次；点击日期查看日程"
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
        val monthStride = width.toFloat() / columns
        val monthWidth = monthStride - monthGap
        repeat(12) { monthIndex ->
            val column = monthIndex % columns
            val row = monthIndex / columns
            drawMonth(
                canvas = canvas,
                month = monthIndex + 1,
                left = column * monthStride,
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
                    dateAt(event.x, event.y)?.let { date ->
                        performClick()
                        onDateSelected(this, date, event.x, event.y)
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
        boldPaint.textSize = sp(15f)
        boldPaint.color = Palette.text
        boldPaint.textAlign = Paint.Align.LEFT
        drawCenteredText(canvas, "$month 月", left + dp(3), top + monthTitleHeight / 2f, boldPaint)

        textPaint.textSize = sp(9f)
        textPaint.color = Palette.muted
        textPaint.textAlign = Paint.Align.CENTER
        val cellWidth = monthWidth / 7f
        WEEKDAYS.forEachIndexed { index, label ->
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
                background = Palette.surface,
                amount = TeachingCalendarLogic.yearCourseOpacity(day.courseCount),
            )
        }
        canvas.drawRoundRect(rect, dp(3).toFloat(), dp(3).toFloat(), fillPaint)

        borderPaint.color = if (today) Palette.nowIndicator else Palette.border
        borderPaint.strokeWidth = dp(if (today) 2 else 1).toFloat()
        canvas.drawRoundRect(rect, dp(3).toFloat(), dp(3).toFloat(), borderPaint)

        val holiday = day.holidays.firstOrNull()
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.color = when {
            selected -> Palette.onPrimary
            holiday?.type == "holiday" -> Palette.holiday
            holiday?.type == "workday" -> Palette.primaryText
            else -> Palette.text
        }
        if (holiday == null) {
            textPaint.textSize = sp(9f)
            drawCenteredText(canvas, day.date.get(Calendar.DAY_OF_MONTH).toString(), rect.centerX(), rect.centerY(), textPaint)
            return
        }

        textPaint.textSize = sp(9f)
        textPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        drawCenteredText(
            canvas,
            day.date.get(Calendar.DAY_OF_MONTH).toString(),
            rect.centerX(),
            rect.centerY() - dp(6),
            textPaint,
        )
        textPaint.textSize = sp(8f)
        drawCenteredText(
            canvas,
            if (holiday.type == "holiday") "休" else "班",
            rect.centerX(),
            rect.centerY() + dp(7),
            textPaint,
        )
        textPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }

    private fun dateAt(x: Float, y: Float): Calendar? {
        if (x !in 0f..width.toFloat() || y !in 0f..height.toFloat()) return null
        val monthStride = width.toFloat() / columns
        val monthColumn = (x / monthStride).toInt().coerceAtMost(columns - 1)
        val monthRow = (y / monthHeight).toInt()
        val monthIndex = monthRow * columns + monthColumn
        if (monthIndex !in 0..11) return null

        val monthWidth = monthStride - monthGap
        val localX = x - monthColumn * monthStride
        if (localX < 0f || localX >= monthWidth) return null
        val localY = y - monthRow * monthHeight - monthTitleHeight - weekdayHeight
        if (localY < 0f || localY >= dayCellHeight * 6f) return null
        val column = (localX / (monthWidth / 7f)).toInt().coerceAtMost(6)
        val row = (localY / dayCellHeight).toInt().coerceAtMost(5)
        val day = YearCalendarLogic.dayNumber(year, monthIndex + 1, row, column) ?: return null
        return calendar(monthIndex + 1, day)
    }

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
        val WEEKDAYS = listOf("一", "二", "三", "四", "五", "六", "日")
    }
}
