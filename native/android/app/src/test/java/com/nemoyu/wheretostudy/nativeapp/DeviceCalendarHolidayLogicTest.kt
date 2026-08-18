package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceCalendarHolidayLogicTest {
    @Test
    fun normalizedNameTrimsAndRejectsEmptyTitles() {
        assertEquals("国庆节", DeviceCalendarHolidayLogic.normalizedName("  国庆节  "))
        assertNull(DeviceCalendarHolidayLogic.normalizedName("   "))
        assertNull(DeviceCalendarHolidayLogic.normalizedName(""))
    }

    @Test
    fun kindFromTitleClassifiesMakeupWorkdays() {
        assertEquals("workday", DeviceCalendarHolidayLogic.kindFromTitle("春节补班"))
        assertEquals("workday", DeviceCalendarHolidayLogic.kindFromTitle("国庆节调休"))
        assertEquals("holiday", DeviceCalendarHolidayLogic.kindFromTitle("端午节"))
        assertEquals("holiday", DeviceCalendarHolidayLogic.kindFromTitle("国庆节"))
    }

    @Test
    fun isHolidayCalendarMatchesKnownTitlesAndKeywordCombinations() {
        assertTrue(DeviceCalendarHolidayLogic.isHolidayCalendar("中国大陆节假日"))
        assertTrue(DeviceCalendarHolidayLogic.isHolidayCalendar("Holidays in China"))
        assertTrue(DeviceCalendarHolidayLogic.isHolidayCalendar("中国节假日"))
        assertFalse(DeviceCalendarHolidayLogic.isHolidayCalendar("Work"))
        assertFalse(DeviceCalendarHolidayLogic.isHolidayCalendar("个人日历"))
    }

    @Test
    fun mergingWorkdaysAddsUniqueWorkdaysAndPreservesSource() {
        val base = HolidaysSnapshot(
            year = 2026,
            source = "device-calendar",
            fetchedAt = "2026-01-01T00:00:00Z",
            items = listOf(HolidayItem(date = "2026-10-01", name = "国庆节", type = "holiday")),
        )
        val workday = HolidayItem(date = "2026-09-20", name = "国庆节补班", type = "workday")
        val merged = DeviceCalendarHolidayLogic.mergingWorkdays(base, listOf(workday, workday))

        assertEquals("device-calendar", merged.source)
        assertEquals(2, merged.items.size)
        assertEquals(1, merged.items.count { it.type == "workday" })

        val noAdditions = DeviceCalendarHolidayLogic.mergingWorkdays(base, emptyList())
        assertEquals(1, noAdditions.items.size)
    }

    @Test
    fun deduplicatedCollapsesTheSameHolidayFromMultipleCalendars() {
        val holiday = HolidayItem(date = "2026-10-01", name = "国庆节", type = "holiday")
        val items = DeviceCalendarHolidayLogic.deduplicated(listOf(holiday, holiday))

        assertEquals(listOf(holiday), items)
    }
}
