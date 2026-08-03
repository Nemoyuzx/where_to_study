package com.nemoyu.wheretostudy.nativeapp

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalDataCoordinatorTest {
    @Test
    fun clearWaitsForAnOlderWriteThenRemovesItsResult() {
        val gate = LocalDataGenerationGate()
        val state = mutableListOf<String>()
        val writeStarted = CountDownLatch(1)
        val releaseWrite = CountDownLatch(1)
        val clearFinished = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        val generation = gate.snapshot()

        val write = executor.submit {
            assertThrows(LocalDataInvalidatedException::class.java) {
                gate.withCurrent(generation) {
                    writeStarted.countDown()
                    assertTrue(releaseWrite.await(2, TimeUnit.SECONDS))
                    state += "stale"
                }
            }
        }
        assertTrue(writeStarted.await(2, TimeUnit.SECONDS))
        val clear = executor.submit {
            gate.clear { state.clear() }
            clearFinished.countDown()
        }
        waitUntil { !gate.isCurrent(generation) }
        assertFalse(clearFinished.await(50, TimeUnit.MILLISECONDS))
        releaseWrite.countDown()

        write.get(2, TimeUnit.SECONDS)
        clear.get(2, TimeUnit.SECONDS)
        assertTrue(state.isEmpty())
        executor.shutdownNow()
    }

    @Test
    fun anOlderWriteCannotStartAfterClearHasClaimedTheGeneration() {
        val gate = LocalDataGenerationGate()
        val state = mutableListOf("cached")
        val clearStarted = CountDownLatch(1)
        val releaseClear = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        val generation = gate.snapshot()

        val clear = executor.submit {
            gate.clear {
                clearStarted.countDown()
                assertTrue(releaseClear.await(2, TimeUnit.SECONDS))
                state.clear()
            }
        }
        assertTrue(clearStarted.await(2, TimeUnit.SECONDS))
        val write = executor.submit {
            assertThrows(LocalDataInvalidatedException::class.java) {
                gate.withCurrent(generation) { state += "stale" }
            }
        }
        releaseClear.countDown()

        clear.get(2, TimeUnit.SECONDS)
        write.get(2, TimeUnit.SECONDS)
        assertEquals(emptyList<String>(), state)
        executor.shutdownNow()
    }

    private fun waitUntil(condition: () -> Boolean) {
        repeat(200) {
            if (condition()) return
            Thread.sleep(5)
        }
        throw AssertionError("condition was not met")
    }
}
