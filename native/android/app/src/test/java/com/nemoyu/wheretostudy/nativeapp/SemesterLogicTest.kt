package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SemesterLogicTest {
    @Test
    fun suggestTermForDatePicksTheSpringSemesterInMarch() {
        val suggested = SemesterLogic.suggestTermForDate(calendarOf(2026, Calendar.MARCH, 15))

        assertEquals("2025-2026-2", suggested.termId)
        assertEquals("2026-03-02", suggested.termStartDate)
    }

    @Test
    fun suggestTermForDatePicksTheFallSemesterInSeptember() {
        val suggested = SemesterLogic.suggestTermForDate(calendarOf(2026, Calendar.SEPTEMBER, 10))

        assertEquals("2026-2027-1", suggested.termId)
        assertEquals("2026-08-31", suggested.termStartDate)
    }

    @Test
    fun suggestTermForDateHandlesSpringAndFallMonthRanges() {
        listOf(
            Calendar.AUGUST,
            Calendar.SEPTEMBER,
            Calendar.OCTOBER,
            Calendar.NOVEMBER,
            Calendar.DECEMBER,
        ).forEach { month ->
            val fall = SemesterLogic.suggestTermForDate(calendarOf(2026, month, 15))
            assertEquals("2026-2027-1", fall.termId)
        }
        listOf(
            Calendar.FEBRUARY,
            Calendar.MARCH,
            Calendar.APRIL,
            Calendar.MAY,
            Calendar.JUNE,
            Calendar.JULY,
        ).forEach { month ->
            val spring = SemesterLogic.suggestTermForDate(calendarOf(2026, month, 15))
            assertEquals("2025-2026-2", spring.termId)
        }
    }

    @Test
    fun januaryRemainsInTheFallTermThatStartedThePreviousYear() {
        val suggested = SemesterLogic.suggestTermForDate(calendarOf(2026, Calendar.JANUARY, 15))

        assertEquals("2025-2026-1", suggested.termId)
        assertEquals("2025-09-01", suggested.termStartDate)
    }

    @Test
    fun springTermAnchorStaysInEarlyMarch() {
        // 2026-03-01 is Sunday; the week of March 2 anchors the start on 03-02.
        val suggested = SemesterLogic.suggestTermForDate(calendarOf(2026, Calendar.MARCH, 1))

        assertEquals("2026-03-02", suggested.termStartDate)
    }

    @Test
    fun isValidTermIdAcceptsStandardIdsAndRejectsGarbage() {
        assertTrue(SemesterLogic.isValidTermId("2025-2026-2"))
        assertTrue(SemesterLogic.isValidTermId("2026-2027-1"))
        assertTrue(SemesterLogic.isValidTermId(" 2025-2026-2 "))
        assertFalse(SemesterLogic.isValidTermId("2025-2026-3"))
        assertFalse(SemesterLogic.isValidTermId("2025-2026"))
        assertFalse(SemesterLogic.isValidTermId("abc"))
        assertFalse(SemesterLogic.isValidTermId(""))
    }

    @Test
    fun isValidTermStartDateRejectsImpossibleDates() {
        assertTrue(SemesterLogic.isValidTermStartDate("2026-03-02"))
        assertTrue(SemesterLogic.isValidTermStartDate(" 2026-03-02 "))
        assertFalse(SemesterLogic.isValidTermStartDate("2026-02-30"))
        assertFalse(SemesterLogic.isValidTermStartDate("2026-13-01"))
        assertFalse(SemesterLogic.isValidTermStartDate("2026-3-2"))
        assertFalse(SemesterLogic.isValidTermStartDate(""))
    }

    @Test
    fun termMatchesCurrentPeriodFlagsMismatchedTerms() {
        val now = calendarOf(2026, Calendar.MARCH, 15)
        val suggested = SemesterLogic.suggestTermForDate(now)

        assertTrue(
            SemesterLogic.termMatchesCurrentPeriod(
                suggested.termId,
                suggested.termStartDate,
                now,
            ),
        )
        assertFalse(
            SemesterLogic.termMatchesCurrentPeriod("1999-2000-1", "2000-09-04", now),
        )
        assertFalse(
            SemesterLogic.termMatchesCurrentPeriod("garbage", "2026-03-02", now),
        )
    }

    private fun calendarOf(year: Int, month: Int, day: Int): Calendar =
        Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
            set(year, month, day, 12, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
}
