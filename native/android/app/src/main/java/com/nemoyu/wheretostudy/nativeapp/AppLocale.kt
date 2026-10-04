package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.app.Dialog
import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.LocaleList
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.EditText
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

enum class AppLanguage(val code: String, val nativeName: String) {
    SYSTEM("system", "跟随系统"),
    SIMPLIFIED_CHINESE("zh-Hans", "简体中文"),
    TRADITIONAL_CHINESE("zh-Hant", "繁體中文"),
    ENGLISH("en", "English"),
    JAPANESE("ja", "日本語"),
    SPANISH("es", "Español"),
    PORTUGUESE("pt", "Português"),
    ARABIC("ar", "العربية"),
    RUSSIAN("ru", "Русский"),
    TURKISH("tr", "Türkçe"),
    THAI("th", "ไทย"),
    MALAY("ms", "Bahasa Melayu"),
    VIETNAMESE("vi", "Tiếng Việt"),
    INDONESIAN("id", "Bahasa Indonesia");

    companion object {
        fun fromCode(value: String): AppLanguage? =
            if (value.equals(SYSTEM.code, ignoreCase = true)) SYSTEM
            else fromLocale(Locale.forLanguageTag(value.replace('_', '-')))

        fun fromLocale(locale: Locale): AppLanguage? = when (locale.language.lowercase(Locale.ROOT)) {
            "zh" -> when {
                locale.script.equals("Hans", ignoreCase = true) -> SIMPLIFIED_CHINESE
                locale.script.equals("Hant", ignoreCase = true) -> TRADITIONAL_CHINESE
                locale.country.uppercase(Locale.ROOT) in setOf("TW", "HK", "MO") -> TRADITIONAL_CHINESE
                else -> SIMPLIFIED_CHINESE
            }
            "in", "id" -> INDONESIAN
            else -> entries.firstOrNull { it != SYSTEM && it.code == locale.language }
        }
    }
}

object AppTypography {
    const val oneStepSmallerScale = 0.92f

    fun adjustedFontScale(systemFontScale: Float): Float =
        systemFontScale * oneStepSmallerScale
}

object AppLocale {
    fun wrap(base: Context, languageCode: String): Context {
        val language = AppLanguage.fromCode(languageCode) ?: AppLanguage.SYSTEM
        val systemLocales = Resources.getSystem().configuration.locales
        val systemLocale = preferredSupportedLocale((0 until systemLocales.size()).map(systemLocales::get))
        val locale = resolvedLocale(language, systemLocale)
        // Localize the resource Context, not the process-wide default used by
        // unrelated API/data code. Contract dates and numbers remain unchanged.
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(locale)
            setLocales(LocaleList(locale))
            fontScale = AppTypography.adjustedFontScale(base.resources.configuration.fontScale)
        }
        return base.createConfigurationContext(configuration)
    }

    fun isEnglish(context: Context): Boolean {
        return resolvedLanguage(context) == AppLanguage.ENGLISH
    }

    fun resolvedLanguage(context: Context): AppLanguage =
        AppLanguage.fromLocale(context.resources.configuration.locales[0]) ?: AppLanguage.ENGLISH

    fun displayLocale(context: Context): Locale = context.resources.configuration.locales[0]

    fun calendarLocale(context: Context): Locale = Locale.Builder().setLocale(displayLocale(context))
        .setUnicodeLocaleKeyword("ca", "gregory").build()

    fun weekdayLabels(context: Context): List<String> {
        val symbols = android.icu.text.DateFormatSymbols(calendarLocale(context))
            .getWeekdays(android.icu.text.DateFormatSymbols.FORMAT, android.icu.text.DateFormatSymbols.NARROW)
        return listOf(Calendar.MONDAY, Calendar.TUESDAY, Calendar.WEDNESDAY, Calendar.THURSDAY,
            Calendar.FRIDAY, Calendar.SATURDAY, Calendar.SUNDAY).map { symbols[it] }
    }

    fun monthDayPattern(context: Context, includesWeekday: Boolean = false): String = when {
        isChinese(context) -> if (includesWeekday) "M月d日 EEEE" else "M月d日"
        isEnglish(context) -> if (includesWeekday) "MMM d, EEEE" else "MMM d"
        else -> android.text.format.DateFormat.getBestDateTimePattern(calendarLocale(context),
            if (includesWeekday) "MMMEd" else "MMMd")
    }

    fun isChinese(context: Context): Boolean = resolvedLanguage(context) in
        setOf(AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.TRADITIONAL_CHINESE)

    fun displayName(context: Context, language: AppLanguage): String =
        if (language == AppLanguage.SYSTEM) UiText.resolve(context, "跟随系统") else language.nativeName

    fun preferredSupportedLocale(locales: List<Locale>): Locale =
        locales.firstOrNull { AppLanguage.fromLocale(it) != null } ?: Locale.US

    fun resolvedLocale(language: AppLanguage, systemLocale: Locale): Locale = when (language) {
        AppLanguage.ENGLISH -> Locale.US
        AppLanguage.SYSTEM -> AppLanguage.fromLocale(systemLocale)?.let { supported ->
            Locale.Builder().setLocale(systemLocale).apply {
                if (supported == AppLanguage.SIMPLIFIED_CHINESE) setScript("Hans")
                if (supported == AppLanguage.TRADITIONAL_CHINESE) setScript("Hant")
            }.build()
        } ?: Locale.US
        else -> Locale.forLanguageTag(language.code)
    }
}

/**
 * Programmatic native screens historically used inline Chinese strings. This
 * central catalog localizes only known application chrome and anchored format
 * strings. Unknown course, assignment, contest and API text is returned
 * verbatim, which prevents third-party content from being mistranslated.
 */
