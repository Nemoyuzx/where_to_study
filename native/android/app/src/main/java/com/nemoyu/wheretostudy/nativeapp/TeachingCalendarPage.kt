package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.Dialog
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewConfiguration
import android.view.Window
import android.view.WindowManager
import android.view.VelocityTracker
import android.view.accessibility.AccessibilityEvent
import android.view.animation.DecelerateInterpolator
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.LinearLayout
import android.widget.FrameLayout
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

    private companion object {
        val SHANGHAI: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")
    }
}

private typealias Mode = TeachingCalendarMode

private data class MonthCalendarEntry(
    val title: String,
)

private data class MonthEntriesRenderState(
    val entries: List<MonthCalendarEntry>,
    val selected: Boolean,
    var slotCapacity: Int = -1,
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
    const val bottomNavigationContentInsetDp = 84

    fun modeTransitionDirection(fromIndex: Int, toIndex: Int): Int = when {
        toIndex > fromIndex -> 1
        toIndex < fromIndex -> -1
        else -> 0
    }

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
    ): Boolean {
        val horizontalDistance = abs(deltaXDp)
        val verticalDistance = abs(deltaYDp)
        if (verticalDistance < thresholdDp || verticalDistance <= horizontalDistance * 1.2f) {
            return false
        }
        return when {
            deltaYDp < 0f -> currentPosition < monthSheetWeekPosition
            deltaYDp > 0f -> currentPosition > monthSheetExpandedPosition
            else -> false
        }
    }

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

    fun monthHorizontalPaddingDp(usesBottomNavigation: Boolean): Int =
        if (usesBottomNavigation) 0 else 16

    fun calendarContentBottomInsetDp(usesBottomNavigation: Boolean): Int =
        if (usesBottomNavigation) bottomNavigationContentInsetDp else 0

    fun monthDaySelectionTargetPosition(): Float = monthSheetDetailsPosition

    fun monthDetailsBorderWidthDp(): Float = 0f

    fun monthEntryTextColor(selected: Boolean, textColor: Int, onPrimaryColor: Int): Int =
        if (selected) onPrimaryColor else textColor

    fun monthEntryBackgroundColor(
        selected: Boolean,
        surfaceVariantColor: Int,
        primaryDarkColor: Int,
    ): Int = if (selected) primaryDarkColor else surfaceVariantColor

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
    private var monthDragStartPosition = TeachingCalendarLogic.monthSheetExpandedPosition
    private var monthDragPosition = TeachingCalendarLogic.monthSheetExpandedPosition
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

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                gestureEligible = swipeEnabled
                claimedGesture = 0
                childCancelled = false
                monthDragStartPosition = monthSheetPosition
                monthDragPosition = monthSheetPosition
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
                            ) -> 2
                            else -> -1
                        }
                        if (claimedGesture > 0) {
                            parent?.requestDisallowInterceptTouchEvent(true)
                            cancelChild(event)
                        } else if (claimedGesture < 0) {
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
                    post { onMonthSheetSettled?.invoke(monthDragStartPosition.roundToInt().toFloat()) }
                }
                gestureEligible = false
                claimedGesture = 0
                restoreParentInterception()
                velocityTracker?.recycle()
                velocityTracker = null
            }
        }
        return super.dispatchTouchEvent(event)
    }
}

