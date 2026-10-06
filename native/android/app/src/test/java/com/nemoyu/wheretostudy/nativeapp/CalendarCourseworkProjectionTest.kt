package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.*
import org.junit.Test

class CalendarCourseworkProjectionTest {
    @Test fun dateOnlyDoesNotInventAMidnightDeadline() {
        assertNull(CalendarCourseworkProjection.timestamp("2026-10-06"))
        assertNull(CalendarCourseworkProjection.timestamp("2026-10-06T25:00:00"))
        assertNull(CalendarCourseworkProjection.timestamp("2026-02-30T12:00:00"))
        assertNull(CalendarCourseworkProjection.timestamp("2026-10-06T12:00:00+18:01"))
        assertNull(CalendarCourseworkProjection.timestamp("2026-10-06T12:00:00garbage"))
        assertEquals("2026-10-06" to 0, CalendarCourseworkProjection.timestamp("2026-10-06 00:00:00"))
        assertEquals("2026-10-06" to 1439, CalendarCourseworkProjection.timestamp("2026-10-06T23:59:00"))
    }
    @Test fun utcOffsetsProjectToShanghaiRegardlessOfDeviceTimezone() {
        assertEquals("2026-10-07" to 0, CalendarCourseworkProjection.timestamp("2026-10-06T16:00:00Z"))
        assertEquals("2026-10-06" to 1439, CalendarCourseworkProjection.timestamp("2026-10-06T23:59:00+08:00"))
    }
    @Test fun consumerSelectsBeijingDayFromAccountWideCacheRatherThanRawDateBucket() {
        val item = AssignmentDeadlineItem("cross", "Cross-day", "Course", "2026-10-05T16:15:00Z", null, "course")
        val points = CalendarCourseworkProjection.cloud(listOf(item), listOf(TeachingCloudCourse("course", "Course", null)))
        assertTrue(CalendarCourseworkProjection.onDate(points, "2026-10-05").isEmpty())
        assertEquals(15, CalendarCourseworkProjection.onDate(points, "2026-10-06").single().minute)
        assertEquals("teaching-cloud.course.course", points.single().courseDetailKey)
    }
    @Test fun tailBadgesAggregateVisuallyWithoutLosingTrueAnchorsOrCourseRoutes() {
        val items = listOf(1420, 1438, 1439).map { TimelineDeadline(it.toString(), "Task", "Course", "2026-10-06", it, "course.$it") }
        val badges = CalendarCourseworkProjection.badges(items, 20)
        assertEquals(1, badges.size)
        assertEquals(listOf(1420, 1438, 1439), badges.single().map { it.minute })
        assertEquals(listOf("course.1420", "course.1438", "course.1439"), badges.single().map { it.courseDetailKey })
        assertEquals(2, CalendarCourseworkProjection.badges(listOf(items[0], items[2].copy(minute = 1440)), 20).size)
    }
    @Test fun exactPointsExpandTheScrollableGridWithoutInventingDuration() {
        assertEquals(0..24, CalendarTimelineLogic.hourBounds(emptyList(), listOf(0, 1439)))
        assertEquals(6..22, CalendarTimelineLogic.hourBounds(emptyList(), listOf(6 * 60)))
        assertEquals(8..22, CalendarTimelineLogic.hourBounds(emptyList()))
        assertEquals(4f to 96f, CalendarCourseworkProjection.markerHorizontalBounds(100f, 4f))
    }
    @Test fun courseRouteRequiresAnUnambiguousCachedCourseAndGroupsExactMinutes() {
        val courses = listOf(TeachingCloudCourse("course", "Course", null))
        val input = listOf(AssignmentDeadlineItem("a", "Task", "Course", "2026-10-06 08:15:00", null, "course"),
            AssignmentDeadlineItem("b", "Task 2", null, "2026-10-06 08:15:00", null),
            AssignmentDeadlineItem("date", "Date-only", "Course", "2026-10-06", null))
        val points = CalendarCourseworkProjection.cloud(input, courses)
        assertEquals(2, points.size)
        assertEquals("teaching-cloud.course.course", points[0].courseDetailKey)
        assertNull(points[1].courseDetailKey)
        assertEquals(1, CalendarCourseworkProjection.groups(points).size)
        assertEquals(495, points[0].minute)
    }
    @Test fun fullWidthMarkerCapturesOnlyItsThinVisibleStrip() {
        assertEquals(4f to 38f, CalendarCourseworkProjection.markerHorizontalBounds(42f, 4f))
        assertTrue(CalendarCourseworkProjection.markerHit(20f, 540f, 4f, 38f, 540f, 18f))
        assertFalse(CalendarCourseworkProjection.markerHit(20f, 530f, 4f, 38f, 540f, 18f))
        assertFalse(CalendarCourseworkProjection.markerHit(20f, 550f, 4f, 38f, 540f, 18f))
        assertFalse(CalendarCourseworkProjection.markerHit(2f, 540f, 4f, 38f, 540f, 18f))
        assertFalse(CalendarCourseworkProjection.markerHit(40f, 540f, 4f, 38f, 540f, 18f))
    }
    @Test fun qmplusUsesTypedQuizClosingTimeAndCachedCourseRoute() {
        val course = QmplusCourse("ebu", "EBU Course", null, "https://qmplus.qmul.ac.uk/course/view.php?id=ebu", null, null, "current")
        val quiz = QmplusActivityItem("quiz", "ebu", "Quiz", "quiz", "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=quiz",
            null, null, "2026-10-06T15:59:00Z", null, null, null, null, null)
        val points = CalendarCourseworkProjection.qmplus(QmplusSnapshot("2026-10-06T00:00:00Z", listOf(course), listOf(quiz), emptyList()), false)
        assertEquals(1439, points.single().minute)
        assertEquals("2026-10-06", points.single().date)
        assertEquals("qmplus.course.ebu", points.single().courseDetailKey)
    }
    @Test fun pendingDotRequiresExplicitSubmissionEvidence() {
        val course = TeachingCloudCourse("course", "Course", null)
        val base = AssignmentDeadlineItem("a", "Task", "Course", "2026-10-06 08:15:00", null, "course")
        assertTrue(CalendarCourseworkProjection.cloud(listOf(base.copy(status = "未提交")), listOf(course)).single().clearlyPending)
        for (status in listOf(null, "已提交", "已批改", "已驳回", "in progress")) {
            assertFalse(CalendarCourseworkProjection.cloud(listOf(base.copy(status = status)), listOf(course)).single().clearlyPending)
        }
        assertFalse(CalendarCourseworkProjection.cloud(listOf(base.copy(status = "未提交"), base.copy(status = "已提交")), listOf(course))
            .any { it.clearlyPending })
    }
    @Test fun quizUnknownStateIsNotTreatedAsAnUnsubmittedAttempt() {
        val course = QmplusCourse("ebu", "EBU Course", null, "https://qmplus.qmul.ac.uk/course/view.php?id=ebu", null, null, "current")
        val quiz = QmplusActivityItem("quiz", "ebu", "Quiz", "quiz", "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=quiz",
            null, null, "2026-10-06T15:59:00Z", null, null, null, null, null)
        fun project(status: String?) = CalendarCourseworkProjection.qmplus(QmplusSnapshot("2026-10-06T00:00:00Z", listOf(course),
            listOf(quiz.copy(status = status)), emptyList()), false).single()
        assertFalse(project(null).clearlyPending)
        assertFalse(project("not attempted").clearlyPending)
        assertFalse(project("submitted").clearlyPending)
        assertTrue(project("nothing submitted").clearlyPending)
    }
}