object UiText {
    private val exactEnglish = mapOf(
        "空教室" to "Empty Classrooms",
        "教学日历" to "Teaching Calendar",
        "设置" to "Settings",
        "查询" to "Query",
        "课程" to "Courses",
        "当前课程" to "Current Courses",
        "我的课程" to "My Courses",
        "教学云平台当前课程接口格式不正确。" to "The Teaching Cloud Platform current-course response has an unsupported format.",
        "课程获取失败。" to "Unable to load courses.",
        "QMplus 同步失败；保留上次课程缓存。" to "QMplus sync failed; the previous course cache is retained.",
        "QMplus 同步或保存失败；保留上次课程缓存。" to "QMplus sync or save failed; the previous course cache is retained.",
        "无法读取 QMplus 课程缓存。" to "Unable to read the QMplus course cache.",
        "无法保存 QMplus 会话清除状态。" to "Unable to save the QMplus session-clear status.",
        "QMplus 网页会话尚未清除；再次连接前会先清除旧会话。" to "QMplus web session not cleared; it will be cleared before reconnecting.",
        "校区班车与重要事件" to "Campus Shuttles and Important Events",
        "班车与重要事件查询" to "Shuttles & Important Events",
        "班车查询" to "Shuttle Search",
        "信息查询" to "Information Search",
        "重要事件" to "Important Events",
        "成绩查询" to "Grades",
        "考试查询" to "Exams",
        "课程作业" to "Assignments",
        "刷新课程作业" to "Refresh Assignments",
        "刷新课表与考试" to "Refresh Schedule and Exams",
        "教学云平台 · 课程作业" to "Teaching Cloud Platform · Assignments",
        "暂无课程作业 DDL" to "No assignment deadlines",
        "课程未标注" to "Course not specified",
        "正在获取课程作业…" to "Loading assignments…",
        "点击刷新课程作业获取 DDL；使用设置中已保存的教学云平台密码。" to "Refresh assignments to load deadlines using the Teaching Cloud Platform password saved in Settings.",
        "点击刷新成绩获取学校已公布的成绩。" to "Refresh grades to load results published by the university.",
        "成绩" to "Grade",
        "学分" to "Credits",
        "未公布" to "Not published",
        "考试" to "Exam",
        "考试安排" to "Exam Arrangements",
        "日期待定" to "Date to be announced",
        "时间待定" to "Time to be announced",
        "考试时间待定" to "Exam time to be announced",
        "全部学期" to "All semesters",
        "当前学期" to "Current semester",
        "选择学期" to "Select Semester",
        "最好成绩" to "Best grades",
        "首次成绩" to "First attempts",
        "全部记录" to "All attempts",
        "成绩记录" to "Grade Records",
        "刷新成绩" to "Refresh Grades",
        "正在获取成绩…" to "Loading grades…",
        "前往账号设置" to "Open Account Settings",
        "前往个人账户" to "Open Personal Account",
        "请先在个人账户中保存教务账号和密码。" to "Save your academic account and password in Personal Account first.",
        "打开教学云平台" to "Open Teaching Cloud Platform",
        "Contest DDL 较新镜像数据" to "Newer Contest DDL mirror data",
        "Contest DDL 备用 API" to "Contest DDL backup API",
        "第三方来源：Contest DDL 主源、较新镜像及备用 API；校内竞赛通知另行获取，不包含课程作业" to "Third-party sources: Contest DDL primary, newer mirror, and backup API. Campus contest notices are fetched separately; assignments are excluded.",
        "本次使用 Contest DDL 镜像数据" to "Using Contest DDL mirror data",
        "本次使用备用 API" to "Using backup API",
        "主数据：Contest DDL" to "Primary data: Contest DDL",
        "备用 API" to "Backup API",
        "较新镜像数据" to "Newer mirror data",
        "请先在设置中保存教务账号和密码，再查询成绩。" to "Save your academic account and password in Settings to view grades.",
        "成绩来自学校教务系统，仅在本次使用期间保留。" to "Grades come from the university system and remain in memory for this session only.",
        "该学期暂无已公布成绩" to "No grades have been published for this semester.",
        "该学期暂无已公布成绩，可选择全部学期查看历史成绩。" to "No grades have been published for this semester. Select All semesters to view past grades.",
        "暂无已公布成绩" to "No grades have been published.",
        "成绩获取失败，请重试或检查账号设置。" to "Unable to fetch grades. Retry or check account settings.",
        "成绩刷新失败，正在显示本次使用中已获取的成绩。" to "Refresh failed. Showing grades fetched earlier in this session.",
        "本学期暂无考试安排" to "No exams are currently scheduled for this semester.",
        "部分考试日期或时间待定，请查看考试安排" to "Some exam dates or times are pending. Open Exam Arrangements for details.",
        "考试安排已同步" to "Exam arrangements are up to date.",
        "考试安排刷新失败，正在显示本账号本学期的缓存" to "Exam refresh failed. Showing this account's cached exams for this semester.",
        "考试安排获取失败，请重新刷新课表" to "Unable to fetch exams. Refresh your schedule to retry.",
        "尚未获取考试安排，请刷新课表" to "Exam arrangements have not been fetched. Refresh your schedule.",
        "返回" to "Back",
        "联动查询" to "Linked Search",
        "查询条件" to "Search Filters",
        "查询概览" to "Query Summary",
        "空教室结果" to "Available Classrooms",
        "教学楼" to "Building",
        "节次筛选" to "Period Filter",
        "选中空闲" to "Select Free",
        "清空" to "Clear",
        "个人空闲节次" to "My Free Periods",
        "使用个人课表排除已有课程" to "Exclude periods occupied by my schedule",
        "获取空教室信息" to "Fetch Classroom Data",
        "正在获取…" to "Fetching…",
        "正在恢复…" to "Restoring…",
        "正在删除…" to "Deleting…",
        "无法保存收藏日程。" to "Unable to save favorites.",
        "本地数据已清除，本次后台结果未保存。" to "Local data was cleared; this background result was not saved.",
        "正在获取当天空教室…" to "Fetching classrooms for today…",
        "正在获取当天空教室" to "Fetching classrooms for today",
        "当天空教室已更新" to "Classrooms for today updated",
        "当天空教室获取失败" to "Unable to fetch classrooms for today",
        "暂无本地空教室数据" to "No cached classroom data",
        "暂无教学楼，请先获取当天空教室" to "No buildings yet. Fetch today's classroom data first.",
        "未选择教学楼" to "No building selected",
        "未选择节次" to "No periods selected",
        "暂无匹配空教室" to "No matching classrooms",
        "匹配教室" to "Matching Classrooms",
        "今日与明日" to "Today and Tomorrow",
        "今日" to "Today",
        "明日" to "Tomorrow",
        "转" to " to ",
        "今天" to "Today",
        "今日无课" to "No courses today",
        "今天可以自由安排" to "No courses scheduled today",
        "课程进行中" to "Course in progress",
        "进行中" to "In progress",
        "下一节" to "Next",
        "还有待上课程" to "More courses later today",
        "今日课程已结束" to "Today's courses are finished",
        "周一" to "Mon",
        "周二" to "Tue",
        "周三" to "Wed",
        "周四" to "Thu",
        "周五" to "Fri",
        "周六" to "Sat",
        "周日" to "Sun",
        "暂无天气数据" to "No weather data",
        "正在更新今日与明日天气…" to "Updating today's and tomorrow's weather…",
        "校区天气" to "Campus Weather",
        "校区天气，已展开，点击折叠" to "Campus weather, expanded; tap to collapse",
        "校区天气，已折叠，点击展开" to "Campus weather, collapsed; tap to expand",
        "课程、节次与法定节假日" to "Courses, periods, and public holidays",
        "日" to "Day",
        "周" to "Week",
        "星期一" to "Monday",
        "星期二" to "Tuesday",
        "星期三" to "Wednesday",
        "星期四" to "Thursday",
        "星期五" to "Friday",
        "星期六" to "Saturday",
        "星期日" to "Sunday",
        "月" to "Month",
        "年" to "Year",
        "今日时间轴" to "Today's Timeline",
        "本周时间轴" to "This Week's Timeline",
        "全天" to "All-day",
        "课程与全天  ⌃" to "Courses & All-day  ⌃",
        "课程与全天  ⌄" to "Courses & All-day  ⌄",
        "收起课程与全天事项" to "Collapse courses and all-day items",
        "展开课程与全天事项" to "Expand courses and all-day items",
        "收起当前日期课程" to "Collapse courses for the selected date",
        "展开当前日期课程" to "Expand courses for the selected date",
        "当日课程" to "Courses for This Day",
        "当日日程" to "Schedule for This Day",
        "暂无课程" to "No courses",
        "无课" to "No courses",
        "整点" to "Hour",
        "课程节次" to "Course Periods",
        "地点未标注" to "Location not specified",
        "教师未标注" to "Instructor not specified",
        "课程详情" to "Course Details",
        "日期" to "Date",
        "类型" to "Type",
        "法定节假日" to "Public holiday",
        "调休工作日" to "Adjusted workday",
        "时间" to "Time",
        "节次" to "Periods",
        "地点" to "Location",
        "教师" to "Instructor",
        "教学周" to "Teaching Weeks",
        "暂无教学周信息" to "Teaching week unavailable",
        "未标注" to "Not specified",
        "关闭" to "Close",
        "完成" to "Done",
        "导入手机日历" to "Import to Device Calendar",
        "导入已收藏日程" to "Import Favorite Events",
        "将把当前收藏的完整日程快照同步到系统日历；重复导入会更新已有项。是否继续？" to
            "Sync the complete snapshots of current favorites to the system calendar. Re-importing updates existing events. Continue?",
        "收藏日程导入失败。" to "Favorite-event import failed.",
        "更多日历操作" to "More calendar actions",
        "正在导入…" to "Importing…",
        "确认导入" to "Confirm Import",
        "取消" to "Cancel",
        "跳转到" to "Open in",
        "颜色越深表示当天课程越多" to "Darker colors indicate more courses",
        "颜色越深表示当天课程越多，彩色边框表示作业与 DDL" to
            "Darker colors indicate more courses; colored borders indicate assignments and DDLs",
        "全天日程" to "All-day Schedule",
        "月视图日程" to "Month Schedule",
        "打开月视图全天日程" to "Open month all-day schedule",
        "周视图全天日程弹窗" to "Week all-day schedule dialog",
        "日视图全天日程弹窗" to "Day all-day schedule dialog",
        "收起月历并显示当日日程" to "Collapse month and show day details",
        "展开月历" to "Expand month",
        "显示完整月份" to "Show full month",
        "月历，已展开" to "Month, expanded",
        "月历与当日日程" to "Month and day details",
        "选中周与当日日程" to "Selected week and day details",
        "课程作业 DDL" to "Assignment DDL",
        "当天暂无课程作业 DDL" to "No assignment deadlines on this day",
        "正在同步云课堂作业…" to "Syncing UCloud assignments…",
        "课程名称未标注" to "Course name not specified",
        "打开作业列表" to "Open Assignment List",
        "黄历信息" to "Almanac",
        "正在查询黄历…" to "Loading almanac…",
        "活动 DDL" to "Event DDL",
        "正在同步竞赛、夏令营与黑客松…" to "Syncing competitions, summer camps, and hackathons…",
        "当天没有已收录的活动截止事项" to "No recorded event deadlines on this day",
        "正在同步作业与校内竞赛通知…" to "Syncing assignments and campus contest notices…",
        "正在同步作业与活动 DDL…" to "Syncing assignments and event DDLs…",
        "作" to "HW",
        "校" to "Campus",
        "公" to "Public",
        "赛" to "Competition",
        "营" to "Camp",
        "黑" to "Hackathon",
        "休" to "Off",
        "班" to "Work",
        "宜" to "Good for",
        "忌" to "Avoid",
        "个人账户" to "Account",
        "教务账号" to "Academic Account",
        "仅删除这一次" to "Delete This Occurrence",
        "删除本学期整门课程" to "Delete This Course for the Term",
        "本学期所有教学周和上课时段" to "All teaching weeks and sessions in this term",
        "仅从本机个人课表中删除，可在设置的已删除课程中恢复。不会修改学校课表或已导出的系统日历。" to
            "Removes it from the personal timetable on this device. Restore it under Deleted Courses in Settings. The school timetable and previously exported system calendar stay unchanged.",
        "课程已删除，可在设置中恢复" to "Course deleted; restore it in Settings",
        "无法保存课程删除记录" to "Unable to save the course deletion",
        "已删除课程" to "Deleted Courses",
        "管理已删除课程" to "Manage Deleted Courses",
        "管理当前账号、本学期的本地删除记录。恢复后立即重新显示课程。" to "Manage local deletions for the current account and term. Restored courses reappear immediately.",
        "当前账号、本学期暂无课程删除记录" to "No deleted courses for the current account and term",
        "本学期整门课程" to "Entire course for this term",
        "恢复课程" to "Restore Course",
        "恢复" to "Restore",
        "删除" to "Delete",
        "将移除此条删除记录；其他删除记录仍然有效。" to "Removes this deletion record. Other deletion records still apply.",
        "课程删除记录已恢复" to "Selected deletion undone",
        "无法读取或保存课程删除记录" to "Unable to read or save course deletions",
        "课表已更新，请重新选择课程。" to "The timetable changed. Please select the course again.",
        "课程删除记录已更新，请重试。" to "Course deletions changed. Please try again.",
        "课表缺少学期编号，无法删除课程。" to "Cannot delete a course without a term identifier.",
        "课程删除记录格式不受支持。" to "Unsupported course deletion record format.",
        "无法清除课程删除记录。" to "Unable to clear course deletions.",
        "教务密码" to "Academic Password",
        "教学云平台密码（可选）" to "Teaching Cloud Platform Password (Optional)",
        "使用教务密码" to "Use Academic Password",
        "改用教务密码" to "Use Academic Password Instead",
        "用于移动教务登录和查询课表、成绩及考试安排；可能与统一身份认证密码不同。部分账号的初始密码可能是八位出生日期（YYYYMMDD），请以本人实际设置为准。" to "Used to sign in to mobile academic services for timetables, grades and exams. It may differ from your unified identity password. For some accounts, the initial password may be the eight-digit birth date (YYYYMMDD); use your actual account settings.",
        "用于课程作业 DDL 查询，通常是统一身份认证密码；未单独设置时使用教务密码。已保存的独立密码留空不变；修改后请保存设置。" to "Used for assignment deadlines and usually matches the unified identity password. If unset, the academic password is used. Leave a saved separate password blank to keep it; save settings after making changes.",
        "保存后使用独立教学云平台密码获取作业 DDL" to "After saving, assignments use the separate Teaching Cloud Platform password",
        "保存后使用教务密码获取作业 DDL" to "After saving, assignments use the academic password",
        "教学云平台密码已安全保存，留空保持不变" to "Teaching Cloud Platform password saved securely; leave blank to keep it",
        "仅用于课程作业 DDL；未设置时使用教务密码" to "Used only for assignment deadlines; defaults to the academic password",
        "密码" to "Password",
        "默认校区" to "Default Campus",
        "西土城" to "Xitucheng",
        "沙河" to "Shahe",
        "保存设置" to "Save Settings",
        "学期设置" to "Semester",
        "自动检测当前学期" to "Detect Current Semester Automatically",
        "学期编号" to "Semester ID",
        "第一周周一（YYYY-MM-DD）" to "Monday of Week 1 (YYYY-MM-DD)",
        "保存学期设置" to "Save Semester",
        "启动或获取/刷新课表后，会自动应用教务返回的学期与开学日期。" to "At launch or after a schedule refresh, the semester and start date returned by Academic Affairs are applied automatically.",
        "关闭自动检测后，将使用手动填写的学期信息。" to "When automatic detection is off, the manually entered semester details are used.",
        "获取/刷新个人课表" to "Fetch / Refresh My Schedule",
        "课程提醒" to "Course Reminders",
        "每日课程摘要已开启" to "Daily course summary enabled",
        "每日课程摘要已关闭" to "Daily course summary disabled",
        "每日课程摘要" to "Daily Course Summary",
        "每天约 07:30 显示当天个人课程摘要" to "Shows your course summary each day at about 07:30",
        "通知权限未开启，无法启用课程摘要" to "Notification permission is required for the course summary",
        "桌面小组件" to "Home-screen Widget",
        "日期详情与生活信息" to "Date Details & Daily Information",
        "黄历与宜忌" to "Almanac and Advice",
        "学科竞赛 DDL" to "Competition DDL",
        "学科竞赛" to "Competition",
        "学术会议 DDL" to "Conference DDL",
        "学术会议" to "Conference",
        "期刊专题 DDL" to "Journal Special Issue DDL",
        "期刊专题" to "Journal Special Issue",
        "校内竞赛通知" to "Campus Contest Notices",
        "夏令营 DDL" to "Summer Camp DDL",
        "夏令营" to "Summer Camp",
        "黑客松 DDL" to "Hackathon DDL",
        "黑客松" to "Hackathon",
        "预推免 DDL" to "Pre-admission DDL",
        "预推免" to "Pre-admission",
        "今日班车状态" to "Today's Shuttle Status",
        "今日暂无生效班车时刻表" to "No active shuttle timetable today",
        "今日没有计划班次" to "No departures scheduled today",
        "今日班车按时刻表运行" to "Today's shuttles follow the timetable",
        "完整班车时刻表" to "Full Shuttle Timetable",
        "当前生效" to "Active now",
        "即将生效" to "Upcoming",
        "已结束时段" to "Past period",
        "时段待确认" to "Period unconfirmed",
        "日期待确认" to "Dates unconfirmed",
        "截至" to "Until",
        "起" to "onward",
        "法定节假日，班车安排以学校通知为准" to "Public holiday: follow the university's shuttle notices",
        "无计划班次" to "No scheduled departures",
        "今日为法定节假日，班车不一定运行；请以学校放假安排为准，放假期间无班车。" to "Today is a public holiday. Shuttles may not run; follow the university's holiday schedule. There is no shuttle service during the holiday break.",
        "当前展示最近一次成功同步的缓存" to "Showing the latest successfully synced cache",
        "刷新班车信息" to "Refresh shuttle information",
        "查看班车通知原文" to "View the original shuttle notice",
        "查看数据来源" to "View data source",
        "第三方来源：北京邮电大学后勤部公开通知，由 Where To Study 服务解析整理，仅供参考，请以官方原文为准。" to "Third-party source: public BUPT Logistics notices, structured by Where To Study for reference only. Please rely on the official notice.",
        "下一班" to "Next departure",
        "候车地点" to "Pickup Locations",
        "乘车提示" to "Rider Notes",
        "未找到当前生效的班车时刻表" to "No currently effective shuttle timetable found",
        "今日暂无已安排班车" to "No shuttle service scheduled today",
        "今日班车已结束" to "Today's shuttle service has ended",
        "当前显示上一次有效缓存，服务正在恢复。" to "Showing the last valid cache while the service recovers.",
        "当前没有可安全展示的生效时刻表，请查看学校原通知。" to "No verified active timetable is available; check the official notice.",
        "今日该方向无班车" to "No shuttle in this direction today",
        "正在获取今日班车与当前时刻表…" to "Loading today's shuttle status and active timetable…",
        "搜索名称、主办方或分类" to "Search name, organizer, or category",
        "全部" to "All",
        "校内通知" to "Campus Notices",
        "显示已结束" to "Show ended",
        "分类" to "Category",
        "全部分类" to "All Categories",
        "适用对象" to "Eligibility",
        "备注" to "Notes",
        "已归档" to "Archived",
        "加载更多" to "Load More",
        "暂无符合条件的重要事件" to "No important events match these filters",
        "正在同步公开活动与校内竞赛通知…" to "Syncing public events and campus contest notices…",
        "点击重试" to "Tap to retry",
        "第三方来源：Contest DDL 与校内竞赛通知公开接口；不包含课程作业" to "Third-party sources: Contest DDL and the public campus-notice API; assignments are excluded",
        "第三方来源：北京邮电大学后勤部公开通知；时刻表由脚本解析，仅供参考" to "Third-party source: public BUPT Logistics notices; timetables are script-parsed and for reference only",
        "自定义日程" to "Custom Schedule",
        "自定义日程源" to "Custom Schedule Feed",
        "自定义日程 HTTPS JSON 地址" to "Custom schedule HTTPS JSON URL",
        "校验并保存自定义日程" to "Validate & Save Custom Feed",
        "正在校验自定义日程…" to "Validating custom feed…",
        "请先填写自定义日程 HTTPS 地址。" to "Enter a custom schedule HTTPS URL first.",
        "自定义日程地址格式不正确。" to "The custom schedule URL is invalid.",
        "自定义日程校验失败。" to "Unable to validate the custom schedule feed.",
        "收藏管理" to "Favorite Management",
        "暂无收藏日程" to "No favorite schedules",
        "返回设置" to "Back to Settings",
        "收藏日程" to "Favorite Schedule",
        "取消收藏" to "Remove Favorite",
        "打开原文" to "Open Original",
        "收藏快照在来源关闭、失效或删除后仍会保留" to
            "Favorite snapshots remain after a source is disabled, unavailable, or removed",
        "只发送无凭据 GET；拒绝重定向、本机及私有/保留 IP，响应上限 2 MiB。" to
            "Uses credential-free GET only; redirects, localhost, and private/reserved IPs are rejected; responses are limited to 2 MiB.",
        "天气、黄历和 DDL 来自第三方公开服务；已收藏日程会保存完整快照，来源关闭、失败或删除后仍会显示，直到取消收藏。" to
            "Weather, almanac, and DDL data comes from public third-party services. Favorite schedules retain complete snapshots and remain visible until removed, even if a source is disabled, unavailable, or deleted.",
        "本地数据" to "Local Data",
        "清除本地数据" to "Clear Local Data",
        "关于本应用" to "About",
        "APP 备案：琼ICP备2026012322号-2A" to
            "App filing: 琼ICP备2026012322号-2A",
        "隐私说明" to "Privacy",
        "GitHub 项目主页" to "GitHub Project",
        "在 GitHub 查看完整隐私声明" to "View Full Privacy Policy on GitHub",
        "在 GitHub 查看完整声明 / Full policy on GitHub ↗" to "Full Policy on GitHub ↗",
        "隐私说明" to "Privacy",
        "隐私声明 / Privacy Policy" to "Privacy Policy",
        "账户与教务请求 / Account and academic requests" to "Account and Academic Requests",
        "云课堂作业 / UCloud assignments" to "UCloud Assignments",
        "节假日数据 / Holiday data" to "Holiday Data",
        "天气、黄历与公开活动 / Weather, almanac, and public events" to "Weather, Almanac, and Public Events",
        "系统日历、通知与小组件 / Calendar, notifications, and widgets" to "Calendar, Notifications, and Widgets",
        "本地数据 / Local data" to "Local Data",
        "不收集的数据与第三方元数据 / Data not collected and third-party metadata" to "Data Not Collected and Third-party Metadata",
        "保留与删除 / Retention and deletion" to "Retention and Deletion",
        "安全与联系 / Security and contact" to "Security and Contact",
        "个人课表、空教室缓存、节假日缓存、账号与偏好均只保存在本机。" to "Your schedule, classroom and holiday caches, account, and preferences stay on this device.",
        "显示课程地点" to "Show Course Locations",
        "显示任课教师" to "Show Instructors",
        "最多显示课程" to "Maximum Courses",
        "样式预览 · 示例内容" to "Style Preview · Sample Content",
        "小组件会显示日期、教学周、当前或下一节状态、节次、地点与教师；展开样式最多展示 6 门课程。预览使用虚构示例，不会写入课表。" to "The widget shows the date, teaching week, current or next-course status, periods, locations, and instructors. Expanded mode shows up to six courses. Preview data is fictional and is never written to your schedule.",
        "应用设置" to "App Settings",
        "语言" to "Language",
        "跟随系统" to "System",
        "简体中文" to "Chinese",
        "更改语言后将立即重新加载界面。" to "The interface reloads immediately after changing the language.",
        "显示数据仅供参考，请以实际情况为准。" to "Displayed data is for reference only; rely on official information.",
        "设置已保存" to "Settings saved",
        "正在获取…" to "Fetching…",
        "无法安全保存账户信息" to "Unable to save account information securely",
        "个人课表获取失败" to "Unable to fetch personal schedule",
        "无法保存学期设置" to "Unable to save semester settings",
        "本地数据已清除" to "Local data cleared",
        "清除全部本地数据？" to "Clear all local data?",
        "将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。" to "This removes the saved account, password, personal schedule, classroom cache, and settings. This cannot be undone.",
        "将删除保存的账号、密码、个人课表、空教室缓存、自定义日程地址、收藏和设置。此操作无法撤销。" to
            "This removes the saved account, password, personal schedule, classroom cache, custom feed URL, favorites, and settings. This cannot be undone.",
        "确认清除" to "Clear",
        "系统日历导入失败。" to "System calendar import failed.",
        "密码已安全保存，留空保持不变" to "Password saved securely; leave blank to keep it",
        "更换账号时请输入新密码" to "Enter the new password when changing accounts",
        "未选择" to "Not selected",
        "展开" to "Expanded",
        "标准" to "Standard",
        "紧凑" to "Compact",
        "展开导航栏" to "Expand Navigation",
        "收起导航栏" to "Collapse Navigation",
        "导航栏已展开" to "Navigation expanded",
        "导航栏已收起" to "Navigation collapsed",
        "无法打开链接" to "Unable to open link",
        "暂无本地课程，请在设置中获取/刷新个人课表" to "No local schedule. Fetch or refresh it in Settings.",
    )

