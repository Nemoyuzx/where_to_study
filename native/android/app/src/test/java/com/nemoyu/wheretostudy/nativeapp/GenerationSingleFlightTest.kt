package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GenerationSingleFlightTest {
    @Test
    fun joinsTheSameGenerationAndSupersedesAnOlderGeneration() {
        val registry = GenerationSingleFlight<String> { LocalDataInvalidatedException() }
        val firstResults = mutableListOf<Result<String>>()
        val secondResults = mutableListOf<Result<String>>()
        val nextResults = mutableListOf<Result<String>>()

        val owner = registry.join(1, firstResults::add)
        val joiner = registry.join(1, secondResults::add)
        val replacement = registry.join(2, nextResults::add)

        assertTrue(owner.shouldStart)
        assertFalse(joiner.shouldStart)
        assertEquals(owner.token, joiner.token)
        assertTrue(replacement.shouldStart)
        assertTrue(firstResults.single().exceptionOrNull() is LocalDataInvalidatedException)
        assertTrue(secondResults.single().exceptionOrNull() is LocalDataInvalidatedException)

        registry.complete(owner.token, Result.success("stale"))
        assertTrue(nextResults.isEmpty())
        registry.complete(replacement.token, Result.success("fresh"))
        assertEquals("fresh", nextResults.single().getOrThrow())
        assertFalse(registry.isRunning())
    }

    @Test
    fun invalidateReleasesEveryJoinedCompletion() {
        val registry = GenerationSingleFlight<String> { LocalDataInvalidatedException() }
        val results = mutableListOf<Result<String>>()
        registry.join(7, results::add)
        registry.join(7, results::add)

        registry.invalidate()

        assertEquals(2, results.size)
        assertTrue(results.all { it.exceptionOrNull() is LocalDataInvalidatedException })
        assertFalse(registry.isRunning())
    }
}
