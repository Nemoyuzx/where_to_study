package com.nemoyu.wheretostudy.nativeapp

import android.app.PendingIntent
import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
import android.widget.ImageView
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.util.SizeF
import androidx.core.os.BundleCompat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

enum class WidgetCoursePhase {
    UPCOMING,
    IN_PROGRESS,
    FINISHED,
}

private val widgetThemeAccentIDs = listOf(
    R.id.widget_theme_accent_1, R.id.widget_theme_accent_2, R.id.widget_theme_accent_3,
    R.id.widget_theme_accent_4, R.id.widget_theme_accent_5, R.id.widget_theme_accent_6,
)
private val widgetThemeIconIDs = listOf(R.id.widget_theme_calendar_icon, R.id.widget_theme_empty_icon)

private fun widgetThemeColors(context: Context): ThemeColors {
    val selection = ColorThemePreferences(context).load()
    val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    val colors = ColorThemeLogic.palette(selection, dark)
    return if (selection.preset == "default") colors.copy(
        primaryText = context.getColor(R.color.widget_primary),
        accent = context.getColor(R.color.widget_accent),
        surface = context.getColor(R.color.widget_background),
        text = context.getColor(R.color.widget_text_primary),
        muted = context.getColor(R.color.widget_text_secondary),
    ) else colors
}

data class TodayCourseWidgetContent(
    val courses: List<Course>,
    val dateContext: String,
    val statusText: String,
    val highlightedCourseID: String?,
    val highlightedCoursePhase: WidgetCoursePhase?,
    val tomorrowCourses: List<Course> = emptyList(),
) {
    val emptyMessage: String
        get() = "今日无课"

    val contextText: String
        get() = listOf(dateContext, statusText)
            .filter(String::isNotBlank)
            .joinToString(" · ")
}

data class WidgetDisplayRow(val course: Course, val isTomorrow: Boolean = false)

object TodayCourseWidgetLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val weekdays = listOf("周日", "周一", "周二", "周三", "周四", "周五", "周六")

    fun content(schedule: ScheduleSnapshot?, nowMillis: Long): TodayCourseWidgetContent {
        val target = Calendar.getInstance(shanghai).apply { timeInMillis = nowMillis }
        val courses = ScheduleLogic.courses(schedule, target)
        val week = ScheduleLogic.weekNumber(schedule, target)
        val highlighted = highlightedCourse(courses, target)
        val tomorrow = (target.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1) }
        return TodayCourseWidgetContent(
            courses = courses,
            dateContext = dateContext(target, week),
            statusText = statusText(courses, target),
            highlightedCourseID = highlighted?.first?.id,
            highlightedCoursePhase = highlighted?.second,
            tomorrowCourses = ScheduleLogic.courses(schedule, tomorrow),
        )
    }

    fun previewContent(nowMillis: Long = System.currentTimeMillis()): TodayCourseWidgetContent {
        val target = Calendar.getInstance(shanghai).apply { timeInMillis = nowMillis }
        val weekday = ((target.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        val termStart = (target.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, 1 - weekday)
        }
        val schedule = ScheduleSnapshot(
            termID = "widget-preview",
            termStartDate = String.format(
                Locale.US,
                "%04d-%02d-%02d",
                termStart.get(Calendar.YEAR),
                termStart.get(Calendar.MONTH) + 1,
                termStart.get(Calendar.DAY_OF_MONTH),
            ),
            fetchedAt = "widget-preview",
            courses = listOf(
                previewCourse(
                    id = "widget-preview-calculus",
                    name = "高等数学",
                    teacher = "示例教师",
                    room = "教2-101",
                    sectionText = "1-2节",
                    timeRange = "08:00-09:35",
                    weekday = weekday,
                    startSlot = 0,
                    endSlot = 1,
                ),
                previewCourse(
                    id = "widget-preview-data-mining",
                    name = "数据挖掘",
                    teacher = "示例教师",
                    room = "教3-335",
                    sectionText = "3-5节",
                    timeRange = "09:50-12:15",
                    weekday = weekday,
                    startSlot = 2,
                    endSlot = 4,
                ),
                previewCourse(
                    id = "widget-preview-network",
                    name = "计算机网络",
                    teacher = "示例教师",
                    room = "教4-201",
                    sectionText = "6-7节",
                    timeRange = "13:00-14:35",
                    weekday = weekday,
                    startSlot = 5,
                    endSlot = 6,
                ),
                previewCourse(
                    id = "widget-preview-neural-network",
                    name = "神经网络与深度学习",
                    teacher = "示例教师",
                    room = "教3-539",
                    sectionText = "8-9节",
                    timeRange = "14:45-16:25",
                    weekday = weekday % 7 + 1,
                    startSlot = 7,
                    endSlot = 8,
                ),
                previewCourse(
                    id = "widget-preview-sports",
                    name = "体育",
                    teacher = "示例教师",
                    room = "体育馆",
                    sectionText = "10-11节",
                    timeRange = "16:35-18:10",
                    weekday = weekday % 7 + 1,
                    startSlot = 9,
                    endSlot = 10,
                ),
                previewCourse(
                    id = "widget-preview-english",
                    name = "学术英语",
                    teacher = "示例教师",
                    room = "主楼-201",
                    sectionText = "12-13节",
                    timeRange = "18:30-20:05",
                    weekday = weekday % 7 + 1,
                    startSlot = 11,
                    endSlot = 12,
                ),
            ),
        )
        return content(schedule, nowMillis)
    }

    fun details(
        course: Course,
        showsLocation: Boolean = true,
        showsTeacher: Boolean = true,
    ): String = listOfNotNull(
        course.timeRange,
        course.sectionText.takeIf(String::isNotBlank),
        course.room.takeIf { showsLocation && it.isNotBlank() },
        course.teacher.takeIf { showsTeacher && it.isNotBlank() },
    ).joinToString(" · ")

    fun title(course: Course, content: TodayCourseWidgetContent): String = when {
        course.id != content.highlightedCourseID -> course.name
        content.highlightedCoursePhase == WidgetCoursePhase.IN_PROGRESS -> "进行中 · ${course.name}"
        content.highlightedCoursePhase == WidgetCoursePhase.UPCOMING -> "下一节 · ${course.name}"
        else -> course.name
    }

    fun displayRows(content: TodayCourseWidgetContent, capacity: Int, courseLimit: Int = 6): List<WidgetDisplayRow> {
        val limit = minOf(capacity.coerceIn(1, 6), courseLimit.coerceIn(1, 6))
        val today = content.courses.take(limit).map { WidgetDisplayRow(it) }
        return today + content.tomorrowCourses.take(limit - today.size).map { WidgetDisplayRow(it, isTomorrow = true) }
    }

    fun title(row: WidgetDisplayRow, content: TodayCourseWidgetContent): String =
        if (row.isTomorrow) "明日 · ${row.course.name}" else title(row.course, content)

    fun nextMidnightAt(nowMillis: Long): Long = Calendar.getInstance(shanghai).run {
        timeInMillis = nowMillis
        add(Calendar.DAY_OF_MONTH, 1)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        timeInMillis
    }

    internal fun rowLimit(minimumHeightDp: Int): Int {
        if (minimumHeightDp <= 0) return 3
        // Header, date/status line, padding and the hidden-course hint need about 80dp.
        // Every course row is 40dp high, so deriving the capacity from the real layout
        // keeps partially resized widgets from clipping their last visible row.
        return ((minimumHeightDp - 80) / 40).coerceIn(1, 6)
    }

    private fun dateContext(target: Calendar, week: Int?): String {
        val values = mutableListOf(
            "${target.get(Calendar.MONTH) + 1}月${target.get(Calendar.DAY_OF_MONTH)}日",
            weekdays[target.get(Calendar.DAY_OF_WEEK) - 1],
            "公历第${TeachingCalendarLogic.calendarWeekNumber(target)}周",
        )
        if (week != null) values += "教学第${week}周"
        return values.joinToString(" · ")
    }

    private fun statusText(courses: List<Course>, target: Calendar): String {
        if (courses.isEmpty()) return "今天可以自由安排"
        val current = courses.firstOrNull { phase(it, target) == WidgetCoursePhase.IN_PROGRESS }
        if (current != null) {
            val end = timeParts(current.timeRange)?.second.orEmpty()
            return if (end.isEmpty()) "课程进行中" else "进行中 · $end 下课"
        }
        val upcoming = courses.firstOrNull { phase(it, target) == WidgetCoursePhase.UPCOMING }
        if (upcoming != null) {
            val start = timeParts(upcoming.timeRange)?.first.orEmpty()
            return if (start.isEmpty()) "还有待上课程" else "下一节 · $start"
        }
        return "今日课程已结束"
    }

    private fun highlightedCourse(
        courses: List<Course>,
        target: Calendar,
    ): Pair<Course, WidgetCoursePhase>? {
        courses.firstOrNull { phase(it, target) == WidgetCoursePhase.IN_PROGRESS }?.let {
            return it to WidgetCoursePhase.IN_PROGRESS
        }
        courses.firstOrNull { phase(it, target) == WidgetCoursePhase.UPCOMING }?.let {
            return it to WidgetCoursePhase.UPCOMING
        }
        return null
    }

    private fun phase(course: Course, target: Calendar): WidgetCoursePhase? {
        val range = minuteRange(course) ?: return null
        val minute = target.get(Calendar.HOUR_OF_DAY) * 60 + target.get(Calendar.MINUTE)
        return when {
            minute < range.first -> WidgetCoursePhase.UPCOMING
            minute <= range.last -> WidgetCoursePhase.IN_PROGRESS
            else -> WidgetCoursePhase.FINISHED
        }
    }

    private fun minuteRange(course: Course): IntRange? {
        val parts = timeParts(course.timeRange) ?: return null
        val start = minutes(parts.first) ?: return null
        val end = minutes(parts.second) ?: return null
        return if (end >= start) start..end else null
    }

    private fun timeParts(value: String): Pair<String, String>? {
        val normalized = value.replace('–', '-').replace('—', '-')
        val parts = normalized.split('-', limit = 2)
        return parts.takeIf { it.size == 2 }?.let { it[0] to it[1] }
    }

    private fun minutes(value: String): Int? {
        val parts = value.split(':', limit = 2).mapNotNull(String::toIntOrNull)
        if (parts.size != 2 || parts[0] !in 0..23 || parts[1] !in 0..59) return null
        return parts[0] * 60 + parts[1]
    }

    private fun previewCourse(
        id: String,
        name: String,
        teacher: String,
        room: String,
        sectionText: String,
        timeRange: String,
        weekday: Int,
        startSlot: Int,
        endSlot: Int,
    ) = Course(
        id = id,
        name = name,
        teacher = teacher,
        room = room,
        weekText = "1周",
        weekNumbers = listOf(1, 2),
        examWeekNumbers = emptyList(),
        weekday = weekday,
        startSlot = startSlot,
        endSlot = endSlot,
        sectionText = sectionText,
        timeRange = timeRange,
    )
}

