package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.Dialog
import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.TransitionDrawable
import android.os.Bundle
import android.net.Uri
import android.text.TextUtils
import android.transition.AutoTransition
import android.transition.TransitionManager
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewConfiguration
import android.view.ViewOutlineProvider
import android.view.Window
import android.view.WindowManager
import android.view.VelocityTracker
import android.view.accessibility.AccessibilityEvent
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

internal enum class TeachingCalendarMode(val label: String) {
    DAY("日"),
    WEEK("周"),
    MONTH("月"),
    YEAR("年"),
}

internal class TeachingCalendarSessionState(
    selectedDateMillis: Long = System.currentTimeMillis(),
    selectedModeName: String = TeachingCalendarMode.WEEK.name,
    monthExpanded: Boolean = true,
    initialMonthSheetPosition: Float? = null,
    initialMonthDetailsDateKey: String? = null,
    initialMonthDetailsScrollY: Int = 0,
    initialDayWeekAgendaExpanded: Boolean = true,
) {
    val selectedDate: Calendar = Calendar.getInstance(SHANGHAI).apply {
        timeInMillis = selectedDateMillis
    }
    var selectedMode: TeachingCalendarMode = TeachingCalendarMode.entries
        .firstOrNull { it.name == selectedModeName }
        ?: TeachingCalendarMode.WEEK
    var monthSheetPosition: Float = initialMonthSheetPosition
        ?.coerceIn(0f, 2f)
        ?: if (monthExpanded) 0f else 1f
    var monthExpanded: Boolean
        get() = monthSheetPosition < 0.5f
        set(value) {
            monthSheetPosition = if (value) 0f else 1f
        }
    var monthDetailsDateKey: String? = initialMonthDetailsDateKey
        private set
    var monthDetailsScrollY: Int = initialMonthDetailsScrollY.coerceAtLeast(0)
        private set
    var dayWeekAgendaExpanded: Boolean = initialDayWeekAgendaExpanded

    fun savedMonthDetailsScrollY(dateKey: String): Int {
        if (monthDetailsDateKey != dateKey) resetMonthDetailsScroll(dateKey)
        return monthDetailsScrollY
    }

    fun updateMonthDetailsScroll(dateKey: String, scrollY: Int) {
        if (monthDetailsDateKey != dateKey) resetMonthDetailsScroll(dateKey)
        monthDetailsScrollY = scrollY.coerceAtLeast(0)
    }

    fun resetMonthDetailsScroll(dateKey: String) {
        monthDetailsDateKey = dateKey
        monthDetailsScrollY = 0
    }

    private companion object {
        val SHANGHAI: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")
    }
}

private typealias Mode = TeachingCalendarMode

private enum class CalendarSupplementaryKind {
    HOLIDAY,
    ASSIGNMENT,
    SCHOOL_NOTICE,
    PUBLIC_DEADLINE,
}

private data class CalendarSupplementaryItem(
    val kind: CalendarSupplementaryKind,
    val title: String,
    val subtitle: String?,
    val deadlineItem: PublicDeadlineItem? = null,
)

private enum class MonthCalendarEntryKind {
    HOLIDAY,
    COURSE,
    ASSIGNMENT,
    SCHOOL_NOTICE,
    PUBLIC_DEADLINE,
    OVERFLOW,
}

private data class MonthCalendarEntry(
    val title: String,
    val kind: MonthCalendarEntryKind,
    val deadlineItem: PublicDeadlineItem? = null,
)

private data class MonthEntriesRenderState(
    val entries: List<MonthCalendarEntry>,
    val selected: Boolean,
    val dateMillis: Long,
    var slotCapacity: Int = -1,
)

private data class MonthDayCellState(
    val dateMillis: Long,
)

private data class CenteredAgendaRow(
    val title: String,
    val subtitle: String?,
    val accent: Int,
    val deadlineItem: PublicDeadlineItem? = null,
)

private class MonthExpansionIndicatorView(context: Context) : View(context) {
    private val indicatorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeWidth = context.dp(4).toFloat()
    }
    private var expansionProgress = 0f

    fun setExpansionProgress(progress: Float) {
        expansionProgress = progress.coerceIn(0f, 1f)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        indicatorPaint.color = Palette.muted
        indicatorPaint.alpha = 140
        val angle = Math.toRadians((24f * expansionProgress).toDouble())
        val segmentLength = context.dp(20).toFloat()
        val horizontal = (cos(angle) * segmentLength).toFloat()
        val vertical = (sin(angle) * segmentLength).toFloat()
        val centerX = width / 2f
        val centerY = height / 2f - context.dp(1)
        canvas.drawLine(centerX - horizontal, centerY + vertical, centerX, centerY, indicatorPaint)
        canvas.drawLine(centerX, centerY, centerX + horizontal, centerY + vertical, indicatorPaint)
    }
}

private class MonthDetailsScrollView(context: Context) : ScrollView(context) {
    var isDetailsScrollingEnabled: Boolean = false

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean =
        isDetailsScrollingEnabled && super.onInterceptTouchEvent(event)

    override fun onTouchEvent(event: MotionEvent): Boolean =
        isDetailsScrollingEnabled && super.onTouchEvent(event)
}

object TeachingCalendarLogic {
    const val swipeThresholdDp = 72
    const val expansionVelocityThresholdDpPerSecond = 640f
    const val monthSheetExpandedPosition = 0f
    const val monthSheetDetailsPosition = 1f
    const val monthSheetWeekPosition = 2f
    const val phoneModeSwitchHeightDp = 38
    const val phoneModeTabHeightDp = 32
    const val phoneNavigationHeightDp = 36
    const val phoneDateStripHeightDp = 56
    const val phoneDateStripGapDp = 6
    const val collapsedMonthDayTopPaddingDp = 5
    const val expandedMonthDayTopPaddingDp = 5
    const val monthWeekdayHeaderHeightDp = 26
    const val monthWeekdayHeaderBottomMarginDp = 8
    const val monthDragHandleHeightDp = 28
    const val compactCalendarBreakpointDp = 1200
    // The floating phone navigation is 60dp tall with a 10dp bottom margin.
    // Keep a small visual gap without shrinking the fixed month viewport by
    // the former 34dp of unused space.
    const val bottomNavigationContentInsetDp = 78
    const val compactAgendaHeaderHeightDp = 34
    const val expandedAgendaHeaderHeightDp = 36
    const val agendaAnimationDurationMillis = 220L
    const val pageAnimationDurationMillis = 300L
    const val almanacAdviceMinimumTextHeightDp = 36
    const val almanacAdviceLineExtraDp = 2

    fun modeTransitionDirection(fromIndex: Int, toIndex: Int): Int = when {
        toIndex > fromIndex -> 1
        toIndex < fromIndex -> -1
        else -> 0
    }

    internal fun pageTransitionOffsets(
        direction: Int,
        distance: Float,
    ): CalendarPageTransitionOffsets {
        val resolvedDirection = direction.compareTo(0)
        val resolvedDistance = abs(distance)
        return CalendarPageTransitionOffsets(
            incomingStartX = resolvedDirection * resolvedDistance,
            outgoingEndX = -resolvedDirection * resolvedDistance,
        )
    }

    fun weekPeriodTitle(base: String, teachingWeek: Int?): String =
        teachingWeek?.takeIf { it > 0 }?.let { "$base 第${it}教学周" } ?: base

    fun teachingWeekAxisLabel(teachingWeek: Int?): String =
        teachingWeek?.takeIf { it > 0 }?.let { "教学\n第${it}周" } ?: "教学\n—"

    fun monthOverflowDescription(hiddenCount: Int): String =
        "月视图还有 ${hiddenCount.coerceAtLeast(0)} 项日程，请选择日期后在下方查看"

    fun yearCourseOpacity(courseCount: Int): Float {
        if (courseCount <= 0) return 0f
        val count = courseCount.toFloat()
        return 0.12f + 0.72f * count / (count + 3f)
    }

    fun phoneDateCellWidth(screenWidthDp: Int, leadingWidthDp: Int = 0): Int =
        ((screenWidthDp - 24 - leadingWidthDp - 6 * 2) / 7).coerceIn(
            if (leadingWidthDp > 0) 34 else 40,
            64,
        )

    fun swipePageDirection(
        deltaXDp: Float,
        deltaYDp: Float,
        thresholdDp: Int = swipeThresholdDp,
    ): Int {
        val horizontalDistance = abs(deltaXDp)
        val verticalDistance = abs(deltaYDp)
        if (horizontalDistance < thresholdDp || horizontalDistance <= verticalDistance * 1.4f) {
            return 0
        }
        return if (deltaXDp < 0f) 1 else -1
    }

    fun canMoveMonthSheet(
        deltaXDp: Float,
        deltaYDp: Float,
        currentPosition: Float,
        thresholdDp: Int,
        detailsCanScrollBackward: Boolean = false,
    ): Boolean {
        val horizontalDistance = abs(deltaXDp)
        val verticalDistance = abs(deltaYDp)
        if (verticalDistance < thresholdDp || verticalDistance <= horizontalDistance * 1.2f) {
            return false
        }
        if (routesMonthDragToDetails(
                currentPosition,
                deltaYDp,
                detailsCanScrollBackward,
            )
        ) {
            return false
        }
        return when {
            deltaYDp < 0f -> currentPosition < monthSheetWeekPosition
            deltaYDp > 0f -> currentPosition > monthSheetExpandedPosition
            else -> false
        }
    }

    fun routesMonthDragToDetails(
        currentPosition: Float,
        deltaYDp: Float,
        detailsCanScrollBackward: Boolean = false,
    ): Boolean = currentPosition >= monthSheetWeekPosition &&
        (deltaYDp < 0f || detailsCanScrollBackward)

    fun monthCellHeightDp(expanded: Boolean): Int = if (expanded) 82 else 46

    fun expandedMonthCellHeightDp(
        monthViewHeightDp: Int,
        verticalPaddingDp: Int,
        weekdayReservedHeightDp: Int,
        dragHandleReservedHeightDp: Int,
    ): Int = (
        (monthViewHeightDp - verticalPaddingDp - weekdayReservedHeightDp -
            dragHandleReservedHeightDp).coerceAtLeast(0) / 6
        ).coerceAtMost(monthCellHeightDp(expanded = true))

    fun monthSheetDragPosition(
        deltaYDp: Float,
        startPosition: Float,
        travelDp: Float = (monthCellHeightDp(true) - monthCellHeightDp(false)) * 6f,
    ): Float {
        if (travelDp <= 0f) return startPosition.coerceIn(0f, 2f)
        return (startPosition - deltaYDp / travelDp).coerceIn(0f, 2f)
    }

    fun monthDetailsDragOverflowDp(
        deltaYDp: Float,
        startPosition: Float,
        travelDp: Float = (monthCellHeightDp(true) - monthCellHeightDp(false)) * 6f,
    ): Float {
        if (deltaYDp >= 0f || travelDp <= 0f) return 0f
        val distanceToDetails =
            (monthSheetWeekPosition - startPosition.coerceIn(0f, 2f)) * travelDp
        return (-deltaYDp - distanceToDetails).coerceAtLeast(0f)
    }

    fun settledMonthSheetPosition(
        position: Float,
        velocityYDpPerSecond: Float,
        velocityThresholdDpPerSecond: Float = expansionVelocityThresholdDpPerSecond,
    ): Int {
        val resolved = position.coerceIn(0f, 2f)
        if (abs(velocityYDpPerSecond) >= velocityThresholdDpPerSecond) {
            return if (velocityYDpPerSecond < 0f) {
                (kotlin.math.floor((resolved + 0.001f).toDouble()).toInt() + 1).coerceAtMost(2)
            } else {
                (kotlin.math.ceil((resolved - 0.001f).toDouble()).toInt() - 1).coerceAtLeast(0)
            }
        }
        return resolved.roundToInt().coerceIn(0, 2)
    }

    fun interpolateMonthMetric(collapsed: Int, expanded: Int, progress: Float): Int =
        (collapsed + (expanded - collapsed) * progress.coerceIn(0f, 1f)).roundToInt()

    fun monthCellExpansionProgress(position: Float): Float =
        1f - position.coerceIn(monthSheetExpandedPosition, monthSheetDetailsPosition)

    fun monthSelectedWeekProgress(position: Float): Float =
        (position - monthSheetDetailsPosition).coerceIn(0f, 1f)

    fun monthRowHeightDp(
        position: Float,
        rowIndex: Int,
        selectedWeekIndex: Int,
        expandedHeightDp: Int = monthCellHeightDp(true),
    ): Int {
        val expandedProgress = monthCellExpansionProgress(position)
        val fullMonthHeight = interpolateMonthMetric(
            monthCellHeightDp(false),
            expandedHeightDp,
            expandedProgress,
        )
        if (rowIndex == selectedWeekIndex) return fullMonthHeight
        return (fullMonthHeight * (1f - monthSelectedWeekProgress(position)))
            .roundToInt()
            .coerceAtLeast(0)
    }

    fun monthEntryAvailableHeightDp(
        cellHeightDp: Int,
        expandedProgress: Float,
        labelHeightDp: Int = 24,
    ): Int {
        val resolved = expandedProgress.coerceIn(0f, 1f)
        val bottomPadding = interpolateMonthMetric(5, 2, resolved)
        val markerHeight = interpolateMonthMetric(12, 0, resolved)
        return (cellHeightDp - expandedMonthDayTopPaddingDp - bottomPadding -
            labelHeightDp - markerHeight).coerceAtLeast(0)
    }

    fun monthEntrySlotCapacity(
        availableHeightDp: Int,
        entryHeightDp: Int = 14,
        entrySpacingDp: Int = 1,
    ): Int {
        if (availableHeightDp <= 0 || entryHeightDp <= 0) return 0
        return ((availableHeightDp + entrySpacingDp) / (entryHeightDp + entrySpacingDp))
            .coerceAtLeast(0)
    }

    fun visibleMonthEntryCount(entryCount: Int, slotCapacity: Int): Int {
        val count = entryCount.coerceAtLeast(0)
        val capacity = slotCapacity.coerceAtLeast(0)
        return if (count > capacity) (capacity - 1).coerceAtLeast(0) else count
    }

    fun hiddenMonthEntryCount(entryCount: Int, slotCapacity: Int): Int =
        (entryCount - visibleMonthEntryCount(entryCount, slotCapacity)).coerceAtLeast(0)

    fun agendaVisibleItemCount(itemCount: Int, compactWeek: Boolean): Int =
        itemCount.coerceAtLeast(0).coerceAtMost(if (compactWeek) 1 else 3)

    fun agendaHiddenItemCount(itemCount: Int, compactWeek: Boolean): Int =
        (itemCount - agendaVisibleItemCount(itemCount, compactWeek)).coerceAtLeast(0)

    fun dayWeekVisibleCourseCount(courseCount: Int): Int = courseCount.coerceAtLeast(0)

    fun shouldShowDayWeekCourseContent(courseCount: Int, expanded: Boolean): Boolean =
        courseCount > 0 && expanded

    fun monthSelectionTransitionDirection(
        fromYear: Int,
        fromMonth: Int,
        toYear: Int,
        toMonth: Int,
    ): Int = (toYear * 12 + toMonth).compareTo(fromYear * 12 + fromMonth)

    fun monthHorizontalPaddingDp(usesBottomNavigation: Boolean): Int =
        if (usesBottomNavigation) 0 else 16

    fun calendarContentBottomInsetDp(usesBottomNavigation: Boolean): Int =
        if (usesBottomNavigation) bottomNavigationContentInsetDp else 0

    fun monthDaySelectionTargetPosition(): Float = monthSheetDetailsPosition

    fun monthDetailsBorderWidthDp(): Float = 0f

    fun monthCellBorderColor(
        supplementaryKind: YearCalendarSupplementaryKind?,
        today: Boolean,
        assignmentColor: Int,
        schoolNoticeColor: Int,
        publicDeadlineColor: Int,
        todayColor: Int,
    ): Int = when (supplementaryKind) {
        YearCalendarSupplementaryKind.ASSIGNMENT -> assignmentColor
        YearCalendarSupplementaryKind.SCHOOL_NOTICE -> schoolNoticeColor
        YearCalendarSupplementaryKind.PUBLIC_DEADLINE -> publicDeadlineColor
        null -> if (today) todayColor else Color.TRANSPARENT
    }

    fun monthCellBorderWidthDp(
        supplementaryKind: YearCalendarSupplementaryKind?,
        today: Boolean,
    ): Float = when {
        supplementaryKind != null -> YearCalendarLogic.supplementaryOuterBorderWidthDp()
        today -> YearCalendarLogic.todayBorderWidthDp()
        else -> 0f
    }

    fun monthCellInnerBorderWidthDp(): Float =
        YearCalendarLogic.supplementaryInnerBorderWidthDp()

    fun monthCellInnerBorderInsetDp(): Float =
        YearCalendarLogic.supplementaryInnerBorderInsetDp()

    fun monthEntryTextColor(selected: Boolean, textColor: Int, onPrimaryColor: Int): Int =
        if (selected) onPrimaryColor else textColor

    fun monthEntryBackgroundColor(
        selected: Boolean,
        surfaceVariantColor: Int,
        selectedDateColor: Int,
    ): Int = if (selected) selectedDateColor else surfaceVariantColor

    fun courseDetailLines(course: Course): List<String> = buildList {
        add("时间：${course.timeRange.ifEmpty { "未标注" }}")
        add("节次：${course.sectionText.ifEmpty { "未标注" }}")
        add("地点：${course.room.ifEmpty { "未标注" }}")
        add("教师：${course.teacher.ifEmpty { "未标注" }}")
        add("周次：${course.weekText.ifEmpty { course.weekNumbers.joinToString(",") }}")
        if (course.examWeekNumbers.isNotEmpty()) {
            add("考试周：${course.examWeekNumbers.joinToString(",")} 周")
        }
    }

}

internal data class CalendarPageTransitionOffsets(
    val incomingStartX: Float,
    val outgoingEndX: Float,
)

