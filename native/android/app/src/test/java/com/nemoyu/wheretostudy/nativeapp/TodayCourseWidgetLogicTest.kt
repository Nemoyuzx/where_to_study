package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayCourseWidgetLogicTest {
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
        assertEquals("09:50-10:35 · 教二楼-335", TodayCourseWidgetLogic.details(content.courses.first()))
        assertEquals("09:50-10:35", TodayCourseWidgetLogic.details(content.courses.first(), false))
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
