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
    fun syncPlanUpdatesOneEventAndRemovesOnlyScopedDuplicatesAndStaleEvents() {
        val snapshot = schedule(course(weekNumbers = listOf(1, 2)))
        val drafts = ScheduleCalendarLogic.expand(snapshot)
        val window = ScheduleCalendarLogic.termWindow(snapshot)
        val plan = CalendarSyncPlanner.plan(
            snapshot,
            drafts,
            listOf(
                ManagedCalendarEvent(11, drafts[0].marker, drafts[0].startsAtMillis),
                ManagedCalendarEvent(12, drafts[0].marker, drafts[0].startsAtMillis),
                ManagedCalendarEvent(
                    13,
                    ScheduleCalendarLogic.markerPrefix + "removed-course",
                    drafts[1].startsAtMillis,
                ),
                ManagedCalendarEvent(
                    14,
                    ScheduleCalendarLogic.markerPrefix + "historic-course",
                    window.endsAtMillis,
                ),
            ),
        )

        assertEquals(listOf(11L), plan.updates.map(CalendarEventUpdate::eventID))
        assertEquals(listOf(drafts[1].marker), plan.inserts.map(CalendarEventDraft::marker))
        assertEquals(listOf(12L), plan.duplicateEventIDs)
        assertEquals(listOf(13L), plan.staleEventIDs)
    }

    @Test
    fun changedCourseIdentityReplacesItsOldEventWithinTheCurrentTerm() {
        val snapshot = schedule(course())
        val draft = ScheduleCalendarLogic.expand(snapshot).single()
        val oldMarker = ScheduleCalendarLogic.stableMarker(snapshot.termID, "old-course-id", 1)

        val plan = CalendarSyncPlanner.plan(
            snapshot,
            listOf(draft),
            listOf(ManagedCalendarEvent(21, oldMarker, draft.startsAtMillis)),
        )

        assertEquals(listOf(draft), plan.inserts)
        assertEquals(listOf(21L), plan.staleEventIDs)
        assertTrue(plan.updates.isEmpty())
    }

    @Test
    fun termWindowCoversEighteenWeeksWithoutReachingTheNextTerm() {
        val snapshot = schedule(course(weekNumbers = listOf(1)))
        val window = ScheduleCalendarLogic.termWindow(snapshot)

        assertEquals("2026-03-02 00:00", format(window.startsAtMillis))
        assertEquals("2026-07-06 00:00", format(window.endsAtMillis))
        assertTrue(window.contains(window.endsAtMillis - 1))
        assertTrue(!window.contains(window.endsAtMillis))
    }

    @Test
    fun termWindowExtendsToTheLatestValidTeachingWeek() {
        val snapshot = schedule(course(weekNumbers = listOf(1, 20)))
        val window = ScheduleCalendarLogic.termWindow(snapshot)

        assertEquals("2026-07-20 00:00", format(window.endsAtMillis))
    }

    @Test
    fun expectedMarkerOutsideTheTermIsUpdatedInsteadOfInsertedAgain() {
        val snapshot = schedule(course())
        val draft = ScheduleCalendarLogic.expand(snapshot).single()
        val window = ScheduleCalendarLogic.termWindow(snapshot)

        val plan = CalendarSyncPlanner.plan(
            snapshot,
            listOf(draft),
            listOf(ManagedCalendarEvent(31, draft.marker, window.endsAtMillis + 1)),
        )

        assertEquals(listOf(31L), plan.updates.map(CalendarEventUpdate::eventID))
        assertTrue(plan.inserts.isEmpty())
        assertTrue(plan.staleEventIDs.isEmpty())
    }

    @Test
    fun emptyScheduleRemovesScopedManagedEvents() {
        val populated = schedule(course())
        val draft = ScheduleCalendarLogic.expand(populated).single()
        val empty = populated.copy(courses = emptyList())

        val plan = CalendarSyncPlanner.plan(
            empty,
            emptyList(),
            listOf(ManagedCalendarEvent(41, draft.marker, draft.startsAtMillis)),
        )

        assertEquals(listOf(41L), plan.staleEventIDs)
        assertTrue(plan.inserts.isEmpty())
        assertTrue(plan.updates.isEmpty())
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
