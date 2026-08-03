package com.nemoyu.wheretostudy.nativeapp

import android.graphics.Typeface
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class PlannerPage(
    private val activity: MainActivity,
    private val preferences: AppPreferences,
    private val scheduleRepository: ScheduleRepository,
) {
    private val selectedSlots = AppMetadata.slots.mapTo(mutableSetOf()) { it.index }

    fun build(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        setBackgroundColor(Palette.background)
        addView(verticalPage(activity).apply {
            val date = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).apply {
                timeZone = TimeZone.getTimeZone("Asia/Shanghai")
            }.format(Date())
            addView(pageTitle(activity, "空教室与个人课表联动查询", date))
            addView(querySurface())
            addView(spacer(activity, 16))
            addView(todayCoursesSurface())
            addView(spacer(activity, 16))
            addView(classroomsSurface())
        })
    }

    private fun querySurface(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "查询条件"))
        addView(TextView(activity).apply {
            text = "校区"
            textSize = 13f
            setTextColor(Palette.muted)
            setPadding(0, 0, 0, activity.dp(8))
        })
        addView(campusControl())
        addView(spacer(activity, 16))
        addView(TextView(activity).apply {
            text = "节次筛选"
            textSize = 13f
            setTextColor(Palette.muted)
            setPadding(0, 0, 0, activity.dp(8))
        })
        addView(slotControl())
    }

    private fun campusControl(): LinearLayout {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val tabs = mutableListOf<Pair<CampusMetadata, TextView>>()
        AppMetadata.campuses.forEach { campus ->
            lateinit var tab: TextView
            tab = fixedTab(activity, campus.name) {
                preferences.campusID = campus.id
                tabs.forEach { (item, view) ->
                    view.setSelectedStyle(activity, item.id == campus.id)
                }
            }
            tab.layoutParams = LinearLayout.LayoutParams(0, activity.dp(46), 1f).apply {
                marginEnd = activity.dp(8)
            }
            tabs += campus to tab
            row.addView(tab)
        }
        tabs.forEach { (campus, view) ->
            view.setSelectedStyle(activity, campus.id == preferences.campusID)
        }
        return row
    }

    private fun slotControl(): LinearLayout {
        val columns = if (activity.resources.configuration.screenWidthDp >= 700) 7 else 2
        return LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            AppMetadata.slots.chunked(columns).forEach { slots ->
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    slots.forEach { slot ->
                        val cell = TextView(activity).apply {
                            text = activity.getString(
                                R.string.slot_format,
                                slot.label,
                                slot.start,
                                slot.end,
                            )
                            textSize = 13f
                            gravity = Gravity.CENTER
                            isClickable = true
                            isFocusable = true
                        }
                        fun refresh() {
                            cell.setSelectedStyle(activity, slot.index in selectedSlots)
                            cell.setTypeface(cell.typeface, Typeface.BOLD)
                        }
                        cell.setOnClickListener {
                            if (!selectedSlots.add(slot.index)) {
                                selectedSlots.remove(slot.index)
                            }
                            refresh()
                        }
                        cell.layoutParams = LinearLayout.LayoutParams(0, activity.dp(58), 1f).apply {
                            marginEnd = activity.dp(7)
                            bottomMargin = activity.dp(7)
                        }
                        refresh()
                        addView(cell)
                    }
                    repeat(columns - slots.size) {
                        addView(TextView(activity).apply {
                            layoutParams = LinearLayout.LayoutParams(0, activity.dp(58), 1f).apply {
                                marginEnd = activity.dp(7)
                            }
                        })
                    }
                })
            }
        }
    }

    private fun todayCoursesSurface(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "当天课程"))
        val today = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
        val courses = ScheduleLogic.courses(scheduleRepository.schedule, today)
        if (courses.isEmpty()) {
            addView(emptyMessage("暂无本地课程，请在设置中获取/刷新个人课表"))
        } else {
            courses.forEach { course -> addView(courseRow(course)) }
        }
    }

    private fun classroomsSurface(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "空教室结果"))
        addView(emptyMessage("暂无本地空教室数据"))
    }

    private fun emptyMessage(message: String): TextView = TextView(activity).apply {
        text = message
        textSize = 14f
        gravity = Gravity.CENTER
        setTextColor(Palette.muted)
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(92),
        )
    }

    private fun courseRow(course: Course): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(activity.dp(12), activity.dp(10), activity.dp(12), activity.dp(10))
        background = roundedBackground(activity, Palette.background, Palette.border, radius = 4)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { bottomMargin = activity.dp(8) }
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(activity).apply {
                text = if (course.examWeekNumbers.isEmpty()) course.name else "试  ${course.name}"
                textSize = 15f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(activity).apply {
                text = course.room.ifEmpty { "地点未标注" }
                textSize = 12f
                setTextColor(Palette.muted)
            })
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(activity).apply {
            text = course.timeRange
            textSize = 13f
            setTextColor(Palette.muted)
            gravity = Gravity.END
        })
    }
}
