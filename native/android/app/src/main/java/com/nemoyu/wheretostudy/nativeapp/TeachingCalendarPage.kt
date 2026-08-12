package com.nemoyu.wheretostudy.nativeapp

import android.app.DatePickerDialog
import android.graphics.Color
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

object TeachingCalendarLogic {
    fun yearCourseOpacity(courseCount: Int): Float {
        if (courseCount <= 0) return 0f
        val count = courseCount.toFloat()
        return 0.12f + 0.72f * count / (count + 3f)
    }
}

class TeachingCalendarPage(
    private val activity: MainActivity,
    private val scheduleRepository: ScheduleRepository,
    private val holidayRepository: HolidayRepository,
) {
    private enum class Mode(val label: String) {
        DAY("日"),
        WEEK("周"),
        MONTH("月"),
        YEAR("年"),
    }

    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val selectedDate = Calendar.getInstance(shanghai)
    private var selectedMode = Mode.WEEK
    private var activePopupAnchor: YearCalendarView? = null
    private var activePopup: PopupWindow? = null

    fun build(): ScrollView {
        val scrollView = ScrollView(activity).apply {
            isFillViewport = true
            setBackgroundColor(Palette.background)
        }
        val root = verticalPage(activity)
        scrollView.addView(root)
        val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val tabs = mutableMapOf<Mode, TextView>()

        fun render() {
            dismissYearPopover()
            tabs.forEach { (mode, view) -> view.setSelectedStyle(activity, mode == selectedMode) }
            content.removeAllViews()
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
            content.addView(
                when (selectedMode) {
                    Mode.DAY -> dayView()
                    Mode.WEEK -> weekView(::render)
                    Mode.MONTH -> monthView(::render)
                    Mode.YEAR -> yearView()
                },
            )
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
                    selectedMode = mode
                    render()
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

    private fun calendarImportButton(): TextView = TextView(activity).apply {
        text = "导入系统日历"
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(Palette.onPrimary)
        setTypeface(typeface, Typeface.BOLD)
        background = roundedBackground(activity, Palette.primary, radius = 6)
        isClickable = true
        isFocusable = true
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(48),
        )
        setOnClickListener {
            text = "正在导入…"
            isEnabled = false
            activity.importCachedScheduleToSystemCalendar { result ->
                if (isAttachedToWindow) {
                    text = "导入系统日历"
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
    }

    private fun dateNavigation(onChanged: () -> Unit): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(navigationButton("‹") {
            stepDate(-1)
            onChanged()
        })
        addView(TextView(activity).apply {
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
        val timeline = CalendarTimelineView(
            activity,
            listOf(timelineDay(selectedDate)),
            selectedDate,
        )
        addView(timeline, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
    }

    private fun weekView(onDateChanged: () -> Unit): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "本周时间轴"))
        val days = weekDates()
        addView(
            CalendarTimelineView(
                activity,
                days.map(::timelineDay),
                selectedDate,
            ) { day ->
                selectedDate.timeInMillis = day.timeInMillis
                onDateChanged()
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    private fun monthView(onDateChanged: () -> Unit): LinearLayout = surface(activity).apply {
        val monthTitle = SimpleDateFormat("yyyy年M月", Locale.CHINA).apply { timeZone = shanghai }
        addView(sectionTitle(activity, monthTitle.format(selectedDate.time)))
        addView(weekdayHeader())
        monthGridDates().chunked(7).forEach { week ->
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                week.forEach { day -> addView(monthDayCell(day, onDateChanged)) }
            })
        }
        addView(spacer(activity, 12))
        addView(selectedDayDetails(selectedDate))
    }

    private fun weekdayHeader(): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        listOf("一", "二", "三", "四", "五", "六", "日").forEach { label ->
            addView(TextView(activity).apply {
                text = label
                textSize = 12f
                gravity = Gravity.CENTER
                setTextColor(Palette.muted)
                setTypeface(typeface, Typeface.BOLD)
                layoutParams = LinearLayout.LayoutParams(0, activity.dp(28), 1f)
            })
        }
    }

    private fun monthDayCell(day: Calendar, onDateChanged: () -> Unit): TextView {
        val courses = coursesOn(day)
        val holidays = holidaysOn(day)
        val inMonth = day.get(Calendar.MONTH) == selectedDate.get(Calendar.MONTH) &&
            day.get(Calendar.YEAR) == selectedDate.get(Calendar.YEAR)
        val selected = sameDay(day, selectedDate)
        val today = sameDay(day, Calendar.getInstance(shanghai))
        return TextView(activity).apply {
            text = buildList {
                add(if (today) "今天 ${day.get(Calendar.DAY_OF_MONTH)}" else day.get(Calendar.DAY_OF_MONTH).toString())
                holidays.firstOrNull()?.let { add("${if (it.type == "holiday") "休" else "班"} ${it.name}") }
                if (holidays.isEmpty()) add(if (courses.isEmpty()) "无课" else "${courses.size} 门课")
            }.joinToString("\n")
            textSize = 11f
            gravity = Gravity.TOP or Gravity.START
            maxLines = 3
            setPadding(activity.dp(5), activity.dp(6), activity.dp(4), activity.dp(4))
            setTextColor(when {
                selected -> Palette.onPrimary
                !inMonth -> Palette.outOfMonth
                holidays.any { it.type == "holiday" } -> Palette.holiday
                else -> Palette.text
            })
            background = calendarCellBackground(
                selected = selected,
                today = today,
                courseCount = courses.size,
                muted = !inMonth,
            )
            isClickable = true
            isFocusable = true
            setOnClickListener {
                selectedDate.timeInMillis = day.timeInMillis
                onDateChanged()
            }
            layoutParams = LinearLayout.LayoutParams(0, activity.dp(80), 1f).apply {
                marginEnd = activity.dp(2)
                bottomMargin = activity.dp(2)
            }
        }
    }

    private fun yearView(): LinearLayout = surface(activity).apply {
        val year = selectedDate.get(Calendar.YEAR)
        addView(sectionTitle(activity, "$year 年课程分布"))
        addView(TextView(activity).apply {
            text = "颜色越深表示当天课程越多；点击日期查看日程"
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(0, 0, 0, activity.dp(12))
        })
        addView(
            YearCalendarView(
                context = activity,
                year = year,
                days = yearCalendarDays(year),
                onDateSelected = ::showDayPopover,
            ),
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    private fun showDayPopover(
        anchor: YearCalendarView,
        day: Calendar,
        tapX: Float,
        tapY: Float,
    ) {
        dismissYearPopover()
        anchor.selectDate(day)
        activePopupAnchor = anchor

        val visibleFrame = Rect().also(anchor::getWindowVisibleDisplayFrame)
        val panelWidth = minOf(activity.dp(300), visibleFrame.width() - activity.dp(32))
        val maximumHeight = (visibleFrame.height() - activity.dp(32)).coerceAtLeast(activity.dp(112))
        val panel = ScrollView(activity).apply {
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            setPadding(activity.dp(14), activity.dp(14), activity.dp(14), activity.dp(14))
            addView(selectedDayDetails(day))
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

    private fun selectedDayDetails(day: Calendar): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
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
                addView(TextView(activity).apply {
                    text = listOf(course.timeRange, course.name, course.room)
                        .filter(String::isNotEmpty).joinToString("  ·  ")
                    textSize = 13f
                    setTextColor(Palette.primaryText)
                    setPadding(0, activity.dp(3), 0, activity.dp(3))
                })
            }
        }
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
            selected -> Palette.primary
            muted -> Palette.surface
            courseCount <= 0 -> Palette.background
            else -> blend(
                Palette.primary,
                Palette.surface,
                TeachingCalendarLogic.yearCourseOpacity(courseCount),
            )
        }
        return roundedBackground(
            activity,
            fill,
            when {
                today -> Palette.nowIndicator
                selected -> Palette.primary
                else -> Palette.border
            },
            radius = 3,
        ).apply {
            if (today) setStroke(activity.dp(2), Palette.nowIndicator)
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

    private companion object {
    }
}
