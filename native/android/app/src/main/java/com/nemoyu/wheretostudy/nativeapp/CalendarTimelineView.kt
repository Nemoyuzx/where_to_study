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
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class TimelineDay(
    val date: Calendar,
    val courses: List<Course>,
    val holidays: List<HolidayItem>,
)

object CalendarTimelineLogic {
    const val startMinute = 8 * 60
    const val endMinute = 22 * 60

    fun minuteOfDay(value: String): Int? {
        val parts = value.split(':')
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        return hour * 60 + minute
    }

    fun position(minute: Int): Float =
        ((minute - startMinute).toFloat() / (endMinute - startMinute))
            .coerceIn(0f, 1f)

    fun hourLabelIsObscured(
        hourMinute: Int,
        currentMinute: Int,
        threshold: Int = 12,
    ): Boolean = abs(hourMinute - currentMinute) <= threshold

    fun dayColumnBounds(
        dayIndex: Int,
        dayWidth: Float,
        contentWidth: Float,
    ): Pair<Float, Float> {
        val left = dayWidth * dayIndex.coerceAtLeast(0)
        return left to min(left + dayWidth, contentWidth)
    }

    fun axisWidthDp(compact: Boolean, showCourseSlots: Boolean = true): Int {
        val hourWidth = if (compact) 42 else 48
        val slotWidth = if (compact) 70 else 96
        return hourWidth + if (showCourseSlots) slotWidth else 0
    }

    fun dayWidthDp(compact: Boolean): Int = if (compact) 132 else 156

    // Compact week columns stay fixed to the phone viewport; the extra vertical room keeps
    // course metadata readable after it is split into separate lines.
    fun hourHeightDp(compact: Boolean): Int = if (compact) 84 else 68

    fun totalHeightDp(compact: Boolean, showDayHeader: Boolean): Int =
        (if (showDayHeader) 72 else 0) + hourHeightDp(compact) * 14 + 2
}

@SuppressLint("ViewConstructor")
class CalendarTimelineView(
    context: Context,
    days: List<TimelineDay>,
    selectedDate: Calendar,
    onDaySelected: ((Calendar) -> Unit)? = null,
    compact: Boolean = false,
    showDayHeader: Boolean = true,
) : LinearLayout(context) {
    init {
        orientation = HORIZONTAL
        isBaselineAligned = false
        setBackgroundColor(Palette.surface)

        val totalHeight = context.dp(CalendarTimelineLogic.totalHeightDp(compact, showDayHeader))
        val showCourseSlots = !compact || days.size == 1
        addView(
            CalendarTimelineCanvas(
                context = context,
                layer = TimelineLayer.AXIS,
                days = days,
                selectedDate = selectedDate,
                compact = compact,
                showDayHeader = showDayHeader,
                showCourseSlots = showCourseSlots,
            ),
            LayoutParams(
                context.dp(CalendarTimelineLogic.axisWidthDp(compact, showCourseSlots)),
                totalHeight,
            ),
        )

        val dayCanvas = CalendarTimelineCanvas(
            context = context,
            layer = TimelineLayer.DAYS,
            days = days,
            selectedDate = selectedDate,
            onDaySelected = onDaySelected,
            compact = compact,
            showDayHeader = showDayHeader,
            showCourseSlots = showCourseSlots,
        )
        if (compact) {
            addView(dayCanvas, LayoutParams(0, totalHeight, 1f))
        } else {
            val preferredDayWidth = context.dp(
                days.size.coerceAtLeast(1) * CalendarTimelineLogic.dayWidthDp(compact),
            )
            addView(
                HorizontalScrollView(context).apply {
                    id = R.id.calendar_timeline_day_scroll
                    isFillViewport = true
                    isHorizontalScrollBarEnabled = false
                    overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
                    addView(
                        dayCanvas,
                        ViewGroup.LayoutParams(preferredDayWidth, totalHeight),
                    )
                },
                LayoutParams(0, totalHeight, 1f),
            )
        }
    }
}

private enum class TimelineLayer {
    AXIS,
    DAYS,
}

