package com.nemoyu.wheretostudy.nativeapp

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.text.ParsePosition
import java.text.SimpleDateFormat

internal enum class InformationQueryMode(val label: String) {
    SHUTTLE("班车查询"),
    IMPORTANT_EVENTS("重要事件"),
}

internal enum class ImportantEventCategory(val label: String) {
    ALL("全部"),
    COMPETITION("学科竞赛"),
    CONFERENCE("学术会议"),
    JOURNAL_SPECIAL_ISSUE("期刊专题"),
    HACKATHON("黑客松"),
    SUMMER_CAMP("夏令营"),
    PRE_ADMISSION("预推免"),
    SCHOOL_NOTICE("校内通知"),
}

internal class InformationQuerySessionState(
    selectedModeName: String? = null,
) {
    var selectedMode: InformationQueryMode = InformationQueryMode.entries
        .firstOrNull { it.name == selectedModeName }
        ?: InformationQueryMode.SHUTTLE
    var query: String = ""
    var category: ImportantEventCategory = ImportantEventCategory.ALL
    var metadataCategory: String? = null
    var showsEnded: Boolean = false
    var visibleEventCount: Int = INITIAL_EVENT_COUNT

    companion object {
        const val INITIAL_EVENT_COUNT = 30
    }
}

internal object ImportantEventQueryLogic {
    fun filter(
        liveItems: List<PublicDeadlineItem>,
        favorites: List<PublicDeadlineItem>,
        query: String,
        category: ImportantEventCategory,
        metadataCategory: String? = null,
        showsEnded: Boolean,
        nowMillis: Long,
    ): List<PublicDeadlineItem> {
        val unique = linkedMapOf<String, PublicDeadlineItem>()
        liveItems.forEach { item ->
            if (item.source != PublicDeadlineSource.CUSTOM) unique[item.favoriteID] = item
        }
        favorites.forEach { item ->
            if (item.source != PublicDeadlineSource.CUSTOM) unique.putIfAbsent(item.favoriteID, item)
        }
        val normalizedQuery = query.trim().lowercase(Locale.ROOT)
        return unique.values.asSequence()
            .filter { showsEnded || !isEnded(it, nowMillis) }
            .filter { category.matches(it) }
            .filter { metadataCategory == null || metadataCategory in it.categories }
            .filter { item ->
                normalizedQuery.isEmpty() || listOfNotNull(
                    item.name,
                    item.organizer,
                    item.sourceName,
                    item.kind.title,
                    item.kind.wireValue.replace('_', ' '),
                    item.source.title,
                    item.source.wireValue.replace('_', ' '),
                    item.level,
                    item.location,
                    item.description,
                    item.eligibility,
                    item.notes,
                    item.metadataSource?.name,
                    item.metadataSource?.sourceType,
                    item.status,
                    item.region,
                    item.mode,
                    *item.categories.toTypedArray(),
                    *item.tags.toTypedArray(),
                ).joinToString(" ")
                    .replace('_', ' ')
                    .lowercase(Locale.ROOT)
                    .contains(normalizedQuery)
            }
            .sortedWith(compareBy(PublicDeadlineItem::deadline, PublicDeadlineItem::name))
            .toList()
    }

    fun metadataCategories(
        liveItems: List<PublicDeadlineItem>,
        favorites: List<PublicDeadlineItem>,
    ): List<String> = (liveItems + favorites)
        .asSequence()
        .filter { it.source != PublicDeadlineSource.CUSTOM }
        .flatMap { it.categories.asSequence() }
        .distinct()
        .sortedWith { left, right -> left.compareTo(right, ignoreCase = true) }
        .toList()

    fun isEnded(item: PublicDeadlineItem, nowMillis: Long): Boolean =
        item.archived || (deadlineMillis(item.deadline)?.let { it < nowMillis } ?: true)

