package com.nemoyu.wheretostudy.nativeapp

import android.content.Context

/** Fixed application formats only; captured business values remain verbatim. */
internal object NativeUiFormats {
    private val rules = listOf(
        Regex("^学期：(.+)\$") to R.string.ui_format_semester,
        Regex("^平均学分绩点：(.+)\$") to R.string.ui_format_gpa,
        Regex("^(\\d+) 门课\$") to R.string.ui_format_courses,
        Regex("^(\\d+) 门\$") to R.string.ui_format_course_count,
        Regex("^收藏管理（(\\d+)）\$") to R.string.ui_format_favorites,
        Regex("^(\\d+) 条结果 · 按 DDL 时间升序\$") to R.string.ui_format_results,
        Regex("^今日安排 (\\d+) 个发车时刻 · (\\d+) 辆车\$") to R.string.ui_format_departures,
        Regex("^今日共 (\\d+) 个方向、(\\d+) 个计划班次\$") to R.string.ui_format_directions,
        Regex("^后勤部通知 · (.+)\$") to R.string.ui_format_notice,
        Regex("^(\\d{4}-\\d{2}-\\d{2}) 起\$") to R.string.ui_format_from,
        Regex("^下一班 (\\d{2}:\\d{2}) · (.+) → (.+)\$") to R.string.ui_format_next_departure,
        Regex("^数据更新时间：(.+)\$") to R.string.ui_format_updated,
        Regex("^自定义日程已保存：(.+)，(\\d+) 项\$") to R.string.ui_format_feed_saved,
        Regex("^自定义来源：(.+)\$") to R.string.ui_format_feed_source,
        Regex("^第 (.+) 节\$") to R.string.ui_format_period,
        Regex("^第(.+)节\$") to R.string.ui_format_period_compact,
        Regex("^第 (.+)-(.+) 节\$") to R.string.ui_format_periods,
        Regex("^(\\d+)\\n周\$") to R.string.ui_format_week_compact,
        Regex("^教学\\n第(\\d+)周\$") to R.string.ui_format_teaching_week_axis,
        Regex("^第(\\d+)教学周\$") to R.string.ui_format_teaching_week,
        Regex("^(.+) 第(\\d+)周\$") to R.string.ui_format_date_week,
        Regex("^(.+) 第(\\d+)教学周\$") to R.string.ui_format_date_teaching_week,
        Regex("^查看全部 (\\d+) 门课程\$") to R.string.ui_format_view_courses,
        Regex("^当日课程（(\\d+)）\$") to R.string.ui_format_day_courses,
        Regex("^已同步 (\\d+) 条课程到系统日历。\$") to R.string.ui_format_calendar_synced,
        Regex("^已同步 (\\d+) 条收藏日程到「(.+)」\$") to R.string.ui_format_favorites_synced,
        Regex("^个人课表已更新，共 (\\d+) 门课程\$") to R.string.ui_format_schedule_updated,
        Regex("^今日课程 · (\\d+) 门\$") to R.string.ui_format_today_courses,
        Regex("^Where To Study  (.+)\\n北邮课表与空教室查询的独立非官方客户端，不由北京邮电大学运营。\$") to R.string.ui_format_about,
        Regex("^已同步 (\\d+) 条课程到「(.+)」（新增 (\\d+)，更新 (\\d+).*）\$") to R.string.ui_format_calendar_upsert,
        Regex("^\\+?(\\d+) 周\$") to R.string.ui_format_weeks,
        Regex("^进行中 · (.+) 下课\$") to R.string.ui_format_ending,
        Regex("^公历 (\\d+)\\n教学 (\\d+|—)\$") to R.string.ui_format_week_axis,
        Regex("^公历第(\\d+)周，第(\\d+)教学周\$") to R.string.ui_format_calendar_teaching_week,
        Regex("^公历第(\\d+)周，暂无教学周信息\$") to R.string.ui_format_calendar_week_unknown,
        Regex("^公历第(\\d+)周\$") to R.string.ui_format_calendar_week,
        Regex("^教学第(\\d+)周\$") to R.string.ui_format_widget_teaching_week,
        Regex("^(\\d{2}:\\d{2}) 下课\$") to R.string.ui_format_ends_at,
        Regex("^第(\\d+)周\$") to R.string.ui_format_week,
    )

    fun resolve(context: Context, source: String): String? {
        for ((pattern, resource) in rules) {
            val match = pattern.matchEntire(source) ?: continue
            val values = match.groupValues.drop(1).toMutableList()
            if (resource == R.string.ui_format_date_week || resource == R.string.ui_format_date_teaching_week)
                values[0] = UiText.dateText(context, values[0]) ?: values[0]
            return context.getString(resource, *values.toTypedArray())
        }
        return null
    }
}
