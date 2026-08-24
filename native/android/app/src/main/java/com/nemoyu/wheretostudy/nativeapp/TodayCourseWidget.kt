package com.nemoyu.wheretostudy.nativeapp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

enum class WidgetCoursePhase {
    UPCOMING,
    IN_PROGRESS,
    FINISHED,
}

data class TodayCourseWidgetContent(
    val courses: List<Course>,
    val dateContext: String,
    val statusText: String,
    val highlightedCourseID: String?,
    val highlightedCoursePhase: WidgetCoursePhase?,
) {
    val emptyMessage: String
        get() = "今日无课"

    val contextText: String
        get() = listOf(dateContext, statusText)
            .filter(String::isNotBlank)
            .joinToString(" · ")
}

object TodayCourseWidgetLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val weekdays = listOf("周日", "周一", "周二", "周三", "周四", "周五", "周六")

    fun content(schedule: ScheduleSnapshot?, nowMillis: Long): TodayCourseWidgetContent {
        val target = Calendar.getInstance(shanghai).apply { timeInMillis = nowMillis }
        val courses = ScheduleLogic.courses(schedule, target)
        val week = ScheduleLogic.weekNumber(schedule, target)
        val highlighted = highlightedCourse(courses, target)
        return TodayCourseWidgetContent(
            courses = courses,
            dateContext = dateContext(target, week),
            statusText = statusText(courses, target),
            highlightedCourseID = highlighted?.first?.id,
            highlightedCoursePhase = highlighted?.second,
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
                    weekday = weekday,
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
                    weekday = weekday,
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
                    weekday = weekday,
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
        weekNumbers = listOf(1),
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

object TodayCourseWidgetPreviewBinder {
    fun bind(
        root: View,
        content: TodayCourseWidgetContent,
        showsLocation: Boolean,
        showsTeacher: Boolean,
        rowLimit: Int,
    ) {
        val context = root.context
        root.findViewById<TextView>(R.id.widget_course_count).text = if (content.courses.isEmpty()) {
            ""
        } else {
            context.getString(R.string.widget_course_count_format, content.courses.size)
        }
        root.findViewById<TextView>(R.id.widget_day_context).text =
            UiText.widgetContext(context, content.contextText)
        root.findViewById<TextView>(R.id.widget_empty_text).text = context.uiText(content.emptyMessage)
        root.findViewById<View>(R.id.widget_empty_state).visibility =
            if (content.courses.isEmpty()) View.VISIBLE else View.GONE
        root.findViewById<View>(R.id.widget_courses).visibility =
            if (content.courses.isEmpty()) View.GONE else View.VISIBLE

        val normalizedLimit = rowLimit.coerceIn(1, widgetRowIDs.size)
        widgetRowIDs.forEachIndexed { index, ids ->
            val course = content.courses.getOrNull(index).takeIf { index < normalizedLimit }
            root.findViewById<View>(ids.container).visibility =
                if (course == null) View.GONE else View.VISIBLE
            if (course != null) {
                root.findViewById<TextView>(ids.name).text =
                    UiText.widgetCourseTitle(context, TodayCourseWidgetLogic.title(course, content))
                root.findViewById<TextView>(ids.details).text = TodayCourseWidgetLogic.details(
                    course,
                    showsLocation,
                    showsTeacher,
                )
            }
        }

        val hiddenCount = (content.courses.size - normalizedLimit).coerceAtLeast(0)
        root.findViewById<TextView>(R.id.widget_more_courses).apply {
            visibility = if (hiddenCount > 0) View.VISIBLE else View.GONE
            if (hiddenCount > 0) {
                text = context.getString(R.string.widget_more_courses_format, hiddenCount)
            }
        }
        root.contentDescription = context.getString(
            R.string.widget_preview_accessibility_format,
            content.contextText,
            content.courses.size,
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

    companion object {
        private val refreshActions = setOf(
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
        }

        private fun update(
            context: Context,
            manager: AppWidgetManager,
            widgetID: Int,
        ) {
            val preferences = AppPreferences(context)
            val schedule = loadUsableSchedule(context)
            val content = TodayCourseWidgetLogic.content(schedule, System.currentTimeMillis())
            val localizedContext = AppLocale.wrap(context, preferences.languageCode)
            val views = RemoteViews(context.packageName, R.layout.widget_today_course)
            val rowLimit = minOf(
                TodayCourseWidgetLogic.rowLimit(
                    manager.getAppWidgetOptions(widgetID)
                        .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT),
                ),
                preferences.widgetCourseLimit,
            )

            views.setOnClickPendingIntent(R.id.widget_root, launchPendingIntent(context))
            views.setTextViewText(
                R.id.widget_course_count,
                if (content.courses.isEmpty()) "" else localizedContext.getString(
                    R.string.widget_course_count_format,
                    content.courses.size,
                ),
            )
            views.setTextViewText(
                R.id.widget_day_context,
                UiText.widgetContext(localizedContext, content.contextText),
            )
            views.setViewVisibility(
                R.id.widget_empty_state,
                if (content.courses.isEmpty()) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_courses,
                if (content.courses.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(
                R.id.widget_empty_text,
                localizedContext.uiText(content.emptyMessage),
            )

            widgetRowIDs.forEachIndexed { index, ids ->
                val course = content.courses.getOrNull(index).takeIf { index < rowLimit }
                views.setViewVisibility(ids.container, if (course == null) View.GONE else View.VISIBLE)
                if (course != null) {
                    views.setTextViewText(
                        ids.name,
                        UiText.widgetCourseTitle(
                            localizedContext,
                            TodayCourseWidgetLogic.title(course, content),
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

            val hiddenCount = (content.courses.size - rowLimit).coerceAtLeast(0)
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
            manager.updateAppWidget(widgetID, views)
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