    private fun deadlineMillis(value: String): Long? {
        val match = Regex(
            "^(\\d{4}-\\d{2}-\\d{2}T(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d)" +
                "(?:\\.(\\d+))?(Z|[+-](?:[01]\\d|2[0-3]):[0-5]\\d)$",
        ).matchEntire(value) ?: return null
        val fraction = match.groupValues[2].take(3).padEnd(3, '0')
        val normalized = "${match.groupValues[1]}.$fraction${match.groupValues[3]}"
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).apply {
            isLenient = false
        }
        val position = ParsePosition(0)
        return formatter.parse(normalized, position)
            ?.takeIf { position.index == normalized.length }
            ?.time
    }

    private fun ImportantEventCategory.matches(item: PublicDeadlineItem): Boolean = when (this) {
        ImportantEventCategory.ALL -> true
        ImportantEventCategory.SCHOOL_NOTICE -> item.source == PublicDeadlineSource.SCHOOL_NOTICE
        ImportantEventCategory.COMPETITION ->
            item.source != PublicDeadlineSource.SCHOOL_NOTICE &&
                item.kind == PublicDeadlineKind.COMPETITION
        ImportantEventCategory.CONFERENCE -> item.kind == PublicDeadlineKind.CONFERENCE
        ImportantEventCategory.JOURNAL_SPECIAL_ISSUE ->
            item.kind == PublicDeadlineKind.JOURNAL_SPECIAL_ISSUE
        ImportantEventCategory.HACKATHON -> item.kind == PublicDeadlineKind.HACKATHON
        ImportantEventCategory.SUMMER_CAMP -> item.kind == PublicDeadlineKind.SUMMER_CAMP
        ImportantEventCategory.PRE_ADMISSION -> item.kind == PublicDeadlineKind.PRE_ADMISSION
    }
}

