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

data class ScheduleSnapshot(
    val termID: String,
    val termStartDate: String,
    val fetchedAt: String,
    val courses: List<Course>,
)

data class Classroom(
    val id: String,
    val building: String,
    val room: String,
    val name: String,
    val size: Int?,
    val type: String,
    val availableSlots: List<Int>,
    val source: String,
)

data class CampusClassrooms(
    val campusID: String,
    val campusName: String,
    val targetDate: String,
    val fetchedAt: String,
    val realtime: Boolean,
    val provider: String,
    val rooms: List<Classroom>,
)

data class ClassroomsCache(
    val cacheVersion: Int,
    val targetDate: String,
    val fetchedAt: String,
    val realtime: Boolean,
    val provider: String,
    val campuses: List<CampusClassrooms>,
)

data class HolidayItem(
    val date: String,
    val name: String,
    val type: String,
)

data class HolidaysSnapshot(
    val year: Int,
    val source: String,
    val fetchedAt: String,
    val items: List<HolidayItem>,
)

object AppMetadata {
    const val classroomsCacheVersion = 2
    const val defaultTermID = ""
    const val defaultTermStartDate = ""

    val campuses = listOf(
        CampusMetadata(id = "01", name = "西土城"),
        CampusMetadata(id = "04", name = "沙河"),
    )

    private val buildingsByCampusID = mapOf(
        "01" to listOf("教1", "教2", "教3", "教4", "主楼"),
        "04" to listOf(
            "综合教学楼N",
            "综合教学楼S",
            "教学实验综合楼N",
            "教学实验综合楼S",
            "智慧教学楼",
        ),
    )

    fun buildings(campusID: String): List<String> = buildingsByCampusID[campusID].orEmpty()

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

object HolidayMetadata {
    const val source = "https://unpkg.com/holiday-calendar@1.3.3/data/CN"
    const val fallbackSource =
        "https://www.gov.cn/yaowen/liebiao/202511/content_7047099.htm"
    const val minimumYear = 1900
    const val maximumYear = 2100
    const val refreshIntervalMillis = 7L * 24L * 60L * 60L * 1_000L
}

object ScheduleLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun weekNumber(termStart: Calendar, target: Calendar): Int {
        val start = startOfDay(termStart)
        val day = startOfDay(target)
        val elapsedDays = Math.floorDiv(day.timeInMillis - start.timeInMillis, MILLIS_PER_DAY)
        if (elapsedDays < 0) return 0
        return Math.floorDiv(elapsedDays.toInt(), 7) + 1
    }

    fun courses(
        schedule: ScheduleSnapshot?,
        target: Calendar,
    ): List<Course> {
        schedule ?: return emptyList()
        val start = parseContractDate(schedule.termStartDate) ?: return emptyList()
        val week = weekNumber(start, target)
        val weekday = ((target.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        return schedule.courses
            .filter { it.weekday == weekday && week in it.weekNumbers }
            .sortedWith(compareBy(Course::startSlot, Course::name))
    }

    fun weekNumber(
        schedule: ScheduleSnapshot?,
        target: Calendar,
    ): Int? {
        schedule ?: return null
        val start = parseContractDate(schedule.termStartDate) ?: return null
        val maximumWeek = schedule.courses
            .flatMap(Course::weekNumbers)
            .filter { it > 0 }
            .maxOrNull()
            ?: return null
        return weekNumber(start, target).takeIf { it in 1..maximumWeek }
    }

    fun busySlots(
        schedule: ScheduleSnapshot?,
        target: Calendar,
    ): Set<Int> = courses(schedule, target)
        .flatMap { it.startSlot..it.endSlot }
        .filter { it in AppMetadata.slots.indices }
        .toSet()

    private fun startOfDay(source: Calendar): Calendar = Calendar.getInstance(shanghai).apply {
        set(source.get(Calendar.YEAR), source.get(Calendar.MONTH), source.get(Calendar.DAY_OF_MONTH), 0, 0, 0)
        set(Calendar.MILLISECOND, 0)
    }

    private fun parseContractDate(value: String): Calendar? {
        val parts = value.split('-').mapNotNull(String::toIntOrNull)
        if (parts.size != 3) return null
        val date = Calendar.getInstance(shanghai).apply {
            isLenient = false
            set(parts[0], parts[1] - 1, parts[2], 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return runCatching { date.timeInMillis }.map { date }.getOrNull()
    }

    private const val MILLIS_PER_DAY = 86_400_000L
}
