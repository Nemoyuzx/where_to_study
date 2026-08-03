package com.nemoyu.wheretostudy.nativeapp

import java.io.ByteArrayInputStream
import java.util.Calendar
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleLogicTest {
    @Test
    fun sjdTransportUsesHttps() {
        assertEquals("https://jwglweixin.bupt.edu.cn", SjdApiClient.ORIGIN)
        assertTrue(SjdApiClient.ORIGIN.startsWith("https://"))
    }

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
    fun scheduleRoomNormalizationKeepsThreeDigitAndDualDoorRooms() {
        assertEquals("335", SjdScheduleParser.normalizeCourseRoom("3-335"))
        assertEquals("101", SjdScheduleParser.normalizeCourseRoom("教1-101"))
        assertEquals("202-203", SjdScheduleParser.normalizeCourseRoom("202-203"))
        assertEquals("217-218", SjdScheduleParser.normalizeCourseRoom("217-218"))
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

    @Test
    fun sharedHolidayFixtureMatchesContract() {
        val expected = HolidaysJsonCodec.decode(fixture("holidays.json"))
        val actual = HolidaySourceParser.parse(
            payload = JSONArray(fixture("holiday-source.json")),
            year = expected.year,
            source = expected.source,
            fetchedAt = expected.fetchedAt,
        )

        assertEquals(expected, actual)
    }

    @Test
    fun holidayCodecRoundTripsSharedFixture() {
        val expected = HolidaysJsonCodec.decode(fixture("holidays.json"))

        assertEquals(expected, HolidaysJsonCodec.decode(HolidaysJsonCodec.encode(expected)))
    }

    @Test
    fun holidayResponseReaderEnforcesDeclaredAndActualByteLimits() {
        val limit = HolidayInputLimits.maxResponseBytes
        val exactLimit = ByteArray(limit) { 'a'.code.toByte() }

        assertEquals(
            limit,
            HolidayResponseReader.read(ByteArrayInputStream(exactLimit), limit.toLong()).length,
        )
        assertHolidayError("节假日服务返回的数据超过大小限制。") {
            HolidayResponseReader.read(ByteArrayInputStream(byteArrayOf()), (limit + 1L))
        }
        assertHolidayError("节假日服务返回的数据超过大小限制。") {
            HolidayResponseReader.read(ByteArrayInputStream(ByteArray(limit + 1)), -1L)
        }
    }

    @Test
    fun holidayResponseReaderRejectsInvalidUtf8WithLocalizedMessage() {
        assertHolidayError("节假日服务返回的数据编码不正确。") {
            HolidayResponseReader.read(
                ByteArrayInputStream(byteArrayOf(0xC3.toByte(), 0x28)),
                declaredLength = 2L,
            )
        }
    }

    @Test
    fun holidayParserRejectsTooManyRecords() {
        val payload = JSONArray().apply {
            repeat(HolidayInputLimits.maxRecords + 1) { index ->
                put(holidayRecord("假期$index", "2026-01-01"))
            }
        }

        assertHolidayError("节假日服务返回的记录数量超过限制。") {
            parseHolidays(payload)
        }
    }

    @Test
    fun holidayParserRejectsOverlongNamesAndRanges() {
        val overlongName = holidayRecord(
            name = "假".repeat(HolidayInputLimits.maxNameLength + 1),
            start = "2026-01-01",
        )
        assertHolidayError("节假日服务返回的名称超过长度限制。") {
            parseHolidays(JSONArray().put(overlongName))
        }

        val overlongRange = JSONArray().apply {
            repeat(HolidayInputLimits.maxRangeEntries + 1) { put("2026-01-01") }
        }
        assertHolidayError("节假日服务返回的日期范围数量超过限制。") {
            parseHolidays(
                JSONArray().put(
                    JSONObject()
                        .put("name", "假期")
                        .put("range", overlongRange)
                        .put("type", "holiday"),
                ),
            )
        }
    }

    @Test
    fun holidayParserRequiresStrictContractDates() {
        listOf("2026-1-01", "2026-02-30").forEach { invalidDate ->
            assertHolidayError("节假日服务返回的日期格式不正确。") {
                parseHolidays(JSONArray().put(holidayRecord("假期", invalidDate)))
            }
        }

        val invalidMiddleDate = JSONObject()
            .put("name", "假期")
            .put(
                "range",
                JSONArray()
                    .put("2026-01-01")
                    .put("2026-1-02")
                    .put("2026-01-03"),
            )
            .put("type", "holiday")
        assertHolidayError("节假日服务返回的日期格式不正确。") {
            parseHolidays(JSONArray().put(invalidMiddleDate))
        }
    }

    @Test
    fun holidayParserRejectsOversizedSpanAndExpandedResult() {
        val oversizedSpan = holidayRecord(
            name = "超长假期",
            start = "2026-01-01",
            end = "2026-02-02",
        )
        assertHolidayError("节假日服务返回的单条日期跨度超过限制。") {
            parseHolidays(JSONArray().put(oversizedSpan))
        }

        fun expandedPayload(recordCount: Int) = JSONArray().apply {
            repeat(recordCount) { index ->
                put(
                    holidayRecord(
                        name = "假期$index",
                        start = "2026-01-01",
                        end = "2026-02-01",
                    ),
                )
            }
        }

        assertEquals(
            HolidayInputLimits.maxExpandedItems,
            parseHolidays(expandedPayload(recordCount = 16)).items.size,
        )
        assertHolidayError("节假日服务返回的展开记录数量超过限制。") {
            parseHolidays(expandedPayload(recordCount = 17))
        }
    }

    @Test
    fun holidayParserKeepsOnlyRequestedYearAcrossBoundary() {
        val snapshot = parseHolidays(
            JSONArray().put(
                holidayRecord(
                    name = "跨年假期",
                    start = "2025-12-20",
                    end = "2026-01-20",
                ),
            ),
        )

        assertEquals(20, snapshot.items.size)
        assertEquals("2026-01-01", snapshot.items.first().date)
        assertEquals("2026-01-20", snapshot.items.last().date)
        assertTrue(snapshot.items.all { it.date.startsWith("2026-") })
    }

    @Test
    fun holidayFailureCooldownBlocksRetryButAllowsForceAndClearsOnSuccess() {
        var now = 1_000L
        val cooldown = HolidayFailureCooldown(cooldownMillis = 100L) { now }

        assertTrue(cooldown.shouldAttempt(2026, force = false))
        cooldown.recordFailure(2026)
        assertFalse(cooldown.shouldAttempt(2026, force = false))
        assertTrue(cooldown.shouldAttempt(2026, force = true))
        assertTrue(cooldown.shouldAttempt(2027, force = false))

        now += 99L
        assertFalse(cooldown.shouldAttempt(2026, force = false))
        now += 1L
        assertTrue(cooldown.shouldAttempt(2026, force = false))

        cooldown.recordFailure(2026)
        cooldown.recordSuccess(2026)
        assertTrue(cooldown.shouldAttempt(2026, force = false))

        cooldown.recordFailure(2026)
        cooldown.clear()
        assertTrue(cooldown.shouldAttempt(2026, force = false))
    }

    @Test
    fun holidayObserversOnlyNotifyRegisteredPages() {
        val observers = HolidayObserverRegistry()
        val firstOwner = Any()
        val secondOwner = Any()
        var firstCalls = 0
        var secondCalls = 0
        observers.add(firstOwner) { firstCalls += 1 }
        observers.add(secondOwner) { secondCalls += 1 }

        observers.snapshot().forEach { it() }
        observers.remove(firstOwner)
        observers.snapshot().forEach { it() }
        observers.clear()
        observers.snapshot().forEach { it() }

        assertEquals(1, firstCalls)
        assertEquals(2, secondCalls)
    }

    @Test
    fun timelineKeepsHourAndCourseSlotCoordinatesIndependent() {
        assertEquals(0f, CalendarTimelineLogic.position(8 * 60))
        assertEquals(0.5f, CalendarTimelineLogic.position(15 * 60))
        assertEquals(1f, CalendarTimelineLogic.position(22 * 60))
        assertEquals(9 * 60 + 50, CalendarTimelineLogic.minuteOfDay("09:50"))
        assertTrue(CalendarTimelineLogic.hourLabelIsObscured(17 * 60, 16 * 60 + 51))
        assertFalse(CalendarTimelineLogic.hourLabelIsObscured(17 * 60, 16 * 60 + 47))
        assertEquals(236f to 354f, CalendarTimelineLogic.dayColumnBounds(2, 118f, 826f))
    }

    @Test
    fun yearCourseDensityContinuesIncreasingPastFourCourses() {
        val opacities = listOf(1, 4, 5, 8, 12).map(TeachingCalendarLogic::yearCourseOpacity)

        assertEquals(0f, TeachingCalendarLogic.yearCourseOpacity(0))
        assertTrue(opacities.zipWithNext().all { (left, right) -> right > left })
        assertTrue(opacities.all { it in 0f..1f })
    }

    @Test
    fun yearCalendarMapsAdaptiveColumnsAndJuneGridDates() {
        assertEquals(1, YearCalendarLogic.columns(390))
        assertEquals(2, YearCalendarLogic.columns(480))
        assertEquals(3, YearCalendarLogic.columns(700))
        assertEquals(4, YearCalendarLogic.columns(1100))
        assertEquals(1, YearCalendarLogic.dayNumber(2026, 6, 0, 0))
        assertEquals(30, YearCalendarLogic.dayNumber(2026, 6, 4, 1))
        assertEquals(null, YearCalendarLogic.dayNumber(2026, 6, 4, 2))
    }

    private fun parseHolidays(payload: JSONArray, year: Int = 2026): HolidaysSnapshot =
        HolidaySourceParser.parse(
            payload = payload,
            year = year,
            source = HolidayMetadata.source,
            fetchedAt = "2026-01-05T08:00:00+08:00",
        )

    private fun holidayRecord(
        name: String,
        start: String,
        end: String? = null,
        type: String = "holiday",
    ): JSONObject = JSONObject()
        .put("name", name)
        .put("range", JSONArray().put(start).apply { if (end != null) put(end) })
        .put("type", type)

    private fun assertHolidayError(expectedMessage: String, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue("Expected HolidayClientException, got $error", error is HolidayClientException)
        assertEquals(expectedMessage, error?.message)
    }

    private fun fixture(name: String): String {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream(name)) {
            "Missing shared fixture: $name"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
