package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class DailyCourseSummaryNotificationTest {
    @Test
    fun nextRunUsesShanghaiSevenThirtyWithoutPolling() {
        assertEquals(
            millis(2026, 3, 2, 7, 30),
            DailyCourseSummaryLogic.nextRunAt(millis(2026, 3, 2, 6, 0)),
        )
        assertEquals(
            millis(2026, 3, 3, 7, 30),
            DailyCourseSummaryLogic.nextRunAt(millis(2026, 3, 2, 7, 30)),
        )
    }

    @Test
    fun deliveryWindowAcceptsReasonableDelayAndRejectsSeverelyLateRuns() {
        assertFalse(DailyCourseSummaryLogic.isWithinDeliveryWindow(
            millis(2026, 3, 2, 7, 29),
        ))
        assertTrue(DailyCourseSummaryLogic.isWithinDeliveryWindow(
            millis(2026, 3, 2, 7, 30),
        ))
        assertTrue(DailyCourseSummaryLogic.isWithinDeliveryWindow(
            millis(2026, 3, 2, 8, 0),
        ))
        assertFalse(DailyCourseSummaryLogic.isWithinDeliveryWindow(
            millis(2026, 3, 2, 8, 1),
        ))
        assertEquals(
            millis(2026, 3, 3, 7, 30),
            DailyCourseSummaryLogic.nextRunAt(millis(2026, 3, 2, 12, 0)),
        )
    }

    @Test
    fun draftContainsOnlyCoursesForTheCurrentDay() {
        val draft = DailyCourseSummaryLogic.draft(
            schedule(listOf(course())),
            millis(2026, 3, 2, 7, 30),
        )

        assertEquals("今日课程 · 1 门", draft?.title)
        assertEquals("09:50-10:35 数据挖掘 @ 教二楼-335", draft?.body)
        assertNull(DailyCourseSummaryLogic.draft(
            schedule(listOf(course())),
            millis(2026, 3, 3, 7, 30),
        ))
        assertNull(DailyCourseSummaryLogic.draft(schedule(emptyList()), millis(2026, 3, 2, 7, 30)))
    }

    @Test
    fun legacyExamMetadataDoesNotAlterNotificationCopy() {
        val draft = DailyCourseSummaryLogic.draft(
            schedule(listOf(course(examWeeks = listOf(1)))),
            millis(2026, 3, 2, 7, 30),
        )

        assertEquals("09:50-10:35 数据挖掘 @ 教二楼-335", draft?.body)
    }

    @Test
    fun reconcileFailsClosedAndOnlyReschedulesWithAllRequirements() {
        assertEquals(
            DailyCourseSummaryScheduleAction.CLEAR,
            DailyCourseSummaryReconcileLogic.action(
                enabled = true,
                permissionGranted = false,
                hasCredentials = true,
                hasSchedule = true,
            ),
        )
        assertEquals(
            DailyCourseSummaryScheduleAction.CLEAR,
            DailyCourseSummaryReconcileLogic.action(
                enabled = true,
                permissionGranted = true,
                hasCredentials = false,
                hasSchedule = true,
            ),
        )
        assertEquals(
            DailyCourseSummaryScheduleAction.CLEAR,
            DailyCourseSummaryReconcileLogic.action(
                enabled = false,
                permissionGranted = true,
                hasCredentials = true,
                hasSchedule = true,
            ),
        )
        assertEquals(
            DailyCourseSummaryScheduleAction.RESCHEDULE,
            DailyCourseSummaryReconcileLogic.action(
                enabled = true,
                permissionGranted = true,
                hasCredentials = true,
                hasSchedule = true,
            ),
        )
    }

    @Test
    fun notificationScheduleLoaderRejectsOldAutomaticCacheButKeepsManualCache() {
        val today = Calendar.getInstance(SHANGHAI).apply {
            clear()
            set(2026, Calendar.AUGUST, 24, 12, 0, 0)
        }
        val oldTerm = schedule(listOf(course())).copy(
            termID = "2025-2026-2",
            termStartDate = "2026-03-02",
        )
        val currentTerm = oldTerm.copy(
            termID = "2026-2027-1",
            termStartDate = "2026-09-07",
        )

        assertNull(selectUsableSchedule(oldTerm, automaticTermDetectionEnabled = true, date = today))
        assertEquals(
            currentTerm,
            selectUsableSchedule(currentTerm, automaticTermDetectionEnabled = true, date = today),
        )
        assertEquals(
            oldTerm,
            selectUsableSchedule(oldTerm, automaticTermDetectionEnabled = false, date = today),
        )
        assertNull(
            selectUsableSchedule(
                currentTerm.copy(termStartDate = "2026-02-30"),
                automaticTermDetectionEnabled = true,
                date = today,
            ),
        )
    }

    @Test
    fun revocationInvalidatesConcurrentWorkEvenWhenDataClearFails() {
        val gate = DailyCourseNotificationExecutionGate()
        gate.authorize()
        val capturedRevision = gate.snapshot()
        val started = CountDownLatch(1)
        val continueWork = CountDownLatch(1)
        val delivered = AtomicBoolean(false)
        val worker = Executors.newSingleThreadExecutor()

        val future = worker.submit {
            started.countDown()
            continueWork.await(2, TimeUnit.SECONDS)
            if (gate.isCurrent(capturedRevision)) delivered.set(true)
        }

        assertTrue(started.await(2, TimeUnit.SECONDS))
        gate.revoke()
        val clearFailure = runCatching { error("simulated storage failure") }
        assertTrue(clearFailure.isFailure)
        continueWork.countDown()
        future.get(2, TimeUnit.SECONDS)
        worker.shutdownNow()

        assertFalse(delivered.get())
        assertFalse(gate.isCurrent(capturedRevision))
    }

    @Test
    fun reauthorizationDoesNotMakeAnOlderExecutionCurrentAgain() {
        val gate = DailyCourseNotificationExecutionGate()
        gate.authorize()
        val oldRevision = gate.snapshot()

        gate.revoke()
        gate.authorize()

        assertFalse(gate.isCurrent(oldRevision))
        assertTrue(gate.isCurrent(gate.snapshot()))
    }

    @Test
    fun revocationEstablishesPersistentFallbacksBeforeCancellingRuntime() {
        val operations = mutableListOf<String>()

        val outcome = performDailyCourseNotificationRevocation(
            revokeAuthorization = {
                operations += "authorization"
                error("simulated authorization storage failure")
            },
            disableService = { operations += "service" },
            disablePreference = {
                operations += "preference"
                error("simulated preference storage failure")
            },
            cancelRuntime = { operations += "cancel" },
        )

        assertEquals(
            listOf("authorization", "service", "preference", "cancel"),
            operations,
        )
        assertFalse(outcome.isComplete)
        assertTrue(outcome.isPersistentlyFailClosed)
    }

    @Test
    fun stoppingManagedWorkInterruptsTheActualBackgroundFuture() {
        val controller = CancellableDailyCourseNotificationWork()
        val worker = Executors.newSingleThreadExecutor()
        val started = CountDownLatch(1)
        val interrupted = CountDownLatch(1)

        controller.submit(worker) {
            started.countDown()
            try {
                Thread.sleep(30_000)
            } catch (_: InterruptedException) {
                interrupted.countDown()
                Thread.currentThread().interrupt()
            }
        }

        assertTrue(started.await(2, TimeUnit.SECONDS))
        controller.cancel()
        assertTrue(interrupted.await(2, TimeUnit.SECONDS))
        worker.shutdownNow()
    }

    private fun schedule(courses: List<Course>) = ScheduleSnapshot(
        termID = "fixture-term",
        termStartDate = "2026-03-02",
        fetchedAt = "2026-03-01T12:00:00+08:00",
        courses = courses,
    )

    private fun course(examWeeks: List<Int> = emptyList()) = Course(
        id = "course-1",
        name = "数据挖掘",
        teacher = "测试教师",
        room = "教二楼-335",
        weekText = "1周",
        weekNumbers = listOf(1),
        examWeekNumbers = examWeeks,
        weekday = 1,
        startSlot = 2,
        endSlot = 2,
        sectionText = "第3节",
        timeRange = "09:50-10:35",
    )

    private fun millis(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
    ): Long = Calendar.getInstance(SHANGHAI).apply {
        clear()
        set(year, month - 1, day, hour, minute, 0)
    }.timeInMillis

    private companion object {
        val SHANGHAI: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")
    }
}
