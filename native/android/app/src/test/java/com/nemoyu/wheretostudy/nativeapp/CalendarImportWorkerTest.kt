package com.nemoyu.wheretostudy.nativeapp

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CalendarImportWorkerTest {
    @Test
    fun closeIsConcurrentSafeAndRejectsNewWork() {
        val worker = CalendarImportWorker()
        val callers = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val finished = CountDownLatch(8)

        try {
            repeat(8) {
                callers.execute {
                    start.await()
                    worker.close()
                    finished.countDown()
                }
            }
            start.countDown()

            assertTrue(finished.await(2, TimeUnit.SECONDS))
            callers.shutdown()
            assertTrue(callers.awaitTermination(2, TimeUnit.SECONDS))
            assertTrue(worker.isShutdown)
            assertFalse(worker.execute { error("closed worker ran a task") })

            worker.close()
            assertTrue(worker.isShutdown)
        } finally {
            start.countDown()
            worker.close()
            callers.shutdownNow()
        }
    }

    @Test
    fun closeAllowsAlreadyAcceptedWorkToFinish() {
        val worker = CalendarImportWorker()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val completed = CountDownLatch(1)

        try {
            assertTrue(worker.execute {
                started.countDown()
                release.await()
                completed.countDown()
            })
            assertTrue(started.await(2, TimeUnit.SECONDS))

            worker.close()
            assertTrue(worker.isShutdown)
            release.countDown()
            assertTrue(completed.await(2, TimeUnit.SECONDS))
        } finally {
            release.countDown()
            worker.close()
        }
    }
}
