package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone

data class SlotMetadata(
    val index: Int,
    val label: String,
    val start: String,
    val end: String,
)

data class CampusMetadata(
    val id: String,
    val name: String,
)

data class Course(
    val id: String,
    val name: String,
    val teacher: String,
    val room: String,
    val weekText: String,
    val weekNumbers: List<Int>,
    val examWeekNumbers: List<Int>,
    val weekday: Int,
    val startSlot: Int,
    val endSlot: Int,
    val sectionText: String,
    val timeRange: String,
)

object AppMetadata {
    val campuses = listOf(
        CampusMetadata(id = "01", name = "西土城"),
        CampusMetadata(id = "04", name = "沙河"),
    )

    val slots = listOf(
        SlotMetadata(0, "1", "08:00", "08:45"),
        SlotMetadata(1, "2", "08:50", "09:35"),
        SlotMetadata(2, "3", "09:50", "10:35"),
        SlotMetadata(3, "4", "10:40", "11:25"),
        SlotMetadata(4, "5", "11:30", "12:15"),
        SlotMetadata(5, "6", "13:00", "13:45"),
        SlotMetadata(6, "7", "13:50", "14:35"),
        SlotMetadata(7, "8", "14:45", "15:30"),
        SlotMetadata(8, "9", "15:40", "16:25"),
        SlotMetadata(9, "10", "16:35", "17:20"),
        SlotMetadata(10, "11", "17:25", "18:10"),
        SlotMetadata(11, "12", "18:30", "19:15"),
        SlotMetadata(12, "13", "19:20", "20:05"),
        SlotMetadata(13, "14", "20:10", "20:55"),
    )
}

object ScheduleLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun examWeeks(courses: List<Course>): Set<Int> {
        val existingWeeks = courses
            .flatMap(Course::weekNumbers)
            .filter { it > 0 }
            .distinct()
            .sorted()
        return listOfNotNull(existingWeeks.getOrNull(16), existingWeeks.getOrNull(17)).toSet()
    }

    fun weekNumber(termStart: Calendar, target: Calendar): Int {
        val start = startOfDay(termStart)
        val day = startOfDay(target)
        val elapsedDays = Math.floorDiv(day.timeInMillis - start.timeInMillis, MILLIS_PER_DAY)
        return Math.floorDiv(elapsedDays.toInt(), 7) + 1
    }

    private fun startOfDay(source: Calendar): Calendar = Calendar.getInstance(shanghai).apply {
        set(source.get(Calendar.YEAR), source.get(Calendar.MONTH), source.get(Calendar.DAY_OF_MONTH), 0, 0, 0)
        set(Calendar.MILLISECOND, 0)
    }

    private const val MILLIS_PER_DAY = 86_400_000L
}
