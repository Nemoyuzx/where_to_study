package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayCourseWidgetLogicTest {
    @Test
    fun spareRowsUseTomorrowWithoutDisplacingTodayOrExceedingPreference() {
        val tomorrow = course("tomorrow", "明日课程", 0, "08:00-09:35").copy(weekday = 2)
        val content = TodayCourseWidgetLogic.content(schedule().copy(courses = schedule().courses + tomorrow), mondayMorning)
        assertEquals(listOf("early", "later", "tomorrow"), TodayCourseWidgetLogic.displayRows(content, 6, 4).map { it.course.id })
        assertEquals(listOf("early", "later"), TodayCourseWidgetLogic.displayRows(content, 6, 2).map { it.course.id })
        assertEquals(listOf("early"), TodayCourseWidgetLogic.displayRows(content, 1, 6).map { it.course.id })
        assertEquals("明日 · 明日课程", TodayCourseWidgetLogic.title(TodayCourseWidgetLogic.displayRows(content, 3).last(), content))
    }

    @Test
    fun emptyTodayCanUseAllCapacityForTomorrowWithoutCallingItNext() {
        val course = course("only-tomorrow", "示例课程", 0, "08:00-09:35").copy(weekday = 2)
        val content = TodayCourseWidgetLogic.content(schedule().copy(courses = listOf(course)), mondayMorning)
        val rows = TodayCourseWidgetLogic.displayRows(content, 1)
        assertTrue(content.courses.isEmpty())
        assertEquals(null, content.highlightedCourseID)
        assertEquals("今天可以自由安排", content.statusText)
        assertTrue(rows.single().isTomorrow)
        assertEquals("明日 · 示例课程", TodayCourseWidgetLogic.title(rows.single(), content))
    }

    @Test
    fun finishedTodayStaysFirstAndDuplicateCourseIDsDoNotHighlightTomorrow() {
        val base = course("same", "重复课程", 0, "08:00-09:35")
        val fixture = schedule().copy(courses = listOf(base, base.copy(weekday = 2)))
        val active = TodayCourseWidgetLogic.content(fixture, mondayMorning)
        assertEquals("明日 · 重复课程", TodayCourseWidgetLogic.title(TodayCourseWidgetLogic.displayRows(active, 2).last(), active))
        val finished = TodayCourseWidgetLogic.content(fixture, millis(2026, 3, 2, 20, 0))
        assertEquals("今日课程已结束", finished.statusText)
        assertEquals(listOf(false, true), TodayCourseWidgetLogic.displayRows(finished, 2).map { it.isTomorrow })
    }

    @Test
    fun tomorrowUsesNewTeachingWeekAcrossSundayAndMonthBoundary() {
        val fixture = schedule().copy(courses = listOf(
            course("week14", "新一周课程", 0, "08:00-09:35").copy(weekNumbers = listOf(14)),
            course("week13", "旧一周课程", 2, "09:50-10:35").copy(weekNumbers = listOf(13)),
        ))
        val content = TodayCourseWidgetLogic.content(fixture, millis(2026, 5, 31, 12, 0))
        assertEquals(listOf("week14"), content.tomorrowCourses.map { it.id })
        assertEquals(millis(2026, 6, 1, 0, 0), TodayCourseWidgetLogic.nextMidnightAt(millis(2026, 5, 31, 12, 0)))
    }

    @Test
    fun midnightPromotesTomorrowAcrossYearWithoutSystemTimezoneDependence() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            val fixture = schedule().copy(termStartDate = "2026-12-28", courses = listOf(
                course("new-year", "新年课程", 0, "08:00-09:35").copy(weekday = 5),
            ))
            val before = millis(2026, 12, 31, 23, 59)
            val midnight = TodayCourseWidgetLogic.nextMidnightAt(before)
            assertEquals(millis(2027, 1, 1, 0, 0), midnight)
            assertEquals("new-year", TodayCourseWidgetLogic.content(fixture, before).tomorrowCourses.single().id)
            val after = TodayCourseWidgetLogic.content(fixture, midnight)
            assertEquals("new-year", after.courses.single().id)
            assertTrue(after.tomorrowCourses.isEmpty())
        } finally { TimeZone.setDefault(original) }
    }

    @Test
    fun previewHasTomorrowOnSundayAndNoTomorrowLeavesOnlyToday() {
        val preview = TodayCourseWidgetLogic.previewContent(millis(2026, 3, 8, 12, 0))
        assertEquals(3, preview.courses.size)
        assertEquals(3, preview.tomorrowCourses.size)
        assertEquals(6, TodayCourseWidgetLogic.displayRows(preview, 6).size)
        val todayOnly = TodayCourseWidgetLogic.content(schedule(), mondayMorning)
        assertEquals(2, TodayCourseWidgetLogic.displayRows(todayOnly, 6).size)
        assertTrue(TodayCourseWidgetLogic.displayRows(TodayCourseWidgetLogic.content(null, mondayMorning), 6).isEmpty())
    }

    @Test
    fun missingScheduleUsesNoCourseState() {
        val content = TodayCourseWidgetLogic.content(null, mondayMorning)

        assertTrue(content.courses.isEmpty())
        assertEquals("今日无课", content.emptyMessage)
    }

    @Test
    fun dayWithoutCoursesUsesNoCourseState() {
        val content = TodayCourseWidgetLogic.content(schedule(), tuesdayMorning)

        assertTrue(content.courses.isEmpty())
        assertEquals("今日无课", content.emptyMessage)
    }

    @Test
    fun currentCoursesAreOrderedAndDetailsIncludeRoom() {
        val content = TodayCourseWidgetLogic.content(schedule(), mondayMorning)

        assertEquals(listOf("early", "later"), content.courses.map(Course::id))
        assertEquals("3月2日 · 周一 · 公历第10周 · 教学第1周", content.dateContext)
        assertEquals("下一节 · 09:50", content.statusText)
        assertEquals("下一节 · 数据挖掘", TodayCourseWidgetLogic.title(content.courses.first(), content))
        assertEquals(
            "09:50-10:35 · 第 3 节 · 教二楼-335 · 测试教师",
            TodayCourseWidgetLogic.details(content.courses.first()),
        )
        assertEquals(
            "09:50-10:35 · 第 3 节",
            TodayCourseWidgetLogic.details(
                content.courses.first(),
                showsLocation = false,
                showsTeacher = false,
            ),
        )
    }

    @Test
    fun widgetHeightAndPreferenceCanExposeUpToSixRows() {
        assertEquals(1, TodayCourseWidgetLogic.rowLimit(110))
        assertEquals(1, TodayCourseWidgetLogic.rowLimit(120))
        assertEquals(2, TodayCourseWidgetLogic.rowLimit(180))
        assertEquals(3, TodayCourseWidgetLogic.rowLimit(205))
        assertEquals(4, TodayCourseWidgetLogic.rowLimit(240))
        assertEquals(6, TodayCourseWidgetLogic.rowLimit(320))
    }

    private fun schedule() = ScheduleSnapshot(
        termID = "fixture-term",
        termStartDate = "2026-03-02",
        fetchedAt = "2026-03-01T12:00:00+08:00",
        courses = listOf(
            course("later", "神经网络", startSlot = 8, timeRange = "15:40-16:25"),
            course("early", "数据挖掘", startSlot = 2, timeRange = "09:50-10:35"),
        ),
    )

    private fun course(id: String, name: String, startSlot: Int, timeRange: String) = Course(
        id = id,
        name = name,
        teacher = "测试教师",
        room = "教二楼-335",
        weekText = "1周",
        weekNumbers = listOf(1),
        examWeekNumbers = emptyList(),
        weekday = 1,
        startSlot = startSlot,
        endSlot = startSlot,
        sectionText = "第 ${startSlot + 1} 节",
        timeRange = timeRange,
    )

    private val mondayMorning = millis(2026, 3, 2, 8, 0)
    private val tuesdayMorning = millis(2026, 3, 3, 8, 0)

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).run {
            clear()
            set(year, month - 1, day, hour, minute, 0)
            timeInMillis
        }
}
