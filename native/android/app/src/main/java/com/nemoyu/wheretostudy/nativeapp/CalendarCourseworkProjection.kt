package com.nemoyu.wheretostudy.nativeapp

import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** A deadline is a point, never a synthetic Course interval. */
data class TimelineDeadline(val id: String, val title: String, val courseName: String?,
    val date: String, val minute: Int, val courseDetailKey: String?, val clearlyPending: Boolean = false)

internal object CalendarCourseworkProjection {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val explicitTimestamp = Regex("^(\\d{4}-\\d{2}-\\d{2})[T ](\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.\\d+)?)?(Z|[+-]\\d{2}:\\d{2})?$")
    fun timestamp(value: String): Pair<String, Int>? = runCatching {
        val match = requireNotNull(explicitTimestamp.matchEntire(value))
        val (day, hour, minute, seconds, offset) = match.destructured
        val zone = when {
            offset.isEmpty() -> shanghai
            offset == "Z" -> TimeZone.getTimeZone("UTC")
            else -> {
                val offsetHour = offset.substring(1, 3).toInt()
                val offsetMinute = offset.substring(4, 6).toInt()
                require(offsetHour in 0..18 && offsetMinute in 0..59 && (offsetHour < 18 || offsetMinute == 0))
                TimeZone.getTimeZone("GMT$offset")
            }
        }
        val text = "$day $hour:$minute:${seconds.ifEmpty { "00" }}"
        val parser = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).apply { timeZone = zone; isLenient = false }
        val position = ParsePosition(0)
        val instant = requireNotNull(parser.parse(text, position))
        require(position.index == text.length && position.errorIndex < 0)
        val local = Calendar.getInstance(shanghai, Locale.ROOT).apply { time = instant }
        SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { timeZone = shanghai }.format(instant) to
            (local.get(Calendar.HOUR_OF_DAY) * 60 + local.get(Calendar.MINUTE))
    }.getOrNull()

    fun cloud(items: List<AssignmentDeadlineItem>, courses: List<TeachingCloudCourse>): List<TimelineDeadline> {
        val evidence = items.groupBy { it.courseID to it.id }
        return items.mapNotNull { item ->
            val stamp = timestamp(item.deadline) ?: return@mapNotNull null
            val matches = courses.filter { course -> item.courseID?.let { it == course.id }
                ?: (item.courseName?.trim()?.takeIf(String::isNotEmpty)?.let { it == course.name?.trim() } == true) }
            TimelineDeadline("ucloud:${item.courseID.orEmpty()}:${item.id}", item.title, item.courseName ?: matches.singleOrNull()?.name, stamp.first, stamp.second,
                matches.singleOrNull()?.let { "teaching-cloud.course.${it.id}" },
                CourseDirectoryLogic.isClearlyPending(evidence[item.courseID to item.id].orEmpty().map { it.status }))
        }
    }

    fun qmplus(snapshot: QmplusSnapshot, showsOtherTerms: Boolean): List<TimelineDeadline> {
        val visible = QmplusSnapshotCodec.ebuOnly(snapshot)
        val courses = visible.courses.filter { it.currentTermStatus == "current" || showsOtherTerms }.associateBy { it.id }
        val evidence = visible.activities.groupBy { Triple(it.courseID, it.kind, it.id) }
        return visible.activities.filter { it.courseID in courses }.mapNotNull { item ->
            val value = (if (item.kind == "quiz") item.closesAt else item.dueAt) ?: return@mapNotNull null
            val stamp = timestamp(value) ?: return@mapNotNull null
            TimelineDeadline("qmplus:${item.courseID}:${item.kind}:${item.id}", item.title, courses[item.courseID]?.name,
                stamp.first, stamp.second, "qmplus.course.${item.courseID}",
                CourseDirectoryLogic.isClearlyPending(evidence[Triple(item.courseID, item.kind, item.id)].orEmpty().map { it.status }))
        }
    }

    fun groups(items: List<TimelineDeadline>): List<List<TimelineDeadline>> =
        items.distinctBy { it.id }.groupBy { it.minute }.toSortedMap().values.toList()

    fun onDate(items: List<TimelineDeadline>, date: String): List<TimelineDeadline> = items.filter { it.date == date }

    /** Merge only the visual badge: every underlying real minute remains an anchor. */
    fun badges(items: List<TimelineDeadline>, minimumMinuteSeparation: Int): List<List<TimelineDeadline>> {
        val result = mutableListOf<MutableList<TimelineDeadline>>()
        groups(items).forEach { group ->
            val previous = result.lastOrNull()
            if (previous != null && group.first().minute - previous.last().minute < minimumMinuteSeparation)
                previous.addAll(group)
            else result.add(group.toMutableList())
        }
        return result
    }

    fun markerHorizontalBounds(dayWidth: Float, inset: Float): Pair<Float, Float> = inset to maxOf(inset, dayWidth - inset)
    fun markerHit(x: Float, y: Float, left: Float, right: Float, anchor: Float, height: Float): Boolean =
        x in left..right && y in (anchor - height / 2)..(anchor + height / 2)
}