private class CalendarSwipeContainer(
    context: MainActivity,
) : FrameLayout(context) {
    var onPageSwipe: ((Int) -> Unit)? = null
    var onMonthSheetSettled: ((Float) -> Unit)? = null
        set(value) {
            field = value
            sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
        }
    var onMonthSheetProgress: ((Float) -> Unit)? = null
    var monthSheetPosition: Float = TeachingCalendarLogic.monthSheetExpandedPosition
        set(value) {
            field = value.coerceIn(
                TeachingCalendarLogic.monthSheetExpandedPosition,
                TeachingCalendarLogic.monthSheetWeekPosition,
            )
            sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
        }
    var swipeEnabled: Boolean = true
    private var downX = 0f
    private var downY = 0f
    private var gestureEligible = false
    private var claimedGesture = 0
    private var childCancelled = false
    private var gestureStartedInMonthDetails = false
    private var monthDetailsCouldScrollBackwardAtGestureStart = false
    private var monthDragStartPosition = TeachingCalendarLogic.monthSheetExpandedPosition
    private var monthDragPosition = TeachingCalendarLogic.monthSheetExpandedPosition
    private var monthDetailsDragStartScrollY = 0
    private var velocityTracker: VelocityTracker? = null
    private val density = resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop / density

    init {
        isFocusable = true
        ViewCompat.setAccessibilityDelegate(this, object : AccessibilityDelegateCompat() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfoCompat,
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                if (swipeEnabled && onPageSwipe != null) {
                    info.addAction(
                        AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_SCROLL_FORWARD,
                    )
                    info.addAction(
                        AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_SCROLL_BACKWARD,
                    )
                }
                if (onMonthSheetSettled != null) {
                    info.contentDescription = when (monthSheetPosition.roundToInt()) {
                        0 -> "月历，已展开"
                        1 -> "月历与当日日程"
                        else -> "选中周与当日日程"
                    }
                    if (monthSheetPosition < TeachingCalendarLogic.monthSheetWeekPosition) {
                        info.addAction(
                            AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_COLLAPSE,
                        )
                    }
                    if (monthSheetPosition > TeachingCalendarLogic.monthSheetExpandedPosition) {
                        info.addAction(
                            AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_EXPAND,
                        )
                    }
                }
            }

            override fun performAccessibilityAction(host: View, action: Int, args: Bundle?): Boolean {
                if (swipeEnabled && onPageSwipe != null) {
                    val pageDirection = when (action) {
                        AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_SCROLL_FORWARD.id -> 1
                        AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_SCROLL_BACKWARD.id -> -1
                        else -> 0
                    }
                    if (pageDirection != 0) {
                        post { onPageSwipe?.invoke(pageDirection) }
                        return true
                    }
                }
                val target = when (action) {
                    AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_EXPAND.id ->
                        monthSheetPosition.roundToInt() - 1
                    AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_COLLAPSE.id ->
                        monthSheetPosition.roundToInt() + 1
                    else -> return super.performAccessibilityAction(host, action, args)
                }.coerceIn(0, 2)
                if (onMonthSheetSettled == null || target == monthSheetPosition.roundToInt()) return false
                post { onMonthSheetSettled?.invoke(target.toFloat()) }
                return true
            }
        })
    }

    private fun restoreParentInterception() {
        parent?.requestDisallowInterceptTouchEvent(false)
    }

    private fun cancelChild(event: MotionEvent) {
        if (childCancelled) return
        val cancelEvent = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
        super.dispatchTouchEvent(cancelEvent)
        cancelEvent.recycle()
        childCancelled = true
    }

    private fun monthDetailsScrollView(): MonthDetailsScrollView? =
        findViewById(R.id.calendar_month_selected_details)

    private fun containsTouch(view: View?, x: Float, y: Float): Boolean {
        if (view == null || view.visibility != View.VISIBLE || view.width <= 0 || view.height <= 0) {
            return false
        }
        val containerLocation = IntArray(2).also(::getLocationOnScreen)
        val viewLocation = IntArray(2).also(view::getLocationOnScreen)
        val left = (viewLocation[0] - containerLocation[0]).toFloat()
        val top = (viewLocation[1] - containerLocation[1]).toFloat()
        return x >= left && x <= left + view.width && y >= top && y <= top + view.height
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        // When the details ScrollView is disabled at the middle detent it may decline
        // ACTION_DOWN. Keep the container as the touch target for the full sequence so
        // the later MOVE can still be claimed by the three-position month sheet.
        val participatesInCalendarGesture = gestureEligible ||
            (event.actionMasked == MotionEvent.ACTION_DOWN && swipeEnabled)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                gestureEligible = swipeEnabled
                claimedGesture = 0
                childCancelled = false
                monthDragStartPosition = monthSheetPosition
                monthDragPosition = monthSheetPosition
                val details = monthDetailsScrollView()
                gestureStartedInMonthDetails = containsTouch(details, event.x, event.y)
                monthDetailsCouldScrollBackwardAtGestureStart =
                    gestureStartedInMonthDetails && details?.canScrollVertically(-1) == true
                monthDetailsDragStartScrollY = details?.scrollY ?: 0
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
                if (gestureEligible) {
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
            }
            MotionEvent.ACTION_MOVE -> {
                velocityTracker?.addMovement(event)
                if (gestureEligible && claimedGesture == 0) {
                    val deltaX = (event.x - downX) / density
                    val deltaY = (event.y - downY) / density
                    if (abs(deltaX) >= touchSlop || abs(deltaY) >= touchSlop) {
                        claimedGesture = when {
                            abs(deltaX) > abs(deltaY) * 1.12f -> 1
                            onMonthSheetSettled != null && TeachingCalendarLogic.canMoveMonthSheet(
                                deltaXDp = deltaX,
                                deltaYDp = deltaY,
                                currentPosition = monthDragStartPosition,
                                thresholdDp = touchSlop.roundToInt().coerceAtLeast(6),
                                detailsCanScrollBackward =
                                    monthDetailsCouldScrollBackwardAtGestureStart,
                            ) -> 2
                            gestureStartedInMonthDetails &&
                                TeachingCalendarLogic.routesMonthDragToDetails(
                                    currentPosition = monthDragStartPosition,
                                    deltaYDp = deltaY,
                                    detailsCanScrollBackward =
                                        monthDetailsCouldScrollBackwardAtGestureStart,
                                ) -> -2
                            else -> -1
                        }
                        if (claimedGesture > 0) {
                            parent?.requestDisallowInterceptTouchEvent(true)
                            cancelChild(event)
                        } else if (claimedGesture == -1) {
                            restoreParentInterception()
                        }
                    }
                }
                if (claimedGesture == 2) {
                    val deltaY = (event.y - downY) / density
                    monthDragPosition = TeachingCalendarLogic.monthSheetDragPosition(
                        deltaYDp = deltaY,
                        startPosition = monthDragStartPosition,
                    )
                    onMonthSheetProgress?.invoke(monthDragPosition)
                    val overflowDp = TeachingCalendarLogic.monthDetailsDragOverflowDp(
                        deltaYDp = deltaY,
                        startPosition = monthDragStartPosition,
                    )
                    if (overflowDp > 0f) {
                        monthDetailsScrollView()?.scrollTo(
                            0,
                            monthDetailsDragStartScrollY + (overflowDp * density).roundToInt(),
                        )
                    }
                    return true
                }
                if (claimedGesture > 0) return true
            }
            MotionEvent.ACTION_UP -> {
                velocityTracker?.addMovement(event)
                velocityTracker?.computeCurrentVelocity(1000)
                val deltaX = (event.x - downX) / density
                val deltaY = (event.y - downY) / density
                if (gestureEligible && claimedGesture == 1) {
                    val direction = TeachingCalendarLogic.swipePageDirection(deltaX, deltaY)
                    gestureEligible = false
                    restoreParentInterception()
                    if (direction != 0) post { onPageSwipe?.invoke(direction) }
                    return true
                }
                if (gestureEligible && claimedGesture == 2) {
                    val velocityY = (velocityTracker?.yVelocity ?: 0f) / density
                    val target = TeachingCalendarLogic.settledMonthSheetPosition(
                        position = monthDragPosition,
                        velocityYDpPerSecond = velocityY,
                    )
                    gestureEligible = false
                    restoreParentInterception()
                    velocityTracker?.recycle()
                    velocityTracker = null
                    post { onMonthSheetSettled?.invoke(target.toFloat()) }
                    return true
                }
                gestureEligible = false
                claimedGesture = 0
                restoreParentInterception()
                velocityTracker?.recycle()
                velocityTracker = null
            }
            MotionEvent.ACTION_CANCEL -> {
                if (claimedGesture == 2) {
                    monthDetailsScrollView()?.scrollTo(0, monthDetailsDragStartScrollY)
                    post { onMonthSheetSettled?.invoke(monthDragStartPosition.roundToInt().toFloat()) }
                }
                gestureEligible = false
                claimedGesture = 0
                restoreParentInterception()
                velocityTracker?.recycle()
                velocityTracker = null
            }
        }
        return super.dispatchTouchEvent(event) || participatesInCalendarGesture
    }
}