private data class WidgetRowIDs(
    val container: Int,
    val name: Int,
    val details: Int,
)

private val widgetRowIDs = listOf(
    WidgetRowIDs(R.id.widget_course_1, R.id.widget_course_name_1, R.id.widget_course_details_1),
    WidgetRowIDs(R.id.widget_course_2, R.id.widget_course_name_2, R.id.widget_course_details_2),
    WidgetRowIDs(R.id.widget_course_3, R.id.widget_course_name_3, R.id.widget_course_details_3),
    WidgetRowIDs(R.id.widget_course_4, R.id.widget_course_name_4, R.id.widget_course_details_4),
    WidgetRowIDs(R.id.widget_course_5, R.id.widget_course_name_5, R.id.widget_course_details_5),
    WidgetRowIDs(R.id.widget_course_6, R.id.widget_course_name_6, R.id.widget_course_details_6),
)

private val widgetThemeTextIDs = listOf(R.id.widget_theme_title) + widgetRowIDs.map { it.name }
private val widgetThemeMutedIDs = listOf(
    R.id.widget_course_count, R.id.widget_day_context, R.id.widget_empty_text, R.id.widget_more_courses,
) + widgetRowIDs.map { it.details }

private fun widgetCountText(context: Context, content: TodayCourseWidgetContent, rows: List<WidgetDisplayRow>): String =
    if (rows.any { it.isTomorrow }) context.getString(
        R.string.widget_today_tomorrow_count_format, content.courses.size, content.tomorrowCourses.size,
    ) else if (content.courses.isEmpty()) "" else context.getString(R.string.widget_course_count_format, content.courses.size)

