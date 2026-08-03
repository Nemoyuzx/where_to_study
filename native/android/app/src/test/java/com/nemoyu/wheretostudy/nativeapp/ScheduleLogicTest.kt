package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone
import org.json.JSONObject
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

    @Test
    fun weekNumberBeforeTermIsZero() {
        val zone = TimeZone.getTimeZone("Asia/Shanghai")
        val start = Calendar.getInstance(zone).apply { set(2026, Calendar.MARCH, 2, 0, 0, 0) }
        val target = Calendar.getInstance(zone).apply { set(2026, Calendar.MARCH, 1, 0, 0, 0) }

        assertEquals(0, ScheduleLogic.weekNumber(start, target))
    }

    @Test
    fun sharedSjdFixturesMatchScheduleContract() {
        val expected = ScheduleJsonCodec.decode(fixture("schedule.json"))
        val actual = SjdScheduleParser.parse(
            current = JSONObject(fixture("sjd-current-week.json")),
            curriculum = JSONObject(fixture("sjd-curriculum.json")),
            fallbackTermID = "unused-term",
            fallbackTermStartDate = "2000-01-03",
            fetchedAt = expected.fetchedAt,
        )

        assertEquals(expected, actual)
    }

    @Test
    fun scheduleCodecRoundTripsSharedFixture() {
        val expected = ScheduleJsonCodec.decode(fixture("schedule.json"))

        assertEquals(expected, ScheduleJsonCodec.decode(ScheduleJsonCodec.encode(expected)))
    }

    @Test
    fun sharedClassroomFixturesMatchCacheContract() {
        val expected = ClassroomsJsonCodec.decode(fixture("classrooms.json"))
        val actual = SjdClassroomParser.parse(
            payloads = mapOf(
                "01" to JSONObject(fixture("sjd-classrooms-xitucheng.json")),
                "04" to JSONObject(fixture("sjd-classrooms-shahe.json")),
            ),
            targetDate = expected.targetDate,
            fetchedAt = expected.fetchedAt,
        )

        assertEquals(expected, actual)
    }

    @Test
    fun classroomCodecRoundTripsSharedFixture() {
        val expected = ClassroomsJsonCodec.decode(fixture("classrooms.json"))

        assertEquals(expected, ClassroomsJsonCodec.decode(ClassroomsJsonCodec.encode(expected)))
    }

    private fun fixture(name: String): String {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream(name)) {
            "Missing shared fixture: $name"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
