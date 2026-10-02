package com.nemoyu.wheretostudy.nativeapp

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AuthoritativeShuttleHolidayUiTest {
    @Test
    fun deviceCalendarPreferenceStillUsesPersistedOfficialFutureYearForShuttleWarning() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "authoritative-shuttle-test-${System.nanoTime()}")
        val displayStore = HolidayStore(File(directory, "display"))
        val authoritativeStore = HolidayStore(File(directory, "official"))
        val fetchedAt = "2027-01-01T00:00:00+08:00"
        val device = HolidaysSnapshot(2027, DeviceCalendarHolidayLogic.sourceLabel, fetchedAt,
            listOf(HolidayItem("2027-02-20", "普通节日", "holiday")))
        val official = HolidaysSnapshot(2027, HolidayMetadata.source, fetchedAt,
            listOf(HolidayItem("2027-10-01", "国庆节", "holiday"),
                HolidayItem("2027-10-04", "调休工作日", "workday")))
        try {
            displayStore.save(device)
            val complete = CountDownLatch(1)
            val repository = HolidayRepository(
                context, store = displayStore, authoritativeStore = authoritativeStore,
                fetchAuthoritative = { year ->
                    assertEquals(2027, year)
                    official
                },
            )
            try {
                assertEquals(DeviceCalendarHolidayLogic.sourceLabel, repository.snapshot(2027)?.source)
                repository.addObserver(this) { complete.countDown() }
                repository.ensureAuthoritative(2027)
                assertTrue("Official holiday refresh must finish", complete.await(5, TimeUnit.SECONDS))
                assertTrue(ShuttleBusLogic.isPublicHoliday(
                    repository.authoritativeSnapshot(2027), "2027-10-01"))
                assertFalse(ShuttleBusLogic.isPublicHoliday(
                    repository.authoritativeSnapshot(2027), "2027-02-20"))
            } finally {
                repository.close()
            }
            val reopened = HolidayRepository(
                context, store = displayStore, authoritativeStore = authoritativeStore,
                fetchAuthoritative = { error("Persisted last-good snapshot should not need a network request") },
            )
            try {
                assertEquals(DeviceCalendarHolidayLogic.sourceLabel, reopened.snapshot(2027)?.source)
                assertTrue(ShuttleBusLogic.isPublicHoliday(
                    reopened.authoritativeSnapshot(2027), "2027-10-01"))
            } finally {
                reopened.close()
            }
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun clearedLocalDataCannotBeRepopulatedByAnOlderOfficialHolidayFetch() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "authoritative-shuttle-clear-${System.nanoTime()}")
        val displayStore = HolidayStore(File(directory, "display"))
        val authoritativeStore = HolidayStore(File(directory, "official"))
        val fetchStarted = CountDownLatch(1)
        val releaseFetch = CountDownLatch(1)
        val fetchReturned = CountDownLatch(1)
        val repository = HolidayRepository(
            context, store = displayStore, authoritativeStore = authoritativeStore,
            fetchAuthoritative = { year ->
                fetchStarted.countDown()
                assertTrue(releaseFetch.await(5, TimeUnit.SECONDS))
                fetchReturned.countDown()
                HolidaysSnapshot(year, HolidayMetadata.source, "2027-01-01T00:00:00+08:00",
                    listOf(HolidayItem("2027-10-01", "国庆节", "holiday")))
            },
        )
        try {
            repository.ensureAuthoritative(2027)
            assertTrue(fetchStarted.await(5, TimeUnit.SECONDS))
            repository.clearLocalData()
            releaseFetch.countDown()
            assertTrue(fetchReturned.await(5, TimeUnit.SECONDS))
            android.os.SystemClock.sleep(250)
            assertNull(authoritativeStore.load(2027))
            assertNull(repository.authoritativeSnapshot(2027))
        } finally {
            releaseFetch.countDown()
            repository.close()
            directory.deleteRecursively()
        }
    }
}
