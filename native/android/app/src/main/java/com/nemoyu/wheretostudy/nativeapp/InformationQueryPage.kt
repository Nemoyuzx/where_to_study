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
import androidx.core.graphics.ColorUtils
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
    var eventScrollY: Int = 0

    companion object {
        const val INITIAL_EVENT_COUNT = 20
        const val EVENT_PAGE_SIZE = 20
    }
}

internal data class ImportantEventFilterSelection(
    val category: ImportantEventCategory,
    val metadataCategory: String?,
)

internal object InformationQueryLayoutLogic {
    const val DEFAULT_CONTENT_BOTTOM_PADDING_DP = 28
    const val MODE_SELECTOR_INSET_DP = 3

    fun contentBottomPaddingDp(usesBottomNavigation: Boolean): Int =
        if (usesBottomNavigation) {
            PhoneNavigationLayoutLogic.CONTENT_INSET_DP
        } else {
            DEFAULT_CONTENT_BOTTOM_PADDING_DP
        }

    fun modeThumbWidthPx(controlWidthPx: Int, horizontalPaddingPx: Int, itemCount: Int): Int =
        ((controlWidthPx - horizontalPaddingPx.coerceAtLeast(0) * 2) /
            itemCount.coerceAtLeast(1)).coerceAtLeast(1)

    fun modeThumbTranslationXPx(thumbWidthPx: Int, index: Int, itemCount: Int): Int =
        index.coerceIn(0, itemCount.coerceAtLeast(1) - 1) * thumbWidthPx.coerceAtLeast(1)
}

internal object ShuttleQueryLayoutLogic {
    const val ROUTE_MIN_WIDTH_DP = 280
    const val ROUTE_SPACING_DP = 16
    const val DEPARTURE_MIN_WIDTH_DP = 86
    const val DEPARTURE_SPACING_DP = 8

    fun columns(contentWidth: Int, minimumWidth: Int, spacing: Int, maximumColumns: Int = Int.MAX_VALUE): Int =
        ((contentWidth.coerceAtLeast(0) + spacing.coerceAtLeast(0)) /
            (minimumWidth.coerceAtLeast(1) + spacing.coerceAtLeast(0)))
            .coerceIn(1, maximumColumns.coerceAtLeast(1))

    fun nextDeparture(departures: List<TodayShuttleDeparture>, currentTime: String): String? =
        departures.firstOrNull { it.time > currentTime }?.time

    fun periodText(route: TodayShuttleRoute): String = route.periodStartDate?.let { start ->
        route.periodEndDate?.let { "$start – $it" } ?: "$start 起"
    } ?: route.periodLabel
}

internal object ImportantEventQueryLogic {
    fun nextVisibleCount(currentCount: Int, totalCount: Int): Int =
        (currentCount.coerceAtLeast(0) + InformationQuerySessionState.EVENT_PAGE_SIZE)
            .coerceAtMost(totalCount.coerceAtLeast(0))