    fun resolve(context: Context, source: String): String {
        if (source.isEmpty()) return source
        NativeUiTextCatalog.resolve(context, source)?.let { return it }
        if (AppLocale.resolvedLanguage(context) == AppLanguage.SIMPLIFIED_CHINESE) return source
        NativeUiFormats.resolve(context, source)?.let { return it }
        if (!AppLocale.isEnglish(context)) return dateText(context, source) ?: source
        exactEnglish[source]?.let { return it }
        Regex("^学期：(.+)$").matchEntire(source)?.let { return "Semester: ${resolve(context, it.groupValues[1])}" }
        Regex("^平均学分绩点：(.+)$").matchEntire(source)?.let { return "Average grade point: ${it.groupValues[1]}" }
        Regex("^(\\d+) 门课$").matchEntire(source)?.let { return "${it.groupValues[1]} courses" }
        Regex("^(\\d+) 门$").matchEntire(source)?.let { return "${it.groupValues[1]} courses" }
        Regex("^收藏管理（(\\d+)）$").matchEntire(source)?.let {
            return "Favorite Management (${it.groupValues[1]})"
        }
        Regex("^(\\d+) 条结果 · 按 DDL 时间升序$").matchEntire(source)?.let {
            return "${it.groupValues[1]} results · sorted by deadline"
        }
        Regex("^今日安排 (\\d+) 个发车时刻 · (\\d+) 辆车$").matchEntire(source)?.let {
            return "Today: ${it.groupValues[1]} departure times · ${it.groupValues[2]} vehicles"
        }
        Regex("^今日共 (\\d+) 个方向、(\\d+) 个计划班次$").matchEntire(source)?.let {
            return "Today: ${it.groupValues[1]} directions, ${it.groupValues[2]} scheduled departures"
        }
        Regex("^后勤部通知 · (.+)$").matchEntire(source)?.let {
            return "Logistics notice · ${it.groupValues[1]}"
        }
        Regex("^(\\d{4}-\\d{2}-\\d{2}) 起$").matchEntire(source)?.let {
            return "From ${it.groupValues[1]}"
        }
        Regex("^下一班 (\\d{2}:\\d{2}) · (.+) → (.+)$").matchEntire(source)?.let {
            return "Next ${it.groupValues[1]} · ${it.groupValues[2]} → ${it.groupValues[3]}"
        }
        Regex("^数据更新时间：(.+)$").matchEntire(source)?.let {
            return "Updated: ${it.groupValues[1]}"
        }
        Regex("^自定义日程已保存：(.+)，(\\d+) 项$").matchEntire(source)?.let {
            return "Custom feed saved: ${it.groupValues[1]}, ${it.groupValues[2]} items"
        }
        Regex("^自定义来源：(.+)$").matchEntire(source)?.let {
            return "Custom source: ${it.groupValues[1]}"
        }
        Regex("^第 (.+) 节$").matchEntire(source)?.let { return "Period ${it.groupValues[1]}" }
        Regex("^第(.+)节$").matchEntire(source)?.let { return "Period ${it.groupValues[1]}" }
        Regex("^第 (.+)-(.+) 节$").matchEntire(source)?.let {
            return "Periods ${it.groupValues[1]}–${it.groupValues[2]}"
        }
        Regex("^(\\d+)\\n周$").matchEntire(source)?.let { return "W${it.groupValues[1]}" }
        Regex("^教学\\n第(\\d+)周$").matchEntire(source)?.let {
            return "Teaching\\nWeek ${it.groupValues[1]}"
        }
        Regex("^第(\\d+)教学周$").matchEntire(source)?.let {
            return "Teaching Week ${it.groupValues[1]}"
        }
        Regex("^(.+) 第(\\d+)周$").matchEntire(source)?.let {
            return "${resolve(context, it.groupValues[1])} · Week ${it.groupValues[2]}"
        }
        Regex("^(.+) 第(\\d+)教学周$").matchEntire(source)?.let {
            return "${resolve(context, it.groupValues[1])} · Teaching Week ${it.groupValues[2]}"
        }
        Regex("^查看全部 (\\d+) 门课程$").matchEntire(source)?.let {
            return "View all ${it.groupValues[1]} courses"
        }
        Regex("^当日课程（(\\d+)）$").matchEntire(source)?.let {
            return "Courses for This Day (${it.groupValues[1]})"
        }
        Regex("^已同步 (\\d+) 条课程到系统日历。$").matchEntire(source)?.let {
            return "Synced ${it.groupValues[1]} courses to the system calendar."
        }
        Regex("^已同步 (\\d+) 条收藏日程到「(.+)」$").matchEntire(source)?.let {
            return "Synced ${it.groupValues[1]} favorite events to \"${it.groupValues[2]}\"."
        }
        Regex("^个人课表已更新，共 (\\d+) 门课程$").matchEntire(source)?.let {
            return "Personal schedule updated: ${it.groupValues[1]} courses"
        }
        Regex("^今日课程 · (\\d+) 门$").matchEntire(source)?.let {
            return "Today's Courses · ${it.groupValues[1]}"
        }
        Regex("^Where To Study  (.+)\\n北邮课表与空教室查询的独立非官方客户端，不由北京邮电大学运营。$")
            .matchEntire(source)?.let {
                return "Where To Study  ${it.groupValues[1]}\nIndependent unofficial BUPT schedule and classroom client; not operated by the university."
            }
        Regex("^已同步 (\\d+) 条课程到「(.+)」（新增 (\\d+)，更新 (\\d+).*）$")
            .matchEntire(source)?.let {
                return "Synced ${it.groupValues[1]} courses to \"${it.groupValues[2]}\" " +
                    "(${it.groupValues[3]} added, ${it.groupValues[4]} updated)."
            }
        Regex("^日期：(.+)\\n类型：(.+)$").matchEntire(source)?.let {
            val type = when (it.groupValues[2]) {
                "法定节假日" -> "Public holiday"
                "调休工作日" -> "Adjusted workday"
                else -> it.groupValues[2]
            }
            return "Date: ${it.groupValues[1]}\nType: $type"
        }
        if (source.startsWith("已清除其余本地数据；未能清除：")) {
            return "Other local data was cleared; unable to clear: " +
                source.removePrefix("已清除其余本地数据；未能清除：")
        }
        Regex("^\\+?(\\d+) 周$").matchEntire(source)?.let { return "${it.groupValues[1]} weeks" }
        if (source.startsWith("作 ")) return "HW ${source.removePrefix("作 ")}"
        if (source.startsWith("校 ")) return "Campus ${source.removePrefix("校 ")}"
        if (source.startsWith("作业 DDL · ")) return "Assignment DDL · ${source.removePrefix("作业 DDL · ")}"
        if (source.startsWith("校内竞赛 · ")) return "Campus Contest · ${source.removePrefix("校内竞赛 · ")}"
        if (source.startsWith("进行中 · ")) return "In progress · ${source.removePrefix("进行中 · ")}"
        if (source.startsWith("下一节 · ")) return "Next · ${source.removePrefix("下一节 · ")}"
        Regex("^进行中 · (.+) 下课$").matchEntire(source)?.let {
            return "In progress · ends at ${it.groupValues[1]}"
        }
        Regex("^公历 (\\d+)\\n教学 (\\d+|—)$").matchEntire(source)?.let {
            return "Calendar ${it.groupValues[1]}\nTeaching ${it.groupValues[2]}"
        }
        Regex("^公历第(\\d+)周，第(\\d+)教学周$").matchEntire(source)?.let {
            return "Calendar week ${it.groupValues[1]}, teaching week ${it.groupValues[2]}"
        }
        Regex("^公历第(\\d+)周，暂无教学周信息$").matchEntire(source)?.let {
            return "Calendar week ${it.groupValues[1]}, teaching week unavailable"
        }
        longPolicyText(source)?.let { return it }
        if (source.endsWith("，点击重试")) {
            return englishStatusFallback(source.removeSuffix("，点击重试")) +
                ", tap to retry"
        }
        dateText(context, source)?.let { return it }
        if (source.contains("；")) {
            return source.replace("；", "; ")
        }
        if (source.startsWith("正在") && source.endsWith("…")) return "Loading…"
        if (source.startsWith("暂无")) return "No data available"
        if (source.endsWith("失败") || source.endsWith("失败。") ||
            source.contains("无法") || source.contains("不可用") ||
            source.contains("格式不正确") || source.contains("不受支持") ||
            source.contains("不受信任") || source.contains("数量异常") ||
            source.contains("缺少来源") || source.contains("状态无效") ||
            source.contains("响应过大") || source.contains("返回错误")
        ) {
            return englishStatusFallback(source)
        }
        return source
    }

