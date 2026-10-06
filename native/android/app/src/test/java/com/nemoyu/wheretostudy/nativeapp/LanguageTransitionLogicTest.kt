package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.*
import org.junit.Test

class LanguageTransitionLogicTest {
    @Test fun ownWindowBuffersHaveHardPixelAndWorkingByteBounds() {
        listOf(1080 to 2400, 4096 to 8192, Int.MAX_VALUE to Int.MAX_VALUE, 1 to 1).forEach { (width, height) ->
            val (w, h) = LanguageTransitionLogic.bufferSize(width, height)
            assertTrue(w > 0 && h > 0)
            assertTrue(w.toLong() * h <= LanguageTransitionLogic.MAXIMUM_PIXELS)
        }
        assertTrue(LanguageTransitionLogic.MAXIMUM_WORKING_BYTES <= 2 * 1024 * 1024)
    }

    @Test fun legacyPixelsAreReallyBlurredWithoutChangingAUniformImage() {
        val solid = IntArray(81) { 0xff123456.toInt() }
        LanguageTransitionLogic.blur(solid, 9, 9)
        assertTrue(solid.all { it == 0xff123456.toInt() })
        val edge = IntArray(81) { if (it % 9 < 4) 0xff000000.toInt() else 0xffffffff.toInt() }
        LanguageTransitionLogic.blur(edge, 9, 9)
        assertTrue((edge[4 * 9 + 4] and 255) in 1..254)
        assertTrue(edge.all { it ushr 24 == 255 })
        assertThrows(java.util.concurrent.CancellationException::class.java) {
            LanguageTransitionLogic.blur(IntArray(81), 9, 9) { true }
        }
    }

    @Test fun revealRequiresTargetLocaleRestoredViewportAndThreeStablePreDrawFrames() {
        val gate = LanguageLayoutReadiness()
        val bounds = listOf(1080, 2400, 1080, 2200)
        assertFalse(gate.observe(false, true, false, false, bounds))
        assertFalse(gate.observe(true, true, true, false, bounds))
        assertFalse(gate.observe(true, true, false, true, bounds))
        assertFalse(gate.observe(true, true, false, false, bounds))
        assertFalse(gate.observe(true, true, false, false, bounds))
        assertTrue(gate.observe(true, true, false, false, bounds))
        assertFalse(gate.observe(true, true, false, false, listOf(1080, 2200, 1080, 2000)))
        assertFalse(gate.observe(true, false, false, false, bounds))
        gate.reset()
        assertFalse(gate.observe(true, true, false, false, bounds))
    }
}