internal class InformationQueryPage(
    private val activity: MainActivity,
    private val shuttleRepository: ShuttleBusRepository,
    private val dailyInfoRepository: CalendarDailyInfoRepository,
    private val preferences: AppPreferences,
    private val availableWidthDp: Int,
    private val sessionState: InformationQuerySessionState,
) {
    private lateinit var root: LinearLayout
    private lateinit var content: FrameLayout
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val shuttleObserver: () -> Unit = {
        if (::root.isInitialized && root.isAttachedToWindow &&
            sessionState.selectedMode == InformationQueryMode.SHUTTLE
        ) renderMode(animate = false)
    }
    private val deadlineObserver: (String) -> Unit = { key ->
        if (key == IMPORTANT_EVENTS_CHANGE_KEY && ::root.isInitialized &&
            root.isAttachedToWindow &&
            sessionState.selectedMode == InformationQueryMode.IMPORTANT_EVENTS
        ) renderMode(animate = false)
    }

    fun build(): View {
        root = LinearLayout(activity).apply {
            id = R.id.information_query_page
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.background)
            addView(queryHeader())
            addView(modeSelector(), LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(48),
            ).apply {
                marginStart = activity.dp(20)
                marginEnd = activity.dp(20)
                bottomMargin = activity.dp(8)
            })
        }
        content = FrameLayout(activity).apply { id = R.id.information_query_content }
        root.addView(content, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))
        root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                shuttleRepository.addObserver(shuttleObserver)
                dailyInfoRepository.addObserver(root, deadlineObserver)
                shuttleRepository.load()
                dailyInfoRepository.loadImportantEvents()
            }

            override fun onViewDetachedFromWindow(view: View) {
                shuttleRepository.removeObserver(shuttleObserver)
                dailyInfoRepository.removeObserver(root)
            }
        })
        renderMode(animate = false)
        UiText.localizeTree(root)
        return root
    }

    private fun queryHeader(): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(activity.dp(20), activity.dp(16), activity.dp(20), activity.dp(8))
        addView(pageTitle(
            activity,
            "查询",
            "校区班车与重要事件",
            titleSizeSp = if (availableWidthDp < 600) 26f else 34f,
        ).apply { setPadding(0, 0, 0, 0) }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
    }

    private fun modeSelector(): FrameLayout {
        val labels = InformationQueryMode.entries
        val initialIndex = sessionState.selectedMode.ordinal
        val control = FrameLayout(activity).apply {
            id = R.id.information_query_mode_switch
            setPadding(activity.dp(3), activity.dp(3), activity.dp(3), activity.dp(3))
            background = roundedBackground(activity, Palette.surfaceVariant, radius = 10)
        }
        val thumb = View(activity).apply {
            background = roundedBackground(activity, Palette.segmentedSelection, radius = 8)
        }
        control.addView(thumb, FrameLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT).apply {
            marginStart = activity.dp(3)
            topMargin = activity.dp(3)
            bottomMargin = activity.dp(3)
        })
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            labels.forEach { mode ->
                addView(TextView(activity).apply {
                    id = if (mode == InformationQueryMode.SHUTTLE) {
                        R.id.information_query_shuttle_tab
                    } else {
                        R.id.information_query_events_tab
                    }
                    text = mode.label
                    textSize = 14f
                    gravity = Gravity.CENTER
                    setTextColor(Palette.text)
                    setTypeface(typeface, if (mode == sessionState.selectedMode) Typeface.BOLD else Typeface.NORMAL)
                    isClickable = true
                    isFocusable = true
                    setOnClickListener { source ->
                        if (mode == sessionState.selectedMode) return@setOnClickListener
                        activity.performControlHaptic(source)
                        val oldOrdinal = sessionState.selectedMode.ordinal
                        sessionState.selectedMode = mode
                        val tabRow = parent as ViewGroup
                        repeat(tabRow.childCount) { index ->
                            (tabRow.getChildAt(index) as TextView).setTypeface(
                                (tabRow.getChildAt(index) as TextView).typeface,
                                if (index == mode.ordinal) Typeface.BOLD else Typeface.NORMAL,
                            )
                        }
                        moveModeThumb(control, thumb, mode.ordinal, animate = true)
                        renderMode(animate = true, direction = mode.ordinal.compareTo(oldOrdinal))
                    }
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
            }
        }
        control.addView(row, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        ))
        control.post { moveModeThumb(control, thumb, initialIndex, animate = false) }
        return control
    }

    private fun moveModeThumb(control: FrameLayout, thumb: View, index: Int, animate: Boolean) {
        if (control.width <= 0) return
        val inset = activity.dp(3)
        val width = ((control.width - inset * 2) / InformationQueryMode.entries.size)
            .coerceAtLeast(1)
        thumb.layoutParams = (thumb.layoutParams as FrameLayout.LayoutParams).apply {
            this.width = width
        }
        val target = (index * width).toFloat()
        thumb.animate().cancel()
        if (animate) {
            thumb.animate().translationX(target).setDuration(220L)
                .setInterpolator(AccelerateDecelerateInterpolator()).start()
        } else thumb.translationX = target
    }

    private fun renderMode(animate: Boolean, direction: Int = 0) {
        if (!::content.isInitialized) return
        val page = when (sessionState.selectedMode) {
            InformationQueryMode.SHUTTLE -> shuttleContent()
            InformationQueryMode.IMPORTANT_EVENTS -> importantEventsContent()
        }
        UiText.localizeTree(page)
        val old = content.getChildAt(0)
        if (!animate || old == null || direction == 0) {
            content.removeAllViews()
            content.addView(page, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ))
            return
        }
        val distance = content.width.takeIf { it > 0 } ?: activity.dp(availableWidthDp)
        page.translationX = direction * distance * 0.18f
        page.alpha = 0f
        content.addView(page, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        ))
        old.animate().cancel()
        page.animate().cancel()
        old.animate().translationX(-direction * distance * 0.12f).alpha(0f)
            .setDuration(200L).withEndAction {
                if (old.parent === content) content.removeView(old)
            }.start()
        page.animate().translationX(0f).alpha(1f).setDuration(220L)
            .setInterpolator(AccelerateDecelerateInterpolator()).start()
    }

    private fun shuttleContent(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        clipToPadding = false
        isVerticalScrollBarEnabled = false
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(activity.dp(20), activity.dp(8), activity.dp(20), activity.dp(28))
            val snapshot = shuttleRepository.snapshot
            when {
                snapshot != null -> renderShuttleSnapshot(snapshot)
                shuttleRepository.error != null -> addView(retryCard(
                    shuttleRepository.error ?: "班车信息获取失败。",
                ) { shuttleRepository.load(force = true) })
                else -> addView(statusCard("正在获取今日班车与当前时刻表…"))
            }
        })
    }

    private fun LinearLayout.renderShuttleSnapshot(snapshot: ShuttleBusSnapshot) {
        val presentation = ShuttleBusLogic.today(snapshot, Calendar.getInstance(shanghai))
        addView(surface(activity, showsBorder = false).apply {
            id = R.id.information_query_shuttle_status
            addView(sectionTitle(activity, "今日班车状态"))
            addView(TextView(activity).apply {
                text = presentation.status
                textSize = 17f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
            presentation.nextDeparture?.let { value ->
                addView(TextView(activity).apply {
                    text = value
                    textSize = 13f
                    setTextColor(Palette.primaryText)
                    setPadding(0, activity.dp(5), 0, 0)
                })
            }
            if (presentation.isStale) addView(TextView(activity).apply {
                text = "当前显示上一次有效缓存，服务正在恢复。"
                textSize = 12f
                setTextColor(Palette.danger)
                setPadding(0, activity.dp(6), 0, 0)
            })
            addView(TextView(activity).apply {
                text = "数据更新时间：${snapshot.generatedAt.replace('T', ' ').take(16)}"
                textSize = 11f
                setTextColor(Palette.muted)
                setPadding(0, activity.dp(6), 0, 0)
            })
        })
        addView(spacer(activity, 12))
        addView(LinearLayout(activity).apply {
            id = R.id.information_query_shuttle_routes
            orientation = LinearLayout.VERTICAL
            if (presentation.routes.isEmpty()) {
                addView(statusCard("当前没有可安全展示的生效时刻表，请查看学校原通知。"))
            } else {
                presentation.routes.forEach { route -> addView(shuttleRouteCard(route)) }
            }
        })
        if (presentation.stops.isNotEmpty()) {
            addView(spacer(activity, 4))
            addView(surface(activity, showsBorder = false).apply {
                addView(sectionTitle(activity, "候车地点"))
                presentation.stops.forEach { (campus, location) ->
                    addView(TextView(activity).apply {
                        text = "$campus · $location"
                        textSize = 13f
                        setTextColor(Palette.text)
                        setPadding(0, activity.dp(3), 0, activity.dp(3))
                    })
                }
            })
        }
        if (presentation.notes.isNotEmpty()) {
            addView(spacer(activity, 12))
            addView(surface(activity, showsBorder = false).apply {
                addView(sectionTitle(activity, "乘车提示"))
                presentation.notes.forEach { note ->
                    addView(TextView(activity).apply {
                        text = "• $note"
                        UiText.preserveRawText(this)
                        textSize = 12f
                        setTextColor(Palette.muted)
                        setPadding(0, activity.dp(2), 0, activity.dp(2))
                    })
                }
            })
        }
        addView(querySourceFooter(
            "第三方来源：北京邮电大学后勤部公开通知；时刻表由脚本解析，仅供参考",
            presentation.noticeURL ?: snapshot.sourcePage,
        ))
    }

    private fun shuttleRouteCard(route: TodayShuttleRoute): LinearLayout =
        surface(activity, showsBorder = false).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = activity.dp(12) }
            addView(TextView(activity).apply {
                text = "${route.from} → ${route.to}"
                textSize = 16f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(activity).apply {
                text = route.periodLabel
                UiText.preserveRawText(this)
                textSize = 11f
                setTextColor(Palette.muted)
                setPadding(0, activity.dp(3), 0, activity.dp(7))
            })
            if (route.departures.isEmpty()) {
                addView(TextView(activity).apply {
                    text = "今日该方向无班车"
                    textSize = 13f
                    setTextColor(Palette.muted)
                })
            } else {
                route.departures.forEach { departure ->
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(0, activity.dp(4), 0, activity.dp(4))
                        addView(TextView(activity).apply {
                            text = departure.time
                            textSize = 14f
                            setTextColor(Palette.primaryText)
                            setTypeface(typeface, Typeface.BOLD)
                        }, LinearLayout.LayoutParams(activity.dp(64), ViewGroup.LayoutParams.WRAP_CONTENT))
                        addView(TextView(activity).apply {
                            text = "${departure.vehicle} × ${departure.count}"
                            UiText.preserveRawText(this)
                            textSize = 13f
                            setTextColor(Palette.text)
                        })
                    })
                }
            }
        }

    private fun importantEventsContent(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        clipToPadding = false
        isVerticalScrollBarEnabled = false
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(activity.dp(20), activity.dp(8), activity.dp(20), activity.dp(28))
            addView(searchField())
            addView(spacer(activity, 8))
            addView(categoryPicker())
            metadataCategoryPicker()?.let { picker ->
                addView(spacer(activity, 6))
                addView(picker)
            }
            addView(Switch(activity).apply {
                id = R.id.information_query_show_ended
                text = "显示已结束"
                textSize = 13f
                setTextColor(Palette.text)
                isChecked = sessionState.showsEnded
                setOnCheckedChangeListener { button, checked ->
                    activity.performControlHaptic(button)
                    sessionState.showsEnded = checked
                    sessionState.visibleEventCount = InformationQuerySessionState.INITIAL_EVENT_COUNT
                    root.findViewById<LinearLayout?>(R.id.information_query_events_list)
                        ?.let(::renderImportantEventList)
                }
            })
            addView(TextView(activity).apply {
                id = R.id.information_query_result_count
                textSize = 12f
                setTextColor(Palette.muted)
                setPadding(0, activity.dp(4), 0, activity.dp(8))
            })
            val eventList = LinearLayout(activity).apply {
                id = R.id.information_query_events_list
                orientation = LinearLayout.VERTICAL
            }
            addView(eventList)
            renderImportantEventList(eventList)
            addView(querySourceFooter(
                "第三方来源：Contest DDL 与校内竞赛通知公开接口；不包含课程作业",
                CalendarDailyInfoSources.deadlinePrimaryPage,
            ))
        })
    }

    private fun searchField(): EditText = EditText(activity).apply {
        id = R.id.information_query_search
        hint = activity.uiText("搜索名称、主办方或分类")
        setText(sessionState.query)
        textSize = 14f
        setTextColor(Palette.text)
        setHintTextColor(Palette.muted)
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_TEXT
        background = roundedBackground(activity, Palette.surface, Palette.border, radius = 8)
        setPadding(activity.dp(12), 0, activity.dp(12), 0)
        minHeight = activity.dp(42)
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) {
                sessionState.query = value?.toString().orEmpty()
                sessionState.visibleEventCount = InformationQuerySessionState.INITIAL_EVENT_COUNT
                if (::root.isInitialized) {
                    root.findViewById<LinearLayout?>(R.id.information_query_events_list)
                        ?.let(::renderImportantEventList)
                }
            }
            override fun afterTextChanged(value: Editable?) = Unit
        })
    }

    private fun categoryPicker(): HorizontalScrollView = HorizontalScrollView(activity).apply {
        isHorizontalScrollBarEnabled = false
        addView(LinearLayout(activity).apply {
            id = R.id.information_query_category_row
            orientation = LinearLayout.HORIZONTAL
            ImportantEventCategory.entries.forEach { category ->
                addView(TextView(activity).apply {
                    text = category.label
                    textSize = 12f
                    gravity = Gravity.CENTER
                    setPadding(activity.dp(12), 0, activity.dp(12), 0)
                    minHeight = activity.dp(34)
                    isClickable = true
                    isFocusable = true
                    fun bind() {
                        val selected = category == sessionState.category
                        setTextColor(if (selected) Palette.onPrimary else Palette.text)
                        setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
                        background = roundedBackground(
                            activity,
                            if (selected) Palette.primaryFill else Palette.surface,
                            if (selected) Palette.primaryFill else Palette.border,
                            radius = 17,
                        )
                    }
                    bind()
                    setOnClickListener { source ->
                        if (sessionState.category == category) return@setOnClickListener
                        activity.performControlHaptic(source)
                        sessionState.category = category
                        sessionState.visibleEventCount = InformationQuerySessionState.INITIAL_EVENT_COUNT
                        (parent as? ViewGroup)?.let { row ->
                            repeat(row.childCount) { index ->
                                (row.getChildAt(index) as? TextView)?.let { button ->
                                    val item = ImportantEventCategory.entries[index]
                                    val selected = item == sessionState.category
                                    button.setTextColor(if (selected) Palette.onPrimary else Palette.text)
                                    button.setTypeface(button.typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
                                    button.background = roundedBackground(
                                        activity,
                                        if (selected) Palette.primaryFill else Palette.surface,
                                        if (selected) Palette.primaryFill else Palette.border,
                                        radius = 17,
                                    )
                                }
                            }
                        }
                        root.findViewById<LinearLayout?>(R.id.information_query_events_list)
                            ?.let(::renderImportantEventList)
                    }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    activity.dp(34),
                ).apply { marginEnd = activity.dp(6) })
            }
        })
    }

    private fun metadataCategoryPicker(): HorizontalScrollView? {
        val options = ImportantEventQueryLogic.metadataCategories(
            dailyInfoRepository.importantEvents().orEmpty(),
            preferences.favoriteDeadlines,
        )
        if (options.isEmpty()) {
            sessionState.metadataCategory = null
            return null
        }
        if (sessionState.metadataCategory !in options) sessionState.metadataCategory = null
        return HorizontalScrollView(activity).apply {
            isHorizontalScrollBarEnabled = false
            addView(LinearLayout(activity).apply {
                id = R.id.information_query_metadata_category_row
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(TextView(activity).apply {
                    text = "分类"
                    textSize = 12f
                    setTextColor(Palette.muted)
                    setPadding(0, 0, activity.dp(8), 0)
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    activity.dp(34),
                ))
                (listOf<String?>(null) + options).forEach { category ->
                    addView(TextView(activity).apply {
                        text = category ?: "全部分类"
                        if (category != null) UiText.preserveRawText(this)
                        textSize = 12f
                        gravity = Gravity.CENTER
                        setPadding(activity.dp(12), 0, activity.dp(12), 0)
                        minHeight = activity.dp(34)
                        isClickable = true
                        isFocusable = true
                        fun bind() {
                            val selected = category == sessionState.metadataCategory
                            setTextColor(if (selected) Palette.onPrimary else Palette.text)
                            setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
                            background = roundedBackground(
                                activity,
                                if (selected) Palette.primaryFill else Palette.surface,
                                if (selected) Palette.primaryFill else Palette.border,
                                radius = 17,
                            )
                        }
                        bind()
                        setOnClickListener { source ->
                            if (sessionState.metadataCategory == category) return@setOnClickListener
                            activity.performControlHaptic(source)
                            sessionState.metadataCategory = category
                            sessionState.visibleEventCount = InformationQuerySessionState.INITIAL_EVENT_COUNT
                            val row = parent as ViewGroup
                            repeat(row.childCount - 1) { index ->
                                val button = row.getChildAt(index + 1) as TextView
                                val value = (listOf<String?>(null) + options)[index]
                                val selected = value == sessionState.metadataCategory
                                button.setTextColor(if (selected) Palette.onPrimary else Palette.text)
                                button.setTypeface(
                                    button.typeface,
                                    if (selected) Typeface.BOLD else Typeface.NORMAL,
                                )
                                button.background = roundedBackground(
                                    activity,
                                    if (selected) Palette.primaryFill else Palette.surface,
                                    if (selected) Palette.primaryFill else Palette.border,
                                    radius = 17,
                                )
                            }
                            root.findViewById<LinearLayout?>(R.id.information_query_events_list)
                                ?.let(::renderImportantEventList)
                        }
                    }, LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        activity.dp(34),
                    ).apply { marginEnd = activity.dp(6) })
                }
            })
        }
    }

    private fun renderImportantEventList(host: LinearLayout) {
        host.removeAllViews()
        val live = dailyInfoRepository.importantEvents()
        when {
            live != null -> {
                val items = ImportantEventQueryLogic.filter(
                    liveItems = live,
                    favorites = preferences.favoriteDeadlines,
                    query = sessionState.query,
                    category = sessionState.category,
                    metadataCategory = sessionState.metadataCategory,
                    showsEnded = sessionState.showsEnded,
                    nowMillis = Calendar.getInstance(shanghai).timeInMillis,
                )
                (host.parent as? ViewGroup)
                    ?.findViewById<TextView?>(R.id.information_query_result_count)?.text =
                    activity.uiText("${items.size} 条结果 · 按 DDL 时间升序")
                if (items.isEmpty()) {
                    host.addView(statusText("暂无符合条件的重要事件"))
                } else {
                    items.take(sessionState.visibleEventCount).forEach { host.addView(eventCard(it)) }
                    if (items.size > sessionState.visibleEventCount) {
                        host.addView(TextView(activity).apply {
                            text = "加载更多"
                            textSize = 14f
                            gravity = Gravity.CENTER
                            setTextColor(Palette.primaryText)
                            setTypeface(typeface, Typeface.BOLD)
                            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 8)
                            isClickable = true
                            isFocusable = true
                            layoutParams = LinearLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                activity.dp(40),
                            ).apply { bottomMargin = activity.dp(12) }
                            setOnClickListener { source ->
                                activity.performControlHaptic(source)
                                sessionState.visibleEventCount += 30
                                renderImportantEventList(host)
                            }
                        })
                    }
                }
            }
            dailyInfoRepository.importantEventsError() != null -> host.addView(retryCard(
                dailyInfoRepository.importantEventsError() ?: "重要事件获取失败。",
            ) { dailyInfoRepository.loadImportantEvents(force = true) })
            else -> host.addView(statusCard("正在同步公开活动与校内竞赛通知…"))
        }
    }

    private fun eventCard(item: PublicDeadlineItem): LinearLayout =
        surface(activity, showsBorder = false).apply {
            setTag(R.id.favorite_deadline_item_key, item.favoriteID)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = activity.dp(10) }
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(TextView(activity).apply {
                        text = item.name
                        UiText.preserveRawText(this)
                        textSize = 15f
                        setTextColor(Palette.text)
                        setTypeface(typeface, Typeface.BOLD)
                        maxLines = 3
                        ellipsize = TextUtils.TruncateAt.END
                    })
                    addView(TextView(activity).apply {
                        text = listOfNotNull(
                            eventTypeLabel(item),
                            item.metadataSource?.name ?: item.sourceName,
                        ).joinToString(" · ")
                        UiText.preserveRawText(this)
                        textSize = 11f
                        setTextColor(if (item.source == PublicDeadlineSource.SCHOOL_NOTICE) {
                            Palette.schoolNotice
                        } else Palette.publicDeadline)
                        setPadding(0, activity.dp(4), 0, 0)
                    })
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                addView(favoriteButton(item), LinearLayout.LayoutParams(
                    activity.dp(40), activity.dp(40),
                ).apply { marginStart = activity.dp(6) })
            })
            addView(TextView(activity).apply {
                text = item.deadline.replace('T', ' ').take(16)
                textSize = 13f
                setTextColor(Palette.primaryText)
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, activity.dp(7), 0, 0)
            })
            val metadata = buildList {
                item.organizer?.let(::add)
                addAll(item.categories.take(4))
                addAll(item.tags.take(2))
                item.level?.let(::add)
                item.location?.let(::add)
            }.joinToString(" · ")
            if (metadata.isNotEmpty()) addView(TextView(activity).apply {
                text = metadata
                UiText.preserveRawText(this)
                textSize = 11f
                setTextColor(Palette.muted)
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
                setPadding(0, activity.dp(4), 0, 0)
            })
            item.description?.let { value ->
                addView(eventDetailText(value, maximumLines = 2))
            }
            item.eligibility?.let { value ->
                addView(eventDetailText("${activity.uiText("适用对象")}：$value", maximumLines = 2))
            }
            item.notes?.let { value ->
                addView(eventDetailText("${activity.uiText("备注")}：$value", maximumLines = 2))
            }
            if (item.archived) addView(TextView(activity).apply {
                text = "已归档"
                textSize = 11f
                setTextColor(Palette.danger)
                setPadding(0, activity.dp(4), 0, 0)
            })
            (item.officialURL ?: item.metadataSource?.url ?: item.sourceHomepage)?.let { url ->
                isClickable = true
                isFocusable = true
                contentDescription = "${item.name}，${activity.uiText("打开原文")}"
                setOnClickListener { openURL(url) }
            }
        }

    private fun eventDetailText(value: String, maximumLines: Int): TextView = TextView(activity).apply {
        text = value
        UiText.preserveRawText(this)
        textSize = 11f
        setTextColor(Palette.muted)
        maxLines = maximumLines
        ellipsize = TextUtils.TruncateAt.END
        setPadding(0, activity.dp(4), 0, 0)
    }

    private fun favoriteButton(item: PublicDeadlineItem): ImageView = ImageView(activity).apply {
        id = R.id.information_query_event_favorite
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        background = roundedBackground(activity, Color.TRANSPARENT, radius = 8)
        tag = item.favoriteID
        setTag(R.id.favorite_deadline_item_key, item.favoriteID)
        fun bind() {
            val favorite = preferences.isFavorite(item)
            setImageResource(if (favorite) R.drawable.ic_star_filled else R.drawable.ic_star_outline)
            imageTintList = ColorStateList.valueOf(if (favorite) Palette.accent else Palette.muted)
            contentDescription = activity.uiText(if (favorite) "取消收藏" else "收藏日程")
        }
        bind()
        setOnClickListener { source ->
            activity.performControlHaptic(source)
            preferences.setFavorite(item, favorite = !preferences.isFavorite(item))
            bind()
            root.findViewById<LinearLayout?>(R.id.information_query_events_list)?.post {
                root.findViewById<LinearLayout?>(R.id.information_query_events_list)
                    ?.let(::renderImportantEventList)
            }
        }
    }

    private fun eventTypeLabel(item: PublicDeadlineItem): String = activity.uiText(
        if (item.source == PublicDeadlineSource.SCHOOL_NOTICE) {
            "校内竞赛通知"
        } else item.kind.title
    )

    private fun retryCard(message: String, retry: () -> Unit): LinearLayout =
        statusCard("${activity.uiText(message)}\n${activity.uiText("点击重试")}").apply {
            isClickable = true
            isFocusable = true
            setOnClickListener { retry() }
        }

    private fun statusCard(message: String): LinearLayout = surface(activity, showsBorder = false).apply {
        addView(statusText(message))
    }

    private fun statusText(message: String): TextView = TextView(activity).apply {
        text = message
        textSize = 13f
        setTextColor(Palette.muted)
        gravity = Gravity.CENTER
        setPadding(0, activity.dp(18), 0, activity.dp(18))
    }

    private fun querySourceFooter(label: String, url: String): TextView = TextView(activity).apply {
        text = "$label ↗"
        textSize = 11f
        setTextColor(Palette.primaryText)
        setPadding(0, activity.dp(8), 0, activity.dp(8))
        isClickable = true
        isFocusable = true
        setOnClickListener { openURL(url) }
    }

    private fun openURL(url: String) {
        runCatching {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }.onFailure {
            Toast.makeText(activity, activity.uiText("无法打开链接"), Toast.LENGTH_SHORT).show()
        }
    }
}
