package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

internal enum class CourseDeletionScope { SINGLE_OCCURRENCE, WHOLE_COURSE }

internal data class CourseDeletion(
    val id: String,
    val accountKey: String,
    val termID: String,
    val sourceCourseID: String?,
    val courseName: String,
    val teacher: String,
    val scope: CourseDeletionScope,
    val date: String? = null,
    val startSlot: Int? = null,
    val endSlot: Int? = null,
)

internal object CourseDeletionLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun accountKey(account: String): String = MessageDigest.getInstance("SHA-256")
        .digest(account.trim().toByteArray(StandardCharsets.UTF_8))
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    fun create(
        account: String,
        schedule: ScheduleSnapshot,
        course: Course,
        date: Calendar,
        scope: CourseDeletionScope,
    ): CourseDeletion {
        require(schedule.termID.isNotBlank()) { "课表缺少学期编号，无法删除课程。" }
        return CourseDeletion(
            id = UUID.randomUUID().toString(),
            accountKey = accountKey(account),
            termID = schedule.termID,
            sourceCourseID = course.sourceCourseID?.trim()?.takeIf(String::isNotEmpty),
            courseName = course.name.trim(),
            teacher = course.teacher.trim(),
            scope = scope,
            date = if (scope == CourseDeletionScope.SINGLE_OCCURRENCE) formatDate(date) else null,
            startSlot = if (scope == CourseDeletionScope.SINGLE_OCCURRENCE) course.startSlot else null,
            endSlot = if (scope == CourseDeletionScope.SINGLE_OCCURRENCE) course.endSlot else null,
        )
    }

    fun matchesCourse(deletion: CourseDeletion, course: Course): Boolean {
        val savedID = deletion.sourceCourseID?.trim()?.takeIf(String::isNotEmpty)
        val sourceID = course.sourceCourseID?.trim()?.takeIf(String::isNotEmpty)
        return if (savedID != null && sourceID != null) savedID == sourceID
        else deletion.courseName.trim() == course.name.trim() && deletion.teacher.trim() == course.teacher.trim()
    }

    fun records(account: String, termID: String, deletions: List<CourseDeletion>): List<CourseDeletion> {
        val key = accountKey(account)
        return deletions.filter { it.accountKey == key && it.termID == termID }
    }

    fun apply(
        schedule: ScheduleSnapshot,
        account: String,
        deletions: List<CourseDeletion>,
    ): ScheduleSnapshot {
        val active = records(account, schedule.termID, deletions)
        if (active.isEmpty()) return schedule
        val termStart = parseDate(schedule.termStartDate)
        return schedule.copy(courses = schedule.courses.mapNotNull { course ->
            val matching = active.filter { matchesCourse(it, course) }
            if (matching.any { it.scope == CourseDeletionScope.WHOLE_COURSE }) return@mapNotNull null
            if (termStart == null || matching.isEmpty()) return@mapNotNull course
            val removedWeeks = matching.mapNotNull occurrence@{ deletion ->
                if (deletion.scope != CourseDeletionScope.SINGLE_OCCURRENCE ||
                    deletion.startSlot != course.startSlot || deletion.endSlot != course.endSlot
                ) return@occurrence null
                val date = deletion.date?.let(::parseDate) ?: return@occurrence null
                val weekday = ((date.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
                if (weekday != course.weekday) return@occurrence null
                ScheduleLogic.weekNumber(termStart, date).takeIf { it in course.weekNumbers }
            }.toSet()
            if (removedWeeks.isEmpty()) course else {
                val remainingWeeks = course.weekNumbers.filterNot { it in removedWeeks }
                if (remainingWeeks.isEmpty()) null else course.copy(
                    weekNumbers = remainingWeeks,
                    weekText = remainingWeeks.joinToString(","),
                    examWeekNumbers = course.examWeekNumbers.filterNot { it in removedWeeks },
                )
            }
        })
    }

    private fun formatDate(date: Calendar): String = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
        .apply { timeZone = shanghai }.format(date.time)

    private fun parseDate(value: String): Calendar? {
        if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) return null
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = shanghai
            isLenient = false
        }
        val position = ParsePosition(0)
        val parsed = format.parse(value, position) ?: return null
        if (position.index != value.length || format.format(parsed) != value) return null
        return Calendar.getInstance(shanghai).apply { time = parsed }
    }
}

internal object CourseDeletionJsonCodec {
    fun encode(deletions: List<CourseDeletion>): String = JSONObject().put("version", 1)
        .put("deletions", JSONArray().apply {
            deletions.forEach { deletion ->
                put(JSONObject()
                    .put("id", deletion.id)
                    .put("account_key", deletion.accountKey)
                    .put("term_id", deletion.termID)
                    .put("source_course_id", deletion.sourceCourseID)
                    .put("course_name", deletion.courseName)
                    .put("teacher", deletion.teacher)
                    .put("scope", deletion.scope.name)
                    .put("date", deletion.date)
                    .put("start_slot", deletion.startSlot)
                    .put("end_slot", deletion.endSlot))
            }
        }).toString()

    fun decode(value: String): List<CourseDeletion> {
        val root = JSONObject(value)
        require(root.getInt("version") == 1) { "课程删除记录格式不受支持。" }
        val records = root.getJSONArray("deletions")
        return (0 until records.length()).map { index ->
            val item = records.getJSONObject(index)
            val scope = CourseDeletionScope.valueOf(item.getString("scope"))
            CourseDeletion(
                id = item.getString("id"),
                accountKey = item.getString("account_key"),
                termID = item.getString("term_id"),
                sourceCourseID = item.optString("source_course_id").takeIf(String::isNotBlank),
                courseName = item.getString("course_name"),
                teacher = item.optString("teacher"),
                scope = scope,
                date = if (scope == CourseDeletionScope.SINGLE_OCCURRENCE) item.getString("date") else null,
                startSlot = if (scope == CourseDeletionScope.SINGLE_OCCURRENCE) item.getInt("start_slot") else null,
                endSlot = if (scope == CourseDeletionScope.SINGLE_OCCURRENCE) item.getInt("end_slot") else null,
            )
        }
    }
}

internal class CourseDeletionStore(context: Context) {
    private val file = AtomicFile(File(context.filesDir, "course_deletions_v1.json"))

    fun load(): List<CourseDeletion> {
        // Older Android AtomicFile implementations recover a committed .bak
        // when a write was interrupted after renaming the base file.
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return emptyList()
        return file.openRead().bufferedReader(StandardCharsets.UTF_8).use {
            CourseDeletionJsonCodec.decode(it.readText())
        }
    }

    fun save(deletions: List<CourseDeletion>) {
        val output = file.startWrite()
        try {
            output.write(CourseDeletionJsonCodec.encode(deletions).toByteArray(StandardCharsets.UTF_8))
            output.fd.sync()
            file.finishWrite(output)
            // AtomicFile logs some sync/rename failures instead of throwing.
            // Publish the filtered UI only after the committed record is readable.
            check(load() == deletions) { "无法保存课程删除记录" }
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }

    fun clear() {
        file.delete()
        check(listOf("", ".bak", ".new").none { File(file.baseFile.path + it).exists() }) {
            "无法清除课程删除记录。"
        }
    }
}
