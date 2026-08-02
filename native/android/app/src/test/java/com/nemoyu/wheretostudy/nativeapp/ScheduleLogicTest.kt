package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class ScheduleLogicTest {
    @Test
    fun examWeeksUseSeventeenthAndEighteenthExistingWeeks() {
        val course = Course(
            id = "fixture-course",
            name = "测试课程",
            teacher = "测试教师",
            room = "测试楼-101",
            weekText = "2-19",
            weekNumbers = (2..19).toList(),
            examWeekNumbers = emptyList(),
            weekday = 1,
            startSlot = 0,
            endSlot = 1,
            sectionText = "1-2节",
            timeRange = "08:00-09:35",
        )

        assertEquals(setOf(18, 19), ScheduleLogic.examWeeks(listOf(course)))
    }

    @Test
    fun weekNumberUsesTermStartDate() {
        val zone = TimeZone.getTimeZone("Asia/Shanghai")
        val start = Calendar.getInstance(zone).apply { set(2026, Calendar.MARCH, 2, 0, 0, 0) }
        val target = Calendar.getInstance(zone).apply { set(2026, Calendar.MARCH, 16, 0, 0, 0) }

        assertEquals(3, ScheduleLogic.weekNumber(start, target))
    }
}