object TodayCourseWidgetPreviewBinder {
    fun bind(
        root: View,
        content: TodayCourseWidgetContent,
        showsLocation: Boolean,
        showsTeacher: Boolean,
        rowLimit: Int,
    ) {
        val context = root.context
        root.bindTheme("widgetColors") {
            val colors = widgetThemeColors(context)
            root.backgroundTintList = if (ColorThemePreferences(context).load().preset == "default") null
                else ColorStateList.valueOf(colors.surface)
            widgetThemeIconIDs.forEach { id -> root.findViewById<ImageView>(id).imageTintList = ColorStateList.valueOf(colors.primaryText) }
            widgetThemeAccentIDs.forEach { id -> root.findViewById<View>(id).setBackgroundColor(colors.accent) }
            widgetThemeTextIDs.forEach { id -> root.findViewById<TextView>(id).setTextColor(colors.text) }
            widgetThemeMutedIDs.forEach { id -> root.findViewById<TextView>(id).setTextColor(colors.muted) }
        }
        val rows = TodayCourseWidgetLogic.displayRows(content, rowLimit)
        root.findViewById<TextView>(R.id.widget_course_count).text = widgetCountText(context, content, rows)
        root.findViewById<TextView>(R.id.widget_day_context).text =
            UiText.widgetContext(context, content.contextText)
        root.findViewById<TextView>(R.id.widget_empty_text).text = context.uiText(content.emptyMessage)
        root.findViewById<View>(R.id.widget_empty_state).visibility =
            if (rows.isEmpty()) View.VISIBLE else View.GONE
        root.findViewById<View>(R.id.widget_courses).visibility =
            if (rows.isEmpty()) View.GONE else View.VISIBLE

        widgetRowIDs.forEachIndexed { index, ids ->
            val row = rows.getOrNull(index)
            val course = row?.course
            root.findViewById<View>(ids.container).visibility =
                if (course == null) View.GONE else View.VISIBLE
            if (course != null) {
                root.findViewById<TextView>(ids.name).text =
                    UiText.widgetCourseTitle(context, TodayCourseWidgetLogic.title(row, content))
                root.findViewById<TextView>(ids.details).text = TodayCourseWidgetLogic.details(
                    course,
                    showsLocation,
                    showsTeacher,
                )
            }
        }

        val hiddenCount = (content.courses.size - rows.count { !it.isTomorrow }).coerceAtLeast(0)
        root.findViewById<TextView>(R.id.widget_more_courses).apply {
            visibility = if (hiddenCount > 0) View.VISIBLE else View.GONE
            if (hiddenCount > 0) {
                text = context.getString(R.string.widget_more_courses_format, hiddenCount)
            }
        }
        root.contentDescription = context.getString(
            R.string.widget_preview_accessibility_format,
            UiText.widgetContext(context, content.contextText) + "; " + rows.joinToString("; ") {
                UiText.widgetCourseTitle(context, TodayCourseWidgetLogic.title(it, content))
            },
            rows.size,
        )
    }
}

class TodayCourseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetID ->
            update(context, appWidgetManager, appWidgetID)
        }
        scheduleMidnightRefresh(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in refreshActions) refresh(context)
    }

    override fun onDisabled(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(midnightPendingIntent(context))
    }

    companion object {
        private const val MIDNIGHT_REFRESH = "com.nemoyu.wheretostudy.nativeapp.WIDGET_MIDNIGHT_REFRESH"
        private val refreshActions = setOf(
            MIDNIGHT_REFRESH,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )

        fun refresh(context: Context) {
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext)
            val provider = ComponentName(appContext, TodayCourseWidgetProvider::class.java)
            manager.getAppWidgetIds(provider).forEach { widgetID ->
                update(appContext, manager, widgetID)
            }
            scheduleMidnightRefresh(appContext)
        }

        private fun midnightPendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, TodayCourseWidgetProvider::class.java).setAction(MIDNIGHT_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun scheduleMidnightRefresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            if (manager.getAppWidgetIds(ComponentName(context, TodayCourseWidgetProvider::class.java)).isEmpty()) return
            // Inexact, local-only refresh also handles devices whose system date is not Beijing's date.
            context.getSystemService(AlarmManager::class.java).set(
                AlarmManager.RTC, TodayCourseWidgetLogic.nextMidnightAt(System.currentTimeMillis()), midnightPendingIntent(context),
            )
        }

        private fun update(
            context: Context,
            manager: AppWidgetManager,
            widgetID: Int,
        ) {
            val preferences = AppPreferences(context)
            val schedule = loadUsableSchedule(context)
            val content = TodayCourseWidgetLogic.content(schedule, System.currentTimeMillis())
            val options = manager.getAppWidgetOptions(widgetID)
            val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val sizes = BundleCompat.getParcelableArrayList(options, AppWidgetManager.OPTION_APPWIDGET_SIZES, SizeF::class.java)
                    ?.filter { it.width > 0 && it.height > 0 }?.distinct()?.take(16)
                if (!sizes.isNullOrEmpty()) RemoteViews(sizes.associateWith { size ->
                    createRemoteViews(context, content, preferences, TodayCourseWidgetLogic.rowLimit(size.height.toInt()))
                }) else legacyRemoteViews(context, content, preferences, options)
            } else legacyRemoteViews(context, content, preferences, options)
            manager.updateAppWidget(widgetID, views)
        }

        private fun legacyRemoteViews(context: Context, content: TodayCourseWidgetContent, preferences: AppPreferences, options: Bundle): RemoteViews =
            RemoteViews(
                createRemoteViews(context, content, preferences, TodayCourseWidgetLogic.rowLimit(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT))),
                createRemoteViews(context, content, preferences, TodayCourseWidgetLogic.rowLimit(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT))),
            )

        internal fun createRemoteViews(context: Context, content: TodayCourseWidgetContent, preferences: AppPreferences, capacity: Int): RemoteViews {
            val localizedContext = AppLocale.wrap(context, preferences.languageCode)
            val views = RemoteViews(context.packageName, R.layout.widget_today_course)
            val colors = widgetThemeColors(context)
            val legacyTheme = ColorThemePreferences(context).load().preset == "default"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setColorStateList(R.id.widget_root, "setBackgroundTintList",
                    if (legacyTheme) null else ColorStateList.valueOf(colors.surface))
            } else if (legacyTheme) {
                views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_background)
            } else {
                views.setInt(R.id.widget_root, "setBackgroundColor", colors.surface)
            }
            widgetThemeIconIDs.forEach { id -> views.setInt(id, "setColorFilter", colors.primaryText) }
            widgetThemeAccentIDs.forEach { id -> views.setInt(id, "setBackgroundColor", colors.accent) }
            widgetThemeTextIDs.forEach { id -> views.setTextColor(id, colors.text) }
            widgetThemeMutedIDs.forEach { id -> views.setTextColor(id, colors.muted) }
            val rows = TodayCourseWidgetLogic.displayRows(content, capacity, preferences.widgetCourseLimit)

            views.setOnClickPendingIntent(R.id.widget_root, launchPendingIntent(context))
            views.setTextViewText(
                R.id.widget_course_count,
                widgetCountText(localizedContext, content, rows),
            )
            views.setTextViewText(
                R.id.widget_day_context,
                UiText.widgetContext(localizedContext, content.contextText),
            )
            views.setViewVisibility(
                R.id.widget_empty_state,
                if (rows.isEmpty()) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_courses,
                if (rows.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(
                R.id.widget_empty_text,
                localizedContext.uiText(content.emptyMessage),
            )

            widgetRowIDs.forEachIndexed { index, ids ->
                val row = rows.getOrNull(index)
                val course = row?.course
                views.setViewVisibility(ids.container, if (course == null) View.GONE else View.VISIBLE)
                if (course != null) {
                    views.setTextViewText(
                        ids.name,
                        UiText.widgetCourseTitle(
                            localizedContext,
                            TodayCourseWidgetLogic.title(row, content),
                        ),
                    )
                    views.setTextViewText(
                        ids.details,
                        TodayCourseWidgetLogic.details(
                            course,
                            preferences.widgetShowsLocation,
                            preferences.widgetShowsTeacher,
                        ),
                    )
                }
            }

            val hiddenCount = (content.courses.size - rows.count { !it.isTomorrow }).coerceAtLeast(0)
            views.setViewVisibility(
                R.id.widget_more_courses,
                if (hiddenCount > 0) View.VISIBLE else View.GONE,
            )
            if (hiddenCount > 0) {
                views.setTextViewText(
                    R.id.widget_more_courses,
                    localizedContext.getString(R.string.widget_more_courses_format, hiddenCount),
                )
            }
            return views
        }

        private fun launchPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
