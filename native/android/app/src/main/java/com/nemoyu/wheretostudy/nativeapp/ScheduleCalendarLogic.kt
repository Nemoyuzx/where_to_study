package com.nemoyu.wheretostudy.nativeapp

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

data class CalendarEventDraft(
    val marker: String,
    val title: String,
    val location: String,
    val description: String,
    val startsAtMillis: Long,
    val endsAtMillis: Long,
    val timeZoneID: String,
)

class ScheduleCalendarExpansionException(message: String) : IllegalArgumentException(message)

object ScheduleCalendarLogic {
    const val timeZoneID = "Asia/Shanghai"
    const val markerPrefix = "wheretostudy://calendar/v1/"

    private val shanghai = TimeZone.getTimeZone(timeZoneID)
    private val contractDatePattern = Regex("\\d{4}-\\d{2}-\\d{2}")

    fun expand(schedule: ScheduleSnapshot): List<CalendarEventDraft> {
        val termStart = parseContractDate(schedule.termStartDate)
            ?: throw ScheduleCalendarExpansionException("课表的学期开始日期无效。")

        return buildList {
            schedule.courses.forEach { course ->
                validateCourse(course)
                course.weekNumbers.distinct().sorted().forEach { week ->
                    if (week <= 0) {
                        throw ScheduleCalendarExpansionException("课表包含无效的教学周。")
                    }
                    val dayOffset = runCatching {
                        Math.addExact(Math.multiplyExact(week - 1, 7), course.weekday - 1)
                    }.getOrElse {
                        throw ScheduleCalendarExpansionException("课表包含超出范围的教学周。")
                    }
                    val eventDate = (termStart.clone() as Calendar).apply {
                        add(Calendar.DAY_OF_MONTH, dayOffset)
                    }
                    val startsAt = withTime(eventDate, AppMetadata.slots[course.startSlot].start)
                    val endsAt = withTime(eventDate, AppMetadata.slots[course.endSlot].end)
                    if (endsAt.timeInMillis <= startsAt.timeInMillis) {
                        throw ScheduleCalendarExpansionException("课表包含无效的课程时间。")
                    }

                    add(
                        CalendarEventDraft(
                            marker = stableMarker(schedule.termID, course.id, week),
                            title = if (week in course.examWeekNumbers) {
                                "试 ${course.name}"
                            } else {
                                course.name
                            },
                            location = course.room,
                            description = listOf(course.teacher, course.sectionText)
                                .filter(String::isNotBlank)
                                .joinToString(" · "),
                            startsAtMillis = startsAt.timeInMillis,
                            endsAtMillis = endsAt.timeInMillis,
                            timeZoneID = timeZoneID,
                        ),
                    )
                }
            }
        }
            .distinctBy(CalendarEventDraft::marker)
            .sortedWith(compareBy(CalendarEventDraft::startsAtMillis, CalendarEventDraft::marker))
    }

    fun stableMarker(termID: String, courseID: String, week: Int): String {
        if (termID.isBlank() || courseID.isBlank() || week <= 0) {
            throw ScheduleCalendarExpansionException("无法为课程生成稳定的日历标识。")
        }
        val identity = listOf(termID, courseID, week.toString()).joinToString("\u001f")
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(identity.toByteArray(StandardCharsets.UTF_8))
        return markerPrefix + digest.joinToString("") { byte ->
            HEX_DIGITS[(byte.toInt() ushr 4) and 0x0f].toString() +
                HEX_DIGITS[byte.toInt() and 0x0f]
        }
    }

    private fun validateCourse(course: Course) {
        if (course.id.isBlank() || course.name.isBlank()) {
            throw ScheduleCalendarExpansionException("课表包含缺少标识或名称的课程。")
        }
        if (course.weekday !in 1..7) {
            throw ScheduleCalendarExpansionException("课表包含无效的上课星期。")
        }
        if (course.startSlot !in AppMetadata.slots.indices ||
            course.endSlot !in AppMetadata.slots.indices ||
            course.startSlot > course.endSlot
        ) {
            throw ScheduleCalendarExpansionException("课表包含无效的课程节次。")
        }
    }

    private fun parseContractDate(value: String): Calendar? {
        if (!contractDatePattern.matches(value)) return null
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = shanghai
            isLenient = false
        }
        val parsed = runCatching { formatter.parse(value) }.getOrNull() ?: return null
        if (formatter.format(parsed) != value) return null
        return Calendar.getInstance(shanghai).apply {
            time = parsed
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    private fun withTime(date: Calendar, value: String): Calendar {
        val parts = value.split(':').mapNotNull(String::toIntOrNull)
        if (parts.size != 2 || parts[0] !in 0..23 || parts[1] !in 0..59) {
            throw ScheduleCalendarExpansionException("课程节次包含无效时间。")
        }
        return (date.clone() as Calendar).apply {
            isLenient = false
            set(Calendar.HOUR_OF_DAY, parts[0])
            set(Calendar.MINUTE, parts[1])
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            timeInMillis
        }
    }

    private const val HEX_DIGITS = "0123456789abcdef"
}
