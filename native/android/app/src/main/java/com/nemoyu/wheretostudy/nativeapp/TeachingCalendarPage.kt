package com.nemoyu.wheretostudy.nativeapp

import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.CalendarView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

class TeachingCalendarPage(
    private val activity: MainActivity,
    private val scheduleRepository: ScheduleRepository,
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

    fun build(): ScrollView {
        val scrollView = ScrollView(activity).apply {
            isFillViewport = true
            setBackgroundColor(Palette.background)
        }
        val root = verticalPage(activity)
        scrollView.addView(root)

        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
        }
        val tabs = mutableMapOf<Mode, TextView>()

        fun render() {
            tabs.forEach { (mode, view) -> view.setSelectedStyle(activity, mode == selectedMode) }
            content.removeAllViews()
            content.addView(dateSummary())
            content.addView(spacer(activity, 12))
            content.addView(
                when (selectedMode) {
                    Mode.DAY -> dayView()
                    Mode.WEEK -> weekView()
                    Mode.MONTH -> monthView { render() }
                    Mode.YEAR -> yearView()
                },
            )
        }

        root.addView(pageTitle(activity, "教学日历", "课程与节次按本地课表展示"))
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
        root.addView(spacer(activity, 16))
        root.addView(content)
        render()
        return scrollView
    }

    private fun dateSummary(): LinearLayout = surface(activity).apply {
        val formatter = SimpleDateFormat("yyyy年M月d日 EEEE", Locale.CHINA).apply {
            timeZone = shanghai
        }
        addView(TextView(activity).apply {
            text = formatter.format(selectedDate.time)
            textSize = 20f
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
        })
        addView(TextView(activity).apply {
            val courses = coursesOn(selectedDate)
            text = if (courses.isEmpty()) "暂无课程" else "${courses.size} 门课"
            textSize = 14f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(5), 0, 0)
        })
    }

    private fun dayView(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "当日课表"))
        val courses = coursesOn(selectedDate)
        AppMetadata.slots.forEach { slot ->
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = roundedBackground(activity, Palette.background, Palette.border, radius = 0)
                setPadding(activity.dp(12), 0, activity.dp(12), 0)
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    activity.dp(64),
                ).apply { bottomMargin = activity.dp(1) }
                addView(TextView(activity).apply {
                    text = activity.getString(
                        R.string.slot_format,
                        slot.label,
                        slot.start,
                        slot.end,
                    )
                    textSize = 13f
                    setTextColor(Palette.muted)
                    gravity = Gravity.CENTER_VERTICAL
                    layoutParams = LinearLayout.LayoutParams(activity.dp(112), ViewGroup.LayoutParams.MATCH_PARENT)
                })
                addView(TextView(activity).apply {
                    val course = courses.firstOrNull {
                        slot.index in it.startSlot..it.endSlot
                    }
                    text = when {
                        course == null -> "暂无课程"
                        course.startSlot == slot.index -> listOf(
                            course.name,
                            course.room,
                            course.timeRange,
                        ).filter(String::isNotEmpty).joinToString("  ·  ")
                        else -> "${course.name}（延续）"
                    }
                    textSize = 14f
                    setTextColor(if (course == null) Palette.muted else Palette.primaryDark)
                    if (course != null) setTypeface(typeface, Typeface.BOLD)
                    gravity = Gravity.CENTER_VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
                })
            })
        }
    }

    private fun weekView(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "本周课程"))
        val firstDay = selectedDate.clone() as Calendar
        val weekdayOffset = (firstDay.get(Calendar.DAY_OF_WEEK) + 5) % 7
        firstDay.add(Calendar.DAY_OF_MONTH, -weekdayOffset)
        val dayFormatter = SimpleDateFormat("M月d日 E", Locale.CHINA).apply { timeZone = shanghai }
        repeat(7) { dayIndex ->
            val day = firstDay.clone() as Calendar
            day.add(Calendar.DAY_OF_MONTH, dayIndex)
            val courses = coursesOn(day)
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(activity.dp(12), 0, activity.dp(12), 0)
                background = roundedBackground(
                    activity,
                    if (sameDay(day, selectedDate)) ColorTokens.selectedDay else Palette.background,
                    Palette.border,
                    radius = 4,
                )
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { bottomMargin = activity.dp(6) }
                minimumHeight = activity.dp(56)
                addView(TextView(activity).apply {
                    text = dayFormatter.format(day.time)
                    textSize = 15f
                    setTextColor(Palette.text)
                    setTypeface(typeface, Typeface.BOLD)
                    layoutParams = LinearLayout.LayoutParams(activity.dp(132), ViewGroup.LayoutParams.MATCH_PARENT)
                    gravity = Gravity.CENTER_VERTICAL
                })
                addView(TextView(activity).apply {
                    text = if (courses.isEmpty()) {
                        "暂无课程"
                    } else {
                        courses.joinToString("\n") { "${it.timeRange}  ${it.name}" }
                    }
                    textSize = 14f
                    setTextColor(if (courses.isEmpty()) Palette.muted else Palette.primaryDark)
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(0, activity.dp(8), 0, activity.dp(8))
                })
            })
        }
    }

    private fun monthView(onDateChanged: () -> Unit): View = surface(activity).apply {
        addView(sectionTitle(activity, "月视图"))
        addView(CalendarView(activity).apply {
            date = selectedDate.timeInMillis
            firstDayOfWeek = Calendar.MONDAY
            setOnDateChangeListener { _, year, month, dayOfMonth ->
                selectedDate.set(year, month, dayOfMonth)
                onDateChanged()
            }
        })
        val selectedCourses = coursesOn(selectedDate)
        addView(TextView(activity).apply {
            text = if (selectedCourses.isEmpty()) {
                "选中日期暂无课程"
            } else {
                selectedCourses.joinToString("\n") { "${it.timeRange}  ${it.name}  ${it.room}" }
            }
            textSize = 14f
            setTextColor(if (selectedCourses.isEmpty()) Palette.muted else Palette.primaryDark)
            setPadding(0, activity.dp(12), 0, 0)
        })
    }

    private fun yearView(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "${selectedDate.get(Calendar.YEAR)} 年"))
        val months = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        (1..12).chunked(3).forEach { rowMonths ->
            months.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                rowMonths.forEach { month ->
                    val courseCount = courseCountInMonth(selectedDate.get(Calendar.YEAR), month)
                    addView(TextView(activity).apply {
                        text = if (courseCount == 0) "$month 月\n暂无课程" else "$month 月\n$courseCount 门课"
                        textSize = 15f
                        gravity = Gravity.CENTER
                        setTextColor(Palette.text)
                        background = roundedBackground(activity, Palette.background, Palette.border, radius = 4)
                        layoutParams = LinearLayout.LayoutParams(0, activity.dp(82), 1f).apply {
                            marginEnd = activity.dp(7)
                            bottomMargin = activity.dp(7)
                        }
                    })
                }
            })
        }
        addView(months)
    }

    private fun sameDay(left: Calendar, right: Calendar): Boolean =
        left.get(Calendar.ERA) == right.get(Calendar.ERA) &&
            left.get(Calendar.YEAR) == right.get(Calendar.YEAR) &&
            left.get(Calendar.DAY_OF_YEAR) == right.get(Calendar.DAY_OF_YEAR)

    private fun coursesOn(date: Calendar): List<Course> =
        ScheduleLogic.courses(scheduleRepository.schedule, date)

    private fun courseCountInMonth(year: Int, month: Int): Int {
        val date = Calendar.getInstance(shanghai).apply {
            set(year, month - 1, 1, 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val days = date.getActualMaximum(Calendar.DAY_OF_MONTH)
        return (1..days).sumOf { day ->
            val target = date.clone() as Calendar
            target.set(Calendar.DAY_OF_MONTH, day)
            coursesOn(target).size
        }
    }

    private object ColorTokens {
        val selectedDay = android.graphics.Color.rgb(232, 244, 239)
    }
}
