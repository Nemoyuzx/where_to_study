package com.nemoyu.wheretostudy.nativeapp

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.TextUtils
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
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
    var weatherExpanded: Boolean = false
        private set
    val selectedSlots: MutableSet<Int> = mutableSetOf()
    val selectedBuildings: MutableSet<String> = mutableSetOf()
    var usePersonalSchedule: Boolean = true
    private var slotSelectionInitialized: Boolean = false

    fun selectCampus(campusID: String) {
        this.campusID = campusID
    }

    fun toggleWeather() {
        weatherExpanded = !weatherExpanded
    }

    fun ensureSlotSelection(allSlots: Iterable<Int>, personalBusySlots: Set<Int>) {
        if (slotSelectionInitialized) return
        selectedSlots += allSlots.filterNot { usePersonalSchedule && it in personalBusySlots }
        slotSelectionInitialized = true
    }
}

class PlannerPage(
    private val activity: MainActivity,
    private val queryState: PlannerQueryState,
    private val scheduleRepository: ScheduleRepository,
    private val classroomRepository: ClassroomRepository,
    private val weatherRepository: WeatherRepository,
    private val preferences: AppPreferences,
    private val availableWidthDp: Int,
    private val usesBottomNavigation: Boolean,
) {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val today = Calendar.getInstance(shanghai)
    private val personalBusySlots = ScheduleLogic.busySlots(scheduleRepository.schedule, today)
    private val selectedSlots: MutableSet<Int> = queryState.selectedSlots
    private val selectedBuildings: MutableSet<String> = queryState.selectedBuildings
    private var usePersonalSchedule: Boolean
        get() = queryState.usePersonalSchedule
        set(value) {
            queryState.usePersonalSchedule = value
        }
    private lateinit var resultsContainer: LinearLayout
    private lateinit var summaryContainer: LinearLayout

    fun build(): ScrollView {
        queryState.ensureSlotSelection(
            AppMetadata.slots.map(SlotMetadata::index),
            personalBusySlots,
        )
        if (preferences.weatherEnabled) {
            weatherRepository.load(queryState.campusID) {
                activity.refreshPlannerIfVisible()
            }
        }
        return ScrollView(activity).apply {
            isFillViewport = true
            clipToPadding = false
            setThemeBackgroundColor { Palette.background }
            isVerticalScrollBarEnabled = true
            scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
            addView(verticalPage(activity).apply {
                if (usesBottomNavigation) {
                    setPadding(
                        paddingLeft, paddingTop, paddingRight,
                        activity.dp(PhoneNavigationLayoutLogic.CONTENT_INSET_DP),
                    )
                }
                val date = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).apply {
                    timeZone = shanghai
                }.format(Date())
                addView(if (availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP) {
                    compactPlannerTitle(date)
                } else {
                    pageTitle(activity, "联动查询", date, R.drawable.ic_section_clock)
                })
                if (preferences.weatherEnabled) addSection(weatherSurface())
                addSection(querySurface())
                addSection(slotSurface())
                addSection(todayCoursesSurface())
                addSection(buildingsSurface())
                addSection(resultsSurface())
                summaryContainer = plannerSurface().apply {
                    id = R.id.planner_summary
                    setPadding(
                        activity.dp(if (isCompact) UiMetrics.surfacePaddingDp else 10),
                        activity.dp(UiMetrics.surfacePaddingDp),
                        activity.dp(if (isCompact) UiMetrics.surfacePaddingDp else 10),
                        activity.dp(UiMetrics.surfacePaddingDp),
                    )
                }
                addView(summaryContainer)
            })
            renderResultsAndSummary()
        }
    }

    private fun LinearLayout.addSection(view: LinearLayout) {
        addView(view)
        addView(spacer(activity, if (isCompact) UiMetrics.phoneSectionSpacingDp else UiMetrics.sectionSpacingDp))
    }

    private val isCompact: Boolean
        get() = availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP

    private fun plannerSurface(): LinearLayout =
        surface(activity, showsBorder = false, compact = isCompact).apply {
            if (isCompact) setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        }

    private fun plannerSectionTitle(title: String, iconResource: Int): TextView =
        sectionTitle(activity, title, iconResource)

    private val controlHeightDp: Int
        get() = if (isCompact) UiMetrics.phoneControlMinHeightDp else UiMetrics.compactControlHeightDp

    private val controlRadiusDp: Int
        get() = if (isCompact) UiMetrics.phoneControlRadiusDp else UiMetrics.controlRadiusDp

    private fun weatherSurface(): LinearLayout = surface(
        activity, showsBorder = !isCompact, compact = isCompact,
    ).apply {
        id = R.id.planner_weather_surface
        setPadding(
            activity.dp(if (isCompact) 12 else UiMetrics.surfacePaddingDp),
            activity.dp(if (isCompact) 10 else 12),
            activity.dp(if (isCompact) 12 else UiMetrics.surfacePaddingDp),
            activity.dp(if (isCompact) 10 else 12),
        )
        val campusID = queryState.campusID
        val weather = weatherRepository.weather(campusID)
        val header = LinearLayout(activity).apply {
            id = R.id.planner_weather_toggle
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = activity.dp(controlHeightDp)
            isClickable = true
            isFocusable = true
            contentDescription = if (queryState.weatherExpanded) {
                "校区天气，已展开，点击折叠"
            } else {
                "校区天气，已折叠，点击展开"
            }
            addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_section_weather)
                bindTheme("imageTintList") { imageTintList = ColorStateList.valueOf(Palette.primaryText) }
                layoutParams = LinearLayout.LayoutParams(activity.dp(22), activity.dp(22)).apply {
                    marginEnd = activity.dp(10)
                }
            })
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(activity).apply {
                    text = "校区天气"
                    textSize = 17f
                    setThemeTextColor { Palette.text }
                    setTypeface(typeface, Typeface.BOLD)
                    includeFontPadding = false
                })
                addView(TextView(activity).apply {
                    text = weather?.let {
                        "${it.campusName} · ${it.district} · ${it.currentWeather} ${it.currentTemperature}°"
                    } ?: "今日与明日"
                    textSize = 12f
                    setThemeTextColor { Palette.muted }
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    setPadding(0, activity.dp(3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_chevron_down)
                bindTheme("imageTintList") { imageTintList = ColorStateList.valueOf(Palette.muted) }
                rotation = if (queryState.weatherExpanded) 180f else 0f
                layoutParams = LinearLayout.LayoutParams(activity.dp(22), activity.dp(22)).apply {
                    marginStart = activity.dp(8)
                }
            })
            setOnClickListener {
                activity.performControlHaptic(it)
                queryState.toggleWeather()
                activity.refreshCurrentPage()
            }
        }
        addView(header, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))

        if (queryState.weatherExpanded) {
            addView(View(activity).apply {
                setThemeBackgroundColor { Palette.border }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    activity.dp(1),
                ).apply {
                    topMargin = activity.dp(10)
                    bottomMargin = activity.dp(10)
                }
            })
            addView(weatherDetails(campusID, weather))
        }
    }

    private fun weatherDetails(campusID: String, weather: CampusWeather?): LinearLayout =
        LinearLayout(activity).apply {
            id = R.id.planner_weather_details
            orientation = LinearLayout.VERTICAL
            when {
                weatherRepository.isLoading(campusID) && weather == null -> {
                    addView(emptyMessage("正在更新今日与明日天气…"))
                }
                weatherRepository.error(campusID) != null && weather == null -> {
                    addView(TextView(activity).apply {
                        text = "${weatherRepository.error(campusID)}，点击重试"
                        textSize = if (isCompact) 12.5f else 14f
                        gravity = Gravity.CENTER
                        setThemeTextColor { Palette.danger }
                        isClickable = true
                        isFocusable = true
                        minHeight = activity.dp(if (isCompact) 48 else 56)
                        background = themedRoundedBackground(
                            activity, { Palette.dangerSurface }, { Palette.dangerBorder },
                            radius = 7)
                        setOnClickListener {
                            activity.performControlHaptic(it)
                            weatherRepository.load(campusID, force = true) {
                                activity.refreshPlannerIfVisible()
                            }
                            activity.refreshCurrentPage()
                        }
                    })
                }
                weather != null -> {
                    addView(LinearLayout(activity).apply {
                        orientation = if (availableWidthDp >= 600) {
                            LinearLayout.HORIZONTAL
                        } else {
                            LinearLayout.VERTICAL
                        }
                        weather.days.forEachIndexed { index, day ->
                            addView(weatherDayCard(day, if (index == 0) "今日" else "明日"),
                                if (orientation == LinearLayout.HORIZONTAL) {
                                    LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                                        if (index > 0) marginStart = activity.dp(8)
                                    }
                                } else {
                                    LinearLayout.LayoutParams(
                                        ViewGroup.LayoutParams.MATCH_PARENT,
                                        ViewGroup.LayoutParams.WRAP_CONTENT,
                                    ).apply {
                                        if (index > 0) topMargin = activity.dp(8)
                                    }
                                },
                            )
                        }
                    })
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(0, activity.dp(8), 0, 0)
                        addView(TextView(activity).apply {
                            text = weather.reportTime
                            UiText.preserveRawText(this)
                            textSize = 11f
                            setThemeTextColor { Palette.muted }
                        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                        addView(TextView(activity).apply {
                            text = "数据：UAPI"
                            textSize = 11f
                            setThemeTextColor { Palette.muted }
                        })
                    })
                }
                else -> addView(emptyMessage("暂无天气数据"))
            }
        }

    private fun weatherDayCard(day: CampusWeatherDay, label: String): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(activity.dp(10), activity.dp(9), activity.dp(10), activity.dp(9))
            background = themedRoundedBackground(
                activity, { if (isCompact) Palette.background else Palette.surfaceVariant },
                { if (isCompact) Color.TRANSPARENT else Palette.border },
                radius = if (isCompact) controlRadiusDp else 7)
            addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_section_weather)
                bindTheme("imageTintList") { imageTintList = ColorStateList.valueOf(Palette.primaryText) }
                layoutParams = LinearLayout.LayoutParams(activity.dp(22), activity.dp(22)).apply {
                    marginEnd = activity.dp(8)
                }
            })
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(activity).apply {
                    text = "${activity.uiText(label)} · ${shortWeatherDate(day.date)}"
                    textSize = 13f
                    setThemeTextColor { Palette.text }
                    setTypeface(typeface, Typeface.BOLD)
                })
                addView(TextView(activity).apply {
                    text = if (day.weatherDay == day.weatherNight) {
                        day.weatherDay
                    } else {
                        "${day.weatherDay}${activity.uiText("转")}${day.weatherNight}"
                    }
                    UiText.preserveRawText(this)
                    textSize = 12f
                    setThemeTextColor { Palette.muted }
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.END
                addView(TextView(activity).apply {
                    text = "${day.temperatureMinimum}° / ${day.temperatureMaximum}°"
                    textSize = 13f
                    setThemeTextColor { Palette.text }
                    setTypeface(typeface, Typeface.BOLD)
                    gravity = Gravity.END
                })
                day.precipitationProbability?.let { probability ->
                    addView(TextView(activity).apply {
                        text = "降水 $probability%"
                        textSize = 11f
                        setThemeTextColor { Palette.muted }
                        gravity = Gravity.END
                    })
                }
            })
        }

    private fun shortWeatherDate(value: String): String =
        value.takeIf { it.length == 10 }?.substring(5)?.replace('-', '/') ?: value

    private fun querySurface(): LinearLayout = plannerSurface().apply {
        id = R.id.planner_query_surface
        addView(plannerSectionTitle(
            "查询条件",
            R.drawable.ic_section_query,
        ).apply {
            setPadding(0, 0, 0, activity.dp(6))
        })
        addView(campusControl())
        addView(spacer(activity, 6))
        addView(fetchButton())
        classroomRepository.cache?.let { cache ->
            addView(TextView(activity).apply {
                text = activity.getString(R.string.classroom_source_format, cache.targetDate)
                textSize = 12f
                setThemeTextColor { Palette.muted }
                setPadding(0, activity.dp(4), 0, 0)
            })
        }
    }

    private fun campusControl(): LinearLayout {
        val row = LinearLayout(activity).apply {
            tag = "planner.campus.control"
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(activity.dp(2), activity.dp(2), activity.dp(2), activity.dp(2))
            background = themedRoundedBackground(
                activity, { Palette.surfaceVariant },
                radius = controlRadiusDp)
            minimumHeight = activity.dp(controlHeightDp)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                if (isCompact) ViewGroup.LayoutParams.WRAP_CONTENT else activity.dp(32),
            )
        }
        val tabs = mutableListOf<Pair<CampusMetadata, TextView>>()
        AppMetadata.campuses.forEachIndexed { index, campus ->
            lateinit var tab: TextView
            tab = fixedTab(activity, campus.name) {}
            if (isCompact) {
                tab.minHeight = activity.dp(controlHeightDp - 4)
                tab.setPadding(activity.dp(6), 0, activity.dp(6), 0)
            }
            tab.setOnClickListener {
                activity.performControlHaptic(it)
                queryState.selectCampus(campus.id)
                selectedBuildings.clear()
                activity.refreshCurrentPage()
            }
            tab.layoutParams = LinearLayout.LayoutParams(
                0,
                if (isCompact) ViewGroup.LayoutParams.WRAP_CONTENT else ViewGroup.LayoutParams.MATCH_PARENT,
                1f,
            ).apply {
                if (index < AppMetadata.campuses.lastIndex) marginEnd = activity.dp(2)
            }
            tabs += campus to tab
            row.addView(tab)
        }
        tabs.forEach { (campus, view) ->
            val selected = campus.id == queryState.campusID
            view.setThemeTextColor { Palette.text }
            view.setTypeface(Typeface.DEFAULT, if (selected) Typeface.BOLD else Typeface.NORMAL)
            view.background = themedRoundedBackground(
                activity, { if (selected) Palette.segmentedSelection else Color.TRANSPARENT },
                radius = controlRadiusDp - 2)
        }
        return row
    }

    private fun fetchButton(): LinearLayout = LinearLayout(activity).apply {
        id = R.id.planner_fetch_button
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        background = themedRoundedBackground(activity, { Palette.primaryFill }, radius = controlRadiusDp)
        isClickable = !classroomRepository.isRefreshing
        isFocusable = true
        isEnabled = !classroomRepository.isRefreshing
        contentDescription = if (classroomRepository.isRefreshing) {
            "正在获取当天空教室"
        } else {
            "获取空教室信息"
        }
        minimumHeight = activity.dp(controlHeightDp)
        if (isCompact) setPadding(activity.dp(12), 0, activity.dp(12), 0)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            if (isCompact) ViewGroup.LayoutParams.WRAP_CONTENT else activity.dp(controlHeightDp),
        )
        val label = TextView(activity).apply {
            text = if (classroomRepository.isRefreshing) {
                "正在获取当天空教室…"
            } else {
                "获取空教室信息"
            }
            textSize = if (isCompact) 15f else 14f
            setThemeTextColor { Palette.onPrimary }
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
            gravity = Gravity.CENTER
        }
        addView(label)
        setOnClickListener {
            activity.performControlHaptic(it)
            label.text = activity.uiText("正在获取当天空教室…")
            contentDescription = activity.uiText("正在获取当天空教室")
            isEnabled = false
            classroomRepository.refresh(force = true) { result ->
                result.onSuccess {
                    Toast.makeText(
                        activity,
                        activity.uiText("当天空教室已更新"),
                        Toast.LENGTH_SHORT,
                    ).show()
                    activity.refreshCurrentPage()
                }.onFailure { error ->
                    label.text = activity.uiText("获取空教室信息")
                    contentDescription = activity.uiText("获取空教室信息")
                    isEnabled = true
                    Toast.makeText(
                        activity,
                        activity.uiText(error.message ?: "当天空教室获取失败"),
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    private fun slotSurface(): LinearLayout = plannerSurface().apply {
        tag = "planner.slot.surface"
        addView(plannerSectionTitle(
            "节次筛选",
            R.drawable.ic_section_clock,
        ))
        val personalToggle = Switch(activity).apply {
            text = "使用个人课表排除已有课程"
            textSize = if (isCompact) 14f else 17f
            setThemeTextColor { Palette.text }
            gravity = Gravity.CENTER_VERTICAL
            switchPadding = activity.dp(12)
            minHeight = activity.dp(controlHeightDp)
            setPadding(0, 0, 0, 0)
            isClickable = true
            isFocusable = true
            isChecked = usePersonalSchedule
            val states = arrayOf(
                intArrayOf(android.R.attr.state_checked),
                intArrayOf(),
            )
            bindTheme("trackTintList") { trackTintList = ColorStateList(
                states,
                intArrayOf(Palette.primaryFill, Palette.surfaceVariant),
            ) }
            bindTheme("thumbTintList") { thumbTintList = ColorStateList(
                states,
                intArrayOf(Palette.onPrimary, Palette.muted),
            ) }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
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
                cell.setThemeTextColor { when {
                        selected -> Palette.onPrimary
                        busy -> Palette.onAccent
                        else -> Palette.text
                    } }
                cell.background = themedRoundedBackground(
                    activity, { when {
                        selected -> Palette.primaryFill
                        busy -> Palette.accent
                        else -> if (isCompact) Palette.background else Palette.surface
                    } }, { if (isCompact) Color.TRANSPARENT else if (selected) Palette.primaryFill else Palette.border },
                    radius = if (isCompact) controlRadiusDp else 6)
                cell.setTypeface(Typeface.DEFAULT, Typeface.NORMAL)
            }
        }

        fun action(label: String, onClick: () -> Unit): TextView = fixedTab(activity, label) {}.apply {
            minHeight = activity.dp(controlHeightDp)
            setOnClickListener {
                activity.performControlHaptic(it)
                onClick()
                refreshCells()
                renderResultsAndSummary()
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                if (isCompact) ViewGroup.LayoutParams.WRAP_CONTENT else activity.dp(controlHeightDp),
            ).apply {
                marginEnd = activity.dp(6)
                bottomMargin = activity.dp(6)
            }
            setPadding(
                activity.dp(if (isCompact) 10 else 12), 0,
                activity.dp(if (isCompact) 10 else 12), 0,
            )
            setThemeTextColor { Palette.primaryText }
            background = themedRoundedBackground(
                activity, { if (isCompact) Palette.selectionSurface else Palette.surface },
                { if (isCompact) Color.TRANSPARENT else Palette.border },
                radius = if (isCompact) controlRadiusDp else 6,
            )
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
        val cellHeightDp = if (isCompact) 46 else 54
        val spacingDp = 4
        return LinearLayout(activity).apply {
            tag = "planner.slot.controls"
            orientation = LinearLayout.VERTICAL
            AppMetadata.slots.chunked(columns).forEach { slots ->
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    slots.forEachIndexed { index, slot ->
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
                                    setSpan(
                                        TypefaceSpan("monospace"),
                                        lineBreak + 1,
                                        value.length,
                                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                                    )
                                }
                            }
                            // The resource is already localized; keep its title/time styling.
                            UiText.preserveRawText(this)
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
                            minHeight = activity.dp(cellHeightDp)
                            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                                if (index < columns - 1) marginEnd = activity.dp(spacingDp)
                                bottomMargin = activity.dp(spacingDp)
                            }
                        }
                        cells[slot.index] = cell
                        addView(cell)
                    }
                    repeat(columns - slots.size) { index ->
                        addView(TextView(activity).apply {
                            layoutParams = LinearLayout.LayoutParams(0, activity.dp(cellHeightDp), 1f).apply {
                                if (slots.size + index < columns - 1) marginEnd = activity.dp(spacingDp)
                            }
                        })
                    }
                })
            }
        }
    }

    private fun todayCoursesSurface(): LinearLayout = plannerSurface().apply {
        addView(plannerSectionTitle("当天课程", R.drawable.ic_nav_calendar))
        val courses = ScheduleLogic.courses(scheduleRepository.schedule, today)
        if (courses.isEmpty()) {
            addView(emptyMessage("暂无本地课程，请在设置中获取/刷新个人课表"))
        } else {
            courses.forEachIndexed { index, course ->
                addView(courseRow(course))
                if (index < courses.lastIndex) {
                    addView(View(activity).apply {
                        setThemeBackgroundColor { Palette.border }
                        layoutParams = LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            activity.dp(1),
                        )
                    })
                }
            }
        }
    }

    private fun buildingsSurface(): LinearLayout = plannerSurface().apply {
        id = R.id.planner_buildings_surface
        addView(plannerSectionTitle("教学楼", R.drawable.ic_section_building))
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
                button.background = themedRoundedBackground(
                    activity, { if (selected) Palette.primaryFill else if (isCompact) Palette.background else Palette.surface },
                    { if (isCompact) Color.TRANSPARENT else if (selected) Palette.primaryFill else Palette.border },
                    radius = if (isCompact) controlRadiusDp else 6)
                icon.bindTheme("imageTintList") { icon.imageTintList = ColorStateList.valueOf(
                    if (selected) Palette.onPrimary else Palette.text,
                ) }
                label.setThemeTextColor { if (selected) Palette.onPrimary else Palette.text }
                label.setTypeface(label.typeface, Typeface.BOLD)
            }
        }
        buildings.chunked(columns).forEach { rowBuildings ->
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                rowBuildings.forEachIndexed { index, building ->
                    lateinit var buttonIcon: ImageView
                    lateinit var buttonLabel: TextView
                    val button = LinearLayout(activity).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER
                        isClickable = true
                        isFocusable = true
                        contentDescription = building
                        setPadding(activity.dp(6), 0, activity.dp(6), 0)
                        minimumHeight = activity.dp(controlHeightDp)
                        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                            if (index < columns - 1) marginEnd = activity.dp(5)
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
                            UiText.preserveRawText(this)
                            textSize = if (isCompact) 14f else 15f
                            includeFontPadding = false
                            gravity = Gravity.CENTER_VERTICAL
                            maxLines = 2
                            setTypeface(typeface, Typeface.BOLD)
                        }
                        addView(buttonLabel, LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                        ))
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
                repeat(columns - rowBuildings.size) { index ->
                    addView(TextView(activity).apply {
                        layoutParams = LinearLayout.LayoutParams(0, activity.dp(controlHeightDp), 1f).apply {
                            if (rowBuildings.size + index < columns - 1) marginEnd = activity.dp(5)
                        }
                    })
                }
            })
        }
        refreshButtons()
    }

    private fun resultsSurface(): LinearLayout = plannerSurface().apply {
        id = R.id.planner_results_surface
        addView(plannerSectionTitle("空教室结果", R.drawable.ic_section_check))
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
        val columns = AdaptiveContentLogic.plannerResultColumns(availableWidthDp)
        val resultRows = presentation.rooms.chunked(columns)
        resultRows.forEachIndexed { rowIndex, rowRooms ->
            if (columns == 1) {
                resultsContainer.addView(classroomRow(rowRooms.single()))
            } else {
                resultsContainer.addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    rowRooms.forEachIndexed { columnIndex, room ->
                        addView(
                            classroomRow(room),
                            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                                .apply {
                                    marginStart = if (columnIndex == 0) 0 else activity.dp(12)
                                    marginEnd = if (columnIndex == 0) activity.dp(12) else 0
                                },
                        )
                        if (columnIndex == 0) {
                            addView(View(activity).apply {
                                setThemeBackgroundColor { Palette.border }
                            }, LinearLayout.LayoutParams(activity.dp(1), ViewGroup.LayoutParams.MATCH_PARENT))
                        }
                    }
                    if (rowRooms.size < columns) {
                        addView(View(activity), LinearLayout.LayoutParams(0, 1, 1f).apply {
                            marginStart = activity.dp(12)
                        })
                    }
                })
            }
            if (rowIndex < resultRows.lastIndex) {
                resultsContainer.addView(View(activity).apply {
                    setThemeBackgroundColor { Palette.border }
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
        summaryContainer.addView(plannerSectionTitle(
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
                setThemeTextColor { Palette.muted }
                maxLines = 2
            })
            addView(TextView(activity).apply {
                text = value.toString()
                textSize = 22f
                gravity = Gravity.CENTER_HORIZONTAL
                setThemeTextColor { Palette.text }
                setTypeface(typeface, Typeface.BOLD)
            })
        }
        fun separator(horizontal: Boolean): android.view.View = android.view.View(activity).apply {
            setThemeBackgroundColor { Palette.border }
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
        setThemeTextColor { Palette.muted }
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(if (isCompact) 56 else 72),
        )
    }

    private fun compactPlannerTitle(date: String): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 0, 0, activity.dp(UiMetrics.phoneSectionSpacingDp))
        addView(TextView(activity).apply {
            text = activity.getString(R.string.planner_eyebrow)
            textSize = 12f
            setThemeTextColor { Palette.muted }
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
        })
        addView(LinearLayout(activity).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, activity.dp(3), 0, 0)
            val titleLabel = TextView(activity).apply {
                tag = "planner.page.title"
                text = "联动查询"
                textSize = UiMetrics.phonePageTitleSizeSp
                setThemeTextColor { Palette.text }
                setTypeface(typeface, Typeface.BOLD)
                includeFontPadding = false
            }
            val dateLabel = TextView(activity).apply {
                text = date
                textSize = 13f
                gravity = Gravity.CENTER_VERTICAL
                setThemeTextColor { Palette.muted }
                includeFontPadding = false
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    R.drawable.ic_section_clock,
                    0,
                    0,
                    0,
                )
                compoundDrawablePadding = activity.dp(5)
                bindTheme("compoundDrawableTintList") { compoundDrawableTintList = ColorStateList.valueOf(Palette.muted) }
            }
            val titleAndDateWidth = titleLabel.paint.measureText(activity.uiText("联动查询")) +
                dateLabel.paint.measureText(date) + activity.dp(36)
            val availableTitleWidth = activity.dp(availableWidthDp - UiMetrics.pagePaddingDp * 2)
            val stacksDate = titleAndDateWidth > availableTitleWidth
            orientation = if (stacksDate) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            addView(titleLabel, if (stacksDate) {
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            } else {
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            })
            addView(dateLabel, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { if (stacksDate) topMargin = activity.dp(6) })
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
                text = course.name
                UiText.preserveRawText(this)
                textSize = if (isCompact) 14f else 15f
                setThemeTextColor { Palette.text }
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(activity).apply {
                text = course.room.ifEmpty { activity.uiText("地点未标注") }
                UiText.preserveRawText(this)
                textSize = 12f
                setThemeTextColor { Palette.muted }
            })
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(activity).apply {
            text = course.timeRange
            textSize = 13f
            setThemeTextColor { Palette.muted }
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
                UiText.preserveRawText(this)
                textSize = if (isCompact) 13.5f else 15f
                setThemeTextColor { Palette.text }
                setTypeface(typeface, Typeface.BOLD)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(TextView(activity).apply {
                text = room.size?.let { "$it 座" } ?: "座位未知"
                textSize = if (isCompact) 11f else 12f
                setThemeTextColor { Palette.muted }
            })
        })
        addView(TextView(activity).apply {
            text = selectedRanges()
            textSize = if (isCompact) 11f else 12f
            setThemeTextColor { Palette.primaryText }
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