internal class TeachingCalendarPage(
    private val activity: MainActivity,
    private val scheduleRepository: ScheduleRepository,
    private val holidayRepository: HolidayRepository,
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
    private var pendingMonthExpansionDirection = 0
    private var activePopupAnchor: YearCalendarView? = null
    private var activePopup: PopupWindow? = null

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
            animateMonthSheetPosition(monthView, target) {
                monthSheetPosition = target
                content.findViewById<CalendarSwipeContainer?>(R.id.calendar_swipe_surface)
                    ?.monthSheetPosition = target
            }
        }

        fun render() {
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
            visibleYears().forEach { year ->
                holidayRepository.ensure(year)
            }
        }

        scrollView.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                holidayRepository.addObserver(scrollView) {
                    if (scrollView.isAttachedToWindow) render()
                }
                render()
            }

            override fun onViewDetachedFromWindow(view: View) {
                scrollView.requestDisallowInterceptTouchEvent(false)
                holidayRepository.removeObserver(scrollView)
                dismissYearPopover()
            }
        })

        root.addView(pageTitle(activity, "教学日历", "课程、节次与法定节假日"))
        root.addView(calendarImportButton())
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
            animateMonthSheetPosition(monthView, target) {
                monthSheetPosition = target
                pageSurface.monthSheetPosition = target
            }
        }

        fun render() {
            dismissYearPopover()
            tabs.forEach { (mode, view) ->
                view.setCompactSelectedStyle(activity, mode == selectedMode)
            }
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
                visibleYears().forEach(holidayRepository::ensure)
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
            replacePhonePage(
                pageSurface,
                pageView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            visibleYears().forEach(holidayRepository::ensure)
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
                    pendingPageDirection = TeachingCalendarLogic.modeTransitionDirection(
                        selectedMode.ordinal,
                        mode.ordinal,
                    )
                    selectedMode = mode
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
                holidayRepository.addObserver(root) {
                    if (root.isAttachedToWindow) render()
                }
                render()
            }

            override fun onViewDetachedFromWindow(view: View) {
                monthExpansionAnimator?.cancel()
                holidayRepository.removeObserver(root)
                dismissYearPopover()
            }
        })
        render()
        return root
    }

    private fun replacePhonePage(
        container: FrameLayout,
        page: View,
        layoutParams: FrameLayout.LayoutParams,
    ) {
        val oldPage = container.getChildAt(0)
        val pageDirection = pendingPageDirection
        val expansionDirection = pendingMonthExpansionDirection
        pendingPageDirection = 0
        pendingMonthExpansionDirection = 0

        if (oldPage == null || (pageDirection == 0 && expansionDirection == 0)) {
            container.removeAllViews()
            container.addView(page, layoutParams)
            return
        }

        if (pageDirection != 0) {
            val distance = container.width.takeIf { it > 0 } ?: activity.dp(availableWidthDp)
            page.translationX = pageDirection * distance.toFloat()
            container.addView(page, layoutParams)
            val interpolator = AccelerateDecelerateInterpolator()
            oldPage.animate()
                .translationX(-pageDirection * distance.toFloat())
                .setDuration(300L)
                .setInterpolator(interpolator)
                .withEndAction {
                    if (oldPage.parent === container) container.removeView(oldPage)
                }
                .start()
            page.animate()
                .translationX(0f)
                .setDuration(300L)
                .setInterpolator(interpolator)
                .start()
            return
        }

        container.removeAllViews()
        page.translationY = activity.dp(if (expansionDirection > 0) -18 else 18).toFloat()
        container.addView(page, layoutParams)
        page.animate()
            .translationY(0f)
            .setDuration(220L)
            .setInterpolator(DecelerateInterpolator())
            .start()
    }

    private fun animateExpandedPageIn(content: View) {
        val direction = pendingPageDirection
        val expansionDirection = pendingMonthExpansionDirection
        pendingPageDirection = 0
        pendingMonthExpansionDirection = 0
        if (direction == 0 && expansionDirection == 0) return
        if (direction == 0) {
            content.translationY = activity.dp(if (expansionDirection > 0) -18 else 18).toFloat()
            content.animate()
                .translationY(0f)
                .setDuration(220L)
                .setInterpolator(DecelerateInterpolator())
                .start()
            return
        }
        val distance = content.width.takeIf { it > 0 } ?: activity.dp(availableWidthDp)
        content.translationX = direction * distance.toFloat()
        content.animate()
            .translationX(0f)
            .setDuration(300L)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .start()
    }

    private fun phoneDayWeekContent(onDateChanged: () -> Unit): LinearLayout =
        LinearLayout(activity).apply {
            id = R.id.calendar_page_body
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.surface)
            setPadding(0, activity.dp(6), 0, 0)
            addView(phoneDateSummary())
            holidayStatus()?.let { message ->
                addView(TextView(activity).apply {
                    text = message
                    textSize = 12f
                    setTextColor(Palette.muted)
                    setPadding(activity.dp(16), activity.dp(4), activity.dp(16), activity.dp(4))
                })
            }
            addView(spacer(activity, 6))
            val timelineDays = if (selectedMode == Mode.DAY) {
                listOf(timelineDay(selectedDate))
            } else {
                weekDates().map(::timelineDay)
            }
            val callback: ((Calendar) -> Unit)? = if (selectedMode == Mode.WEEK) {
                { day ->
                    if (!sameDay(selectedDate, day)) performCalendarHaptic()
                    selectedDate.timeInMillis = day.timeInMillis
                    onDateChanged()
                }
            } else {
                null
            }
            if (timelineDays.any { it.holidays.isNotEmpty() }) {
                addView(allDayStrip(timelineDays, compact = true, onDaySelected = callback))
            }
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

    private fun calendarImportButton(compact: Boolean = false): TextView = TextView(activity).apply {
        id = R.id.calendar_overflow_button
        val defaultLabel = if (compact) "•••" else "导入手机日历"
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
            text = if (compact) "…" else "正在导入…"
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
                        "已同步 ${summary.totalEvents} 条课程到「${summary.calendarName}」" +
                            "（新增 ${summary.insertedEvents}，更新 ${summary.updatedEvents}" +
                            "${duplicateText}${staleText}）",
                        Toast.LENGTH_LONG,
                    ).show()
                }.onFailure { error ->
                    Toast.makeText(
                        activity,
                        error.message ?: "系统日历导入失败。",
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
                .show()
        }

        setOnClickListener { anchor ->
            if (compact) {
                PopupMenu(activity, anchor).apply {
                    menu.add(0, R.id.calendar_import_menu_item, 0, "导入手机日历")
                    setOnMenuItemClickListener { item ->
                        if (item.itemId == R.id.calendar_import_menu_item) {
                            confirmImport()
                            true
                        } else {
                            false
                        }
                    }
                }.show()
            } else {
                confirmImport()
            }
        }
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
                onChanged()
            },
            selectedDate.get(Calendar.YEAR),
            selectedDate.get(Calendar.MONTH),
            selectedDate.get(Calendar.DAY_OF_MONTH),
        ).show()
    }

    private fun periodTitle(): String {
        val date = when (selectedMode) {
            Mode.DAY -> SimpleDateFormat("yyyy年M月d日", Locale.CHINA).apply {
                timeZone = shanghai
            }.format(selectedDate.time)
            Mode.WEEK, Mode.MONTH -> SimpleDateFormat("yyyy年M月", Locale.CHINA).apply {
                timeZone = shanghai
            }.format(selectedDate.time)
            Mode.YEAR -> SimpleDateFormat("yyyy年", Locale.CHINA).apply {
                timeZone = shanghai
            }.format(selectedDate.time)
        }
        return if (selectedMode == Mode.WEEK) {
            "$date 第${selectedDate.get(Calendar.WEEK_OF_YEAR)}周"
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
                    text = "${selectedDate.get(Calendar.WEEK_OF_YEAR)}\n周"
                    textSize = 9.5f
                    gravity = Gravity.CENTER
                    setTextColor(Palette.muted)
                    includeFontPadding = false
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
                        append(SimpleDateFormat("E", Locale.CHINA).apply { timeZone = shanghai }.format(day.time))
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
                        if (selected) Palette.primaryFill else Color.TRANSPARENT,
                        when {
                            selected -> Palette.primaryFill
                            isToday -> Palette.primary
                            else -> Color.TRANSPARENT
                        },
                        radius = 10,
                    ).apply {
                        if (isToday && !selected) setStroke(activity.dp(2), Palette.primary)
                    }
                    isClickable = true
                    isFocusable = true
                    contentDescription = SimpleDateFormat("M月d日 EEEE", Locale.CHINA).apply {
                        timeZone = shanghai
                    }.format(day.time)
                    setOnClickListener {
                        if (!sameDay(selectedDate, day)) performCalendarHaptic()
                        selectedDate.timeInMillis = day.timeInMillis
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
        val formatter = SimpleDateFormat("yyyy年M月d日 EEEE", Locale.CHINA).apply { timeZone = shanghai }
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
        val formatter = SimpleDateFormat("yyyy年M月d日 EEEE", Locale.CHINA).apply { timeZone = shanghai }
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
        if (days.any { it.holidays.isNotEmpty() }) {
            addView(allDayStrip(days, compact = false, onDaySelected = null))
        }
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
            onDateChanged()
        }
        if (timelineDays.any { it.holidays.isNotEmpty() }) {
            addView(allDayStrip(timelineDays, compact = false, onDaySelected = selectDay))
        }
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
        val monthTitle = SimpleDateFormat("yyyy年M月", Locale.CHINA).apply { timeZone = shanghai }
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
                            onPositionChanged = onPositionChanged,
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
        addView(ScrollView(activity).apply {
            id = R.id.calendar_month_selected_details
            visibility = if (renderedMonthSheetPosition <= 0.01f) View.GONE else View.VISIBLE
            isFillViewport = false
            clipToPadding = false
            scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
            addView(selectedDayDetails(selectedDate, asCard = true))
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
        listOf("一", "二", "三", "四", "五", "六", "日").forEach { label ->
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
        onPositionChanged: (Float) -> Unit,
        sheetPosition: Float,
    ): LinearLayout {
        val courses = coursesOn(day)
        val holidays = holidaysOn(day)
        val inMonth = day.get(Calendar.MONTH) == selectedDate.get(Calendar.MONTH) &&
            day.get(Calendar.YEAR) == selectedDate.get(Calendar.YEAR)
        val selected = sameDay(day, selectedDate)
        val today = sameDay(day, Calendar.getInstance(shanghai))
        return LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = calendarCellBackground(
                selected = selected,
                today = today,
                courseCount = courses.size,
                muted = !inMonth,
            )
            isClickable = true
            isFocusable = true
            contentDescription = buildList {
                add("${day.get(Calendar.MONTH) + 1}月${day.get(Calendar.DAY_OF_MONTH)}日")
                holidays.forEach { add(it.name) }
                courses.forEach { add("${it.name} ${it.timeRange} ${it.room} ${it.teacher}") }
            }.joinToString("，")
            setOnClickListener {
                if (!sameDay(selectedDate, day) ||
                    renderedMonthSheetPosition.roundToInt() !=
                    TeachingCalendarLogic.monthSheetDetailsPosition.roundToInt()
                ) {
                    performCalendarHaptic()
                }
                selectedDate.timeInMillis = day.timeInMillis
                onDateChanged()
                onPositionChanged(TeachingCalendarLogic.monthDaySelectionTargetPosition())
            }
            addView(TextView(activity).apply {
                id = R.id.calendar_month_day_label
                text = day.get(Calendar.DAY_OF_MONTH).toString()
                gravity = Gravity.CENTER
                maxLines = 1
                setTypeface(typeface, if (selected || today) Typeface.BOLD else Typeface.NORMAL)
                setTextColor(when {
                    selected -> Palette.onPrimary
                    !inMonth -> Palette.outOfMonth
                    holidays.any { it.type == "holiday" } -> Palette.holiday
                    else -> Palette.text
                })
            })
            val entries = buildList {
                holidays.forEach { item ->
                    add(MonthCalendarEntry(
                        title = (if (item.type == "holiday") "休 " else "班 ") + item.name,
                    ))
                }
                courses.forEach { course -> add(MonthCalendarEntry(course.name)) }
            }
            addView(LinearLayout(activity).apply {
                id = R.id.calendar_month_expanded_entries
                orientation = LinearLayout.VERTICAL
                tag = MonthEntriesRenderState(entries, selected)
            })
            val marker = buildString {
                holidays.firstOrNull()?.let { append(if (it.type == "holiday") "休" else "班") }
                if (holidays.isNotEmpty() && courses.isNotEmpty()) append("  ")
                repeat(courses.size.coerceAtMost(3)) { append("•") }
            }
            addView(TextView(activity).apply {
                id = R.id.calendar_month_compact_marker
                text = marker
                textSize = 9.5f
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                setTextColor(if (selected) Palette.onPrimary else Palette.muted)
            })
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.MATCH_PARENT,
                1f,
            ).apply {
                marginEnd = activity.dp(2)
                bottomMargin = activity.dp(2)
            }
            val expandedProgress = TeachingCalendarLogic.monthCellExpansionProgress(sheetPosition)
            val initialCellHeightDp = TeachingCalendarLogic.monthRowHeightDp(
                position = sheetPosition,
                rowIndex = 0,
                selectedWeekIndex = 0,
                expandedHeightDp = expandedMonthCellHeightDp,
            )
            applyMonthDayCellProgress(this, expandedProgress, initialCellHeightDp)
        }
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
                container.addView(monthEntryView(
                    MonthCalendarEntry("+$hiddenCount"),
                    state.selected,
                ), LinearLayout.LayoutParams(
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
        monthView.findViewById<View>(R.id.calendar_month_selected_details).apply {
            visibility = if (resolved <= 0.01f) View.GONE else View.VISIBLE
            alpha = resolved.coerceIn(0f, 1f)
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
        textSize = 9.5f
        gravity = Gravity.CENTER_VERTICAL
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        setPadding(activity.dp(3), 0, activity.dp(3), 0)
        setTextColor(TeachingCalendarLogic.monthEntryTextColor(
            selected = selected,
            textColor = Palette.text,
            onPrimaryColor = Palette.onPrimary,
        ))
        background = roundedBackground(
            activity,
            TeachingCalendarLogic.monthEntryBackgroundColor(
                selected = selected,
                surfaceVariantColor = Palette.surfaceVariant,
                primaryDarkColor = Palette.primaryDark,
            ),
            Palette.border,
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
            text = "颜色越深表示当天课程越多"
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
                onDateSelected = { anchor, day, tapX, tapY ->
                    performCalendarHaptic()
                    showDayPopover(anchor, day, tapX, tapY, onDateChanged)
                },
                onMonthSelected = { month ->
                    performCalendarHaptic()
                    selectedDate.timeInMillis = month.timeInMillis
                    pendingPageDirection = TeachingCalendarLogic.modeTransitionDirection(
                        selectedMode.ordinal,
                        Mode.MONTH.ordinal,
                    )
                    selectedMode = Mode.MONTH
                    onDateChanged()
                },
            ),
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    private fun allDayStrip(
        days: List<TimelineDay>,
        compact: Boolean,
        onDaySelected: ((Calendar) -> Unit)?,
    ): LinearLayout = LinearLayout(activity).apply {
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
                val hasHoliday = day.holidays.isNotEmpty()
                addView(TextView(activity).apply {
                    text = day.holidays.joinToString(" · ") { holiday ->
                        "${if (holiday.type == "holiday") "休" else "班"} ${holiday.name}"
                    }
                    textSize = if (compact && days.size > 1) 9.5f else 11f
                    gravity = Gravity.CENTER
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    setPadding(activity.dp(3), 0, activity.dp(3), 0)
                    setTextColor(if (day.holidays.any { it.type == "holiday" }) {
                        Palette.holiday
                    } else {
                        Palette.primaryText
                    })
                    background = if (hasHoliday) {
                        roundedBackground(activity, Palette.selectionSurface, radius = 4)
                    } else {
                        null
                    }
                    isClickable = onDaySelected != null && hasHoliday
                    isFocusable = onDaySelected != null && hasHoliday
                    contentDescription = if (hasHoliday) {
                        val date = SimpleDateFormat("M月d日", Locale.CHINA).apply {
                            timeZone = shanghai
                        }.format(day.date.time)
                        "$date，全天，$text"
                    } else {
                        null
                    }
                    setOnClickListener {
                        if (hasHoliday) {
                            onDaySelected?.invoke(day.date.clone() as Calendar)
                            day.holidays.firstOrNull()?.let(::showHolidayDetails)
                        }
                    }
                }, LinearLayout.LayoutParams(0, activity.dp(36), 1f).apply {
                    marginStart = activity.dp(2)
                    marginEnd = activity.dp(2)
                })
            }
        }, LinearLayout.LayoutParams(0, activity.dp(40), 1f))
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

        val visibleFrame = Rect().also(anchor::getWindowVisibleDisplayFrame)
        val panelWidth = minOf(activity.dp(300), visibleFrame.width() - activity.dp(32))
        val maximumHeight = (visibleFrame.height() - activity.dp(32)).coerceAtLeast(activity.dp(112))
        val panel = ScrollView(activity).apply {
            scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            setPadding(activity.dp(14), activity.dp(14), activity.dp(14), activity.dp(14))
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(selectedDayDetails(day))
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
                            pendingPageDirection = TeachingCalendarLogic.modeTransitionDirection(
                                selectedMode.ordinal,
                                mode.ordinal,
                            )
                            selectedMode = mode
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
                anchor.clearSelection()
                if (activePopup === popup) {
                    activePopup = null
                    activePopupAnchor = null
                }
            }
        }
        activePopup = popup
        popup.showAtLocation(anchor, Gravity.TOP or Gravity.START, popupX, popupY)
    }

    private fun selectedDayDetails(
        day: Calendar,
        asCard: Boolean = false,
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
        val formatter = SimpleDateFormat("yyyy年M月d日 EEEE", Locale.CHINA).apply { timeZone = shanghai }
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
                    text = if (course.examWeekNumbers.isEmpty()) course.name else "试  ${course.name}"
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
        val date = SimpleDateFormat("yyyy年M月d日 EEEE", Locale.CHINA).apply {
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
            .setMessage("日期：${item.date}\n类型：${if (item.type == "holiday") "法定节假日" else "调休工作日"}")
            .setPositiveButton("完成", null)
            .show()
    }

    private fun yearCalendarDays(year: Int): List<YearCalendarDay> {
        val formatter = contractDate()
        val holidaysByDate = holidayRepository.items(year).groupBy(HolidayItem::date)
        return buildList {
            for (month in 1..12) {
                val date = Calendar.getInstance(shanghai).apply {
                    set(year, month - 1, 1, 12, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                repeat(date.getActualMaximum(Calendar.DAY_OF_MONTH)) { dayOffset ->
                    date.set(Calendar.DAY_OF_MONTH, dayOffset + 1)
                    val snapshot = date.clone() as Calendar
                    add(
                        YearCalendarDay(
                            date = snapshot,
                            courseCount = coursesOn(snapshot).size,
                            holidays = holidaysByDate[formatter.format(snapshot.time)].orEmpty(),
                        ),
                    )
                }
            }
        }
    }

    private fun dismissYearPopover() {
        val popup = activePopup
        activePopup = null
        if (popup?.isShowing == true) popup.dismiss()
        activePopupAnchor?.clearSelection()
        activePopupAnchor = null
    }

    private fun calendarCellBackground(
        selected: Boolean,
        today: Boolean,
        courseCount: Int,
        muted: Boolean,
    ): GradientDrawable {
        val fill = when {
            selected -> Palette.primaryFill
            muted -> Color.TRANSPARENT
            courseCount <= 0 -> Color.TRANSPARENT
            else -> blend(
                Palette.primary,
                Palette.background,
                TeachingCalendarLogic.yearCourseOpacity(courseCount),
            )
        }
        return roundedBackground(
            activity,
            fill,
            when {
                today && !selected -> Palette.nowIndicator
                else -> Color.TRANSPARENT
            },
            radius = 9,
        ).apply {
            if (today && !selected) setStroke(activity.dp(2), Palette.nowIndicator)
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

    private fun stepDate(direction: Int) {
        when (selectedMode) {
            Mode.DAY -> selectedDate.add(Calendar.DAY_OF_MONTH, direction)
            Mode.WEEK -> selectedDate.add(Calendar.DAY_OF_MONTH, direction * 7)
            Mode.MONTH -> selectedDate.add(Calendar.MONTH, direction)
            Mode.YEAR -> selectedDate.add(Calendar.YEAR, direction)
        }
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

    private fun blend(foreground: Int, background: Int, amount: Float): Int = Color.rgb(
        (Color.red(background) + (Color.red(foreground) - Color.red(background)) * amount).toInt(),
        (Color.green(background) + (Color.green(foreground) - Color.green(background)) * amount).toInt(),
        (Color.blue(background) + (Color.blue(foreground) - Color.blue(background)) * amount).toInt(),
    )

}
