package com.nemoyu.wheretostudy.nativeapp

import java.net.SocketTimeoutException
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class DailyClassroomRefreshLogicTest {
    @Test
    fun schedulesTodayAtSevenBeforeSevenInShanghai() {
        val now = shanghaiTime(2026, Calendar.AUGUST, 3, 6, 45)

        assertEquals(
            shanghaiTime(2026, Calendar.AUGUST, 3, 7, 0),
            DailyClassroomRefreshLogic.nextRunAt(now),
        )
    }

    @Test
    fun schedulesTomorrowAtSevenAfterSevenInShanghai() {
        val now = shanghaiTime(2026, Calendar.AUGUST, 3, 7, 1)

        assertEquals(
            shanghaiTime(2026, Calendar.AUGUST, 4, 7, 0),
            DailyClassroomRefreshLogic.nextRunAt(now),
        )
    }

    @Test
    fun exactlySevenSchedulesTheFollowingDay() {
        val now = shanghaiTime(2026, Calendar.AUGUST, 3, 7, 0)

        assertEquals(
            shanghaiTime(2026, Calendar.AUGUST, 4, 7, 0),
            DailyClassroomRefreshLogic.nextRunAt(now),
        )
    }

    @Test
    fun daylightSavingDefaultZoneDoesNotAffectShanghaiSchedule() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            val now = shanghaiTime(2026, Calendar.MARCH, 8, 6, 30)

            assertEquals(
                shanghaiTime(2026, Calendar.MARCH, 8, 7, 0),
                DailyClassroomRefreshLogic.nextRunAt(now),
            )
        } finally {
            TimeZone.setDefault(original)
        }
    }

    @Test
    fun missingCredentialsSkipTheNetworkRequest() {
        listOf(
            null to null,
            "" to "password",
            "   " to "password",
            "account" to null,
            "account" to "",
        ).forEach { (account, password) ->
            assertEquals(
                ClassroomRefreshDecision.SKIP_MISSING_CREDENTIALS,
                DailyClassroomRefreshLogic.refreshDecision(account, password),
            )
        }
        assertEquals(
            ClassroomRefreshDecision.FETCH,
            DailyClassroomRefreshLogic.refreshDecision("account", "password"),
        )
    }

    @Test
    fun retriesOnlyTemporaryRefreshFailures() {
        assertEquals(false, DailyClassroomRefreshLogic.shouldRetry(null))
        assertEquals(
            false,
            DailyClassroomRefreshLogic.shouldRetry(
                ClassroomClientException("missing credentials", retryable = false),
            ),
        )
        assertEquals(
            true,
            DailyClassroomRefreshLogic.shouldRetry(
                ClassroomClientException("temporary provider failure", retryable = true),
            ),
        )
        assertEquals(
            true,
            DailyClassroomRefreshLogic.shouldRetry(SocketTimeoutException("network timeout")),
        )
        assertEquals(
            false,
            DailyClassroomRefreshLogic.shouldRetry(ScheduleClientException("login rejected")),
        )
        assertEquals(
            false,
            DailyClassroomRefreshLogic.shouldRetry(IllegalStateException("unknown failure")),
        )
    }

    @Test
    fun backgroundRefreshRequestsAtMostTwoRetries() {
        assertEquals(true, DailyClassroomRefreshLogic.canRequestRetry(0))
        assertEquals(true, DailyClassroomRefreshLogic.canRequestRetry(1))
        assertEquals(false, DailyClassroomRefreshLogic.canRequestRetry(2))
        assertEquals(false, DailyClassroomRefreshLogic.canRequestRetry(3))
    }

    private fun shanghaiTime(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
    ): Long = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
        clear()
        set(year, month, day, hour, minute, 0)
    }.timeInMillis
}
