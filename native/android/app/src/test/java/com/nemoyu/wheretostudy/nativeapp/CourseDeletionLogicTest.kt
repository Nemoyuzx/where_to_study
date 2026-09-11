package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class CourseDeletionLogicTest {
    private val account = "20260001"
    private val monday = course("row-a", "source-a", weekday = 1)
    private val wednesday = monday.copy(id = "row-b", weekday = 3, room = "different-room")
    private val unrelated = course("row-c", "source-b", name = "Another course")
    private val schedule = ScheduleSnapshot("2026-2027-1", "2026-09-07", "fixture", listOf(monday, wednesday, unrelated))

    @Test
    fun wholeCourseRemovesAllRowsWithSameSourceEvenAfterTimeLocationAndTitleChanges() {
        val record = deletion(monday, CourseDeletionScope.WHOLE_COURSE)
        val refreshed = schedule.copy(courses = schedule.courses.map {
            if (it.sourceCourseID == "source-a") it.copy(
                id = "new-${it.id}", name = "Renamed", teacher = "New teacher", room = "New room",
                startSlot = 2, endSlot = 3, weekNumbers = listOf(2, 5),
            ) else it
        })
        val actual = CourseDeletionLogic.apply(refreshed, account, listOf(record))
        assertEquals(listOf(unrelated), actual.courses)
        assertEquals(3, refreshed.courses.size)
    }

    @Test
    fun oneOccurrenceRemovesOnlySelectedDateAndSlots() {
        val anotherTime = monday.copy(id = "later", startSlot = 4, endSlot = 5)
        val raw = schedule.copy(courses = schedule.courses + anotherTime)
        val record = deletion(monday, CourseDeletionScope.SINGLE_OCCURRENCE, day = 14)
        val actual = CourseDeletionLogic.apply(raw, account, listOf(record))
        assertEquals(listOf(1, 3), actual.courses.first { it.id == monday.id }.weekNumbers)
        assertEquals(listOf(1, 2, 3), actual.courses.first { it.id == wednesday.id }.weekNumbers)
        assertEquals(listOf(1, 2, 3), actual.courses.first { it.id == anotherTime.id }.weekNumbers)
        assertTrue(ScheduleLogic.courses(actual, date(14)).none { it.id == monday.id })
        assertTrue(ScheduleLogic.courses(actual, date(7)).any { it.id == monday.id })
        assertEquals(listOf(1, 2, 3), monday.weekNumbers)
    }

    @Test
    fun identityFallbackWorksWithEitherLegacyRecordOrLegacySnapshotButNeverDifferentExplicitIds() {
        val record = deletion(monday, CourseDeletionScope.WHOLE_COURSE)
        assertTrue(CourseDeletionLogic.matchesCourse(record, monday.copy(sourceCourseID = null)))
        assertTrue(CourseDeletionLogic.matchesCourse(record.copy(sourceCourseID = null), monday))
        assertTrue(CourseDeletionLogic.matchesCourse(record, monday.copy(
            sourceCourseID = null, name = " ${monday.name} ", teacher = " ${monday.teacher} ",
        )))
        assertFalse(CourseDeletionLogic.matchesCourse(record, monday.copy(sourceCourseID = "different")))
        assertFalse(CourseDeletionLogic.matchesCourse(record.copy(sourceCourseID = null), monday.copy(teacher = "Other")))
    }

    @Test
    fun deletionCannotAffectAnotherAccountOrTermAndRoundTripsWithoutRawAccount() {
        val record = deletion(monday, CourseDeletionScope.WHOLE_COURSE)
        val encoded = CourseDeletionJsonCodec.encode(listOf(record))
        assertFalse(encoded.contains(account))
        assertEquals(listOf(record), CourseDeletionJsonCodec.decode(encoded))
        assertEquals(schedule, CourseDeletionLogic.apply(schedule, "20260002", listOf(record)))
        val nextTerm = schedule.copy(termID = "2026-2027-2")
        assertEquals(nextTerm, CourseDeletionLogic.apply(nextTerm, account, listOf(record)))
        assertEquals(listOf(unrelated), CourseDeletionLogic.apply(schedule, " $account ", listOf(record)).courses)
    }

    @Test
    fun restoreDropsOnlyTheSelectedRuleAndRefreshNeverResurrectsIt() {
        val occurrence = deletion(monday, CourseDeletionScope.SINGLE_OCCURRENCE, day = 14)
        val whole = deletion(monday, CourseDeletionScope.WHOLE_COURSE)
        val records = listOf(occurrence, whole)
        assertEquals(listOf(unrelated), CourseDeletionLogic.apply(schedule, account, records).courses)
        val restoredWhole = CourseDeletionLogic.apply(schedule, account, records.filterNot { it.id == whole.id })
        assertEquals(listOf(1, 3), restoredWhole.courses.first().weekNumbers)
        val diskReload = ScheduleJsonCodec.decode(ScheduleJsonCodec.encode(schedule))
        val diskRules = CourseDeletionJsonCodec.decode(CourseDeletionJsonCodec.encode(records))
        assertEquals(listOf(unrelated), CourseDeletionLogic.apply(diskReload, account, diskRules).courses)
        assertEquals(schedule, CourseDeletionLogic.apply(schedule, account, emptyList()))
    }

    @Test
    fun localDeletionReleasesPlannerBusySlotsAndFiltersCalendarExportsFromEffectiveSnapshot() {
        val raw = schedule.copy(courses = listOf(monday))
        val record = deletion(monday, CourseDeletionScope.SINGLE_OCCURRENCE, day = 14)
        val effective = CourseDeletionLogic.apply(raw, account, listOf(record))
        assertEquals(setOf(0, 1), ScheduleLogic.busySlots(raw, date(14)))
        assertTrue(ScheduleLogic.busySlots(effective, date(14)).isEmpty())
        assertTrue(TodayCourseWidgetLogic.content(effective, date(14).timeInMillis).courses.isEmpty())
        assertNull(DailyCourseSummaryLogic.draft(effective, date(14).timeInMillis))
        assertEquals(1, TodayCourseWidgetLogic.content(effective, date(7).timeInMillis).courses.size)
        assertTrue(checkNotNull(DailyCourseSummaryLogic.draft(effective, date(7).timeInMillis)).body.contains(monday.name))
        assertEquals(2, ScheduleCalendarLogic.expand(effective).size)
        assertEquals(3, ScheduleCalendarLogic.expand(raw).size)
    }

    @Test
    fun occurrenceUsesShanghaiDateAndRejectsOtherDatesAndOutOfTermWeeks() {
        val utcDate = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(2026, Calendar.SEPTEMBER, 13, 16, 30, 0)
        }
        val record = CourseDeletionLogic.create(account, schedule, monday, utcDate, CourseDeletionScope.SINGLE_OCCURRENCE)
        assertEquals("2026-09-14", record.date)
        assertEquals(listOf(1, 3), CourseDeletionLogic.apply(schedule, account, listOf(record)).courses.first().weekNumbers)
        listOf("2026-09-15", "2026-09-06", "2026-02-30", "2026-09-28").forEach { invalidOccurrence ->
            assertEquals(schedule, CourseDeletionLogic.apply(schedule, account, listOf(record.copy(date = invalidOccurrence))))
        }
    }

    @Test
    fun deletingTheOnlyWeekDropsTheRowAndSingleOccurrenceSurvivesRoomAndRowIdChanges() {
        val record = deletion(monday, CourseDeletionScope.SINGLE_OCCURRENCE, day = 14)
        val refreshed = schedule.copy(courses = listOf(monday.copy(id = "changed", room = "changed", weekNumbers = listOf(2))))
        assertTrue(CourseDeletionLogic.apply(refreshed, account, listOf(record)).courses.isEmpty())
        assertEquals(listOf(record), CourseDeletionJsonCodec.decode(CourseDeletionJsonCodec.encode(listOf(record))))
    }

    @Test
    fun sourceIdentityIsOptionalInLegacyCacheAndPreservedByCodec() {
        val decoded = ScheduleJsonCodec.decode(ScheduleJsonCodec.encode(schedule))
        assertEquals("source-a", decoded.courses.first().sourceCourseID)
        val legacy = schedule.copy(courses = listOf(monday.copy(sourceCourseID = null)))
        assertNull(ScheduleJsonCodec.decode(ScheduleJsonCodec.encode(legacy)).courses.single().sourceCourseID)
    }

    private fun deletion(course: Course, scope: CourseDeletionScope, day: Int = 7) =
        CourseDeletionLogic.create(account, schedule, course, date(day), scope)

    private fun date(day: Int): Calendar = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
        clear()
        set(2026, Calendar.SEPTEMBER, day, 12, 0, 0)
    }

    private fun course(id: String, source: String?, weekday: Int = 1, name: String = "Test course") = Course(
        id, name, "Teacher", "Room", "1-3", listOf(1, 2, 3), emptyList(), weekday,
        0, 1, "1-2节", "08:00-09:35", source,
    )
}
