package com.nemoyu.wheretostudy.nativeapp

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleCalendarLogicTest {
    @Test
    fun expandsEveryTeachingWeekInShanghaiTime() {
        val events = ScheduleCalendarLogic.expand(
            schedule(course(weekNumbers = listOf(1, 3))),
        )

        assertEquals(2, events.size)
        assertEquals("2026-03-02 08:00", format(events[0].startsAtMillis))
        assertEquals("2026-03-02 09:35", format(events[0].endsAtMillis))
        assertEquals("2026-03-16 08:00", format(events[1].startsAtMillis))
        assertEquals("2026-03-16 09:35", format(events[1].endsAtMillis))
        assertTrue(events.all { it.timeZoneID == "Asia/Shanghai" })
    }

    @Test
    fun prefixesOnlyExamWeekEvents() {
        val events = ScheduleCalendarLogic.expand(
            schedule(course(weekNumbers = listOf(1, 3), examWeekNumbers = listOf(3))),
        )

        assertEquals("数据挖掘", events[0].title)
        assertEquals("试 数据挖掘", events[1].title)
    }

    @Test
    fun appliesWeekdayAndSlotOffsets() {
        val event = ScheduleCalendarLogic.expand(
            schedule(course(weekNumbers = listOf(2), weekday = 3, startSlot = 9, endSlot = 9)),
        ).single()

        assertEquals("2026-03-11 16:35", format(event.startsAtMillis))
        assertEquals("2026-03-11 17:20", format(event.endsAtMillis))
    }

    @Test
    fun markerIsStableAndSeparatesOccurrences() {
        val first = ScheduleCalendarLogic.stableMarker("2025-2026-2", "course-42", 3)
        val repeated = ScheduleCalendarLogic.stableMarker("2025-2026-2", "course-42", 3)
        val otherWeek = ScheduleCalendarLogic.stableMarker("2025-2026-2", "course-42", 4)

        assertEquals(first, repeated)
        assertEquals(
            "wheretostudy://calendar/v1/ce09889ac4df78d7be3be9ca4b8dd4b1494553f7029705429c729b68dd322acd",
            first,
        )
        assertNotEquals(first, otherWeek)
    }

    @Test
    fun duplicateCachedCoursesProduceOneEventPerMarker() {
        val cached = schedule(course()).let { snapshot ->
            snapshot.copy(courses = listOf(snapshot.courses.single(), snapshot.courses.single()))
        }

        assertEquals(1, ScheduleCalendarLogic.expand(cached).size)
    }

    @Test
    fun rejectsInvalidTermDates() {
        listOf("2026-02-30", "2026-3-02", "not-a-date").forEach { invalidDate ->
            assertThrows(ScheduleCalendarExpansionException::class.java) {
                ScheduleCalendarLogic.expand(schedule(course(), termStartDate = invalidDate))
            }
        }
    }

    @Test
    fun rejectsInvalidSlots() {
        listOf(
            course(startSlot = -1),
            course(endSlot = AppMetadata.slots.size),
            course(startSlot = 2, endSlot = 1),
        ).forEach { invalidCourse ->
            assertThrows(ScheduleCalendarExpansionException::class.java) {
                ScheduleCalendarLogic.expand(schedule(invalidCourse))
            }
        }
    }

    private fun schedule(
        course: Course,
        termStartDate: String = "2026-03-02",
    ): ScheduleSnapshot = ScheduleSnapshot(
        termID = "2025-2026-2",
        termStartDate = termStartDate,
        fetchedAt = "2026-03-01T12:00:00+08:00",
        courses = listOf(course),
    )

    private fun course(
        weekNumbers: List<Int> = listOf(1),
        examWeekNumbers: List<Int> = emptyList(),
        weekday: Int = 1,
        startSlot: Int = 0,
        endSlot: Int = 1,
    ): Course = Course(
        id = "course-42",
        name = "数据挖掘",
        teacher = "徐思雅",
        room = "教二楼-335",
        weekText = "1-3周",
        weekNumbers = weekNumbers,
        examWeekNumbers = examWeekNumbers,
        weekday = weekday,
        startSlot = startSlot,
        endSlot = endSlot,
        sectionText = "1-2节",
        timeRange = "08:00-09:35",
    )

    private fun format(value: Long): String = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("Asia/Shanghai")
    }.format(Date(value))
}