@SuppressLint("ViewConstructor")
private class CalendarTimelineCanvas(
    context: Context,
    private val layer: TimelineLayer,
    private val days: List<TimelineDay>,
    private val selectedDate: Calendar,
    private val onDaySelected: ((Calendar) -> Unit)? = null,
    private val compact: Boolean,
    private val showDayHeader: Boolean,
    private val showCourseSlots: Boolean,
) : View(context) {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Palette.border
        strokeWidth = dp(1).toFloat()
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Palette.muted
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
    private val boldPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Palette.text
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val hourAxisWidth = dp(if (compact) 42 else 48).toFloat()
    private val slotAxisWidth = if (showCourseSlots) dp(if (compact) 70 else 96).toFloat() else 0f
    private val axisWidth = hourAxisWidth + slotAxisWidth
    private val headerHeight = dp(if (showDayHeader) 72 else 0).toFloat()
    private val hourHeight = dp(CalendarTimelineLogic.hourHeightDp(compact)).toFloat()
    private val timelineHeight = hourHeight * 14f
    private val totalHeight = headerHeight + timelineHeight + dp(2)
    private val minuteInvalidation = object : Runnable {
        override fun run() {
            invalidate()
            postDelayed(this, 60_000L)
        }
    }

    init {
        isFocusable = true
        isClickable = layer == TimelineLayer.DAYS && onDaySelected != null
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = if (layer == TimelineLayer.AXIS) {
            buildAxisContentDescription()
        } else {
            buildDayContentDescription()
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val preferredWidth = when (layer) {
            TimelineLayer.AXIS -> axisWidth.toInt()
            TimelineLayer.DAYS -> if (days.size > 1) {
                dp(days.size * CalendarTimelineLogic.dayWidthDp(compact))
            } else {
                dp(160)
            }
        }
        setMeasuredDimension(
            resolveSize(preferredWidth, widthMeasureSpec),
            resolveSize(totalHeight.toInt(), heightMeasureSpec),
        )
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        removeCallbacks(minuteInvalidation)
        postDelayed(minuteInvalidation, 60_000L)
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(minuteInvalidation)
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(Palette.surface)
        when (layer) {
            TimelineLayer.AXIS -> drawAxis(canvas)
            TimelineLayer.DAYS -> drawDays(canvas)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (layer != TimelineLayer.DAYS || onDaySelected == null || days.isEmpty()) return false
        if (showDayHeader && event.action == MotionEvent.ACTION_UP && event.y <= headerHeight) {
            val dayWidth = width.toFloat() / days.size
            val index = (event.x / dayWidth).toInt().coerceIn(days.indices)
            onDaySelected.invoke(days[index].date.clone() as Calendar)
            performClick()
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    private fun drawAxis(canvas: Canvas) {
        if (showDayHeader) {
            fillPaint.color = Palette.background
            canvas.drawRect(0f, 0f, width.toFloat(), headerHeight, fillPaint)
            boldPaint.color = Palette.text
            boldPaint.textAlign = Paint.Align.CENTER
            boldPaint.textSize = sp(12f)
            drawCenteredText(canvas, "整点", hourAxisWidth / 2f, headerHeight / 2f, boldPaint)
            if (showCourseSlots) {
                drawCenteredText(
                    canvas,
                    "课程节次",
                    hourAxisWidth + slotAxisWidth / 2f,
                    headerHeight / 2f,
                    boldPaint,
                )
            }
        }

        canvas.drawLine(0f, headerHeight, width.toFloat(), headerHeight, linePaint)
        if (showCourseSlots) {
            canvas.drawLine(hourAxisWidth, 0f, hourAxisWidth, totalHeight, linePaint)
        }
        canvas.drawLine(width.toFloat(), 0f, width.toFloat(), totalHeight, linePaint)

        val currentMinute = currentMinuteIfVisible()
        textPaint.color = Palette.muted
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.textSize = sp(if (compact) 10f else 11f)
        for (hour in 8..22) {
            val hourMinute = hour * 60
            val y = yForMinute(hourMinute)
            canvas.drawLine(0f, y, width.toFloat(), y, linePaint)
            if (currentMinute != null && CalendarTimelineLogic.hourLabelIsObscured(hourMinute, currentMinute)) {
                continue
            }
            val labelY = when (hour) {
                8 -> y + dp(11)
                22 -> y - dp(5)
                else -> y - dp(4)
            }
            drawCenteredText(canvas, "%02d:00".format(hour), hourAxisWidth / 2f, labelY, textPaint)
        }

        if (showCourseSlots) {
            AppMetadata.slots.forEach { slot ->
                val start = CalendarTimelineLogic.minuteOfDay(slot.start) ?: return@forEach
                val end = CalendarTimelineLogic.minuteOfDay(slot.end) ?: return@forEach
                val centerY = (yForMinute(start) + yForMinute(end)) / 2f
                boldPaint.color = Palette.muted
                boldPaint.textAlign = Paint.Align.CENTER
                boldPaint.textSize = sp(if (compact) 9.5f else 11f)
                textPaint.color = Palette.muted
                textPaint.textSize = sp(if (compact) 7.5f else 9f)
                drawCenteredText(
                    canvas,
                    "第 ${slot.label} 节",
                    hourAxisWidth + slotAxisWidth / 2f,
                    centerY - dp(7),
                    boldPaint,
                )
                drawCenteredText(
                    canvas,
                    "${slot.start}-${slot.end}",
                    hourAxisWidth + slotAxisWidth / 2f,
                    centerY + dp(8),
                    textPaint,
                )
            }
        }

        if (currentMinute != null) drawCurrentTimeAxisLabel(canvas, currentMinute)
    }

    private fun drawDays(canvas: Canvas) {
        val dayWidth = width.toFloat() / days.size.coerceAtLeast(1)
        drawDayGridAndHeaders(canvas, dayWidth)
        drawCourseBlocks(canvas, dayWidth)
        drawCurrentTimeLine(canvas, dayWidth)
    }

    private fun drawDayGridAndHeaders(canvas: Canvas, dayWidth: Float) {
        if (showDayHeader) {
            fillPaint.color = Palette.background
            canvas.drawRect(0f, 0f, width.toFloat(), headerHeight, fillPaint)

            days.forEachIndexed { index, day ->
                if (sameDay(day.date, selectedDate)) {
                    fillPaint.color = blend(Palette.primary, Palette.surface, 0.10f)
                    val left = dayWidth * index
                    canvas.drawRect(left, 0f, left + dayWidth, headerHeight, fillPaint)
                }
            }
        }

        for (hour in 8..22) {
            val y = yForMinute(hour * 60)
            canvas.drawLine(0f, y, width.toFloat(), y, linePaint)
        }
        for (index in 0..days.size) {
            val x = dayWidth * index
            canvas.drawLine(x, 0f, x, totalHeight, linePaint)
        }
        canvas.drawLine(0f, headerHeight, width.toFloat(), headerHeight, linePaint)

        if (showDayHeader) {
            val formatter = SimpleDateFormat("M/d E", Locale.CHINA).apply { timeZone = shanghai }
            days.forEachIndexed { index, day ->
                val left = dayWidth * index
                val right = left + dayWidth
                boldPaint.color = Palette.text
                boldPaint.textAlign = Paint.Align.CENTER
                boldPaint.textSize = sp(13f)
                drawCenteredText(
                    canvas,
                    formatter.format(day.date.time),
                    (left + right) / 2f,
                    dp(24).toFloat(),
                    boldPaint,
                )

                val badge = holidayBadge(day.holidays)
                textPaint.color = when {
                    day.holidays.any { it.type == "holiday" } -> Palette.holiday
                    day.holidays.any { it.type == "workday" } -> Palette.primaryText
                    day.courses.isEmpty() -> Palette.muted
                    else -> Palette.primaryText
                }
                textPaint.textAlign = Paint.Align.CENTER
                textPaint.textSize = sp(10f)
                val detail = badge.ifEmpty { if (day.courses.isEmpty()) "无课" else "${day.courses.size} 门课" }
                drawCenteredText(
                    canvas,
                    ellipsize(detail, dayWidth - dp(8), textPaint),
                    (left + right) / 2f,
                    dp(49).toFloat(),
                    textPaint,
                )
                if (sameDay(day.date, Calendar.getInstance(shanghai))) {
                    fillPaint.color = Palette.nowIndicator
                    canvas.drawRect(left + dp(6), headerHeight - dp(3), right - dp(6), headerHeight, fillPaint)
                }
            }
        }
    }

    private fun drawCourseBlocks(canvas: Canvas, dayWidth: Float) {
        days.forEachIndexed { dayIndex, day ->
            val dayLeft = dayWidth * dayIndex
            val placements = placeCourses(day.courses)
            val tracks = placements.maxOfOrNull { it.track + 1 } ?: 1
            placements.forEach { placement ->
                val trackWidth = dayWidth / tracks
                val outerInset = dp(if (days.size == 1) 3 else 1)
                val contentInset = dp(if (days.size == 1) 6 else 2)
                val left = dayLeft + trackWidth * placement.track + outerInset
                val right = left + trackWidth - outerInset * 2
                val start = AppMetadata.slots.getOrNull(placement.course.startSlot)?.start
                    ?.let(CalendarTimelineLogic::minuteOfDay) ?: return@forEach
                val end = AppMetadata.slots.getOrNull(placement.course.endSlot)?.end
                    ?.let(CalendarTimelineLogic::minuteOfDay) ?: return@forEach
                val top = yForMinute(start) + dp(2)
                val bottom = max(top + dp(34), yForMinute(end) - dp(2))
                fillPaint.color = if (placement.track == 0) Palette.primary else Palette.primaryDark
                canvas.drawRoundRect(RectF(left, top, right, bottom), dp(5).toFloat(), dp(5).toFloat(), fillPaint)

                canvas.save()
                canvas.clipRect(left, top, right, bottom)
                boldPaint.color = Palette.onPrimary
                boldPaint.textAlign = Paint.Align.LEFT
                val singleDay = days.size == 1
                val blockHeight = bottom - top
                boldPaint.textSize = sp(if (singleDay) 13f else 10.5f)
                textPaint.color = Palette.onPrimary
                textPaint.textAlign = Paint.Align.LEFT
                textPaint.textSize = sp(if (singleDay) 11f else 9.5f)
                val availableWidth = right - left - contentInset * 2
                if (singleDay) {
                    canvas.drawText(
                        ellipsize(placement.course.name, availableWidth, boldPaint),
                        left + contentInset,
                        top + dp(17),
                        boldPaint,
                    )
                    if (blockHeight >= dp(42)) {
                        canvas.drawText(
                            ellipsize(placement.course.timeRange, availableWidth, textPaint),
                            left + contentInset,
                            top + dp(33),
                            textPaint,
                        )
                    }
                    if (blockHeight >= dp(60)) {
                        canvas.drawText(
                            ellipsize(placement.course.room, availableWidth, textPaint),
                            left + contentInset,
                            top + dp(49),
                            textPaint,
                        )
                    }
                    if (blockHeight >= dp(76) && placement.course.teacher.isNotEmpty()) {
                        canvas.drawText(
                            ellipsize(placement.course.teacher, availableWidth, textPaint),
                            left + contentInset,
                            top + dp(65),
                            textPaint,
                        )
                    }
                } else {
                    var baseline = top + dp(12)
                    val lineStep = dp(11).toFloat()
                    val maximumBaseline = bottom - dp(2)
                    fun drawLines(value: String, paint: Paint, maximumLines: Int) {
                        if (value.isEmpty() || baseline > maximumBaseline) return
                        wrapText(value, availableWidth, paint, maximumLines).forEach { line ->
                            if (baseline <= maximumBaseline) {
                                canvas.drawText(line, left + contentInset, baseline, paint)
                                baseline += lineStep
                            }
                        }
                    }
                    drawLines(placement.course.name, boldPaint, 1)
                    drawLines(placement.course.timeRange, textPaint, 1)
                    drawLines(placement.course.room, textPaint, 2)
                    drawLines(placement.course.teacher, textPaint, 2)
                }
                canvas.restore()
            }
        }
    }

    private fun drawCurrentTimeLine(canvas: Canvas, dayWidth: Float) {
        val now = Calendar.getInstance(shanghai)
        val todayIndex = days.indexOfFirst { sameDay(it.date, now) }
        if (todayIndex < 0) return
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        if (minute !in CalendarTimelineLogic.startMinute..CalendarTimelineLogic.endMinute) return
        val y = yForMinute(minute)
        val (left, right) = CalendarTimelineLogic.dayColumnBounds(
            dayIndex = todayIndex,
            dayWidth = dayWidth,
            contentWidth = width.toFloat(),
        )
        fillPaint.color = Palette.nowIndicator
        canvas.drawRect(left, y - dp(1), right, y + dp(1), fillPaint)
        canvas.drawCircle(left, y, dp(4).toFloat(), fillPaint)
    }

    private fun drawCurrentTimeAxisLabel(canvas: Canvas, minute: Int) {
        val now = Calendar.getInstance(shanghai)
        val label = "%02d:%02d".format(now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE))
        val y = yForMinute(minute)
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.textSize = sp(10f)
        val labelWidth = max(dp(38).toFloat(), textPaint.measureText(label) + dp(8))
        val halfHeight = dp(9).toFloat()
        fillPaint.color = Palette.nowIndicator
        canvas.drawRoundRect(
            RectF(
                hourAxisWidth / 2f - labelWidth / 2f,
                y - halfHeight,
                hourAxisWidth / 2f + labelWidth / 2f,
                y + halfHeight,
            ),
            halfHeight,
            halfHeight,
            fillPaint,
        )
        textPaint.color = Palette.onPrimary
        drawCenteredText(canvas, label, hourAxisWidth / 2f, y, textPaint)
    }

    private fun currentMinuteIfVisible(): Int? {
        val now = Calendar.getInstance(shanghai)
        if (days.none { sameDay(it.date, now) }) return null
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return minute.takeIf { it in CalendarTimelineLogic.startMinute..CalendarTimelineLogic.endMinute }
    }

    private fun yForMinute(minute: Int): Float =
        headerHeight + timelineHeight * CalendarTimelineLogic.position(minute)

    private fun holidayBadge(items: List<HolidayItem>): String = items.joinToString(" · ") {
        "${if (it.type == "holiday") "休" else "班"} ${it.name}"
    }

    private fun wrapText(text: String, maxWidth: Float, paint: Paint, maximumLines: Int): List<String> {
        if (text.isEmpty() || maximumLines <= 0 || maxWidth <= 0f) return emptyList()
        val lines = mutableListOf<String>()
        var start = 0
        while (start < text.length && lines.size < maximumLines) {
            var end = start + 1
            var fittingEnd = end
            while (end <= text.length && paint.measureText(text, start, end) <= maxWidth) {
                fittingEnd = end
                end += 1
            }
            if (lines.size == maximumLines - 1 && fittingEnd < text.length) {
                lines += ellipsize(text.substring(start), maxWidth, paint)
                break
            }
            lines += text.substring(start, fittingEnd)
            start = fittingEnd
        }
        return lines
    }

    private fun buildAxisContentDescription(): String = buildString {
        append("整点")
        if (showCourseSlots) {
            append("；课程节次；")
            append(AppMetadata.slots.joinToString("；") { "第 ${it.label} 节 ${it.start}-${it.end}" })
        }
    }

    private fun buildDayContentDescription(): String = days.joinToString("；") { day ->
        val date = SimpleDateFormat("yyyy年M月d日", Locale.CHINA).apply { timeZone = shanghai }.format(day.date.time)
        val holidays = holidayBadge(day.holidays)
        val courses = day.courses.joinToString("，") { "${it.timeRange} ${it.name} ${it.room}" }
        listOf(date, holidays, courses.ifEmpty { "无课" }).filter(String::isNotEmpty).joinToString("，")
    }

    private fun placeCourses(courses: List<Course>): List<CoursePlacement> {
        val trackEnds = mutableListOf<Int>()
        return courses.sortedWith(compareBy(Course::startSlot, Course::endSlot, Course::name)).map { course ->
            val track = trackEnds.indexOfFirst { it < course.startSlot }.takeIf { it >= 0 } ?: trackEnds.size
            if (track == trackEnds.size) trackEnds += course.endSlot else trackEnds[track] = course.endSlot
            CoursePlacement(course, track)
        }
    }

    private fun sameDay(left: Calendar, right: Calendar): Boolean =
        left.get(Calendar.ERA) == right.get(Calendar.ERA) &&
            left.get(Calendar.YEAR) == right.get(Calendar.YEAR) &&
            left.get(Calendar.DAY_OF_YEAR) == right.get(Calendar.DAY_OF_YEAR)

    private fun drawCenteredText(canvas: Canvas, value: String, x: Float, y: Float, paint: Paint) {
        val centeredY = y - (paint.ascent() + paint.descent()) / 2f
        canvas.drawText(value, x, centeredY, paint)
    }

    private fun ellipsize(value: String, maxWidth: Float, paint: Paint): String {
        if (paint.measureText(value) <= maxWidth) return value
        val suffix = "…"
        var end = value.length
        while (end > 0 && paint.measureText(value.substring(0, end) + suffix) > maxWidth) end -= 1
        return value.substring(0, end) + suffix
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

    private data class CoursePlacement(val course: Course, val track: Int)

    private companion object {
    }
}
