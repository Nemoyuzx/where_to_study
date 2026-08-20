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
import java.util.Calendar
import java.util.TimeZone

data class TodayCourseWidgetContent(
    val courses: List<Course>,
) {
    val emptyMessage: String
        get() = "今日无课"
}

object TodayCourseWidgetLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun content(schedule: ScheduleSnapshot?, nowMillis: Long): TodayCourseWidgetContent {
        val target = Calendar.getInstance(shanghai).apply { timeInMillis = nowMillis }
        return TodayCourseWidgetContent(ScheduleLogic.courses(schedule, target))
    }

    fun details(course: Course, showsLocation: Boolean = true): String = listOfNotNull(
        course.timeRange,
        course.room.takeIf { showsLocation },
    )
        .filter(String::isNotBlank)
        .joinToString(" · ")
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
        private val rowIDs = listOf(
            Triple(R.id.widget_course_1, R.id.widget_course_name_1, R.id.widget_course_details_1),
            Triple(R.id.widget_course_2, R.id.widget_course_name_2, R.id.widget_course_details_2),
            Triple(R.id.widget_course_3, R.id.widget_course_name_3, R.id.widget_course_details_3),
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
            val schedule = runCatching { ScheduleStore(context).load() }.getOrNull()
            val content = TodayCourseWidgetLogic.content(schedule, System.currentTimeMillis())
            val preferences = AppPreferences(context)
            val views = RemoteViews(context.packageName, R.layout.widget_today_course)
            val rowLimit = minOf(
                rowLimit(manager.getAppWidgetOptions(widgetID)),
                preferences.widgetCourseLimit,
            )

            views.setOnClickPendingIntent(R.id.widget_root, launchPendingIntent(context))
            views.setTextViewText(
                R.id.widget_course_count,
                if (content.courses.isEmpty()) "" else context.getString(
                    R.string.widget_course_count_format,
                    content.courses.size,
                ),
            )
            views.setViewVisibility(
                R.id.widget_empty_state,
                if (content.courses.isEmpty()) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_courses,
                if (content.courses.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_empty_text, content.emptyMessage)

            rowIDs.forEachIndexed { index, (containerID, nameID, detailsID) ->
                val course = content.courses.getOrNull(index).takeIf { index < rowLimit }
                views.setViewVisibility(containerID, if (course == null) View.GONE else View.VISIBLE)
                if (course != null) {
                    views.setTextViewText(nameID, course.name)
                    views.setTextViewText(
                        detailsID,
                        TodayCourseWidgetLogic.details(course, preferences.widgetShowsLocation),
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
                    context.getString(R.string.widget_more_courses_format, hiddenCount),
                )
            }
            manager.updateAppWidget(widgetID, views)
        }

        private fun rowLimit(options: Bundle): Int {
            val minimumHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            return if (minimumHeight in 1..129) 2 else 3
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