internal fun buildAlmanacAdviceRow(
    context: Context,
    label: String,
    value: String,
    color: Int,
): LinearLayout = LinearLayout(context).apply {
    id = R.id.calendar_almanac_advice_row
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.TOP
    isBaselineAligned = false
    background = roundedBackground(context, Palette.background, Palette.border, radius = 7)
    setPadding(context.dp(9), context.dp(8), context.dp(9), context.dp(8))
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = context.dp(7) }
    addView(TextView(context).apply {
        id = R.id.calendar_almanac_advice_label
        text = label
        textSize = 12f
        gravity = Gravity.CENTER
        setTextColor(color)
        setTypeface(typeface, Typeface.BOLD)
    }, LinearLayout.LayoutParams(context.dp(24), context.dp(24)).apply {
        marginEnd = context.dp(7)
    })
    addView(TextView(context).apply {
        id = R.id.calendar_almanac_advice_text
        text = value
        textSize = 12f
        setTextColor(Palette.muted)
        includeFontPadding = true
        setLineSpacing(
            context.dp(TeachingCalendarLogic.almanacAdviceLineExtraDp).toFloat(),
            1f,
        )
        setPadding(
            0,
            0,
            0,
            context.dp(TeachingCalendarLogic.almanacAdviceLineExtraDp),
        )
        minHeight = context.dp(TeachingCalendarLogic.almanacAdviceMinimumTextHeightDp)
    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
}

internal class TeachingCalendarPage(
    private val activity: MainActivity,
    private val scheduleRepository: ScheduleRepository,
    private val holidayRepository: HolidayRepository,
    private val dailyInfoRepository: CalendarDailyInfoRepository,
    private val preferences: AppPreferences,
    private val availableWidthDp: Int,
    private val sessionState: TeachingCalendarSessionState,
    private val usesBottomNavigation: Boolean,
) {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val selectedDate = sessionState.selectedDate
    private var selectedMode: Mode
        get() = sessionState.selectedMode
        set(value) {
            sessionState.selectedMode = value
        }
    private var monthSheetPosition: Float
        get() = sessionState.monthSheetPosition
        set(value) {
            sessionState.monthSheetPosition = value.coerceIn(0f, 2f)
        }
    private var renderedMonthSheetPosition = monthSheetPosition
    private var expandedMonthCellHeightDp = TeachingCalendarLogic.monthCellHeightDp(true)
    private var monthExpansionAnimator: ValueAnimator? = null
    private var pendingPageDirection = 0
    private var pendingModeSelectionFrom: Mode? = null
    private var pendingMonthSelectionStartPosition: Float? = null
    private var pendingMonthSelectionTargetPosition: Float? = null
    private var calendarHostRoot: View? = null
    private var calendarRenderAction: (() -> Unit)? = null
    private var activePopupAnchor: YearCalendarView? = null
    private var activePopup: PopupWindow? = null
    private var activePopupDetailsHost: LinearLayout? = null
    private var activePopupDateMillis: Long? = null
    private var activeYearCalendar: YearCalendarView? = null

    /**
     * Starts data work from calendar state changes and lifecycle events, never
     * from a View-construction function. Repository completions update only the
     * currently mounted month cells/details, so they cannot replace or cut off
     * a month-page transition.
     */
    private fun requestCalendarDataForSelection() {
        visibleYears().forEach(holidayRepository::ensure)
        if (selectedMode == Mode.YEAR) {
            val requestedYear = selectedDate.get(Calendar.YEAR)
            val dates = yearDates(requestedYear)
            dailyInfoRepository.loadCalendarMarkers(
                dates = dates.map { contractDate().format(it.time) },
                includeDeadlines = preferences.hasEnabledPublicDeadlines,
            ) {
                if (selectedMode == Mode.YEAR &&
                    selectedDate.get(Calendar.YEAR) == requestedYear
                ) {
                    activeYearCalendar?.updateDays(yearCalendarDays(requestedYear))
                }
            }
            return
        }
        val dates = when (selectedMode) {
            Mode.DAY -> listOf(selectedDate.clone() as Calendar)
            Mode.WEEK -> weekDates()
            Mode.MONTH -> monthGridDates()
            Mode.YEAR -> emptyList()
        }
        requestDailyInfoForDates(dates, includeAlmanac = selectedMode == Mode.MONTH)
    }

    private fun requestDailyInfoForDates(
        dates: List<Calendar>,
        includeAlmanac: Boolean = false,
    ) {
        val selectedKey = contractDate().format(selectedDate.time)
        val dateKeys = dates
            .map { contractDate().format(it.time) }
            .distinct()
            .sortedBy { if (it == selectedKey) 0 else 1 }
        if (includeAlmanac && preferences.almanacEnabled && selectedKey in dateKeys) {
            dailyInfoRepository.loadAlmanac(selectedKey) {}
        }
        dateKeys.forEach { dateKey ->
            if (preferences.hasEnabledPublicDeadlines) {
                dailyInfoRepository.loadDeadlines(dateKey) {}
            }
            dailyInfoRepository.loadAssignments(dateKey) {}
        }
    }

    private fun activeMonthView(): ViewGroup? {
        val root = calendarHostRoot ?: return null
        if (!root.isAttachedToWindow || selectedMode != Mode.MONTH) return null
        val surface = root.findViewById<FrameLayout?>(R.id.calendar_swipe_surface)
        val activePage = surface?.takeIf { it.childCount > 0 }
            ?.getChildAt(surface.childCount - 1)
            ?: root
        return activePage.findViewById(R.id.calendar_month_view)
    }

    private fun refreshSelectedMonthDetailsInPlace(expectedDateKey: String) {
        val root = calendarHostRoot ?: return
        root.post {
            if (calendarHostRoot !== root || !root.isAttachedToWindow) return@post
            val currentDateKey = contractDate().format(selectedDate.time)
            if (currentDateKey != expectedDateKey) return@post
            val details = activeMonthView()?.findViewById<MonthDetailsScrollView>(
                R.id.calendar_month_selected_details,
            ) ?: return@post
            if (details.tag != expectedDateKey) return@post
            val retainedScrollY = details.scrollY
            details.removeAllViews()
            details.addView(monthSelectedDetails(selectedDate))
            UiText.localizeTree(details)
            details.post {
                if (details.isAttachedToWindow && details.tag == expectedDateKey) {
                    details.scrollTo(0, retainedScrollY)
                }
            }
        }
    }

    private fun handleDailyInfoChanged(dateKey: String) {
        refreshSelectedMonthDetailsInPlace(dateKey)
        refreshMonthCellsInPlace(dateKey)
        refreshDayWeekAgendaInPlace(dateKey)
        refreshYearCalendarInPlace(dateKey)
        refreshYearPopoverInPlace(dateKey)
    }

    private fun refreshYearCalendarInPlace(expectedDateKey: String) {
        if (selectedMode != Mode.YEAR) return
        val yearView = activeYearCalendar ?: return
        if (!yearView.isAttachedToWindow) return
        val day = runCatching {
            contractDate().parse(expectedDateKey)?.let { value ->
                Calendar.getInstance(shanghai).apply { time = value }
            }
        }.getOrNull() ?: return
        if (day.get(Calendar.YEAR) != selectedDate.get(Calendar.YEAR)) return
        yearView.updateDay(yearCalendarDay(day))
    }

    private fun refreshMonthCellsInPlace(expectedDateKey: String? = null) {
        val root = calendarHostRoot ?: return
        root.post {
            if (calendarHostRoot !== root || !root.isAttachedToWindow) return@post
            val monthView = activeMonthView() ?: return@post
            val grid = monthView.findViewById<ViewGroup>(R.id.calendar_month_grid)
            repeat(grid.childCount) { rowIndex ->
                val row = grid.getChildAt(rowIndex) as ViewGroup
                repeat(row.childCount) cellLoop@ { cellIndex ->
                    val cell = row.getChildAt(cellIndex) as? LinearLayout ?: return@cellLoop
                    val state = cell.tag as? MonthDayCellState ?: return@cellLoop
                    val day = Calendar.getInstance(shanghai).apply {
                        timeInMillis = state.dateMillis
                    }
                    if (expectedDateKey != null && contractDate().format(day.time) != expectedDateKey) {
                        return@cellLoop
                    }
                    val cellHeightDp = (row.height / activity.resources.displayMetrics.density)
                        .roundToInt()
                    bindMonthDayCell(
                        cell,
                        day,
                        renderedMonthSheetPosition,
                        cellHeightDp,
                    )
                }
            }
        }
    }

    private fun refreshDayWeekAgendaInPlace(expectedDateKey: String) {
        if (selectedMode !in listOf(Mode.DAY, Mode.WEEK)) return
        val root = calendarHostRoot ?: return
        root.post {
            if (calendarHostRoot !== root || !root.isAttachedToWindow) return@post
            val selectedKey = contractDate().format(selectedDate.time)
            val visibleKeys = if (selectedMode == Mode.DAY) {
                setOf(selectedKey)
            } else {
                weekDates().mapTo(mutableSetOf()) { contractDate().format(it.time) }
            }
            if (expectedDateKey !in visibleKeys) return@post
            val oldSection = root.findViewById<LinearLayout?>(R.id.calendar_day_week_agenda)
                ?: return@post
            val parent = oldSection.parent as? ViewGroup ?: return@post
            val index = parent.indexOfChild(oldSection)
            val layoutParams = oldSection.layoutParams
            val days = if (selectedMode == Mode.DAY) {
                listOf(timelineDay(selectedDate))
            } else {
                weekDates().map(::timelineDay)
            }
            val replacement = dayWeekAgendaSection(
                days = days,
                compact = availableWidthDp < TeachingCalendarLogic.compactCalendarBreakpointDp,
            )
            UiText.localizeTree(replacement)
            parent.removeViewAt(index)
            parent.addView(replacement, index, layoutParams)
        }
    }

    private fun refreshYearPopoverInPlace(expectedDateKey: String) {
        val host = activePopupDetailsHost ?: return
        val dateMillis = activePopupDateMillis ?: return
        val day = Calendar.getInstance(shanghai).apply { timeInMillis = dateMillis }
        if (contractDate().format(day.time) != expectedDateKey || !host.isAttachedToWindow) return
        host.removeAllViews()
        host.addView(selectedDayDetails(day, includeSupplementary = true))
        UiText.localizeTree(host)
    }

    private fun refreshHolidayDataInPlace() {
        val root = calendarHostRoot ?: return
        root.post {
            if (calendarHostRoot !== root || !root.isAttachedToWindow) return@post
            refreshMonthCellsInPlace()
            refreshSelectedMonthDetailsInPlace(contractDate().format(selectedDate.time))
            refreshDayWeekAgendaInPlace(contractDate().format(selectedDate.time))
        }
    }

    fun build(): View = if (availableWidthDp < TeachingCalendarLogic.compactCalendarBreakpointDp) {
        phoneBuild()
    } else {
        expandedBuild()
    }

    private fun expandedBuild(): ScrollView {
        val scrollView = ScrollView(activity).apply {
            isFillViewport = true
            scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
            setBackgroundColor(Palette.background)
        }
        val root = verticalPage(activity)
        scrollView.addView(root)
        val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val tabs = mutableMapOf<Mode, TextView>()

        fun updateMonthSheetProgress(position: Float) {
            monthExpansionAnimator?.cancel()
            renderedMonthSheetPosition = position.coerceIn(0f, 2f)
            content.findViewById<ViewGroup?>(R.id.calendar_month_view)?.let { monthView ->
                applyMonthSheetPosition(monthView, renderedMonthSheetPosition)
            }
        }

        fun settleMonthSheet(position: Float) {
            val monthView = content.findViewById<ViewGroup?>(R.id.calendar_month_view) ?: return
            val target = position.roundToInt().coerceIn(0, 2).toFloat()
            if (target != monthSheetPosition.roundToInt().toFloat()) performCalendarHaptic()
            if (target < TeachingCalendarLogic.monthSheetWeekPosition) {
                val dateKey = contractDate().format(selectedDate.time)
                sessionState.resetMonthDetailsScroll(dateKey)
                monthView.findViewById<MonthDetailsScrollView?>(
                    R.id.calendar_month_selected_details,
                )?.scrollTo(0, 0)
            }
            monthSheetPosition = target
            content.findViewById<CalendarSwipeContainer?>(R.id.calendar_swipe_surface)
                ?.monthSheetPosition = target
            animateMonthSheetPosition(monthView, target) {
                monthSheetPosition = target
                content.findViewById<CalendarSwipeContainer?>(R.id.calendar_swipe_surface)
                    ?.monthSheetPosition = target
            }
        }

        fun render() {
            calendarRenderAction = ::render
            dismissYearPopover()
            tabs.forEach { (mode, view) -> view.setSelectedStyle(activity, mode == selectedMode) }
            content.removeAllViews()
            renderedMonthSheetPosition = monthSheetPosition
            content.addView(dateNavigation(::render))
            content.addView(spacer(activity, 12))
            content.addView(dateSummary())
            content.addView(spacer(activity, 12))
            holidayStatus()?.let { message ->
                content.addView(TextView(activity).apply {
                    text = message
                    textSize = 13f
                    setTextColor(Palette.muted)
                    setPadding(activity.dp(4), 0, activity.dp(4), activity.dp(10))
                })
            }
            val calendarView = when (selectedMode) {
                    Mode.DAY -> dayView()
                    Mode.WEEK -> weekView(::render)
                    Mode.MONTH -> monthView(::render, ::settleMonthSheet)
                    Mode.YEAR -> yearView(::render)
                }
            content.addView(
                if (selectedMode == Mode.YEAR) {
                    calendarView
                } else {
                    swipeContainer(
                        calendarView,
                        ::render,
                        monthSheetPosition = monthSheetPosition,
                        onMonthSheetSettled = if (selectedMode == Mode.MONTH) {
                            ::settleMonthSheet
                        } else {
                            null
                        },
                        onMonthSheetProgress = if (selectedMode == Mode.MONTH) {
                            ::updateMonthSheetProgress
                        } else {
                            null
                        },
                    )
                },
            )
            animateExpandedPageIn(content)
            animatePendingMonthDaySelection(calendarView)
            UiText.localizeTree(content)
        }

        scrollView.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                calendarHostRoot = scrollView
                holidayRepository.addObserver(scrollView) {
                    refreshHolidayDataInPlace()
                }
                dailyInfoRepository.addObserver(scrollView, ::handleDailyInfoChanged)
                requestCalendarDataForSelection()
                render()
            }

            override fun onViewDetachedFromWindow(view: View) {
                scrollView.requestDisallowInterceptTouchEvent(false)
                holidayRepository.removeObserver(scrollView)
                dailyInfoRepository.removeObserver(scrollView)
                if (calendarHostRoot === scrollView) calendarHostRoot = null
                calendarRenderAction = null
                dismissYearPopover()
            }
        })

        root.addView(pageTitle(activity, "教学日历", "课程、节次与法定节假日"))
        root.addView(calendarImportButton())
        root.addView(spacer(activity, 8))
        root.addView(favoriteCalendarImportButton())
        root.addView(spacer(activity, 12))
        root.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            Mode.entries.forEach { mode ->
                val tab = fixedTab(activity, mode.label) {
                    pendingPageDirection = TeachingCalendarLogic.modeTransitionDirection(
                        selectedMode.ordinal,
                        mode.ordinal,
                    )
                    selectedMode = mode
                    requestCalendarDataForSelection()
                    render()
                }.apply {
                    id = when (mode) {
                        Mode.DAY -> R.id.calendar_mode_day
                        Mode.WEEK -> R.id.calendar_mode_week
                        Mode.MONTH -> R.id.calendar_mode_month
                        Mode.YEAR -> R.id.calendar_mode_year
                    }
                }
                tab.layoutParams = LinearLayout.LayoutParams(0, activity.dp(44), 1f).apply {
                    marginEnd = activity.dp(6)
                }
                tabs[mode] = tab
                addView(tab)
            }
        })
        root.addView(spacer(activity, 14))
        root.addView(content)
        render()
        return scrollView
    }

    private fun phoneBuild(): LinearLayout {
        val root = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.background)
        }
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.background)
        }
        val pageSurface = CalendarSwipeContainer(activity).apply {
            id = R.id.calendar_swipe_surface
            setBackgroundColor(Palette.background)
        }
        val tabs = mutableMapOf<Mode, TextView>()
        val periodLabel = TextView(activity).apply {
            id = R.id.calendar_period_label
            textSize = 22f
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
            maxLines = 1
            isClickable = true
            isFocusable = true
        }
        fun updateMonthSheetProgress(position: Float) {
            monthExpansionAnimator?.cancel()
            renderedMonthSheetPosition = position.coerceIn(0f, 2f)
            pageSurface.findViewById<ViewGroup?>(R.id.calendar_month_view)?.let { monthView ->
                applyMonthSheetPosition(monthView, renderedMonthSheetPosition)
            }
        }

        fun settleMonthSheet(position: Float) {
            val monthView = pageSurface.findViewById<ViewGroup?>(R.id.calendar_month_view) ?: return
            val target = position.roundToInt().coerceIn(0, 2).toFloat()
            if (target != monthSheetPosition.roundToInt().toFloat()) performCalendarHaptic()
            if (target < TeachingCalendarLogic.monthSheetWeekPosition) {
                val dateKey = contractDate().format(selectedDate.time)
                sessionState.resetMonthDetailsScroll(dateKey)
                monthView.findViewById<MonthDetailsScrollView?>(
                    R.id.calendar_month_selected_details,
                )?.scrollTo(0, 0)
            }
            monthSheetPosition = target
            pageSurface.monthSheetPosition = target
            animateMonthSheetPosition(monthView, target) {
                monthSheetPosition = target
                pageSurface.monthSheetPosition = target
            }
        }

        fun render() {
            calendarRenderAction = ::render
            dismissYearPopover()
            pageSurface.swipeEnabled = selectedMode != Mode.YEAR
            pageSurface.monthSheetPosition = monthSheetPosition
            pageSurface.onMonthSheetSettled = if (selectedMode == Mode.MONTH) {
                ::settleMonthSheet
            } else {
                null
            }
            pageSurface.onMonthSheetProgress = if (selectedMode == Mode.MONTH) {
                ::updateMonthSheetProgress
            } else {
                null
            }
            periodLabel.text = periodTitle()
            val pageView: View = if (selectedMode == Mode.DAY || selectedMode == Mode.WEEK) {
                phoneDayWeekContent(::render)
            } else {
                val fixedMonth = selectedMode == Mode.MONTH
                val body = LinearLayout(activity).apply {
                    id = R.id.calendar_page_body
                    orientation = LinearLayout.VERTICAL
                    val horizontalPadding = if (selectedMode == Mode.YEAR) 16 else 0
                    val topPadding = if (selectedMode == Mode.YEAR) 16 else 8
                    setPadding(
                        activity.dp(horizontalPadding),
                        activity.dp(topPadding),
                        activity.dp(horizontalPadding),
                        activity.dp(
                            TeachingCalendarLogic.calendarContentBottomInsetDp(
                                usesBottomNavigation,
                            ),
                        ),
                    )
                    holidayStatus()?.let { message ->
                        addView(TextView(activity).apply {
                            text = message
                            textSize = 12f
                            setTextColor(Palette.muted)
                            setPadding(activity.dp(4), 0, activity.dp(4), activity.dp(8))
                        })
                    }
                    val calendar = when (selectedMode) {
                        Mode.DAY, Mode.WEEK -> error("Day and week use a fixed phone timeline layout")
                        Mode.MONTH -> monthView(::render, ::settleMonthSheet)
                        Mode.YEAR -> yearView(::render)
                    }
                    addView(calendar, LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        if (fixedMonth) 0 else ViewGroup.LayoutParams.WRAP_CONTENT,
                        if (fixedMonth) 1f else 0f,
                    ))
                }
                if (fixedMonth) {
                    body
                } else {
                    ScrollView(activity).apply {
                        isFillViewport = true
                        clipToPadding = false
                        scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
                        addView(body, ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                        ))
                    }
                }
            }
            content.removeAllViews()
            if (selectedMode == Mode.DAY || selectedMode == Mode.WEEK) {
                content.addView(spacer(activity, TeachingCalendarLogic.phoneDateStripGapDp))
                content.addView(phoneDateStrip(::render))
            }
            content.addView(
                pageSurface,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
            )
            // Build the incoming page first, then start the tab and page
            // transitions together. Starting the tab cross-fade before page
            // construction makes the indicator visibly lead heavier views.
            updatePhoneModeTabs(tabs)
            replacePhonePage(
                pageSurface,
                pageView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            animatePendingMonthDaySelection(pageView)
            UiText.localizeTree(root)
        }

        pageSurface.onPageSwipe = { direction ->
            if (selectedMode != Mode.YEAR) {
                performCalendarHaptic()
                stepDate(direction)
                pendingPageDirection = direction
                render()
            }
        }

        root.addView(LinearLayout(activity).apply {
            id = R.id.calendar_phone_header
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(activity.dp(16), activity.dp(5), activity.dp(12), activity.dp(5))
            addView(periodLabel, LinearLayout.LayoutParams(
                0,
                activity.dp(TeachingCalendarLogic.phoneNavigationHeightDp),
                1f,
            ))
            periodLabel.setOnClickListener { showDatePicker(::render) }
            addView(phoneNavigationButton("今天", 52) {
                performCalendarHaptic()
                selectedDate.timeInMillis = Calendar.getInstance(shanghai).timeInMillis
                requestCalendarDataForSelection()
                render()
            })
            addView(phoneNavigationButton("‹", 34) {
                performCalendarHaptic()
                stepDate(-1)
                pendingPageDirection = -1
                render()
            })
            addView(phoneNavigationButton("›", 34) {
                performCalendarHaptic()
                stepDate(1)
                pendingPageDirection = 1
                render()
            })
            addView(calendarImportButton(compact = true))
        })
        root.addView(LinearLayout(activity).apply {
            id = R.id.calendar_mode_switch
            orientation = LinearLayout.HORIZONTAL
            setPadding(activity.dp(3), activity.dp(3), activity.dp(3), activity.dp(3))
            background = roundedBackground(activity, Palette.surfaceVariant, radius = 10)
            Mode.entries.forEach { mode ->
                val tab = fixedTab(activity, mode.label) {
                    if (selectedMode == mode) return@fixedTab
                    performCalendarHaptic()
                    pendingModeSelectionFrom = selectedMode.takeIf {
                        availableWidthDp < TeachingCalendarLogic.compactCalendarBreakpointDp
                    }
                    pendingPageDirection = TeachingCalendarLogic.modeTransitionDirection(
                        selectedMode.ordinal,
                        mode.ordinal,
                    )
                    selectedMode = mode
                    requestCalendarDataForSelection()
                    render()
                }.apply {
                    id = when (mode) {
                        Mode.DAY -> R.id.calendar_mode_day
                        Mode.WEEK -> R.id.calendar_mode_week
                        Mode.MONTH -> R.id.calendar_mode_month
                        Mode.YEAR -> R.id.calendar_mode_year
                    }
                    minimumHeight = 0
                    layoutParams = LinearLayout.LayoutParams(
                        0,
                        activity.dp(TeachingCalendarLogic.phoneModeTabHeightDp),
                        1f,
                    )
                }
                tabs[mode] = tab
                addView(tab)
            }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(TeachingCalendarLogic.phoneModeSwitchHeightDp),
        ).apply {
            marginStart = activity.dp(12)
            marginEnd = activity.dp(12)
            topMargin = activity.dp(4)
        })
        root.addView(content, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))
        root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                calendarHostRoot = root
                holidayRepository.addObserver(root) {
                    refreshHolidayDataInPlace()
                }
                dailyInfoRepository.addObserver(root, ::handleDailyInfoChanged)
                requestCalendarDataForSelection()
                render()
            }

            override fun onViewDetachedFromWindow(view: View) {
                monthExpansionAnimator?.cancel()
                holidayRepository.removeObserver(root)
                dailyInfoRepository.removeObserver(root)
                if (calendarHostRoot === root) calendarHostRoot = null
                calendarRenderAction = null
                dismissYearPopover()
            }
        })
        render()
        return root
    }

    private fun updatePhoneModeTabs(tabs: Map<Mode, TextView>) {
        val previous = pendingModeSelectionFrom
        pendingModeSelectionFrom = null
        tabs.forEach { (mode, view) ->
            val selected = mode == selectedMode
            if (previous != null && (mode == previous || selected)) {
                val fromSelected = mode == previous
                val transition = TransitionDrawable(arrayOf(
                    roundedBackground(
                        activity,
                        if (fromSelected) Palette.segmentedSelection else Color.TRANSPARENT,
                        radius = UiMetrics.controlRadiusDp,
                    ),
                    roundedBackground(
                        activity,
                        if (selected) Palette.segmentedSelection else Color.TRANSPARENT,
                        radius = UiMetrics.controlRadiusDp,
                    ),
                )).apply { isCrossFadeEnabled = true }
                view.background = transition
                view.setTypeface(
                    view.typeface,
                    if (selected) Typeface.BOLD else Typeface.NORMAL,
                )
                view.setTextColor(Palette.text)
                transition.startTransition(TeachingCalendarLogic.pageAnimationDurationMillis.toInt())
            } else {
                view.setCompactSelectedStyle(activity, selected)
            }
        }
    }

    private fun replacePhonePage(
        container: FrameLayout,
        page: View,
        layoutParams: FrameLayout.LayoutParams,
    ) {
        val pageDirection = pendingPageDirection
        pendingPageDirection = 0

        // A rapid second selection may arrive before the previous transition
        // finishes. Keep only the newest mounted page as the outgoing surface.
        while (container.childCount > 1) container.removeViewAt(0)
        val oldPage = container.getChildAt(0)

        // Date selection and the vertical month-sheet animation deliberately
        // never share the horizontal month-pager transform. The new content is
        // mounted at x=0 and animatePendingMonthDaySelection() owns the only
        // animation for that interaction.
        if (oldPage == null || pageDirection == 0) {
            container.removeAllViews()
            page.alpha = 1f
            page.translationX = 0f
            page.translationY = 0f
            container.addView(page, layoutParams)
            return
        }

        oldPage.animate().cancel()
        oldPage.alpha = 1f
        oldPage.translationX = 0f
        oldPage.translationY = 0f
        page.animate().cancel()
        if (pageDirection != 0) {
            val distance = container.width.takeIf { it > 0 } ?: activity.dp(availableWidthDp)
            page.alpha = 1f
            val offsets = TeachingCalendarLogic.pageTransitionOffsets(
                pageDirection,
                distance.toFloat(),
            )
            page.translationX = offsets.incomingStartX
            page.translationY = 0f
            container.addView(page, layoutParams)
            val interpolator = AccelerateDecelerateInterpolator()
            oldPage.animate()
                .translationX(offsets.outgoingEndX)
                .setDuration(TeachingCalendarLogic.pageAnimationDurationMillis)
                .setInterpolator(interpolator)
                .withEndAction {
                    if (oldPage.parent === container) container.removeView(oldPage)
                }
                .start()
            page.animate()
                .translationX(0f)
                .setDuration(TeachingCalendarLogic.pageAnimationDurationMillis)
                .setInterpolator(interpolator)
                .start()
            return
        }
    }

    private fun animatePendingMonthDaySelection(root: View) {
        val startPosition = pendingMonthSelectionStartPosition ?: return
        val targetPosition = pendingMonthSelectionTargetPosition ?: return
        pendingMonthSelectionStartPosition = null
        pendingMonthSelectionTargetPosition = null
        val monthView = root.findViewById<ViewGroup?>(R.id.calendar_month_view) ?: return

        renderedMonthSheetPosition = startPosition.coerceIn(0f, 2f)
        applyMonthSheetPosition(monthView, renderedMonthSheetPosition)
        monthView.post {
            if (!monthView.isAttachedToWindow) return@post
            animateMonthSheetPosition(monthView, targetPosition) {
                monthSheetPosition = targetPosition
            }
        }
    }

    private fun animateExpandedPageIn(content: View) {
        val direction = pendingPageDirection
        pendingPageDirection = 0
        if (direction == 0) return
        content.animate().cancel()
        val distance = content.width.takeIf { it > 0 } ?: activity.dp(availableWidthDp)
        val offsets = TeachingCalendarLogic.pageTransitionOffsets(direction, distance.toFloat())
        content.alpha = 1f
        content.translationX = offsets.incomingStartX
        content.translationY = 0f
        content.animate()
            .translationX(0f)
            .setDuration(TeachingCalendarLogic.pageAnimationDurationMillis)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .start()
    }

    private fun phoneDayWeekContent(onDateChanged: () -> Unit): LinearLayout =
        LinearLayout(activity).apply {
            id = R.id.calendar_page_body
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.surface)
            setPadding(0, activity.dp(6), 0, 0)
            holidayStatus()?.let { message ->
                addView(TextView(activity).apply {
                    text = message
                    textSize = 12f
                    setTextColor(Palette.muted)
                    setPadding(activity.dp(16), activity.dp(4), activity.dp(16), activity.dp(4))
                })
                addView(spacer(activity, 4))
            }
            val timelineDays = if (selectedMode == Mode.DAY) {
                listOf(timelineDay(selectedDate))
            } else {
                weekDates().map(::timelineDay)
            }
            val callback: ((Calendar) -> Unit)? = if (selectedMode == Mode.WEEK) {
                { day ->
                    if (!sameDay(selectedDate, day)) performCalendarHaptic()
                    selectedDate.timeInMillis = day.timeInMillis
                    requestCalendarDataForSelection()
                    onDateChanged()
                }
            } else {
                null
            }
            addView(dayWeekAgendaSection(
                days = timelineDays,
                compact = true,
            ))
            addView(ScrollView(activity).apply {
                id = R.id.calendar_timeline_scroll
                isFillViewport = false
                clipToPadding = false
                scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
                setPadding(
                    0,
                    0,
                    0,
                    activity.dp(
                        TeachingCalendarLogic.calendarContentBottomInsetDp(
                            usesBottomNavigation,
                        ),
                    ),
                )
                addView(phoneTimelineView(timelineDays, callback))
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ))
        }

    private fun dayWeekAgendaSection(
        days: List<TimelineDay>,
        compact: Boolean,
    ): LinearLayout {
        val section = LinearLayout(activity).apply {
            id = R.id.calendar_day_week_agenda
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.surface)
        }
        val selectedDay = days.firstOrNull { sameDay(it.date, selectedDate) }
            ?: days.firstOrNull()
            ?: return section
        val courses = coursesOn(selectedDay.date)
        val content = LinearLayout(activity).apply {
            id = R.id.calendar_day_week_agenda_content
            orientation = LinearLayout.VERTICAL
            if (courses.isNotEmpty()) addView(compactCourseArea(selectedDay.date, compact))
            visibility = if (TeachingCalendarLogic.shouldShowDayWeekCourseContent(
                    courses.size,
                    sessionState.dayWeekAgendaExpanded,
                )
            ) {
                View.VISIBLE
            } else {
                View.GONE
            }
        }
        val indicator = ImageView(activity).apply {
            id = R.id.calendar_day_week_agenda_indicator
            setImageResource(R.drawable.ic_chevron_down)
            imageTintList = ColorStateList.valueOf(Palette.muted)
            rotation = if (sessionState.dayWeekAgendaExpanded) 180f else 0f
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            scaleType = ImageView.ScaleType.CENTER
        }
        val toggle = LinearLayout(activity).apply {
            id = R.id.calendar_day_week_agenda_toggle
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            isClickable = true
            isFocusable = true
            contentDescription = if (sessionState.dayWeekAgendaExpanded) {
                "收起当前日期课程"
            } else {
                "展开当前日期课程"
            }
            setPadding(activity.dp(if (compact) 14 else 12), 0, activity.dp(8), 0)
            addView(TextView(activity).apply {
                text = if (compact) displayMonthDayWithWeekday(selectedDay.date) else "当日课程"
                textSize = if (compact) 12f else 13f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
                includeFontPadding = false
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(TextView(activity).apply {
                text = if (courses.isEmpty()) "暂无课程" else "${courses.size} 门课"
                textSize = if (compact) 10f else 11f
                setTextColor(Palette.muted)
                includeFontPadding = false
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            })
            addView(
                indicator,
                LinearLayout.LayoutParams(activity.dp(22), ViewGroup.LayoutParams.MATCH_PARENT),
            )
            setOnClickListener {
                performCalendarHaptic()
                sessionState.dayWeekAgendaExpanded = !sessionState.dayWeekAgendaExpanded
                contentDescription = activity.uiText(if (sessionState.dayWeekAgendaExpanded) {
                    "收起当前日期课程"
                } else {
                    "展开当前日期课程"
                })
                indicator.animate().cancel()
                indicator.animate()
                    .rotation(if (sessionState.dayWeekAgendaExpanded) 180f else 0f)
                    .setDuration(TeachingCalendarLogic.agendaAnimationDurationMillis)
                    .setInterpolator(AccelerateDecelerateInterpolator())
                    .start()
                if (courses.isNotEmpty()) {
                    TransitionManager.beginDelayedTransition(
                        section,
                        AutoTransition().apply {
                            duration = TeachingCalendarLogic.agendaAnimationDurationMillis
                            interpolator = AccelerateDecelerateInterpolator()
                        },
                    )
                    content.visibility = if (sessionState.dayWeekAgendaExpanded) {
                        View.VISIBLE
                    } else {
                        View.GONE
                    }
                }
            }
        }
        section.addView(toggle, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(
                if (compact) {
                    TeachingCalendarLogic.compactAgendaHeaderHeightDp
                } else {
                    TeachingCalendarLogic.expandedAgendaHeaderHeightDp
                },
            ),
        ))
        section.addView(content)
        val hasSupplementaryItems = days.any { supplementaryItemsOn(it.date).isNotEmpty() }
        if (hasSupplementaryItems) {
            section.addView(allDayStrip(days, compact))
        }
        return section
    }

    private fun compactCourseArea(day: Calendar, compact: Boolean): LinearLayout =
        LinearLayout(activity).apply {
            id = R.id.calendar_day_week_course_area
            orientation = LinearLayout.VERTICAL
            setPadding(
                activity.dp(if (compact) 12 else 4),
                0,
                activity.dp(if (compact) 12 else 4),
                activity.dp(3),
            )
            val courses = coursesOn(day)
            courses.take(TeachingCalendarLogic.dayWeekVisibleCourseCount(courses.size))
                .forEach { course -> addView(dayWeekCourseRow(day, course)) }
        }

    private fun dayWeekCourseRow(day: Calendar, course: Course): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            isFocusable = true
            contentDescription = listOf(
                course.name,
                course.timeRange,
                course.room,
                course.teacher,
            ).filter(String::isNotEmpty).joinToString("，")
            setPadding(0, activity.dp(2), 0, activity.dp(2))
            addView(TextView(activity).apply {
                text = course.name
                UiText.preserveRawText(this)
                textSize = 12f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                includeFontPadding = false
            })
            addView(TextView(activity).apply {
                text = listOf(
                    course.timeRange,
                    course.room,
                    course.teacher.takeIf(String::isNotEmpty)?.let { "教师：$it" }.orEmpty(),
                ).filter(String::isNotEmpty).joinToString(" · ")
                textSize = 10f
                setTextColor(Palette.muted)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                includeFontPadding = false
                setPadding(0, activity.dp(1), 0, 0)
            })
            setOnClickListener { showCourseDetails(day, course) }
        }

    private fun calendarImportButton(compact: Boolean = false): TextView = TextView(activity).apply {
        id = R.id.calendar_overflow_button
        val defaultLabel = if (compact) "•••" else activity.uiText("导入手机日历")
        text = defaultLabel
        textSize = if (compact) 12f else 15f
        gravity = Gravity.CENTER
        setTextColor(if (compact) Palette.text else Palette.onPrimary)
        setTypeface(typeface, Typeface.BOLD)
        includeFontPadding = false
        if (compact) letterSpacing = 0.08f
        background = roundedBackground(
            activity,
            if (compact) Color.TRANSPARENT else Palette.primaryFill,
            radius = UiMetrics.controlRadiusDp,
        )
        isClickable = true
        isFocusable = true
        contentDescription = if (compact) "更多日历操作" else "导入手机日历"
        layoutParams = if (compact) {
            LinearLayout.LayoutParams(
                activity.dp(36),
                activity.dp(TeachingCalendarLogic.phoneNavigationHeightDp),
            )
        } else {
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, activity.dp(48))
        }
        fun beginImport() {
            text = if (compact) "…" else activity.uiText("正在导入…")
            isEnabled = false
            activity.importCachedScheduleToSystemCalendar { result ->
                if (isAttachedToWindow) {
                    text = defaultLabel
                    isEnabled = true
                }
                result.onSuccess { summary ->
                    val duplicateText = if (summary.removedDuplicates > 0) {
                        "，清理重复 ${summary.removedDuplicates} 条"
                    } else {
                        ""
                    }
                    val staleText = if (summary.removedStaleEvents > 0) {
                        "，清理失效 ${summary.removedStaleEvents} 条"
                    } else {
                        ""
                    }
                    Toast.makeText(
                        activity,
                        activity.uiText("已同步 ${summary.totalEvents} 条课程到「${summary.calendarName}」" +
                            "（新增 ${summary.insertedEvents}，更新 ${summary.updatedEvents}" +
                            "${duplicateText}${staleText}）"),
                        Toast.LENGTH_LONG,
                    ).show()
                }.onFailure { error ->
                    Toast.makeText(
                        activity,
                        activity.uiText(error.message ?: "系统日历导入失败。"),
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }

        fun confirmImport() {
            AlertDialog.Builder(activity)
                .setTitle("导入手机日历")
                .setMessage("将把本地个人课表写入手机系统日历；再次导入会更新已有课程。是否继续？")
                .setNegativeButton("取消", null)
                .setPositiveButton("确认导入") { _, _ -> beginImport() }
                .showLocalized()
        }

        setOnClickListener { anchor ->
            if (compact) {
                PopupMenu(activity, anchor).apply {
                    menu.add(
                        0,
                        R.id.calendar_import_menu_item,
                        0,
                        activity.uiText("导入手机日历"),
                    )
                    menu.add(
                        0,
                        R.id.calendar_import_favorites_menu_item,
                        1,
                        activity.uiText("导入已收藏日程"),
                    )
                    setOnMenuItemClickListener { item ->
                        when (item.itemId) {
                            R.id.calendar_import_menu_item -> {
                                confirmImport()
                                true
                            }
                            R.id.calendar_import_favorites_menu_item -> {
                                confirmFavoriteCalendarImport()
                                true
                            }
                            else -> false
                        }
                    }
                }.show()
            } else {
                confirmImport()
            }
        }
    }

    private fun favoriteCalendarImportButton(): TextView = TextView(activity).apply {
        text = activity.uiText("导入已收藏日程")
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(Palette.text)
        setTypeface(typeface, Typeface.BOLD)
        includeFontPadding = false
        background = roundedBackground(
            activity,
            Palette.surface,
            Palette.border,
            radius = UiMetrics.controlRadiusDp,
        )
        isClickable = true
        isFocusable = true
        contentDescription = text
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(48),
        )
        setOnClickListener { confirmFavoriteCalendarImport() }
    }

    private fun confirmFavoriteCalendarImport() {
        AlertDialog.Builder(activity)
            .setTitle(activity.uiText("导入已收藏日程"))
            .setMessage(activity.uiText("将把当前收藏的完整日程快照同步到系统日历；重复导入会更新已有项。是否继续？"))
            .setNegativeButton(activity.uiText("取消"), null)
            .setPositiveButton(activity.uiText("确认导入")) { _, _ ->
                activity.importFavoriteDeadlinesToSystemCalendar { result ->
                    result.onSuccess { summary ->
                        Toast.makeText(
                            activity,
                            activity.uiText("已同步 ${summary.totalEvents} 条收藏日程到「${summary.calendarName}」"),
                            Toast.LENGTH_LONG,
                        ).show()
                    }.onFailure { error ->
                        Toast.makeText(
                            activity,
                            activity.uiText(error.message ?: "收藏日程导入失败。"),
                            Toast.LENGTH_LONG,
                        ).show()
                    }
                }
            }
            .showLocalized()
    }

    private fun phoneNavigationButton(
        label: String,
        width: Int = 40,
        onClick: (() -> Unit)? = null,
    ): TextView = TextView(activity).apply {
        text = label
        textSize = if (label.length == 1) 23f else 13f
        gravity = Gravity.CENTER
        setTextColor(if (label == "今天") Palette.primaryText else Palette.text)
        setTypeface(typeface, if (label == "今天") Typeface.BOLD else Typeface.NORMAL)
        isClickable = true
        isFocusable = true
        background = roundedBackground(activity, Color.TRANSPARENT, radius = UiMetrics.controlRadiusDp)
        layoutParams = LinearLayout.LayoutParams(
            activity.dp(width),
            activity.dp(TeachingCalendarLogic.phoneNavigationHeightDp),
        )
        onClick?.let { action -> setOnClickListener { action() } }
    }

    private fun showDatePicker(onChanged: () -> Unit) {
        DatePickerDialog(
            activity,
            { _, year, month, day ->
                performCalendarHaptic()
                selectedDate.set(year, month, day, 12, 0, 0)
                selectedDate.set(Calendar.MILLISECOND, 0)
                requestCalendarDataForSelection()
                onChanged()
            },
            selectedDate.get(Calendar.YEAR),
            selectedDate.get(Calendar.MONTH),
            selectedDate.get(Calendar.DAY_OF_MONTH),
        ).show()
    }

    private fun periodTitle(): String {
        val date = when (selectedMode) {
            Mode.DAY -> SimpleDateFormat("yyyy年M月d日", displayLocale()).apply {
                timeZone = shanghai
            }.format(selectedDate.time)
            Mode.WEEK, Mode.MONTH -> SimpleDateFormat("yyyy年M月", displayLocale()).apply {
                timeZone = shanghai
            }.format(selectedDate.time)
            Mode.YEAR -> SimpleDateFormat("yyyy年", displayLocale()).apply {
                timeZone = shanghai
            }.format(selectedDate.time)
        }
        return if (selectedMode == Mode.WEEK) {
            val teachingWeek = ScheduleLogic.weekNumber(scheduleRepository.schedule, selectedDate)
            TeachingCalendarLogic.weekPeriodTitle(date, teachingWeek)
        } else {
            date
        }
    }

    private fun phoneDateStrip(onDateChanged: () -> Unit): LinearLayout =
        LinearLayout(activity).apply {
            id = R.id.calendar_date_strip
            orientation = LinearLayout.HORIZONTAL
            val today = Calendar.getInstance(shanghai)
            val leadingWidth = if (selectedMode == Mode.WEEK) {
                CalendarTimelineLogic.axisWidthDp(compact = true, showCourseSlots = false)
            } else {
                0
            }
            if (leadingWidth > 0) {
                addView(TextView(activity).apply {
                    id = R.id.calendar_week_number
                    val teachingWeek = ScheduleLogic.weekNumber(
                        scheduleRepository.schedule,
                        selectedDate,
                    )
                    text = TeachingCalendarLogic.teachingWeekAxisLabel(teachingWeek)
                    textSize = 9.5f
                    gravity = Gravity.CENTER
                    setTextColor(Palette.muted)
                    includeFontPadding = false
                    maxLines = 2
                    contentDescription = if (teachingWeek != null) {
                        "第${teachingWeek}教学周"
                    } else {
                        "暂无教学周信息"
                    }
                }, LinearLayout.LayoutParams(
                    activity.dp(leadingWidth),
                    activity.dp(TeachingCalendarLogic.phoneDateStripHeightDp),
                ))
            }
            val days = weekDates()
            days.forEach { day ->
                val selected = sameDay(day, selectedDate)
                val isToday = sameDay(day, today)
                val holidays = holidaysOn(day)
                addView(TextView(activity).apply {
                    text = buildString {
                        append(SimpleDateFormat("E", displayLocale()).apply { timeZone = shanghai }.format(day.time))
                        append('\n')
                        append(day.get(Calendar.DAY_OF_MONTH))
                    }
                    textSize = 11f
                    gravity = Gravity.CENTER
                    maxLines = 2
                    includeFontPadding = false
                    setPadding(0, activity.dp(2), 0, activity.dp(2))
                    setTextColor(when {
                        selected -> Palette.onPrimary
                        holidays.any { it.type == "holiday" } -> Palette.holiday
                        else -> Palette.text
                    })
                    setTypeface(typeface, if (selected || isToday) Typeface.BOLD else Typeface.NORMAL)
                    background = roundedBackground(
                        activity,
                        if (selected) Palette.selectedDate else Color.TRANSPARENT,
                        when {
                            isToday -> Palette.nowIndicator
                            selected -> Palette.selectedDate
                            else -> Color.TRANSPARENT
                        },
                        radius = 10,
                    ).apply {
                        if (isToday) setStroke(activity.dp(2), Palette.nowIndicator)
                    }
                    isClickable = true
                    isFocusable = true
                    contentDescription = displayMonthDayWithWeekday(day)
                    setOnClickListener {
                        if (!sameDay(selectedDate, day)) performCalendarHaptic()
                        selectedDate.timeInMillis = day.timeInMillis
                        requestCalendarDataForSelection()
                        onDateChanged()
                    }
                }, LinearLayout.LayoutParams(
                    0,
                    activity.dp(TeachingCalendarLogic.phoneDateStripHeightDp),
                    1f,
                ).apply {
                    if (!sameDay(day, days.last())) marginEnd = activity.dp(2)
                })
            }
        }

    private fun phoneDateSummary(): LinearLayout = LinearLayout(activity).apply {
        id = R.id.calendar_date_summary
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(activity.dp(16), activity.dp(5), activity.dp(16), activity.dp(5))
        val formatter = SimpleDateFormat("yyyy年M月d日 EEEE", displayLocale()).apply { timeZone = shanghai }
        addView(TextView(activity).apply {
            text = formatter.format(selectedDate.time)
            textSize = 14f
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
        }, LinearLayout.LayoutParams(0, activity.dp(26), 1f))
        val courses = coursesOn(selectedDate)
        addView(TextView(activity).apply {
            text = if (courses.isEmpty()) "暂无课程" else "${courses.size} 门课"
            textSize = 11f
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            setTextColor(Palette.muted)
            includeFontPadding = false
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, activity.dp(26)))
    }

    private fun phoneTimelineView(
        days: List<TimelineDay>,
        onDaySelected: ((Calendar) -> Unit)?,
    ): LinearLayout = LinearLayout(activity).apply {
        id = R.id.calendar_timeline
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(Palette.surface)
        addView(
            CalendarTimelineView(
                context = activity,
                days = days,
                selectedDate = selectedDate,
                onDaySelected = onDaySelected,
                onCourseSelected = ::showCourseDetails,
                compact = true,
                showDayHeader = false,
            ),
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    private fun dateNavigation(onChanged: () -> Unit): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(navigationButton("‹") {
            stepDate(-1)
            pendingPageDirection = -1
            onChanged()
        })
        addView(TextView(activity).apply {
            id = R.id.calendar_period_label
            text = contractDate().format(selectedDate.time)
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Palette.text)
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                DatePickerDialog(
                    activity,
                    { _, year, month, day ->
                        selectedDate.set(year, month, day, 12, 0, 0)
                        selectedDate.set(Calendar.MILLISECOND, 0)
                        requestCalendarDataForSelection()
                        onChanged()
                    },
                    selectedDate.get(Calendar.YEAR),
                    selectedDate.get(Calendar.MONTH),
                    selectedDate.get(Calendar.DAY_OF_MONTH),
                ).show()
            }
            layoutParams = LinearLayout.LayoutParams(0, activity.dp(44), 1f).apply {
                marginStart = activity.dp(6)
                marginEnd = activity.dp(6)
            }
        })
        addView(navigationButton("今天", width = 66) {
            selectedDate.timeInMillis = Calendar.getInstance(shanghai).timeInMillis
            requestCalendarDataForSelection()
            onChanged()
        })
        addView(navigationButton("›") {
            stepDate(1)
            pendingPageDirection = 1
            onChanged()
        }.apply {
            (layoutParams as LinearLayout.LayoutParams).marginStart = activity.dp(6)
        })
    }

    private fun navigationButton(label: String, width: Int = 44, onClick: () -> Unit): TextView =
        TextView(activity).apply {
            text = label
            textSize = if (label.length == 1) 24f else 14f
            gravity = Gravity.CENTER
            setTextColor(Palette.text)
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            isClickable = true
            isFocusable = true
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(activity.dp(width), activity.dp(44))
        }

    private fun dateSummary(): LinearLayout = surface(activity).apply {
        val formatter = SimpleDateFormat("yyyy年M月d日 EEEE", displayLocale()).apply { timeZone = shanghai }
        addView(TextView(activity).apply {
            text = formatter.format(selectedDate.time)
            textSize = 20f
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
        })
        val courses = coursesOn(selectedDate)
        val holidays = holidaysOn(selectedDate)
        addView(TextView(activity).apply {
            text = buildList {
                add(if (courses.isEmpty()) "暂无课程" else "${courses.size} 门课")
                holidays.forEach { add("${if (it.type == "holiday") "休" else "班"} ${it.name}") }
            }.joinToString("  ·  ")
            textSize = 14f
            setTextColor(if (holidays.any { it.type == "holiday" }) Palette.holiday else Palette.muted)
            setPadding(0, activity.dp(5), 0, 0)
        })
    }

    private fun dayView(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "当日时间轴"))
        val days = listOf(timelineDay(selectedDate))
        addView(dayWeekAgendaSection(
            days = days,
            compact = false,
        ))
        val timeline = CalendarTimelineView(
            activity,
            days,
            selectedDate,
            onCourseSelected = ::showCourseDetails,
        )
        addView(timeline, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
    }

    private fun weekView(onDateChanged: () -> Unit): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "本周时间轴"))
        val days = weekDates()
        val timelineDays = days.map(::timelineDay)
        val selectDay: (Calendar) -> Unit = { day ->
            selectedDate.timeInMillis = day.timeInMillis
            requestCalendarDataForSelection()
            onDateChanged()
        }
        addView(dayWeekAgendaSection(
            days = timelineDays,
            compact = false,
        ))
        addView(
            CalendarTimelineView(
                context = activity,
                days = timelineDays,
                selectedDate = selectedDate,
                onDaySelected = selectDay,
                onCourseSelected = ::showCourseDetails,
            ),
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    private fun monthView(
        onDateChanged: () -> Unit,
        onPositionChanged: (Float) -> Unit,
    ): LinearLayout = surface(activity).apply {
        id = R.id.calendar_month_view
        clipChildren = false
        clipToPadding = false
        val compactMonth = availableWidthDp < TeachingCalendarLogic.compactCalendarBreakpointDp
        if (compactMonth) {
            setBackgroundColor(Palette.background)
            val horizontalPadding = TeachingCalendarLogic.monthHorizontalPaddingDp(
                usesBottomNavigation,
            )
            setPadding(
                activity.dp(horizontalPadding),
                activity.dp(8),
                activity.dp(horizontalPadding),
                0,
            )
        }
        val monthTitle = SimpleDateFormat("yyyy年M月", displayLocale()).apply { timeZone = shanghai }
        if (!compactMonth) {
            addView(sectionTitle(activity, monthTitle.format(selectedDate.time)))
        }
        addView(weekdayHeader())
        val dates = monthGridDates()
        val selectedWeekIndex = dates.indexOfFirst { sameDay(it, selectedDate) }
            .coerceAtLeast(0) / 7
        val grid = LinearLayout(activity).apply {
            id = R.id.calendar_month_grid
            tag = selectedWeekIndex
            orientation = LinearLayout.VERTICAL
            dates.chunked(7).forEachIndexed { rowIndex, week ->
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    week.forEach { day ->
                        addView(monthDayCell(
                            day = day,
                            onDateChanged = onDateChanged,
                            sheetPosition = renderedMonthSheetPosition,
                        ))
                    }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    activity.dp(TeachingCalendarLogic.monthRowHeightDp(
                        position = renderedMonthSheetPosition,
                        rowIndex = rowIndex,
                        selectedWeekIndex = selectedWeekIndex,
                        expandedHeightDp = expandedMonthCellHeightDp,
                    )),
                ))
            }
        }
        addView(grid, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
        addView(monthExpansionHandle(onPositionChanged))
        val detailsDateKey = contractDate().format(selectedDate.time)
        addView(MonthDetailsScrollView(activity).apply {
            id = R.id.calendar_month_selected_details
            tag = detailsDateKey
            visibility = if (renderedMonthSheetPosition <= 0.01f) View.GONE else View.VISIBLE
            isDetailsScrollingEnabled =
                renderedMonthSheetPosition >= TeachingCalendarLogic.monthSheetWeekPosition - 0.01f
            isFillViewport = false
            isNestedScrollingEnabled = true
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            background = roundedBackground(
                activity,
                Palette.background,
                radius = UiMetrics.surfaceRadiusDp,
            )
            outlineProvider = ViewOutlineProvider.BACKGROUND
            clipToOutline = true
            clipChildren = true
            clipToPadding = true
            scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
            setPadding(0, activity.dp(2), 0, activity.dp(24))
            addView(monthSelectedDetails(selectedDate))
            val restoredScrollY = sessionState.savedMonthDetailsScrollY(detailsDateKey)
            var restoringScroll = true
            setOnScrollChangeListener { _, _, scrollY, _, _ ->
                if (!restoringScroll) {
                    sessionState.updateMonthDetailsScroll(detailsDateKey, scrollY)
                }
            }
            post {
                scrollTo(0, restoredScrollY)
                post { restoringScroll = false }
            }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))
        if (compactMonth) {
            post {
                val density = resources.displayMetrics.density
                val weekday = findViewById<View>(R.id.calendar_month_weekday_header)
                val weekdayMargins = weekday.layoutParams as? ViewGroup.MarginLayoutParams
                val weekdayReservedPx = weekday.height +
                    (weekdayMargins?.topMargin ?: 0) + (weekdayMargins?.bottomMargin ?: 0)
                val dragHandle = findViewById<View>(R.id.calendar_month_drag_handle)
                expandedMonthCellHeightDp = TeachingCalendarLogic.expandedMonthCellHeightDp(
                    monthViewHeightDp = (height / density).toInt(),
                    verticalPaddingDp = ceil(
                        (paddingTop + paddingBottom) / density.toDouble(),
                    ).toInt(),
                    weekdayReservedHeightDp = ceil(
                        weekdayReservedPx / density.toDouble(),
                    ).toInt(),
                    dragHandleReservedHeightDp = ceil(
                        dragHandle.height / density.toDouble(),
                    ).toInt(),
                )
                applyMonthSheetPosition(this, renderedMonthSheetPosition)
            }
        }
    }

    private fun monthExpansionHandle(onPositionChanged: (Float) -> Unit): FrameLayout =
        FrameLayout(activity).apply {
            id = R.id.calendar_month_drag_handle
            isClickable = true
            isFocusable = true
            clipChildren = false
            clipToPadding = false
            elevation = activity.dp(2).toFloat()
            contentDescription = monthSheetContentDescription(renderedMonthSheetPosition)
            setOnClickListener {
                val target = when (renderedMonthSheetPosition.roundToInt()) {
                    0 -> 1f
                    1 -> 0f
                    else -> 1f
                }
                onPositionChanged(target)
            }
            addView(MonthExpansionIndicatorView(activity).apply {
                id = R.id.calendar_month_drag_indicator
                setExpansionProgress(
                    TeachingCalendarLogic.monthCellExpansionProgress(renderedMonthSheetPosition),
                )
            }, FrameLayout.LayoutParams(activity.dp(44), activity.dp(18), Gravity.CENTER))
        }.also {
            it.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(TeachingCalendarLogic.monthDragHandleHeightDp),
            )
        }

    private fun weekdayHeader(): LinearLayout = LinearLayout(activity).apply {
        id = R.id.calendar_month_weekday_header
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(TeachingCalendarLogic.monthWeekdayHeaderHeightDp),
        ).apply {
            bottomMargin = activity.dp(TeachingCalendarLogic.monthWeekdayHeaderBottomMarginDp)
        }
        val labels = if (AppLocale.isEnglish(activity)) {
            listOf("M", "T", "W", "T", "F", "S", "S")
        } else {
            listOf("一", "二", "三", "四", "五", "六", "日")
        }
        labels.forEach { label ->
            addView(TextView(activity).apply {
                text = label
                textSize = 12f
                gravity = Gravity.CENTER
                setTextColor(Palette.muted)
                setTypeface(typeface, Typeface.BOLD)
                layoutParams = LinearLayout.LayoutParams(0, activity.dp(18), 1f)
            })
        }
    }

    private fun monthDayCell(
        day: Calendar,
        onDateChanged: () -> Unit,
        sheetPosition: Float,
    ): LinearLayout {
        return LinearLayout(activity).apply {
            tag = MonthDayCellState(day.timeInMillis)
            orientation = LinearLayout.VERTICAL
            isClickable = true
            isFocusable = true
            setOnClickListener {
                if (!sameDay(selectedDate, day) ||
                    renderedMonthSheetPosition.roundToInt() !=
                    TeachingCalendarLogic.monthSheetDetailsPosition.roundToInt()
                ) {
                    performCalendarHaptic()
                }
                val previousPosition = renderedMonthSheetPosition
                val monthDirection = TeachingCalendarLogic.monthSelectionTransitionDirection(
                    fromYear = selectedDate.get(Calendar.YEAR),
                    fromMonth = selectedDate.get(Calendar.MONTH),
                    toYear = day.get(Calendar.YEAR),
                    toMonth = day.get(Calendar.MONTH),
                )
                val targetPosition = TeachingCalendarLogic.monthDaySelectionTargetPosition()
                monthExpansionAnimator?.cancel()
                selectedDate.timeInMillis = day.timeInMillis
                monthSheetPosition = targetPosition
                renderedMonthSheetPosition = previousPosition
                pendingMonthSelectionStartPosition = previousPosition
                pendingMonthSelectionTargetPosition = targetPosition
                if (monthDirection != 0) pendingPageDirection = monthDirection
                sessionState.resetMonthDetailsScroll(contractDate().format(selectedDate.time))
                requestCalendarDataForSelection()
                onDateChanged()
            }
            addView(TextView(activity).apply {
                id = R.id.calendar_month_day_label
                text = day.get(Calendar.DAY_OF_MONTH).toString()
                gravity = Gravity.CENTER
                maxLines = 1
            })
            addView(LinearLayout(activity).apply {
                id = R.id.calendar_month_expanded_entries
                orientation = LinearLayout.VERTICAL
            })
            addView(TextView(activity).apply {
                id = R.id.calendar_month_compact_marker
                textSize = 9.5f
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            })
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.MATCH_PARENT,
                1f,
            ).apply {
                marginEnd = activity.dp(2)
                bottomMargin = activity.dp(2)
            }
            bindMonthDayCell(this, day, sheetPosition)
        }
    }

    private fun bindMonthDayCell(
        cell: LinearLayout,
        day: Calendar,
        sheetPosition: Float,
        measuredCellHeightDp: Int? = null,
    ) {
        val courses = coursesOn(day)
        val holidays = holidaysOn(day)
        val assignments = assignmentsOn(day)
        val schoolNotices = schoolNoticesOn(day)
        val publicDeadlines = publicDeadlinesOn(day)
        val inMonth = day.get(Calendar.MONTH) == selectedDate.get(Calendar.MONTH) &&
            day.get(Calendar.YEAR) == selectedDate.get(Calendar.YEAR)
        val selected = sameDay(day, selectedDate)
        val today = sameDay(day, Calendar.getInstance(shanghai))
        val supplementaryKinds = YearCalendarLogic.supplementaryKinds(
            assignmentCount = assignments.size,
            schoolNoticeCount = schoolNotices.size,
            publicDeadlineCount = publicDeadlines.size,
        )
        cell.background = calendarCellBackground(
            selected = selected,
            today = today,
            courseCount = courses.size,
            muted = !inMonth,
            supplementaryKinds = supplementaryKinds,
        )
        cell.contentDescription = buildList {
            add(displayMonthDay(day))
            holidays.forEach { add(it.name) }
            courses.forEach { add("${it.name} ${it.timeRange} ${it.room} ${it.teacher}") }
            assignments.forEach {
                add("${activity.uiText("作业 DDL")} ${it.title} ${it.deadline}")
            }
            schoolNotices.forEach {
                add("${activity.uiText("校内竞赛通知")} ${it.name} ${it.deadline}")
            }
            publicDeadlines.forEach {
                add("${activity.uiText(deadlineKindTitle(it.kind))} ${it.name} ${it.deadline}")
            }
        }.joinToString(if (AppLocale.isEnglish(activity)) ", " else "，")
        cell.findViewById<TextView>(R.id.calendar_month_day_label).apply {
            val showsTodayBadge = today && supplementaryKinds.isNotEmpty()
            setTypeface(typeface, if (selected || today) Typeface.BOLD else Typeface.NORMAL)
            setTextColor(when {
                showsTodayBadge -> Palette.onPrimary
                selected -> Palette.onPrimary
                !inMonth -> Palette.outOfMonth
                holidays.any { it.type == "holiday" } -> Palette.holiday
                else -> Palette.text
            })
            background = if (showsTodayBadge) {
                roundedBackground(activity, Palette.nowIndicator, radius = 999)
            } else {
                null
            }
            val horizontalPadding = if (showsTodayBadge) activity.dp(5) else 0
            setPadding(horizontalPadding, 0, horizontalPadding, 0)
        }
        val entries = buildList {
            holidays.forEach { item ->
                add(MonthCalendarEntry(
                    title = activity.uiText(if (item.type == "holiday") "休" else "班") +
                        " ${item.name}",
                    kind = MonthCalendarEntryKind.HOLIDAY,
                ))
            }
            courses.forEach { course ->
                add(MonthCalendarEntry(course.name, MonthCalendarEntryKind.COURSE))
            }
            assignments.forEach { assignment ->
                add(MonthCalendarEntry(
                    "${activity.uiText("作")} ${assignment.title}",
                    MonthCalendarEntryKind.ASSIGNMENT,
                ))
            }
            schoolNotices.forEach { notice ->
                add(MonthCalendarEntry(
                    "${activity.uiText("校")} ${notice.name}",
                    MonthCalendarEntryKind.SCHOOL_NOTICE,
                    notice,
                ))
            }
            publicDeadlines.forEach { deadline ->
                add(MonthCalendarEntry(
                    "${activity.uiText("公")} ${deadline.name}",
                    MonthCalendarEntryKind.PUBLIC_DEADLINE,
                    deadline,
                ))
            }
        }
        cell.findViewById<LinearLayout>(R.id.calendar_month_expanded_entries).apply {
            tag = MonthEntriesRenderState(entries, selected, day.timeInMillis)
        }
        cell.findViewById<TextView>(R.id.calendar_month_compact_marker).apply {
            text = buildString {
                holidays.firstOrNull()?.let {
                    append(activity.uiText(if (it.type == "holiday") "休" else "班"))
                }
                if (holidays.isNotEmpty() && courses.isNotEmpty()) append("  ")
                repeat(courses.size.coerceAtMost(3)) { append("•") }
                if (assignments.isNotEmpty()) append("  ${activity.uiText("作")}${assignments.size}")
                if (schoolNotices.isNotEmpty()) append("  ${activity.uiText("校")}${schoolNotices.size}")
                if (publicDeadlines.isNotEmpty()) {
                    append("  ${activity.uiText("公")}${publicDeadlines.size}")
                }
            }
            setTextColor(when {
                selected -> Palette.onPrimary
                assignments.isNotEmpty() -> Palette.assignment
                schoolNotices.isNotEmpty() -> Palette.schoolNotice
                publicDeadlines.isNotEmpty() -> Palette.publicDeadline
                else -> Palette.muted
            })
        }
        val expandedProgress = TeachingCalendarLogic.monthCellExpansionProgress(sheetPosition)
        val initialCellHeightDp = measuredCellHeightDp
            ?: TeachingCalendarLogic.monthRowHeightDp(
                position = sheetPosition,
                rowIndex = 0,
                selectedWeekIndex = 0,
                expandedHeightDp = expandedMonthCellHeightDp,
            )
        applyMonthDayCellProgress(cell, expandedProgress, initialCellHeightDp)
        UiText.localizeTree(cell)
    }

    private fun applyMonthDayCellProgress(
        cell: LinearLayout,
        progress: Float,
        cellHeightDp: Int,
    ) {
        val resolved = progress.coerceIn(0f, 1f)
        cell.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        val markerHeightDp = TeachingCalendarLogic.interpolateMonthMetric(12, 0, resolved)
        val bottomPaddingDp = TeachingCalendarLogic.interpolateMonthMetric(5, 2, resolved)
        cell.setPadding(
            activity.dp(TeachingCalendarLogic.interpolateMonthMetric(4, 3, resolved)),
            activity.dp(TeachingCalendarLogic.expandedMonthDayTopPaddingDp),
            activity.dp(TeachingCalendarLogic.interpolateMonthMetric(4, 3, resolved)),
            activity.dp(bottomPaddingDp),
        )
        cell.findViewById<TextView>(R.id.calendar_month_day_label).apply {
            textSize = 15f
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(24),
            )
        }
        cell.findViewById<LinearLayout>(R.id.calendar_month_expanded_entries).apply {
            val availableHeightDp = TeachingCalendarLogic.monthEntryAvailableHeightDp(
                cellHeightDp = cellHeightDp,
                expandedProgress = resolved,
            )
            visibility = if (resolved <= 0.01f) View.GONE else View.VISIBLE
            alpha = resolved
            layoutParams = layoutParams.apply {
                height = activity.dp(availableHeightDp)
            }
            renderMonthEntries(this, availableHeightDp)
        }
        cell.findViewById<TextView>(R.id.calendar_month_compact_marker).apply {
            visibility = if (resolved >= 0.99f) View.GONE else View.VISIBLE
            alpha = 1f - resolved
            includeFontPadding = false
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(markerHeightDp),
            )
        }
    }

    private fun renderMonthEntries(container: LinearLayout, availableHeightDp: Int) {
        val state = container.tag as? MonthEntriesRenderState ?: return
        val slotCapacity = TeachingCalendarLogic.monthEntrySlotCapacity(availableHeightDp)
        if (state.slotCapacity == slotCapacity) return
        state.slotCapacity = slotCapacity
        container.removeAllViews()
        if (slotCapacity <= 0) return
        val visibleCount = TeachingCalendarLogic.visibleMonthEntryCount(
            state.entries.size,
            slotCapacity,
        )
        state.entries.take(visibleCount).forEach { entry ->
            container.addView(monthEntryView(entry, state.selected), LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(14),
            ).apply { topMargin = activity.dp(1) })
        }
        TeachingCalendarLogic.hiddenMonthEntryCount(state.entries.size, slotCapacity)
            .takeIf { it > 0 }
            ?.let { hiddenCount ->
                val overflow = monthEntryView(
                    MonthCalendarEntry("+$hiddenCount", MonthCalendarEntryKind.OVERFLOW),
                    state.selected,
                ).apply {
                    contentDescription = activity.uiText(
                        TeachingCalendarLogic.monthOverflowDescription(hiddenCount),
                    )
                }
                container.addView(overflow, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    activity.dp(14),
                ).apply { topMargin = activity.dp(1) })
            }
    }

    private fun applyMonthSheetPosition(
        monthView: ViewGroup,
        position: Float,
    ) {
        val resolved = position.coerceIn(0f, 2f)
        renderedMonthSheetPosition = resolved
        val expandedProgress = TeachingCalendarLogic.monthCellExpansionProgress(resolved)
        val grid = monthView.findViewById<ViewGroup>(R.id.calendar_month_grid)
        val selectedWeekIndex = (grid.tag as? Int) ?: 0
        repeat(grid.childCount) { rowIndex ->
            val row = grid.getChildAt(rowIndex) as ViewGroup
            val rowHeightDp = TeachingCalendarLogic.monthRowHeightDp(
                position = resolved,
                rowIndex = rowIndex,
                selectedWeekIndex = selectedWeekIndex,
                expandedHeightDp = expandedMonthCellHeightDp,
            )
            row.layoutParams = row.layoutParams.apply {
                height = activity.dp(rowHeightDp)
            }
            repeat(row.childCount) { cellIndex ->
                applyMonthDayCellProgress(
                    row.getChildAt(cellIndex) as LinearLayout,
                    expandedProgress,
                    rowHeightDp,
                )
            }
        }
        monthView.findViewById<MonthDetailsScrollView>(R.id.calendar_month_selected_details).apply {
            visibility = if (resolved <= 0.01f) View.GONE else View.VISIBLE
            alpha = resolved.coerceIn(0f, 1f)
            isDetailsScrollingEnabled =
                resolved >= TeachingCalendarLogic.monthSheetWeekPosition - 0.01f
        }
        monthView.findViewById<View>(R.id.calendar_month_drag_handle).apply {
            contentDescription = monthSheetContentDescription(resolved)
        }
        monthView.findViewById<MonthExpansionIndicatorView>(R.id.calendar_month_drag_indicator)
            .setExpansionProgress(expandedProgress)
        monthView.requestLayout()
    }

    private fun animateMonthSheetPosition(
        monthView: ViewGroup,
        targetPosition: Float,
        onSettled: () -> Unit,
    ) {
        monthExpansionAnimator?.cancel()
        val target = targetPosition.coerceIn(0f, 2f)
        val start = renderedMonthSheetPosition.coerceIn(0f, 2f)
        if (abs(target - start) <= 0.001f) {
            renderedMonthSheetPosition = target
            applyMonthSheetPosition(monthView, target)
            onSettled()
            return
        }
        monthExpansionAnimator = ValueAnimator.ofFloat(start, target).apply {
            duration = (120L + 160L * abs(target - start)).roundToInt().toLong()
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                renderedMonthSheetPosition = animator.animatedValue as Float
                if (monthView.isAttachedToWindow) {
                    applyMonthSheetPosition(monthView, renderedMonthSheetPosition)
                }
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                private var cancelled = false

                override fun onAnimationCancel(animation: android.animation.Animator) {
                    cancelled = true
                }

                override fun onAnimationEnd(animation: android.animation.Animator) {
                    if (cancelled) return
                    renderedMonthSheetPosition = target
                    if (monthView.isAttachedToWindow) {
                        applyMonthSheetPosition(monthView, target)
                    }
                    onSettled()
                    monthExpansionAnimator = null
                }
            })
            start()
        }
    }

    private fun monthSheetContentDescription(position: Float): String =
        when (position.roundToInt().coerceIn(0, 2)) {
            0 -> "收起月历并显示当日日程"
            1 -> "展开月历"
            else -> "显示完整月份"
        }

    private fun monthEntryView(
        entry: MonthCalendarEntry,
        selected: Boolean,
    ): TextView = TextView(activity).apply {
        id = R.id.calendar_month_entry
        text = entry.title
        UiText.preserveRawText(this)
        textSize = 9.5f
        gravity = Gravity.CENTER_VERTICAL
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        setPadding(activity.dp(3), 0, activity.dp(3), 0)
        val accent = monthEntryAccent(entry.kind)
        setTextColor(if (selected) Palette.onPrimary else accent)
        background = roundedBackground(
            activity,
            if (selected) {
                blend(accent, Palette.selectedDate, 0.52f)
            } else {
                blend(accent, Palette.surface, 0.14f)
            },
            blend(accent, Palette.border, 0.42f),
            radius = 4,
            borderWidthDp = 0.75f,
        )
        disableMonthGridEntryInteraction()
    }

    private fun yearView(onDateChanged: () -> Unit): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(Palette.background)
        val year = selectedDate.get(Calendar.YEAR)
        addView(TextView(activity).apply {
            text = "颜色越深表示当天课程越多，彩色边框表示作业与 DDL"
            textSize = 12f
            setTextColor(Palette.muted)
            includeFontPadding = false
            setPadding(0, 0, 0, activity.dp(12))
        })
        addView(
            YearCalendarView(
                context = activity,
                year = year,
                days = yearCalendarDays(year),
                availableWidthDp = availableWidthDp,
                initialSelectedDate = selectedDate,
                onDateSelected = { anchor, day, tapX, tapY ->
                    performCalendarHaptic()
                    selectedDate.timeInMillis = day.timeInMillis
                    showDayPopover(anchor, day, tapX, tapY, onDateChanged)
                },
                onMonthSelected = { month ->
                    performCalendarHaptic()
                    selectedDate.timeInMillis = month.timeInMillis
                    pendingModeSelectionFrom = selectedMode
                    pendingPageDirection = TeachingCalendarLogic.modeTransitionDirection(
                        selectedMode.ordinal,
                        Mode.MONTH.ordinal,
                    )
                    selectedMode = Mode.MONTH
                    requestCalendarDataForSelection()
                    onDateChanged()
                },
            ).also {
                it.id = R.id.calendar_year_view
                activeYearCalendar = it
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    private fun allDayStrip(
        days: List<TimelineDay>,
        compact: Boolean,
    ): View {
        if (days.size == 1) {
            return singleDayAllDayStrip(days.first())
        }
        return LinearLayout(activity).apply {
            id = R.id.calendar_all_day_strip
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Palette.surface)
            val showCourseSlots = !compact || days.size == 1
            addView(TextView(activity).apply {
            text = "全天"
            textSize = if (compact) 11f else 12f
            gravity = Gravity.CENTER
            setTextColor(Palette.muted)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
            }, LinearLayout.LayoutParams(
                activity.dp(CalendarTimelineLogic.axisWidthDp(compact, showCourseSlots)),
                activity.dp(40),
            ))
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                days.forEach { day ->
                val items = supplementaryItemsOn(day.date)
                val compactWeek = compact && days.size > 1
                val visibleCount = TeachingCalendarLogic.agendaVisibleItemCount(
                    items.size,
                    compactWeek,
                )
                val hiddenCount = TeachingCalendarLogic.agendaHiddenItemCount(
                    items.size,
                    compactWeek,
                )
                val accent = items.firstOrNull()?.let { supplementaryAccent(it.kind) }
                    ?: Palette.muted
                addView(TextView(activity).apply {
                    text = buildList {
                        items.take(visibleCount).forEach { add(it.title) }
                        if (hiddenCount > 0) add("+$hiddenCount")
                    }.joinToString(" · ")
                    textSize = if (compactWeek) 9.5f else 11f
                    gravity = Gravity.CENTER
                    maxLines = if (compactWeek) 1 else 2
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    setPadding(activity.dp(3), 0, activity.dp(3), 0)
                    setTextColor(accent)
                    background = if (items.isNotEmpty()) {
                        roundedBackground(
                            activity,
                            blend(accent, Palette.surface, 0.13f),
                            blend(accent, Palette.border, 0.35f),
                            radius = 4,
                            borderWidthDp = 0.75f,
                        )
                    } else {
                        null
                    }
                    isClickable = items.isNotEmpty()
                    isFocusable = items.isNotEmpty()
                    contentDescription = if (items.isNotEmpty()) {
                        val date = displayMonthDay(day.date)
                        "$date，全天，$text"
                    } else {
                        null
                    }
                    setOnClickListener {
                        if (items.isNotEmpty()) {
                            showDayWeekAllDayDialog(day.date, items)
                        }
                    }
                }, LinearLayout.LayoutParams(0, activity.dp(if (compactWeek) 36 else 48), 1f).apply {
                    marginStart = activity.dp(2)
                    marginEnd = activity.dp(2)
                })
                }
            }, LinearLayout.LayoutParams(0, activity.dp(if (compact && days.size > 1) 40 else 52), 1f))
        }
    }

    private fun singleDayAllDayStrip(
        day: TimelineDay,
    ): HorizontalScrollView = HorizontalScrollView(activity).apply {
        id = R.id.calendar_all_day_strip
        isHorizontalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        setBackgroundColor(Palette.surface)
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(activity.dp(16), activity.dp(8), activity.dp(16), activity.dp(8))
            addView(TextView(activity).apply {
                text = "全天"
                textSize = 12f
                setTextColor(Palette.muted)
                includeFontPadding = false
                gravity = Gravity.CENTER_VERTICAL
            })
            val items = supplementaryItemsOn(day.date)
            items.take(3).forEach { item ->
                val accent = supplementaryAccent(item.kind)
                addView(TextView(activity).apply {
                    text = "${displayMonthDay(day.date)} · ${item.title}"
                    textSize = 11f
                    setTextColor(accent)
                    setTypeface(typeface, Typeface.BOLD)
                    includeFontPadding = false
                    gravity = Gravity.CENTER
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    background = roundedBackground(
                        activity,
                        blend(accent, Palette.surface, 0.13f),
                        blend(accent, Palette.border, 0.35f),
                        radius = 12,
                        borderWidthDp = 0.75f,
                    )
                    setPadding(activity.dp(10), activity.dp(5), activity.dp(10), activity.dp(5))
                    isClickable = true
                    isFocusable = true
                    contentDescription = "${displayMonthDay(day.date)}，全天，${item.title}"
                    setOnClickListener {
                        showDayWeekAllDayDialog(day.date, items)
                    }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { marginStart = activity.dp(8) })
            }
            val hiddenCount = (items.size - 3).coerceAtLeast(0)
            if (hiddenCount > 0) {
                addView(TextView(activity).apply {
                    text = "+$hiddenCount"
                    textSize = 11f
                    setTextColor(Palette.primaryText)
                    setTypeface(typeface, Typeface.BOLD)
                    includeFontPadding = false
                    gravity = Gravity.CENTER
                    background = roundedBackground(
                        activity,
                        Palette.surfaceVariant,
                        Palette.border,
                        radius = 7,
                    )
                    setPadding(activity.dp(9), activity.dp(5), activity.dp(9), activity.dp(5))
                    isClickable = true
                    isFocusable = true
                    contentDescription = "查看其余 $hiddenCount 项全天日程"
                    setOnClickListener { showDayWeekAllDayDialog(day.date, items) }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { marginStart = activity.dp(8) })
            }
        })
    }

    private fun showDayWeekAllDayDialog(
        day: Calendar,
        items: List<CalendarSupplementaryItem>,
    ) {
        showCenteredAgendaDialog(
            title = "${activity.uiText("全天日程")} · ${displayMonthDayWithWeekday(day)}",
            rows = items.map { item ->
                CenteredAgendaRow(
                    title = item.title,
                    subtitle = item.subtitle,
                    accent = supplementaryAccent(item.kind),
                    deadlineItem = item.deadlineItem,
                )
            },
            contentDescription = activity.uiText(
                if (selectedMode == Mode.WEEK) "周视图全天日程弹窗" else "日视图全天日程弹窗",
            ),
        )
    }

    private fun showCenteredAgendaDialog(
        title: String,
        rows: List<CenteredAgendaRow>,
        contentDescription: String,
    ) {
        performCalendarHaptic()
        val dialog = Dialog(activity).apply {
            requestWindowFeature(Window.FEATURE_NO_TITLE)
        }
        val panel = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            this.contentDescription = contentDescription
            background = roundedBackground(
                activity,
                Palette.surface,
                Palette.border,
                radius = 14,
            )
            setPadding(activity.dp(20), activity.dp(18), activity.dp(20), activity.dp(14))
            addView(TextView(activity).apply {
                text = title
                textSize = 18f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
                includeFontPadding = false
                setPadding(0, 0, 0, activity.dp(12))
            })
            addView(ScrollView(activity).apply {
                isVerticalScrollBarEnabled = false
                overScrollMode = View.OVER_SCROLL_NEVER
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    rows.forEach { row ->
                        addView(supplementaryDetailRow(
                            label = "•",
                            title = row.title,
                            subtitle = row.subtitle.orEmpty(),
                            accent = row.accent,
                            deadlineItem = row.deadlineItem,
                        ))
                    }
                })
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
            addView(TextView(activity).apply {
                text = activity.uiText("完成")
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(Palette.primaryText)
                setTypeface(typeface, Typeface.BOLD)
                isClickable = true
                isFocusable = true
                background = roundedBackground(
                    activity,
                    Palette.surfaceVariant,
                    radius = 8,
                )
                setOnClickListener { dialog.dismiss() }
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(42),
            ).apply { topMargin = activity.dp(12) })
        }
        dialog.setContentView(panel)
        dialog.setCanceledOnTouchOutside(true)
        dialog.show()
        UiText.localizeDialog(dialog)
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setGravity(Gravity.CENTER)
            val maximumWidth = activity.dp(440)
            val availableWidth = activity.resources.displayMetrics.widthPixels - activity.dp(32)
            setLayout(minOf(maximumWidth, availableWidth), WindowManager.LayoutParams.WRAP_CONTENT)
        }
    }

    private fun supplementaryAccent(kind: CalendarSupplementaryKind): Int = when (kind) {
        CalendarSupplementaryKind.HOLIDAY -> Palette.holiday
        CalendarSupplementaryKind.ASSIGNMENT -> Palette.assignment
        CalendarSupplementaryKind.SCHOOL_NOTICE -> Palette.schoolNotice
        CalendarSupplementaryKind.PUBLIC_DEADLINE -> Palette.publicDeadline
    }

    private fun monthEntryAccent(kind: MonthCalendarEntryKind): Int = when (kind) {
        MonthCalendarEntryKind.HOLIDAY -> Palette.holiday
        MonthCalendarEntryKind.COURSE -> Palette.primary
        MonthCalendarEntryKind.ASSIGNMENT -> Palette.assignment
        MonthCalendarEntryKind.SCHOOL_NOTICE -> Palette.schoolNotice
        MonthCalendarEntryKind.PUBLIC_DEADLINE -> Palette.publicDeadline
        MonthCalendarEntryKind.OVERFLOW -> Palette.primaryText
    }

    private fun showDayPopover(
        anchor: YearCalendarView,
        day: Calendar,
        tapX: Float,
        tapY: Float,
        onDateChanged: () -> Unit,
    ) {
        dismissYearPopover()
        anchor.selectDate(day)
        activePopupAnchor = anchor
        requestDailyInfoForDates(listOf(day))

        val visibleFrame = Rect().also(anchor::getWindowVisibleDisplayFrame)
        val panelWidth = minOf(activity.dp(300), visibleFrame.width() - activity.dp(32))
        val maximumHeight = (visibleFrame.height() - activity.dp(32)).coerceAtLeast(activity.dp(112))
        val panel = ScrollView(activity).apply {
            scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            setPadding(activity.dp(14), activity.dp(14), activity.dp(14), activity.dp(14))
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(selectedDayDetails(day, includeSupplementary = true))
                    activePopupDetailsHost = this
                    activePopupDateMillis = day.timeInMillis
                })
                addView(spacer(activity, 12))
                addView(TextView(activity).apply {
                    text = "跳转到"
                    textSize = 12f
                    setTextColor(Palette.muted)
                    setPadding(0, 0, 0, activity.dp(6))
                })
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    listOf(Mode.DAY, Mode.WEEK, Mode.MONTH).forEach { mode ->
                        addView(fixedTab(activity, mode.label) {
                            performCalendarHaptic()
                            selectedDate.timeInMillis = day.timeInMillis
                            pendingModeSelectionFrom = selectedMode.takeIf {
                                availableWidthDp < TeachingCalendarLogic.compactCalendarBreakpointDp
                            }
                            pendingPageDirection = TeachingCalendarLogic.modeTransitionDirection(
                                selectedMode.ordinal,
                                mode.ordinal,
                            )
                            selectedMode = mode
                            requestCalendarDataForSelection()
                            dismissYearPopover()
                            onDateChanged()
                        }.apply {
                            setSelectedStyle(activity, false)
                        }, LinearLayout.LayoutParams(0, activity.dp(38), 1f).apply {
                            marginEnd = activity.dp(6)
                        })
                    }
                })
            })
            measure(
                View.MeasureSpec.makeMeasureSpec(panelWidth, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(maximumHeight, View.MeasureSpec.AT_MOST),
            )
        }
        val panelHeight = panel.measuredHeight.coerceIn(activity.dp(112), maximumHeight)
        val location = IntArray(2).also(anchor::getLocationOnScreen)
        val targetX = location[0] + tapX.toInt()
        val targetY = location[1] + tapY.toInt()
        val popupX = (targetX - panelWidth / 2).coerceIn(
            visibleFrame.left + activity.dp(16),
            (visibleFrame.right - panelWidth - activity.dp(16)).coerceAtLeast(visibleFrame.left),
        )
        val below = targetY + activity.dp(8)
        val popupY = if (below + panelHeight <= visibleFrame.bottom - activity.dp(16)) {
            below
        } else {
            (targetY - panelHeight - activity.dp(8)).coerceAtLeast(visibleFrame.top + activity.dp(16))
        }

        lateinit var popup: PopupWindow
        popup = PopupWindow(panel, panelWidth, panelHeight, true).apply {
            isOutsideTouchable = true
            elevation = activity.dp(10).toFloat()
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setOnDismissListener {
                anchor.selectDate(selectedDate)
                if (activePopup === popup) {
                    activePopup = null
                    activePopupAnchor = null
                    activePopupDetailsHost = null
                    activePopupDateMillis = null
                }
            }
        }
        activePopup = popup
        popup.showAtLocation(anchor, Gravity.TOP or Gravity.START, popupX, popupY)
    }

    private fun monthSelectedDetails(day: Calendar): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = shanghai }
            .format(day.time)
        addView(selectedDayDetails(day, asCard = true))
        addView(spacer(activity, 10))
        addView(assignmentDeadlineCard(date))
        if (preferences.almanacEnabled) {
            addView(spacer(activity, 10))
            addView(almanacCard(date))
        }
        if (preferences.hasCalendarDeadlinesToDisplay) {
            addView(spacer(activity, 10))
            addView(publicDeadlineCard(date))
        }
        setPadding(0, 0, 0, activity.dp(4))
    }

    private fun assignmentDeadlineCard(date: String): LinearLayout =
        dailyDetailCard("课程作业 DDL").apply {
            val items = dailyInfoRepository.assignments(date).orEmpty()
            when {
                items.isNotEmpty() -> items.forEach { item ->
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(0, activity.dp(7), 0, activity.dp(7))
                        addView(LinearLayout(activity).apply {
                            orientation = LinearLayout.VERTICAL
                            addView(TextView(activity).apply {
                                text = item.title
                                UiText.preserveRawText(this)
                                textSize = 14f
                                setTextColor(Palette.text)
                                setTypeface(typeface, Typeface.BOLD)
                            })
                            addView(TextView(activity).apply {
                                text = listOfNotNull(item.courseName, item.status).joinToString(" · ")
                                    .ifEmpty { "课程名称未标注" }
                                textSize = 12f
                                setTextColor(Palette.muted)
                                setPadding(0, activity.dp(2), 0, 0)
                            })
                        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                        addView(TextView(activity).apply {
                            text = item.deadline.substringAfter(' ').take(5)
                            textSize = 13f
                            setTextColor(Palette.primaryText)
                            setTypeface(typeface, Typeface.BOLD)
                        })
                    })
                }
                dailyInfoRepository.isLoadingAssignments(date) ->
                    addView(statusText("正在同步云课堂作业…"))
                dailyInfoRepository.assignmentError(date) != null -> addView(TextView(activity).apply {
                    text = "${dailyInfoRepository.assignmentError(date)}，点击重试"
                    textSize = 13f
                    setTextColor(Palette.danger)
                    setPadding(0, activity.dp(6), 0, activity.dp(6))
                    setOnClickListener {
                        activity.performControlHaptic(this)
                        dailyInfoRepository.loadAssignments(date, force = true) {}
                        refreshSelectedMonthDetailsInPlace(date)
                    }
                })
                else -> addView(statusText("当天暂无课程作业 DDL"))
            }
            addView(thirdPartyFooter(
                "第三方来源：北京邮电大学云课堂",
                listOf("打开作业列表" to CalendarDailyInfoSources.assignments),
            ))
        }

    private fun almanacCard(date: String): LinearLayout = dailyDetailCard("黄历信息").apply {
        val info = dailyInfoRepository.almanac(date)
        when {
            info != null -> {
                addView(TextView(activity).apply {
                    text = "农历 ${info.lunarDate} · ${info.weekday}"
                    textSize = 16f
                    setTextColor(Palette.text)
                    setTypeface(typeface, Typeface.BOLD)
                })
                addView(TextView(activity).apply {
                    text = "${info.ganzhiYear}年 · ${info.ganzhiMonth}月 · " +
                        "${info.ganzhiDay}日 · 肖${info.zodiac}"
                    textSize = 13f
                    setTextColor(Palette.muted)
                    setPadding(0, activity.dp(4), 0, 0)
                })
                listOfNotNull(info.solarTerm, info.lunarFestival, info.solarFestival)
                    .takeIf(List<String>::isNotEmpty)
                    ?.let { festivals ->
                        addView(TextView(activity).apply {
                            text = festivals.joinToString(" · ")
                            textSize = 12f
                            setTextColor(Palette.muted)
                            setPadding(0, activity.dp(4), 0, 0)
                        })
                    }
                info.yi?.let { addView(almanacAdviceRow("宜", it, Palette.primaryText)) }
                info.ji?.let { addView(almanacAdviceRow("忌", it, Palette.danger)) }
            }
            dailyInfoRepository.isLoadingAlmanac(date) -> addView(statusText("正在查询黄历…"))
            dailyInfoRepository.almanacError(date) != null -> addView(TextView(activity).apply {
                text = "${dailyInfoRepository.almanacError(date)}，点击重试"
                textSize = 13f
                setTextColor(Palette.danger)
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    dailyInfoRepository.loadAlmanac(date, force = true) {}
                    refreshSelectedMonthDetailsInPlace(date)
                }
            })
            else -> addView(statusText("正在查询黄历…"))
        }
        addView(thirdPartyFooter(
            "民俗信息仅供参考 · 第三方来源",
            listOf(
                "农历：UAPI" to "https://uapis.cn/docs/api-reference/get-misc-lunartime",
                "宜忌：Timeless" to "https://api.timelessq.com/docs/api-15277838",
            ),
        ))
    }

    private fun publicDeadlineCard(date: String): LinearLayout = dailyDetailCard("活动 DDL").apply {
        val snapshot = dailyInfoRepository.deadlines(date)
        val items = snapshot?.items.orEmpty().filter(::deadlineIsEnabled)
        when {
            items.isNotEmpty() -> items.forEach { addView(publicDeadlineRow(it)) }
            dailyInfoRepository.isLoadingDeadlines(date) ->
                addView(statusText("正在同步竞赛、夏令营与黑客松…"))
            dailyInfoRepository.deadlineError(date) != null -> addView(TextView(activity).apply {
                text = "${dailyInfoRepository.deadlineError(date)}，点击重试"
                textSize = 13f
                setTextColor(Palette.danger)
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    dailyInfoRepository.loadDeadlines(date, force = true) {}
                    refreshSelectedMonthDetailsInPlace(date)
                }
            })
            else -> addView(statusText("当天没有已收录的活动截止事项"))
        }
        addView(thirdPartyFooter(
            "第三方来源 · 校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考",
            buildList {
                addAll(listOf(
                "主数据：Contest DDL" to CalendarDailyInfoSources.deadlinePrimaryPage,
                "备用 API" to CalendarDailyInfoSources.deadlineBackup,
                "校内竞赛通知" to CalendarDailyInfoSources.schoolContestNotices,
                ))
                items.firstOrNull { it.source == PublicDeadlineSource.CUSTOM }
                    ?.sourceHomepage
                    ?.let { homepage ->
                        add(
                            "自定义来源：${items.first { it.source == PublicDeadlineSource.CUSTOM }
                                .sourceName ?: PublicDeadlineSource.CUSTOM.title}" to homepage,
                        )
                    }
            },
        ))
    }

    private fun dailyDetailCard(title: String): LinearLayout =
        surface(activity, showsBorder = false).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedBackground(activity, Palette.surface, radius = 10)
            setPadding(activity.dp(14), activity.dp(12), activity.dp(14), activity.dp(12))
            addView(TextView(activity).apply {
                text = title
                textSize = 14f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
                includeFontPadding = false
                setPadding(0, 0, 0, activity.dp(8))
            })
        }

    private fun statusText(value: String): TextView = TextView(activity).apply {
        text = value
        textSize = 13f
        setTextColor(Palette.muted)
    }

    private fun almanacAdviceRow(label: String, value: String, color: Int): LinearLayout =
        buildAlmanacAdviceRow(activity, label, value, color)

    private fun publicDeadlineRow(item: PublicDeadlineItem): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = roundedBackground(activity, Palette.background, Palette.border, radius = 7)
            setPadding(activity.dp(10), activity.dp(7), activity.dp(5), activity.dp(7))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = activity.dp(7) }
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(TextView(activity).apply {
                        text = item.name
                        UiText.preserveRawText(this)
                        textSize = 13f
                        setTextColor(Palette.text)
                        setTypeface(typeface, Typeface.BOLD)
                        maxLines = 2
                        ellipsize = TextUtils.TruncateAt.END
                    })
                    addView(TextView(activity).apply {
                        text = listOfNotNull(deadlineCategoryTitle(item), item.organizer)
                            .joinToString(" · ")
                        textSize = 11f
                        setTextColor(Palette.muted)
                        setPadding(0, activity.dp(2), 0, 0)
                    })
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                addView(TextView(activity).apply {
                    text = deadlineTime(item.deadline)
                    textSize = 11f
                    setTextColor(Palette.muted)
                    setPadding(activity.dp(8), 0, 0, 0)
                })
                item.officialURL?.let { url ->
                    isClickable = true
                    isFocusable = true
                    contentDescription = "${item.name}，${activity.uiText("打开原文")}"
                    setOnClickListener { openExternalURL(url) }
                }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(favoriteDeadlineButton(item), LinearLayout.LayoutParams(
                activity.dp(38),
                activity.dp(38),
            ).apply { marginStart = activity.dp(5) })
        }

    private fun favoriteDeadlineButton(item: PublicDeadlineItem): ImageView =
        ImageView(activity).apply {
            id = R.id.calendar_deadline_favorite
            scaleType = ImageView.ScaleType.CENTER
            isClickable = true
            isFocusable = true
            background = roundedBackground(activity, Color.TRANSPARENT, radius = 8)
            tag = item.favoriteID
            setTag(R.id.favorite_deadline_item_key, item.favoriteID)
            fun bind() {
                val favorite = preferences.isFavorite(item)
                setImageResource(
                    if (favorite) R.drawable.ic_star_filled else R.drawable.ic_star_outline,
                )
                imageTintList = ColorStateList.valueOf(
                    if (favorite) Palette.accent else Palette.muted,
                )
                contentDescription = activity.uiText(if (favorite) "取消收藏" else "收藏日程")
            }
            bind()
            setOnClickListener {
                activity.performControlHaptic(it)
                preferences.setFavorite(item, favorite = !preferences.isFavorite(item))
                bind()
            }
        }

    private fun thirdPartyFooter(
        label: String,
        links: List<Pair<String, String>>,
    ): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, activity.dp(9), 0, 0)
        addView(TextView(activity).apply {
            text = label
            textSize = 10.5f
            setTextColor(Palette.muted)
        })
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            links.forEachIndexed { index, (title, url) ->
                addView(TextView(activity).apply {
                    text = title
                    textSize = 10.5f
                    setTextColor(Palette.primaryText)
                    isClickable = true
                    isFocusable = true
                    setPadding(0, activity.dp(3), activity.dp(if (index == links.lastIndex) 0 else 12), 0)
                    setOnClickListener { openExternalURL(url) }
                })
            }
        })
    }

    private fun deadlineIsEnabled(item: PublicDeadlineItem): Boolean {
        if (preferences.isFavorite(item)) return true
        if (item.source == PublicDeadlineSource.SCHOOL_NOTICE) {
            return preferences.schoolContestNoticesEnabled
        }
        return when (item.kind) {
            PublicDeadlineKind.COMPETITION -> preferences.competitionDeadlinesEnabled
            PublicDeadlineKind.SUMMER_CAMP -> preferences.summerCampDeadlinesEnabled
            PublicDeadlineKind.HACKATHON -> preferences.hackathonDeadlinesEnabled
            PublicDeadlineKind.CUSTOM -> preferences.customDeadlinesEnabled
        }
    }

    private fun deadlineCategoryTitle(item: PublicDeadlineItem): String = when {
        item.source == PublicDeadlineSource.CUSTOM && item.sourceName != null ->
            "${activity.uiText(item.kind.title)} · ${item.sourceName}"
        item.source == PublicDeadlineSource.SCHOOL_NOTICE -> item.source.title
        else -> item.kind.title
    }

    private fun deadlineTime(value: String): String =
        if (value.length >= 16) value.substring(11, 16) else value

    private fun openExternalURL(url: String) {
        runCatching {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }.onFailure {
            Toast.makeText(
                activity,
                activity.uiText("无法打开链接"),
                Toast.LENGTH_SHORT,
            ).show()
        }
    }

    private fun selectedDayDetails(
        day: Calendar,
        asCard: Boolean = false,
        includeSupplementary: Boolean = false,
    ): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        if (asCard) {
            background = roundedBackground(
                activity,
                Palette.surface,
                radius = 10,
                borderWidthDp = TeachingCalendarLogic.monthDetailsBorderWidthDp(),
            )
            setPadding(activity.dp(14), activity.dp(14), activity.dp(14), activity.dp(14))
            addView(TextView(activity).apply {
                text = "当日日程"
                textSize = 11f
                setTextColor(Palette.muted)
                setTypeface(typeface, Typeface.BOLD)
                includeFontPadding = false
                setPadding(0, 0, 0, activity.dp(4))
            })
        }
        val formatter = SimpleDateFormat("yyyy年M月d日 EEEE", displayLocale()).apply { timeZone = shanghai }
        addView(TextView(activity).apply {
            text = formatter.format(day.time)
            textSize = 16f
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 0, 0, activity.dp(8))
        })
        holidaysOn(day).forEach { item ->
            addView(TextView(activity).apply {
                text = activity.getString(
                    R.string.holiday_item_format,
                    activity.getString(
                        if (item.type == "holiday") R.string.holiday_marker else R.string.workday_marker,
                    ),
                    item.name,
                )
                textSize = 13f
                setTextColor(if (item.type == "holiday") Palette.holiday else Palette.primaryText)
                setPadding(0, 0, 0, activity.dp(5))
                isClickable = true
                isFocusable = true
                setOnClickListener { showHolidayDetails(item) }
            })
        }
        if (includeSupplementary) {
            assignmentsOn(day).forEach { assignment ->
                addView(supplementaryDetailRow(
                    label = "作",
                    title = assignment.title,
                    subtitle = listOfNotNull(
                        assignment.courseName,
                        assignment.deadline,
                        assignment.status,
                    ).joinToString(" · "),
                    accent = Palette.assignment,
                ))
            }
            schoolNoticesOn(day).forEach { notice ->
                addView(supplementaryDetailRow(
                    label = "校",
                    title = notice.name,
                    subtitle = listOfNotNull(notice.deadline, notice.organizer)
                        .joinToString(" · "),
                    accent = Palette.schoolNotice,
                    deadlineItem = notice,
                ))
            }
            publicDeadlinesOn(day).forEach { deadline ->
                addView(supplementaryDetailRow(
                    label = publicDeadlineLabel(deadline.kind),
                    title = deadline.name,
                    subtitle = listOfNotNull(deadline.deadline, deadline.organizer)
                        .joinToString(" · "),
                    accent = Palette.publicDeadline,
                    deadlineItem = deadline,
                ))
            }
            val dateKey = contractDate().format(day.time)
            if (dailyInfoRepository.isLoadingAssignments(dateKey) ||
                dailyInfoRepository.isLoadingDeadlines(dateKey)
            ) {
                addView(TextView(activity).apply {
                    text = "正在同步作业与活动 DDL…"
                    textSize = 12f
                    setTextColor(Palette.muted)
                    setPadding(0, activity.dp(3), 0, activity.dp(3))
                })
            }
        }
        val courses = coursesOn(day)
        if (courses.isEmpty()) {
            addView(TextView(activity).apply {
                text = "暂无课程"
                textSize = 13f
                setTextColor(Palette.muted)
            })
        } else {
            courses.forEach { course ->
                addView(selectedDayCourseRow(day, course))
            }
        }
    }

    private fun supplementaryDetailRow(
        label: String,
        title: String,
        subtitle: String,
        accent: Int,
        deadlineItem: PublicDeadlineItem? = null,
    ): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.TOP
        setPadding(0, activity.dp(4), 0, activity.dp(4))
        addView(TextView(activity).apply {
            text = label
            textSize = 11f
            gravity = Gravity.CENTER
            setTextColor(accent)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(
                activity,
                blend(accent, Palette.surface, 0.14f),
                radius = 5,
            )
        }, LinearLayout.LayoutParams(activity.dp(30), activity.dp(30)).apply {
            marginEnd = activity.dp(9)
        })
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(activity).apply {
                text = title
                UiText.preserveRawText(this)
                textSize = 13f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(activity).apply {
                text = subtitle
                UiText.preserveRawText(this)
                textSize = 11f
                setTextColor(Palette.muted)
                setPadding(0, activity.dp(2), 0, 0)
            })
            deadlineItem?.officialURL?.let { url ->
                isClickable = true
                isFocusable = true
                contentDescription = "$title，${activity.uiText("打开原文")}"
                setOnClickListener { openExternalURL(url) }
            }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        deadlineItem?.let { item ->
            addView(favoriteDeadlineButton(item), LinearLayout.LayoutParams(
                activity.dp(38),
                activity.dp(38),
            ).apply { marginStart = activity.dp(5) })
        }
    }

    private fun selectedDayCourseRow(day: Calendar, course: Course): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            isClickable = true
            isFocusable = true
            background = roundedBackground(activity, Color.TRANSPARENT, radius = 6)
            contentDescription = listOf(
                course.name,
                course.timeRange,
                course.room,
                course.teacher,
            ).filter(String::isNotEmpty).joinToString("，")
            setPadding(0, activity.dp(4), 0, activity.dp(4))
            addView(View(activity).apply {
                background = roundedBackground(activity, Palette.primary, radius = 2)
            }, LinearLayout.LayoutParams(activity.dp(4), activity.dp(38)).apply {
                marginEnd = activity.dp(10)
            })
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(activity).apply {
                    text = course.name
                    UiText.preserveRawText(this)
                    textSize = 13f
                    setTextColor(Palette.text)
                    setTypeface(typeface, Typeface.BOLD)
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                })
                addView(TextView(activity).apply {
                    text = listOf(
                        course.timeRange,
                        course.room,
                        course.teacher.takeIf(String::isNotEmpty)?.let { "教师：$it" }.orEmpty(),
                    ).filter(String::isNotEmpty).joinToString(" · ")
                    textSize = 11f
                    setTextColor(Palette.muted)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    setPadding(0, activity.dp(2), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            setOnClickListener { showCourseDetails(day, course) }
        }

    private fun showCourseDetails(day: Calendar, course: Course) {
        performCalendarHaptic()
        val dialog = Dialog(activity).apply {
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            setCanceledOnTouchOutside(true)
        }
        val card = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 10)
            setPadding(activity.dp(18), activity.dp(18), activity.dp(18), activity.dp(14))
        }
        card.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            addView(View(activity).apply {
                background = roundedBackground(activity, Palette.accent, radius = 2)
            }, LinearLayout.LayoutParams(activity.dp(4), activity.dp(44)).apply {
                marginEnd = activity.dp(12)
            })
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(activity).apply {
                    text = if (course.examWeekNumbers.isEmpty()) {
                        course.name
                    } else {
                        "${activity.uiText("试")}  ${course.name}"
                    }
                    UiText.preserveRawText(this)
                    textSize = 18f
                    setTextColor(Palette.text)
                    setTypeface(typeface, Typeface.BOLD)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                })
                addView(TextView(activity).apply {
                    text = "课程详情"
                    textSize = 11f
                    setTextColor(Palette.muted)
                    includeFontPadding = false
                    setPadding(0, activity.dp(3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(TextView(activity).apply {
                text = "×"
                textSize = 24f
                gravity = Gravity.CENTER
                setTextColor(Palette.muted)
                includeFontPadding = false
                isClickable = true
                isFocusable = true
                contentDescription = "关闭"
                background = roundedBackground(activity, Palette.surfaceVariant, radius = 8)
                setOnClickListener { dialog.dismiss() }
            }, LinearLayout.LayoutParams(activity.dp(36), activity.dp(36)).apply {
                marginStart = activity.dp(8)
            })
        })
        card.addView(spacer(activity, 16))
        val date = SimpleDateFormat("yyyy年M月d日 EEEE", displayLocale()).apply {
            timeZone = shanghai
        }.format(day.time)
        buildList {
            add("日期" to date)
            add("时间" to course.timeRange.ifEmpty { "未标注" })
            add("节次" to course.sectionText.ifEmpty { "未标注" })
            add("地点" to course.room.ifEmpty { "未标注" })
            add("教师" to course.teacher.ifEmpty { "未标注" })
            add("教学周" to course.weekText.ifEmpty { course.weekNumbers.joinToString("、") })
            if (course.examWeekNumbers.isNotEmpty()) {
                add("考试周" to course.examWeekNumbers.joinToString("、") { "$it 周" })
            }
        }.forEachIndexed { index, (label, value) ->
            card.addView(courseDetailRow(label, value), LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                if (index > 0) topMargin = activity.dp(10)
            })
        }
        card.addView(TextView(activity).apply {
            text = "完成"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Palette.onPrimary)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
            isClickable = true
            isFocusable = true
            background = roundedBackground(activity, Palette.primaryFill, radius = 8)
            setOnClickListener { dialog.dismiss() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, activity.dp(42)).apply {
            topMargin = activity.dp(18)
        })
        dialog.setContentView(ScrollView(activity).apply {
            clipToPadding = false
            setPadding(activity.dp(1), activity.dp(1), activity.dp(1), activity.dp(1))
            addView(card, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        })
        dialog.show()
        UiText.localizeDialog(dialog)
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            attributes = attributes.apply { dimAmount = 0.34f }
            val availableWidth = (
                activity.resources.displayMetrics.widthPixels - activity.dp(32)
            ).coerceAtLeast(activity.dp(240))
            setLayout(minOf(activity.dp(420), availableWidth), ViewGroup.LayoutParams.WRAP_CONTENT)
            setGravity(Gravity.CENTER)
        }
    }

    private fun courseDetailRow(label: String, value: String): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            addView(TextView(activity).apply {
                text = label
                textSize = 11f
                setTextColor(Palette.muted)
                includeFontPadding = false
            }, LinearLayout.LayoutParams(activity.dp(54), ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(TextView(activity).apply {
                text = value
                textSize = 14f
                setTextColor(Palette.text)
                includeFontPadding = false
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }

    private fun showHolidayDetails(item: HolidayItem) {
        performCalendarHaptic()
        AlertDialog.Builder(activity)
            .setTitle(item.name)
            .setMessage(
                "${activity.uiText("日期")}: ${item.date}\n" +
                    "${activity.uiText("类型")}: ${activity.uiText(
                        if (item.type == "holiday") "法定节假日" else "调休工作日",
                    )}",
            )
            .setPositiveButton(activity.uiText("完成"), null)
            .show()
    }

    private fun yearCalendarDays(year: Int): List<YearCalendarDay> {
        return buildList {
            for (month in 1..12) {
                val date = Calendar.getInstance(shanghai).apply {
                    set(year, month - 1, 1, 12, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                repeat(date.getActualMaximum(Calendar.DAY_OF_MONTH)) { dayOffset ->
                    date.set(Calendar.DAY_OF_MONTH, dayOffset + 1)
                    val snapshot = date.clone() as Calendar
                    add(yearCalendarDay(snapshot))
                }
            }
        }
    }

    private fun yearCalendarDay(day: Calendar): YearCalendarDay = YearCalendarDay(
        date = day.clone() as Calendar,
        courseCount = coursesOn(day).size,
        holidays = holidaysOn(day),
        supplementaryKinds = YearCalendarLogic.supplementaryKinds(
            assignmentCount = assignmentsOn(day).size,
            schoolNoticeCount = schoolNoticesOn(day).size,
            publicDeadlineCount = publicDeadlinesOn(day).size,
        ),
    )

    private fun dismissYearPopover() {
        val popup = activePopup
        activePopup = null
        activePopupDetailsHost = null
        activePopupDateMillis = null
        if (popup?.isShowing == true) popup.dismiss()
        activePopupAnchor?.selectDate(selectedDate)
        activePopupAnchor = null
    }

    private fun calendarCellBackground(
        selected: Boolean,
        today: Boolean,
        courseCount: Int,
        muted: Boolean,
        supplementaryKinds: List<YearCalendarSupplementaryKind> = emptyList(),
    ): Drawable {
        val fill = when {
            selected -> Palette.selectedDate
            muted -> Color.TRANSPARENT
            courseCount <= 0 -> Color.TRANSPARENT
            else -> blend(
                Palette.primary,
                Palette.background,
                TeachingCalendarLogic.yearCourseOpacity(courseCount),
            )
        }
        val borderKinds = YearCalendarLogic.borderKinds(supplementaryKinds)
        val outerKind = borderKinds.firstOrNull()
        val borderColor = TeachingCalendarLogic.monthCellBorderColor(
            supplementaryKind = outerKind,
            today = today,
            assignmentColor = Palette.assignment,
            schoolNoticeColor = Palette.schoolNotice,
            publicDeadlineColor = Palette.publicDeadline,
            todayColor = Palette.nowIndicator,
        )
        val borderWidthDp = TeachingCalendarLogic.monthCellBorderWidthDp(
            outerKind,
            today,
        )
        val outer = roundedBackground(
            activity,
            fill,
            borderColor,
            radius = 9,
            borderWidthDp = borderWidthDp,
        )
        val innerKind = borderKinds.getOrNull(1) ?: return outer
        val inner = roundedBackground(
            activity,
            Color.TRANSPARENT,
            TeachingCalendarLogic.monthCellBorderColor(
                supplementaryKind = innerKind,
                today = false,
                assignmentColor = Palette.assignment,
                schoolNoticeColor = Palette.schoolNotice,
                publicDeadlineColor = Palette.publicDeadline,
                todayColor = Palette.nowIndicator,
            ),
            radius = 7,
            borderWidthDp = TeachingCalendarLogic.monthCellInnerBorderWidthDp(),
        )
        val inset = (
            TeachingCalendarLogic.monthCellInnerBorderInsetDp() *
                activity.resources.displayMetrics.density
            ).roundToInt()
        return LayerDrawable(arrayOf(outer, inner)).apply {
            setLayerInset(1, inset, inset, inset, inset)
        }
    }

    private fun timelineDay(date: Calendar): TimelineDay = TimelineDay(
        date = date.clone() as Calendar,
        courses = coursesOn(date),
        holidays = holidaysOn(date),
    )

    private fun visibleYears(): Set<Int> = when (selectedMode) {
        Mode.DAY -> setOf(selectedDate.get(Calendar.YEAR))
        Mode.WEEK -> weekDates().mapTo(mutableSetOf()) { it.get(Calendar.YEAR) }
        Mode.MONTH -> monthGridDates().mapTo(mutableSetOf()) { it.get(Calendar.YEAR) }
        Mode.YEAR -> setOf(selectedDate.get(Calendar.YEAR))
    }

    private fun holidayStatus(): String? = visibleYears()
        .map(holidayRepository::status)
        .firstOrNull(String::isNotEmpty)

    private fun holidaysOn(date: Calendar): List<HolidayItem> {
        val target = contractDate().format(date.time)
        return holidayRepository.items(date.get(Calendar.YEAR)).filter { it.date == target }
    }

    private fun assignmentsOn(date: Calendar): List<AssignmentDeadlineItem> =
        dailyInfoRepository.assignments(contractDate().format(date.time)).orEmpty()

    private fun schoolNoticesOn(date: Calendar): List<PublicDeadlineItem> {
        return dailyInfoRepository.deadlines(contractDate().format(date.time))
            ?.items
            .orEmpty()
            .filter { it.source == PublicDeadlineSource.SCHOOL_NOTICE && deadlineIsEnabled(it) }
    }

    private fun publicDeadlinesOn(date: Calendar): List<PublicDeadlineItem> =
        dailyInfoRepository.deadlines(contractDate().format(date.time))
            ?.items
            .orEmpty()
            .filter { it.source != PublicDeadlineSource.SCHOOL_NOTICE && deadlineIsEnabled(it) }

    private fun supplementaryItemsOn(date: Calendar): List<CalendarSupplementaryItem> = buildList {
        holidaysOn(date).forEach { holiday ->
            add(CalendarSupplementaryItem(
                kind = CalendarSupplementaryKind.HOLIDAY,
                title = activity.uiText(if (holiday.type == "holiday") "休" else "班") +
                    " ${holiday.name}",
                subtitle = null,
            ))
        }
        assignmentsOn(date).forEach { assignment ->
            add(CalendarSupplementaryItem(
                kind = CalendarSupplementaryKind.ASSIGNMENT,
                title = "${activity.uiText("作业 DDL")} · ${assignment.title}",
                subtitle = listOfNotNull(
                    assignment.courseName,
                    assignment.deadline.substringAfter(' ').take(5),
                ).joinToString(" · ").takeIf(String::isNotEmpty),
            ))
        }
        schoolNoticesOn(date).forEach { notice ->
            add(CalendarSupplementaryItem(
                kind = CalendarSupplementaryKind.SCHOOL_NOTICE,
                title = "${activity.uiText("校内竞赛通知")} · ${notice.name}",
                subtitle = listOfNotNull(
                    deadlineTime(notice.deadline),
                    notice.organizer,
                ).joinToString(" · ").takeIf(String::isNotEmpty),
                deadlineItem = notice,
            ))
        }
        publicDeadlinesOn(date).forEach { deadline ->
            add(CalendarSupplementaryItem(
                kind = CalendarSupplementaryKind.PUBLIC_DEADLINE,
                title = "${activity.uiText(deadlineKindTitle(deadline.kind))} · ${deadline.name}",
                subtitle = listOfNotNull(
                    deadlineTime(deadline.deadline),
                    deadline.organizer,
                ).joinToString(" · ").takeIf(String::isNotEmpty),
                deadlineItem = deadline,
            ))
        }
    }

    private fun deadlineKindTitle(kind: PublicDeadlineKind): String = when (kind) {
        PublicDeadlineKind.COMPETITION -> "学科竞赛 DDL"
        PublicDeadlineKind.SUMMER_CAMP -> "夏令营 DDL"
        PublicDeadlineKind.HACKATHON -> "黑客松 DDL"
        PublicDeadlineKind.CUSTOM -> "自定义日程"
    }

    private fun publicDeadlineLabel(kind: PublicDeadlineKind): String = activity.uiText(when (kind) {
        PublicDeadlineKind.COMPETITION -> "赛"
        PublicDeadlineKind.SUMMER_CAMP -> "营"
        PublicDeadlineKind.HACKATHON -> "黑"
        PublicDeadlineKind.CUSTOM -> "自"
    })

    private fun coursesOn(date: Calendar): List<Course> =
        ScheduleLogic.courses(scheduleRepository.schedule, date)

    private fun weekDates(): List<Calendar> {
        val first = selectedDate.clone() as Calendar
        first.add(Calendar.DAY_OF_MONTH, -((first.get(Calendar.DAY_OF_WEEK) + 5) % 7))
        return (0 until 7).map { offset ->
            (first.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, offset) }
        }
    }

    private fun monthGridDates(): List<Calendar> = monthGridDates(
        selectedDate.get(Calendar.YEAR),
        selectedDate.get(Calendar.MONTH) + 1,
    )

    private fun monthGridDates(year: Int, month: Int): List<Calendar> {
        val first = Calendar.getInstance(shanghai).apply {
            set(year, month - 1, 1, 12, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        first.add(Calendar.DAY_OF_MONTH, -((first.get(Calendar.DAY_OF_WEEK) + 5) % 7))
        return (0 until 42).map { offset ->
            (first.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, offset) }
        }
    }

    private fun yearDates(year: Int): List<Calendar> = buildList {
        val date = Calendar.getInstance(shanghai).apply {
            set(year, Calendar.JANUARY, 1, 12, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        repeat(date.getActualMaximum(Calendar.DAY_OF_YEAR)) {
            add(date.clone() as Calendar)
            date.add(Calendar.DAY_OF_MONTH, 1)
        }
    }

    private fun stepDate(direction: Int) {
        when (selectedMode) {
            Mode.DAY -> selectedDate.add(Calendar.DAY_OF_MONTH, direction)
            Mode.WEEK -> selectedDate.add(Calendar.DAY_OF_MONTH, direction * 7)
            Mode.MONTH -> selectedDate.add(Calendar.MONTH, direction)
            Mode.YEAR -> selectedDate.add(Calendar.YEAR, direction)
        }
        requestCalendarDataForSelection()
    }

    private fun performCalendarHaptic() {
        if (availableWidthDp >= TeachingCalendarLogic.compactCalendarBreakpointDp) return
        activity.window.decorView.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    private fun swipeContainer(
        view: View,
        onChanged: () -> Unit,
        monthSheetPosition: Float = TeachingCalendarLogic.monthSheetExpandedPosition,
        onMonthSheetSettled: ((Float) -> Unit)? = null,
        onMonthSheetProgress: ((Float) -> Unit)? = null,
    ): CalendarSwipeContainer =
        CalendarSwipeContainer(activity).apply {
            id = R.id.calendar_swipe_surface
            this.monthSheetPosition = monthSheetPosition
            this.onMonthSheetSettled = onMonthSheetSettled
            this.onMonthSheetProgress = onMonthSheetProgress
            addView(view, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
            onPageSwipe = { direction ->
                stepDate(direction)
                pendingPageDirection = direction
                onChanged()
            }
        }

    private fun sameDay(left: Calendar, right: Calendar): Boolean =
        left.get(Calendar.ERA) == right.get(Calendar.ERA) &&
            left.get(Calendar.YEAR) == right.get(Calendar.YEAR) &&
            left.get(Calendar.DAY_OF_YEAR) == right.get(Calendar.DAY_OF_YEAR)

    private fun contractDate(): SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = shanghai
        isLenient = false
    }

    private fun displayLocale(): Locale =
        if (AppLocale.isEnglish(activity)) Locale.US else Locale.SIMPLIFIED_CHINESE

    private fun displayMonthDay(day: Calendar): String = SimpleDateFormat(
        if (AppLocale.isEnglish(activity)) "MMM d" else "M月d日",
        displayLocale(),
    ).apply { timeZone = shanghai }.format(day.time)

    private fun displayMonthDayWithWeekday(day: Calendar): String = SimpleDateFormat(
        if (AppLocale.isEnglish(activity)) "MMM d, EEEE" else "M月d日 EEEE",
        displayLocale(),
    ).apply { timeZone = shanghai }.format(day.time)

    private fun blend(foreground: Int, background: Int, amount: Float): Int = Color.rgb(
        (Color.red(background) + (Color.red(foreground) - Color.red(background)) * amount).toInt(),
        (Color.green(background) + (Color.green(foreground) - Color.green(background)) * amount).toInt(),
        (Color.blue(background) + (Color.blue(foreground) - Color.blue(background)) * amount).toInt(),
    )

}
