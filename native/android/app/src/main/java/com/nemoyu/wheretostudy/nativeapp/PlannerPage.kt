package com.nemoyu.wheretostudy.nativeapp

import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.AbsListView
import android.widget.BaseAdapter
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class PlannerPage(
    private val activity: MainActivity,
    private val preferences: AppPreferences,
    private val scheduleRepository: ScheduleRepository,
    private val classroomRepository: ClassroomRepository,
    private val availableWidthDp: Int,
) {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val today = Calendar.getInstance(shanghai)
    private val personalBusySlots = ScheduleLogic.busySlots(scheduleRepository.schedule, today)
    private val selectedSlots = AppMetadata.slots.mapNotNullTo(mutableSetOf()) { slot ->
        slot.index.takeUnless(personalBusySlots::contains)
    }
    private val selectedBuildings = mutableSetOf<String>()
    private var usePersonalSchedule = true
    private lateinit var resultsAdapter: ClassroomResultsAdapter
    private lateinit var summaryContainer: LinearLayout

    fun build(): ListView = ListView(activity).apply {
        setBackgroundColor(Palette.background)
        divider = null
        dividerHeight = 0
        isVerticalScrollBarEnabled = true
        addHeaderView(verticalPage(activity).apply {
            layoutParams = AbsListView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            val date = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).apply {
                timeZone = shanghai
            }.format(Date())
            addView(pageTitle(activity, "空教室与个人课表联动查询", date))
            addSection(querySurface())
            addSection(slotSurface())
            addSection(todayCoursesSurface())
            addSection(buildingsSurface())
            addView(surface(activity).apply {
                addView(sectionTitle(activity, "空教室结果"))
            })
        }, null, false)
        addFooterView(verticalPage(activity).apply {
            layoutParams = AbsListView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            addView(spacer(activity, 8))
            summaryContainer = surface(activity)
            addView(summaryContainer)
        }, null, false)
        resultsAdapter = ClassroomResultsAdapter()
        adapter = resultsAdapter
        renderResultsAndSummary()
    }

    private fun LinearLayout.addSection(view: LinearLayout) {
        addView(view)
        addView(spacer(activity, 16))
    }

    private fun querySurface(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "查询条件"))
        addView(label("校区"))
        addView(campusControl())
        addView(spacer(activity, 14))
        addView(fetchButton())
        classroomRepository.cache?.let { cache ->
            addView(TextView(activity).apply {
                text = activity.getString(R.string.classroom_source_format, cache.targetDate)
                textSize = 12f
                setTextColor(Palette.muted)
                setPadding(0, activity.dp(10), 0, 0)
            })
        }
    }

    private fun label(value: String): TextView = TextView(activity).apply {
        text = value
        textSize = 13f
        setTextColor(Palette.muted)
        setPadding(0, 0, 0, activity.dp(8))
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
                selectedBuildings.clear()
                activity.refreshCurrentPage()
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

    private fun fetchButton(): TextView = TextView(activity).apply {
        text = if (classroomRepository.isRefreshing) "正在获取当天空教室…" else "获取空教室信息"
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(Palette.onPrimary)
        setTypeface(typeface, Typeface.BOLD)
        background = roundedBackground(activity, Palette.primary, radius = 6)
        isClickable = !classroomRepository.isRefreshing
        isFocusable = true
        isEnabled = !classroomRepository.isRefreshing
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(46),
        )
        setOnClickListener {
            val button = it as TextView
            button.text = "正在获取当天空教室…"
            button.isEnabled = false
            classroomRepository.refresh(force = true) { result ->
                result.onSuccess {
                    Toast.makeText(activity, "当天空教室已更新", Toast.LENGTH_SHORT).show()
                    activity.refreshCurrentPage()
                }.onFailure { error ->
                    button.text = "获取空教室信息"
                    button.isEnabled = true
                    Toast.makeText(
                        activity,
                        error.message ?: "当天空教室获取失败",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    private fun slotSurface(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "节次筛选"))
        val personalToggle = TextView(activity).apply {
            textSize = 14f
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(42),
            ).apply { bottomMargin = activity.dp(10) }
        }
        addView(personalToggle)
        val actions = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        addView(actions)
        val cells = mutableMapOf<Int, TextView>()

        fun refreshCells() {
            personalToggle.text = activity.getString(
                R.string.personal_schedule_state_format,
                activity.getString(if (usePersonalSchedule) R.string.state_on else R.string.state_off),
            )
            personalToggle.setSelectedStyle(activity, usePersonalSchedule)
            cells.forEach { (index, cell) ->
                val busy = usePersonalSchedule && index in personalBusySlots
                val selected = index in selectedSlots
                cell.isEnabled = !busy
                cell.setTextColor(
                    when {
                        selected -> Palette.onPrimary
                        busy -> Palette.onAccent
                        else -> Palette.text
                    },
                )
                cell.background = roundedBackground(
                    activity,
                    when {
                        selected -> Palette.primary
                        busy -> Palette.accent
                        else -> Palette.surface
                    },
                    if (selected) Palette.primary else Palette.border,
                    radius = 6,
                )
                cell.setTypeface(cell.typeface, Typeface.BOLD)
            }
        }

        fun action(label: String, onClick: () -> Unit): TextView = fixedTab(activity, label) {
            onClick()
            refreshCells()
            renderResultsAndSummary()
        }.apply {
            layoutParams = LinearLayout.LayoutParams(0, activity.dp(40), 1f).apply {
                marginEnd = activity.dp(7)
                bottomMargin = activity.dp(10)
            }
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
        }

        actions.addView(action("选中空闲") {
            selectedSlots.clear()
            selectedSlots += AppMetadata.slots.map(SlotMetadata::index)
                .filterNot { usePersonalSchedule && it in personalBusySlots }
        })
        actions.addView(action("清空") { selectedSlots.clear() })
        addView(slotControl(cells) { refreshCells() })

        personalToggle.setOnClickListener {
            usePersonalSchedule = !usePersonalSchedule
            if (usePersonalSchedule) {
                selectedSlots.removeAll(personalBusySlots)
            } else {
                selectedSlots.addAll(personalBusySlots)
            }
            refreshCells()
            renderResultsAndSummary()
        }
        refreshCells()
    }

    private fun slotControl(
        cells: MutableMap<Int, TextView>,
        refreshCells: () -> Unit,
    ): LinearLayout {
        val columns = AdaptiveContentLogic.plannerSlotColumns(availableWidthDp)
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
                            setOnClickListener {
                                if (usePersonalSchedule && slot.index in personalBusySlots) return@setOnClickListener
                                if (!selectedSlots.add(slot.index)) selectedSlots.remove(slot.index)
                                refreshCells()
                                renderResultsAndSummary()
                            }
                            layoutParams = LinearLayout.LayoutParams(0, activity.dp(58), 1f).apply {
                                marginEnd = activity.dp(7)
                                bottomMargin = activity.dp(7)
                            }
                        }
                        cells[slot.index] = cell
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
        val courses = ScheduleLogic.courses(scheduleRepository.schedule, today)
        if (courses.isEmpty()) {
            addView(emptyMessage("暂无本地课程，请在设置中获取/刷新个人课表"))
        } else {
            courses.forEach { course -> addView(courseRow(course)) }
        }
    }

    private fun buildingsSurface(): LinearLayout = surface(activity).apply {
        addView(sectionTitle(activity, "教学楼"))
        val buildings = campusRooms().map(Classroom::building).distinct().sorted()
        if (buildings.isEmpty()) {
            addView(emptyMessage("暂无教学楼，请先获取当天空教室"))
            return@apply
        }
        val columns = AdaptiveContentLogic.plannerBuildingColumns(availableWidthDp)
        val buttons = mutableMapOf<String, TextView>()
        fun refreshButtons() {
            buttons.forEach { (building, button) ->
                button.setSelectedStyle(activity, building in selectedBuildings)
            }
        }
        buildings.chunked(columns).forEach { rowBuildings ->
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                rowBuildings.forEach { building ->
                    val button = fixedTab(activity, building) {
                        if (!selectedBuildings.add(building)) selectedBuildings.remove(building)
                        refreshButtons()
                        renderResultsAndSummary()
                    }.apply {
                        layoutParams = LinearLayout.LayoutParams(0, activity.dp(48), 1f).apply {
                            marginEnd = activity.dp(7)
                            bottomMargin = activity.dp(7)
                        }
                    }
                    buttons[building] = button
                    addView(button)
                }
                repeat(columns - rowBuildings.size) {
                    addView(TextView(activity).apply {
                        layoutParams = LinearLayout.LayoutParams(0, activity.dp(48), 1f).apply {
                            marginEnd = activity.dp(7)
                        }
                    })
                }
            })
        }
        refreshButtons()
    }

    private fun renderResultsAndSummary() {
        if (::resultsAdapter.isInitialized) renderResults()
        if (::summaryContainer.isInitialized) renderSummary()
    }

    private fun renderResults() {
        val presentation = when {
            classroomRepository.cache == null -> {
                ClassroomResultsPresentation.empty("暂无本地空教室数据")
            }
            selectedBuildings.isEmpty() -> {
                ClassroomResultsPresentation.empty("未选择教学楼")
            }
            selectedSlots.isEmpty() -> {
                ClassroomResultsPresentation.empty("未选择节次")
            }
            else -> {
                val rooms = matchingRooms()
                if (rooms.isEmpty()) {
                    ClassroomResultsPresentation.empty("暂无匹配空教室")
                } else {
                    ClassroomResultsPresentation.from(rooms)
                }
            }
        }
        resultsAdapter.submit(presentation)
    }

    private fun renderSummary() {
        summaryContainer.removeAllViews()
        summaryContainer.addView(sectionTitle(activity, "查询概览"))
        val freeCount = if (usePersonalSchedule) {
            AppMetadata.slots.size - personalBusySlots.size
        } else {
            AppMetadata.slots.size
        }
        val values = listOf(
            "当天课程" to ScheduleLogic.courses(scheduleRepository.schedule, today).size,
            "个人空闲节次" to freeCount,
            "匹配教室" to if (selectedBuildings.isEmpty() || selectedSlots.isEmpty()) 0 else matchingRooms().size,
        )
        val columns = AdaptiveContentLogic.plannerSummaryColumns(availableWidthDp)
        fun metric(label: String, value: Int): LinearLayout = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(activity.dp(12), activity.dp(10), activity.dp(12), activity.dp(10))
            addView(TextView(activity).apply {
                text = label
                textSize = 12f
                setTextColor(Palette.muted)
            })
            addView(TextView(activity).apply {
                text = value.toString()
                textSize = 22f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
        }
        fun separator(horizontal: Boolean): android.view.View = android.view.View(activity).apply {
            setBackgroundColor(Palette.border)
            layoutParams = if (horizontal) {
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, activity.dp(1))
            } else {
                LinearLayout.LayoutParams(activity.dp(1), activity.dp(64))
            }
        }
        if (columns == 1) {
            values.forEachIndexed { index, (label, value) ->
                summaryContainer.addView(metric(label, value).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        activity.dp(72),
                    )
                })
                if (index < values.lastIndex) summaryContainer.addView(separator(horizontal = true))
            }
        } else {
            summaryContainer.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                values.forEachIndexed { index, (label, value) ->
                    addView(metric(label, value), LinearLayout.LayoutParams(0, activity.dp(72), 1f))
                    if (index < values.lastIndex) addView(separator(horizontal = false))
                }
            })
        }
    }

    private fun campusRooms(): List<Classroom> = classroomRepository
        .campus(preferences.campusID)?.rooms.orEmpty()

    private fun matchingRooms(): List<Classroom> = campusRooms()
        .asSequence()
        .filter { it.building in selectedBuildings }
        .filter { room -> selectedSlots.all(room.availableSlots::contains) }
        .sortedWith(compareBy(Classroom::building, Classroom::room))
        .toList()

    private fun selectedRanges(): String {
        val slots = selectedSlots.sorted()
        if (slots.isEmpty()) return "未选择"
        val ranges = mutableListOf<IntRange>()
        var start = slots.first()
        var end = start
        slots.drop(1).forEach { slot ->
            if (slot == end + 1) {
                end = slot
            } else {
                ranges += start..end
                start = slot
                end = slot
            }
        }
        ranges += start..end
        return ranges.joinToString(" / ") { range ->
            val first = AppMetadata.slots[range.first]
            val last = AppMetadata.slots[range.last]
            val label = if (range.first == range.last) {
                "第 ${first.label} 节"
            } else {
                "第 ${first.label}-${last.label} 节"
            }
            "$label ${first.start}-${last.end}"
        }
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

    private companion object {
        const val ROOM_VIEW_TYPE = 0
        const val MESSAGE_VIEW_TYPE = 1
    }

    private inner class ClassroomResultsAdapter : BaseAdapter() {
        private var presentation = ClassroomResultsPresentation.empty("暂无本地空教室数据")

        fun submit(value: ClassroomResultsPresentation) {
            presentation = value
            notifyDataSetChanged()
        }

        override fun getCount(): Int = presentation.rooms.size +
            if (presentation.message != null) 1 else 0

        override fun getItem(position: Int): Any? = presentation.rooms.getOrNull(position)

        override fun getItemId(position: Int): Long = position.toLong()

        override fun getViewTypeCount(): Int = 2

        override fun getItemViewType(position: Int): Int =
            if (position < presentation.rooms.size) ROOM_VIEW_TYPE else MESSAGE_VIEW_TYPE

        override fun isEnabled(position: Int): Boolean = false

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
            if (getItemViewType(position) == ROOM_VIEW_TYPE) {
                val holder = (convertView?.tag as? ClassroomRowHolder)
                    ?: createClassroomRow(parent).also { it.root.tag = it }
                holder.bind(presentation.rooms[position])
                holder.root
            } else {
                val message = convertView as? TextView ?: TextView(activity).apply {
                    textSize = 13f
                    gravity = Gravity.CENTER
                    setTextColor(Palette.muted)
                    setPadding(activity.dp(20), activity.dp(12), activity.dp(20), activity.dp(20))
                    minHeight = activity.dp(72)
                }
                message.text = presentation.message
                message
            }

        private fun createClassroomRow(parent: ViewGroup): ClassroomRowHolder {
            val root = FrameLayout(parent.context).apply {
                setPadding(activity.dp(20), 0, activity.dp(20), activity.dp(8))
            }
            val card = LinearLayout(parent.context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(activity.dp(12), activity.dp(10), activity.dp(12), activity.dp(10))
                background = roundedBackground(activity, Palette.surface, Palette.border, radius = 4)
            }
            root.addView(
                card,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            val heading = LinearLayout(parent.context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            card.addView(heading)
            val name = TextView(parent.context).apply {
                textSize = 15f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            }
            heading.addView(name, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            val size = TextView(parent.context).apply {
                textSize = 12f
                setTextColor(Palette.muted)
            }
            heading.addView(size)
            val ranges = TextView(parent.context).apply {
                textSize = 12f
                setTextColor(Palette.primaryText)
                setPadding(0, activity.dp(5), 0, 0)
            }
            card.addView(ranges)
            return ClassroomRowHolder(root, name, size, ranges)
        }

        private inner class ClassroomRowHolder(
            val root: FrameLayout,
            private val name: TextView,
            private val size: TextView,
            private val ranges: TextView,
        ) {
            fun bind(room: Classroom) {
                name.text = room.name
                size.text = room.size?.let { "$it 座" } ?: "座位未知"
                ranges.text = selectedRanges()
            }
        }
    }
}

internal data class ClassroomResultsPresentation(
    val rooms: List<Classroom>,
    val message: String?,
) {
    companion object {
        fun empty(message: String) = ClassroomResultsPresentation(emptyList(), message)

        fun from(rooms: List<Classroom>) = ClassroomResultsPresentation(rooms, null)
    }
}