    private fun englishStatusFallback(source: String): String = when {
        source.contains("班车") -> "Unable to load shuttle information"
        source.contains("重要事件") -> "Unable to load important events"
        source.contains("天气") -> "Unable to load weather"
        source.contains("黄历") || source.contains("宜忌") -> "Unable to load almanac data"
        source.contains("DDL") || source.contains("竞赛") -> "Unable to load deadline data"
        source.contains("作业") || source.contains("云课堂") -> "Unable to load assignments"
        source.contains("课表") -> "Unable to load the personal schedule"
        source.contains("空教室") -> "Unable to load classroom data"
        source.contains("日历") -> "Unable to complete the calendar operation"
        else -> "Unable to complete the request"
    }

    private fun longPolicyText(source: String): String? = when {
        source.startsWith("Where To Study 是用于查看") ->
            "Where To Study is an independent, unofficial client for viewing BUPT schedules, empty classrooms, and related study information. It is not operated by or affiliated with the university."
        source.startsWith("学号和密码保存在") ->
            "Credentials stay in protected OS storage. With valid saved credentials and automatic term detection enabled, the app refreshes the personal schedule once at launch to verify the term identifier and first Monday. Credentials are also used over HTTPS for schedules, classrooms, or assignments you request. Schedule and classroom requests go to jwglweixin.bupt.edu.cn; supported platforms may refresh today’s classrooms automatically. The maintainer cannot read credentials, and settings APIs never return a password."
        source.startsWith("密码仅通过 HTTPS 提交") ->
            "The password is sent only to auth.bupt.edu.cn over HTTPS. An optional separate Teaching Cloud Platform password uses the same protected credential storage; otherwise the academic password is used. A one-time ticket is exchanged for an in-memory token used with apiucloud.bupt.edu.cn. Browser cookies are not read, and tickets, cookies, tokens, and assignments are not written to disk; results may be reused in memory for up to 10 minutes."
        source.startsWith("课表、空教室、校区") ->
            "Schedules, classroom data, campus, semester settings, switches, the custom feed URL, and up to 500 favorite snapshots remain on the device. Course widgets read only the local schedule. Course deletions are isolated by account and term, affect only this device, and can be restored in Settings. Clearing local data removes all of these items."
        source.startsWith("应用可能通过 unpkg") ->
            "The app may fetch a fixed holiday-calendar dataset from unpkg. Android may also read a system holiday calendar when permission already exists. Requests contain only CN and the year. iOS marks days off only from authoritative rest-day data."
        source.startsWith("UAPI 按校区行政区") ->
            "UAPI provides district-level weather and base almanac data without GPS. Timeless may add advice. Public events use Contest DDL on GitHub first; the where-to-study.cn mirror is selected only when its generated data is newer, and the existing API is a fallback if both fail. Campus contest notices have a separate source. These public requests carry no personal credentials. Custom schedules use credential-free GET requests only to the user-provided HTTPS URL, reject redirects, localhost, and literal private/reserved IPs, and limit responses to 2 MiB. Displayed data is for reference only."
        source.startsWith("日历写入和本地课程通知") ->
            "Calendar writes and local course notifications require your action and permission. The app manages only events marked Where To Study. Course widgets are provided only on supported systems, and their data is not uploaded."
        source.startsWith("本项目只运营用于整理公开班车与活动数据的固定接口") ->
            "The project operates only fixed endpoints that organize public shuttle and event data. It provides no user accounts, cloud synchronization, advertising, analytics, or behavioral tracking and does not collect GPS location, contacts, advertising identifiers, diagnostics, or usage behavior. BUPT services, unpkg, UAPI, Timeless, GitHub Pages, the fixed public Where To Study endpoints, and a user-selected custom schedule server may process ordinary network metadata such as IP address and request time under their own policies."
        source.startsWith("凭据与缓存保留") ->
            "Credentials and caches remain on the device until replaced, cleared, or removed with the app. Clearing local data does not delete records held by the university or third parties."
        source.startsWith("请按 SECURITY.md") ->
            "Report security issues according to SECURITY.md. For privacy questions, open a GitHub issue without sensitive information. Never publish accounts, passwords, tokens, or personal schedules."
        source.startsWith("天气、黄历和 DDL 来自") ->
            "Weather, almanac, and deadline data comes from public third-party services. Campus contest notices are extracted by a script from public notice pages on the university intranet. Each card identifies its source."
        source.startsWith("显示数据仅供参考") ->
            "Displayed data is for reference only; rely on actual official information."
        else -> null
    }

