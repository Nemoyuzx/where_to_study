package com.nemoyu.wheretostudy.nativeapp

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

data class ExamArrangement(
    val id: String,
    val name: String,
    val date: String,
    val startTime: String,
    val endTime: String,
    val room: String,
    val seat: String = "",
    val timeText: String = "",
)

data class ExamSchedule(
    val termID: String,
    val accountKey: String,
    val fetchedAt: String,
    val status: String,
    val message: String,
    val items: List<ExamArrangement>,
)

internal data class AcademicTerm(val id: String, val name: String)
internal data class AcademicTerms(val currentTermID: String, val terms: List<AcademicTerm>)
internal data class AcademicGrade(
    val id: String, val name: String, val score: String?, val credits: String?,
    val courseCode: String?, val courseAttribute: String?, val courseNature: String?, val examNature: String?,
    val semesterName: String? = null, val gradeStatus: String? = null,
)
internal data class AcademicGrades(
    val termID: String, val recordType: String, val fetchedAt: String,
    val averageGradePoint: String?, val items: List<AcademicGrade>,
)

internal object AcademicScheduleLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    fun dateText(date: Calendar): String = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
        .apply { timeZone = shanghai }.format(date.time)

    fun parseDate(value: String): Calendar? {
        if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) return null
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = shanghai; isLenient = false
        }
        val position = ParsePosition(0)
        val parsed = formatter.parse(value, position) ?: return null
        if (position.index != value.length || formatter.format(parsed) != value) return null
        return Calendar.getInstance(shanghai).apply { time = parsed }
    }

    fun minute(value: String?): Int? {
        if (value == null || !Regex("(?:[01]\\d|2[0-3]):[0-5]\\d").matches(value)) return null
        return value.take(2).toInt() * 60 + value.takeLast(2).toInt()
    }

    fun start(course: Course): String? = if (course.eventKind == "exam") course.startTime
        else AppMetadata.slots.getOrNull(course.startSlot)?.start
    fun end(course: Course): String? = if (course.eventKind == "exam") course.endTime
        else AppMetadata.slots.getOrNull(course.endSlot)?.end
    fun interval(course: Course): Pair<Int, Int>? {
        val start = minute(start(course)) ?: return null
        val end = minute(end(course)) ?: return null
        return (start to end).takeIf { start < end }
    }

    fun courses(schedule: ScheduleSnapshot, date: Calendar, regular: List<Course>): List<Course> {
        val dateText = dateText(date)
        val exams = schedule.examSchedule?.takeIf { it.termID == schedule.termID && it.status != "failed" }
            ?.items.orEmpty().filter { it.date == dateText }.map { exam ->
                Course(
                    id = "exam:${exam.id}", name = exam.name, teacher = "", room = exam.room,
                    weekText = "", weekNumbers = emptyList(), examWeekNumbers = emptyList(),
                    weekday = ((date.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1,
                    startSlot = -1, endSlot = -1, sectionText = "考试",
                    timeRange = if (minute(exam.startTime) != null && minute(exam.endTime) != null &&
                        minute(exam.startTime)!! < minute(exam.endTime)!!
                    ) "${exam.startTime}-${exam.endTime}" else "时间待定",
                    eventKind = "exam", eventDate = exam.date,
                    startTime = exam.startTime, endTime = exam.endTime,
                )
            }
        val intervals = exams.mapNotNull(::interval)
        val visible = regular.filter { course ->
            val range = interval(course)
            range == null || intervals.none { range.first < it.second && it.first < range.second }
        }
        return (visible + exams).sortedWith(compareBy<Course> { interval(it)?.first ?: Int.MAX_VALUE }
            .thenBy { it.name }.thenBy { it.id })
    }

    fun usableExams(schedule: ScheduleSnapshot, account: String): ScheduleSnapshot = schedule.copy(
        examSchedule = schedule.examSchedule?.takeIf {
            account.isNotBlank() && it.accountKey == CourseDeletionLogic.accountKey(account) &&
                it.termID == schedule.termID && it.status in setOf("fresh", "stale", "failed")
        },
    )

    fun mergeFailure(fetched: ScheduleSnapshot, previous: ScheduleSnapshot?): ScheduleSnapshot {
        val incoming = fetched.examSchedule ?: return fetched
        if (incoming.status != "failed") return fetched
        val prior = previous?.examSchedule?.takeIf {
            it.termID == incoming.termID && it.accountKey == incoming.accountKey &&
                it.status in setOf("fresh", "stale")
        } ?: return fetched
        return fetched.copy(examSchedule = prior.copy(status = "stale", message = incoming.message))
    }

    fun statusText(schedule: ExamSchedule?): String = when (schedule?.status) {
        "fresh" -> if (schedule.items.isEmpty()) "本学期暂无考试安排" else
            if (schedule.items.any { it.date.isBlank() || minute(it.startTime) == null || minute(it.endTime) == null })
                "部分考试日期或时间待定，请查看考试安排" else "考试安排已同步"
        "stale" -> "考试安排刷新失败，正在显示本账号本学期的缓存"
        "failed" -> "考试安排获取失败，请重新刷新课表"
        else -> "尚未获取考试安排，请刷新课表"
    }
}

internal object AcademicResponseParser {
    fun timestamp(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.ROOT)
        .apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }.format(Date())

    private fun data(payload: JSONObject): JSONArray {
        if (scalar(payload.opt("code")) != "1") throw ScheduleClientException("教务查询失败，请重试或检查账号设置。")
        return payload.optJSONArray("data") ?: throw ScheduleClientException("教务查询返回了无法识别的数据。")
    }

    fun terms(current: JSONObject, semesters: JSONObject): AcademicTerms {
        val currentRows = data(current)
        val currentID = if (currentRows.length() == 0) "" else
            scalar(currentRows.getJSONObject(0).opt("semesterId"))
                ?: throw ScheduleClientException("当前学期数据格式不正确。")
        val rows = data(semesters)
        val terms = (0 until rows.length()).map { index ->
            val row = rows.optJSONObject(index) ?: throw ScheduleClientException("学期列表数据格式不正确。")
            val id = scalar(row.opt("semesterId"))?.takeIf(String::isNotBlank)
                ?: throw ScheduleClientException("学期列表数据格式不正确。")
            AcademicTerm(id, scalar(row.opt("semesterName"))?.takeIf(String::isNotBlank) ?: id)
        }.distinctBy(AcademicTerm::id)
        return AcademicTerms(currentID, terms)
    }

    fun grades(payload: JSONObject, termID: String, recordType: String): AcademicGrades {
        require(recordType in setOf("1", "0", ""))
        val rows = data(payload)
        val root = if (rows.length() == 0) null else rows.optJSONObject(0)
            ?: throw ScheduleClientException("成绩数据格式不正确。")
        val records = root?.optJSONArray("achievement") ?: if (root == null) JSONArray()
            else throw ScheduleClientException("成绩数据格式不正确。")
        val items = (0 until records.length()).map { index ->
            val row = records.optJSONObject(index) ?: throw ScheduleClientException("成绩数据格式不正确。")
            val name = scalar(row.opt("courseName"))?.takeIf(String::isNotBlank)
                ?: throw ScheduleClientException("成绩数据缺少课程名称。")
            val fields = listOf("fraction", "credit", "kcbh", "curriculumAttributes", "courseNature", "examinationNature")
                .map { scalar(row.opt(it)) }
            val semesterName = scalar(row.opt("curSemesterName"))
            val gradeStatus = scalar(row.opt("cjbs"))
            val recordID = scalar(row.opt("cj0708id"))
            AcademicGrade(digest(recordID?.let(::listOf) ?: (listOf(name, semesterName, gradeStatus) + fields)),
                name, fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], semesterName, gradeStatus)
        }.distinctBy(AcademicGrade::id)
        return AcademicGrades(termID, recordType, timestamp(), scalar(root?.opt("pjxfjd")), items)
    }

    fun exams(payload: JSONObject, termID: String, accountKey: String): ExamSchedule {
        val rows = data(payload)
        val items = (0 until rows.length()).map { index ->
            val row = rows.optJSONObject(index) ?: throw ScheduleClientException("考试安排数据格式不正确。")
            val name = scalar(row.opt("courseName"))?.takeIf(String::isNotBlank)
                ?: throw ScheduleClientException("考试安排缺少课程名称。")
            val time = scalar(row.opt("time")).orEmpty()
            val dateSource = time.ifBlank { scalar(row.opt("ksqssj")).orEmpty() }
            val dates = Regex("(?<!\\d)(\\d{4})[-/年](\\d{1,2})[-/月](\\d{1,2})日?(?!\\d)")
                .findAll(dateSource).map { match ->
                    "%s-%02d-%02d".format(Locale.ROOT, match.groupValues[1],
                        match.groupValues[2].toInt(), match.groupValues[3].toInt())
                }.distinct().toList()
            val date = dates.singleOrNull()?.takeIf { AcademicScheduleLogic.parseDate(it) != null }.orEmpty()
            val timePattern = Regex("(?<!\\d)([01]?\\d|2[0-3]):([0-5]\\d)(?!\\d)")
            val timeValues = timePattern.findAll(time).map {
                "%02d:%s".format(Locale.ROOT, it.groupValues[1].toInt(), it.groupValues[2])
            }.toList()
            val explicitRange = Regex("(?:[01]?\\d|2[0-3]):[0-5]\\d\\s*[-–—~～至]\\s*(?:[01]?\\d|2[0-3]):[0-5]\\d")
                .findAll(time).count() == 1
            val times = timeValues.let { parsed ->
                if (parsed.isEmpty() && time.isBlank()) listOfNotNull(
                    scalar(row.opt("zssj1"))?.takeIf { AcademicScheduleLogic.minute(it) != null },
                    scalar(row.opt("zssj2"))?.takeIf { AcademicScheduleLogic.minute(it) != null },
                ) else if (explicitRange) parsed else emptyList()
            }
            val valid = times.size == 2 && AcademicScheduleLogic.minute(times[0])!! < AcademicScheduleLogic.minute(times[1])!!
            val start = if (valid) times[0] else ""
            val end = if (valid) times[1] else ""
            val room = scalar(row.opt("examinationPlace")).orEmpty()
            val id = digest(listOf(name, date, start, end, room, time))
            ExamArrangement(id, name, date, start, end, room, timeText = dateSource)
        }.distinctBy(ExamArrangement::id)
        return ExamSchedule(termID, accountKey, timestamp(), "fresh", "", items)
    }

    private fun scalar(value: Any?): String? {
        val text = when (value) {
            null, JSONObject.NULL -> null
            is String -> value.trim().takeIf(String::isNotEmpty)
            is Number -> value.toString()
            else -> throw ScheduleClientException("教务数据字段格式不正确。")
        }
        if (text != null && text.length > 2_048) throw ScheduleClientException("教务数据字段过长。")
        return text
    }
    private fun digest(fields: List<String?>): String = MessageDigest.getInstance("SHA-256")
        .digest(fields.joinToString("\u001f") { it.orEmpty() }.toByteArray(StandardCharsets.UTF_8))
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }
}

internal class SjdAcademicClient(private val api: SjdApiClient = SjdApiClient()) {
    fun terms(credentials: Credentials): AcademicTerms = api.authenticated(credentials) { token ->
        AcademicResponseParser.terms(
            api.post("/bjyddx/currentTerm", SjdApiClient.CLASSROOM_REFERER, token = token),
            api.post("/bjyddx/semesterList", SjdApiClient.CLASSROOM_REFERER, token = token),
        )
    }
    fun grades(credentials: Credentials, termID: String, recordType: String): AcademicGrades = api.authenticated(credentials) { token ->
        val query = java.net.URLEncoder.encode(termID, StandardCharsets.UTF_8.name())
        AcademicResponseParser.grades(api.post(
            "/bjyddx/student/termGPA?semester=$query&type=$recordType",
            SjdApiClient.CLASSROOM_REFERER, token = token,
        ), termID, recordType)
    }
}
