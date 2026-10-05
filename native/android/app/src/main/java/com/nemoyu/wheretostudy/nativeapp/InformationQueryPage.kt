package com.nemoyu.wheretostudy.nativeapp

import android.animation.ValueAnimator
import android.content.Intent
import android.app.AlertDialog
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
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
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.text.ParsePosition
import java.text.SimpleDateFormat

internal enum class InformationQueryMode(
    val label: String, val compactLabel: String, val compactEnglishLabel: String, val iconResource: Int,
) {
    SHUTTLE("班车查询", "班车", "Shuttle", R.drawable.ic_shuttle_bus),
    IMPORTANT_EVENTS("重要事件", "事件", "Events", R.drawable.ic_settings_notification),
    GRADES("成绩查询", "成绩", "Grades", R.drawable.ic_section_summary),
    EXAMS("考试查询", "考试安排", "Exams", R.drawable.ic_nav_calendar),
    ASSIGNMENTS("课程作业", "作业", "Tasks", R.drawable.ic_section_check),
    COURSES("我的课程", "课程", "Courses", R.drawable.ic_course_book),
    QMPLUS("QMplus", "QMplus", "QMplus", R.drawable.ic_settings_language);

    companion object {
        val queryModes = listOf(SHUTTLE, IMPORTANT_EVENTS)
        val courseModes = listOf(COURSES, GRADES, EXAMS, ASSIGNMENTS)
    }
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
    val modeScrollY = mutableMapOf<InformationQueryMode, Int>()
    var visibleCourseCount = 20
    var visibleQmplusRowCount = 20
    var automaticCourseLoadAttempted = false
    var showsOtherQmCourses = false
    var courseDetailKey: String? = null
    var courseDetailScrollY = 0
    var courseDetailVisibleCount = 20
    var fullTimetableExpanded = false
    val expandedTimetablePeriods = mutableSetOf<String>()
    val expandedTimetableDirections = mutableSetOf<String>()
    val expandedCourseKeys = mutableSetOf<String>()
    val inlineCourseCounts = mutableMapOf<String, Int>()

    fun toggleFullTimetable() { fullTimetableExpanded = !fullTimetableExpanded }

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
    const val PHONE_TITLE_SIZE_SP = 26f
    const val GRADE_RESULT_SPACING_DP = 10

    fun usesIconOnlyTabs(itemWidthPx: Int, widestLabelPx: Float, iconWidthPx: Int,
        iconSpacingPx: Int, horizontalPaddingPx: Int): Boolean =
        widestLabelPx + iconWidthPx + iconSpacingPx + horizontalPaddingPx * 2 > itemWidthPx

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
    // Keep the exact v0.2.9 shuttle action geometry.
    const val ACTION_TOUCH_SIZE_DP = 48
    const val ACTION_ICON_SIZE_DP = 22
    const val ACTION_MINIMUM_INK_DP = 15
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
    private val gradesRepository: AcademicGradesRepository,
    private val scheduleRepository: ScheduleRepository,
    private val holidayRepository: HolidayRepository? = null,
    private val holidaySnapshotForYear: (Int) -> HolidaysSnapshot? =
        { year -> holidayRepository?.authoritativeSnapshot(year) },
    private val modes: List<InformationQueryMode> = InformationQueryMode.queryModes,
    private val pageTitleText: String = "信息查询",
    private val qmplusRepository: QmplusRepository? = null,
) {
    private lateinit var root: LinearLayout
    private lateinit var content: FrameLayout
    private lateinit var scroll: ScrollView
    private var renderedMode: InformationQueryMode? = null
    private var renderRevision = 0
    private var restoringScroll = false
    private var renderedAssignments: Triple<List<AssignmentDeadlineItem>?, Boolean, String?>? = null
    private var renderedCourses: Triple<List<TeachingCloudCourse>?, Boolean, String?>? = null
    private var isAppendingImportantEventPage = false
    private var qmplusRows: List<Pair<QmplusCourse, QmplusActivityItem?>> = emptyList()
    private var courseDetailsDialog: AlertDialog? = null
    private var courseDetailsScroll: ScrollView? = null
    private var pendingCourseDetailRestore: Runnable? = null
    private var detachingCourseDetails = false
    private var restoringCourseDetails = false
    private var detailCloudItems: List<AssignmentDeadlineItem> = emptyList()
    private var detailQmItems: List<QmplusActivityItem> = emptyList()
    private val isCompact: Boolean
        get() = availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP
    private val isPhone: Boolean
        get() = activity.resources.configuration.smallestScreenWidthDp < 600
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
    private var modeTransitionBody: View? = null
    private var pendingModeContentRefresh = false
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
        if (::root.isInitialized && root.isAttachedToWindow &&
            sessionState.selectedMode == InformationQueryMode.ASSIGNMENTS &&
            assignmentState() != renderedAssignments
        ) renderMode(animate = false)
        if (::root.isInitialized && root.isAttachedToWindow && sessionState.selectedMode == InformationQueryMode.COURSES &&
            (courseState() != renderedCourses || assignmentState() != renderedAssignments)) {
            renderMode(animate = false)
            refreshCourseDetails()
        }
    }
    private val gradeObserver: () -> Unit = {
        if (::root.isInitialized && root.isAttachedToWindow && sessionState.selectedMode == InformationQueryMode.GRADES)
            renderMode(animate = false)
    }
    private val holidayObserver: () -> Unit = {
        if (::root.isInitialized && root.isAttachedToWindow &&
            sessionState.selectedMode == InformationQueryMode.SHUTTLE
        ) renderMode(animate = false)
    }
    private val qmplusObserver: () -> Unit = {
        if (::root.isInitialized && root.isAttachedToWindow && sessionState.selectedMode in
            listOf(InformationQueryMode.QMPLUS, InformationQueryMode.COURSES)) {
            renderMode(animate = false)
            refreshCourseDetails()
        }
    }

    fun build(): View {
        require(modes.isNotEmpty())
        if (sessionState.selectedMode !in modes) sessionState.selectedMode = modes.first()
        root = LinearLayout(activity).apply {
            id = R.id.information_query_page
            orientation = LinearLayout.VERTICAL
            setThemeBackgroundColor { Palette.background }
        }
        content = FrameLayout(activity).apply { id = R.id.information_query_content }
        scroll = ScrollView(activity).apply {
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
                addView(content, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                ))
            }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
            setOnScrollChangeListener { _, _, scrollY, _, _ ->
                if (!restoringScroll) renderedMode?.let { mode ->
                    sessionState.modeScrollY[mode] = scrollY.coerceAtLeast(0)
                    if (mode == InformationQueryMode.IMPORTANT_EVENTS) sessionState.eventScrollY = scrollY.coerceAtLeast(0)
                }
                if (renderedMode == InformationQueryMode.IMPORTANT_EVENTS &&
                    (getChildAt(0)?.height ?: 0) - height - scrollY <= activity.dp(240)
                ) content.findViewById<LinearLayout?>(R.id.information_query_events_list)?.let(::appendImportantEventPage)
                if ((getChildAt(0)?.height ?: 0) - height - scrollY <= activity.dp(240)) {
                    if (renderedMode == InformationQueryMode.COURSES)
                        content.findViewById<LinearLayout?>(R.id.course_current_list)?.let { appendCourseRows(it, true) }
                    if (renderedMode == InformationQueryMode.COURSES)
                        content.findViewById<LinearLayout?>(R.id.course_qmplus_list)?.let { appendQmplusCourseRows(it, true) }
                    if (renderedMode == InformationQueryMode.QMPLUS)
                        content.findViewById<LinearLayout?>(R.id.course_qmplus_list)?.let { appendQmplusRows(it, true) }
                }
            }
        }
        root.addView(scroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))
        root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                if (InformationQueryMode.SHUTTLE in modes) {
                    shuttleRepository.addObserver(shuttleObserver)
                    holidayRepository?.addObserver(root, holidayObserver)
                }
                dailyInfoRepository.addObserver(root, deadlineObserver)
                if (activity.allowsAutomaticPageLoads()) {
                    if (InformationQueryMode.SHUTTLE in modes) {
                        shuttleRepository.load()
                        holidayRepository?.ensure(Calendar.getInstance(shanghai).get(Calendar.YEAR))
                        holidayRepository?.ensureAuthoritative(Calendar.getInstance(shanghai).get(Calendar.YEAR))
                    }
                    if (InformationQueryMode.IMPORTANT_EVENTS in modes) dailyInfoRepository.loadImportantEvents()
                    if (sessionState.selectedMode == InformationQueryMode.COURSES && gradesRepository.hasCredentials &&
                        !sessionState.automaticCourseLoadAttempted) {
                        sessionState.automaticCourseLoadAttempted = true
                        dailyInfoRepository.loadCurrentCourses()
                    }
                }
                if (InformationQueryMode.GRADES in modes) {
                    gradesRepository.addObserver(gradeObserver)
                    gradesRepository.reconcile()
                }
                qmplusRepository?.addObserver(root, qmplusObserver)
                sessionState.courseDetailKey?.let { key ->
                    val weakPage = java.lang.ref.WeakReference(this@InformationQueryPage)
                    pendingCourseDetailRestore = Runnable { weakPage.get()?.showCourseDetails(key) }
                    pendingCourseDetailRestore?.let(root::postOnAnimation)
                }
            }

            override fun onViewDetachedFromWindow(view: View) {
                val outgoing = modeTransitionBody
                modeTransitionBody = null
                pendingModeContentRefresh = false
                renderRevision++
                outgoing?.animate()?.cancel()
                shuttleRepository.removeObserver(shuttleObserver)
                holidayRepository?.removeObserver(root)
                dailyInfoRepository.removeObserver(root)
                gradesRepository.removeObserver(gradeObserver)
                qmplusRepository?.removeObserver(root)
                pendingCourseDetailRestore?.let(root::removeCallbacks)
                pendingCourseDetailRestore = null
                detachingCourseDetails = true
                courseDetailsDialog?.dismiss()
                courseDetailsDialog = null; courseDetailsScroll = null
                detailCloudItems = emptyList(); detailQmItems = emptyList(); restoringCourseDetails = false
                detachingCourseDetails = false
            }
        })
        renderMode(animate = false)
        UiText.localizeTree(root)
        return root
    }

    fun scheduleDidRefresh() {
        if (::root.isInitialized && root.isAttachedToWindow &&
            sessionState.selectedMode == InformationQueryMode.EXAMS
        ) renderMode(animate = false)
    }

    private fun queryHeader(): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(activity.dp(pagePaddingDp), activity.dp(16), activity.dp(pagePaddingDp), activity.dp(12))
        addView(pageTitle(
            activity,
            pageTitleText,
            titleSizeSp = if (isPhone) InformationQueryLayoutLogic.PHONE_TITLE_SIZE_SP else 34f,
        ).apply {
            setPadding(0, 0, 0, 0)
            (getChildAt(0) as TextView).apply { text = text.toString().uppercase(Locale.ROOT) }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
    }

    private fun modeSelectorLabel(mode: InformationQueryMode): String =
        if (isPhone || availableWidthDp < 560) {
            if (AppLocale.isEnglish(activity)) mode.compactEnglishLabel else activity.uiText(mode.compactLabel)
        } else activity.uiText(mode.label)

    private fun modeSelector(): FrameLayout {
        val labels = modes
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
                    id = when (mode) {
                        InformationQueryMode.SHUTTLE -> R.id.information_query_shuttle_tab
                        InformationQueryMode.IMPORTANT_EVENTS -> R.id.information_query_events_tab
                        InformationQueryMode.GRADES -> R.id.information_query_grades_tab
                        InformationQueryMode.EXAMS -> R.id.information_query_exams_tab
                        InformationQueryMode.ASSIGNMENTS -> R.id.information_query_assignments_tab
                        InformationQueryMode.COURSES -> R.id.course_current_tab
                        InformationQueryMode.QMPLUS -> R.id.course_qmplus_tab
                    }
                    text = modeSelectorLabel(mode)
                    UiText.preserveRawText(this)
                    contentDescription = activity.uiText(mode.label)
                    textSize = if (isCompact) 15f else 14f
                    includeFontPadding = false
                    isSingleLine = true
                    gravity = Gravity.CENTER
                    setThemeTextColor { Palette.text }
                    bindTheme("queryIconTint") {
                        compoundDrawableTintList = ColorStateList.valueOf(Palette.text)
                    }
                    isSelected = mode == sessionState.selectedMode
                    setTypeface(Typeface.DEFAULT, if (isSelected) Typeface.BOLD else Typeface.NORMAL)
                    isClickable = true
                    isFocusable = true
                    setOnClickListener { source ->
                        if (mode == sessionState.selectedMode) return@setOnClickListener
                        activity.performControlHaptic(source)
                        val oldOrdinal = labels.indexOf(sessionState.selectedMode)
                        if (mode != InformationQueryMode.COURSES) {
                            sessionState.courseDetailKey = null
                            courseDetailsDialog?.dismiss()
                        }
                        sessionState.selectedMode = mode
                        val tabRow = parent as ViewGroup
                        repeat(tabRow.childCount) { index ->
                            (tabRow.getChildAt(index) as TextView).apply {
                                isSelected = index == labels.indexOf(mode)
                                setTypeface(Typeface.DEFAULT, if (isSelected) Typeface.BOLD else Typeface.NORMAL)
                            }
                        }
                        val index = labels.indexOf(mode)
                        moveModeThumb(control, thumb, index, animate = true)
                        renderMode(animate = true, direction = index.compareTo(oldOrdinal))
                    }
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
            }
        }
        control.addView(row, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        ))
        // Keep all five destinations inside the track. Measure bold labels at
        // the user's real font scale; the whole phone control falls back to icons.
        fun updateLabels() {
            val width = InformationQueryLayoutLogic.modeThumbWidthPx(
                control.width, control.paddingStart, labels.size)
            val iconWidth = activity.dp(22)
            val iconSpacing = activity.dp(4)
            val horizontalPadding = activity.dp(8)
            val widestLabel = labels.maxOf { mode ->
                TextView(activity).apply {
                    textSize = if (isCompact) 15f else 14f
                    setTypeface(Typeface.DEFAULT, Typeface.BOLD)
                }.paint.measureText(modeSelectorLabel(mode))
            }
            val iconsOnly = InformationQueryLayoutLogic.usesIconOnlyTabs(
                width, widestLabel, if (isPhone) iconWidth else 0,
                if (isPhone) iconSpacing else 0, horizontalPadding)
            labels.forEachIndexed { index, mode ->
                (row.getChildAt(index) as TextView).apply {
                    val label = if (iconsOnly) "" else modeSelectorLabel(mode)
                    if (text.toString() != label) text = label
                    if (isPhone || iconsOnly) {
                        if (compoundDrawablesRelative[0] == null) {
                            val icon = activity.getDrawable(mode.iconResource)!!.mutate().apply {
                                setBounds(0, 0, iconWidth, iconWidth)
                            }
                            setCompoundDrawablesRelative(icon, null, null, null)
                        }
                        compoundDrawablePadding = if (iconsOnly) 0 else iconSpacing
                    } else if (compoundDrawablesRelative[0] != null) {
                        setCompoundDrawablesRelative(null, null, null, null)
                    }
                    val padding = if (iconsOnly) ((width - iconWidth) / 2).coerceAtLeast(0) else horizontalPadding
                    if (paddingLeft != padding || paddingRight != padding) setPadding(padding, 0, padding, 0)
                }
            }
            moveModeThumb(control, thumb, labels.indexOf(sessionState.selectedMode), animate = false)
        }
        control.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            if (right - left != oldRight - oldLeft) updateLabels()
        }
        // A selection can arrive before the first layout (including accessibility
        // actions). Initialize from current state, not a stale construction index.
        control.post { updateLabels() }
        return FrameLayout(activity).apply {
            tag = "information.query.mode.viewport"
            background = themedRoundedBackground(activity, { Palette.surfaceVariant }, radius = 24)
            clipToOutline = true
            addView(control, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
            ))
        }
    }

    private fun modeSelectorHeightPx(): Int {
        val inset = activity.dp(InformationQueryLayoutLogic.MODE_SELECTOR_INSET_DP)
        val labelWidth = ((activity.dp(availableWidthDp - pagePaddingDp * 2) - inset * 2) /
            modes.size).coerceAtLeast(1)
        val labelHeight = modes.maxOf { mode ->
            TextView(activity).apply {
                text = modeSelectorLabel(mode)
                textSize = if (isCompact) 15f else 14f
                includeFontPadding = false
                isSingleLine = true
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
            itemCount = modes.size,
        )
        thumb.layoutParams = (thumb.layoutParams as FrameLayout.LayoutParams).apply {
            this.width = width
        }
        val target = InformationQueryLayoutLogic.modeThumbTranslationXPx(
            thumbWidthPx = width,
            index = index,
            itemCount = modes.size,
        ).toFloat()
        thumb.animate().cancel()
        if (animate) {
            thumb.animate().translationX(target).setDuration(220L)
                .setInterpolator(AccelerateDecelerateInterpolator()).start()
        } else thumb.translationX = target
    }

    private fun renderMode(animate: Boolean, direction: Int = 0) {
        if (!::content.isInitialized) return
        if (!animate && modeTransitionBody != null) {
            // Repository state has already updated. Delay only the body rebuild
            // so publications cannot cut an incoming page's animation short.
            pendingModeContentRefresh = true
            return
        }
        // The page title, selector and scroll owner survive both selections and
        // repository publications. Only the selected query's body is invalidated.
        val mode = sessionState.selectedMode
        renderedMode?.takeUnless { restoringScroll }?.let { sessionState.modeScrollY[it] = scroll.scrollY }
        val targetScrollY = sessionState.modeScrollY[mode]
            ?: if (mode == InformationQueryMode.IMPORTANT_EVENTS) sessionState.eventScrollY else 0
        val revision = ++renderRevision
        restoringScroll = true
        renderedMode = mode
        scroll.id = when (mode) {
            InformationQueryMode.SHUTTLE -> R.id.information_query_shuttle_scroll
            InformationQueryMode.IMPORTANT_EVENTS -> R.id.information_query_events_scroll
            InformationQueryMode.GRADES -> R.id.information_query_grades_scroll
            InformationQueryMode.EXAMS -> R.id.information_query_exams_scroll
            InformationQueryMode.ASSIGNMENTS -> R.id.information_query_assignments_scroll
            InformationQueryMode.COURSES -> R.id.course_current_scroll
            InformationQueryMode.QMPLUS -> R.id.course_qmplus_scroll
        }
        val page = when (sessionState.selectedMode) {
            InformationQueryMode.SHUTTLE -> shuttleContent()
            InformationQueryMode.IMPORTANT_EVENTS -> importantEventsContent()
            InformationQueryMode.GRADES -> gradesContent()
            InformationQueryMode.EXAMS -> examsContent()
            InformationQueryMode.ASSIGNMENTS -> assignmentsContent()
            InformationQueryMode.COURSES -> coursesContent()
            InformationQueryMode.QMPLUS -> qmplusContent()
        }
        UiText.localizeTree(page)
        // Cancel and remove outgoing bodies immediately: rapid selections must
        // never leave duplicate controls or stale end-actions in the view tree.
        modeTransitionBody = null
        pendingModeContentRefresh = false
        repeat(content.childCount) { content.getChildAt(it).animate().cancel() }
        content.removeAllViews()
        content.addView(page, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
        if (animate && direction != 0 &&
            (Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled())
        ) {
            modeTransitionBody = page
            page.translationX = direction * activity.dp(16).toFloat()
            page.alpha = 0f
            page.animate().translationX(0f).alpha(1f).setDuration(220L)
                .setInterpolator(AccelerateDecelerateInterpolator())
                .withEndAction {
                    if (modeTransitionBody !== page) return@withEndAction
                    modeTransitionBody = null
                    if (root.isAttachedToWindow && pendingModeContentRefresh) {
                        pendingModeContentRefresh = false
                        renderMode(animate = false)
                    }
                }.start()
        }
        scroll.post {
            if (revision == renderRevision) {
                scroll.scrollTo(0, targetScrollY)
                restoringScroll = false
            }
        }
    }

    private fun queryPageHeader(): LinearLayout = LinearLayout(activity).apply {
        tag = "information.query.header"
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

    private fun gradesContent(): LinearLayout = queryBody {
        if (!gradesRepository.hasCredentials) {
            addView(statusCard("请先在设置中保存教务账号和密码，再查询成绩。"))
            addView(gradeAction("前往个人账户", R.drawable.ic_settings_account) {
                activity.findViewById<View>(R.id.navigation_settings)?.performClick()
            })
        } else {
            val snapshot = gradesRepository.snapshot
            addView(querySurface().apply {
                val termID = gradesRepository.selectedTermID
                val title = if (termID == "") activity.uiText("全部学期") else gradesRepository.terms?.terms
                    ?.firstOrNull { it.id == termID }?.let(::gradeTermLabel) ?: activity.uiText("当前学期")
                addView(LinearLayout(activity).apply {
                  orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
                  addView(gradeAction("学期：$title") {
                    val terms = listOf(AcademicTerm("", "全部学期")) + gradesRepository.terms?.terms.orEmpty()
                    AlertDialog.Builder(activity).setTitle(activity.uiText("选择学期"))
                        .setItems(terms.map(::gradeTermLabel).toTypedArray()) { _, index ->
                            gradesRepository.select(terms[index].id)
                        }.show().also(UiText::localizeDialog)
                  }.apply { id = R.id.information_query_grades_term; isEnabled = gradesRepository.terms != null },
                    LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                  addView(gradeAction(if (gradesRepository.isLoading) "正在获取…" else "刷新成绩") {
                      gradesRepository.load(force = true)
                  }.apply { id = R.id.information_query_grades_refresh; isEnabled = !gradesRepository.isLoading },
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                      .apply { marginStart = activity.dp(8) })
                })
                val types = listOf("1" to "最好成绩", "0" to "首次成绩", "" to "全部记录")
                addView(gradeAction(types.first { it.first == gradesRepository.recordType }.second) {
                    AlertDialog.Builder(activity).setTitle(activity.uiText("成绩记录"))
                        .setItems(types.map { activity.uiText(it.second) }.toTypedArray()) { _, index ->
                            gradesRepository.selectedTermID?.let { gradesRepository.select(it, types[index].first) }
                        }.show().also(UiText::localizeDialog)
                }.apply { isEnabled = gradesRepository.selectedTermID != null })
            })
            addView(spacer(activity, 12))
            gradesRepository.error?.let { addView(statusCard(if (snapshot == null) it else
                "成绩刷新失败，正在显示本次使用中已获取的成绩。")) }
            when {
                snapshot != null -> {
                    snapshot.averageGradePoint?.let { average ->
                        addView(compactGradeSurface().apply {
                            tag = "academic.grade.average"
                            addView(TextView(activity).apply {
                                text = activity.uiText("平均学分绩点：$average")
                                UiText.preserveRawText(this)
                                textSize = 15f
                                includeFontPadding = false
                                setThemeTextColor { Palette.muted }
                            })
                        })
                    }
                    if (snapshot.items.isEmpty()) addView(statusCard(if (snapshot.termID.isNotBlank())
                        "该学期暂无已公布成绩，可选择全部学期查看历史成绩。" else "暂无已公布成绩").apply {
                            tag = "academic.grade.empty"
                        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                            if (snapshot.averageGradePoint != null) topMargin = activity.dp(InformationQueryLayoutLogic.GRADE_RESULT_SPACING_DP)
                        })
                    val gradeItems = if (snapshot.termID.isBlank()) snapshot.items.groupBy { it.semesterName.orEmpty() }
                        .toSortedMap(compareByDescending<String> { it }).values.flatten() else snapshot.items
                    var lastTerm: String? = null
                    gradeItems.forEach { grade ->
                        val semester = grade.semesterName.orEmpty()
                        if (snapshot.termID.isBlank() && semester != lastTerm) {
                            lastTerm = semester
                            addView(TextView(activity).apply {
                                text = semester.ifBlank { activity.uiText("学期") }; UiText.preserveRawText(this)
                                textSize = 15f; setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.muted }
                                setPadding(0, activity.dp(16), 0, activity.dp(4))
                            })
                        }
                        addView(compactGradeSurface().apply {
                            tag = "academic.grade.row"
                            addView(TextView(activity).apply {
                                text = grade.name; UiText.preserveRawText(this)
                                textSize = 17f; setTypeface(typeface, Typeface.BOLD)
                                includeFontPadding = false
                                setThemeTextColor { Palette.text }
                            })
                            addView(TextView(activity).apply {
                                val score = grade.score ?: activity.uiText("未公布")
                                val credits = grade.credits ?: activity.uiText("未公布")
                                text = activity.uiText("成绩") + ": $score  ·  " + activity.uiText("学分") + ": $credits"
                                UiText.preserveRawText(this); textSize = 15f
                                includeFontPadding = false
                                setThemeTextColor { Palette.primaryText }
                                setPadding(0, activity.dp(4), 0, 0)
                            })
                            val details = listOfNotNull(grade.semesterName, grade.courseCode, grade.courseAttribute,
                                grade.courseNature, grade.examNature, grade.gradeStatus)
                            if (details.isNotEmpty()) addView(TextView(activity).apply {
                                text = details.joinToString(" · "); UiText.preserveRawText(this)
                                textSize = 13f; setThemeTextColor { Palette.muted }
                                includeFontPadding = false
                                setPadding(0, activity.dp(4), 0, 0)
                            })
                        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                            topMargin = activity.dp(InformationQueryLayoutLogic.GRADE_RESULT_SPACING_DP)
                        })
                    }
                }
                gradesRepository.isLoading -> addView(statusCard("正在获取成绩…"))
                gradesRepository.error == null -> addView(statusCard("点击刷新成绩获取学校已公布的成绩。"))
            }
        }
        addView(TextView(activity).apply {
            text = "成绩来自学校教务系统，仅在本次使用期间保留。"
            textSize = 12f; setThemeTextColor { Palette.muted }
            setPadding(0, activity.dp(16), 0, 0)
        })
    }

    private fun gradeTermLabel(term: AcademicTerm): String = AcademicTermPresentation.label(
        term, gradesRepository.terms?.currentTermID, activity.uiText(term.name), activity.uiText("当前学期"))

    private fun compactGradeSurface(): LinearLayout = querySurface().apply {
        setPadding(paddingLeft, activity.dp(10), paddingRight, activity.dp(10))
    }

    private fun queryBody(build: LinearLayout.() -> Unit): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(activity.dp(pagePaddingDp), activity.dp(8), activity.dp(pagePaddingDp),
            activity.dp(InformationQueryLayoutLogic.contentBottomPaddingDp(usesBottomNavigation)))
        build()
    }

    private fun privateQueryContent(build: LinearLayout.() -> Unit): LinearLayout = queryBody {
        build()
        // Match the iOS query VStack's visible rhythm for every neighboring
        // control, source, message and result, including loading/error states.
        repeat(childCount) { index ->
            val child = getChildAt(index)
            child.layoutParams = (child.layoutParams as LinearLayout.LayoutParams).apply {
                topMargin = if (index == 0) 0 else activity.dp(16)
                bottomMargin = 0
            }
        }
    }

    private fun assignmentsContent(): LinearLayout = privateQueryContent {
        val (items, loading, error) = assignmentState().also { renderedAssignments = it }
        if (!gradesRepository.hasCredentials) {
            addView(statusCard("请先在个人账户中保存教务账号和密码。"))
            addView(gradeAction("前往个人账户", R.drawable.ic_settings_account) {
                activity.findViewById<View>(R.id.navigation_settings)?.performClick()
            })
        }
        addView(gradeAction(if (loading) "正在获取…" else "刷新课程作业") {
            dailyInfoRepository.loadAllAssignments(force = true)
        }.apply { id = R.id.information_query_assignments_refresh; isEnabled = !loading })
        addView(querySourceFooter("教学云平台 · 课程作业", CalendarDailyInfoSources.assignments))
        addView(gradeAction("打开教学云平台", R.drawable.ic_shuttle_external) {
            openURL(CalendarDailyInfoSources.assignments)
        })
        error?.let { message ->
            addView(statusCard(if (items == null) message else "作业刷新失败，正在显示已获取的缓存。\n$message"))
        }
        when {
            items != null && items.isEmpty() -> addView(statusCard("暂无课程作业 DDL"))
            items != null -> items.sortedWith(compareBy(AssignmentDeadlineItem::deadline, AssignmentDeadlineItem::title))
                .forEach { item ->
                    addView(querySurface().apply {
                        tag = "assignment.query.row"
                        addView(eventDetailText(item.courseName ?: "课程未标注", 2))
                        addView(TextView(activity).apply {
                            text = item.title; UiText.preserveRawText(this)
                            textSize = 17f; setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
                        })
                        addView(eventDetailText(item.deadline.replace('T', ' ').take(16), 2))
                        item.status?.let { addView(eventDetailText(it, 2)) }
                    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = activity.dp(10) })
                }
            loading -> addView(statusCard("正在获取课程作业…"))
            error == null -> addView(statusCard("点击刷新课程作业获取 DDL；使用设置中已保存的教学云平台密码。"))
        }
    }

    private fun coursesContent(): LinearLayout = privateQueryContent {
        val (courses, loading, error) = courseState().also { renderedCourses = it }
        renderedAssignments = assignmentState()
        addView(courseSectionHeader(activity.getString(R.string.course_source_teaching_cloud), courses?.size,
            R.id.course_current_refresh, !loading, activity.getString(R.string.current_courses_refresh)) {
                dailyInfoRepository.loadCurrentCourses(force = true)
            })
        if (!gradesRepository.hasCredentials) {
            addView(statusCard("请先在个人账户中保存教务账号和密码。"))
            addView(gradeAction("前往个人账户", R.drawable.ic_settings_account) {
                activity.findViewById<View>(R.id.navigation_settings)?.performClick()
            })
        }
        error?.let { addView(statusCard(it)) }
        when {
            courses != null && courses.isEmpty() -> addView(statusCard(activity.getString(R.string.current_courses_empty)))
            courses != null -> addView(LinearLayout(activity).apply {
                id = R.id.course_current_list; orientation = LinearLayout.VERTICAL
                appendCourseRows(this, false)
            })
            loading -> addView(statusCard(activity.getString(R.string.qmplus_loading)))
            else -> addView(statusCard(activity.getString(R.string.current_courses_hint)))
        }
        val repository = qmplusRepository
        if (repository?.isFeatureEnabled != true) { qmplusRows = emptyList(); return@privateQueryContent }
        val snapshot = repository?.snapshot?.let(QmplusSnapshotCodec::ebuOnly)
        val current = snapshot?.courses?.filter { it.currentTermStatus == "current" }
        val others = snapshot?.courses?.filter { it.currentTermStatus != "current" }.orEmpty()
        addView(courseSectionHeader("QMplus · EBU", current?.size, R.id.course_qmplus_refresh,
            repository != null && !repository.isLoading && !repository.isClearingSession && repository.connection == null,
            if (repository?.manualContinuationRequired == true) activity.uiText("手动继续") else activity.getString(R.string.qmplus_connect_sync)) { activity.connectQmplus() })
        repository?.error?.let { addView(statusCard(activity.uiText(it))) }
        if (snapshot == null) addView(statusCard(activity.getString(
            if (repository?.isLoading == true) R.string.qmplus_loading else R.string.qmplus_not_connected)))
        else {
            if (snapshot.partial) addView(statusCard(activity.getString(R.string.qmplus_partial)))
            val visible = current.orEmpty() + if (sessionState.showsOtherQmCourses) others else emptyList()
            qmplusRows = visible.map { it to null }
            if (visible.isEmpty()) addView(statusCard(activity.getString(R.string.qmplus_no_courses)))
            addView(LinearLayout(activity).apply {
                id = R.id.course_qmplus_list; orientation = LinearLayout.VERTICAL
                appendQmplusCourseRows(this, false)
            })
            if (others.isNotEmpty()) addView(gradeAction(activity.getString(
                if (sessionState.showsOtherQmCourses) R.string.qmplus_hide_other_courses else R.string.qmplus_show_other_courses, others.size)) {
                sessionState.showsOtherQmCourses = !sessionState.showsOtherQmCourses
                renderMode(animate = false)
            })
        }
    }

    private fun courseSectionHeader(title: String, count: Int?, refreshID: Int, enabled: Boolean,
        refreshLabel: String, refresh: () -> Unit): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        addView(LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(activity).apply {
                text = title; UiText.preserveRawText(this); textSize = 17f
                includeFontPadding = false; setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
            })
            count?.let { addView(eventDetailText(activity.getString(R.string.course_directory_count, it), 1)) }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(ImageView(activity).apply {
            id = refreshID; setImageResource(R.drawable.ic_refresh); scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(activity.dp(7), activity.dp(7), activity.dp(7), activity.dp(7))
            background = themedRoundedBackground(activity, { Palette.surfaceVariant }, radius = 8)
            bindTheme("courseRefreshTint") { imageTintList = ColorStateList.valueOf(Palette.primaryText) }
            contentDescription = refreshLabel; isEnabled = enabled; isClickable = true; isFocusable = true
            setOnClickListener { if (root.isAttachedToWindow) { activity.performControlHaptic(it); refresh() } }
        }, LinearLayout.LayoutParams(activity.dp(UiMetrics.controlHeightDp), activity.dp(UiMetrics.controlHeightDp))
            .apply { marginStart = activity.dp(12) })
    }

    private fun appendCourseRows(list: LinearLayout, advance: Boolean) {
        if (advance && (!list.isAttachedToWindow || !root.isAttachedToWindow)) return
        val courses = dailyInfoRepository.currentTeachingCloudCourses().orEmpty()
        val assignments = dailyInfoRepository.allAssignments()
        val target = if (advance) (list.childCount + 20).coerceAtMost(courses.size)
            else sessionState.visibleCourseCount.coerceAtMost(courses.size)
        for (index in list.childCount until target) {
            val course = courses[index]
            val key = "teaching-cloud.course.${course.id}"
            list.addView(inlineCourseRow(key, course.name ?: activity.uiText("课程未标注"),
                course.teacherNames, CourseDirectoryLogic.teachingCloudCounts(course.id, assignments)))
        }
        sessionState.visibleCourseCount = maxOf(20, target)
    }

    private fun appendQmplusCourseRows(list: LinearLayout, advance: Boolean) {
        if (advance && (!list.isAttachedToWindow || !root.isAttachedToWindow)) return
        val snapshot = qmplusRepository?.snapshot?.let(QmplusSnapshotCodec::ebuOnly) ?: return
        val target = if (advance) (list.childCount + 20).coerceAtMost(qmplusRows.size)
            else sessionState.visibleQmplusRowCount.coerceAtMost(qmplusRows.size)
        for (index in list.childCount until target) {
            val course = qmplusRows[index].first
            val key = "qmplus.course.${course.id}"
            val term = if (course.currentTermStatus == "current") null else activity.getString(
                if (course.currentTermStatus == "other") R.string.qmplus_term_other else R.string.qmplus_term_unknown)
            list.addView(inlineCourseRow(key, course.name, emptyList(),
                CourseDirectoryLogic.qmplusCounts(course.id, snapshot.activities), term))
        }
        sessionState.visibleQmplusRowCount = maxOf(20, target)
    }

    private fun inlineCourseRow(key: String, name: String, teachers: List<String>,
        counts: CourseSubmissionCounts, term: String? = null): LinearLayout {
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL; tag = "$key.assignments"
            setPadding(activity.dp(52), 0, 0, activity.dp(12))
        }
        val viewport = NaturalDisclosureViewport(activity).apply {
            visibility = if (key in sessionState.expandedCourseKeys) View.VISIBLE else View.GONE
            addView(body, android.widget.FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        lateinit var row: LinearLayout
        lateinit var motion: DisclosureMotionController
        row = courseDirectoryRow(activity, key, name, teachers, counts, term,
            onDetails = { showCourseDetails(key) }) {
            val expanded = if (key in sessionState.expandedCourseKeys) {
                sessionState.expandedCourseKeys.remove(key); false
            } else { sessionState.expandedCourseKeys.add(key); true }
            if (expanded && body.childCount == 0) populateInlineAssignments(key, body)
            ViewCompat.setStateDescription(row.findViewWithTag("$key.disclosure.header"),
                activity.uiText(if (expanded) "已展开" else "已折叠"))
            motion.animateTo(expanded, body.childCount > 0)
        } as LinearLayout
        val indicator = row.findViewWithTag<View>("$key.disclosure.indicator")
        indicator.rotation = if (key in sessionState.expandedCourseKeys) 180f else 0f
        ViewCompat.setStateDescription(row.findViewWithTag("$key.disclosure.header"),
            activity.uiText(if (key in sessionState.expandedCourseKeys) "已展开" else "已折叠"))
        row.addView(viewport, 1)
        if (key in sessionState.expandedCourseKeys) populateInlineAssignments(key, body)
        motion = DisclosureMotionController(row, viewport, indicator, onDetached = {
            viewport.visibility = if (key in sessionState.expandedCourseKeys) View.VISIBLE else View.GONE
            viewport.layoutParams.height = ViewGroup.LayoutParams.WRAP_CONTENT; viewport.alpha = 1f
            indicator.rotation = if (key in sessionState.expandedCourseKeys) 180f else 0f
        })
        return row
    }

    private fun populateInlineAssignments(key: String, body: LinearLayout) {
        body.removeAllViews()
        val cloud = dailyInfoRepository.currentTeachingCloudCourses()?.firstOrNull { "teaching-cloud.course.${it.id}" == key }
        val snapshot = qmplusRepository?.takeIf { it.isFeatureEnabled }?.snapshot?.let(QmplusSnapshotCodec::ebuOnly)
        val qm = snapshot?.courses?.firstOrNull { "qmplus.course.${it.id}" == key }
        val cloudItems = cloud?.let { CourseDirectoryLogic.teachingCloudAssignments(it.id, dailyInfoRepository.allAssignments()) }
        val qmItems = qm?.let { course -> snapshot?.activities.orEmpty().filter { it.courseID == course.id } }.orEmpty()
        val visible = sessionState.inlineCourseCounts[key] ?: 20
        if (cloud != null && cloudItems == null) body.addView(statusCard(activity.getString(R.string.course_assignments_not_loaded)))
        else if (cloudItems.orEmpty().isEmpty() && qmItems.isEmpty()) body.addView(statusCard(activity.getString(R.string.course_no_cached_assignments)))
        cloudItems.orEmpty().take(visible).forEach { body.addView(cloudAssignmentCard(it)) }
        qmItems.take(visible).forEach { body.addView(qmplusActivityCard(it)) }
        if (cloudItems.orEmpty().size + qmItems.size > visible) body.addView(gradeAction("加载更多") {
            if (body.isAttachedToWindow && key in sessionState.expandedCourseKeys) {
                sessionState.inlineCourseCounts[key] = visible + 20
                populateInlineAssignments(key, body)
            }
        })
    }

    private fun showCourseDetails(key: String) {
        if (!root.isAttachedToWindow || activity.isFinishing || activity.isDestroyed ||
            sessionState.selectedMode != InformationQueryMode.COURSES) return
        if (sessionState.courseDetailKey != key) {
            sessionState.courseDetailScrollY = 0
            sessionState.courseDetailVisibleCount = 20
        }
        val body = courseDetailsBody(key) ?: run { sessionState.courseDetailKey = null; return }
        sessionState.courseDetailKey = key
        courseDetailsDialog?.setOnDismissListener(null)
        courseDetailsDialog?.dismiss()
        val detailScroll = ScrollView(activity).apply {
            id = R.id.course_detail_scroll; addView(body)
            setOnScrollChangeListener { _, _, y, _, _ -> if (isAttachedToWindow && !restoringCourseDetails) {
                sessionState.courseDetailScrollY = y
                if ((getChildAt(0)?.height ?: 0) - height - y <= activity.dp(240)) appendCourseDetailPage(key)
            } }
        }
        courseDetailsScroll = detailScroll
        restoringCourseDetails = true
        val dialog = AlertDialog.Builder(activity).setView(detailScroll)
            .setNegativeButton(activity.getString(R.string.course_detail_back)) { _, _ -> sessionState.courseDetailKey = null }
            .create()
        courseDetailsDialog = dialog
        dialog.setOnDismissListener {
            if (courseDetailsDialog === dialog) {
                if (!detachingCourseDetails) sessionState.courseDetailKey = null
                courseDetailsDialog = null; courseDetailsScroll = null
            }
        }
        dialog.show()
        dialog.window?.let { bindWindowColorTheme(it, modal = true) }
        detailScroll.postOnAnimation {
            if (courseDetailsScroll !== detailScroll) return@postOnAnimation
            if (detailScroll.isAttachedToWindow) detailScroll.scrollTo(0, sessionState.courseDetailScrollY)
            restoringCourseDetails = false
        }
    }

    private fun refreshCourseDetails() {
        val key = sessionState.courseDetailKey ?: return
        val detailScroll = courseDetailsScroll ?: return
        val body = courseDetailsBody(key)
        if (body == null) { sessionState.courseDetailKey = null; courseDetailsDialog?.dismiss(); return }
        val y = detailScroll.scrollY
        restoringCourseDetails = true
        detailScroll.removeAllViews(); detailScroll.addView(body)
        detailScroll.postOnAnimation {
            if (courseDetailsScroll !== detailScroll) return@postOnAnimation
            if (detailScroll.isAttachedToWindow) detailScroll.scrollTo(0, y)
            restoringCourseDetails = false
        }
    }

    private fun courseDetailsBody(key: String): LinearLayout? {
        val cloud = dailyInfoRepository.currentTeachingCloudCourses()?.firstOrNull { "teaching-cloud.course.${it.id}" == key }
        val snapshot = qmplusRepository?.takeIf { it.isFeatureEnabled }?.snapshot?.let(QmplusSnapshotCodec::ebuOnly)
        val qm = snapshot?.courses?.firstOrNull { "qmplus.course.${it.id}" == key }
        if (cloud == null && qm == null) return null
        return LinearLayout(activity).apply {
            id = R.id.course_detail_content; orientation = LinearLayout.VERTICAL
            setPadding(activity.dp(20), activity.dp(16), activity.dp(20), activity.dp(16))
            setThemeBackgroundColor { Palette.surface }
            addView(TextView(activity).apply {
                id = R.id.course_detail_title
                text = cloud?.name ?: qm?.name ?: activity.uiText("课程未标注")
                UiText.preserveRawText(this); textSize = 17f; setTypeface(typeface, Typeface.BOLD)
                setThemeTextColor { Palette.text }
            })
            cloud?.teacherNames?.forEach { addView(eventDetailText(it, 2)) }
            if (cloud != null) {
                val assignments = CourseDirectoryLogic.teachingCloudAssignments(cloud.id, dailyInfoRepository.allAssignments())
                addView(eventDetailText(activity.getString(R.string.course_detail_assignments), 2))
                if (assignments == null) addView(statusCard(activity.getString(R.string.course_assignments_not_loaded)))
                else if (assignments.isEmpty()) addView(statusCard(activity.getString(R.string.course_no_cached_assignments)))
                detailCloudItems = assignments.orEmpty(); detailQmItems = emptyList()
                addView(LinearLayout(activity).apply {
                    id = R.id.course_detail_list; orientation = LinearLayout.VERTICAL
                    appendCourseDetailRows(this, false)
                })
                addView(gradeAction(activity.getString(R.string.course_open_assignments_query)) {
                    sessionState.courseDetailKey = null; courseDetailsDialog?.dismiss()
                    root.findViewById<View>(R.id.information_query_assignments_tab)?.performClick()
                })
                addView(gradeAction("打开教学云平台", R.drawable.ic_shuttle_external) { openURL(CalendarDailyInfoSources.assignments) })
            } else if (qm != null && snapshot != null) {
                if (snapshot.partial) addView(statusCard(activity.getString(R.string.qmplus_partial)))
                val activities = snapshot.activities.filter { it.courseID == qm.id }
                if (activities.isEmpty()) addView(statusCard(activity.getString(R.string.course_no_cached_activities)))
                detailCloudItems = emptyList(); detailQmItems = activities
                addView(LinearLayout(activity).apply {
                    id = R.id.course_detail_list; orientation = LinearLayout.VERTICAL
                    appendCourseDetailRows(this, false)
                })
                addView(gradeAction(activity.getString(R.string.qmplus_open_course), R.drawable.ic_shuttle_external) { activity.connectQmplus(qm.url) })
            }
        }
    }

    private fun appendCourseDetailPage(key: String) {
        if (sessionState.courseDetailKey != key || courseDetailsScroll?.isAttachedToWindow != true) return
        courseDetailsScroll?.findViewById<LinearLayout?>(R.id.course_detail_list)?.let { appendCourseDetailRows(it, true) }
    }

    private fun appendCourseDetailRows(list: LinearLayout, advance: Boolean) {
        if (advance && (restoringCourseDetails || !list.isAttachedToWindow)) return
        val total = detailCloudItems.size + detailQmItems.size
        val target = if (advance) (list.childCount + 20).coerceAtMost(total)
            else sessionState.courseDetailVisibleCount.coerceAtMost(total)
        for (index in list.childCount until target) {
            val card = if (detailCloudItems.isNotEmpty()) cloudAssignmentCard(detailCloudItems[index])
                else qmplusActivityCard(detailQmItems[index])
            list.addView(card, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = activity.dp(10) })
        }
        sessionState.courseDetailVisibleCount = maxOf(20, target)
    }

    private fun cloudAssignmentCard(item: AssignmentDeadlineItem): LinearLayout = querySurface().apply {
        tag = "course.detail.assignment.${item.id}"
        addView(TextView(activity).apply {
            text = item.title; UiText.preserveRawText(this); textSize = 17f
            setThemeTextColor { Palette.text }; setTypeface(typeface, Typeface.BOLD)
        })
        addView(eventDetailText(listOfNotNull(item.deadline.replace('T', ' ').take(16),
            item.status?.takeIf { it.isNotBlank() }).joinToString(" · "), Int.MAX_VALUE))
    }

    private fun qmplusActivityCard(item: QmplusActivityItem): LinearLayout = querySurface().apply {
        tag = "course.detail.qmplus.${item.kind}.${item.id}"
        addView(TextView(activity).apply {
            text = item.title; UiText.preserveRawText(this); textSize = 17f
            setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
        })
        val metadata = buildList {
          add(activity.getString(if (item.kind == "quiz") R.string.qmplus_quiz else R.string.qmplus_assignment))
          QmplusActivityPresentation.timeFields(item).forEach { (field, value) ->
            val label = when (field) {
                "due_at" -> R.string.qmplus_due; "cutoff_at" -> R.string.qmplus_cutoff
                "opens_at" -> R.string.qmplus_opens; else -> R.string.qmplus_closes
            }
            add(activity.getString(label) + ": " + value.replace('T', ' ').removeSuffix("Z") + " UTC")
        }
        if (item.kind == "quiz") item.timeLimitSeconds?.let {
            add(activity.getString(R.string.qmplus_time_limit, it))
        }
          item.status?.takeIf { it.isNotBlank() && it != "unknown" }?.let(::add)
          item.rawTimeText?.takeIf { it.isNotBlank() }?.let(::add)
        }
        addView(eventDetailText(metadata.joinToString(" · "), Int.MAX_VALUE))
        addView(gradeAction(activity.getString(R.string.qmplus_open_activity), R.drawable.ic_shuttle_external) { activity.connectQmplus(item.url) })
    }

    private fun qmplusContent(): LinearLayout = privateQueryContent {
        val repository = qmplusRepository
        if (repository?.isFeatureEnabled != true) { qmplusRows = emptyList(); return@privateQueryContent }
        val snapshot = repository?.snapshot
        addView(gradeAction(if (repository?.manualContinuationRequired == true) activity.uiText("手动继续") else activity.getString(R.string.qmplus_connect_sync)) { activity.connectQmplus() }
            .apply { id = R.id.course_qmplus_refresh
                isEnabled = repository != null && !repository.isLoading && !repository.isClearingSession && repository.connection == null })
        addView(querySourceFooter("QMplus · Queen Mary University of London", QmplusPolicy.START_URL))
        repository?.error?.let { addView(statusCard(activity.uiText(it))) }
        when {
            snapshot == null -> addView(statusCard(activity.getString(
                if (repository?.isLoading == true) R.string.qmplus_loading else R.string.qmplus_not_connected)))
            else -> {
                addView(eventDetailText(activity.getString(R.string.qmplus_fetched_at, snapshot.fetchedAt), 2))
                if (snapshot.partial) addView(statusCard(activity.getString(R.string.qmplus_partial)))
                snapshot.warnings.forEach { addView(eventDetailText(it, 2)) }
                if (snapshot.courses.isEmpty()) addView(statusCard(activity.getString(R.string.qmplus_no_courses)))
                val activities = snapshot.activities.groupBy { it.courseID }
                qmplusRows = snapshot.courses.sortedBy { when (it.currentTermStatus) { "current" -> 0; "unknown" -> 1; else -> 2 } }
                    .flatMap { course -> listOf(course to null) + activities[course.id].orEmpty().map { course to it } }
                addView(LinearLayout(activity).apply {
                    id = R.id.course_qmplus_list; orientation = LinearLayout.VERTICAL
                    appendQmplusRows(this, false)
                })
            }
        }
    }

    private fun appendQmplusRows(list: LinearLayout, advance: Boolean) {
        if (advance && (!list.isAttachedToWindow || !root.isAttachedToWindow)) return
        val target = if (advance) (list.childCount + 20).coerceAtMost(qmplusRows.size)
            else sessionState.visibleQmplusRowCount.coerceAtMost(qmplusRows.size)
        for (index in list.childCount until target) {
            val (course, item) = qmplusRows[index]
            list.addView(querySurface().apply {
                tag = if (item == null) "qmplus.course.${course.id}" else "qmplus.activity.${item.kind}.${item.id}"
                addView(TextView(activity).apply {
                    text = item?.title ?: course.name; UiText.preserveRawText(this); textSize = 17f
                    setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
                })
                if (item == null) {
                    addView(eventDetailText(activity.getString(when (course.currentTermStatus) {
                        "current" -> R.string.qmplus_term_current; "other" -> R.string.qmplus_term_other
                        else -> R.string.qmplus_term_unknown
                    }), 2))
                    addView(gradeAction(activity.getString(R.string.qmplus_open_course), R.drawable.ic_shuttle_external) { activity.connectQmplus(course.url) })
                } else {
                    addView(eventDetailText(course.name, 2))
                    addView(eventDetailText(activity.getString(if (item.kind == "quiz") R.string.qmplus_quiz else R.string.qmplus_assignment), 2))
                    listOf(R.string.qmplus_due to item.dueAt, R.string.qmplus_opens to item.opensAt,
                        R.string.qmplus_closes to item.closesAt, R.string.qmplus_cutoff to item.cutoffAt).forEach { (label, value) ->
                        addView(eventDetailText(activity.getString(label) + ": " +
                            (value?.let { it.replace('T', ' ').removeSuffix("Z") + " UTC" }
                                ?: activity.getString(R.string.qmplus_not_published)), 3))
                    }
                    item.timeLimitSeconds?.let { addView(eventDetailText(activity.getString(R.string.qmplus_time_limit, it), 2)) }
                    item.status?.let { addView(eventDetailText(it, 2)) }
                    if (item.detailStatus != "available") addView(eventDetailText(activity.getString(R.string.qmplus_detail_unavailable), 3))
                    item.rawTimeText?.takeIf { it.isNotBlank() }?.let { addView(eventDetailText(it, 6)) }
                    addView(gradeAction(activity.getString(R.string.qmplus_open_activity), R.drawable.ic_shuttle_external) { activity.connectQmplus(item.url) })
                }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { if (index > 0) topMargin = activity.dp(10) })
        }
        sessionState.visibleQmplusRowCount = maxOf(20, target)
    }

    private fun assignmentState() = Triple(dailyInfoRepository.allAssignments(),
        dailyInfoRepository.isLoadingAllAssignments(), dailyInfoRepository.allAssignmentsError())
    private fun courseState() = Triple(dailyInfoRepository.currentTeachingCloudCourses(),
        dailyInfoRepository.isLoadingCurrentCourses(), dailyInfoRepository.currentCoursesError())

    private fun examsContent(): LinearLayout = privateQueryContent {
        val exams = scheduleRepository.schedule?.examSchedule
        addView(gradeAction(if (scheduleRepository.isRefreshing) "正在获取…" else "刷新课表与考试") {
            scheduleRepository.refresh(activity.scheduleCompletionCallback(refreshOtherPages = false))
            renderMode(animate = false)
        }.apply { id = R.id.information_query_exams_refresh; isEnabled = !scheduleRepository.isRefreshing })
        addView(statusCard(AcademicScheduleLogic.statusText(exams)))
        exams?.items.orEmpty().forEach { exam ->
            addView(querySurface().apply {
                tag = "academic.exam.row"
                addView(TextView(activity).apply {
                    text = exam.name; UiText.preserveRawText(this)
                    textSize = 17f; setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
                })
                addView(eventDetailText(exam.date.ifBlank { "日期待定" }, 2))
                val time = if (AcademicScheduleLogic.minute(exam.startTime) != null && AcademicScheduleLogic.minute(exam.endTime) != null)
                    "${exam.startTime}–${exam.endTime}" else "时间待定"
                addView(eventDetailText(time, 2))
                if (exam.room.isNotBlank()) addView(eventDetailText(exam.room, 2))
                if (exam.seat.isNotBlank()) addView(eventDetailText("座位：${exam.seat}", 2))
                if (exam.timeText.isNotBlank()) addView(eventDetailText(exam.timeText, 3))
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = activity.dp(10) })
        }
    }

    private fun gradeAction(label: String, iconResource: Int = 0, action: () -> Unit): TextView = TextView(activity).apply {
        text = label; textSize = 15f; gravity = Gravity.CENTER
        setThemeTextColor { Palette.primaryText }; minimumHeight = activity.dp(UiMetrics.controlHeightDp)
        setPadding(activity.dp(12), 0, activity.dp(12), 0)
        if (iconResource != 0) {
            val iconSize = activity.dp(16)
            val icon = activity.getDrawable(iconResource)?.mutate()?.apply {
                setBounds(0, 0, iconSize, iconSize)
            }
            setCompoundDrawablesRelative(icon, null, null, null)
            compoundDrawablePadding = activity.dp(6)
            bindTheme("gradeActionIcon") {
                compoundDrawableTintList = ColorStateList.valueOf(Palette.primaryText)
            }
            contentDescription = activity.uiText(label)
        }
        background = themedRoundedBackground(activity, { Palette.surfaceVariant }, radius = 8)
        isClickable = true; isFocusable = true
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = activity.dp(8) }
        setOnClickListener { activity.performControlHaptic(it); action() }
    }

    private fun shuttleContent(): LinearLayout = queryBody {
        val snapshot = shuttleRepository.snapshot
        when {
            snapshot != null -> renderShuttleSnapshot(snapshot)
            shuttleRepository.error != null -> addView(retryCard(
                shuttleRepository.error ?: "班车信息获取失败。",
            ) { shuttleRepository.load(force = true) })
            else -> addView(statusCard("正在获取今日班车与当前时刻表…"))
        }
    }

    private fun LinearLayout.renderShuttleSnapshot(snapshot: ShuttleBusSnapshot) {
        val now = Calendar.getInstance(shanghai)
        val currentTime = "%02d:%02d".format(Locale.ROOT, now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE))
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = shanghai
        }.format(now.time)
        val isHoliday = ShuttleBusLogic.isPublicHoliday(
            holidaySnapshotForYear(now.get(Calendar.YEAR)), today,
        )
        val presentation = ShuttleBusLogic.today(snapshot, now, isHoliday)
        val departureCount = presentation.routes.sumOf { it.departures.size }
        val statusTitle = when {
            isHoliday -> "法定节假日，班车安排以学校通知为准"
            presentation.routes.isEmpty() -> "今日暂无生效班车时刻表"
            departureCount == 0 -> "今日没有计划班次"
            else -> "今日班车按时刻表运行"
        }
        addView(shuttleSurface().apply {
            id = R.id.information_query_shuttle_status
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(shuttleIcon(R.drawable.ic_shuttle_bus),
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
                }, shuttleActionLayoutParams().apply { marginStart = activity.dp(8) })
            })
            if (presentation.isStale) addView(TextView(activity).apply {
                text = "当前展示最近一次成功同步的缓存"
                textSize = 12f
                setThemeTextColor { Palette.muted }
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
                        }, shuttleActionLayoutParams().apply { marginStart = activity.dp(8) })
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
        if (isHoliday) {
            addView(shuttleSurface().apply {
                tag = "information.query.shuttle.holiday.warning"
                addView(TextView(activity).apply {
                    text = "今日为法定节假日，班车不一定运行；请以学校放假安排为准，放假期间无班车。"
                    textSize = 13f
                    setThemeTextColor { Palette.muted }
                })
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = activity.dp(12) })
        }
        addView(spacer(activity, ShuttleQueryLayoutLogic.ROUTE_SPACING_DP))
        addView(adaptiveShuttleGrid(
            presentation.routes,
            activity.dp(ShuttleQueryLayoutLogic.ROUTE_MIN_WIDTH_DP),
            activity.dp(ShuttleQueryLayoutLogic.ROUTE_SPACING_DP),
            maximumColumns = 2,
        ) { route -> shuttleRouteCard(route, currentTime, !isHoliday, presentation.stops.filter { (campus, _) ->
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
        ShuttleBusLogic.latestTimetableNotice(snapshot)?.let { notice ->
            val schedules = notice.schedules.filter { it.parseStatus == "parsed" && it.rows.isNotEmpty() }
            addView(shuttleSurface().apply {
                tag = "information.query.shuttle.full-timetable"
                addView(TextView(activity).apply {
                    text = activity.uiText("完整班车时刻表"); textSize = 17f
                    setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
                })
                addView(TextView(activity).apply {
                    text = notice.title; UiText.preserveRawText(this); textSize = 12f
                    setThemeTextColor { Palette.muted }; setPadding(0, activity.dp(4), 0, activity.dp(10))
                })
                schedules.groupBy { it.period }.forEach { (period, directions) ->
                    val periodKey = listOf(period.label, period.startDate.orEmpty(), period.endDate.orEmpty()).joinToString("|")
                    addView(shuttleTimetableDisclosure("period.$periodKey", period.label,
                        fullTimetablePeriodMetadata(period, today), sessionState.expandedTimetablePeriods) {
                        LinearLayout(activity).apply {
                            orientation = LinearLayout.VERTICAL
                            directions.forEach { route ->
                                val directionKey = periodKey + "|" + route.from.orEmpty() + "|" + route.to.orEmpty()
                                addView(shuttleTimetableDisclosure("direction.$directionKey",
                                    route.from.orEmpty() + " → " + route.to.orEmpty(), null,
                                    sessionState.expandedTimetableDirections) { fullTimetableCell(route) })
                                addView(spacer(activity, 8))
                            }
                        }
                    })
                    addView(spacer(activity, 8))
                }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = activity.dp(16) })
        }
        addView(shuttleSourceFooter(snapshot.sourcePage))
    }

    private fun shuttleTimetableDisclosure(key: String, title: String, description: String?,
        expandedKeys: MutableSet<String>, makeBody: () -> View): LinearLayout = shuttleSurface().apply {
        tag = "information.query.shuttle.$key"
        val body = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val viewport = NaturalDisclosureViewport(activity).apply {
            visibility = if (key in expandedKeys) View.VISIBLE else View.GONE
            addView(body, android.widget.FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        val indicator = ImageView(activity).apply {
            setImageResource(R.drawable.ic_chevron_down)
            imageTintList = android.content.res.ColorStateList.valueOf(Palette.muted)
            rotation = if (key in expandedKeys) 180f else 0f
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val header = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            isClickable = true; isFocusable = true
            minimumHeight = activity.dp(filterHeightDp)
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(activity).apply {
                    text = title; UiText.preserveRawText(this); textSize = 14f
                    setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
                })
                description?.let { addView(TextView(activity).apply {
                    text = it; UiText.preserveRawText(this); textSize = 12f
                    setThemeTextColor { Palette.muted }
                }) }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(indicator, LinearLayout.LayoutParams(activity.dp(18), activity.dp(18)))
        }
        fun updateAccessibility() {
            ViewCompat.setStateDescription(header, activity.uiText(if (key in expandedKeys) "已展开" else "已折叠"))
        }
        ViewCompat.setAccessibilityDelegate(header, object : AccessibilityDelegateCompat() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfoCompat) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = android.widget.Button::class.java.name
                info.addAction(if (key in expandedKeys) AccessibilityNodeInfoCompat.ACTION_COLLAPSE
                    else AccessibilityNodeInfoCompat.ACTION_EXPAND)
            }
            override fun performAccessibilityAction(host: View, action: Int, args: android.os.Bundle?): Boolean {
                if ((action == AccessibilityNodeInfoCompat.ACTION_EXPAND && key !in expandedKeys) ||
                    (action == AccessibilityNodeInfoCompat.ACTION_COLLAPSE && key in expandedKeys)) return host.performClick()
                return super.performAccessibilityAction(host, action, args)
            }
        })
        if (key in expandedKeys) body.addView(makeBody())
        val motion = DisclosureMotionController(this, viewport, indicator, onDetached = {
            viewport.visibility = if (key in expandedKeys) View.VISIBLE else View.GONE
            viewport.layoutParams.height = ViewGroup.LayoutParams.WRAP_CONTENT; viewport.alpha = 1f
            indicator.rotation = if (key in expandedKeys) 180f else 0f
        })
        header.setOnClickListener {
            activity.performControlHaptic(it)
            val expanded = if (key in expandedKeys) { expandedKeys.remove(key); false }
                else { expandedKeys.add(key); true }
            if (expanded && body.childCount == 0) body.addView(makeBody())
            updateAccessibility(); motion.animateTo(expanded)
        }
        updateAccessibility()
        addView(header); addView(viewport)
    }

    private fun fullTimetableCell(schedule: ShuttleBusSchedule): LinearLayout =
        LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        background = themedRoundedBackground(activity, { Palette.surfaceVariant }, radius = 8)
        if (availableWidthDp >= 760) {
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                ShuttleBusLogic.timetableWeekdays.forEachIndexed { index, (key, label) ->
                    val departures = ShuttleBusLogic.timetableDepartures(schedule, key)
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        setPadding(activity.dp(5), activity.dp(7), activity.dp(5), activity.dp(7))
                        background = themedRoundedBackground(activity, { Palette.surface }, radius = 6)
                        addView(TextView(activity).apply {
                            text = activity.uiText(label)
                            textSize = 12f
                            setTypeface(typeface, Typeface.BOLD)
                            setThemeTextColor { Palette.primaryText }
                        })
                        addView(TextView(activity).apply {
                            text = if (departures.isEmpty()) activity.uiText("无计划班次") else
                                departures.joinToString("\n") { departure ->
                                    "${departure.time} ${departure.vehicle}×${departure.count}"
                                }
                            UiText.preserveRawText(this)
                            textSize = 11f
                            setThemeTextColor { Palette.text }
                            setPadding(0, activity.dp(5), 0, 0)
                        })
                    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                        if (index < ShuttleBusLogic.timetableWeekdays.lastIndex) marginEnd = activity.dp(6)
                    })
                }
            })
        } else ShuttleBusLogic.timetableWeekdays.forEach { (key, label) ->
            val departures = ShuttleBusLogic.timetableDepartures(schedule, key)
            addView(TextView(activity).apply {
                text = "${activity.uiText(label)}  " +
                    if (departures.isEmpty()) activity.uiText("无计划班次") else
                        departures.joinToString(" · ") { departure ->
                            "${departure.time} ${departure.vehicle} × ${departure.count}"
                        }
                UiText.preserveRawText(this)
                textSize = 12f
                setThemeTextColor { Palette.text }
                setPadding(0, activity.dp(3), 0, activity.dp(3))
            })
        }
    }

    private fun fullTimetablePeriodMetadata(period: ShuttleBusPeriod, today: String): String {
        val dates = when {
            period.startDate != null && period.endDate != null ->
                "${period.startDate} – ${period.endDate}"
            period.startDate != null -> "${period.startDate} ${activity.uiText("起")}"
            period.endDate != null -> "${activity.uiText("截至")} ${period.endDate}"
            else -> activity.uiText("日期待确认")
        }
        val state = when (ShuttleBusLogic.periodStatus(period, today)) {
            TimetablePeriodStatus.ACTIVE -> "当前生效"
            TimetablePeriodStatus.UPCOMING -> "即将生效"
            TimetablePeriodStatus.PAST -> "已结束时段"
            TimetablePeriodStatus.UNCONFIRMED -> "时段待确认"
        }
        return "$dates · ${activity.uiText(state)}"
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
        addView(shuttleIcon(R.drawable.ic_shuttle_notice), LinearLayout.LayoutParams(activity.dp(18), activity.dp(20))
            .apply { marginEnd = activity.dp(9) })
        addView(TextView(activity).apply {
            text = "第三方来源：北京邮电大学后勤部公开通知，由 Where To Study 服务解析整理，仅供参考，请以官方原文为准。"
            textSize = 12f
            setThemeTextColor { ColorThemeLogic.readableText(Palette.muted,
                ColorUtils.blendARGB(Palette.background, Palette.primaryFill, 0.08f)) }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(shuttleIconButton(R.drawable.ic_shuttle_external, "查看数据来源", outlined = false).apply {
            id = R.id.information_query_shuttle_source_link
            setOnClickListener { openURL(url) }
        }, shuttleActionLayoutParams().apply { marginStart = activity.dp(4) })
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
            // Keep icon artwork independent from the app's compact text controls.
            // A 32 dp control with the previous 13 dp inset shrank it to only 6 dp.
            val inset = activity.dp((ShuttleQueryLayoutLogic.ACTION_TOUCH_SIZE_DP -
                ShuttleQueryLayoutLogic.ACTION_ICON_SIZE_DP) / 2)
            setPadding(inset, inset, inset, inset)
            if (outlined) background = themedRoundedBackground(activity, {
                ColorUtils.blendARGB(Palette.surface, Palette.primaryFill, 0.12f)
            }, radius = 24)
        }

    private fun shuttleActionLayoutParams() = LinearLayout.LayoutParams(
        activity.dp(ShuttleQueryLayoutLogic.ACTION_TOUCH_SIZE_DP),
        activity.dp(ShuttleQueryLayoutLogic.ACTION_TOUCH_SIZE_DP),
    )

    private fun shuttleRouteCard(
        route: TodayShuttleRoute,
        currentTime: String,
        showNext: Boolean,
        pickupLocations: List<String>,
    ): LinearLayout =
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
                addView(shuttleDepartureGrid(route.departures, currentTime, showNext))
            }
        }

    private fun shuttleDepartureGrid(
        departures: List<TodayShuttleDeparture>,
        currentTime: String,
        showNext: Boolean,
    ): LinearLayout {
        val nextDeparture = if (showNext) ShuttleQueryLayoutLogic.nextDeparture(departures, currentTime)
        else null
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

    private fun importantEventsContent(): LinearLayout {
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

        lateinit var eventList: LinearLayout
        return queryBody {
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
                "第三方来源：Contest DDL 主源、较新镜像及备用 API；校内竞赛通知另行获取，不包含课程作业",
                CalendarDailyInfoSources.deadlinePrimaryPage,
            ))
            addView(querySourceFooter(
                "Contest DDL 较新镜像数据",
                CalendarDailyInfoSources.deadlineMirror,
            ))
            addView(querySourceFooter("Contest DDL 备用 API", CalendarDailyInfoSources.deadlineBackup))
        }
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
        sessionState.modeScrollY[InformationQueryMode.IMPORTANT_EVENTS] = 0
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
        text = "${activity.uiText(label)} ↗"
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