    fun localizeTree(root: View) {
        val preservesBusinessText = root.getTag(R.id.preserve_raw_text) == true
        if (root is TextView && !preservesBusinessText) {
            if (root !is EditText) root.text = resolve(root.context, root.text.toString())
            root.hint = root.hint?.toString()?.let { resolve(root.context, it) }
        }
        if (!preservesBusinessText) root.contentDescription = root.contentDescription?.toString()?.let {
            resolve(root.context, it)
        }
        if (root is EditText &&
            (root.inputType and android.text.InputType.TYPE_MASK_CLASS) == android.text.InputType.TYPE_CLASS_TEXT &&
            (root.inputType and android.text.InputType.TYPE_MASK_VARIATION) == android.text.InputType.TYPE_TEXT_VARIATION_URI
        ) root.textDirection = View.TEXT_DIRECTION_LTR
        if (root is ViewGroup) {
            repeat(root.childCount) { index -> localizeTree(root.getChildAt(index)) }
        }
    }

    fun preserveRawText(view: View) {
        view.setTag(R.id.preserve_raw_text, true)
    }

    fun widgetContext(context: Context, source: String): String {
        return source.split(" · ").joinToString(" · ") { resolve(context, it) }
    }

    fun widgetCourseTitle(context: Context, source: String): String {
        return when {
            source.startsWith("进行中 · ") ->
                "${resolve(context, "进行中")} · ${source.removePrefix("进行中 · ")}"
            source.startsWith("下一节 · ") ->
                "${resolve(context, "下一节")} · ${source.removePrefix("下一节 · ")}"
            source.startsWith("明日 · ") ->
                "${resolve(context, "明日")} · ${source.removePrefix("明日 · ")}"
            else -> source
        }
    }