    fun filter(
        liveItems: List<PublicDeadlineItem>,
        favorites: List<PublicDeadlineItem>,
        query: String,
        category: ImportantEventCategory,
        metadataCategory: String? = null,
        showsEnded: Boolean,
        nowMillis: Long,
    ): List<PublicDeadlineItem> {
        val normalizedQuery = query.trim().lowercase(Locale.ROOT)
        return mergedCatalog(liveItems, favorites).asSequence()
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

    fun availableTypeFilters(
        liveItems: List<PublicDeadlineItem>,
        favorites: List<PublicDeadlineItem>,
    ): List<ImportantEventCategory> {
        val catalog = mergedCatalog(liveItems, favorites)
        return ImportantEventCategory.entries.filter { category ->
            category == ImportantEventCategory.ALL || catalog.any { item -> category.matches(item) }
        }
    }

    fun metadataCategories(
        liveItems: List<PublicDeadlineItem>,
        favorites: List<PublicDeadlineItem>,
        category: ImportantEventCategory,
        showsEnded: Boolean,
        nowMillis: Long,
    ): List<String> = mergedCatalog(liveItems, favorites)
        .asSequence()
        .filter { item -> category.matches(item) }
        .filter { showsEnded || !isEnded(it, nowMillis) }
        .flatMap { it.categories.asSequence() }
        .distinct()
        .sortedWith { left, right -> left.compareTo(right, ignoreCase = true) }
        .toList()

    fun normalizedSelection(
        liveItems: List<PublicDeadlineItem>,
        favorites: List<PublicDeadlineItem>,
        category: ImportantEventCategory,
        metadataCategory: String?,
        showsEnded: Boolean,
        nowMillis: Long,
    ): ImportantEventFilterSelection {
        val availableTypes = availableTypeFilters(liveItems, favorites)
        val normalizedType = category.takeIf(availableTypes::contains)
            ?: ImportantEventCategory.ALL
        val availableMetadata = metadataCategories(
            liveItems,
            favorites,
            normalizedType,
            showsEnded,
            nowMillis,
        )
        return ImportantEventFilterSelection(
            category = normalizedType,
            metadataCategory = metadataCategory?.takeIf(availableMetadata::contains),
        )
    }

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

    private fun mergedCatalog(
        liveItems: List<PublicDeadlineItem>,
        favorites: List<PublicDeadlineItem>,
    ): Collection<PublicDeadlineItem> {
        val unique = linkedMapOf<String, PublicDeadlineItem>()
        liveItems.forEach { item ->
            if (item.source != PublicDeadlineSource.CUSTOM) unique[item.favoriteID] = item
        }
        favorites.forEach { item ->
            if (item.source != PublicDeadlineSource.CUSTOM) unique.putIfAbsent(item.favoriteID, item)
        }
        return unique.values
    }

    private fun ImportantEventCategory.matches(item: PublicDeadlineItem): Boolean = when (this) {
        ImportantEventCategory.ALL -> true
        ImportantEventCategory.SCHOOL_NOTICE -> item.source == PublicDeadlineSource.SCHOOL_NOTICE
        ImportantEventCategory.COMPETITION ->
            item.source != PublicDeadlineSource.SCHOOL_NOTICE &&
                item.kind == PublicDeadlineKind.COMPETITION
        ImportantEventCategory.CONFERENCE ->
            item.source != PublicDeadlineSource.SCHOOL_NOTICE &&
                item.kind == PublicDeadlineKind.CONFERENCE
        ImportantEventCategory.JOURNAL_SPECIAL_ISSUE ->
            item.source != PublicDeadlineSource.SCHOOL_NOTICE &&
                item.kind == PublicDeadlineKind.JOURNAL_SPECIAL_ISSUE
        ImportantEventCategory.HACKATHON ->
            item.source != PublicDeadlineSource.SCHOOL_NOTICE &&
                item.kind == PublicDeadlineKind.HACKATHON
        ImportantEventCategory.SUMMER_CAMP ->
            item.source != PublicDeadlineSource.SCHOOL_NOTICE &&
                item.kind == PublicDeadlineKind.SUMMER_CAMP
        ImportantEventCategory.PRE_ADMISSION ->
            item.source != PublicDeadlineSource.SCHOOL_NOTICE &&
                item.kind == PublicDeadlineKind.PRE_ADMISSION
    }
}

internal class InformationQueryPage(
    private val activity: MainActivity,
    private val shuttleRepository: ShuttleBusRepository,
    private val dailyInfoRepository: CalendarDailyInfoRepository,
    private val preferences: AppPreferences,
    private val availableWidthDp: Int,
    private val sessionState: InformationQuerySessionState,
    private val usesBottomNavigation: Boolean,
) {
    private lateinit var root: LinearLayout
    private lateinit var content: FrameLayout
    private var pinnedQueryHeader: LinearLayout? = null
    private var isAppendingImportantEventPage = false
    private val isCompact: Boolean
        get() = availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP
    private val pagePaddingDp: Int
        get() = 16
    private val sectionSpacingDp: Int
        get() = if (isCompact) UiMetrics.phoneSectionSpacingDp else 12
    private val controlRadiusDp: Int
        get() = if (isCompact) UiMetrics.phoneControlRadiusDp else UiMetrics.controlRadiusDp
    private val filterHeightDp: Int
        get() = UiMetrics.controlHeightDp

    private fun querySurface(): LinearLayout =
        surface(activity, showsBorder = false, compact = isCompact)

    // Match the reference shuttle Surface at every width: 16 dp insets,
    // an 8 dp corner and a fine outline, independent of phone-only cards.
    private fun shuttleSurface(): LinearLayout = surface(activity, showsBorder = true, compact = false).apply {
        background = themedRoundedBackground(activity, { Palette.surface }, {
            ColorUtils.blendARGB(Palette.border, Palette.surface, 0.55f)
        }, radius = 8)
    }

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
            setThemeBackgroundColor { Palette.background }
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
        setPadding(activity.dp(pagePaddingDp), activity.dp(16), activity.dp(pagePaddingDp), activity.dp(12))
        addView(pageTitle(
            activity,
            "信息查询",
            titleSizeSp = 34f,
        ).apply {
            setPadding(0, 0, 0, 0)
            (getChildAt(0) as TextView).apply { text = text.toString().uppercase(Locale.ROOT) }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
    }

    private fun modeSelector(): FrameLayout {
        val labels = InformationQueryMode.entries
        val control = FrameLayout(activity).apply {
            id = R.id.information_query_mode_switch
            val inset = activity.dp(InformationQueryLayoutLogic.MODE_SELECTOR_INSET_DP)
            setPadding(inset, inset, inset, inset)
            background = themedRoundedBackground(activity, { Palette.surfaceVariant }, radius = 24)
        }
        val thumb = View(activity).apply {
            id = R.id.information_query_mode_thumb
            background = themedRoundedBackground(activity, { Palette.segmentedSelection }, radius = 22)
        }
        control.addView(thumb, FrameLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT))
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
                    textSize = if (isCompact) 15f else 14f
                    includeFontPadding = false
                    gravity = Gravity.CENTER
                    setThemeTextColor { Palette.text }
                    isSelected = mode == sessionState.selectedMode
                    setTypeface(Typeface.DEFAULT, if (isSelected) Typeface.BOLD else Typeface.NORMAL)
                    isClickable = true
                    isFocusable = true
                    setOnClickListener { source ->
                        if (mode == sessionState.selectedMode) return@setOnClickListener
                        activity.performControlHaptic(source)
                        val oldOrdinal = sessionState.selectedMode.ordinal
                        sessionState.selectedMode = mode
                        val tabRow = parent as ViewGroup
                        repeat(tabRow.childCount) { index ->
                            (tabRow.getChildAt(index) as TextView).apply {
                                isSelected = index == mode.ordinal
                                setTypeface(Typeface.DEFAULT, if (isSelected) Typeface.BOLD else Typeface.NORMAL)
                            }
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
        // A selection can arrive before the first layout (including accessibility
        // actions). Initialize from current state, not a stale construction index.
        control.post { moveModeThumb(control, thumb, sessionState.selectedMode.ordinal, animate = false) }
        return control
    }

    private fun modeSelectorHeightPx(): Int {
        if (!isCompact) return activity.dp(UiMetrics.controlHeightDp)
        val inset = activity.dp(InformationQueryLayoutLogic.MODE_SELECTOR_INSET_DP)
        val labelWidth = ((activity.dp(availableWidthDp - pagePaddingDp * 2) - inset * 2) /
            InformationQueryMode.entries.size).coerceAtLeast(1)
        val labelHeight = InformationQueryMode.entries.maxOf { mode ->
            TextView(activity).apply {
                text = activity.uiText(mode.label)
                textSize = 15f
                includeFontPadding = false
                setTypeface(typeface, Typeface.BOLD)
                measure(
                    View.MeasureSpec.makeMeasureSpec(labelWidth, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                )
            }.measuredHeight
        }
        return maxOf(activity.dp(UiMetrics.phoneControlMinHeightDp), labelHeight + inset * 2)
    }

    private fun moveModeThumb(control: FrameLayout, thumb: View, index: Int, animate: Boolean) {
        if (control.width <= 0) return
        val width = InformationQueryLayoutLogic.modeThumbWidthPx(
            controlWidthPx = control.width,
            horizontalPaddingPx = control.paddingStart,
            itemCount = InformationQueryMode.entries.size,
        )
        thumb.layoutParams = (thumb.layoutParams as FrameLayout.LayoutParams).apply {
            this.width = width
        }
        val target = InformationQueryLayoutLogic.modeThumbTranslationXPx(
            thumbWidthPx = width,
            index = index,
            itemCount = InformationQueryMode.entries.size,
        ).toFloat()
        thumb.animate().cancel()
        if (animate) {
            thumb.animate().translationX(target).setDuration(220L)
                .setInterpolator(AccelerateDecelerateInterpolator()).start()
        } else thumb.translationX = target
    }

    private fun renderMode(animate: Boolean, direction: Int = 0) {
        if (!::content.isInitialized) return
        // Shuttle follows one scrolling page like iOS. Keep the established
        // event filter/pagination viewport when users switch to important events.
        pinnedQueryHeader?.let(root::removeView)
        pinnedQueryHeader = if (sessionState.selectedMode == InformationQueryMode.IMPORTANT_EVENTS) {
            queryPageHeader().also { root.addView(it, 0) }
        } else null
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

    private fun queryPageHeader(): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        addView(queryHeader())
        addView(modeSelector(), LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, modeSelectorHeightPx(),
        ).apply {
            marginStart = activity.dp(pagePaddingDp)
            marginEnd = activity.dp(pagePaddingDp)
            bottomMargin = activity.dp(8)
        })
        UiText.localizeTree(this)
    }

    private fun shuttleContent(): ScrollView = ScrollView(activity).apply {
        id = R.id.information_query_shuttle_scroll
        isFillViewport = true
        clipToPadding = false
        isVerticalScrollBarEnabled = false
        addView(object : LinearLayout(activity) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val width = MeasureSpec.getSize(widthMeasureSpec).coerceAtMost(activity.dp(1180))
                super.onMeasure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), heightMeasureSpec)
            }
        }.apply {
            orientation = LinearLayout.VERTICAL
            addView(queryPageHeader())
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(activity.dp(pagePaddingDp), activity.dp(8), activity.dp(pagePaddingDp),
                    activity.dp(InformationQueryLayoutLogic.contentBottomPaddingDp(usesBottomNavigation)))
                val snapshot = shuttleRepository.snapshot
                when {
                    snapshot != null -> renderShuttleSnapshot(snapshot)
                    shuttleRepository.error != null -> addView(retryCard(
                        shuttleRepository.error ?: "班车信息获取失败。",
                    ) { shuttleRepository.load(force = true) })
                    else -> addView(statusCard("正在获取今日班车与当前时刻表…"))
                }
            })
        }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
    }

    private fun LinearLayout.renderShuttleSnapshot(snapshot: ShuttleBusSnapshot) {
        val now = Calendar.getInstance(shanghai)
        val currentTime = "%02d:%02d".format(Locale.ROOT, now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE))
        val presentation = ShuttleBusLogic.today(snapshot, now)
        val departureCount = presentation.routes.sumOf { it.departures.size }
        val statusTitle = when {
            presentation.routes.isEmpty() -> "今日暂无生效班车时刻表"
            departureCount == 0 -> "今日没有计划班次"
            else -> "今日班车按时刻表运行"
        }
        addView(shuttleSurface().apply {
            id = R.id.information_query_shuttle_status
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(shuttleIcon(if (departureCount == 0) R.drawable.ic_nav_calendar else R.drawable.ic_shuttle_bus),
                    LinearLayout.LayoutParams(activity.dp(24), activity.dp(26)).apply { marginEnd = activity.dp(10) })
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(TextView(activity).apply {
                        tag = "information.query.shuttle.status.title"
                        text = statusTitle
                        textSize = 17f
                        setThemeTextColor { Palette.text }
                        setTypeface(typeface, Typeface.BOLD)
                    })
                    addView(TextView(activity).apply {
                        tag = "information.query.shuttle.status.summary"
                        text = "今日共 ${presentation.routes.size} 个方向、$departureCount 个计划班次"
                        textSize = 16f
                        setThemeTextColor { Palette.muted }
                        setPadding(0, activity.dp(4), 0, 0)
                    })
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                addView(shuttleIconButton(R.drawable.ic_refresh, "刷新班车信息").apply {
                    id = R.id.information_query_shuttle_refresh
                    isEnabled = !shuttleRepository.isLoading()
                    alpha = if (isEnabled) 1f else 0.45f
                    setOnClickListener {
                        activity.performControlHaptic(it)
                        shuttleRepository.load(force = true)
                        renderMode(animate = false)
                    }
                }, LinearLayout.LayoutParams(activity.dp(UiMetrics.controlHeightDp), activity.dp(UiMetrics.controlHeightDp)).apply { marginStart = activity.dp(8) })
            })
            if (presentation.isStale) addView(TextView(activity).apply {
                text = "当前展示最近一次成功同步的缓存"
                textSize = 12f
                setThemeTextColor { Palette.accent }
                setPadding(0, activity.dp(10), 0, 0)
            })
            presentation.noticeTitle?.let { title ->
                addView(View(activity).apply { setThemeBackgroundColor { Palette.border } },
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, activity.dp(1)).apply {
                        topMargin = activity.dp(10)
                        bottomMargin = activity.dp(10)
                    })
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.TOP
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(TextView(activity).apply {
                            tag = "information.query.shuttle.notice.title"
                            text = title
                            UiText.preserveRawText(this)
                            textSize = 15f
                            setTypeface(typeface, Typeface.BOLD)
                            setThemeTextColor { Palette.text }
                        })
                        presentation.noticePublishedAt?.let { publishedAt ->
                            addView(TextView(activity).apply {
                                tag = "information.query.shuttle.notice.date"
                                text = "后勤部通知 · $publishedAt"
                                textSize = 12f
                                setThemeTextColor { Palette.muted }
                                setPadding(0, activity.dp(3), 0, 0)
                            })
                        }
                    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                    presentation.noticeURL?.let { url ->
                        addView(shuttleIconButton(R.drawable.ic_shuttle_external, "查看班车通知原文", outlined = false).apply {
                            id = R.id.information_query_shuttle_notice_link
                            setOnClickListener { openURL(url) }
                        }, LinearLayout.LayoutParams(activity.dp(UiMetrics.controlHeightDp), activity.dp(UiMetrics.controlHeightDp)).apply { marginStart = activity.dp(8) })
                    }
                })
            }
            val unassignedStops = presentation.stops.filter { (campus, _) ->
                presentation.routes.none { route -> shuttleStopMatches(campus, route.from) }
            }.map { (campus, location) -> "$campus · $location" }
            (presentation.notes + unassignedStops).forEach { note ->
                addView(TextView(activity).apply {
                    tag = "information.query.shuttle.status.note"
                    text = note
                    UiText.preserveRawText(this)
                    textSize = 12f
                    setThemeTextColor { Palette.muted }
                    setPadding(0, activity.dp(10), 0, 0)
                })
            }
        })
        addView(spacer(activity, ShuttleQueryLayoutLogic.ROUTE_SPACING_DP))
        addView(adaptiveShuttleGrid(
            presentation.routes,
            activity.dp(ShuttleQueryLayoutLogic.ROUTE_MIN_WIDTH_DP),
            activity.dp(ShuttleQueryLayoutLogic.ROUTE_SPACING_DP),
            maximumColumns = 2,
        ) { route -> shuttleRouteCard(route, currentTime, presentation.stops.filter { (campus, _) ->
            shuttleStopMatches(campus, route.from)
        }.map { it.second }) }.apply {
            id = R.id.information_query_shuttle_routes
            if (presentation.routes.isEmpty()) {
                addView(statusCard("当前没有可安全展示的生效时刻表，请查看学校原通知。"))
            }
        })
        addView(TextView(activity).apply {
            text = listOfNotNull(presentation.nextDeparture,
                "数据更新时间：${snapshot.generatedAt.replace('T', ' ').take(16)}").joinToString("\n")
            text = text.split('\n').joinToString("\n") { activity.uiText(it) }
            UiText.preserveRawText(this)
            textSize = 11f
            setThemeTextColor { Palette.muted }
            setPadding(0, activity.dp(12), 0, 0)
        })
        addView(shuttleSourceFooter(snapshot.sourcePage))
    }

    private fun shuttleStopMatches(campus: String, departureCampus: String): Boolean =
        campus.contains(departureCampus) || departureCampus.contains(campus)

    private fun shuttleSourceFooter(url: String): LinearLayout = LinearLayout(activity).apply {
        id = R.id.information_query_shuttle_source_footer
        tag = "information.query.source.footer"
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.TOP
        setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        background = themedRoundedBackground(activity, {
            ColorUtils.blendARGB(Palette.background, Palette.primaryFill, 0.08f)
        }, radius = 10)
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            .apply { topMargin = activity.dp(16) }
        addView(shuttleIcon(R.drawable.ic_settings_info), LinearLayout.LayoutParams(activity.dp(18), activity.dp(20))
            .apply { marginEnd = activity.dp(9) })
        addView(TextView(activity).apply {
            text = "第三方来源：北京邮电大学后勤部公开通知，由 Where To Study 服务解析整理，仅供参考，请以官方原文为准。"
            textSize = 12f
            setThemeTextColor { ColorThemeLogic.readableText(Palette.muted,
                ColorUtils.blendARGB(Palette.background, Palette.primaryFill, 0.08f)) }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(shuttleIconButton(R.drawable.ic_shuttle_external, "查看数据来源", outlined = false).apply {
            setOnClickListener { openURL(url) }
        }, LinearLayout.LayoutParams(activity.dp(UiMetrics.controlHeightDp), activity.dp(UiMetrics.controlHeightDp)).apply { marginStart = activity.dp(4) })
        isClickable = true
        isFocusable = true
        setOnClickListener { openURL(url) }
    }

    private fun shuttleIcon(resource: Int): ImageView = ImageView(activity).apply {
        setImageResource(resource)
        scaleType = ImageView.ScaleType.FIT_CENTER
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        bindTheme("imageTintList") { imageTintList = ColorStateList.valueOf(Palette.primaryText) }
    }

    private fun shuttleIconButton(resource: Int, label: String, outlined: Boolean = true): ImageView =
        shuttleIcon(resource).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            contentDescription = activity.uiText(label)
            isClickable = true
            isFocusable = true
            setPadding(activity.dp(13), activity.dp(13), activity.dp(13), activity.dp(13))
            if (outlined) background = themedRoundedBackground(activity, {
                ColorUtils.blendARGB(Palette.surface, Palette.primaryFill, 0.12f)
            }, radius = 24)
        }

    private fun shuttleRouteCard(route: TodayShuttleRoute, currentTime: String, pickupLocations: List<String>): LinearLayout =
        shuttleSurface().apply {
            tag = "information.query.shuttle.route"
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(shuttleIcon(R.drawable.ic_shuttle_route), LinearLayout.LayoutParams(
                    activity.dp(20), activity.dp(22),
                ).apply { marginEnd = activity.dp(8) })
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(TextView(activity).apply {
                        tag = "information.query.shuttle.route.title"
                        text = "${route.from} → ${route.to}"
                        UiText.preserveRawText(this)
                        textSize = 17f
                        setThemeTextColor { Palette.text }
                        setTypeface(typeface, Typeface.BOLD)
                    })
                    addView(TextView(activity).apply {
                        tag = "information.query.shuttle.route.period"
                        text = ShuttleQueryLayoutLogic.periodText(route)
                        if (route.periodStartDate == null) UiText.preserveRawText(this)
                        textSize = 12f
                        setThemeTextColor { Palette.muted }
                        setPadding(0, activity.dp(3), 0, 0)
                    })
                    pickupLocations.forEach { location ->
                        addView(TextView(activity).apply {
                            tag = "information.query.shuttle.route.pickup"
                            text = "${activity.uiText("候车地点")} · $location"
                            UiText.preserveRawText(this)
                            textSize = 12f
                            setThemeTextColor { Palette.muted }
                            setPadding(0, activity.dp(3), 0, 0)
                        })
                    }
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            })
            addView(spacer(activity, 12))
            if (route.departures.isEmpty()) {
                addView(TextView(activity).apply {
                    text = "今日该方向无班车"
                    textSize = 13f
                    setThemeTextColor { Palette.muted }
                })
            } else {
                addView(shuttleDepartureGrid(route.departures, currentTime))
            }
        }

    private fun shuttleDepartureGrid(departures: List<TodayShuttleDeparture>, currentTime: String): LinearLayout {
        val nextDeparture = ShuttleQueryLayoutLogic.nextDeparture(departures, currentTime)
        val timeMeasure = TextView(activity).apply {
            textSize = 15f
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
            fontFeatureSettings = "tnum"
            letterSpacing = 0f
        }.paint.measureText("00:00").toInt() + activity.dp(21)
        val minimumWidth = maxOf(activity.dp(ShuttleQueryLayoutLogic.DEPARTURE_MIN_WIDTH_DP), timeMeasure)
        return adaptiveShuttleGrid(departures, minimumWidth,
            activity.dp(ShuttleQueryLayoutLogic.DEPARTURE_SPACING_DP)) { departure ->
            val isNext = departure.time == nextDeparture
            LinearLayout(activity).apply {
                tag = "information.query.shuttle.departure"
                isSelected = isNext
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                minimumHeight = activity.dp(44)
                setPadding(activity.dp(4), activity.dp(7), activity.dp(4), activity.dp(7))
                background = themedRoundedBackground(activity, {
                    if (isNext) ColorUtils.blendARGB(Palette.surface, Palette.primaryFill, 0.12f)
                    else Palette.background
                }, radius = 8)
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER
                    addView(TextView(activity).apply {
                        text = departure.time
                        textSize = 15f
                        includeFontPadding = false
                        setThemeTextColor { Palette.text }
                        setTypeface(Typeface.DEFAULT, Typeface.BOLD)
                        fontFeatureSettings = "tnum"
                        letterSpacing = 0f
                        gravity = Gravity.CENTER
                    })
                    if (isNext) addView(View(activity).apply {
                        tag = "information.query.shuttle.next.dot"
                        background = themedRoundedBackground(activity, { Palette.primaryFill }, radius = 5)
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                    }, LinearLayout.LayoutParams(activity.dp(5), activity.dp(5)).apply { marginStart = activity.dp(4) })
                })
                addView(TextView(activity).apply {
                    text = "${departure.vehicle} × ${departure.count}"
                    UiText.preserveRawText(this)
                    textSize = 11f
                    includeFontPadding = false
                    gravity = Gravity.CENTER
                    setThemeTextColor { Palette.muted }
                    setPadding(0, activity.dp(2), 0, 0)
                })
                if (isNext) contentDescription = "${activity.uiText("下一班")} ${departure.time} · ${departure.vehicle} × ${departure.count}"
            }
        }.apply {
            tag = "information.query.shuttle.departures"
        }
    }

    private fun <T> adaptiveShuttleGrid(
        items: List<T>,
        minimumWidthPx: Int,
        spacingPx: Int,
        maximumColumns: Int = Int.MAX_VALUE,
        makeCell: (T) -> View,
    ): LinearLayout = object : LinearLayout(activity) {
        private var renderedColumns = 0

        init {
            orientation = VERTICAL
            rebuild(1)
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val width = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
            if (items.isNotEmpty() && width > 0) {
                rebuild(ShuttleQueryLayoutLogic.columns(width, minimumWidthPx, spacingPx, maximumColumns))
            }
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        }

        private fun rebuild(columns: Int) {
            if (items.isEmpty() || columns == renderedColumns) return
            renderedColumns = columns
            removeAllViews()
            items.chunked(columns).forEachIndexed { rowIndex, rowItems ->
                addView(LinearLayout(activity).apply {
                    orientation = HORIZONTAL
                    gravity = Gravity.TOP
                    repeat(columns) { index ->
                        val cell = rowItems.getOrNull(index)?.let(makeCell) ?: View(activity)
                        // A plain View with WRAP_CONTENT can consume its entire
                        // AT_MOST height in ScrollView. Empty slots reserve width only.
                        val cellHeight = if (index < rowItems.size) ViewGroup.LayoutParams.WRAP_CONTENT else 1
                        addView(cell, LayoutParams(0, cellHeight, 1f).apply {
                            if (index < columns - 1) marginEnd = spacingPx
                        })
                        UiText.localizeTree(cell)
                    }
                }, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    if (rowIndex > 0) topMargin = spacingPx
                })
            }
        }
    }

    private fun importantEventsContent(): ScrollView {
        val liveItems = dailyInfoRepository.importantEvents().orEmpty()
        val favorites = preferences.favoriteDeadlines
        val nowMillis = Calendar.getInstance(shanghai).timeInMillis
        val normalizedSelection = ImportantEventQueryLogic.normalizedSelection(
            liveItems,
            favorites,
            sessionState.category,
            sessionState.metadataCategory,
            sessionState.showsEnded,
            nowMillis,
        )
        sessionState.category = normalizedSelection.category
        sessionState.metadataCategory = normalizedSelection.metadataCategory
        val typeFilters = ImportantEventQueryLogic.availableTypeFilters(liveItems, favorites)
        val metadataCategories = ImportantEventQueryLogic.metadataCategories(
            liveItems,
            favorites,
            sessionState.category,
            sessionState.showsEnded,
            nowMillis,
        )

        val scrollView = ScrollView(activity).apply {
            id = R.id.information_query_events_scroll
            isFillViewport = true
            clipToPadding = false
            isVerticalScrollBarEnabled = false
        }
        lateinit var eventList: LinearLayout
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                activity.dp(pagePaddingDp),
                activity.dp(8),
                activity.dp(pagePaddingDp),
                activity.dp(InformationQueryLayoutLogic.contentBottomPaddingDp(
                    usesBottomNavigation,
                )),
            )
            val filters = if (isCompact) querySurface() else LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
            }
            addView(filters.apply {
                tag = "information.query.events.filters"
                addView(searchField())
                addView(spacer(activity, if (isCompact) 12 else 8))
                addView(categoryPicker(typeFilters))
                metadataCategoryPicker(metadataCategories)?.let { picker ->
                    addView(spacer(activity, if (isCompact) 8 else 6))
                    addView(picker)
                }
                addView(Switch(activity).apply {
                    id = R.id.information_query_show_ended
                    text = "显示已结束"
                    textSize = if (isCompact) 14f else 13f
                    setThemeTextColor { Palette.text }
                    minHeight = activity.dp(if (isCompact) UiMetrics.phoneControlMinHeightDp else 34)
                    switchPadding = activity.dp(12)
                    isChecked = sessionState.showsEnded
                    setOnCheckedChangeListener { button, checked ->
                        activity.performControlHaptic(button)
                        sessionState.showsEnded = checked
                        resetImportantEventPaging()
                        renderMode(animate = false)
                    }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { if (isCompact) topMargin = activity.dp(8) })
                addView(TextView(activity).apply {
                    id = R.id.information_query_result_count
                    textSize = 12f
                    setThemeTextColor { Palette.muted }
                    setPadding(0, activity.dp(4), 0, activity.dp(if (isCompact) 0 else 8))
                })
            })
            if (isCompact) addView(spacer(activity, sectionSpacingDp))
            eventList = LinearLayout(activity).apply {
                id = R.id.information_query_events_list
                orientation = LinearLayout.VERTICAL
            }
            addView(eventList)
            renderImportantEventList(eventList)
            addView(querySourceFooter(
                "第三方来源：Contest DDL 与校内竞赛通知公开接口；不包含课程作业",
                CalendarDailyInfoSources.deadlinePrimaryPage,
            ))
        }
        scrollView.addView(body)
        scrollView.setOnScrollChangeListener { _, _, scrollY, _, _ ->
            sessionState.eventScrollY = scrollY.coerceAtLeast(0)
            val contentHeight = scrollView.getChildAt(0)?.height ?: return@setOnScrollChangeListener
            val remaining = contentHeight - scrollView.height - scrollY
            if (remaining <= activity.dp(240)) {
                appendImportantEventPage(eventList)
            }
        }
        if (sessionState.eventScrollY > 0) {
            scrollView.post {
                if (scrollView.isAttachedToWindow) {
                    scrollView.scrollTo(0, sessionState.eventScrollY)
                }
            }
        }
        return scrollView
    }

    private fun searchField(): EditText = EditText(activity).apply {
        id = R.id.information_query_search
        hint = activity.uiText("搜索名称、主办方或分类")
        setText(sessionState.query)
        // User input is already locale-independent. Prevent the tree-localizer
        // from writing it back and accidentally resetting incremental paging.
        UiText.preserveRawText(this)
        textSize = 14f
        setThemeTextColor { Palette.text }
        bindTheme("hint") { setHintTextColor(Palette.muted) }
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_TEXT
        background = themedRoundedBackground(activity, {
            if (isCompact) Palette.background else if (Palette.selection.preset == "default") Palette.surface else Palette.surfaceVariant
        }, { if (isCompact) Color.TRANSPARENT else Palette.border }, radius = controlRadiusDp)
        setPadding(activity.dp(12), 0, activity.dp(12), 0)
        minHeight = activity.dp(UiMetrics.controlHeightDp)
        if (isCompact) {
            val iconSize = activity.dp(20)
            val icon = activity.getDrawable(R.drawable.ic_nav_query)?.mutate()?.apply {
                setBounds(0, 0, iconSize, iconSize)
            }
            setCompoundDrawablesRelative(icon, null, null, null)
            compoundDrawablePadding = activity.dp(8)
            bindTheme("compoundDrawableTintList") {
                compoundDrawableTintList = ColorStateList.valueOf(Palette.muted)
            }
        }
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) {
                sessionState.query = value?.toString().orEmpty()
                resetImportantEventPaging()
                if (::root.isInitialized) {
                    root.findViewById<LinearLayout?>(R.id.information_query_events_list)
                        ?.let(::renderImportantEventList)
                }
            }
            override fun afterTextChanged(value: Editable?) = Unit
        })
    }

    private fun categoryPicker(
        categories: List<ImportantEventCategory>,
    ): HorizontalScrollView = HorizontalScrollView(activity).apply {
        isHorizontalScrollBarEnabled = false
        addView(LinearLayout(activity).apply {
            id = R.id.information_query_category_row
            orientation = LinearLayout.HORIZONTAL
            categories.forEach { category ->
                addView(TextView(activity).apply {
                    text = category.label
                    textSize = if (isCompact) 13f else 12f
                    includeFontPadding = false
                    gravity = Gravity.CENTER
                    setPadding(activity.dp(12), 0, activity.dp(12), 0)
                    minHeight = activity.dp(filterHeightDp)
                    isClickable = true
                    isFocusable = true
                    fun bind() {
                        val selected = category == sessionState.category
                        setThemeTextColor { if (selected) Palette.onPrimary else Palette.text }
                        setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
                        background = themedRoundedBackground(
                            activity, { if (selected) Palette.primaryFill else if (isCompact) Palette.background else Palette.surface },
                            { if (isCompact) Color.TRANSPARENT else if (selected) Palette.primaryFill else Palette.border },
                            radius = if (isCompact) 24 else 17)
                    }
                    bind()
                    setOnClickListener { source ->
                        if (sessionState.category == category) return@setOnClickListener
                        activity.performControlHaptic(source)
                        sessionState.category = category
                        sessionState.metadataCategory = null
                        resetImportantEventPaging()
                        renderMode(animate = false)
                    }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    activity.dp(filterHeightDp),
                ).apply { marginEnd = activity.dp(if (isCompact) 8 else 6) })
            }
        })
    }

    private fun metadataCategoryPicker(options: List<String>): HorizontalScrollView? {
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
                    gravity = Gravity.CENTER_VERTICAL
                    setThemeTextColor { Palette.muted }
                    setPadding(0, 0, activity.dp(8), 0)
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    activity.dp(filterHeightDp),
                ))
                (listOf<String?>(null) + options).forEach { category ->
                    addView(TextView(activity).apply {
                        text = category ?: "全部分类"
                        if (category != null) UiText.preserveRawText(this)
                        textSize = if (isCompact) 13f else 12f
                        includeFontPadding = false
                        gravity = Gravity.CENTER
                        setPadding(activity.dp(12), 0, activity.dp(12), 0)
                        minHeight = activity.dp(filterHeightDp)
                        isClickable = true
                        isFocusable = true
                        fun bind() {
                            val selected = category == sessionState.metadataCategory
                            setThemeTextColor { if (selected) Palette.onPrimary else Palette.text }
                            setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
                            background = themedRoundedBackground(
                                activity, { if (selected) Palette.primaryFill else if (isCompact) Palette.background else Palette.surface },
                                { if (isCompact) Color.TRANSPARENT else if (selected) Palette.primaryFill else Palette.border },
                                radius = if (isCompact) 24 else 17)
                        }
                        bind()
                        setOnClickListener { source ->
                            if (sessionState.metadataCategory == category) return@setOnClickListener
                            activity.performControlHaptic(source)
                            sessionState.metadataCategory = category
                            resetImportantEventPaging()
                            val row = parent as ViewGroup
                            repeat(row.childCount - 1) { index ->
                                val button = row.getChildAt(index + 1) as TextView
                                val value = (listOf<String?>(null) + options)[index]
                                val selected = value == sessionState.metadataCategory
                                button.setThemeTextColor { if (selected) Palette.onPrimary else Palette.text }
                                button.setTypeface(
                                    button.typeface,
                                    if (selected) Typeface.BOLD else Typeface.NORMAL,
                                )
                                button.background = themedRoundedBackground(
                                    activity, { if (selected) Palette.primaryFill else if (isCompact) Palette.background else Palette.surface },
                                    { if (isCompact) Color.TRANSPARENT else if (selected) Palette.primaryFill else Palette.border },
                                    radius = if (isCompact) 24 else 17)
                            }
                            root.findViewById<LinearLayout?>(R.id.information_query_events_list)
                                ?.let(::renderImportantEventList)
                        }
                    }, LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        activity.dp(filterHeightDp),
                    ).apply { marginEnd = activity.dp(if (isCompact) 8 else 6) })
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
                    items.take(sessionState.visibleEventCount).forEach { item ->
                        host.addView(eventCard(item).also(UiText::localizeTree))
                    }
                }
            }
            dailyInfoRepository.importantEventsError() != null -> host.addView(retryCard(
                dailyInfoRepository.importantEventsError() ?: "重要事件获取失败。",
            ) { dailyInfoRepository.loadImportantEvents(force = true) })
            else -> host.addView(statusCard("正在同步公开活动与校内竞赛通知…"))
        }
    }

    private fun appendImportantEventPage(host: LinearLayout) {
        if (isAppendingImportantEventPage || !host.isAttachedToWindow ||
            sessionState.selectedMode != InformationQueryMode.IMPORTANT_EVENTS
        ) return
        val live = dailyInfoRepository.importantEvents() ?: return
        val items = ImportantEventQueryLogic.filter(
            liveItems = live,
            favorites = preferences.favoriteDeadlines,
            query = sessionState.query,
            category = sessionState.category,
            metadataCategory = sessionState.metadataCategory,
            showsEnded = sessionState.showsEnded,
            nowMillis = Calendar.getInstance(shanghai).timeInMillis,
        )
        val renderedCount = (0 until host.childCount).count { index ->
            host.getChildAt(index).getTag(R.id.favorite_deadline_item_key) != null
        }
        val nextCount = ImportantEventQueryLogic.nextVisibleCount(renderedCount, items.size)
        if (nextCount <= renderedCount) return

        isAppendingImportantEventPage = true
        try {
            sessionState.visibleEventCount = nextCount
            items.subList(renderedCount, nextCount).forEach { item ->
                host.addView(eventCard(item).also(UiText::localizeTree))
            }
        } finally {
            isAppendingImportantEventPage = false
        }
    }

    private fun resetImportantEventPaging() {
        sessionState.visibleEventCount = InformationQuerySessionState.INITIAL_EVENT_COUNT
        sessionState.eventScrollY = 0
        if (::root.isInitialized) {
            root.findViewById<ScrollView?>(R.id.information_query_events_scroll)?.scrollTo(0, 0)
        }
    }

    private fun eventCard(item: PublicDeadlineItem): LinearLayout =
        querySurface().apply {
            setTag(R.id.favorite_deadline_item_key, item.favoriteID)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = activity.dp(if (isCompact) 12 else 10) }
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(TextView(activity).apply {
                        text = item.name
                        UiText.preserveRawText(this)
                        textSize = if (isCompact) 16f else 15f
                        includeFontPadding = false
                        setLineSpacing(activity.dp(2).toFloat(), 1f)
                        setThemeTextColor { Palette.text }
                        setTypeface(typeface, Typeface.BOLD)
                        maxLines = 3
                        ellipsize = TextUtils.TruncateAt.END
                    })
                    if (isCompact) addView(eventDeadline(item))
                    addView(TextView(activity).apply {
                        text = listOfNotNull(
                            eventTypeLabel(item),
                            item.metadataSource?.name ?: item.sourceName,
                        ).joinToString(" · ")
                        UiText.preserveRawText(this)
                        textSize = if (isCompact) 12f else 11f
                        setThemeTextColor { if (isCompact) Palette.muted else DeadlineVisualLogic.color(item) }
                        setPadding(0, activity.dp(4), 0, 0)
                    })
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                addView(favoriteButton(item), LinearLayout.LayoutParams(
                    activity.dp(if (isCompact) UiMetrics.phoneControlMinHeightDp else 40),
                    activity.dp(if (isCompact) UiMetrics.phoneControlMinHeightDp else 40),
                ).apply { marginStart = activity.dp(6) })
            })
            if (!isCompact) addView(eventDeadline(item))
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
                textSize = if (isCompact) 12f else 11f
                setThemeTextColor { Palette.muted }
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
                setThemeTextColor { Palette.danger }
                setPadding(0, activity.dp(4), 0, 0)
            })
            (item.officialURL ?: item.metadataSource?.url ?: item.sourceHomepage)?.let { url ->
                isClickable = true
                isFocusable = true
                contentDescription = "${item.name}，${activity.uiText("打开原文")}"
                setOnClickListener { openURL(url) }
            }
        }

    private fun eventDeadline(item: PublicDeadlineItem): TextView = TextView(activity).apply {
        tag = "information.query.event.deadline"
        text = item.deadline.replace('T', ' ').take(16)
        textSize = if (isCompact) 15f else 13f
        setThemeTextColor { DeadlineVisualLogic.color(item) }
        setTypeface(Typeface.MONOSPACE, Typeface.BOLD)
        setPadding(0, activity.dp(if (isCompact) 6 else 7), 0, 0)
    }

    private fun eventDetailText(value: String, maximumLines: Int): TextView = TextView(activity).apply {
        text = value
        UiText.preserveRawText(this)
        textSize = if (isCompact) 12f else 11f
        setThemeTextColor { Palette.muted }
        maxLines = maximumLines
        ellipsize = TextUtils.TruncateAt.END
        setPadding(0, activity.dp(if (isCompact) 5 else 4), 0, 0)
    }

    private fun favoriteButton(item: PublicDeadlineItem): ImageView = ImageView(activity).apply {
        id = R.id.information_query_event_favorite
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        background = themedRoundedBackground(activity, { Color.TRANSPARENT }, radius = 8)
        tag = item.favoriteID
        setTag(R.id.favorite_deadline_item_key, item.favoriteID)
        fun bind() {
            val favorite = preferences.isFavorite(item)
            setImageResource(if (favorite) R.drawable.ic_star_filled else R.drawable.ic_star_outline)
            bindTheme("imageTintList") { imageTintList = ColorStateList.valueOf(if (favorite) Palette.accent else Palette.muted) }
            contentDescription = activity.uiText(if (favorite) "取消收藏" else "收藏日程")
        }
        bind()
        setOnClickListener { source ->
            activity.performControlHaptic(source)
            preferences.setFavorite(item, favorite = !preferences.isFavorite(item))
            content.post {
                if (::root.isInitialized && root.isAttachedToWindow &&
                    sessionState.selectedMode == InformationQueryMode.IMPORTANT_EVENTS
                ) {
                    renderMode(animate = false)
                }
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

    private fun statusCard(message: String): LinearLayout = querySurface().apply {
        addView(statusText(message))
    }

    private fun statusText(message: String): TextView = TextView(activity).apply {
        text = message
        textSize = 13f
        setThemeTextColor { Palette.muted }
        gravity = Gravity.CENTER
        setPadding(0, activity.dp(18), 0, activity.dp(18))
    }

    private fun querySourceFooter(
        label: String,
        url: String,
        viewID: Int = View.NO_ID,
    ): TextView = TextView(activity).apply {
        id = viewID
        tag = "information.query.source.footer"
        text = "$label ↗"
        textSize = if (isCompact) 12f else 11f
        setThemeTextColor { Palette.primaryText }
        if (isCompact) {
            background = themedRoundedBackground(activity, { Palette.selectionSurface }, radius = controlRadiusDp)
            setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
            setLineSpacing(activity.dp(2).toFloat(), 1f)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = activity.dp(4) }
        } else {
            setPadding(0, activity.dp(8), 0, activity.dp(8))
        }
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
