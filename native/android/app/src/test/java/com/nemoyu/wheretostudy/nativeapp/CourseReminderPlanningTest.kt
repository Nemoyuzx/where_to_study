package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Test

class CourseReminderPlanningTest {
    private val account = "reminder-test-only"
    private val accountKey = CourseDeletionLogic.accountKey(account)
    private val course = Course("course-1", "Synthetic class", "Teacher", "Room", "1–2", listOf(1, 2),
        emptyList(), 1, 0, 3, "1–4", "08:00-11:25", sourceCourseID = "source-1")
    private val schedule = ScheduleSnapshot("2026-2027-1", "2026-09-07", "fixture", listOf(course))
    private fun at(day: Int, hour: Int, minute: Int) = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
        clear(); set(2026, Calendar.SEPTEMBER, day, hour, minute)
    }.timeInMillis
    private fun plan(snapshot: ScheduleSnapshot? = schedule, offsets: List<Int> = listOf(10)) =
        CourseReminderPlanning.expand(snapshot, accountKey, offsets)

    @Test fun oldAndMalformedValuesSafelyUseOneTenMinuteReminder() {
        listOf(null, "", "oops", "0", "-1", "1441", "10,", "10,2.5", "5,10,5", "1,2,3,4,5,6", "2147483647").forEach {
            assertEquals(listOf(10), CourseReminderPlanning.decodeStored(it))
        }
        assertEquals(listOf(10, 5), CourseReminderPlanning.decodeStored("5,10"))
    }

    @Test fun invalidEditsAreRejectedInsteadOfSilentlyReplacingUserInput() {
        listOf(emptyList(), listOf(""), listOf("0"), listOf("1441"), listOf("+5"),
            listOf("5.5"), listOf("5", "5"), listOf("1", "2", "3", "4", "5", "6")).forEach {
            assertTrue(runCatching { CourseReminderPlanning.parseInput(it) }.isFailure)
        }
        assertEquals(listOf(1440, 10, 5, 1), CourseReminderPlanning.parseInput(listOf("1", "5", "10", "1440")))
    }

    @Test fun defaultsAndCustomFiveTenOffsetsUseOnlyOneStartForFourLessonSlots() {
        val defaults = plan()
        assertEquals(2, defaults.size)
        assertEquals(at(7, 7, 50), defaults.first().fireAtMillis)
        assertEquals(at(7, 8, 0), defaults.first().startsAtMillis)
        val both = plan(offsets = listOf(5, 10))
        assertEquals(listOf(at(7, 7, 50), at(7, 7, 55), at(14, 7, 50), at(14, 7, 55)), both.map { it.fireAtMillis })
        assertEquals(4, both.map { it.key }.toSet().size)
    }

    @Test fun duplicateCachedRowsAndWeekNumbersNeverCreateExtraNotifications() {
        val duplicated = course.copy(weekNumbers = listOf(1, 1, 2))
        assertEquals(plan(), plan(schedule.copy(courses = listOf(duplicated, duplicated))))
    }

    @Test fun refreshTimestampAndLocationDoNotChangeDeliveryIdentityButStartTimeDoes() {
        assertEquals(plan().map { it.key }, plan(schedule.copy(fetchedAt = "new", courses = listOf(course.copy(room = "Changed")))).map { it.key })
        assertNotEquals(plan().first().key, plan(schedule.copy(courses = listOf(course.copy(startSlot = 2)))).first().key)
        val stale = plan().first()
        assertTrue(CourseReminderPlanning.deliverable(plan(schedule.copy(courses = listOf(course.copy(startSlot = 2)))),
            setOf(stale.key), stale.fireAtMillis, stale.fireAtMillis, emptySet()).isEmpty())
    }

    @Test fun accountAndTermSeparateDeliveredKeys() {
        assertNotEquals(plan().first().key, CourseReminderPlanning.expand(schedule, "other-account", listOf(10)).first().key)
        assertNotEquals(plan().first().key, plan(schedule.copy(termID = "different-term")).first().key)
        assertTrue(CourseReminderPlanning.expand(schedule, "", listOf(10)).isEmpty())
        assertTrue(plan(null).isEmpty())
    }

    @Test fun deletingAndRestoringOccurrencesChangesOnlyTheirPlans() {
        val date = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply { timeInMillis = at(7, 12, 0) }
        val deletion = CourseDeletionLogic.create(account, schedule, course, date, CourseDeletionScope.SINGLE_OCCURRENCE)
        val effective = CourseDeletionLogic.apply(schedule, account, listOf(deletion))
        assertEquals(listOf(at(14, 7, 50)), plan(effective).map { it.fireAtMillis })
        assertEquals(plan(), plan(CourseDeletionLogic.apply(schedule, account, emptyList())))
    }

    @Test fun timedExamsSuppressOverlappingCoursesAndPendingTimesAreExcluded() {
        val exams = ExamSchedule(schedule.termID, accountKey, "fixture", "fresh", "", listOf(
            ExamArrangement("exam-1", "Synthetic exam", "2026-09-07", "09:07", "10:43", "Exam room"),
            ExamArrangement("exam-2", "Pending exam", "2026-09-08", "", "", ""),
        ))
        val actual = plan(schedule.copy(examSchedule = exams))
        assertEquals(2, actual.size)
        assertEquals("考试 · Synthetic exam", actual.first().title)
        assertEquals(at(7, 8, 57), actual.first().fireAtMillis)
        assertFalse(actual.any { it.title.contains("Pending") })
    }

    @Test fun unknownExamTimesDoNotSuppressRegularClassOrInventMidnightReminders() {
        val exam = ExamSchedule(schedule.termID, accountKey, "fixture", "fresh", "",
            listOf(ExamArrangement("pending", "Pending", "2026-09-07", "", "", "")))
        assertEquals(plan(), plan(schedule.copy(examSchedule = exam)))
    }

    @Test fun newPlansOnlyIncludeFutureTimesWithoutStartupReplay() {
        val drafts = plan(offsets = listOf(10, 5))
        assertEquals(at(7, 7, 55), CourseReminderPlanning.nextBatch(drafts, at(7, 7, 50), emptySet()).single().fireAtMillis)
        assertEquals(at(14, 7, 50), CourseReminderPlanning.nextBatch(drafts, at(7, 8, 0), emptySet()).single().fireAtMillis)
        assertTrue(CourseReminderPlanning.nextBatch(drafts, at(15, 0, 0), emptySet()).isEmpty())
    }

    @Test fun delayedEarlierOffsetExpiresWhenTheNextOffsetArrivesAndNothingDeliversAfterStart() {
        val drafts = plan(offsets = listOf(10, 5))
        val first = drafts.first()
        assertEquals(listOf(first), CourseReminderPlanning.deliverable(drafts, setOf(first.key), first.fireAtMillis,
            at(7, 7, 54), emptySet()))
        assertTrue(CourseReminderPlanning.deliverable(drafts, setOf(first.key), first.fireAtMillis, at(7, 7, 55), emptySet()).isEmpty())
        val second = drafts[1]
        assertTrue(CourseReminderPlanning.deliverable(drafts, setOf(second.key), second.fireAtMillis, at(7, 8, 0), emptySet()).isEmpty())
    }

    @Test fun duplicateDeliveryAndBackwardClockChangesRespectPersistentLedger() {
        val drafts = plan()
        val first = drafts.first()
        val delivered = setOf(first.key)
        assertTrue(CourseReminderPlanning.deliverable(drafts, delivered, first.fireAtMillis, first.fireAtMillis, delivered).isEmpty())
        assertEquals(drafts[1], CourseReminderPlanning.nextBatch(drafts, at(7, 7, 0), delivered).single())
    }

    @Test fun sameTimeCoursesShareOneBatchWithoutCollidingWithEachOther() {
        val other = course.copy(id = "course-2", sourceCourseID = "source-2", name = "Other")
        val batch = CourseReminderPlanning.nextBatch(plan(schedule.copy(courses = listOf(course, other))), at(7, 0, 0), emptySet())
        assertEquals(2, batch.size)
        assertEquals(2, batch.map { it.key }.toSet().size)
    }

    @Test fun shanghaiInstantsRemainStableOnForeignDevicesAndDayLongLeadCrossesMidnight() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            assertEquals(at(6, 8, 0), plan(offsets = listOf(1440)).first().fireAtMillis)
            assertEquals(at(7, 7, 55), plan(offsets = listOf(5)).first().fireAtMillis)
        } finally { TimeZone.setDefault(original) }
    }

    @Test fun staleNotificationPermissionResultsCannotEnableAnotherAccountOrCancelledRequest() {
        assertTrue(CourseReminderPlanning.requestMatchesAccount(true, accountKey, accountKey))
        assertFalse(CourseReminderPlanning.requestMatchesAccount(false, accountKey, accountKey))
        assertFalse(CourseReminderPlanning.requestMatchesAccount(true, accountKey, "other"))
    }
}