    fun localizeDialog(dialog: Dialog) {
        dialog.window?.decorView?.let(::localizeTree)
        if (dialog is AlertDialog) {
            dialog.window?.let { bindWindowColorTheme(it, modal = true) }
            listOf(AlertDialog.BUTTON_POSITIVE, AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_NEUTRAL)
                .mapNotNull(dialog::getButton).forEach { button ->
                    val defaultColors = button.textColors
                    button.bindTheme("dialogButton") {
                        button.setTextColor(if (Palette.selection.preset == "default") defaultColors
                            else android.content.res.ColorStateList.valueOf(Palette.primaryText))
                    }
                }
        }
        dialog.window?.decorView?.refreshColorTheme()
    }

    internal fun dateText(context: Context, source: String): String? {
        val locale = AppLocale.calendarLocale(context)
        val zone = TimeZone.getTimeZone("Asia/Shanghai")
        Regex("^(\\d{4})年(\\d{1,2})月(\\d{1,2})日(?: (.+))?$").matchEntire(source)?.let {
            val calendar = Calendar.getInstance(zone, Locale.US).apply {
                set(it.groupValues[1].toInt(), it.groupValues[2].toInt() - 1, it.groupValues[3].toInt())
            }
            val pattern = if (AppLocale.isEnglish(context)) "MMM d, yyyy"
                else android.text.format.DateFormat.getBestDateTimePattern(locale, "yMMMd")
            val date = SimpleDateFormat(pattern, locale).apply { timeZone = zone }
                .format(calendar.time)
            val weekday = it.groupValues.getOrElse(4) { "" }.takeIf(String::isNotBlank)?.let {
                NativeUiTextCatalog.resolve(context, it) ?: it
            }
            return listOfNotNull(date, weekday).joinToString(" ")
        }
        Regex("^(\\d{4})年(\\d{1,2})月$").matchEntire(source)?.let {
            val calendar = Calendar.getInstance(zone, Locale.US).apply {
                set(it.groupValues[1].toInt(), it.groupValues[2].toInt() - 1, 1)
            }
            val pattern = if (AppLocale.isEnglish(context)) "MMMM yyyy"
                else android.text.format.DateFormat.getBestDateTimePattern(locale, "yMMMM")
            return SimpleDateFormat(pattern, locale).apply { timeZone = zone }
                .format(calendar.time)
        }
        Regex("^(\\d{4})年$").matchEntire(source)?.let { return it.groupValues[1] }
        Regex("^(\\d{1,2})月(\\d{1,2})日$").matchEntire(source)?.let {
            val calendar = Calendar.getInstance(zone, Locale.US).apply {
                set(2000, it.groupValues[1].toInt() - 1, it.groupValues[2].toInt())
            }
            return SimpleDateFormat(AppLocale.monthDayPattern(context), locale).apply { timeZone = zone }.format(calendar.time)
        }
        Regex("^第(\\d+)周$").matchEntire(source)?.let { return "Week ${it.groupValues[1]}" }
        return null
    }

}

fun AlertDialog.Builder.showLocalized(): AlertDialog = show().also(UiText::localizeDialog)

fun Context.uiText(source: String): String = UiText.resolve(this, source)
