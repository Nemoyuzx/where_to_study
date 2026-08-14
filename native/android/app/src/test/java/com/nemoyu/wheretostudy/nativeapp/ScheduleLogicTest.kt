package com.nemoyu.wheretostudy.nativeapp

import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URI
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
    fun campusBuildingCatalogKeepsEveryOriginalBuildingVisible() {
        assertEquals(listOf("教1", "教2", "教3", "教4", "主楼"), AppMetadata.buildings("01"))
        assertEquals(
            listOf(
                "综合教学楼N",
                "综合教学楼S",
                "教学实验综合楼N",
                "教学实验综合楼S",
                "智慧教学楼",
            ),
            AppMetadata.buildings("04"),
        )
        assertTrue(AppMetadata.buildings("unknown").isEmpty())
    }

    @Test
    fun sjdTransportUsesHttps() {
        assertEquals("https://jwglweixin.bupt.edu.cn", SjdApiClient.ORIGIN)
        assertTrue(SjdApiClient.ORIGIN.startsWith("https://"))
    }

    @Test
    fun sjdRedirectPolicyAllowsOnlySameHttpsOriginAndPort() {
        val current = URI.create("${SjdApiClient.ORIGIN}/bjyddx/login")

        assertEquals(
            URI.create("${SjdApiClient.ORIGIN}/bjyddx/student/curriculum?week=all"),
            SjdRedirectPolicy.resolve(
                current,
                "/bjyddx/student/curriculum?week=all",
                redirectsFollowed = 0,
            ),
        )
        assertEquals(
            URI.create("https://JWGLWEIXIN.BUPT.EDU.CN:443/bjyddx/todayClassrooms?campusId=01"),
            SjdRedirectPolicy.resolve(
                current,
                "https://JWGLWEIXIN.BUPT.EDU.CN:443/bjyddx/todayClassrooms?campusId=01",
                redirectsFollowed = 1,
            ),
        )
    }

    @Test
    fun sjdRedirectPolicyRejectsCrossOriginAndUnsafeTargets() {
        val current = URI.create("${SjdApiClient.ORIGIN}/bjyddx/login")
        listOf(
            "http://jwglweixin.bupt.edu.cn/bjyddx/login",
            "https://example.com/bjyddx/login",
            "https://jwglweixin.bupt.edu.cn.example.com/bjyddx/login",
            "https://jwglweixin.bupt.edu.cn:/bjyddx/login",
            "https://jwglweixin.bupt.edu.cn:444/bjyddx/login",
            "https://user@jwglweixin.bupt.edu.cn/bjyddx/login",
        ).forEach { location ->
            assertSjdError("移动教务拒绝了不安全的重定向。") {
                SjdRedirectPolicy.resolve(current, location, redirectsFollowed = 0)
            }
        }
    }

    @Test
    fun sjdRedirectPolicyRejectsInvalidAndExcessiveRedirects() {
        val current = URI.create("${SjdApiClient.ORIGIN}/bjyddx/login")

        listOf<String?>(null, "", "http://[").forEach { location ->
            assertSjdError("移动教务返回了无效的重定向地址。") {
                SjdRedirectPolicy.resolve(current, location, redirectsFollowed = 0)
            }
        }
        assertSjdError("移动教务重定向次数过多。") {
            SjdRedirectPolicy.resolve(
                current,
                "/bjyddx/login",
                redirectsFollowed = SjdRedirectPolicy.maxRedirects,
            )
        }
    }

    @Test
    fun sjdRedirectPolicyConvertsPostForLegacyAndSeeOtherRedirects() {
        listOf(
            HttpURLConnection.HTTP_MOVED_PERM,
            HttpURLConnection.HTTP_MOVED_TEMP,
            HttpURLConnection.HTTP_SEE_OTHER,
        ).forEach { status ->
            assertEquals(
                SjdRedirectRequest("GET", preserveBody = false),
                SjdRedirectPolicy.followUp(status, "POST"),
            )
        }
    }

    @Test
    fun sjdRedirectPolicyPreservesMethodAndBodyForTemporaryAndPermanentRedirects() {
        listOf(307, 308).forEach { status ->
            assertEquals(
                SjdRedirectRequest("POST", preserveBody = true),
                SjdRedirectPolicy.followUp(status, "POST"),
            )
        }
        assertEquals(
            SjdRedirectRequest("HEAD", preserveBody = true),
            SjdRedirectPolicy.followUp(HttpURLConnection.HTTP_SEE_OTHER, "HEAD"),
        )
        assertEquals(
            SjdRedirectRequest("GET", preserveBody = true),
            SjdRedirectPolicy.followUp(HttpURLConnection.HTTP_MOVED_TEMP, "GET"),
        )
    }

    @Test
    fun sjdResponseReaderAcceptsNormalPayload() {
        val payload = "{\"code\":1,\"message\":\"正常\"}"
        val bytes = payload.toByteArray(Charsets.UTF_8)

        assertEquals(
            payload,
            SjdResponseReader.read(ByteArrayInputStream(bytes), bytes.size.toLong()),
        )
    }

    @Test
    fun sjdResponseReaderRejectsActualBytesBeyondLimit() {
        assertSjdError("移动教务返回的数据超过大小限制。") {
            SjdResponseReader.read(
                ByteArrayInputStream(ByteArray(SjdInputLimits.maxResponseBytes + 1)),
                declaredLength = -1L,
            )
        }
    }

    @Test
    fun sjdResponseReaderRejectsDeclaredLengthBeyondLimit() {
        assertSjdError("移动教务返回的数据超过大小限制。") {
            SjdResponseReader.read(
                ByteArrayInputStream(byteArrayOf()),
                declaredLength = SjdInputLimits.maxResponseBytes + 1L,
            )
        }
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
            payload = JSONObject(fixture("holiday-source.json")),
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
    fun holidayParserRejectsOverlongNames() {
        val overlongName = holidayRecord(
            name = "假".repeat(HolidayInputLimits.maxNameLength + 1),
            date = "2026-01-01",
        )
        assertHolidayError("节假日服务返回的名称超过长度限制。") {
            parseHolidays(JSONArray().put(overlongName))
        }
    }

    @Test
    fun holidayParserRequiresStrictContractDates() {
        listOf("2026-1-01", "2026-02-30").forEach { invalidDate ->
            assertHolidayError("节假日服务返回的日期格式不正确。") {
                parseHolidays(JSONArray().put(holidayRecord("假期", invalidDate)))
            }
        }

    }

    @Test
    fun holidayParserRejectsMismatchedPayloadYearAndRegion() {
        assertHolidayError("节假日数据年份与请求不一致。") {
            parseHolidays(JSONArray(), payloadYear = 2025)
        }
        assertHolidayError("节假日数据区域不正确。") {
            parseHolidays(JSONArray(), region = "JP")
        }
    }

    @Test
    fun holidayParserRejectsItemOutsideRequestedYear() {
        assertHolidayError("节假日数据包含其他年份的日期。") {
            parseHolidays(
            JSONArray().put(
                holidayRecord(
                    name = "跨年假期",
                    date = "2025-12-31",
                ),
            ),
            )
        }
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
        assertEquals(112, CalendarTimelineLogic.axisWidthDp(compact = true))
        assertEquals(
            42,
            CalendarTimelineLogic.axisWidthDp(compact = true, showCourseSlots = false),
        )
        assertEquals(144, CalendarTimelineLogic.axisWidthDp(compact = false))
        assertEquals(96, CalendarTimelineLogic.dayWidthDp(compact = true))
        assertEquals(814, CalendarTimelineLogic.totalHeightDp(compact = true, showDayHeader = false))
        assertEquals(970, CalendarTimelineLogic.totalHeightDp(compact = false, showDayHeader = true))
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

    @Test
    fun phoneCalendarDateCellsStayReadableAcrossSupportedWidths() {
        assertEquals(40, TeachingCalendarLogic.phoneDateCellWidth(320))
        assertEquals(50, TeachingCalendarLogic.phoneDateCellWidth(390))
        assertEquals(63, TeachingCalendarLogic.phoneDateCellWidth(480))
        assertEquals(34, TeachingCalendarLogic.phoneDateCellWidth(320, leadingWidthDp = 42))
        assertEquals(44, TeachingCalendarLogic.phoneDateCellWidth(390, leadingWidthDp = 42))
        assertEquals(57, TeachingCalendarLogic.phoneDateCellWidth(480, leadingWidthDp = 42))
    }

    private fun parseHolidays(
        dates: JSONArray,
        year: Int = 2026,
        payloadYear: Int = year,
        region: String = "CN",
    ): HolidaysSnapshot =
        HolidaySourceParser.parse(
            payload = JSONObject()
                .put("year", payloadYear)
                .put("region", region)
                .put("dates", dates),
            year = year,
            source = HolidayMetadata.source,
            fetchedAt = "2026-01-05T08:00:00+08:00",
        )

    private fun holidayRecord(
        name: String,
        date: String,
        type: String = "public_holiday",
    ): JSONObject = JSONObject()
        .put("name", name)
        .put("date", date)
        .put("type", type)

    private fun assertHolidayError(expectedMessage: String, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue("Expected HolidayClientException, got $error", error is HolidayClientException)
        assertEquals(expectedMessage, error?.message)
    }

    private fun assertSjdError(expectedMessage: String, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue("Expected ScheduleClientException, got $error", error is ScheduleClientException)
        assertEquals(expectedMessage, error?.message)
    }

    private fun fixture(name: String): String {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream(name)) {
            "Missing shared fixture: $name"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
