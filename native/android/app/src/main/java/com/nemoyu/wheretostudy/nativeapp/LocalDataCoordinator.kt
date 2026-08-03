package com.nemoyu.wheretostudy.nativeapp

import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

internal class LocalDataInvalidatedException : IllegalStateException(
    "本地数据已清除，本次后台结果未保存。",
)

internal class LocalDataGenerationGate {
    private val generation = AtomicLong(0)
    private val ioLock = ReentrantLock()

    fun snapshot(): Long = generation.get()

    fun isCurrent(expectedGeneration: Long): Boolean = generation.get() == expectedGeneration

    fun <T> withCurrent(
        expectedGeneration: Long,
        operation: () -> T,
    ): T = ioLock.withLock {
        ensureCurrent(expectedGeneration)
        operation().also { ensureCurrent(expectedGeneration) }
    }

    fun <T> clear(operation: () -> T): T {
        generation.incrementAndGet()
        return ioLock.withLock(operation)
    }

    private fun ensureCurrent(expectedGeneration: Long) {
        if (!isCurrent(expectedGeneration)) throw LocalDataInvalidatedException()
    }
}

internal object LocalDataCoordinator {
    private val gate = LocalDataGenerationGate()

    fun snapshot(): Long = gate.snapshot()

    fun isCurrent(expectedGeneration: Long): Boolean = gate.isCurrent(expectedGeneration)

    fun <T> withCurrent(
        expectedGeneration: Long,
        operation: () -> T,
    ): T = gate.withCurrent(expectedGeneration, operation)

    fun <T> clear(operation: () -> T): T = gate.clear(operation)
}
