package com.nemoyu.wheretostudy.nativeapp

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class PlannerQueryState(defaultCampusID: String) {
    var campusID: String = defaultCampusID
        private set

    fun selectCampus(campusID: String) {
        this.campusID = campusID
    }
}

class PlannerPage(
    private val activity: MainActivity,
    private val queryState: PlannerQueryState,
    private val scheduleRepository: ScheduleRepository,
    private val classroomRepository: ClassroomRepository,
    private val availableWidthDp: Int,
    private val usesBottomNavigation: Boolean,
) {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val today = Calendar.getInstance(shanghai)
    private val personalBusySlots = ScheduleLogic.busySlots(scheduleRepository.schedule, today)
    private val selectedSlots = AppMetadata.slots.mapNotNullTo(mutableSetOf()) { slot ->
        slot.index.takeUnless(personalBusySlots::contains)
    }
    private val selectedBuildings = mutableSetOf<String>()
    private var usePersonalSchedule = true
    private lateinit var resultsContainer: LinearLayout
    private lateinit var summaryContainer: LinearLayout

    fun build(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        clipToPadding = false
        setBackgroundColor(Palette.background)
        isVerticalScrollBarEnabled = true
        scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
        addView(verticalPage(activity).apply {
            val date = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).apply {
                timeZone = shanghai
            }.format(Date())
            addView(if (availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP) {
                compactPlannerTitle(date)
            } else {
                pageTitle(activity, "联动查询", date, R.drawable.ic_section_clock)
            })
            addSection(querySurface())
            addSection(slotSurface())
            addSection(todayCoursesSurface())
            addSection(buildingsSurface())
            addSection(resultsSurface())
            summaryContainer = surface(activity, showsBorder = false).apply {
                id = R.id.planner_summary
                setPadding(
                    activity.dp(10),
                    activity.dp(UiMetrics.surfacePaddingDp),
                    activity.dp(10),
                    activity.dp(UiMetrics.surfacePaddingDp),
                )
            }
            addView(summaryContainer)
            if (usesBottomNavigation) {
                addView(spacer(activity, 72))
            }
        })
        renderResultsAndSummary()
    }

    private fun LinearLayout.addSection(view: LinearLayout) {
        addView(view)
        addView(spacer(activity, if (isCompact) 10 else UiMetrics.sectionSpacingDp))
    }

    private val isCompact: Boolean
        get() = availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP

    private fun querySurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        id = R.id.planner_query_surface
        setPadding(
            activity.dp(if (isCompact) 12 else UiMetrics.surfacePaddingDp),
            activity.dp(if (isCompact) 12 else UiMetrics.surfacePaddingDp),
            activity.dp(if (isCompact) 12 else UiMetrics.surfacePaddingDp),
            activity.dp(if (isCompact) 12 else UiMetrics.surfacePaddingDp),
        )
        addView(sectionTitle(
            activity,
            "查询条件",
            R.drawable.ic_section_query,
        ).apply {
            textSize = if (isCompact) 15f else 17f
            setPadding(0, 0, 0, activity.dp(6))
        })
        addView(campusControl())
        addView(spacer(activity, 6))
        addView(fetchButton())
        classroomRepository.cache?.let { cache ->
            addView(TextView(activity).apply {
                text = activity.getString(R.string.classroom_source_format, cache.targetDate)
                textSize = 12f
                setTextColor(Palette.muted)
            setPadding(0, activity.dp(4), 0, 0)
            })
        }
    }

    private fun campusControl(): LinearLayout {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(activity.dp(2), activity.dp(2), activity.dp(2), activity.dp(2))
            background = roundedBackground(
                activity,
                Palette.surfaceVariant,
                radius = UiMetrics.controlRadiusDp,
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(32),
            )
        }
        val tabs = mutableListOf<Pair<CampusMetadata, TextView>>()
        AppMetadata.campuses.forEach { campus ->
            lateinit var tab: TextView
            tab = fixedTab(activity, campus.name) {}
            tab.setOnClickListener {
                activity.performControlHaptic(it)
                queryState.selectCampus(campus.id)
                selectedBuildings.clear()
                activity.refreshCurrentPage()
            }
            tab.layoutParams = LinearLayout.LayoutParams(
                0,
                activity.dp(28),
                1f,
            ).apply {
                marginEnd = activity.dp(2)
            }
            tabs += campus to tab
            row.addView(tab)
        }
        tabs.forEach { (campus, view) ->
            val selected = campus.id == queryState.campusID
            view.setTextColor(Palette.text)
            view.setTypeface(view.typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
            view.background = roundedBackground(
                activity,
                if (selected) Palette.segmentedSelection else Color.TRANSPARENT,
                radius = UiMetrics.controlRadiusDp - 2,
            )
        }
        return row
    }

    private fun fetchButton(): LinearLayout = LinearLayout(activity).apply {
        id = R.id.planner_fetch_button
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        background = roundedBackground(activity, Palette.primaryFill, radius = 8)
        isClickable = !classroomRepository.isRefreshing
        isFocusable = true
        isEnabled = !classroomRepository.isRefreshing
        contentDescription = if (classroomRepository.isRefreshing) {
            "正在获取当天空教室"
        } else {
            "获取空教室信息"
        }
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(UiMetrics.compactControlHeightDp),
        )
        val label = TextView(activity).apply {
            text = if (classroomRepository.isRefreshing) {
                "正在获取当天空教室…"
            } else {
                "获取空教室信息"
            }
            textSize = 14f
            setTextColor(Palette.onPrimary)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
        }
        addView(label)
        setOnClickListener {
            activity.performControlHaptic(it)
            label.text = "正在获取当天空教室…"
            contentDescription = "正在获取当天空教室"
            isEnabled = false
            classroomRepository.refresh(force = true) { result ->
                result.onSuccess {
                    Toast.makeText(activity, "当天空教室已更新", Toast.LENGTH_SHORT).show()
                    activity.refreshCurrentPage()
                }.onFailure { error ->
                    label.text = "获取空教室信息"
                    contentDescription = "获取空教室信息"
                    isEnabled = true
                    Toast.makeText(
                        activity,
                        error.message ?: "当天空教室获取失败",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    private fun slotSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        if (isCompact) setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        addView(sectionTitle(
            activity,
            "节次筛选",
            R.drawable.ic_section_clock,
        ).apply { if (isCompact) textSize = 15f })
        val personalToggle = Switch(activity).apply {
            text = "使用个人课表排除已有课程"
            textSize = if (isCompact) 14f else 17f
            setTextColor(Palette.text)
            gravity = Gravity.CENTER_VERTICAL
            isClickable = true
            isFocusable = true
            isChecked = usePersonalSchedule
            val states = arrayOf(
                intArrayOf(android.R.attr.state_checked),
                intArrayOf(),
            )
            trackTintList = ColorStateList(
                states,
                intArrayOf(Palette.primaryFill, Palette.surfaceVariant),
            )
            thumbTintList = ColorStateList(
                states,
                intArrayOf(Palette.onPrimary, Palette.muted),
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(if (isCompact) 32 else UiMetrics.compactControlHeightDp),
            ).apply { bottomMargin = activity.dp(4) }
        }
        addView(personalToggle)
        val actions = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        addView(actions)
        val cells = mutableMapOf<Int, TextView>()

        fun refreshCells() {
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
                        selected -> Palette.primaryFill
                        busy -> Palette.accent
                        else -> Palette.surface
                    },
                    if (selected) Palette.primaryFill else Palette.border,
                    radius = 6,
                )
                cell.setTypeface(Typeface.DEFAULT, Typeface.NORMAL)
            }
        }

        fun action(label: String, onClick: () -> Unit): TextView = fixedTab(activity, label) {}.apply {
            setOnClickListener {
                activity.performControlHaptic(it)
                onClick()
                refreshCells()
                renderResultsAndSummary()
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                activity.dp(if (isCompact) 32 else UiMetrics.compactControlHeightDp),
            ).apply {
                marginEnd = activity.dp(6)
                bottomMargin = activity.dp(6)
            }
            setPadding(activity.dp(if (isCompact) 10 else 12), 0, activity.dp(if (isCompact) 10 else 12), 0)
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
        }

        actions.addView(action("选中空闲") {
            selectedSlots.clear()
            selectedSlots += AppMetadata.slots.map(SlotMetadata::index)
                .filterNot { usePersonalSchedule && it in personalBusySlots }
        })
        actions.addView(action("清空") { selectedSlots.clear() })
        addView(slotControl(cells) { refreshCells() })

        personalToggle.setOnCheckedChangeListener { button, checked ->
            activity.performControlHaptic(button)
            usePersonalSchedule = checked
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
                            val value = activity.getString(
                                R.string.slot_format,
                                slot.label,
                                slot.start,
                                slot.end,
                            )
                            text = SpannableString(value).apply {
                                val lineBreak = value.indexOf('\n').takeIf { it >= 0 }
                                if (lineBreak != null) {
                                    setSpan(
                                        StyleSpan(Typeface.BOLD),
                                        0,
                                        lineBreak,
                                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                                    )
                                    setSpan(
                                        RelativeSizeSpan(0.8f),
                                        lineBreak + 1,
                                        value.length,
                                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                                    )
                                }
                            }
                            textSize = if (isCompact) 13f else 15f
                            gravity = Gravity.CENTER
                            includeFontPadding = false
                            setPadding(activity.dp(2), 0, activity.dp(2), 0)
                            isClickable = true
                            isFocusable = true
                            setOnClickListener {
                                if (usePersonalSchedule && slot.index in personalBusySlots) return@setOnClickListener
                                activity.performControlHaptic(it)
                                if (!selectedSlots.add(slot.index)) selectedSlots.remove(slot.index)
                                refreshCells()
                                renderResultsAndSummary()
                            }
                            minHeight = activity.dp(if (isCompact) 46 else 54)
                            layoutParams = LinearLayout.LayoutParams(0, activity.dp(if (isCompact) 46 else 54), 1f).apply {
                                marginEnd = activity.dp(4)
                                bottomMargin = activity.dp(4)
                            }
                        }
                        cells[slot.index] = cell
                        addView(cell)
                    }
                    repeat(columns - slots.size) {
                        addView(TextView(activity).apply {
                            layoutParams = LinearLayout.LayoutParams(0, activity.dp(if (isCompact) 46 else 54), 1f).apply {
                                marginEnd = activity.dp(4)
                            }
                        })
                    }
                })
            }
        }
    }

    private fun todayCoursesSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        if (isCompact) setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        addView(sectionTitle(activity, "当天课程", R.drawable.ic_nav_calendar).apply {
            if (isCompact) textSize = 15f
        })
        val courses = ScheduleLogic.courses(scheduleRepository.schedule, today)
        if (courses.isEmpty()) {
            addView(emptyMessage("暂无本地课程，请在设置中获取/刷新个人课表"))
        } else {
            courses.forEachIndexed { index, course ->
                addView(courseRow(course))
                if (index < courses.lastIndex) {
                    addView(View(activity).apply {
                        setBackgroundColor(Palette.border)
                        layoutParams = LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            activity.dp(1),
                        )
                    })
                }
            }
        }
    }

    private fun buildingsSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        id = R.id.planner_buildings_surface
        if (isCompact) setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        addView(sectionTitle(activity, "教学楼", R.drawable.ic_section_building).apply {
            if (isCompact) textSize = 15f
        })
        val buildings = AppMetadata.buildings(queryState.campusID).ifEmpty {
            campusRooms().map(Classroom::building).distinct().sorted()
        }
        if (buildings.isEmpty()) {
            addView(emptyMessage("暂无教学楼，请先获取当天空教室"))
            return@apply
        }
        val columns = AdaptiveContentLogic.plannerBuildingColumns(availableWidthDp)
        val buttons = mutableMapOf<String, Triple<LinearLayout, ImageView, TextView>>()
        fun refreshButtons() {
            buttons.forEach { (building, views) ->
                val (button, icon, label) = views
                val selected = building in selectedBuildings
                button.background = roundedBackground(
                    activity,
                    if (selected) Palette.primaryFill else Palette.surface,
                    if (selected) Palette.primaryFill else Palette.border,
                    radius = 6,
                )
                icon.imageTintList = ColorStateList.valueOf(
                    if (selected) Palette.onPrimary else Palette.text,
                )
                label.setTextColor(if (selected) Palette.onPrimary else Palette.text)
                label.setTypeface(label.typeface, Typeface.BOLD)
            }
        }
        buildings.chunked(columns).forEach { rowBuildings ->
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                rowBuildings.forEach { building ->
                    lateinit var buttonIcon: ImageView
                    lateinit var buttonLabel: TextView
                    val button = LinearLayout(activity).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER
                        isClickable = true
                        isFocusable = true
                        contentDescription = building
                        layoutParams = LinearLayout.LayoutParams(0, activity.dp(if (isCompact) 40 else 46), 1f).apply {
                            marginEnd = activity.dp(5)
                            bottomMargin = activity.dp(5)
                        }
                        buttonIcon = ImageView(activity).apply {
                            setImageResource(R.drawable.ic_location_pin)
                            scaleType = ImageView.ScaleType.CENTER_INSIDE
                            setPadding(activity.dp(1), activity.dp(1), activity.dp(1), activity.dp(1))
                        }
                        addView(
                            buttonIcon,
                            LinearLayout.LayoutParams(activity.dp(18), activity.dp(18)).apply {
                                marginEnd = activity.dp(3)
                            },
                        )
                        buttonLabel = TextView(activity).apply {
                            text = building
                            textSize = if (isCompact) 13f else 15f
                            includeFontPadding = false
                            gravity = Gravity.CENTER_VERTICAL
                            maxLines = 1
                            setTypeface(typeface, Typeface.BOLD)
                        }
                        addView(buttonLabel)
                        setOnClickListener {
                            activity.performControlHaptic(it)
                            if (!selectedBuildings.add(building)) selectedBuildings.remove(building)
                            refreshButtons()
                            renderResultsAndSummary()
                        }
                    }
                    buttons[building] = Triple(button, buttonIcon, buttonLabel)
                    addView(button)
                }
                repeat(columns - rowBuildings.size) {
                    addView(TextView(activity).apply {
                        layoutParams = LinearLayout.LayoutParams(0, activity.dp(if (isCompact) 40 else 46), 1f).apply {
                            marginEnd = activity.dp(5)
                        }
                    })
                }
            })
        }
        refreshButtons()
    }

    private fun resultsSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        id = R.id.planner_results_surface
        if (isCompact) setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        addView(sectionTitle(activity, "空教室结果", R.drawable.ic_section_check).apply {
            if (isCompact) textSize = 15f
        })
        resultsContainer = LinearLayout(activity).apply {
            id = R.id.planner_results_content
            orientation = LinearLayout.VERTICAL
        }
        addView(resultsContainer)
    }

    private fun renderResultsAndSummary() {
        if (::resultsContainer.isInitialized) renderResults()
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
        resultsContainer.removeAllViews()
        presentation.message?.let { message ->
            resultsContainer.addView(emptyMessage(message))
            return
        }
        presentation.rooms.forEachIndexed { index, room ->
            resultsContainer.addView(classroomRow(room))
            if (index < presentation.rooms.lastIndex) {
                resultsContainer.addView(View(activity).apply {
                    setBackgroundColor(Palette.border)
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        activity.dp(1),
                    )
                })
            }
        }
    }

    private fun renderSummary() {
        summaryContainer.removeAllViews()
        summaryContainer.addView(sectionTitle(
            activity,
            "查询概览",
            R.drawable.ic_section_summary,
        ))
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
            setPadding(activity.dp(2), activity.dp(10), activity.dp(2), activity.dp(10))
            addView(TextView(activity).apply {
                text = label
                textSize = 11.5f
                gravity = Gravity.CENTER_HORIZONTAL
                setTextColor(Palette.muted)
                maxLines = 1
            })
            addView(TextView(activity).apply {
                text = value.toString()
                textSize = 22f
                gravity = Gravity.CENTER_HORIZONTAL
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
        .campus(queryState.campusID)?.rooms.orEmpty()

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
        textSize = if (isCompact) 12.5f else 14f
        gravity = Gravity.CENTER
        setTextColor(Palette.muted)
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(if (isCompact) 56 else 72),
        )
    }

    private fun compactPlannerTitle(date: String): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 0, 0, activity.dp(12))
        addView(TextView(activity).apply {
            text = activity.getString(R.string.planner_eyebrow)
            textSize = 11f
            setTextColor(Palette.muted)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
        })
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, activity.dp(3), 0, 0)
            addView(TextView(activity).apply {
                text = "联动查询"
                textSize = 28f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
                includeFontPadding = false
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(TextView(activity).apply {
                text = date
                textSize = 13f
                gravity = Gravity.CENTER_VERTICAL
                setTextColor(Palette.muted)
                includeFontPadding = false
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    R.drawable.ic_section_clock,
                    0,
                    0,
                    0,
                )
                compoundDrawablePadding = activity.dp(5)
                compoundDrawableTintList = ColorStateList.valueOf(Palette.muted)
            })
        })
    }

    private fun courseRow(course: Course): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, activity.dp(if (isCompact) 7 else 10), 0, activity.dp(if (isCompact) 7 else 10))
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(activity).apply {
                text = if (course.examWeekNumbers.isEmpty()) course.name else "试  ${course.name}"
                textSize = if (isCompact) 14f else 15f
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

    private fun classroomRow(room: Classroom): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, activity.dp(if (isCompact) 7 else 10), 0, activity.dp(if (isCompact) 7 else 10))
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(activity).apply {
                text = room.name
                textSize = if (isCompact) 13.5f else 15f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(TextView(activity).apply {
                text = room.size?.let { "$it 座" } ?: "座位未知"
                textSize = if (isCompact) 11f else 12f
                setTextColor(Palette.muted)
            })
        })
        addView(TextView(activity).apply {
            text = selectedRanges()
            textSize = if (isCompact) 11f else 12f
            setTextColor(Palette.primaryText)
            setPadding(0, activity.dp(3), 0, 0)
        })
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
