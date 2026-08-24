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
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

enum class AppLanguage(val code: String) {
    SYSTEM("system"),
    SIMPLIFIED_CHINESE("zh-Hans"),
    ENGLISH("en"),
}

object AppTypography {
    const val oneStepSmallerScale = 0.92f

    fun adjustedFontScale(systemFontScale: Float): Float =
        systemFontScale * oneStepSmallerScale
}

object AppLocale {
    fun wrap(base: Context, languageCode: String): Context {
        val language = AppLanguage.entries.firstOrNull { it.code == languageCode }
            ?: AppLanguage.SYSTEM
        val locale = resolvedLocale(language)
        Locale.setDefault(locale)
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(locale)
            setLocales(LocaleList(locale))
            fontScale = AppTypography.adjustedFontScale(base.resources.configuration.fontScale)
        }
        return base.createConfigurationContext(configuration)
    }

    fun isEnglish(context: Context): Boolean {
        return context.resources.configuration.locales[0].language != Locale.CHINESE.language
    }

    fun displayName(context: Context, language: AppLanguage): String = when (language) {
        AppLanguage.SYSTEM -> UiText.resolve(context, "跟随系统")
        AppLanguage.SIMPLIFIED_CHINESE -> UiText.resolve(context, "简体中文")
        AppLanguage.ENGLISH -> "English"
    }

    private fun resolvedLocale(language: AppLanguage): Locale = when (language) {
        AppLanguage.SIMPLIFIED_CHINESE -> Locale.SIMPLIFIED_CHINESE
        AppLanguage.ENGLISH -> Locale.US
        AppLanguage.SYSTEM -> Resources.getSystem().configuration.locales[0]
            .takeIf { it.language == Locale.CHINESE.language }
            ?.let { Locale.SIMPLIFIED_CHINESE }
            ?: Locale.US
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
        "联动查询" to "Linked Search",
        "查询条件" to "Search Filters",
        "查询概览" to "Query Summary",
        "空教室结果" to "Available Classrooms",
        "教学楼" to "Building",
        "节次筛选" to "Period Filter",
        "个人空闲节次" to "My Free Periods",
        "使用个人课表排除已有课程" to "Exclude periods occupied by my schedule",
        "获取空教室信息" to "Fetch Classroom Data",
        "正在获取…" to "Fetching…",
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
        "考试周" to "Exam Weeks",
        "未标注" to "Not specified",
        "关闭" to "Close",
        "完成" to "Done",
        "导入手机日历" to "Import to Device Calendar",
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
        "月视图溢出日程弹窗" to "Month overflow schedule dialog",
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
        "试" to "Exam",
        "休" to "Off",
        "班" to "Work",
        "宜" to "Good for",
        "忌" to "Avoid",
        "个人账户" to "Account",
        "教务账号" to "Academic Account",
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
        "获取/刷新课表后会自动应用教务返回的学期与开学日期。" to "Fetching the schedule automatically applies the semester and start date returned by Academic Affairs.",
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
        "校内竞赛通知" to "Campus Contest Notices",
        "夏令营 DDL" to "Summer Camp DDL",
        "夏令营" to "Summer Camp",
        "黑客松 DDL" to "Hackathon DDL",
        "黑客松" to "Hackathon",
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
        if (!AppLocale.isEnglish(context) || source.isEmpty()) return source
        exactEnglish[source]?.let { return it }
        Regex("^(\\d+) 门课$").matchEntire(source)?.let { return "${it.groupValues[1]} courses" }
        Regex("^(\\d+) 门$").matchEntire(source)?.let { return "${it.groupValues[1]} courses" }
        Regex("^收藏管理（(\\d+)）$").matchEntire(source)?.let {
            return "Favorite Management (${it.groupValues[1]})"
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
        longPolicyText(source)?.let { return it }
        if (source.endsWith("，点击重试")) {
            return englishStatusFallback(source.removeSuffix("，点击重试")) +
                ", tap to retry"
        }
        dateText(source)?.let { return it }
        if (source.contains("（试）") || source.contains("；")) {
            return source.replace("（试）", " (Exam)").replace("；", "; ")
        }
        if (source.startsWith("正在") && source.endsWith("…")) return "Loading…"
        if (source.startsWith("暂无")) return "No data available"
        if (source.endsWith("失败") || source.endsWith("失败。") ||
            source.contains("无法") || source.contains("不可用") ||
            source.contains("格式不正确")
        ) {
            return englishStatusFallback(source)
        }
        return source
    }

    private fun englishStatusFallback(source: String): String = when {
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
            "Your student ID and password remain in protected operating-system storage. They are used over HTTPS only when you request schedules, classrooms, or assignments. The maintainer cannot read them, and Settings never returns the saved password."
        source.startsWith("密码仅通过 HTTPS 提交") ->
            "The password is sent only to auth.bupt.edu.cn over HTTPS. A one-time ticket is exchanged for an in-memory token used with apiucloud.bupt.edu.cn. Browser cookies are not read, and tickets, cookies, tokens, and assignments are not written to disk; results may be reused in memory for up to 10 minutes."
        source.startsWith("课表、空教室、校区") ->
            "Schedules, classroom data, campus, semester settings, switches, the custom feed URL, and up to 500 favorite snapshots remain on the device. Course widgets read only the local schedule. Clearing local data removes all of these items."
        source.startsWith("应用可能通过 unpkg") ->
            "The app may fetch a fixed holiday-calendar dataset from unpkg. Android may also read a system holiday calendar when permission already exists. Requests contain only CN and the year. iOS marks days off only from authoritative rest-day data."
        source.startsWith("UAPI 按校区行政区") ->
            "UAPI provides district-level weather and base almanac data without GPS. Timeless may add advice. Contest DDL and campus notices provide public events. Custom schedules use credential-free GET requests only to the user-provided HTTPS URL, reject redirects, localhost, and literal private/reserved IPs, and limit responses to 2 MiB. Displayed data is for reference only."
        source.startsWith("日历写入和本地课程通知") ->
            "Calendar writes and local course notifications require your action and permission. The app manages only events marked Where To Study. Course widgets are provided only on supported systems, and their data is not uploaded."
        source.startsWith("项目不运营应用后端") ->
            "The project operates no application backend and includes no ads, analytics, or tracking SDKs. It does not collect GPS, contacts, advertising identifiers, diagnostics, or usage behavior. Third parties may process IP addresses and request times under their own policies."
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
        if (root is TextView && root.getTag(R.id.preserve_raw_text) != true) {
            root.text = resolve(root.context, root.text.toString())
            root.hint = root.hint?.toString()?.let { resolve(root.context, it) }
        }
        root.contentDescription = root.contentDescription?.toString()?.let {
            resolve(root.context, it)
        }
        if (root is ViewGroup) {
            repeat(root.childCount) { index -> localizeTree(root.getChildAt(index)) }
        }
    }

    fun preserveRawText(view: TextView) {
        view.setTag(R.id.preserve_raw_text, true)
    }

    fun widgetContext(context: Context, source: String): String {
        if (!AppLocale.isEnglish(context)) return source
        return source.split(" · ").joinToString(" · ") { part ->
            exactEnglish[part] ?: dateText(part) ?: part
        }
    }

    fun widgetCourseTitle(context: Context, source: String): String {
        if (!AppLocale.isEnglish(context)) return source
        return when {
            source.startsWith("进行中 · ") ->
                "In progress · ${source.removePrefix("进行中 · ")}"
            source.startsWith("下一节 · ") ->
                "Next · ${source.removePrefix("下一节 · ")}"
            else -> source
        }
    }

    fun localizeDialog(dialog: Dialog) {
        dialog.window?.decorView?.let(::localizeTree)
    }

    private fun dateText(source: String): String? {
        val locale = Locale.US
        val zone = TimeZone.getTimeZone("Asia/Shanghai")
        Regex("^(\\d{4})年(\\d{1,2})月(\\d{1,2})日(?: (.+))?$").matchEntire(source)?.let {
            val calendar = Calendar.getInstance(zone).apply {
                set(it.groupValues[1].toInt(), it.groupValues[2].toInt() - 1, it.groupValues[3].toInt())
            }
            val date = SimpleDateFormat("MMM d, yyyy", locale).apply { timeZone = zone }
                .format(calendar.time)
            val weekday = exactEnglish[it.groupValues.getOrElse(4) { "" }]
            return listOfNotNull(date, weekday).joinToString(" ")
        }
        Regex("^(\\d{4})年(\\d{1,2})月$").matchEntire(source)?.let {
            val calendar = Calendar.getInstance(zone).apply {
                set(it.groupValues[1].toInt(), it.groupValues[2].toInt() - 1, 1)
            }
            return SimpleDateFormat("MMMM yyyy", locale).apply { timeZone = zone }
                .format(calendar.time)
        }
        Regex("^(\\d{4})年$").matchEntire(source)?.let { return it.groupValues[1] }
        Regex("^(\\d{1,2})月(\\d{1,2})日$").matchEntire(source)?.let {
            val calendar = Calendar.getInstance(zone).apply {
                set(2000, it.groupValues[1].toInt() - 1, it.groupValues[2].toInt())
            }
            return SimpleDateFormat("MMM d", locale).apply { timeZone = zone }.format(calendar.time)
        }
        Regex("^第(\\d+)周$").matchEntire(source)?.let { return "Week ${it.groupValues[1]}" }
        return null
    }

}

fun AlertDialog.Builder.showLocalized(): AlertDialog = show().also(UiText::localizeDialog)

fun Context.uiText(source: String): String = UiText.resolve(this, source)
